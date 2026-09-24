// Package label implements reading a nutrition facts table from a photo of a
// food package: it asks a vision provider to transcribe the table, validates
// the answer and normalizes it to values per 100 g.
//
// The interfaces in this file are defined on the consumer side so that the AI
// vision provider can be replaced independently.
package label

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"strings"
	"unicode/utf8"

	"example.com/calsnap/server/internal/app/analysis"
)

// ErrNotRecognized means the photo shows no readable nutrition table, or one
// that cannot be turned into values per 100 g (per serving without a serving
// size).
var ErrNotRecognized = errors.New("no nutrition table could be read")

// Bases a nutrition table can be printed for.
const (
	BasisPer100g    = "per_100g"
	BasisPer100ml   = "per_100ml"
	BasisPerServing = "per_serving"
)

// Warning codes reported next to the values.
const (
	WarningLowConfidence   = "LOW_CONFIDENCE"
	WarningEnergyMismatch  = "ENERGY_MISMATCH"
	WarningEnergyEstimated = "ENERGY_ESTIMATED"
	WarningValuesConverted = "VALUES_CONVERTED"
	WarningVolumeBasis     = "VOLUME_BASIS"
)

// Limits of the AI result contract.
const (
	maxNameRunes = 100

	// Values are checked twice: as printed (a serving can be large) and after
	// the conversion to 100 g (a physical limit).
	maxPrintedKcal  = 5000
	maxPrintedMacro = 1000
	maxServing      = 2000
	maxKcalPer100g  = 900
	maxMacroPer100  = 100
	maxMacroSum     = 105

	kJPerKcal = 4.184
	// A label whose energy is further than this from what its macros imply
	// gets ENERGY_MISMATCH; fibre, polyols and alcohol explain small gaps.
	mismatchAbsolute = 40.0
	mismatchRelative = 0.35

	lowConfidenceBelow = 0.5
)

// Extraction is the provider's transcription of the table, conforming to
// protocol/ai/nutrition-label-result.schema.json. Values are exactly as
// printed; absent means the provider did not see them.
type Extraction struct {
	Found         bool     `json:"found"`
	ProductName   string   `json:"productName,omitempty"`
	Basis         string   `json:"basis,omitempty"`
	ServingSizeG  *float64 `json:"servingSizeG,omitempty"`
	EnergyKcal    *float64 `json:"energyKcal,omitempty"`
	EnergyKJ      *float64 `json:"energyKj,omitempty"`
	Protein       *float64 `json:"protein,omitempty"`
	Fat           *float64 `json:"fat,omitempty"`
	Carbohydrates *float64 `json:"carbohydrates,omitempty"`
	Confidence    float64  `json:"confidence"`

	// Usage is filled by the provider and is not part of the JSON contract.
	Usage analysis.Usage `json:"-"`
}

// Reader transcribes a nutrition table on a photo. Implementations must
// return errors wrapping analysis.ErrUnavailable, ErrInvalidResponse or
// ErrRejected.
type Reader interface {
	ReadLabel(ctx context.Context, img analysis.Image, rc analysis.RequestContext) (Extraction, error)
}

// ParseExtraction strictly decodes provider JSON (unknown fields are
// rejected) and validates it. Every failure wraps analysis.ErrInvalidResponse.
func ParseExtraction(data []byte) (Extraction, error) {
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	var e Extraction
	if err := dec.Decode(&e); err != nil {
		return Extraction{}, fmt.Errorf("%w: decode: %v", analysis.ErrInvalidResponse, err)
	}
	if _, err := dec.Token(); !errors.Is(err, io.EOF) {
		return Extraction{}, fmt.Errorf("%w: trailing data after JSON value", analysis.ErrInvalidResponse)
	}
	if err := ValidateExtraction(e); err != nil {
		return Extraction{}, err
	}
	return e, nil
}

// ValidateExtraction applies the range checks to a provider answer. Numbers
// from a provider are never used without passing it.
func ValidateExtraction(e Extraction) error {
	bad := func(format string, args ...any) error {
		return fmt.Errorf("%w: "+format, append([]any{analysis.ErrInvalidResponse}, args...)...)
	}
	if !e.Found {
		return nil
	}
	if !finite(e.Confidence) || e.Confidence < 0 || e.Confidence > 1 {
		return bad("confidence %v is outside [0, 1]", e.Confidence)
	}
	if utf8.RuneCountInString(e.ProductName) > maxNameRunes {
		return bad("productName is longer than %d characters", maxNameRunes)
	}
	switch e.Basis {
	case BasisPer100g, BasisPer100ml, BasisPerServing:
	default:
		return bad("basis %q is not one of per_100g, per_100ml, per_serving", e.Basis)
	}
	if s := e.ServingSizeG; s != nil && (!finite(*s) || *s <= 0 || *s > maxServing) {
		return bad("servingSizeG %v is outside (0, %d]", *s, maxServing)
	}
	for name, v := range map[string]struct {
		val *float64
		max float64
	}{
		"energyKcal":    {e.EnergyKcal, maxPrintedKcal},
		"energyKj":      {e.EnergyKJ, maxPrintedKcal * kJPerKcal},
		"protein":       {e.Protein, maxPrintedMacro},
		"fat":           {e.Fat, maxPrintedMacro},
		"carbohydrates": {e.Carbohydrates, maxPrintedMacro},
	} {
		if v.val != nil && (!finite(*v.val) || *v.val < 0 || *v.val > v.max) {
			return bad("%s %v is outside [0, %v]", name, *v.val, v.max)
		}
	}
	return nil
}

// Nutrition holds values per 100 g; nil means the table did not show it.
type Nutrition struct {
	Kcal    *float64
	Protein *float64
	Fat     *float64
	Carbs   *float64
}

// Result is a table normalized to 100 g.
type Result struct {
	// Name is the product name printed on the package, possibly empty.
	Name string
	// ServingSizeG is the declared serving in grams, 0 when unknown.
	ServingSizeG float64
	Nutrition    Nutrition
	Warnings     []string
}

// Normalize turns a validated extraction into values per 100 g. It returns
// ErrNotRecognized for a photo without a usable table and an error wrapping
// analysis.ErrInvalidResponse when the converted values are impossible (the
// provider misread the table), which the caller may retry.
func Normalize(e Extraction) (Result, error) {
	if !e.Found {
		return Result{}, ErrNotRecognized
	}
	if e.EnergyKcal == nil && e.EnergyKJ == nil && e.Protein == nil && e.Fat == nil && e.Carbohydrates == nil {
		return Result{}, ErrNotRecognized
	}

	factor := 1.0
	var warnings []string
	switch e.Basis {
	case BasisPerServing:
		if e.ServingSizeG == nil {
			return Result{}, ErrNotRecognized
		}
		factor = 100 / *e.ServingSizeG
		warnings = append(warnings, WarningValuesConverted)
	case BasisPer100ml:
		warnings = append(warnings, WarningVolumeBasis)
	}
	scale := func(v *float64) *float64 {
		if v == nil {
			return nil
		}
		out := round1(*v * factor)
		return &out
	}

	n := Nutrition{Kcal: scale(e.EnergyKcal), Protein: scale(e.Protein), Fat: scale(e.Fat), Carbs: scale(e.Carbohydrates)}
	if n.Kcal == nil && e.EnergyKJ != nil {
		kcal := round1(*e.EnergyKJ * factor / kJPerKcal)
		n.Kcal = &kcal
	}
	if n.Kcal == nil && n.Protein != nil && n.Fat != nil && n.Carbs != nil {
		kcal := round1(4**n.Protein + 4**n.Carbs + 9**n.Fat)
		n.Kcal = &kcal
		warnings = append(warnings, WarningEnergyEstimated)
	}
	if err := validatePer100(n); err != nil {
		return Result{}, err
	}
	if n.Kcal != nil && n.Protein != nil && n.Fat != nil && n.Carbs != nil {
		implied := 4**n.Protein + 4**n.Carbs + 9**n.Fat
		if math.Abs(*n.Kcal-implied) > math.Max(mismatchAbsolute, mismatchRelative**n.Kcal) {
			warnings = append(warnings, WarningEnergyMismatch)
		}
	}
	if e.Confidence < lowConfidenceBelow {
		warnings = append(warnings, WarningLowConfidence)
	}

	res := Result{Name: cleanName(e.ProductName), Nutrition: n, Warnings: warnings}
	if e.ServingSizeG != nil {
		res.ServingSizeG = *e.ServingSizeG
	}
	return res, nil
}

func validatePer100(n Nutrition) error {
	if n.Kcal != nil && (*n.Kcal < 0 || *n.Kcal > maxKcalPer100g) {
		return fmt.Errorf("%w: %v kcal per 100 g is outside [0, %d]", analysis.ErrInvalidResponse, *n.Kcal, maxKcalPer100g)
	}
	var sum float64
	for name, v := range map[string]*float64{"protein": n.Protein, "fat": n.Fat, "carbohydrates": n.Carbs} {
		if v == nil {
			continue
		}
		if *v < 0 || *v > maxMacroPer100 {
			return fmt.Errorf("%w: %s %v per 100 g is outside [0, %d]", analysis.ErrInvalidResponse, name, *v, maxMacroPer100)
		}
		sum += *v
	}
	if sum > maxMacroSum {
		return fmt.Errorf("%w: macros sum to %v per 100 g, more than %d", analysis.ErrInvalidResponse, sum, maxMacroSum)
	}
	return nil
}

// cleanName drops control characters and collapses white space; the name is
// text read from a photo and so untrusted.
func cleanName(s string) string {
	s = strings.Map(func(r rune) rune {
		if r < ' ' || r == 0x7f {
			return ' '
		}
		return r
	}, s)
	return strings.Join(strings.Fields(s), " ")
}

func round1(v float64) float64 { return math.Round(v*10) / 10 }

func finite(v float64) bool { return !math.IsNaN(v) && !math.IsInf(v, 0) }
