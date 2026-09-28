package fake_test

import (
	"context"
	"encoding/json"
	"testing"

	"example.com/calsnap/server/internal/app/analysis"
	"example.com/calsnap/server/internal/app/plateadvice"
	"example.com/calsnap/server/internal/testutil"
	"example.com/calsnap/server/internal/vision/fake"
)

func TestDeterministicByImageHash(t *testing.T) {
	t.Parallel()

	p := fake.Provider{}
	img := analysis.Image{Data: []byte("some photo")}
	first, err := p.Analyze(context.Background(), img, analysis.RequestContext{})
	if err != nil {
		t.Fatal(err)
	}
	for range 5 {
		again, _ := p.Analyze(context.Background(), img, analysis.RequestContext{})
		a, _ := json.Marshal(first)
		b, _ := json.Marshal(again)
		if string(a) != string(b) {
			t.Fatal("same image must give the same result")
		}
	}
}

func TestEveryScenarioIsReachableAndValid(t *testing.T) {
	t.Parallel()

	p := fake.Provider{}
	seen := map[int]bool{}
	for i := range 200 {
		res, err := p.Analyze(context.Background(), analysis.Image{Data: []byte{byte(i), byte(i >> 3), 7}}, analysis.RequestContext{})
		if err != nil {
			t.Fatal(err)
		}
		if err := analysis.Validate(res); err != nil {
			t.Fatalf("canned result invalid: %v", err)
		}
		seen[len(res.Items)] = true
	}
	for _, n := range []int{0, 2, 3, 4} {
		if !seen[n] {
			t.Errorf("no scenario with %d items was produced", n)
		}
	}
}

func TestRespectsCancelledContext(t *testing.T) {
	t.Parallel()

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := (fake.Provider{}).Analyze(ctx, analysis.Image{}, analysis.RequestContext{}); err == nil {
		t.Fatal("expected context error")
	}
}

// TestResultsMirrorProtocolFixtures keeps the canned data equal to the shared
// fixtures that the client and the contract tests use.
func TestResultsMirrorProtocolFixtures(t *testing.T) {
	t.Parallel()

	files := []string{"ai-result-full.json", "ai-result-partial.json", "ai-result-estimated.json", "ai-result-no-food.json"}
	results := fake.Results()
	if len(results) != len(files) {
		t.Fatalf("%d results, %d fixtures", len(results), len(files))
	}
	for i, name := range files {
		want, err := analysis.ParseResult(testutil.Fixture(t, name))
		if err != nil {
			t.Fatal(err)
		}
		a, _ := json.Marshal(want)
		b, _ := json.Marshal(results[i])
		if string(a) != string(b) {
			t.Errorf("%s differs from fake scenario %d:\n%s\n%s", name, i, a, b)
		}
	}
}

// TestAdviseIsConsistentForEveryBalance exercises every combination of the
// three statuses except all-unknown (rejected before Advise is ever called),
// in both locales, and checks the canned advice always passes shape and
// consistency validation, as design.md Decision 2 promises.
func TestAdviseIsConsistentForEveryBalance(t *testing.T) {
	t.Parallel()

	statuses := []plateadvice.Status{plateadvice.StatusLow, plateadvice.StatusOK, plateadvice.StatusHigh, plateadvice.StatusUnknown}
	p := fake.Provider{}
	for _, locale := range []string{analysis.LocaleRU, analysis.LocaleEN} {
		for _, veg := range statuses {
			for _, protein := range statuses {
				for _, carb := range statuses {
					balance := plateadvice.Balance{VegetablesFruit: veg, Protein: protein, ComplexCarbohydrates: carb}
					if veg == plateadvice.StatusUnknown && protein == plateadvice.StatusUnknown && carb == plateadvice.StatusUnknown {
						continue
					}
					advice, err := p.Advise(context.Background(), plateadvice.Input{Locale: locale, MealType: plateadvice.MealLunch, Balance: balance})
					if err != nil {
						t.Fatalf("locale=%s balance=%+v: Advise() error = %v", locale, balance, err)
					}
					if err := plateadvice.ValidateAdvice(advice); err != nil {
						t.Fatalf("locale=%s balance=%+v: ValidateAdvice() error = %v", locale, balance, err)
					}
					if err := plateadvice.CheckConsistency(advice, balance); err != nil {
						t.Fatalf("locale=%s balance=%+v: CheckConsistency() error = %v", locale, balance, err)
					}
				}
			}
		}
	}
}

func TestAdviseRespectsCancelledContext(t *testing.T) {
	t.Parallel()

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	balance := plateadvice.Balance{VegetablesFruit: plateadvice.StatusLow, Protein: plateadvice.StatusOK, ComplexCarbohydrates: plateadvice.StatusOK}
	if _, err := (fake.Provider{}).Advise(ctx, plateadvice.Input{Locale: analysis.LocaleEN, Balance: balance}); err == nil {
		t.Fatal("expected context error")
	}
}
