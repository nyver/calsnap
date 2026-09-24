package nutrition

import (
	"bytes"
	"context"
	"strings"
	"testing"

	"example.com/calsnap/server/internal/app/analysis"
	"example.com/calsnap/server/internal/testutil"
)

func loadCatalog(t testing.TB) *Catalog {
	t.Helper()
	c, err := LoadEmbedded(0.85)
	if err != nil {
		t.Fatalf("LoadEmbedded: %v", err)
	}
	return c
}

func TestEmbeddedCatalogMatchesProtocolCopy(t *testing.T) {
	t.Parallel()

	canonical := testutil.ReadProtocol(t, "nutrition/catalog.json")
	if !bytes.Equal(canonical, embeddedCatalog) {
		t.Fatal("server/internal/nutrition/catalog.json differs from protocol/nutrition/catalog.json; run scripts/sync-catalog.sh")
	}
}

func TestEmbeddedCatalogIsValid(t *testing.T) {
	t.Parallel()

	c := loadCatalog(t)
	if c.Len() < 1000 || c.Len() > 5000 {
		t.Errorf("catalog has %d foods, want 1000-5000", c.Len())
	}
	if c.Version() < 1 {
		t.Errorf("catalogVersion = %d", c.Version())
	}
}

func TestEveryEntryIsFindableByItsNamesAndAliases(t *testing.T) {
	t.Parallel()

	c := loadCatalog(t)
	ctx := context.Background()
	for i := range c.entries {
		e := &c.entries[i]
		names := []string{e.ID, e.Name.EN, e.Name.RU}
		names = append(names, e.Aliases.EN...)
		names = append(names, e.Aliases.RU...)
		for _, name := range names {
			m, ok, err := c.FindFood(ctx, name)
			if err != nil || !ok {
				t.Errorf("%q (%s) not found", name, e.ID)
				continue
			}
			if m.Food.ID != e.ID {
				t.Errorf("%q resolves to %s, want %s", name, m.Food.ID, e.ID)
			}
			if m.Kind != analysis.MatchExact && m.Kind != analysis.MatchAlias {
				t.Errorf("%q matched as %s, want exact or alias", name, m.Kind)
			}
		}
	}
}

func TestFindFood(t *testing.T) {
	t.Parallel()

	c := loadCatalog(t)
	tests := []struct {
		name     string
		wantID   string
		wantKind string
	}{
		{"chicken_breast", "chicken_breast", analysis.MatchExact},
		{"Grilled  Chicken Breast!", "chicken_breast", analysis.MatchExact},
		{"white rice", "rice", analysis.MatchAlias},
		{"Boiled rice", "rice", analysis.MatchAlias},
		{"fried rice", "fried_rice", analysis.MatchExact},
		{"Sliced cucumber", "cucumber", analysis.MatchExact},
		{"куриная грудка", "chicken_breast", analysis.MatchAlias},
		{"Жареный  рис", "fried_rice", analysis.MatchAlias},
		{"свёкла", "beetroot", analysis.MatchAlias},
		{"chicken breast fillet with skin", "chicken_breast", analysis.MatchFuzzy},
		{"fresh cherry tomatoe", "cherry_tomato", analysis.MatchFuzzy},
		{"кефир 1%", "kefir", analysis.MatchAlias},
		{"Кефир 2,5%", "kefir_2_5", analysis.MatchAlias},
		{"кефир 3.2% жирности", "kefir_3_2", analysis.MatchFuzzy},
		{"pasta bolognese sauce dish", "spaghetti_bolognese", analysis.MatchFuzzy},
		{"tomatoe", "tomato", analysis.MatchFuzzy},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			m, ok, err := c.FindFood(context.Background(), tt.name)
			if err != nil {
				t.Fatal(err)
			}
			if !ok {
				t.Fatalf("no match for %q", tt.name)
			}
			if m.Food.ID != tt.wantID || m.Kind != tt.wantKind {
				t.Errorf("got %s/%s, want %s/%s", m.Food.ID, m.Kind, tt.wantID, tt.wantKind)
			}
		})
	}
}

// TestNumbersInNamesMustAgree guards against fuzzy matching a percentage
// variant to a different one: an unknown percentage falls through to the AI
// estimate instead of borrowing the values of another fat content.
func TestNumbersInNamesMustAgree(t *testing.T) {
	t.Parallel()

	c := loadCatalog(t)
	for _, name := range []string{"кефир 7%", "творог 12%", "сметана 40%", "milk 9%"} {
		if m, ok, _ := c.FindFood(context.Background(), name); ok {
			t.Errorf("%q unexpectedly matched %s (%s)", name, m.Food.ID, m.Kind)
		}
	}
}

// TestCISStaples pins the everyday Russian and CIS foods that users log most
// often, in Russian and English, to their catalog entries.
func TestCISStaples(t *testing.T) {
	t.Parallel()

	c := loadCatalog(t)
	tests := []struct {
		name   string
		wantID string
	}{
		{"борщ", "borscht"},
		{"Борщ с говядиной", "borscht"},
		{"borscht", "borscht"},
		{"щи", "shchi"},
		{"щи из квашеной капусты", "shchi"},
		{"солянка", "solyanka"},
		{"солянка мясная", "solyanka"},
		{"пельмени", "pelmeni"},
		{"Пельмени со сметаной", "pelmeni"},
		{"жареные пельмени", "fried_pelmeni"},
		{"вареники", "vareniki"},
		{"вареники с картошкой", "vareniki_potato"},
		{"вареники с творогом", "vareniki_cottage_cheese"},
		{"сырники", "syrniki"},
		{"сырники со сметаной", "syrniki"},
		{"оливье", "olivier_salad"},
		{"салат оливье", "olivier_salad"},
		{"оливье с курицей", "olivier_chicken"},
		{"гречка", "buckwheat"},
		{"гречневая каша", "buckwheat"},
		{"гречка с мясом", "buckwheat_with_meat"},
		{"плов", "plov"},
		{"плов с курицей", "plov_chicken"},
		{"плов из баранины", "plov_lamb"},
		{"котлеты", "cutlet"},
		{"куриные котлеты", "chicken_cutlet"},
		{"котлеты по-киевски", "chicken_kiev"},
		{"блины", "blini"},
		{"блины со сметаной", "blini"},
		{"блины с мясом", "blini_with_meat"},
		{"панкейки", "pancakes"},
		{"творог", "cottage_cheese"},
		{"творог 9%", "cottage_cheese_9"},
		{"творог обезжиренный", "cottage_cheese_0"},
		{"кефир", "kefir"},
		{"кефир 2.5%", "kefir_2_5"},
		{"окрошка", "okroshka"},
		{"уха", "ukha"},
		{"рассольник", "rassolnik"},
		{"харчо", "kharcho"},
		{"голубцы", "cabbage_rolls"},
		{"хачапури по-аджарски", "khachapuri_adjarian"},
		{"шашлык из свинины", "shashlik_pork"},
		{"винегрет", "vinegret"},
		{"селёдка под шубой", "herring_under_fur_coat"},
		{"холодец", "kholodets"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			m, ok, err := c.FindFood(context.Background(), tt.name)
			if err != nil || !ok {
				t.Fatalf("no match for %q", tt.name)
			}
			if m.Food.ID != tt.wantID {
				t.Errorf("%q resolves to %s (%s), want %s", tt.name, m.Food.ID, m.Kind, tt.wantID)
			}
		})
	}
}

// TestEnergyMatchesMacros catches typos in kcal or macro values: energy should
// be within a broad band of the Atwater estimate 4P + 9F + 4C. Entries whose
// energy legitimately differs (alcohol, fibre-rich fruit) are listed explicitly.
func TestEnergyMatchesMacros(t *testing.T) {
	t.Parallel()

	exempt := map[string]string{
		"lemon": "fibre", "lime": "fibre",
		"beer": "alcohol", "beer_light": "alcohol", "beer_dark": "alcohol", "cider": "alcohol",
		"wine": "alcohol", "red_wine": "alcohol", "white_wine": "alcohol", "champagne": "alcohol", "mulled_wine": "alcohol",
		"sake": "alcohol", "vodka": "alcohol", "whiskey": "alcohol", "brandy": "alcohol", "rum": "alcohol",
		"gin": "alcohol", "tequila": "alcohol", "samogon": "alcohol",
	}
	c := loadCatalog(t)
	for i := range c.entries {
		e := &c.entries[i]
		n := e.Nutrition
		if n.Kcal < 20 {
			continue
		}
		if _, ok := exempt[e.ID]; ok {
			continue
		}
		atwater := 4*n.Protein + 9*n.Fat + 4*n.Carbs
		if ratio := atwater / n.Kcal; ratio < 0.65 || ratio > 1.4 {
			t.Errorf("%s: kcal %v but 4P+9F+4C = %.0f (ratio %.2f)", e.ID, n.Kcal, atwater, ratio)
		}
	}
}

// TestSimilarityReachableIsUpperBound proves the length prefilter of the fuzzy
// stage never skips a pair that would reach the threshold.
func TestSimilarityReachableIsUpperBound(t *testing.T) {
	t.Parallel()

	c := loadCatalog(t)
	const threshold = 0.85
	keys := c.scan
	if len(keys) > 300 {
		keys = keys[:300]
	}
	for _, a := range keys {
		for _, b := range keys {
			if similarity(a.key, b.key) >= threshold && !similarityReachable(a.runes, b.runes, threshold) {
				t.Fatalf("%q vs %q reaches %v but is filtered out", a.key, b.key, threshold)
			}
		}
	}
}

func TestFindFoodNoMatch(t *testing.T) {
	t.Parallel()

	c := loadCatalog(t)
	for _, name := range []string{
		"grandma's special casserole",
		"parsley garnish",
		"xyzzy",
		"",
		"   !!! ",
	} {
		if m, ok, _ := c.FindFood(context.Background(), name); ok {
			t.Errorf("%q unexpectedly matched %s (%s)", name, m.Food.ID, m.Kind)
		}
	}
}

func TestFoodLocalizedNames(t *testing.T) {
	t.Parallel()

	c := loadCatalog(t)
	m, ok, _ := c.FindFood(context.Background(), "chicken breast")
	if !ok {
		t.Fatal("chicken breast not found")
	}
	if got := m.Food.DisplayName(analysis.LocaleRU); got != "Куриная грудка" {
		t.Errorf("ru name = %q", got)
	}
	if got := m.Food.DisplayName(analysis.LocaleEN); got != "Chicken breast" {
		t.Errorf("en name = %q", got)
	}
	f, err := c.GetNutrition(context.Background(), "chicken_breast")
	if err != nil || f.Nutrition.Protein != 31 {
		t.Errorf("GetNutrition = %+v, %v", f, err)
	}
	if _, err := c.GetNutrition(context.Background(), "nope"); err == nil {
		t.Error("GetNutrition of unknown id must fail")
	}
}

func TestParseValidation(t *testing.T) {
	t.Parallel()

	const head = `{"formatVersion":1,"catalogVersion":1,"modifiers":{"en":["grilled"],"ru":[]},"foods":[`
	entry := func(id, alias string, kcal string) string {
		return `{"id":"` + id + `","name":{"en":"` + id + ` en","ru":"` + id + ` ru"},"aliases":{"en":["` + alias +
			`"],"ru":[]},"nutrition":{"kcal":` + kcal + `,"protein":1,"fat":1,"carbs":1},"source":"test"}`
	}
	tests := []struct {
		name    string
		doc     string
		wantErr string
	}{
		{"ok", head + entry("a", "aa", "10") + `]}`, ""},
		{"duplicate alias", head + entry("a", "shared", "10") + "," + entry("b", "shared", "10") + `]}`, `alias "shared"`},
		{"alias equals other id", head + entry("a", "b", "10") + "," + entry("b", "bb", "10") + `]}`, "duplicates the id"},
		{"duplicate id", head + entry("a", "x", "10") + "," + entry("a", "y", "10") + `]}`, "duplicate catalog id"},
		{"kcal out of range", head + entry("a", "x", "901") + `]}`, "kcal"},
		{"bad id", head + entry("Bad-Id", "x", "10") + `]}`, "snake_case"},
		{"unknown format", `{"formatVersion":2,"catalogVersion":1,"foods":[]}`, "formatVersion"},
		{"unknown field", strings.Replace(head, `"modifiers"`, `"extra":1,"modifiers"`, 1) + entry("a", "x", "10") + `]}`, "unknown field"},
		{"no foods", `{"formatVersion":1,"catalogVersion":1,"modifiers":{"en":[],"ru":[]},"foods":[]}`, "no foods"},
		{"bad modifier", strings.Replace(head, `"grilled"`, `"Two Words"`, 1) + entry("a", "x", "10") + `]}`, "modifier"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			_, err := Parse([]byte(tt.doc), 0.85)
			switch {
			case tt.wantErr == "" && err != nil:
				t.Fatalf("unexpected error: %v", err)
			case tt.wantErr != "" && err == nil:
				t.Fatalf("expected error containing %q", tt.wantErr)
			case tt.wantErr != "" && !strings.Contains(err.Error(), tt.wantErr):
				t.Fatalf("error %q does not contain %q", err, tt.wantErr)
			}
		})
	}
}

func TestSimilarity(t *testing.T) {
	t.Parallel()

	tests := []struct {
		a, b string
		want float64
	}{
		{"", "", 1},
		{"abc", "abc", 1},
		{"abc", "", 0},
		{"kitten", "sitting", 1 - 3.0/7.0},
		{"tomato", "tomatoe", 1 - 1.0/7.0},
		{"щи", "щи", 1},
	}
	for _, tt := range tests {
		if got := similarity(tt.a, tt.b); got < tt.want-1e-9 || got > tt.want+1e-9 {
			t.Errorf("similarity(%q,%q) = %v, want %v", tt.a, tt.b, got, tt.want)
		}
	}
}
