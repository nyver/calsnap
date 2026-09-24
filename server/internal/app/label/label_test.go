package label_test

import (
	"context"
	"errors"
	"reflect"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"example.com/calsnap/server/internal/app/analysis"
	"example.com/calsnap/server/internal/app/label"
	"example.com/calsnap/server/internal/testutil"
)

func num(v float64) *float64 { return &v }

func TestParseExtractionFixtures(t *testing.T) {
	t.Parallel()

	for _, name := range []string{"ai-label-per100g.json", "ai-label-per-serving.json", "ai-label-not-found.json", "ai-label-partial.json"} {
		if _, err := label.ParseExtraction(testutil.Fixture(t, name)); err != nil {
			t.Errorf("%s: %v", name, err)
		}
	}
	for _, name := range []string{"ai-label-invalid-basis.json", "ai-label-invalid-negative.json", "ai-label-invalid-unknown-field.json"} {
		if _, err := label.ParseExtraction(testutil.Fixture(t, name)); !errors.Is(err, analysis.ErrInvalidResponse) {
			t.Errorf("%s: err = %v, want ErrInvalidResponse", name, err)
		}
	}
	for name, doc := range map[string]string{
		"malformed":     `{"found": tru`,
		"trailing data": `{"found":false,"confidence":1} {"x":1}`,
		"bad range":     `{"found":true,"basis":"per_100g","protein":5000,"confidence":0.9}`,
		"bad serving":   `{"found":true,"basis":"per_serving","servingSizeG":0,"protein":5,"confidence":0.9}`,
		"bad conf":      `{"found":true,"basis":"per_100g","protein":5,"confidence":2}`,
		"long name":     `{"found":true,"basis":"per_100g","protein":5,"confidence":0.9,"productName":"` + strings.Repeat("x", 101) + `"}`,
	} {
		if _, err := label.ParseExtraction([]byte(doc)); !errors.Is(err, analysis.ErrInvalidResponse) {
			t.Errorf("%s: err = %v, want ErrInvalidResponse", name, err)
		}
	}
}

func TestNormalize(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		in   label.Extraction
		want label.Result
	}{
		{
			name: "a per 100 g table is taken as it is",
			in: label.Extraction{
				Found: true, ProductName: "  Spread\n", Basis: label.BasisPer100g,
				EnergyKcal: num(220), Protein: num(8.4), Fat: num(12.1), Carbohydrates: num(18.2), Confidence: 0.9,
			},
			want: label.Result{Name: "Spread", Nutrition: label.Nutrition{Kcal: num(220), Protein: num(8.4), Fat: num(12.1), Carbs: num(18.2)}},
		},
		{
			name: "a per serving table is converted with the serving size",
			in: label.Extraction{
				Found: true, Basis: label.BasisPerServing, ServingSizeG: num(30),
				EnergyKcal: num(120), Protein: num(3), Fat: num(6), Carbohydrates: num(13.5), Confidence: 0.9,
			},
			want: label.Result{
				ServingSizeG: 30,
				Nutrition:    label.Nutrition{Kcal: num(400), Protein: num(10), Fat: num(20), Carbs: num(45)},
				Warnings:     []string{label.WarningValuesConverted},
			},
		},
		{
			name: "the serving size is kept next to a per 100 g table",
			in: label.Extraction{
				Found: true, Basis: label.BasisPer100g, ServingSizeG: num(25),
				EnergyKcal: num(300), Protein: num(10), Fat: num(10), Carbohydrates: num(40), Confidence: 0.9,
			},
			want: label.Result{ServingSizeG: 25, Nutrition: label.Nutrition{Kcal: num(300), Protein: num(10), Fat: num(10), Carbs: num(40)}},
		},
		{
			name: "kilojoules alone become kcal",
			in:   label.Extraction{Found: true, Basis: label.BasisPer100g, EnergyKJ: num(1000), Protein: num(10), Fat: num(10), Carbohydrates: num(30), Confidence: 0.9},
			want: label.Result{Nutrition: label.Nutrition{Kcal: num(239), Protein: num(10), Fat: num(10), Carbs: num(30)}},
		},
		{
			name: "kcal wins over kilojoules",
			in:   label.Extraction{Found: true, Basis: label.BasisPer100g, EnergyKcal: num(250), EnergyKJ: num(9999), Protein: num(10), Fat: num(10), Carbohydrates: num(30), Confidence: 0.9},
			want: label.Result{Nutrition: label.Nutrition{Kcal: num(250), Protein: num(10), Fat: num(10), Carbs: num(30)}},
		},
		{
			name: "missing energy is computed from complete macros and says so",
			in:   label.Extraction{Found: true, Basis: label.BasisPer100g, Protein: num(10), Fat: num(10), Carbohydrates: num(30), Confidence: 0.9},
			want: label.Result{
				Nutrition: label.Nutrition{Kcal: num(250), Protein: num(10), Fat: num(10), Carbs: num(30)},
				Warnings:  []string{label.WarningEnergyEstimated},
			},
		},
		{
			name: "values the table did not show stay unknown, not zero",
			in:   label.Extraction{Found: true, Basis: label.BasisPer100g, Protein: num(8.4), Fat: num(12.1), Confidence: 0.4},
			want: label.Result{
				Nutrition: label.Nutrition{Protein: num(8.4), Fat: num(12.1)},
				Warnings:  []string{label.WarningLowConfidence},
			},
		},
		{
			name: "a per 100 ml table is used as per 100 g and marked",
			in:   label.Extraction{Found: true, Basis: label.BasisPer100ml, EnergyKcal: num(42), Protein: num(0), Fat: num(0), Carbohydrates: num(10.6), Confidence: 0.9},
			want: label.Result{
				Nutrition: label.Nutrition{Kcal: num(42), Protein: num(0), Fat: num(0), Carbs: num(10.6)},
				Warnings:  []string{label.WarningVolumeBasis},
			},
		},
		{
			name: "an energy far from the macros is flagged for the user",
			in:   label.Extraction{Found: true, Basis: label.BasisPer100g, EnergyKcal: num(500), Protein: num(10), Fat: num(10), Carbohydrates: num(30), Confidence: 0.9},
			want: label.Result{
				Nutrition: label.Nutrition{Kcal: num(500), Protein: num(10), Fat: num(10), Carbs: num(30)},
				Warnings:  []string{label.WarningEnergyMismatch},
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got, err := label.Normalize(tt.in)
			if err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("got %+v\nwant %+v", got, tt.want)
			}
		})
	}
}

func TestNormalizeDeclines(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		in   label.Extraction
		want error
	}{
		{"no table on the photo", label.Extraction{Found: false, Confidence: 0.9}, label.ErrNotRecognized},
		{"a table without any number", label.Extraction{Found: true, Basis: label.BasisPer100g, Confidence: 0.9}, label.ErrNotRecognized},
		{"per serving without a serving size", label.Extraction{Found: true, Basis: label.BasisPerServing, EnergyKcal: num(100), Confidence: 0.9}, label.ErrNotRecognized},
		{
			// 40 g of fat in a 5 g serving is 800 g per 100 g: a misread.
			"impossible values after the conversion",
			label.Extraction{Found: true, Basis: label.BasisPerServing, ServingSizeG: num(5), Fat: num(40), Confidence: 0.9},
			analysis.ErrInvalidResponse,
		},
		{"macros above the physical limit", label.Extraction{Found: true, Basis: label.BasisPer100g, Protein: num(60), Fat: num(50), Confidence: 0.9}, analysis.ErrInvalidResponse},
		{"energy above 900 kcal per 100 g", label.Extraction{Found: true, Basis: label.BasisPer100g, EnergyKcal: num(2100), Confidence: 0.9}, analysis.ErrInvalidResponse},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			if _, err := label.Normalize(tt.in); !errors.Is(err, tt.want) {
				t.Errorf("err = %v, want %v", err, tt.want)
			}
		})
	}
}

// scriptedReader returns scripted extractions or errors, call by call.
type scriptedReader struct {
	calls atomic.Int32
	fn    func(ctx context.Context, call int) (label.Extraction, error)
}

func (s *scriptedReader) ReadLabel(ctx context.Context, _ analysis.Image, _ analysis.RequestContext) (label.Extraction, error) {
	return s.fn(ctx, int(s.calls.Add(1)))
}

var good = label.Extraction{
	Found: true, Basis: label.BasisPer100g,
	EnergyKcal: num(220), Protein: num(8.4), Fat: num(12.1), Carbohydrates: num(18.2), Confidence: 0.9,
}

type harness struct {
	svc    *label.Service
	reader *scriptedReader
	mu     sync.Mutex
	sleeps []time.Duration
}

func newHarness(t *testing.T, cfg label.Config, fn func(context.Context, int) (label.Extraction, error)) *harness {
	t.Helper()
	h := &harness{reader: &scriptedReader{fn: fn}}
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
	h.svc = label.NewService(cfg, label.Deps{
		Reader: h.reader,
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

func request() label.Request {
	return label.Request{Image: analysis.Image{Data: []byte("img"), MIMEType: "image/jpeg", Width: 8, Height: 8}, Locale: "en", RequestID: "req-1"}
}

func TestServiceReadsAndNormalizes(t *testing.T) {
	t.Parallel()

	h := newHarness(t, label.Config{}, func(context.Context, int) (label.Extraction, error) { return good, nil })
	res, err := h.svc.Read(context.Background(), request())
	if err != nil {
		t.Fatal(err)
	}
	if res.Nutrition.Kcal == nil || *res.Nutrition.Kcal != 220 || h.reader.calls.Load() != 1 {
		t.Errorf("res = %+v, calls = %d", res, h.reader.calls.Load())
	}
}

func TestServiceDoesNotRetryAPhotoWithoutATable(t *testing.T) {
	t.Parallel()

	h := newHarness(t, label.Config{}, func(context.Context, int) (label.Extraction, error) {
		return label.Extraction{Found: false, Confidence: 1}, nil
	})
	if _, err := h.svc.Read(context.Background(), request()); !errors.Is(err, label.ErrNotRecognized) {
		t.Fatalf("err = %v", err)
	}
	if h.reader.calls.Load() != 1 {
		t.Errorf("calls = %d, want 1", h.reader.calls.Load())
	}
}

func TestServiceRetriesInvalidAnswersOnce(t *testing.T) {
	t.Parallel()

	h := newHarness(t, label.Config{}, func(_ context.Context, call int) (label.Extraction, error) {
		if call == 1 {
			// A misread that only shows after the conversion.
			return label.Extraction{Found: true, Basis: label.BasisPer100g, EnergyKcal: num(2100), Confidence: 0.9}, nil
		}
		return good, nil
	})
	if _, err := h.svc.Read(context.Background(), request()); err != nil {
		t.Fatal(err)
	}
	if h.reader.calls.Load() != 2 {
		t.Errorf("calls = %d, want 2", h.reader.calls.Load())
	}

	always := newHarness(t, label.Config{}, func(context.Context, int) (label.Extraction, error) {
		return label.Extraction{}, analysis.ErrInvalidResponse
	})
	if _, err := always.svc.Read(context.Background(), request()); !errors.Is(err, analysis.ErrInvalidResponse) {
		t.Errorf("err = %v", err)
	}
	if always.reader.calls.Load() != 2 {
		t.Errorf("calls = %d, want 2 (one retry)", always.reader.calls.Load())
	}
}

func TestServiceRetriesTransientFailuresWithBackoff(t *testing.T) {
	t.Parallel()

	h := newHarness(t, label.Config{}, func(_ context.Context, call int) (label.Extraction, error) {
		if call < 3 {
			return label.Extraction{}, analysis.ErrUnavailable
		}
		return good, nil
	})
	if _, err := h.svc.Read(context.Background(), request()); err != nil {
		t.Fatal(err)
	}
	if want := []time.Duration{500 * time.Millisecond, time.Second}; !reflect.DeepEqual(h.sleeps, want) {
		t.Errorf("sleeps = %v, want %v", h.sleeps, want)
	}

	down := newHarness(t, label.Config{}, func(context.Context, int) (label.Extraction, error) {
		return label.Extraction{}, analysis.ErrUnavailable
	})
	if _, err := down.svc.Read(context.Background(), request()); !errors.Is(err, analysis.ErrUnavailable) {
		t.Errorf("err = %v", err)
	}
	if down.reader.calls.Load() != 3 {
		t.Errorf("calls = %d, want 3 (two retries)", down.reader.calls.Load())
	}
}

func TestServiceDoesNotRetryRejections(t *testing.T) {
	t.Parallel()

	h := newHarness(t, label.Config{}, func(context.Context, int) (label.Extraction, error) {
		return label.Extraction{}, analysis.ErrRejected
	})
	if _, err := h.svc.Read(context.Background(), request()); !errors.Is(err, analysis.ErrRejected) {
		t.Fatalf("err = %v", err)
	}
	if h.reader.calls.Load() != 1 {
		t.Errorf("calls = %d, want 1", h.reader.calls.Load())
	}
}

func TestServiceBoundsConcurrency(t *testing.T) {
	t.Parallel()

	started, release := make(chan struct{}), make(chan struct{})
	h := newHarness(t, label.Config{MaxConcurrent: 1}, func(context.Context, int) (label.Extraction, error) {
		close(started)
		<-release
		return good, nil
	})
	done := make(chan error, 1)
	go func() {
		_, err := h.svc.Read(context.Background(), request())
		done <- err
	}()
	<-started
	if _, err := h.svc.Read(context.Background(), request()); !errors.Is(err, analysis.ErrUnavailable) {
		t.Errorf("a busy service must say unavailable, got %v", err)
	}
	close(release)
	if err := <-done; err != nil {
		t.Errorf("first read: %v", err)
	}
}

func TestServicePassesCancellationThrough(t *testing.T) {
	t.Parallel()

	ctx, cancel := context.WithCancel(context.Background())
	h := newHarness(t, label.Config{}, func(ctx context.Context, _ int) (label.Extraction, error) {
		cancel()
		<-ctx.Done()
		return label.Extraction{}, ctx.Err()
	})
	if _, err := h.svc.Read(ctx, request()); !errors.Is(err, context.Canceled) {
		t.Errorf("err = %v, want context.Canceled", err)
	}
}
