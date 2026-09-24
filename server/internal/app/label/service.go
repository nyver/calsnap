package label

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"math/rand/v2"
	"time"

	"example.com/calsnap/server/internal/app/analysis"
)

// Retry policy towards the AI provider, the same as for meal analysis.
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
}

// Deps are the collaborators of Service. Now, Sleep and Jitter are injectable
// for deterministic tests; nil values select the real implementations.
type Deps struct {
	Reader  Reader
	Metrics analysis.Metrics
	Logger  *slog.Logger

	Now    func() time.Time
	Sleep  func(ctx context.Context, d time.Duration) error
	Jitter func() float64 // uniform in [0, 1)
}

// Request is a validated label reading request.
type Request struct {
	Image     analysis.Image
	Locale    string
	RequestID string
}

// Service is the label reading use case. It is safe for concurrent use.
type Service struct {
	cfg   Config
	d     Deps
	slots chan struct{}
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
	return &Service{cfg: cfg, d: d, slots: make(chan struct{}, cfg.MaxConcurrent)}
}

// Read transcribes the table on the photo and normalizes it to 100 g.
//
// Errors wrap analysis.ErrUnavailable, ErrInvalidResponse or ErrRejected, or
// are ErrNotRecognized, or the context error when the caller went away.
func (s *Service) Read(ctx context.Context, req Request) (Result, error) {
	ctx, cancel := context.WithTimeout(ctx, s.cfg.OverallTimeout)
	defer cancel()

	release, err := s.acquire(ctx)
	if err != nil {
		return Result{}, err
	}
	defer release()

	rc := analysis.RequestContext{RequestID: req.RequestID, Locale: req.Locale}
	log := s.d.Logger.With("request_id", req.RequestID)
	var transient, invalid int
	for {
		callCtx, callCancel := context.WithTimeout(ctx, s.cfg.CallTimeout)
		start := s.d.Now()
		ext, err := s.d.Reader.ReadLabel(callCtx, req.Image, rc)
		callCancel()
		s.d.Metrics.ObserveAICall(s.cfg.ProviderName, s.d.Now().Sub(start).Seconds())

		if err == nil {
			if verr := ValidateExtraction(ext); verr != nil {
				err = verr
			}
		}
		var res Result
		if err == nil {
			// Impossible values after the conversion mean a misread table.
			res, err = Normalize(ext)
			if errors.Is(err, ErrNotRecognized) {
				s.d.Metrics.AIUsage(ext.Usage.InputTokens, ext.Usage.OutputTokens)
				return Result{}, err
			}
		}
		if err == nil {
			s.d.Metrics.AIUsage(ext.Usage.InputTokens, ext.Usage.OutputTokens)
			return res, nil
		}
		if ctx.Err() != nil {
			return Result{}, s.contextError(ctx)
		}

		switch {
		case errors.Is(err, analysis.ErrInvalidResponse):
			s.d.Metrics.InvalidAIResponse()
			s.d.Metrics.AIError(analysis.ErrKindInvalidResponse)
			invalid++
			log.Warn("label reader returned an invalid response", "attempt", invalid)
			if invalid > maxInvalidRetries {
				return Result{}, err
			}
		case errors.Is(err, analysis.ErrRejected):
			s.d.Metrics.AIError(analysis.ErrKindRejected)
			return Result{}, err
		case errors.Is(err, analysis.ErrUnavailable), errors.Is(err, context.DeadlineExceeded):
			s.d.Metrics.AIError(analysis.ErrKindUnavailable)
			transient++
			log.Warn("label reader unavailable", "attempt", transient)
			if transient > maxTransientRetries {
				return Result{}, fmt.Errorf("%w: retries exhausted", analysis.ErrUnavailable)
			}
			if serr := s.d.Sleep(ctx, s.backoff(transient)); serr != nil {
				return Result{}, s.contextError(ctx)
			}
		default:
			// Providers must wrap one of the typed errors; anything else is a bug.
			return Result{}, fmt.Errorf("label reader: %w", err)
		}
	}
}

// acquire takes one of the analysis slots, waiting a bounded time.
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
		return nil, fmt.Errorf("%w: all analysis slots are busy", analysis.ErrUnavailable)
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
