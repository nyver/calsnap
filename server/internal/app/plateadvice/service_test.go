package plateadvice_test

import (
	"context"
	"errors"
	"reflect"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"example.com/calsnap/server/internal/app/analysis"
	"example.com/calsnap/server/internal/app/plateadvice"
)

// scriptedAdvisor returns scripted advice or errors, call by call.
type scriptedAdvisor struct {
	calls atomic.Int32
	fn    func(ctx context.Context, call int) (plateadvice.Advice, error)
}

func (s *scriptedAdvisor) Advise(ctx context.Context, _ plateadvice.Input) (plateadvice.Advice, error) {
	return s.fn(ctx, int(s.calls.Add(1)))
}

var good = plateadvice.Advice{
	Summary: "Add a few more vegetables.",
	Suggestions: []plateadvice.Suggestion{
		{Action: plateadvice.ActionAdd, TargetGroup: plateadvice.GroupVegetable, Title: "Add vegetables", Reason: "Vegetables and fruit are low."},
	},
}

// inconsistent is shape-valid but contradicts the balance of request():
// protein is ok, so ADD targeting it must be rejected by CheckConsistency.
var inconsistent = plateadvice.Advice{
	Summary: "Add more protein.",
	Suggestions: []plateadvice.Suggestion{
		{Action: plateadvice.ActionAdd, TargetGroup: plateadvice.GroupProtein, Title: "Add protein", Reason: "More protein never hurts."},
	},
}

type harness struct {
	svc     *plateadvice.Service
	advisor *scriptedAdvisor
	mu      sync.Mutex
	sleeps  []time.Duration
}

func newHarness(t *testing.T, cfg plateadvice.Config, fn func(context.Context, int) (plateadvice.Advice, error)) *harness {
	t.Helper()
	h := &harness{advisor: &scriptedAdvisor{fn: fn}}
	if cfg.CallTimeout == 0 {
		cfg.CallTimeout = time.Second
	}
	if cfg.OverallTimeout == 0 {
		cfg.OverallTimeout = 5 * time.Second
	}
	if cfg.MaxConcurrent == 0 {
		cfg.MaxConcurrent = 4
	}
	if cfg.QueueWait == 0 {
		cfg.QueueWait = 10 * time.Millisecond
	}
	if cfg.ReplayTTL == 0 {
		cfg.ReplayTTL = time.Minute
	}
	if cfg.ReplayMaxEntries == 0 {
		cfg.ReplayMaxEntries = 100
	}
	h.svc = plateadvice.NewService(cfg, plateadvice.Deps{
		Advisor: h.advisor,
		Sleep: func(_ context.Context, d time.Duration) error {
			h.mu.Lock()
			defer h.mu.Unlock()
			h.sleeps = append(h.sleeps, d)
			return nil
		},
		Jitter: func() float64 { return 0.5 },
	})
	return h
}

func request() plateadvice.Request {
	return plateadvice.Request{
		Locale:   analysis.LocaleEN,
		MealType: plateadvice.MealLunch,
		Items: []plateadvice.Item{
			{Name: "rice", WeightG: 150, PlateGroup: plateadvice.GroupComplexCarbohydrate},
		},
		Balance: plateadvice.Balance{
			VegetablesFruit:      plateadvice.StatusLow,
			Protein:              plateadvice.StatusOK,
			ComplexCarbohydrates: plateadvice.StatusOK,
		},
		RequestID:       "req-1",
		ClientRequestID: "req-1",
	}
}

func TestServiceSuccess(t *testing.T) {
	t.Parallel()

	h := newHarness(t, plateadvice.Config{}, func(context.Context, int) (plateadvice.Advice, error) { return good, nil })
	advice, err := h.svc.Advise(context.Background(), request())
	if err != nil {
		t.Fatal(err)
	}
	if advice.Summary != good.Summary || h.advisor.calls.Load() != 1 {
		t.Errorf("advice = %+v, calls = %d", advice, h.advisor.calls.Load())
	}
}

func TestServiceRepairsAnInvalidAnswer(t *testing.T) {
	t.Parallel()

	h := newHarness(t, plateadvice.Config{}, func(_ context.Context, call int) (plateadvice.Advice, error) {
		if call == 1 {
			return plateadvice.Advice{}, analysis.ErrInvalidResponse
		}
		return good, nil
	})
	if _, err := h.svc.Advise(context.Background(), request()); err != nil {
		t.Fatal(err)
	}
	if h.advisor.calls.Load() != 2 {
		t.Errorf("calls = %d, want 2", h.advisor.calls.Load())
	}
}

func TestServiceInvalidTwiceFails(t *testing.T) {
	t.Parallel()

	h := newHarness(t, plateadvice.Config{}, func(context.Context, int) (plateadvice.Advice, error) {
		return plateadvice.Advice{}, analysis.ErrInvalidResponse
	})
	if _, err := h.svc.Advise(context.Background(), request()); !errors.Is(err, analysis.ErrInvalidResponse) {
		t.Errorf("err = %v, want ErrInvalidResponse", err)
	}
	if h.advisor.calls.Load() != 2 {
		t.Errorf("calls = %d, want 2 (one retry)", h.advisor.calls.Load())
	}
}

func TestServiceRetriesAnInconsistentAnswer(t *testing.T) {
	t.Parallel()

	h := newHarness(t, plateadvice.Config{}, func(_ context.Context, call int) (plateadvice.Advice, error) {
		if call == 1 {
			return inconsistent, nil
		}
		return good, nil
	})
	advice, err := h.svc.Advise(context.Background(), request())
	if err != nil {
		t.Fatal(err)
	}
	if advice.Summary != good.Summary || h.advisor.calls.Load() != 2 {
		t.Errorf("advice = %+v, calls = %d", advice, h.advisor.calls.Load())
	}
}

func TestServiceTransientFailuresRetryThenFail(t *testing.T) {
	t.Parallel()

	h := newHarness(t, plateadvice.Config{}, func(_ context.Context, call int) (plateadvice.Advice, error) {
		if call < 3 {
			return plateadvice.Advice{}, analysis.ErrUnavailable
		}
		return good, nil
	})
	if _, err := h.svc.Advise(context.Background(), request()); err != nil {
		t.Fatal(err)
	}
	if want := []time.Duration{500 * time.Millisecond, time.Second}; !reflect.DeepEqual(h.sleeps, want) {
		t.Errorf("sleeps = %v, want %v", h.sleeps, want)
	}

	down := newHarness(t, plateadvice.Config{}, func(context.Context, int) (plateadvice.Advice, error) {
		return plateadvice.Advice{}, analysis.ErrUnavailable
	})
	if _, err := down.svc.Advise(context.Background(), request()); !errors.Is(err, analysis.ErrUnavailable) {
		t.Errorf("err = %v", err)
	}
	if down.advisor.calls.Load() != 3 {
		t.Errorf("calls = %d, want 3 (two retries)", down.advisor.calls.Load())
	}
}

func TestServiceDoesNotRetryRejections(t *testing.T) {
	t.Parallel()

	h := newHarness(t, plateadvice.Config{}, func(context.Context, int) (plateadvice.Advice, error) {
		return plateadvice.Advice{}, analysis.ErrRejected
	})
	if _, err := h.svc.Advise(context.Background(), request()); !errors.Is(err, analysis.ErrRejected) {
		t.Fatalf("err = %v", err)
	}
	if h.advisor.calls.Load() != 1 {
		t.Errorf("calls = %d, want 1", h.advisor.calls.Load())
	}
}

func TestServiceFallsBackAfterExhaustion(t *testing.T) {
	t.Parallel()

	primary := &scriptedAdvisor{fn: func(context.Context, int) (plateadvice.Advice, error) {
		return plateadvice.Advice{}, analysis.ErrUnavailable
	}}
	fallback := &scriptedAdvisor{fn: func(context.Context, int) (plateadvice.Advice, error) { return good, nil }}
	svc := plateadvice.NewService(plateadvice.Config{
		CallTimeout: time.Second, OverallTimeout: 5 * time.Second,
		MaxConcurrent: 4, QueueWait: 10 * time.Millisecond, ReplayTTL: time.Minute, ReplayMaxEntries: 10,
	}, plateadvice.Deps{
		Advisor: primary, AdvisorFallback: fallback,
		Sleep: func(context.Context, time.Duration) error { return nil },
	})

	advice, err := svc.Advise(context.Background(), request())
	if err != nil {
		t.Fatal(err)
	}
	if advice.Summary != good.Summary {
		t.Errorf("advice = %+v", advice)
	}
	if primary.calls.Load() != 3 { // maxTransientRetries=2, so 3 attempts before falling back
		t.Errorf("primary calls = %d, want 3", primary.calls.Load())
	}
	if fallback.calls.Load() != 1 {
		t.Errorf("fallback calls = %d, want 1", fallback.calls.Load())
	}
}

func TestServiceFallsBackAfterRejection(t *testing.T) {
	t.Parallel()

	primary := &scriptedAdvisor{fn: func(context.Context, int) (plateadvice.Advice, error) {
		return plateadvice.Advice{}, analysis.ErrRejected
	}}
	fallback := &scriptedAdvisor{fn: func(context.Context, int) (plateadvice.Advice, error) { return good, nil }}
	svc := plateadvice.NewService(plateadvice.Config{
		CallTimeout: time.Second, OverallTimeout: 5 * time.Second,
		MaxConcurrent: 4, QueueWait: 10 * time.Millisecond, ReplayTTL: time.Minute, ReplayMaxEntries: 10,
	}, plateadvice.Deps{Advisor: primary, AdvisorFallback: fallback})

	advice, err := svc.Advise(context.Background(), request())
	if err != nil {
		t.Fatal(err)
	}
	if advice.Summary != good.Summary {
		t.Errorf("advice = %+v", advice)
	}
	if primary.calls.Load() != 1 {
		t.Errorf("primary calls = %d, want 1", primary.calls.Load())
	}
	if fallback.calls.Load() != 1 {
		t.Errorf("fallback calls = %d, want 1", fallback.calls.Load())
	}
}

func TestServiceFallsBackOnlyOnce(t *testing.T) {
	t.Parallel()

	primary := &scriptedAdvisor{fn: func(context.Context, int) (plateadvice.Advice, error) {
		return plateadvice.Advice{}, analysis.ErrRejected
	}}
	fallback := &scriptedAdvisor{fn: func(context.Context, int) (plateadvice.Advice, error) {
		return plateadvice.Advice{}, analysis.ErrRejected
	}}
	svc := plateadvice.NewService(plateadvice.Config{
		CallTimeout: time.Second, OverallTimeout: 5 * time.Second,
		MaxConcurrent: 4, QueueWait: 10 * time.Millisecond, ReplayTTL: time.Minute, ReplayMaxEntries: 10,
	}, plateadvice.Deps{Advisor: primary, AdvisorFallback: fallback})

	if _, err := svc.Advise(context.Background(), request()); !errors.Is(err, analysis.ErrRejected) {
		t.Fatalf("err = %v", err)
	}
	if primary.calls.Load() != 1 || fallback.calls.Load() != 1 {
		t.Errorf("primary calls = %d, fallback calls = %d, want 1 and 1", primary.calls.Load(), fallback.calls.Load())
	}
}

func TestServiceOverallDeadlineGivesUnavailable(t *testing.T) {
	t.Parallel()

	h := newHarness(t, plateadvice.Config{OverallTimeout: 30 * time.Millisecond, CallTimeout: 5 * time.Second}, func(ctx context.Context, _ int) (plateadvice.Advice, error) {
		<-ctx.Done()
		return plateadvice.Advice{}, analysis.ErrUnavailable
	})
	if _, err := h.svc.Advise(context.Background(), request()); !errors.Is(err, analysis.ErrUnavailable) {
		t.Errorf("err = %v, want ErrUnavailable", err)
	}
}

func TestServicePassesCancellationThrough(t *testing.T) {
	t.Parallel()

	ctx, cancel := context.WithCancel(context.Background())
	h := newHarness(t, plateadvice.Config{}, func(ctx context.Context, _ int) (plateadvice.Advice, error) {
		cancel()
		<-ctx.Done()
		return plateadvice.Advice{}, ctx.Err()
	})
	if _, err := h.svc.Advise(ctx, request()); !errors.Is(err, context.Canceled) {
		t.Errorf("err = %v, want context.Canceled", err)
	}
}

func TestServiceBoundsConcurrency(t *testing.T) {
	t.Parallel()

	started, release := make(chan struct{}), make(chan struct{})
	h := newHarness(t, plateadvice.Config{MaxConcurrent: 1}, func(context.Context, int) (plateadvice.Advice, error) {
		close(started)
		<-release
		return good, nil
	})
	done := make(chan error, 1)
	go func() {
		_, err := h.svc.Advise(context.Background(), request())
		done <- err
	}()
	<-started
	if _, err := h.svc.Advise(context.Background(), request()); !errors.Is(err, analysis.ErrUnavailable) {
		t.Errorf("a busy service must say unavailable, got %v", err)
	}
	close(release)
	if err := <-done; err != nil {
		t.Errorf("first advise: %v", err)
	}
}

func TestServiceReplayHitMakesNoSecondCall(t *testing.T) {
	t.Parallel()

	h := newHarness(t, plateadvice.Config{}, func(context.Context, int) (plateadvice.Advice, error) { return good, nil })
	first, err := h.svc.Advise(context.Background(), request())
	if err != nil {
		t.Fatal(err)
	}
	second, err := h.svc.Advise(context.Background(), request())
	if err != nil {
		t.Fatal(err)
	}
	if h.advisor.calls.Load() != 1 {
		t.Errorf("calls = %d, want 1 (replayed)", h.advisor.calls.Load())
	}
	if second.Summary != first.Summary {
		t.Errorf("replayed advice differs: %+v != %+v", second, first)
	}
}

func TestServiceSameIDDifferentRequestMisses(t *testing.T) {
	t.Parallel()

	h := newHarness(t, plateadvice.Config{}, func(context.Context, int) (plateadvice.Advice, error) { return good, nil })
	if _, err := h.svc.Advise(context.Background(), request()); err != nil {
		t.Fatal(err)
	}
	changed := request()
	changed.Items[0].WeightG = 200
	if _, err := h.svc.Advise(context.Background(), changed); err != nil {
		t.Fatal(err)
	}
	if h.advisor.calls.Load() != 2 {
		t.Errorf("calls = %d, want 2 (no replay across different content)", h.advisor.calls.Load())
	}
}

func TestServiceRequestWithoutClientIDNeverReplays(t *testing.T) {
	t.Parallel()

	h := newHarness(t, plateadvice.Config{}, func(context.Context, int) (plateadvice.Advice, error) { return good, nil })
	req := request()
	req.RequestID, req.ClientRequestID = "generated-1", ""
	if _, err := h.svc.Advise(context.Background(), req); err != nil {
		t.Fatal(err)
	}
	if _, err := h.svc.Advise(context.Background(), req); err != nil {
		t.Fatal(err)
	}
	if h.advisor.calls.Load() != 2 {
		t.Errorf("calls = %d, want 2 (no client id, no replay)", h.advisor.calls.Load())
	}
}
