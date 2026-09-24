// Package httpapi is the HTTP transport of the server: routing, middleware,
// request validation and the unified error format.
package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"

	"example.com/calsnap/server/internal/app/analysis"
)

// Error codes of the public API.
const (
	CodeInvalidRequest         = "INVALID_REQUEST"
	CodeInvalidImage           = "INVALID_IMAGE"
	CodeImageTooLarge          = "IMAGE_TOO_LARGE"
	CodeUnsupportedImageFormat = "UNSUPPORTED_IMAGE_FORMAT"
	CodeRateLimited            = "RATE_LIMITED"
	CodeAIProviderUnavailable  = "AI_PROVIDER_UNAVAILABLE"
	CodeAIInvalidResponse      = "AI_INVALID_RESPONSE"
	CodeNutritionMatchFailed   = "NUTRITION_MATCH_FAILED"
	CodeImageAnalysisFailed    = "IMAGE_ANALYSIS_FAILED"
	CodeInternalError          = "INTERNAL_ERROR"

	CodeProductNotFound          = "PRODUCT_NOT_FOUND"
	CodeProductSourceUnavailable = "PRODUCT_SOURCE_UNAVAILABLE"
	CodeLabelNotRecognized       = "LABEL_NOT_RECOGNIZED"
)

// statusClientClosed is the de-facto status for requests the client abandoned.
// It is only ever recorded in logs and metrics; nobody reads the response.
const statusClientClosed = 499

var codeStatus = map[string]int{
	CodeInvalidRequest:         http.StatusBadRequest,
	CodeInvalidImage:           http.StatusBadRequest,
	CodeImageTooLarge:          http.StatusRequestEntityTooLarge,
	CodeUnsupportedImageFormat: http.StatusUnsupportedMediaType,
	CodeRateLimited:            http.StatusTooManyRequests,
	CodeAIInvalidResponse:      http.StatusBadGateway,
	CodeNutritionMatchFailed:   http.StatusBadGateway,
	CodeImageAnalysisFailed:    http.StatusBadGateway,
	CodeAIProviderUnavailable:  http.StatusServiceUnavailable,
	CodeInternalError:          http.StatusInternalServerError,

	CodeProductNotFound:          http.StatusNotFound,
	CodeProductSourceUnavailable: http.StatusServiceUnavailable,
	CodeLabelNotRecognized:       http.StatusUnprocessableEntity,
}

// defaultMessages are short English developer-facing texts. They never contain
// internal details, provider responses or secrets.
var defaultMessages = map[string]string{
	CodeInvalidRequest:         "Invalid request.",
	CodeInvalidImage:           "The image is missing or cannot be decoded.",
	CodeImageTooLarge:          "The image exceeds the allowed size.",
	CodeUnsupportedImageFormat: "Only JPEG, PNG and WebP images are supported.",
	CodeRateLimited:            "Too many requests. Try again later.",
	CodeAIProviderUnavailable:  "The analysis service is temporarily unavailable.",
	CodeAIInvalidResponse:      "The analysis service returned an invalid result.",
	CodeNutritionMatchFailed:   "Nutrition data could not be determined.",
	CodeImageAnalysisFailed:    "The meal could not be analyzed.",
	CodeInternalError:          "Internal error.",

	CodeProductNotFound:          "No nutrition data was found for this barcode.",
	CodeProductSourceUnavailable: "The product database is temporarily unavailable.",
	CodeLabelNotRecognized:       "No readable nutrition table was found in the image.",
}

// apiError is an error that maps directly to a response.
type apiError struct {
	Code    string
	Message string // empty selects the default message
	Status  int    // zero selects the status of the code
}

func (e *apiError) Error() string { return e.Code + ": " + e.Message }

func newError(code string, message ...string) *apiError {
	e := &apiError{Code: code}
	if len(message) > 0 {
		e.Message = message[0]
	}
	return e
}

// errorBody is the JSON body of every non-2xx response.
type errorBody struct {
	Code      string `json:"code"`
	Message   string `json:"message"`
	RequestID string `json:"requestId"`
}

// classify maps an error from the use case to an API error. The bool is true
// when the client abandoned the request.
func classify(err error) (*apiError, bool) {
	var ae *apiError
	switch {
	case errors.As(err, &ae):
		return ae, false
	case errors.Is(err, context.Canceled):
		return nil, true
	case errors.Is(err, analysis.ErrUnavailable), errors.Is(err, context.DeadlineExceeded):
		return newError(CodeAIProviderUnavailable), false
	case errors.Is(err, analysis.ErrInvalidResponse):
		return newError(CodeAIInvalidResponse), false
	case errors.Is(err, analysis.ErrMatchFailed):
		return newError(CodeNutritionMatchFailed), false
	case errors.Is(err, analysis.ErrRejected):
		return newError(CodeImageAnalysisFailed), false
	default:
		return newError(CodeInternalError), false
	}
}

// writeAPIError writes the unified error body and records the code for the access log.
func writeAPIError(w http.ResponseWriter, r *http.Request, e *apiError) {
	status := e.Status
	if status == 0 {
		var ok bool
		if status, ok = codeStatus[e.Code]; !ok {
			status = http.StatusInternalServerError
		}
	}
	msg := e.Message
	if msg == "" {
		msg = defaultMessages[e.Code]
	}
	if in := infoFrom(r.Context()); in != nil {
		in.errorCode = e.Code
	}
	writeJSON(w, status, errorBody{Code: e.Code, Message: msg, RequestID: requestIDFrom(r.Context())})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	// The status line is already sent; an encoding failure can only be a broken connection.
	_ = json.NewEncoder(w).Encode(v)
}

func notFound(w http.ResponseWriter, r *http.Request) {
	writeAPIError(w, r, &apiError{Code: CodeInvalidRequest, Message: "Unknown route.", Status: http.StatusNotFound})
}

func methodNotAllowed(allow string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Allow", allow)
		writeAPIError(w, r, &apiError{Code: CodeInvalidRequest, Message: "Method not allowed.", Status: http.StatusMethodNotAllowed})
	}
}
