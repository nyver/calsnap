package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strconv"

	"example.com/calsnap/server/internal/app/analysis"
	"example.com/calsnap/server/internal/app/product"
	"example.com/calsnap/server/internal/ratelimit"
)

// ProductLookup is the use case consumed by the product endpoint.
type ProductLookup interface {
	Lookup(ctx context.Context, barcode, locale string) (product.Product, error)
}

// productSource is reported with every product so that clients can credit it.
const productSource = "openfoodfacts"

type productDTO struct {
	Barcode      string       `json:"barcode"`
	Name         string       `json:"name"`
	Brand        string       `json:"brand,omitempty"`
	ServingSizeG float64      `json:"servingSizeG,omitempty"`
	Nutrition    nutritionDTO `json:"nutrition"`
	Source       string       `json:"source"`
}

// product handles GET /v1/products/{barcode}.
//
// NOTE: the barcode is deliberately absent from logs: it reveals what someone
// eats. The access log records the route pattern, not the path.
func (h *handlers) product(w http.ResponseWriter, r *http.Request) {
	if h.ProductLimiter != nil {
		if ok, retry := h.ProductLimiter.Allow(ratelimit.ClientKey(r, h.TrustedProxies)); !ok {
			h.Observer.RateLimited()
			w.Header().Set("Retry-After", strconv.Itoa(ratelimit.RetryAfterSeconds(retry)))
			writeAPIError(w, r, newError(CodeRateLimited))
			return
		}
	}

	locale := analysis.LocaleEN
	if r.URL.Query().Get("locale") == analysis.LocaleRU {
		locale = analysis.LocaleRU
	}
	p, err := h.Products.Lookup(r.Context(), r.PathValue("barcode"), locale)
	if err != nil {
		aerr, gone := classifyProduct(err)
		if gone {
			infoFrom(r.Context()).errorCode = "CLIENT_CLOSED"
			w.WriteHeader(statusClientClosed)
			return
		}
		if aerr.Code == CodeInternalError {
			h.Logger.With("request_id", requestIDFrom(r.Context())).Error("product lookup failed unexpectedly", "error", err.Error())
		}
		if aerr.Code == CodeProductSourceUnavailable {
			w.Header().Set("Retry-After", "5")
		}
		writeAPIError(w, r, aerr)
		return
	}
	writeJSON(w, http.StatusOK, productDTO{
		Barcode:      p.Barcode,
		Name:         p.Name,
		Brand:        p.Brand,
		ServingSizeG: p.ServingSizeG,
		Nutrition: nutritionDTO{
			KcalPer100g:    p.Nutrition.Kcal,
			ProteinPer100g: p.Nutrition.Protein,
			FatPer100g:     p.Nutrition.Fat,
			CarbsPer100g:   p.Nutrition.Carbs,
		},
		Source: productSource,
	})
}

// classifyProduct maps an error from the lookup use case to an API error. The
// bool is true when the client abandoned the request.
func classifyProduct(err error) (*apiError, bool) {
	switch {
	case errors.Is(err, product.ErrInvalidBarcode):
		return newError(CodeInvalidRequest, "barcode must be 8, 12, 13 or 14 digits with a valid check digit."), false
	case errors.Is(err, product.ErrNotFound):
		return newError(CodeProductNotFound), false
	case errors.Is(err, context.Canceled):
		return nil, true
	case errors.Is(err, product.ErrUnavailable), errors.Is(err, context.DeadlineExceeded):
		return newError(CodeProductSourceUnavailable), false
	default:
		return newError(CodeInternalError), false
	}
}
