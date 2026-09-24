package analysis_test

import (
	"errors"
	"testing"

	"example.com/calsnap/server/internal/app/analysis"
	"example.com/calsnap/server/internal/testutil"
)

func TestParseResultFixtures(t *testing.T) {
	t.Parallel()

	valid := map[string]int{
		"ai-result-full.json":              4,
		"ai-result-partial.json":           3,
		"ai-result-estimated.json":         2,
		"ai-result-no-food.json":           0,
		"ai-result-missing-nutrition.json": 1,
	}
	for name, wantItems := range valid {
		t.Run("valid/"+name, func(t *testing.T) {
			t.Parallel()
			res, err := analysis.ParseResult(testutil.Fixture(t, name))
			if err != nil {
				t.Fatalf("ParseResult: %v", err)
			}
			if len(res.Items) != wantItems {
				t.Errorf("items = %d, want %d", len(res.Items), wantItems)
			}
		})
	}

	invalid := []string{
		"ai-result-invalid-negative-weight.json",
		"ai-result-invalid-zero-weight.json",
		"ai-result-invalid-weight-too-large.json",
		"ai-result-invalid-confidence-range.json",
		"ai-result-invalid-empty-name.json",
		"ai-result-invalid-name-too-long.json",
		"ai-result-invalid-kcal-range.json",
		"ai-result-invalid-macro-range.json",
		"ai-result-invalid-macro-sum.json",
		"ai-result-invalid-unknown-field.json",
		"ai-result-invalid-too-many-items.json",
		"ai-result-malformed.txt",
	}
	for _, name := range invalid {
		t.Run("invalid/"+name, func(t *testing.T) {
			t.Parallel()
			_, err := analysis.ParseResult(testutil.Fixture(t, name))
			if !errors.Is(err, analysis.ErrInvalidResponse) {
				t.Fatalf("err = %v, want ErrInvalidResponse", err)
			}
		})
	}
}

func TestParseResultEdgeCases(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		in   string
		ok   bool
	}{
		{"null items", `{"items": null}`, false},
		{"missing items", `{}`, false},
		{"trailing garbage", `{"items": []} {"items": []}`, false},
		{"empty input", ``, false},
		{"exactly 20 items", `{"items": [` + repeat(`{"name":"a","displayName":"a","estimatedWeightG":1,"confidence":1},`, 19) + `{"name":"a","displayName":"a","estimatedWeightG":3000,"confidence":0}]}`, true},
		{"macro sum exactly 105", `{"items":[{"name":"a","displayName":"a","estimatedWeightG":1,"confidence":1,"nutritionPer100g":{"kcal":900,"protein":35,"fat":35,"carbs":35}}]}`, true},
		{"cooking method too long", `{"items":[{"name":"a","displayName":"a","estimatedWeightG":1,"confidence":1,"cookingMethod":"` + repeat("x", 51) + `"}]}`, false},
		{"multibyte name of 100 runes", `{"items":[{"name":"` + repeat("щ", 100) + `","displayName":"a","estimatedWeightG":1,"confidence":1}]}`, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			_, err := analysis.ParseResult([]byte(tt.in))
			if (err == nil) != tt.ok {
				t.Fatalf("err = %v, want ok=%v", err, tt.ok)
			}
			if err != nil && !errors.Is(err, analysis.ErrInvalidResponse) {
				t.Errorf("error does not wrap ErrInvalidResponse: %v", err)
			}
		})
	}
}

func repeat(s string, n int) string {
	out := ""
	for range n {
		out += s
	}
	return out
}
