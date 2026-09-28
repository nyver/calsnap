package plateadvice

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"math/rand/v2"
	"time"

	"example.com/calsnap/server/internal/app/analysis"
)

// Retry policy towards the AI provider, the same as for meal analysis and
// label reading.
const (
	maxTransientRetries = 2
	maxInvalidRetries   = 1
	baseBackoff         = 500 * time.Millisecond
	backoffJitter       = 0.3
)

// Config tunes the use case.
type Config struct {
	// ProviderName labels AI metrics.
	ProviderName   string
	CallTimeout    time.Duration
	OverallTimeout time.Duration
	MaxConcurrent  int
	QueueWait      time.Duration

	ReplayTTL        time.Duration
	ReplayMaxEntries int
}

// Deps are the collaborators of Service. Now, Sleep and Jitter are injectable
// for deterministic tests; nil values select the real implementations.
type Deps struct {
	Advisor Advisor
	// AdvisorFallback is tried, with its own retry budget, once the primary
	// model is rejected outright or exhausts its own retries. Nil disables
	// the fallback.
	AdvisorFallback Advisor
	Metrics         analysis.Metrics
	Logger          *slog.Logger

	Now    func() time.Time
	Sleep  func(ctx context.Context, d time.Duration) error
	Jitter func() float64 // uniform in [0, 1)
}

// Service is the plate advice use case. It is safe for concurrent use.
//
// NOTE: the retry/fallback loop below is copied from label.Service.Read
// rather than extracted into a shared helper, because extracting one would
// also have to touch internal/app/analysis and internal/app/label, which are
// out of scope for this change and whose tests cannot run reliably on this
// host (see AGENTS.md host constraints). See docs/adr/014-ai-plate-advice.md
// for the follow-up.
type Service struct {
	cfg    Config
	d      Deps
	slots  chan struct{}
	replay *replayCache
}

// NewService creates the use case. cfg must already be validated.
func NewService(cfg Config, d Deps) *Service {
	if d.Metrics == nil {
		d.Metrics = analysis.NopMetrics{}
	}
	if d.Logger == nil {
		d.Logger = slog.New(slog.DiscardHandler)
	}
	if d.Now == nil {
		d.Now = time.Now
	}
	if d.Sleep == nil {
		d.Sleep = sleepCtx
	}
	if d.Jitter == nil {
		d.Jitter = rand.Float64
	}
	return &Service{
		cfg:    cfg,
		d:      d,
		slots:  make(chan struct{}, cfg.MaxConcurrent),
		replay: newReplayCache(cfg.ReplayTTL, cfg.ReplayMaxEntries, d.Now),
	}
}

// Advise asks the configured AI provider for plate advice. req must already
// be validated (see ValidateRequest).
//
// Errors wrap analysis.ErrUnavailable, analysis.ErrInvalidResponse or
// analysis.ErrRejected, or are the context error when the caller went away.
func (s *Service) Advise(ctx context.Context, req Request) (Advice, error) {
	if req.ClientRequestID == "" {
		return s.run(ctx, req)
	}

	key := replayKey(req)
	if advice, ok := s.replay.get(key); ok {
		return advice, nil
	}
	advice, err := s.run(ctx, req)
	if err != nil {
		return Advice{}, err
	}
	s.replay.put(key, advice)
	return advice, nil
}

// replayKey combines the client request id with a hash of the request
// content, so that the same id with different content never replays a stale
// answer (design.md Decision 6).
func replayKey(req Request) string {
	// canonicalRequest carries only the fields that determine the answer:
	// never the request id, which is the other half of the key.
	type canonicalRequest struct {
		Locale   string  `json:"locale"`
		MealType string  `json:"mealType"`
		Items    []Item  `json:"items"`
		Balance  Balance `json:"balance"`
	}
	encoded, _ := json.Marshal(canonicalRequest{Locale: req.Locale, MealType: req.MealType, Items: req.Items, Balance: req.Balance}) //nolint:errcheck // only strings/float64s/enums, always encodable
	sum := sha256.Sum256(encoded)
	return req.ClientRequestID + ":" + hex.EncodeToString(sum[:16])
}

func (s *Service) run(ctx context.Context, req Request) (Advice, error) {
	ctx, cancel := context.WithTimeout(ctx, s.cfg.OverallTimeout)
	defer cancel()

	release, err := s.acquire(ctx)
	if err != nil {
		return Advice{}, err
	}
	defer release()

	in := req.Input()
	log := s.d.Logger.With("request_id", req.RequestID)
	var transient, invalid int
	advisor := s.d.Advisor
	fallbackUsed := false

	// useFallback switches to the fallback model once, giving it its own
	// full retry budget. It reports whether a fallback was available.
	useFallback := func(reason string, err error) bool {
		if fallbackUsed || s.d.AdvisorFallback == nil {
			return false
		}
		fallbackUsed = true
		advisor = s.d.AdvisorFallback
		transient, invalid = 0, 0
		s.d.Metrics.AIFallbackUsed()
		log.Warn("switching to the fallback AI model", "reason", reason, "error", err.Error())
		return true
	}

	for {
		callCtx, callCancel := context.WithTimeout(ctx, s.cfg.CallTimeout)
		start := s.d.Now()
		advice, err := advisor.Advise(callCtx, in)
		callCancel()
		s.d.Metrics.ObserveAICall(s.cfg.ProviderName, s.d.Now().Sub(start).Seconds())

		if err == nil {
			// The advisor already ran ParseAdvice's shape checks; consistency
			// with the local balance is the guarantee this service adds.
			err = CheckConsistency(advice, req.Balance)
		}
		if err == nil {
			s.d.Metrics.AIUsage(advice.Usage.InputTokens, advice.Usage.OutputTokens)
			return advice, nil
		}
		if ctx.Err() != nil {
			return Advice{}, s.contextError(ctx)
		}

		switch {
		case errors.Is(err, analysis.ErrInvalidResponse):
			s.d.Metrics.InvalidAIResponse()
			s.d.Metrics.AIError(analysis.ErrKindInvalidResponse)
			invalid++
			log.Warn("plate advisor returned an invalid response", "attempt", invalid, "error", err.Error())
			if invalid > maxInvalidRetries {
				if useFallback("invalid response", err) {
					continue
				}
				return Advice{}, err
			}
		case errors.Is(err, analysis.ErrRejected):
			s.d.Metrics.AIError(analysis.ErrKindRejected)
			if useFallback("rejected", err) {
				continue
			}
			return Advice{}, err
		case errors.Is(err, analysis.ErrUnavailable), errors.Is(err, context.DeadlineExceeded):
			s.d.Metrics.AIError(analysis.ErrKindUnavailable)
			transient++
			log.Warn("plate advisor unavailable", "attempt", transient, "error", err.Error())
			if transient > maxTransientRetries {
				if useFallback("unavailable", err) {
					continue
				}
				return Advice{}, fmt.Errorf("%w: retries exhausted", analysis.ErrUnavailable)
			}
			if serr := s.d.Sleep(ctx, s.backoff(transient)); serr != nil {
				return Advice{}, s.contextError(ctx)
			}
		default:
			// Providers must wrap one of the typed errors; anything else is a bug.
			return Advice{}, fmt.Errorf("plate advisor: %w", err)
		}
	}
}

// acquire takes one of the plate advice slots, waiting a bounded time.
func (s *Service) acquire(ctx context.Context) (func(), error) {
	select {
	case s.slots <- struct{}{}:
		return s.release, nil
	default:
	}
	waitCtx, cancel := context.WithTimeout(ctx, s.cfg.QueueWait)
	defer cancel()
	select {
	case s.slots <- struct{}{}:
		return s.release, nil
	case <-waitCtx.Done():
		if ctx.Err() != nil {
			return nil, s.contextError(ctx)
		}
		return nil, fmt.Errorf("%w: all plate advice slots are busy", analysis.ErrUnavailable)
	}
}

func (s *Service) release() { <-s.slots }

// contextError converts a finished context into the error the caller should
// see: the overall deadline means the provider was too slow (unavailable),
// while a cancellation is passed through.
func (s *Service) contextError(ctx context.Context) error {
	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		return fmt.Errorf("%w: overall deadline exceeded", analysis.ErrUnavailable)
	}
	return ctx.Err()
}

// backoff returns 500 ms * 2^(attempt-1) with +-30% jitter.
func (s *Service) backoff(attempt int) time.Duration {
	d := baseBackoff << (attempt - 1)
	factor := 1 + (s.d.Jitter()*2-1)*backoffJitter
	return time.Duration(float64(d) * factor)
}

func sleepCtx(ctx context.Context, d time.Duration) error {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-t.C:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}
