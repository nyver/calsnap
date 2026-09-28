// Package fake implements a deterministic analysis.FoodVisionProvider for
// development and tests. It never touches the network. The configuration
// refuses it in production.
package fake

import (
	"context"
	"crypto/sha256"

	"example.com/calsnap/server/internal/app/analysis"
	"example.com/calsnap/server/internal/app/label"
	"example.com/calsnap/server/internal/app/plateadvice"
)

// Provider returns one of a few canned results chosen by the hash of the image,
// so the same photo always yields the same answer.
type Provider struct{}

var (
	_ analysis.FoodVisionProvider = Provider{}
	_ label.Reader                = Provider{}
	_ plateadvice.Advisor         = Provider{}
)

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

// ReadLabel implements label.Reader with canned tables chosen by the hash of
// the image: a per 100 g table, a per serving table and a photo without a
// table.
func (Provider) ReadLabel(ctx context.Context, img analysis.Image, _ analysis.RequestContext) (label.Extraction, error) {
	if err := ctx.Err(); err != nil {
		return label.Extraction{}, err
	}
	scenarios := LabelResults()
	sum := sha256.Sum256(img.Data)
	return scenarios[int(sum[0])%len(scenarios)], nil
}

// adviceText is a locale pair of ready-made suggestion wording.
type adviceText struct {
	title, reason string
	examples      []string
}

func pickText(ru bool, ruText, enText adviceText) adviceText {
	if ru {
		return ruText
	}
	return enText
}

// Advise implements plateadvice.Advisor: deterministic, locale-appropriate
// advice built only from the supplied balance, so it always passes
// plateadvice.CheckConsistency (see design.md Decision 2). It never touches
// the network.
func (Provider) Advise(ctx context.Context, in plateadvice.Input) (plateadvice.Advice, error) {
	if err := ctx.Err(); err != nil {
		return plateadvice.Advice{}, err
	}
	ru := in.Locale == analysis.LocaleRU
	b := in.Balance

	var suggestions []plateadvice.Suggestion
	add := func(action, target string, t adviceText) {
		suggestions = append(suggestions, plateadvice.Suggestion{
			Action: action, TargetGroup: target, Title: t.title, Reason: t.reason, Examples: t.examples,
		})
	}

	if b.VegetablesFruit == plateadvice.StatusLow {
		add(plateadvice.ActionAdd, plateadvice.GroupVegetable, pickText(ru,
			adviceText{"Добавьте овощи", "Овощей и фруктов сейчас мало по сравнению с остальным блюдом.", []string{"огуречно-томатный салат", "брокколи на пару"}},
			adviceText{"Add vegetables", "Vegetables and fruit are low compared with the rest of the meal.", []string{"cucumber and tomato salad", "steamed broccoli"}},
		))
	}
	if b.Protein == plateadvice.StatusLow {
		add(plateadvice.ActionAdd, plateadvice.GroupProtein, pickText(ru,
			adviceText{"Добавьте белок", "Белка сейчас мало по сравнению с остальным блюдом.", []string{"куриная грудка", "яйцо"}},
			adviceText{"Add protein", "Protein is low compared with the rest of the meal.", []string{"chicken breast", "egg"}},
		))
	}
	switch b.ComplexCarbohydrates {
	case plateadvice.StatusHigh:
		// A group whose own dimension is high cannot be an OPTIONAL_REPLACE
		// target, so fall back to a group outside any dimension when
		// vegetablesFruit also happens to be high.
		target := plateadvice.GroupVegetable
		if b.VegetablesFruit == plateadvice.StatusHigh {
			target = plateadvice.GroupOther
		}
		add(plateadvice.ActionOptionalReplace, target, pickText(ru,
			adviceText{"Замените часть гарнира", "Сложных углеводов сейчас больше, чем нужно для баланса.", []string{"часть гарнира можно заменить овощами"}},
			adviceText{"Swap part of the side", "Complex carbohydrates make up more of the plate than a balanced portion.", []string{"trade some of the side for extra vegetables"}},
		))
	case plateadvice.StatusLow:
		add(plateadvice.ActionAdd, plateadvice.GroupComplexCarbohydrate, pickText(ru,
			adviceText{"Добавьте гарнир", "Сложных углеводов сейчас мало по сравнению с остальным блюдом.", []string{"гречка", "бурый рис"}},
			adviceText{"Add a side", "Complex carbohydrates are low compared with the rest of the meal.", []string{"buckwheat", "brown rice"}},
		))
	}

	if len(suggestions) == 0 {
		// Nothing is low or high enough to react to: point at whichever
		// dimension is confirmed ok, so KEEP stays consistent.
		target := ""
		switch {
		case b.Protein == plateadvice.StatusOK:
			target = plateadvice.GroupProtein
		case b.VegetablesFruit == plateadvice.StatusOK:
			target = plateadvice.GroupVegetable
		case b.ComplexCarbohydrates == plateadvice.StatusOK:
			target = plateadvice.GroupComplexCarbohydrate
		}
		add(plateadvice.ActionKeep, target, pickText(ru,
			adviceText{"Баланс уже неплохой", "Тарелка уже сбалансирована по этому показателю: менять ничего не обязательно.", nil},
			adviceText{"The balance already looks good", "The plate is already balanced on this measure: no change is required.", nil},
		))
	}
	if len(suggestions) > 3 {
		suggestions = suggestions[:3]
	}

	summary := "A few small changes can help balance the plate."
	if ru {
		summary = "Небольшие изменения помогут сбалансировать тарелку."
	}
	return plateadvice.Advice{Summary: summary, Suggestions: suggestions}, nil
}

// LabelResults returns the canned label readings in scenario order.
func LabelResults() []label.Extraction {
	num := func(v float64) *float64 { return &v }
	return []label.Extraction{
		{
			Found: true, ProductName: "Chocolate hazelnut spread", Basis: label.BasisPer100g,
			EnergyKcal: num(220), EnergyKJ: num(920), Protein: num(8.4), Fat: num(12.1), Carbohydrates: num(18.2), Confidence: 0.9,
		},
		{
			Found: true, Basis: label.BasisPerServing, ServingSizeG: num(30),
			EnergyKcal: num(120), Protein: num(3), Fat: num(6), Carbohydrates: num(13.5), Confidence: 0.8,
		},
		{Found: false, Confidence: 0.9},
	}
}
