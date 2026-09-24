// Package fake implements a deterministic analysis.FoodVisionProvider for
// development and tests. It never touches the network. The configuration
// refuses it in production.
package fake

import (
	"context"
	"crypto/sha256"

	"example.com/calsnap/server/internal/app/analysis"
)

// Provider returns one of a few canned results chosen by the hash of the image,
// so the same photo always yields the same answer.
type Provider struct{}

var _ analysis.FoodVisionProvider = Provider{}

// Analyze implements analysis.FoodVisionProvider.
func (Provider) Analyze(ctx context.Context, img analysis.Image, _ analysis.RequestContext) (analysis.Result, error) {
	if err := ctx.Err(); err != nil {
		return analysis.Result{}, err
	}
	scenarios := Results()
	sum := sha256.Sum256(img.Data)
	return scenarios[int(sum[0])%len(scenarios)], nil
}

// Results returns the canned results in scenario order: full, partial,
// estimated nutrition and no food. They mirror protocol/fixtures/ai-result-*.json.
func Results() []analysis.Result {
	item := func(name, display string, weight, conf float64, cooking string, kcal, p, f, c float64) analysis.RecognizedItem {
		return analysis.RecognizedItem{
			Name: name, DisplayName: display, EstimatedWeightG: weight, Confidence: conf, CookingMethod: cooking,
			NutritionPer100g: &analysis.Nutrition{Kcal: kcal, Protein: p, Fat: f, Carbs: c},
		}
	}
	return []analysis.Result{
		{Items: []analysis.RecognizedItem{
			item("grilled chicken breast", "Куриная грудка на гриле", 135, 0.92, "grilled", 165, 31, 3.6, 0),
			item("white rice", "Рис", 170, 0.86, "", 130, 2.7, 0.3, 28),
			item("cucumber", "Огурцы", 80, 0.81, "", 15, 0.7, 0.1, 3.6),
			item("tomato", "Помидоры", 65, 0.78, "", 18, 0.9, 0.2, 3.9),
		}},
		{Items: []analysis.RecognizedItem{
			item("pasta", "Pasta", 200, 0.9, "", 158, 5.8, 0.9, 31),
			item("tomato sauce", "Tomato sauce", 60, 0.35, "", 40, 1.5, 1, 7),
			item("parsley garnish", "Parsley garnish", 5, 0.1, "", 36, 3, 0.8, 6.3),
		}},
		{Items: []analysis.RecognizedItem{
			item("grandma's special casserole", "Grandma's special casserole", 250, 0.55, "", 180, 8, 9, 17),
			item("rice", "Rice", 100, 0.9, "", 130, 2.7, 0.3, 28),
		}},
		{Items: []analysis.RecognizedItem{}},
	}
}
