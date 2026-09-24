package nutrition

import (
	"bytes"
	"context"
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"sort"
	"strings"
	"unicode/utf8"

	"example.com/calsnap/server/internal/app/analysis"
)

// SupportedFormatVersion is the catalog format this code understands.
const SupportedFormatVersion = 1

//go:embed catalog.json
var embeddedCatalog []byte

var idPattern = regexp.MustCompile(`^[a-z0-9]+(_[a-z0-9]+)*$`)

// document mirrors protocol/nutrition/catalog.json.
type document struct {
	FormatVersion  int `json:"formatVersion"`
	CatalogVersion int `json:"catalogVersion"`
	Modifiers      struct {
		EN []string `json:"en"`
		RU []string `json:"ru"`
	} `json:"modifiers"`
	Foods []Entry `json:"foods"`
}

// Entry is one catalog food. Nutrition values are per 100 g.
type Entry struct {
	ID   string `json:"id"`
	Name struct {
		EN string `json:"en"`
		RU string `json:"ru"`
	} `json:"name"`
	Aliases struct {
		EN []string `json:"en"`
		RU []string `json:"ru"`
	} `json:"aliases"`
	Nutrition       analysis.Nutrition `json:"nutrition"`
	GramsPerPiece   float64            `json:"gramsPerPiece"`
	GramsPerPortion float64            `json:"gramsPerPortion"`
	DensityGPerMl   float64            `json:"densityGPerMl"`
	Source          string             `json:"source"`
}

// scanKey is one searchable name of an entry used by the fuzzy stage.
type scanKey struct {
	key    string
	runes  int
	tokens []string
	nums   []string // purely numeric tokens, e.g. the "2", "5" of "kefir 2.5%"
	entry  *Entry
}

// Catalog is an immutable, validated nutrition catalog. It implements
// analysis.NutritionProvider.
type Catalog struct {
	version   int
	norm      *Normalizer
	threshold float64
	entries   []Entry
	byID      map[string]*Entry
	byAlias   map[string]*Entry // full keys of names and aliases
	scan      []scanKey
}

var _ analysis.NutritionProvider = (*Catalog)(nil)

// LoadEmbedded parses and validates the catalog compiled into the binary.
func LoadEmbedded(fuzzyThreshold float64) (*Catalog, error) {
	return Parse(embeddedCatalog, fuzzyThreshold)
}

// Parse decodes and validates catalog JSON. An invalid catalog is an error:
// the server must not start with it.
func Parse(data []byte, fuzzyThreshold float64) (*Catalog, error) {
	var doc document
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&doc); err != nil {
		return nil, fmt.Errorf("decode catalog: %w", err)
	}
	if doc.FormatVersion != SupportedFormatVersion {
		return nil, fmt.Errorf("catalog formatVersion %d is not supported (want %d)", doc.FormatVersion, SupportedFormatVersion)
	}
	if doc.CatalogVersion < 1 {
		return nil, errors.New("catalogVersion must be at least 1")
	}
	if len(doc.Foods) == 0 {
		return nil, errors.New("catalog has no foods")
	}

	mods := append(append([]string{}, doc.Modifiers.EN...), doc.Modifiers.RU...)
	for _, m := range mods {
		if m == "" || m != strings.ToLower(m) || len(Tokens(m)) != 1 {
			return nil, fmt.Errorf("modifier %q must be a single lowercase word", m)
		}
	}

	c := &Catalog{
		version:   doc.CatalogVersion,
		norm:      NewNormalizer(mods),
		threshold: fuzzyThreshold,
		entries:   doc.Foods,
		byID:      make(map[string]*Entry, len(doc.Foods)),
		byAlias:   make(map[string]*Entry),
	}
	for i := range c.entries {
		e := &c.entries[i]
		if err := validateEntry(e); err != nil {
			return nil, err
		}
		if _, dup := c.byID[e.ID]; dup {
			return nil, fmt.Errorf("duplicate catalog id %q", e.ID)
		}
		c.byID[e.ID] = e
	}
	for i := range c.entries {
		e := &c.entries[i]
		names := []string{e.Name.EN, e.Name.RU}
		names = append(names, e.Aliases.EN...)
		names = append(names, e.Aliases.RU...)
		seen := map[string]struct{}{e.ID: {}}
		for _, name := range names {
			k := Full(name)
			if k == "" {
				return nil, fmt.Errorf("entry %q has an empty name or alias", e.ID)
			}
			if _, dup := seen[k]; dup {
				continue
			}
			seen[k] = struct{}{}
			if other, ok := c.byID[k]; ok && other != e {
				return nil, fmt.Errorf("alias %q of %q duplicates the id of %q", name, e.ID, other.ID)
			}
			if other, ok := c.byAlias[k]; ok && other != e {
				return nil, fmt.Errorf("alias %q of %q duplicates an alias of %q", name, e.ID, other.ID)
			}
			c.byAlias[k] = e
		}
		for k := range seen {
			tokens := strings.Split(k, "_")
			c.scan = append(c.scan, scanKey{key: k, runes: utf8.RuneCountInString(k), tokens: tokens, nums: numericTokens(tokens), entry: e})
		}
	}
	// Deterministic scan order makes ties reproducible.
	sort.Slice(c.scan, func(i, j int) bool { return c.scan[i].key < c.scan[j].key })
	return c, nil
}

func validateEntry(e *Entry) error {
	if !idPattern.MatchString(e.ID) {
		return fmt.Errorf("catalog id %q must be snake_case", e.ID)
	}
	if strings.TrimSpace(e.Name.EN) == "" || strings.TrimSpace(e.Name.RU) == "" {
		return fmt.Errorf("entry %q needs both en and ru names", e.ID)
	}
	n := e.Nutrition
	if n.Kcal < 0 || n.Kcal > 900 {
		return fmt.Errorf("entry %q: kcal %v is outside [0, 900]", e.ID, n.Kcal)
	}
	for name, v := range map[string]float64{"protein": n.Protein, "fat": n.Fat, "carbs": n.Carbs} {
		if v < 0 || v > 100 {
			return fmt.Errorf("entry %q: %s %v is outside [0, 100]", e.ID, name, v)
		}
	}
	if n.Protein+n.Fat+n.Carbs > 105 {
		return fmt.Errorf("entry %q: macros sum to more than 105", e.ID)
	}
	for name, v := range map[string]float64{
		"gramsPerPiece": e.GramsPerPiece, "gramsPerPortion": e.GramsPerPortion, "densityGPerMl": e.DensityGPerMl,
	} {
		if v < 0 {
			return fmt.Errorf("entry %q: %s must not be negative", e.ID, name)
		}
	}
	return nil
}

// Version returns catalogVersion of the loaded document.
func (c *Catalog) Version() int { return c.version }

// Len returns the number of foods.
func (c *Catalog) Len() int { return len(c.entries) }

// Normalize implements analysis.NutritionProvider.
func (c *Catalog) Normalize(name string) string { return c.norm.Key(name) }

// GetNutrition implements analysis.NutritionProvider.
func (c *Catalog) GetNutrition(_ context.Context, id string) (analysis.Food, error) {
	e, ok := c.byID[id]
	if !ok {
		return analysis.Food{}, fmt.Errorf("catalog food %q not found", id)
	}
	return toFood(e), nil
}

// FindFood implements analysis.NutritionProvider.
func (c *Catalog) FindFood(_ context.Context, name string) (analysis.Match, bool, error) {
	e, kind := c.find(name)
	if e == nil {
		return analysis.Match{}, false, nil
	}
	return analysis.Match{Food: toFood(e), Kind: kind}, true, nil
}

func toFood(e *Entry) analysis.Food {
	return analysis.Food{
		ID:        e.ID,
		Names:     map[string]string{analysis.LocaleEN: e.Name.EN, analysis.LocaleRU: e.Name.RU},
		Nutrition: e.Nutrition,
	}
}

// find runs the matching pipeline: for the modifier-preserving key and then the
// modifier-free key it tries an exact id and an alias; the fuzzy stage follows.
func (c *Catalog) find(name string) (*Entry, string) {
	full := Full(name)
	if full == "" {
		return nil, ""
	}
	stripped := c.norm.Key(name)
	keys := []string{full}
	if stripped != full {
		keys = append(keys, stripped)
	}
	for _, k := range keys {
		if e, ok := c.byID[k]; ok {
			return e, analysis.MatchExact
		}
		if e, ok := c.byAlias[k]; ok {
			return e, analysis.MatchAlias
		}
	}
	if e := c.fuzzy(stripped); e != nil {
		return e, analysis.MatchFuzzy
	}
	return nil, ""
}

// fuzzy finds the best catalog name for a normalized key. An entry qualifies
// when its normalized name has at least two words that all occur in the key
// ("chicken breast fillet" contains "chicken breast"), or when the normalized
// Levenshtein similarity reaches the threshold. Numbers must agree: a name that
// contains numbers ("kefir 2.5%") only qualifies when the key has the same
// numbers, so "kefir 1%" never resolves to "kefir 0%". Ties are resolved by the
// number of shared words, then by similarity, then by key order.
func (c *Catalog) fuzzy(key string) *Entry {
	words := strings.Split(key, "_")
	keyRunes := utf8.RuneCountInString(key)
	wordSet := make(map[string]struct{}, len(words))
	for _, w := range words {
		wordSet[w] = struct{}{}
	}
	var (
		best       *Entry
		bestShared int
		bestSim    float64
	)
	for _, sk := range c.scan {
		shared := 0
		for _, t := range sk.tokens {
			if _, ok := wordSet[t]; ok {
				shared++
			}
		}
		if !hasAll(wordSet, sk.nums) {
			continue
		}
		contained := len(sk.tokens) >= 2 && shared == len(sk.tokens)
		if !contained && !similarityReachable(keyRunes, sk.runes, c.threshold) {
			continue
		}
		sim := similarity(key, sk.key)
		if !contained && sim < c.threshold {
			continue
		}
		if best == nil || shared > bestShared || (shared == bestShared && sim > bestSim) {
			best, bestShared, bestSim = sk.entry, shared, sim
		}
	}
	return best
}

// numericTokens returns the tokens that consist of digits only.
func numericTokens(tokens []string) []string {
	var nums []string
	for _, t := range tokens {
		if strings.Trim(t, "0123456789") == "" {
			nums = append(nums, t)
		}
	}
	return nums
}

// hasAll reports whether every word is in set.
func hasAll(set map[string]struct{}, words []string) bool {
	for _, w := range words {
		if _, ok := set[w]; !ok {
			return false
		}
	}
	return true
}

// similarityReachable reports whether two names of the given rune lengths can
// reach the threshold at all: the edit distance is at least the length
// difference, so similarity is at most 1 - |la-lb|/max(la, lb). It lets the
// fuzzy stage skip most of a large catalog without running Levenshtein.
func similarityReachable(la, lb int, threshold float64) bool {
	longest := max(la, lb)
	if longest == 0 {
		return true
	}
	diff := la - lb
	if diff < 0 {
		diff = -diff
	}
	return 1-float64(diff)/float64(longest) >= threshold
}

// similarity is 1 - levenshtein(a, b) / max(len(a), len(b)) over runes.
func similarity(a, b string) float64 {
	ra, rb := []rune(a), []rune(b)
	longest := max(len(ra), len(rb))
	if longest == 0 {
		return 1
	}
	return 1 - float64(levenshtein(ra, rb))/float64(longest)
}

func levenshtein(a, b []rune) int {
	if len(a) == 0 {
		return len(b)
	}
	if len(b) == 0 {
		return len(a)
	}
	prev := make([]int, len(b)+1)
	cur := make([]int, len(b)+1)
	for j := range prev {
		prev[j] = j
	}
	for i := 1; i <= len(a); i++ {
		cur[0] = i
		for j := 1; j <= len(b); j++ {
			cost := 1
			if a[i-1] == b[j-1] {
				cost = 0
			}
			cur[j] = min(prev[j]+1, cur[j-1]+1, prev[j-1]+cost)
		}
		prev, cur = cur, prev
	}
	return prev[len(b)]
}
