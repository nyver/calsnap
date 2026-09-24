package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strconv"

	"example.com/calsnap/server/internal/app/analysis"
	"example.com/calsnap/server/internal/app/label"
	"example.com/calsnap/server/internal/ratelimit"
)

// LabelReader is the use case consumed by the label endpoint.
type LabelReader interface {
	Read(ctx context.Context, req label.Request) (label.Result, error)
}

type labelResponseDTO struct {
	RequestID    string            `json:"requestId"`
	Name         string            `json:"name,omitempty"`
	ServingSizeG float64           `json:"servingSizeG,omitempty"`
	Nutrition    labelNutritionDTO `json:"nutrition"`
	Warnings     []string          `json:"warnings"`
}

// labelNutritionDTO carries values per 100 g; a value the table did not show
// is absent, never zero.
type labelNutritionDTO struct {
	KcalPer100g    *float64 `json:"kcalPer100g,omitempty"`
	ProteinPer100g *float64 `json:"proteinPer100g,omitempty"`
	FatPer100g     *float64 `json:"fatPer100g,omitempty"`
	CarbsPer100g   *float64 `json:"carbsPer100g,omitempty"`
}

// label handles POST /v1/labels/analyze: one photo of a nutrition facts table.
// It shares the analysis rate limit because it costs the same AI call.
func (h *handlers) label(w http.ResponseWriter, r *http.Request) {
	log := h.Logger.With("request_id", requestIDFrom(r.Context()))
	info := infoFrom(r.Context())

	if ok, retry := h.Limiter.Allow(ratelimit.ClientKey(r, h.TrustedProxies)); !ok {
		h.Observer.RateLimited()
		w.Header().Set("Retry-After", strconv.Itoa(ratelimit.RetryAfterSeconds(retry)))
		writeAPIError(w, r, newError(CodeRateLimited))
		return
	}
	form, aerr := h.readForm(w, r)
	if aerr != nil {
		writeAPIError(w, r, aerr)
		return
	}
	if form.sideImage != nil {
		writeAPIError(w, r, newError(CodeInvalidRequest, "sideImage is not accepted for labels."))
		return
	}
	info.imageBytes = len(form.image)
	locale, _, aerr := parseContext(form.locale, "")
	if aerr != nil {
		writeAPIError(w, r, aerr)
		return
	}
	img, aerr := inspectImage(form.image, h.MaxImageDimensionPx)
	if aerr != nil {
		writeAPIError(w, r, aerr)
		return
	}

	res, err := h.Labels.Read(r.Context(), label.Request{
		Image:     analysis.Image{Data: form.image, MIMEType: img.mime, Width: img.width, Height: img.height},
		Locale:    locale,
		RequestID: requestIDFrom(r.Context()),
	})
	if err != nil {
		aerr, gone := classifyLabel(err)
		if gone {
			info.errorCode = "CLIENT_CLOSED"
			w.WriteHeader(statusClientClosed)
			return
		}
		if aerr.Code == CodeInternalError {
			log.Error("label reading failed unexpectedly", "error", err.Error())
		}
		if aerr.Code == CodeAIProviderUnavailable {
			w.Header().Set("Retry-After", "5")
		}
		writeAPIError(w, r, aerr)
		return
	}

	warnings := res.Warnings
	if warnings == nil {
		warnings = []string{}
	}
	writeJSON(w, http.StatusOK, labelResponseDTO{
		RequestID:    requestIDFrom(r.Context()),
		Name:         res.Name,
		ServingSizeG: res.ServingSizeG,
		Nutrition: labelNutritionDTO{
			KcalPer100g:    res.Nutrition.Kcal,
			ProteinPer100g: res.Nutrition.Protein,
			FatPer100g:     res.Nutrition.Fat,
			CarbsPer100g:   res.Nutrition.Carbs,
		},
		Warnings: warnings,
	})
}

// classifyLabel maps an error from the label use case to an API error. The
// bool is true when the client abandoned the request.
func classifyLabel(err error) (*apiError, bool) {
	if errors.Is(err, label.ErrNotRecognized) {
		return newError(CodeLabelNotRecognized), false
	}
	return classify(err)
}
