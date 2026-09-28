package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"mime"
	"net/http"
	"strconv"

	"example.com/calsnap/server/internal/app/plateadvice"
	"example.com/calsnap/server/internal/ratelimit"
)

// maxPlateAdviceBodyBytes bounds the JSON request body.
const maxPlateAdviceBodyBytes = 64 << 10

// PlateAdviser is the use case consumed by the plate advice endpoint.
type PlateAdviser interface {
	Advise(ctx context.Context, req plateadvice.Request) (plateadvice.Advice, error)
}

type plateAdviceRequestDTO struct {
	Locale   string                `json:"locale"`
	MealType string                `json:"mealType"`
	Items    []plateAdviceItemDTO  `json:"items"`
	Balance  plateAdviceBalanceDTO `json:"balance"`
}

type plateAdviceItemDTO struct {
	Name       string  `json:"name"`
	WeightG    float64 `json:"weightG"`
	PlateGroup string  `json:"plateGroup"`
}

type plateAdviceBalanceDTO struct {
	VegetablesFruit      string `json:"vegetablesFruit"`
	Protein              string `json:"protein"`
	ComplexCarbohydrates string `json:"complexCarbohydrates"`
}

type plateAdviceResponseDTO struct {
	RequestID   string                     `json:"requestId"`
	Summary     string                     `json:"summary"`
	Suggestions []plateAdviceSuggestionDTO `json:"suggestions"`
}

type plateAdviceSuggestionDTO struct {
	Action      string   `json:"action"`
	TargetGroup string   `json:"targetGroup,omitempty"`
	Title       string   `json:"title"`
	Reason      string   `json:"reason"`
	Examples    []string `json:"examples"`
}

// plateAdvice handles POST /v1/plate-advice: a JSON-only request carrying the
// current meal's items and the local plate-balance assessment, answered with
// 1-3 AI suggestions. See design.md Decision 7.
func (h *handlers) plateAdvice(w http.ResponseWriter, r *http.Request) {
	log := h.Logger.With("request_id", requestIDFrom(r.Context()))
	info := infoFrom(r.Context())

	if ok, retry := h.PlateAdviceLimiter.Allow(ratelimit.ClientKey(r, h.TrustedProxies)); !ok {
		h.Observer.RateLimited()
		w.Header().Set("Retry-After", strconv.Itoa(ratelimit.RetryAfterSeconds(retry)))
		writeAPIError(w, r, newError(CodeRateLimited))
		return
	}

	mediaType, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if err != nil || mediaType != "application/json" {
		writeAPIError(w, r, &apiError{Code: CodeInvalidRequest, Message: "Content-Type must be application/json.", Status: http.StatusUnsupportedMediaType})
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, maxPlateAdviceBodyBytes)
	var dto plateAdviceRequestDTO
	dec := json.NewDecoder(r.Body)
	if err := dec.Decode(&dto); err != nil {
		var tooBig *http.MaxBytesError
		if errors.As(err, &tooBig) {
			writeAPIError(w, r, &apiError{Code: CodeInvalidRequest, Message: "Request body exceeds 64 KiB.", Status: http.StatusRequestEntityTooLarge})
			return
		}
		writeAPIError(w, r, newError(CodeInvalidRequest, "Malformed JSON body."))
		return
	}
	if _, err := dec.Token(); !errors.Is(err, io.EOF) {
		writeAPIError(w, r, newError(CodeInvalidRequest, "Trailing data after the JSON value."))
		return
	}

	items := make([]plateadvice.Item, len(dto.Items))
	for i, it := range dto.Items {
		items[i] = plateadvice.Item{Name: it.Name, WeightG: it.WeightG, PlateGroup: it.PlateGroup}
	}
	req, aerr := validatePlateAdviceRequest(plateadvice.Request{
		Locale:   dto.Locale,
		MealType: dto.MealType,
		Items:    items,
		Balance: plateadvice.Balance{
			VegetablesFruit:      plateadvice.Status(dto.Balance.VegetablesFruit),
			Protein:              plateadvice.Status(dto.Balance.Protein),
			ComplexCarbohydrates: plateadvice.Status(dto.Balance.ComplexCarbohydrates),
		},
	})
	if aerr != nil {
		writeAPIError(w, r, aerr)
		return
	}
	req.RequestID = requestIDFrom(r.Context())
	if info.clientID {
		req.ClientRequestID = req.RequestID
	}
	info.itemCount, info.hasItemInfo = len(req.Items), true

	advice, err := h.PlateAdvice.Advise(r.Context(), req)
	if err != nil {
		aerr, gone := classifyPlateAdvice(err)
		if gone {
			info.errorCode = "CLIENT_CLOSED"
			w.WriteHeader(statusClientClosed)
			return
		}
		if aerr.Code == CodeInternalError {
			log.Error("plate advice failed unexpectedly", "error", err.Error())
		}
		if aerr.Code == CodeAIProviderUnavailable {
			w.Header().Set("Retry-After", "5")
		}
		writeAPIError(w, r, aerr)
		return
	}

	suggestions := make([]plateAdviceSuggestionDTO, 0, len(advice.Suggestions))
	for _, s := range advice.Suggestions {
		examples := s.Examples
		if examples == nil {
			examples = []string{}
		}
		suggestions = append(suggestions, plateAdviceSuggestionDTO{
			Action: s.Action, TargetGroup: s.TargetGroup, Title: s.Title, Reason: s.Reason, Examples: examples,
		})
	}
	writeJSON(w, http.StatusOK, plateAdviceResponseDTO{
		RequestID:   req.RequestID,
		Summary:     advice.Summary,
		Suggestions: suggestions,
	})
}

// validatePlateAdviceRequest wraps plateadvice.ValidateRequest, translating
// its error into the transport's apiError.
func validatePlateAdviceRequest(req plateadvice.Request) (plateadvice.Request, *apiError) {
	validated, err := plateadvice.ValidateRequest(req)
	if err == nil {
		return validated, nil
	}
	aerr, _ := classifyPlateAdvice(err)
	return plateadvice.Request{}, aerr
}

// classifyPlateAdvice maps an error from request validation or the plate
// advice use case to an API error. The bool is true when the client
// abandoned the request.
func classifyPlateAdvice(err error) (*apiError, bool) {
	var reqErr *plateadvice.RequestError
	switch {
	case errors.As(err, &reqErr):
		return newError(CodeInvalidRequest, reqErr.Error()), false
	case errors.Is(err, plateadvice.ErrNotEvaluable):
		return newError(CodeBalanceNotEvaluable), false
	default:
		return classify(err)
	}
}
