package analysis

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"strings"
	"unicode/utf8"
)

// Limits of the AI result contract.
const (
	maxItems       = 20
	maxNameRunes   = 100
	maxWeightG     = 3000
	maxKcalPer100g = 900
	maxMacroPer100 = 100
	maxMacroSum    = 105
	maxCookingLen  = 50
)

// ParseResult strictly decodes provider JSON (unknown fields are rejected) and
// validates it. Every failure wraps ErrInvalidResponse.
func ParseResult(data []byte) (Result, error) {
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	var res Result
	if err := dec.Decode(&res); err != nil {
		return Result{}, fmt.Errorf("%w: decode: %v", ErrInvalidResponse, err)
	}
	if _, err := dec.Token(); !errors.Is(err, io.EOF) {
		return Result{}, fmt.Errorf("%w: trailing data after JSON value", ErrInvalidResponse)
	}
	if err := Validate(res); err != nil {
		return Result{}, err
	}
	return res, nil
}

// Validate applies all range and consistency checks to a provider result.
// Numbers coming from a provider are never used without passing it.
func Validate(res Result) error {
	if res.Items == nil {
		return fmt.Errorf("%w: items is missing", ErrInvalidResponse)
	}
	if len(res.Items) > maxItems {
		return fmt.Errorf("%w: %d items, at most %d allowed", ErrInvalidResponse, len(res.Items), maxItems)
	}
	for i, it := range res.Items {
		if err := validateItem(it); err != nil {
			return fmt.Errorf("%w: item %d: %v", ErrInvalidResponse, i, err)
		}
	}
	return nil
}

func validateItem(it RecognizedItem) error {
	if err := validateName("name", it.Name); err != nil {
		return err
	}
	if err := validateName("displayName", it.DisplayName); err != nil {
		return err
	}
	if !finite(it.EstimatedWeightG) || it.EstimatedWeightG <= 0 || it.EstimatedWeightG > maxWeightG {
		return fmt.Errorf("estimatedWeightG %v is outside (0, %d]", it.EstimatedWeightG, maxWeightG)
	}
	if !finite(it.Confidence) || it.Confidence < 0 || it.Confidence > 1 {
		return fmt.Errorf("confidence %v is outside [0, 1]", it.Confidence)
	}
	if utf8.RuneCountInString(it.CookingMethod) > maxCookingLen {
		return errors.New("cookingMethod is too long")
	}
	if n := it.NutritionPer100g; n != nil {
		if !finite(n.Kcal) || n.Kcal < 0 || n.Kcal > maxKcalPer100g {
			return fmt.Errorf("kcal %v is outside [0, %d]", n.Kcal, maxKcalPer100g)
		}
		for name, v := range map[string]float64{"protein": n.Protein, "fat": n.Fat, "carbs": n.Carbs} {
			if !finite(v) || v < 0 || v > maxMacroPer100 {
				return fmt.Errorf("%s %v is outside [0, %d]", name, v, maxMacroPer100)
			}
		}
		if n.Protein+n.Fat+n.Carbs > maxMacroSum {
			return fmt.Errorf("macros sum to %v, more than %d", n.Protein+n.Fat+n.Carbs, maxMacroSum)
		}
	}
	return nil
}

func validateName(field, v string) error {
	if strings.TrimSpace(v) == "" {
		return fmt.Errorf("%s is empty", field)
	}
	if utf8.RuneCountInString(v) > maxNameRunes {
		return fmt.Errorf("%s is longer than %d characters", field, maxNameRunes)
	}
	return nil
}

func finite(v float64) bool { return !math.IsNaN(v) && !math.IsInf(v, 0) }
