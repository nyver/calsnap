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
	if c.Len() < 150 || c.Len() > 250 {
		t.Errorf("catalog has %d foods, want 150-250", c.Len())
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
		{"fresh cherry tomatoe", "tomato", analysis.MatchFuzzy},
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
