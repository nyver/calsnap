package analysis

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"log/slog"
	"math/rand/v2"
	"slices"
	"strings"
	"time"

	"golang.org/x/sync/singleflight"
)

// Retry policy towards the AI provider.
const (
	maxTransientRetries = 2
	maxInvalidRetries   = 1
	baseBackoff         = 500 * time.Millisecond
	backoffJitter       = 0.3
	lowConfidenceBelow  = 0.5
	// maxDedupAttempts bounds how often a waiter re-runs the analysis itself when
	// the request it was sharing was cancelled by its owner.
	maxDedupAttempts = 3
)

// Config tunes the use case.
type Config struct {
	// ProviderName labels AI metrics.
	ProviderName     string
	MinConfidence    float64
	CallTimeout      time.Duration
	OverallTimeout   time.Duration
	MaxConcurrent    int
	QueueWait        time.Duration
	ReplayTTL        time.Duration
	ReplayMaxEntries int
}

// Deps are the collaborators of Service. Now, Sleep and Jitter are injectable
// for deterministic tests; nil values select the real implementations.
type Deps struct {
	Vision    FoodVisionProvider
	Nutrition NutritionProvider
	Metrics   Metrics
	Logger    *slog.Logger

	Now    func() time.Time
	Sleep  func(ctx context.Context, d time.Duration) error
	Jitter func() float64 // uniform in [0, 1)
}

// Service is the meal analysis use case.
type Service struct {
	cfg    Config
	d      Deps
	slots  chan struct{}
	replay *replayCache
	group  singleflight.Group
}

// NewService creates the use case. cfg must already be validated.
func NewService(cfg Config, d Deps) *Service {
	if d.Metrics == nil {
		d.Metrics = NopMetrics{}
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

// Analyze recognizes the foods on the photo and resolves their nutrition.
//
// Errors wrap ErrUnavailable, ErrInvalidResponse, ErrRejected or
// ErrMatchFailed, or are the context error when the caller went away.
func (s *Service) Analyze(ctx context.Context, req Request) (Response, error) {
	if req.ClientRequestID == "" {
		return s.run(ctx, req)
	}

	// The image hash is part of the key so that a request id alone can never
	// retrieve somebody else's result.
	h := sha256.New()
	h.Write(req.Image.Data)
	if req.SideImage != nil {
		// A separator keeps "ab"+"c" and "a"+"bc" apart.
		h.Write([]byte{0})
		h.Write(req.SideImage.Data)
	}
	key := req.ClientRequestID + ":" + hex.EncodeToString(h.Sum(nil)[:16])

	if resp, ok := s.replay.get(key); ok {
		return resp, nil
	}
	for attempt := 1; ; attempt++ {
		ch := s.group.DoChan(key, func() (any, error) {
			// A cached result may have been stored between the check above and now.
			if resp, ok := s.replay.get(key); ok {
				return resp, nil
			}
			resp, err := s.run(ctx, req)
			if err != nil {
				return nil, err
			}
			s.replay.put(key, resp)
			return resp, nil
		})
		select {
		case <-ctx.Done():
			return Response{}, ctx.Err()
		case res := <-ch:
			if res.Err != nil {
				// The owner of the shared call went away; run our own attempt.
				if res.Shared && errors.Is(res.Err, context.Canceled) && ctx.Err() == nil && attempt < maxDedupAttempts {
					continue
				}
				return Response{}, res.Err
			}
			return cloneResponse(res.Val.(Response)), nil
		}
	}
}

func (s *Service) run(ctx context.Context, req Request) (Response, error) {
	ctx, cancel := context.WithTimeout(ctx, s.cfg.OverallTimeout)
	defer cancel()

	release, err := s.acquire(ctx)
	if err != nil {
		return Response{}, err
	}
	defer release()

	res, err := s.callProvider(ctx, req)
	if err != nil {
		return Response{}, err
	}
	return s.build(ctx, req, res)
}

// acquire takes one of the global analysis slots, waiting a bounded time.
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
		return nil, fmt.Errorf("%w: all analysis slots are busy", ErrUnavailable)
	}
}

func (s *Service) release() { <-s.slots }

// contextError converts a finished context into the error the caller should see:
// the overall deadline means the provider was too slow (unavailable), while a
// cancellation is passed through.
func (s *Service) contextError(ctx context.Context) error {
	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		return fmt.Errorf("%w: overall analysis deadline exceeded", ErrUnavailable)
	}
	return ctx.Err()
}

func (s *Service) callProvider(ctx context.Context, req Request) (Result, error) {
	rc := RequestContext{
		RequestID:       req.RequestID,
		Locale:          req.Locale,
		PlateDiameterCm: req.PlateDiameterCm,
		SideImage:       req.SideImage,
	}
	log := s.d.Logger.With("request_id", req.RequestID)
	var transient, invalid int

	for {
		callCtx, cancel := context.WithTimeout(ctx, s.cfg.CallTimeout)
		start := s.d.Now()
		res, err := s.d.Vision.Analyze(callCtx, req.Image, rc)
		cancel()
		s.d.Metrics.ObserveAICall(s.cfg.ProviderName, s.d.Now().Sub(start).Seconds())

		if err == nil {
			if verr := Validate(res); verr != nil {
				err = verr
			}
		}
		if err == nil {
			s.d.Metrics.AIUsage(res.Usage.InputTokens, res.Usage.OutputTokens)
			return res, nil
		}
		if ctx.Err() != nil {
			return Result{}, s.contextError(ctx)
		}

		switch {
		case errors.Is(err, ErrInvalidResponse):
			s.d.Metrics.InvalidAIResponse()
			s.d.Metrics.AIError(ErrKindInvalidResponse)
			invalid++
			log.Warn("food vision provider returned an invalid response", "attempt", invalid)
			if invalid > maxInvalidRetries {
				return Result{}, err
			}
		case errors.Is(err, ErrRejected):
			s.d.Metrics.AIError(ErrKindRejected)
			return Result{}, err
		case errors.Is(err, ErrUnavailable), errors.Is(err, context.DeadlineExceeded):
			s.d.Metrics.AIError(ErrKindUnavailable)
			transient++
			log.Warn("food vision provider unavailable", "attempt", transient)
			if transient > maxTransientRetries {
				return Result{}, fmt.Errorf("%w: retries exhausted", ErrUnavailable)
			}
			if serr := s.d.Sleep(ctx, s.backoff(transient)); serr != nil {
				return Result{}, s.contextError(ctx)
			}
		default:
			// Providers must wrap one of the typed errors; anything else is a bug.
			return Result{}, fmt.Errorf("food vision provider: %w", err)
		}
	}
}

// backoff returns 500 ms * 2^(attempt-1) with +-30% jitter.
func (s *Service) backoff(attempt int) time.Duration {
	d := baseBackoff << (attempt - 1)
	factor := 1 + (s.d.Jitter()*2-1)*backoffJitter
	return time.Duration(float64(d) * factor)
}

func (s *Service) build(ctx context.Context, req Request, res Result) (Response, error) {
	kept := make([]RecognizedItem, 0, len(res.Items))
	for _, it := range res.Items {
		if it.Confidence >= s.cfg.MinConfidence {
			kept = append(kept, it)
		}
	}
	dropped := len(res.Items) - len(kept)
	slices.SortStableFunc(kept, func(a, b RecognizedItem) int {
		switch {
		case a.EstimatedWeightG > b.EstimatedWeightG:
			return -1
		case a.EstimatedWeightG < b.EstimatedWeightG:
			return 1
		default:
			return 0
		}
	})

	var estimated, lowConfidence bool
	items := make([]ResponseItem, 0, len(kept))
	for i, it := range kept {
		ri, fromCatalog, err := s.resolve(ctx, req.Locale, it)
		if err != nil {
			return Response{}, err
		}
		if !fromCatalog {
			estimated = true
		}
		if it.Confidence < lowConfidenceBelow {
			lowConfidence = true
		}
		ri.ID = fmt.Sprintf("temp-%d", i+1)
		items = append(items, ri)
	}

	warnings := []string{}
	if len(items) == 0 {
		warnings = append(warnings, WarningNoFoodDetected)
	}
	if dropped > 0 {
		warnings = append(warnings, WarningPartialRecognition)
	}
	if lowConfidence {
		warnings = append(warnings, WarningLowConfidence)
	}
	if estimated {
		warnings = append(warnings, WarningNutritionEstimated)
	}
	return Response{RequestID: req.RequestID, Items: items, Warnings: warnings}, nil
}

// resolve turns a recognized item into a response item: catalog nutrition when
// the pipeline finds a match, otherwise the provider's own estimate.
func (s *Service) resolve(ctx context.Context, locale string, it RecognizedItem) (ResponseItem, bool, error) {
	ri := ResponseItem{
		EstimatedWeightG: it.EstimatedWeightG,
		Confidence:       it.Confidence,
	}
	match, ok, err := s.d.Nutrition.FindFood(ctx, it.Name)
	if err != nil && ctx.Err() != nil {
		return ResponseItem{}, false, s.contextError(ctx)
	}
	if err == nil && ok {
		s.d.Metrics.NutritionMatch(match.Kind)
		ri.Name = match.Food.DisplayName(locale)
		ri.NormalizedName = match.Food.ID
		ri.NutritionSource = SourceCatalog
		ri.Nutrition = match.Food.Nutrition
		return ri, true, nil
	}

	if it.NutritionPer100g == nil {
		s.d.Metrics.NutritionMatchFailed()
		return ResponseItem{}, false, ErrMatchFailed
	}
	s.d.Metrics.NutritionMatch(MatchFallback)
	ri.Name = strings.TrimSpace(it.DisplayName)
	ri.NormalizedName = s.d.Nutrition.Normalize(it.Name)
	if ri.NormalizedName == "" {
		ri.NormalizedName = "unknown_food"
	}
	ri.NutritionSource = SourceAIEstimate
	ri.Nutrition = *it.NutritionPer100g
	return ri, false, nil
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
