package product_test

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"example.com/calsnap/server/internal/app/product"
)

func TestNormalizeBarcode(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		in   string
		want string
		ok   bool
	}{
		{"EAN-13", "4006381333931", "4006381333931", true},
		{"EAN-13 with spaces", " 4006381333931 ", "4006381333931", true},
		{"EAN-8", "96385074", "96385074", true},
		{"UPC-A becomes EAN-13", "036000291452", "0036000291452", true},
		{"GTIN-14", "10012345678902", "10012345678902", true},
		{"wrong check digit", "4006381333932", "", false},
		{"too short", "1234567", "", false},
		{"nine digits", "123456789", "", false},
		{"too long", "123456789012345", "", false},
		{"letters", "40063813339A1", "", false},
		{"with a dash", "4006381-33931", "", false},
		{"empty", "", "", false},
		{"unicode digits", "٤٠٠٦٣٨١٣٣٣٩٣١", "", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got, err := product.NormalizeBarcode(tt.in)
			if tt.ok != (err == nil) || got != tt.want {
				t.Errorf("NormalizeBarcode(%q) = %q, %v; want %q, ok=%v", tt.in, got, err, tt.want, tt.ok)
			}
			if !tt.ok && !errors.Is(err, product.ErrInvalidBarcode) {
				t.Errorf("error = %v, want ErrInvalidBarcode", err)
			}
		})
	}
}

// fakeSource counts calls and answers with a scripted result.
type fakeSource struct {
	mu    sync.Mutex
	calls int
	last  struct{ barcode, locale string }
	fn    func(call int) (product.Product, error)
}

func (s *fakeSource) Lookup(_ context.Context, barcode, locale string) (product.Product, error) {
	s.mu.Lock()
	s.calls++
	call := s.calls
	s.last.barcode, s.last.locale = barcode, locale
	s.mu.Unlock()
	return s.fn(call)
}

func (s *fakeSource) count() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.calls
}

type clock struct{ now time.Time }

func (c *clock) Now() time.Time          { return c.now }
func (c *clock) advance(d time.Duration) { c.now = c.now.Add(d) }

var yogurt = product.Product{
	Barcode: "4006381333931", Name: "Yogurt", Brand: "Danone", ServingSizeG: 150,
	Nutrition: product.Nutrition{Kcal: 61, Protein: 3.5, Fat: 2.1, Carbs: 7.6},
}

func newService(src product.Source, clk *clock, maxEntries int) *product.Service {
	return product.NewService(product.Config{CacheTTL: time.Hour, CacheMaxEntries: maxEntries}, src, clk.Now)
}

func TestLookupValidatesBeforeAskingTheSource(t *testing.T) {
	t.Parallel()

	src := &fakeSource{fn: func(int) (product.Product, error) { return yogurt, nil }}
	svc := newService(src, &clock{now: time.Unix(0, 0)}, 10)
	if _, err := svc.Lookup(context.Background(), "12345", "en"); !errors.Is(err, product.ErrInvalidBarcode) {
		t.Fatalf("error = %v", err)
	}
	if src.count() != 0 {
		t.Error("an invalid barcode must not reach the source")
	}
}

func TestLookupPassesTheNormalizedCodeAndLocale(t *testing.T) {
	t.Parallel()

	src := &fakeSource{fn: func(int) (product.Product, error) { return yogurt, nil }}
	svc := newService(src, &clock{now: time.Unix(0, 0)}, 10)
	if _, err := svc.Lookup(context.Background(), "036000291452", "ru"); err != nil {
		t.Fatal(err)
	}
	if src.last.barcode != "0036000291452" || src.last.locale != "ru" {
		t.Errorf("source got %+v", src.last)
	}
	if _, err := svc.Lookup(context.Background(), "4006381333931", "de"); err != nil {
		t.Fatal(err)
	}
	if src.last.locale != "en" {
		t.Errorf("an unknown locale falls back to en, got %q", src.last.locale)
	}
}

func TestFoundProductsAreCachedUntilTheyExpire(t *testing.T) {
	t.Parallel()

	clk := &clock{now: time.Unix(1000, 0)}
	src := &fakeSource{fn: func(int) (product.Product, error) { return yogurt, nil }}
	svc := newService(src, clk, 10)
	for range 3 {
		got, err := svc.Lookup(context.Background(), "4006381333931", "en")
		if err != nil || got != yogurt {
			t.Fatalf("got %+v, %v", got, err)
		}
	}
	if src.count() != 1 {
		t.Errorf("source calls = %d, want 1", src.count())
	}
	// A different locale has its own entry: the name may differ.
	if _, err := svc.Lookup(context.Background(), "4006381333931", "ru"); err != nil {
		t.Fatal(err)
	}
	if src.count() != 2 {
		t.Errorf("source calls = %d, want 2", src.count())
	}
	clk.advance(2 * time.Hour)
	if _, err := svc.Lookup(context.Background(), "4006381333931", "en"); err != nil {
		t.Fatal(err)
	}
	if src.count() != 3 {
		t.Errorf("source calls after the TTL = %d, want 3", src.count())
	}
}

func TestUnknownProductsAreRememberedBrieflyOnly(t *testing.T) {
	t.Parallel()

	clk := &clock{now: time.Unix(1000, 0)}
	src := &fakeSource{fn: func(int) (product.Product, error) { return product.Product{}, product.ErrNotFound }}
	svc := newService(src, clk, 10)
	for range 3 {
		if _, err := svc.Lookup(context.Background(), "4006381333931", "en"); !errors.Is(err, product.ErrNotFound) {
			t.Fatalf("error = %v", err)
		}
	}
	if src.count() != 1 {
		t.Errorf("source calls = %d, want 1", src.count())
	}
	clk.advance(11 * time.Minute)
	_, _ = svc.Lookup(context.Background(), "4006381333931", "en")
	if src.count() != 2 {
		t.Errorf("source calls after the negative TTL = %d, want 2", src.count())
	}
}

func TestFailuresAreNotCached(t *testing.T) {
	t.Parallel()

	src := &fakeSource{fn: func(call int) (product.Product, error) {
		if call == 1 {
			return product.Product{}, product.ErrUnavailable
		}
		return yogurt, nil
	}}
	svc := newService(src, &clock{now: time.Unix(0, 0)}, 10)
	if _, err := svc.Lookup(context.Background(), "4006381333931", "en"); !errors.Is(err, product.ErrUnavailable) {
		t.Fatalf("error = %v", err)
	}
	if got, err := svc.Lookup(context.Background(), "4006381333931", "en"); err != nil || got != yogurt {
		t.Fatalf("retry = %+v, %v", got, err)
	}
}

func TestTheCacheIsBounded(t *testing.T) {
	t.Parallel()

	src := &fakeSource{fn: func(int) (product.Product, error) { return yogurt, nil }}
	svc := newService(src, &clock{now: time.Unix(0, 0)}, 2)
	codes := []string{"4006381333931", "96385074", "036000291452"}
	for _, c := range codes {
		if _, err := svc.Lookup(context.Background(), c, "en"); err != nil {
			t.Fatal(err)
		}
	}
	// The first code was evicted by the third; the third is still cached.
	before := src.count()
	_, _ = svc.Lookup(context.Background(), codes[2], "en")
	if src.count() != before {
		t.Error("the newest entry must be cached")
	}
	_, _ = svc.Lookup(context.Background(), codes[0], "en")
	if src.count() != before+1 {
		t.Error("the oldest entry must have been evicted")
	}
}
