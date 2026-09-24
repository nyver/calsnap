package analysis_test

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"example.com/calsnap/server/internal/app/analysis"
	"example.com/calsnap/server/internal/nutrition"
	"example.com/calsnap/server/internal/testutil"
)

// stubVision returns scripted results; fn receives the 1-based call number.
type stubVision struct {
	calls atomic.Int32
	fn    func(ctx context.Context, call int) (analysis.Result, error)
}

func (s *stubVision) Analyze(ctx context.Context, _ analysis.Image, _ analysis.RequestContext) (analysis.Result, error) {
	return s.fn(ctx, int(s.calls.Add(1)))
}

type recordingMetrics struct {
	mu       sync.Mutex
	aiErrors map[string]int
	invalid  int
	matches  map[string]int
	failed   int
	usage    [2]int
}

func newRecordingMetrics() *recordingMetrics {
	return &recordingMetrics{aiErrors: map[string]int{}, matches: map[string]int{}}
}

func (m *recordingMetrics) ObserveAICall(string, float64) {}
func (m *recordingMetrics) AIError(k string)              { m.lock(func() { m.aiErrors[k]++ }) }
func (m *recordingMetrics) InvalidAIResponse()            { m.lock(func() { m.invalid++ }) }
func (m *recordingMetrics) NutritionMatch(k string)       { m.lock(func() { m.matches[k]++ }) }
func (m *recordingMetrics) NutritionMatchFailed()         { m.lock(func() { m.failed++ }) }
func (m *recordingMetrics) AIUsage(in, out int)           { m.lock(func() { m.usage = [2]int{in, out} }) }
func (m *recordingMetrics) lock(f func())                 { m.mu.Lock(); defer m.mu.Unlock(); f() }

type harness struct {
	svc     *analysis.Service
	vision  *stubVision
	metrics *recordingMetrics
	sleeps  *[]time.Duration
	clock   *fakeClock
}

type fakeClock struct {
	mu sync.Mutex
	t  time.Time
}

func (c *fakeClock) now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.t
}

func (c *fakeClock) advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.t = c.t.Add(d)
}

func newHarness(t *testing.T, mutate func(*analysis.Config), fn func(ctx context.Context, call int) (analysis.Result, error)) *harness {
	t.Helper()
	cat, err := nutrition.LoadEmbedded(0.85)
	if err != nil {
		t.Fatal(err)
	}
	cfg := analysis.Config{
		ProviderName:     "stub",
		MinConfidence:    0.2,
		CallTimeout:      5 * time.Second,
		OverallTimeout:   10 * time.Second,
		MaxConcurrent:    4,
		QueueWait:        20 * time.Millisecond,
		ReplayTTL:        10 * time.Minute,
		ReplayMaxEntries: 100,
	}
	if mutate != nil {
		mutate(&cfg)
	}
	h := &harness{
		vision:  &stubVision{fn: fn},
		metrics: newRecordingMetrics(),
		sleeps:  new([]time.Duration),
		clock:   &fakeClock{t: time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)},
	}
	var sleepMu sync.Mutex
	h.svc = analysis.NewService(cfg, analysis.Deps{
		Vision:    h.vision,
		Nutrition: cat,
		Metrics:   h.metrics,
		Now:       h.clock.now,
		Sleep: func(_ context.Context, d time.Duration) error {
			sleepMu.Lock()
			defer sleepMu.Unlock()
			*h.sleeps = append(*h.sleeps, d)
			return nil
		},
		Jitter: func() float64 { return 0.5 }, // factor 1.0
	})
	return h
}

func fixtureResult(t *testing.T, name string) analysis.Result {
	t.Helper()
	res, err := analysis.ParseResult(testutil.Fixture(t, name))
	if err != nil {
		t.Fatalf("fixture %s: %v", name, err)
	}
	return res
}

func returns(res analysis.Result) func(context.Context, int) (analysis.Result, error) {
	return func(context.Context, int) (analysis.Result, error) { return res, nil }
}

func request(id string) analysis.Request {
	return analysis.Request{
		Image:           analysis.Image{Data: []byte("image-bytes"), MIMEType: "image/jpeg", Width: 10, Height: 10},
		Locale:          "en",
		RequestID:       "req-1",
		ClientRequestID: id,
	}
}

func TestAnalyzeFullFixture(t *testing.T) {
	t.Parallel()

	h := newHarness(t, nil, returns(fixtureResult(t, "ai-result-full.json")))
	req := request("")
	req.Locale = "ru"
	resp, err := h.svc.Analyze(context.Background(), req)
	if err != nil {
		t.Fatal(err)
	}
	if len(resp.Warnings) != 0 || len(resp.Items) != 4 {
		t.Fatalf("resp = %+v", resp)
	}
	wantOrder := []struct{ id, name, norm string }{
		{"temp-1", "Рис", "rice"},
		{"temp-2", "Куриная грудка", "chicken_breast"},
		{"temp-3", "Огурец", "cucumber"},
		{"temp-4", "Помидор", "tomato"},
	}
	for i, w := range wantOrder {
		it := resp.Items[i]
		if it.ID != w.id || it.Name != w.name || it.NormalizedName != w.norm || it.NutritionSource != analysis.SourceCatalog {
			t.Errorf("item %d = %+v, want %+v", i, it, w)
		}
	}
	if h.metrics.matches[analysis.MatchAlias] != 1 || h.metrics.matches[analysis.MatchExact] != 3 {
		t.Errorf("match metrics = %v", h.metrics.matches)
	}
}

func TestAnalyzePartialAndLowConfidence(t *testing.T) {
	t.Parallel()

	h := newHarness(t, nil, returns(fixtureResult(t, "ai-result-partial.json")))
	resp, err := h.svc.Analyze(context.Background(), request(""))
	if err != nil {
		t.Fatal(err)
	}
	if len(resp.Items) != 2 {
		t.Fatalf("items = %d, want 2 (one dropped)", len(resp.Items))
	}
	want := []string{analysis.WarningPartialRecognition, analysis.WarningLowConfidence}
	if fmt.Sprint(resp.Warnings) != fmt.Sprint(want) {
		t.Errorf("warnings = %v, want %v", resp.Warnings, want)
	}
}

func TestAnalyzeConfidenceFilteringScenarios(t *testing.T) {
	t.Parallel()

	item := func(name string, w, conf float64) analysis.RecognizedItem {
		return analysis.RecognizedItem{
			Name: name, DisplayName: name, EstimatedWeightG: w, Confidence: conf,
			NutritionPer100g: &analysis.Nutrition{Kcal: 100},
		}
	}
	tests := []struct {
		name      string
		items     []analysis.RecognizedItem
		wantItems int
		warnings  []string
	}{
		{"uncertain item dropped", []analysis.RecognizedItem{item("a", 10, 0.9), item("b", 20, 0.6), item("c", 30, 0.1)}, 2, []string{analysis.WarningPartialRecognition, analysis.WarningNutritionEstimated}},
		{"low confidence kept", []analysis.RecognizedItem{item("a", 10, 0.35)}, 1, []string{analysis.WarningLowConfidence, analysis.WarningNutritionEstimated}},
		{"exactly minimum kept", []analysis.RecognizedItem{item("a", 10, 0.2)}, 1, []string{analysis.WarningLowConfidence, analysis.WarningNutritionEstimated}},
		{"all dropped", []analysis.RecognizedItem{item("a", 10, 0.1)}, 0, []string{analysis.WarningNoFoodDetected, analysis.WarningPartialRecognition}},
		{"no items", []analysis.RecognizedItem{}, 0, []string{analysis.WarningNoFoodDetected}},
		{"confident item only", []analysis.RecognizedItem{item("a", 10, 0.5)}, 1, []string{analysis.WarningNutritionEstimated}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			h := newHarness(t, nil, returns(analysis.Result{Items: tt.items}))
			resp, err := h.svc.Analyze(context.Background(), request(""))
			if err != nil {
				t.Fatal(err)
			}
			if len(resp.Items) != tt.wantItems {
				t.Errorf("items = %d, want %d", len(resp.Items), tt.wantItems)
			}
			if fmt.Sprint(resp.Warnings) != fmt.Sprint(tt.warnings) {
				t.Errorf("warnings = %v, want %v", resp.Warnings, tt.warnings)
			}
		})
	}
}

func TestAnalyzeEstimatedNutritionFallback(t *testing.T) {
	t.Parallel()

	h := newHarness(t, nil, returns(fixtureResult(t, "ai-result-estimated.json")))
	resp, err := h.svc.Analyze(context.Background(), request(""))
	if err != nil {
		t.Fatal(err)
	}
	if len(resp.Items) != 2 || fmt.Sprint(resp.Warnings) != "[NUTRITION_ESTIMATED]" {
		t.Fatalf("resp = %+v", resp)
	}
	first := resp.Items[0]
	if first.NutritionSource != analysis.SourceAIEstimate || first.NormalizedName != "grandmas_special_casserole" ||
		first.Name != "Grandma's special casserole" || first.Nutrition.Kcal != 180 {
		t.Errorf("fallback item = %+v", first)
	}
	if h.metrics.matches[analysis.MatchFallback] != 1 {
		t.Errorf("fallback metric = %v", h.metrics.matches)
	}
}

func TestAnalyzeMatchFailedWithoutAnyProfile(t *testing.T) {
	t.Parallel()

	h := newHarness(t, nil, returns(fixtureResult(t, "ai-result-missing-nutrition.json")))
	_, err := h.svc.Analyze(context.Background(), request(""))
	if !errors.Is(err, analysis.ErrMatchFailed) {
		t.Fatalf("err = %v, want ErrMatchFailed", err)
	}
	if h.metrics.failed != 1 {
		t.Errorf("match-failed metric = %d", h.metrics.failed)
	}
}

func TestAnalyzeNoFood(t *testing.T) {
	t.Parallel()

	h := newHarness(t, nil, returns(fixtureResult(t, "ai-result-no-food.json")))
	resp, err := h.svc.Analyze(context.Background(), request(""))
	if err != nil {
		t.Fatal(err)
	}
	if len(resp.Items) != 0 || fmt.Sprint(resp.Warnings) != "[NO_FOOD_DETECTED]" {
		t.Errorf("resp = %+v", resp)
	}
}

func TestAnalyzeRecordsUsage(t *testing.T) {
	t.Parallel()

	res := fixtureResult(t, "ai-result-no-food.json")
	res.Usage = analysis.Usage{InputTokens: 1200, OutputTokens: 80}
	h := newHarness(t, nil, returns(res))
	if _, err := h.svc.Analyze(context.Background(), request("")); err != nil {
		t.Fatal(err)
	}
	if h.metrics.usage != [2]int{1200, 80} {
		t.Errorf("usage = %v", h.metrics.usage)
	}
}

func TestRetryPolicy(t *testing.T) {
	t.Parallel()

	valid := fixtureResult(t, "ai-result-no-food.json")
	unavailable := fmt.Errorf("http 503: %w", analysis.ErrUnavailable)
	invalid := fmt.Errorf("prose: %w", analysis.ErrInvalidResponse)
	negative := fixtureResult(t, "ai-result-full.json")
	negative.Items[0].EstimatedWeightG = -50

	tests := []struct {
		name       string
		script     []error // nil entry = success; results[i] used when non-nil
		results    map[int]analysis.Result
		wantErr    error
		wantCalls  int32
		wantSleeps []time.Duration
	}{
		{"recover from one 503", []error{unavailable, nil}, nil, nil, 2, []time.Duration{500 * time.Millisecond}},
		{"two transient failures then success", []error{unavailable, unavailable, nil}, nil, nil, 3, []time.Duration{500 * time.Millisecond, time.Second}},
		{"transient retries exhausted", []error{unavailable, unavailable, unavailable, nil}, nil, analysis.ErrUnavailable, 3, []time.Duration{500 * time.Millisecond, time.Second}},
		{"invalid then valid", []error{invalid, nil}, nil, nil, 2, nil},
		{"invalid twice", []error{invalid, invalid, nil}, nil, analysis.ErrInvalidResponse, 2, nil},
		{"rejected is not retried", []error{fmt.Errorf("http 400: %w", analysis.ErrRejected), nil}, nil, analysis.ErrRejected, 1, nil},
		{"unknown error is not retried", []error{errors.New("boom"), nil}, nil, errors.New("boom"), 1, nil},
		{"negative weight then valid", []error{nil, nil}, map[int]analysis.Result{1: negative}, nil, 2, nil},
		{"negative weight twice", []error{nil, nil, nil}, map[int]analysis.Result{1: negative, 2: negative}, analysis.ErrInvalidResponse, 2, nil},
		{"mixed failures", []error{unavailable, invalid, nil}, nil, nil, 3, []time.Duration{500 * time.Millisecond}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			h := newHarness(t, nil, func(_ context.Context, call int) (analysis.Result, error) {
				if call > len(tt.script) {
					return analysis.Result{}, errors.New("script exhausted")
				}
				if err := tt.script[call-1]; err != nil {
					return analysis.Result{}, err
				}
				if r, ok := tt.results[call]; ok {
					return r, nil
				}
				return valid, nil
			})
			_, err := h.svc.Analyze(context.Background(), request(""))
			switch {
			case tt.wantErr == nil && err != nil:
				t.Fatalf("unexpected error: %v", err)
			case tt.wantErr != nil && err == nil:
				t.Fatalf("expected error %v", tt.wantErr)
			case tt.wantErr != nil && errors.Is(tt.wantErr, analysis.ErrUnavailable) != errors.Is(err, analysis.ErrUnavailable):
				t.Fatalf("err = %v, want %v", err, tt.wantErr)
			case tt.wantErr != nil && errors.Is(tt.wantErr, analysis.ErrInvalidResponse) != errors.Is(err, analysis.ErrInvalidResponse):
				t.Fatalf("err = %v, want %v", err, tt.wantErr)
			}
			if got := h.vision.calls.Load(); got != tt.wantCalls {
				t.Errorf("provider calls = %d, want %d", got, tt.wantCalls)
			}
			if fmt.Sprint(*h.sleeps) != fmt.Sprint(tt.wantSleeps) {
				t.Errorf("sleeps = %v, want %v", *h.sleeps, tt.wantSleeps)
			}
		})
	}
}

func TestBackoffJitterBounds(t *testing.T) {
	t.Parallel()

	for _, tc := range []struct {
		jitter float64
		want   time.Duration
	}{{0, 350 * time.Millisecond}, {0.5, 500 * time.Millisecond}, {1, 650 * time.Millisecond}} {
		cat, _ := nutrition.LoadEmbedded(0.85)
		var slept []time.Duration
		vision := &stubVision{fn: func(_ context.Context, call int) (analysis.Result, error) {
			if call == 1 {
				return analysis.Result{}, analysis.ErrUnavailable
			}
			return analysis.Result{Items: []analysis.RecognizedItem{}}, nil
		}}
		svc := analysis.NewService(analysis.Config{
			MinConfidence: 0.2, CallTimeout: time.Second, OverallTimeout: time.Minute, MaxConcurrent: 1,
			QueueWait: time.Millisecond, ReplayTTL: time.Minute, ReplayMaxEntries: 1,
		}, analysis.Deps{
			Vision: vision, Nutrition: cat,
			Sleep:  func(_ context.Context, d time.Duration) error { slept = append(slept, d); return nil },
			Jitter: func() float64 { return tc.jitter },
		})
		if _, err := svc.Analyze(context.Background(), request("")); err != nil {
			t.Fatal(err)
		}
		if len(slept) != 1 || slept[0] != tc.want {
			t.Errorf("jitter %v: slept %v, want %v", tc.jitter, slept, tc.want)
		}
	}
}

func TestClientCancellationStopsProviderAndRetries(t *testing.T) {
	t.Parallel()

	started := make(chan struct{})
	h := newHarness(t, nil, func(ctx context.Context, _ int) (analysis.Result, error) {
		close(started)
		<-ctx.Done()
		return analysis.Result{}, fmt.Errorf("call aborted: %w", analysis.ErrUnavailable)
	})
	ctx, cancel := context.WithCancel(context.Background())
	errCh := make(chan error, 1)
	go func() {
		_, err := h.svc.Analyze(ctx, request(""))
		errCh <- err
	}()
	<-started
	cancel()
	err := <-errCh
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("err = %v, want context.Canceled", err)
	}
	if got := h.vision.calls.Load(); got != 1 {
		t.Errorf("provider calls = %d, want 1 (no retry after cancellation)", got)
	}
	if len(*h.sleeps) != 0 {
		t.Errorf("unexpected backoff sleeps: %v", *h.sleeps)
	}
}

func TestOverallDeadlineYieldsUnavailable(t *testing.T) {
	t.Parallel()

	h := newHarness(t, func(c *analysis.Config) {
		c.OverallTimeout = 30 * time.Millisecond
		c.CallTimeout = 30 * time.Millisecond
	}, func(ctx context.Context, _ int) (analysis.Result, error) {
		<-ctx.Done()
		return analysis.Result{}, ctx.Err()
	})
	_, err := h.svc.Analyze(context.Background(), request(""))
	if !errors.Is(err, analysis.ErrUnavailable) {
		t.Fatalf("err = %v, want ErrUnavailable", err)
	}
}

func TestPerCallTimeoutIsRetried(t *testing.T) {
	t.Parallel()

	h := newHarness(t, func(c *analysis.Config) { c.CallTimeout = 20 * time.Millisecond }, func(ctx context.Context, call int) (analysis.Result, error) {
		if call == 1 {
			<-ctx.Done()
			return analysis.Result{}, ctx.Err()
		}
		return analysis.Result{Items: []analysis.RecognizedItem{}}, nil
	})
	if _, err := h.svc.Analyze(context.Background(), request("")); err != nil {
		t.Fatalf("err = %v", err)
	}
	if got := h.vision.calls.Load(); got != 2 {
		t.Errorf("provider calls = %d, want 2", got)
	}
	if h.metrics.aiErrors[analysis.ErrKindUnavailable] != 1 {
		t.Errorf("ai errors = %v", h.metrics.aiErrors)
	}
}

func TestConcurrencyCapWithBoundedQueue(t *testing.T) {
	t.Parallel()

	gate := make(chan struct{})
	entered := make(chan struct{}, 4)
	h := newHarness(t, func(c *analysis.Config) {
		c.MaxConcurrent = 1
		c.QueueWait = 10 * time.Millisecond
	}, func(ctx context.Context, _ int) (analysis.Result, error) {
		entered <- struct{}{}
		select {
		case <-gate:
		case <-ctx.Done():
		}
		return analysis.Result{Items: []analysis.RecognizedItem{}}, nil
	})
	first := make(chan error, 1)
	go func() {
		_, err := h.svc.Analyze(context.Background(), request(""))
		first <- err
	}()
	<-entered

	_, err := h.svc.Analyze(context.Background(), request(""))
	if !errors.Is(err, analysis.ErrUnavailable) {
		t.Fatalf("saturated err = %v, want ErrUnavailable", err)
	}

	close(gate)
	if err := <-first; err != nil {
		t.Fatalf("first request: %v", err)
	}
	if _, err := h.svc.Analyze(context.Background(), request("")); err != nil {
		t.Fatalf("request after release: %v", err)
	}
}

func TestReplayServesRetryWithoutSecondAICall(t *testing.T) {
	t.Parallel()

	h := newHarness(t, nil, returns(fixtureResult(t, "ai-result-full.json")))
	first, err := h.svc.Analyze(context.Background(), request("0190f7a2-1b2c"))
	if err != nil {
		t.Fatal(err)
	}
	h.clock.advance(30 * time.Second)
	second, err := h.svc.Analyze(context.Background(), request("0190f7a2-1b2c"))
	if err != nil {
		t.Fatal(err)
	}
	if got := h.vision.calls.Load(); got != 1 {
		t.Fatalf("provider calls = %d, want 1", got)
	}
	if fmt.Sprint(first) != fmt.Sprint(second) {
		t.Errorf("replayed response differs:\n%+v\n%+v", first, second)
	}

	// Mutating a returned response must not corrupt the cache.
	second.Items[0].Name = "tampered"
	third, _ := h.svc.Analyze(context.Background(), request("0190f7a2-1b2c"))
	if third.Items[0].Name == "tampered" {
		t.Error("replay cache shares memory with callers")
	}

	h.clock.advance(11 * time.Minute)
	if _, err := h.svc.Analyze(context.Background(), request("0190f7a2-1b2c")); err != nil {
		t.Fatal(err)
	}
	if got := h.vision.calls.Load(); got != 2 {
		t.Errorf("provider calls after TTL = %d, want 2", got)
	}
}

func TestFailuresAreNotCached(t *testing.T) {
	t.Parallel()

	h := newHarness(t, nil, func(_ context.Context, call int) (analysis.Result, error) {
		if call <= 3 {
			return analysis.Result{}, analysis.ErrUnavailable
		}
		return analysis.Result{Items: []analysis.RecognizedItem{}}, nil
	})
	if _, err := h.svc.Analyze(context.Background(), request("client-id-1")); !errors.Is(err, analysis.ErrUnavailable) {
		t.Fatalf("first err = %v", err)
	}
	if _, err := h.svc.Analyze(context.Background(), request("client-id-1")); err != nil {
		t.Fatalf("retry with same id must trigger a new attempt: %v", err)
	}
	if got := h.vision.calls.Load(); got != 4 {
		t.Errorf("provider calls = %d, want 4", got)
	}
}

func TestSameIDWithDifferentImageIsNotShared(t *testing.T) {
	t.Parallel()

	h := newHarness(t, nil, returns(analysis.Result{Items: []analysis.RecognizedItem{}}))
	a := request("shared-id-1")
	b := request("shared-id-1")
	b.Image.Data = []byte("another image")
	for _, r := range []analysis.Request{a, b} {
		if _, err := h.svc.Analyze(context.Background(), r); err != nil {
			t.Fatal(err)
		}
	}
	if got := h.vision.calls.Load(); got != 2 {
		t.Errorf("provider calls = %d, want 2", got)
	}
}

func TestConcurrentDuplicatesShareOneAnalysis(t *testing.T) {
	t.Parallel()

	gate := make(chan struct{})
	entered := make(chan struct{}, 32)
	h := newHarness(t, nil, func(ctx context.Context, _ int) (analysis.Result, error) {
		entered <- struct{}{}
		select {
		case <-gate:
		case <-ctx.Done():
		}
		return analysis.Result{Items: []analysis.RecognizedItem{}}, nil
	})
	const n = 8
	var wg sync.WaitGroup
	errs := make(chan error, n)
	for range n {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := h.svc.Analyze(context.Background(), request("dup-id-1234"))
			errs <- err
		}()
	}
	<-entered
	close(gate)
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Errorf("waiter error: %v", err)
		}
	}
	if got := h.vision.calls.Load(); got != 1 {
		t.Errorf("provider calls = %d, want 1", got)
	}
}

func TestWaiterRunsOwnAttemptWhenOwnerIsCancelled(t *testing.T) {
	t.Parallel()

	entered := make(chan struct{}, 4)
	h := newHarness(t, nil, func(ctx context.Context, call int) (analysis.Result, error) {
		if call == 1 {
			entered <- struct{}{}
			<-ctx.Done()
			return analysis.Result{}, ctx.Err()
		}
		return analysis.Result{Items: []analysis.RecognizedItem{}}, nil
	})
	ownerCtx, cancelOwner := context.WithCancel(context.Background())
	ownerErr := make(chan error, 1)
	go func() {
		_, err := h.svc.Analyze(ownerCtx, request("owner-id-123"))
		ownerErr <- err
	}()
	<-entered

	waiterErr := make(chan error, 1)
	go func() {
		_, err := h.svc.Analyze(context.Background(), request("owner-id-123"))
		waiterErr <- err
	}()
	cancelOwner()

	if err := <-ownerErr; !errors.Is(err, context.Canceled) {
		t.Errorf("owner err = %v, want context.Canceled", err)
	}
	if err := <-waiterErr; err != nil {
		t.Errorf("waiter must succeed with its own attempt: %v", err)
	}
}
