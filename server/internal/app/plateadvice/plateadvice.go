// Package plateadvice implements the plate-advice use case: given the
// already computed, local plate-balance assessment and the names, weights
// and plate groups of the current meal's foods, it asks the configured AI
// provider for 1-3 short, structured suggestions that make the plate more
// balanced. The local balance is authoritative: the AI never re-scores it,
// and any answer that contradicts it is rejected.
//
// The Advisor interface is defined on the consumer side so that the AI
// provider can be replaced independently, following the pattern of
// internal/app/analysis and internal/app/label.
package plateadvice

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

// Status is the plate-balance quality of one dimension.
type Status string

// Balance statuses.
const (
	StatusLow     Status = "low"
	StatusOK      Status = "ok"
	StatusHigh    Status = "high"
	StatusUnknown Status = "unknown"
)

func (s Status) valid() bool {
	switch s {
	case StatusLow, StatusOK, StatusHigh, StatusUnknown:
		return true
	default:
		return false
	}
}

// Plate groups, mirroring the catalog's plate.group (protocol/ai and the
// client's PlateGroup enum).
const (
	GroupVegetable           = "vegetable"
	GroupFruit               = "fruit"
	GroupProtein             = "protein"
	GroupComplexCarbohydrate = "complex_carbohydrate"
	GroupHealthyFat          = "healthy_fat"
	GroupDairy               = "dairy"
	GroupOther               = "other"
	GroupUnknown             = "unknown"
)

func validItemGroup(g string) bool {
	switch g {
	case GroupVegetable, GroupFruit, GroupProtein, GroupComplexCarbohydrate, GroupHealthyFat, GroupDairy, GroupOther, GroupUnknown:
		return true
	default:
		return false
	}
}

// validTargetGroup reports whether g is an acceptable AI suggestion target:
// any plate group except unknown.
func validTargetGroup(g string) bool {
	switch g {
	case GroupVegetable, GroupFruit, GroupProtein, GroupComplexCarbohydrate, GroupHealthyFat, GroupDairy, GroupOther:
		return true
	default:
		return false
	}
}

// Meal types.
const (
	MealBreakfast = "breakfast"
	MealLunch     = "lunch"
	MealDinner    = "dinner"
	MealSnack     = "snack"
	MealOther     = "other"
)

func validMealType(m string) bool {
	switch m {
	case MealBreakfast, MealLunch, MealDinner, MealSnack, MealOther:
		return true
	default:
		return false
	}
}

// Suggested actions.
const (
	ActionAdd             = "ADD"
	ActionKeep            = "KEEP"
	ActionOptionalReplace = "OPTIONAL_REPLACE"
)

// dimensionOf maps a plate group to the balance dimension it counts towards.
// healthy_fat, dairy and other belong to no dimension.
var dimensionOf = map[string]string{
	GroupVegetable:           "vegetablesFruit",
	GroupFruit:               "vegetablesFruit",
	GroupProtein:             "protein",
	GroupComplexCarbohydrate: "complexCarbohydrates",
}

// Limits of the request and the AI output contracts.
const (
	minItems         = 1
	maxItems         = 30
	maxItemNameRunes = 120
	maxWeightG       = 10000

	minSuggestions  = 1
	maxSuggestions  = 3
	minSummaryRunes = 1
	maxSummaryRunes = 300
	maxTitleRunes   = 100
	maxReasonRunes  = 240
	maxExamples     = 4
	maxExampleRunes = 80
)

// Item is one food in a plate advice request.
type Item struct {
	Name       string
	WeightG    float64
	PlateGroup string
}

// Balance is the local plate-balance assessment for the three dimensions
// that plate advice reasons about.
type Balance struct {
	VegetablesFruit      Status
	Protein              Status
	ComplexCarbohydrates Status
}

// status returns the balance status for a dimension name (as produced by
// dimensionOf), and whether the dimension is known.
func (b Balance) status(dimension string) (Status, bool) {
	switch dimension {
	case "vegetablesFruit":
		return b.VegetablesFruit, true
	case "protein":
		return b.Protein, true
	case "complexCarbohydrates":
		return b.ComplexCarbohydrates, true
	default:
		return "", false
	}
}

// allUnknown reports whether every dimension is unknown, meaning the plate
// balance cannot be evaluated.
func (b Balance) allUnknown() bool {
	return b.VegetablesFruit == StatusUnknown && b.Protein == StatusUnknown && b.ComplexCarbohydrates == StatusUnknown
}

// Input is what an Advisor receives: everything needed to build the prompt,
// without transport-only fields such as the request id.
type Input struct {
	Locale   string
	MealType string
	Items    []Item
	Balance  Balance
}

// Request is a plate advice request, before or after validation.
type Request struct {
	Locale   string
	MealType string
	Items    []Item
	Balance  Balance

	// RequestID is the effective correlation id.
	RequestID string
	// ClientRequestID is set only when the client supplied a valid id; it is
	// the key for replay suppression.
	ClientRequestID string
}

// Input returns the provider-facing view of the request.
func (r Request) Input() Input {
	return Input{Locale: r.Locale, MealType: r.MealType, Items: r.Items, Balance: r.Balance}
}

// Suggestion is one piece of advice.
type Suggestion struct {
	Action string `json:"action"`
	// TargetGroup is empty when the suggestion targets no specific group.
	TargetGroup string   `json:"targetGroup,omitempty"`
	Title       string   `json:"title"`
	Reason      string   `json:"reason"`
	Examples    []string `json:"examples,omitempty"`
}

// Advice is the provider's structured answer, conforming to
// protocol/ai/plate-advice-result.schema.json.
type Advice struct {
	Summary     string       `json:"summary"`
	Suggestions []Suggestion `json:"suggestions"`

	// Usage is filled by the provider and is not part of the JSON contract.
	Usage analysis.Usage `json:"-"`
}

// Advisor asks the configured AI provider for plate advice. Implementations
// must return errors wrapping analysis.ErrUnavailable,
// analysis.ErrInvalidResponse or analysis.ErrRejected.
type Advisor interface {
	Advise(ctx context.Context, in Input) (Advice, error)
}

// ErrNotEvaluable means every balance dimension is unknown, so no AI call is
// made: there is nothing for the model to react to.
var ErrNotEvaluable = errors.New("plate balance is not evaluable")

// RequestError is a validation failure of an incoming request. Its message
// names the offending field only, never the value the client sent.
type RequestError struct {
	Field  string
	Reason string
}

func (e *RequestError) Error() string {
	if e.Reason == "" {
		return "plate advice request: invalid " + e.Field
	}
	return "plate advice request: " + e.Field + ": " + e.Reason
}

func fieldErr(field, reason string) error { return &RequestError{Field: field, Reason: reason} }

// ValidateRequest normalizes and validates an incoming request. On success it
// returns the request with item names cleaned (control characters replaced
// by spaces, white space collapsed and trimmed). It returns ErrNotEvaluable
// when every balance dimension is unknown, or a *RequestError for any other
// violation.
func ValidateRequest(req Request) (Request, error) {
	switch req.Locale {
	case analysis.LocaleEN, analysis.LocaleRU:
	default:
		return Request{}, fieldErr("locale", "must be ru or en")
	}
	if !validMealType(req.MealType) {
		return Request{}, fieldErr("mealType", "must be breakfast, lunch, dinner, snack or other")
	}
	if n := len(req.Items); n < minItems || n > maxItems {
		return Request{}, fieldErr("items", fmt.Sprintf("must have between %d and %d entries", minItems, maxItems))
	}

	items := make([]Item, len(req.Items))
	for i, it := range req.Items {
		name := cleanName(it.Name)
		if n := utf8.RuneCountInString(name); n < 1 || n > maxItemNameRunes {
			return Request{}, fieldErr(fmt.Sprintf("items[%d].name", i), fmt.Sprintf("must have between 1 and %d characters after normalization", maxItemNameRunes))
		}
		if !finite(it.WeightG) || it.WeightG <= 0 || it.WeightG > maxWeightG {
			return Request{}, fieldErr(fmt.Sprintf("items[%d].weightG", i), fmt.Sprintf("must be a finite number in (0, %d]", maxWeightG))
		}
		if !validItemGroup(it.PlateGroup) {
			return Request{}, fieldErr(fmt.Sprintf("items[%d].plateGroup", i), "must be a known plate group")
		}
		items[i] = Item{Name: name, WeightG: it.WeightG, PlateGroup: it.PlateGroup}
	}

	if !req.Balance.VegetablesFruit.valid() {
		return Request{}, fieldErr("balance.vegetablesFruit", "must be low, ok, high or unknown")
	}
	if !req.Balance.Protein.valid() {
		return Request{}, fieldErr("balance.protein", "must be low, ok, high or unknown")
	}
	if !req.Balance.ComplexCarbohydrates.valid() {
		return Request{}, fieldErr("balance.complexCarbohydrates", "must be low, ok, high or unknown")
	}
	if req.Balance.allUnknown() {
		return Request{}, ErrNotEvaluable
	}

	out := req
	out.Items = items
	return out, nil
}

// ParseAdvice strictly decodes provider JSON (unknown fields and trailing
// data are rejected) and validates it. Every failure wraps
// analysis.ErrInvalidResponse.
func ParseAdvice(data []byte) (Advice, error) {
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	var a Advice
	if err := dec.Decode(&a); err != nil {
		return Advice{}, fmt.Errorf("%w: decode: %v", analysis.ErrInvalidResponse, err)
	}
	if _, err := dec.Token(); !errors.Is(err, io.EOF) {
		return Advice{}, fmt.Errorf("%w: trailing data after JSON value", analysis.ErrInvalidResponse)
	}
	if err := ValidateAdvice(a); err != nil {
		return Advice{}, err
	}
	return a, nil
}

// ValidateAdvice checks the shape of an AI answer: counts, string lengths and
// enums. It does not check consistency with the balance; see CheckConsistency.
// Every failure wraps analysis.ErrInvalidResponse and never echoes the
// provider's text.
func ValidateAdvice(a Advice) error {
	bad := func(format string, args ...any) error {
		return fmt.Errorf("%w: "+format, append([]any{analysis.ErrInvalidResponse}, args...)...)
	}
	if n := utf8.RuneCountInString(a.Summary); n < minSummaryRunes || n > maxSummaryRunes {
		return bad("summary length is outside [%d, %d]", minSummaryRunes, maxSummaryRunes)
	}
	if n := len(a.Suggestions); n < minSuggestions || n > maxSuggestions {
		return bad("suggestions has %d entries, must be between %d and %d", n, minSuggestions, maxSuggestions)
	}
	for i, s := range a.Suggestions {
		switch s.Action {
		case ActionAdd, ActionKeep, ActionOptionalReplace:
		default:
			return bad("suggestion %d: action is not ADD, KEEP or OPTIONAL_REPLACE", i)
		}
		if s.TargetGroup != "" && !validTargetGroup(s.TargetGroup) {
			return bad("suggestion %d: targetGroup is not a known plate group", i)
		}
		if n := utf8.RuneCountInString(s.Title); n < 1 || n > maxTitleRunes {
			return bad("suggestion %d: title length is outside [1, %d]", i, maxTitleRunes)
		}
		if n := utf8.RuneCountInString(s.Reason); n < 1 || n > maxReasonRunes {
			return bad("suggestion %d: reason length is outside [1, %d]", i, maxReasonRunes)
		}
		if n := len(s.Examples); n > maxExamples {
			return bad("suggestion %d: examples has %d entries, more than %d", i, n, maxExamples)
		}
		for j, ex := range s.Examples {
			if n := utf8.RuneCountInString(ex); n < 1 || n > maxExampleRunes {
				return bad("suggestion %d: example %d length is outside [1, %d]", i, j, maxExampleRunes)
			}
		}
	}
	return nil
}

// CheckConsistency rejects AI output that contradicts the supplied balance,
// the code-level guarantee behind "the local balance is authoritative":
//   - ADD must target a group whose dimension is low;
//   - KEEP targeting a group that belongs to a dimension must target one that
//     is ok; a target outside any dimension is unconstrained;
//   - OPTIONAL_REPLACE must not target a dimension that is high; a target
//     outside any dimension is allowed.
//
// Errors wrap analysis.ErrInvalidResponse and name only the rule and the
// enum values involved, never free text from the request or the response.
func CheckConsistency(a Advice, balance Balance) error {
	for _, s := range a.Suggestions {
		dim, hasDim := dimensionOf[s.TargetGroup]
		var status Status
		if hasDim {
			status, _ = balance.status(dim)
		}
		switch s.Action {
		case ActionAdd:
			if s.TargetGroup == "" {
				return fmt.Errorf("%w: ADD has no targetGroup", analysis.ErrInvalidResponse)
			}
			if !hasDim || status != StatusLow {
				return fmt.Errorf("%w: ADD targets %s which is %s", analysis.ErrInvalidResponse, s.TargetGroup, statusOrNone(hasDim, status))
			}
		case ActionKeep:
			if hasDim && status != StatusOK {
				return fmt.Errorf("%w: KEEP targets %s which is %s", analysis.ErrInvalidResponse, s.TargetGroup, status)
			}
		case ActionOptionalReplace:
			if hasDim && status == StatusHigh {
				return fmt.Errorf("%w: OPTIONAL_REPLACE targets %s which is %s", analysis.ErrInvalidResponse, s.TargetGroup, status)
			}
		}
	}
	return nil
}

func statusOrNone(hasDim bool, status Status) string {
	if !hasDim {
		return "not part of any dimension"
	}
	return string(status)
}

// cleanName drops control characters and collapses white space; item names
// come from the client and are untrusted.
func cleanName(s string) string {
	s = strings.Map(func(r rune) rune {
		if r < ' ' || r == 0x7f {
			return ' '
		}
		return r
	}, s)
	return strings.Join(strings.Fields(s), " ")
}

func finite(v float64) bool { return !math.IsNaN(v) && !math.IsInf(v, 0) }
