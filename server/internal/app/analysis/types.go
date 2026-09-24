// Package analysis implements the meal analysis use case: it asks a food
// vision provider to recognize foods on a photo, validates and filters the
// answer, resolves nutrition per 100 g and builds the API result.
//
// The interfaces in this file are defined on the consumer side so that the
// AI vision provider and the nutrition source can be replaced independently.
package analysis

import (
	"context"
	"errors"
)

// Locales supported for display names.
const (
	LocaleEN = "en"
	LocaleRU = "ru"
)

// Warning codes reported next to the recognized items.
const (
	WarningNoFoodDetected     = "NO_FOOD_DETECTED"
	WarningPartialRecognition = "PARTIAL_RECOGNITION"
	WarningLowConfidence      = "LOW_CONFIDENCE"
	WarningNutritionEstimated = "NUTRITION_ESTIMATED"
)

// Nutrition sources reported per item.
const (
	SourceCatalog    = "catalog"
	SourceAIEstimate = "ai_estimate"
)

// Match kinds reported by a NutritionProvider.
const (
	MatchExact    = "exact"
	MatchAlias    = "alias"
	MatchFuzzy    = "fuzzy"
	MatchFallback = "fallback"
)

// Typed errors. Providers wrap them with fmt.Errorf("...: %w", err) so that the
// use case can decide about retries with errors.Is.
var (
	// ErrUnavailable marks a transient provider failure (network error,
	// timeout, HTTP 429/5xx). It is retried.
	ErrUnavailable = errors.New("food vision provider unavailable")
	// ErrInvalidResponse marks output that is not valid JSON or violates the
	// result contract. It is re-attempted once.
	ErrInvalidResponse = errors.New("food vision provider returned an invalid response")
	// ErrRejected marks a non-retryable provider refusal (HTTP 4xx other than
	// 429, blocked content, bad credentials).
	ErrRejected = errors.New("food vision provider rejected the request")
	// ErrMatchFailed means an item has neither a catalog match nor an AI estimate.
	ErrMatchFailed = errors.New("nutrition profile could not be determined")
)

// Image is an uploaded photo that already passed transport validation.
type Image struct {
	Data     []byte
	MIMEType string // image/jpeg, image/png or image/webp
	Width    int
	Height   int
}

// RequestContext is the optional context passed to the vision provider.
type RequestContext struct {
	RequestID       string
	Locale          string  // "en" or "ru"
	PlateDiameterCm float64 // 0 when unknown
	// SideImage is a second photo of the same meal taken from the side; nil for
	// the usual single top-down photo. Providers send it after the main image.
	SideImage *Image
}

// Nutrition holds values per 100 g of food.
type Nutrition struct {
	Kcal    float64 `json:"kcal"`
	Protein float64 `json:"protein"`
	Fat     float64 `json:"fat"`
	Carbs   float64 `json:"carbs"`
}

// RecognizedItem is one food reported by the vision provider.
type RecognizedItem struct {
	Name             string     `json:"name"`
	DisplayName      string     `json:"displayName"`
	EstimatedWeightG float64    `json:"estimatedWeightG"`
	Confidence       float64    `json:"confidence"`
	CookingMethod    string     `json:"cookingMethod,omitempty"`
	NutritionPer100g *Nutrition `json:"nutritionPer100g,omitempty"`
}

// Usage reports token consumption when the provider exposes it.
type Usage struct {
	InputTokens  int
	OutputTokens int
}

// Result is the provider's structured answer, conforming to
// protocol/ai/food-vision-result.schema.json.
type Result struct {
	Items []RecognizedItem `json:"items"`

	// Usage is filled by the provider and is not part of the JSON contract.
	Usage Usage `json:"-"`
}

// FoodVisionProvider recognizes foods on a photo. Implementations must return
// errors wrapping ErrUnavailable, ErrInvalidResponse or ErrRejected.
type FoodVisionProvider interface {
	Analyze(ctx context.Context, img Image, rc RequestContext) (Result, error)
}

// Food is a nutrition profile known to a NutritionProvider.
type Food struct {
	ID        string
	Names     map[string]string // display names keyed by locale
	Nutrition Nutrition
}

// DisplayName returns the name in the locale, falling back to English.
func (f Food) DisplayName(locale string) string {
	if n := f.Names[locale]; n != "" {
		return n
	}
	return f.Names[LocaleEN]
}

// Match is a successful nutrition lookup.
type Match struct {
	Food Food
	Kind string // MatchExact, MatchAlias or MatchFuzzy
}

// NutritionProvider resolves nutrition profiles. The catalog implementation is
// in memory; an external food API could replace it without changing the
// client contract.
type NutritionProvider interface {
	// Normalize returns the stable snake_case key of a food name.
	Normalize(name string) string
	// FindFood resolves a food name reported by the vision provider.
	FindFood(ctx context.Context, name string) (Match, bool, error)
	// GetNutrition returns a profile by its id.
	GetNutrition(ctx context.Context, id string) (Food, error)
}

// Metrics receives technical counters. Implementations must not receive image
// content, food names or client addresses.
type Metrics interface {
	ObserveAICall(provider string, seconds float64)
	AIError(kind string)
	InvalidAIResponse()
	NutritionMatch(kind string)
	NutritionMatchFailed()
	AIUsage(inputTokens, outputTokens int)
}

// AI error kinds used with Metrics.AIError.
const (
	ErrKindUnavailable     = "unavailable"
	ErrKindInvalidResponse = "invalid_response"
	ErrKindRejected        = "rejected"
)

// NopMetrics discards all measurements.
type NopMetrics struct{}

// ObserveAICall implements Metrics.
func (NopMetrics) ObserveAICall(string, float64) {}

// AIError implements Metrics.
func (NopMetrics) AIError(string) {}

// InvalidAIResponse implements Metrics.
func (NopMetrics) InvalidAIResponse() {}

// NutritionMatch implements Metrics.
func (NopMetrics) NutritionMatch(string) {}

// NutritionMatchFailed implements Metrics.
func (NopMetrics) NutritionMatchFailed() {}

// AIUsage implements Metrics.
func (NopMetrics) AIUsage(int, int) {}

// Request is a validated analysis request.
type Request struct {
	Image Image
	// SideImage is the optional second view of the meal (see RequestContext).
	SideImage       *Image
	Locale          string
	PlateDiameterCm float64
	// RequestID is the effective correlation id.
	RequestID string
	// ClientRequestID is set only when the client supplied a valid id; it is the
	// key for duplicate suppression.
	ClientRequestID string
}

// ResponseItem is one recognized food in the API result.
type ResponseItem struct {
	ID               string
	Name             string
	NormalizedName   string
	EstimatedWeightG float64
	Confidence       float64
	NutritionSource  string
	Nutrition        Nutrition
}

// Response is the analysis result returned to the client.
type Response struct {
	RequestID string
	Items     []ResponseItem
	Warnings  []string
}
