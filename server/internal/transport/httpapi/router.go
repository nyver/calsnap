package httpapi

import (
	"net/http"
	"time"
)

// NewHandler builds the HTTP handler for the public API.
func NewHandler(d Deps) http.Handler {
	if d.Now == nil {
		d.Now = time.Now
	}
	h := &handlers{Deps: d}

	mux := http.NewServeMux()
	mux.HandleFunc("POST /v1/meals/analyze", h.analyze)
	mux.HandleFunc("/v1/meals/analyze", methodNotAllowed(http.MethodPost))
	if d.Products != nil {
		mux.HandleFunc("GET /v1/products/{barcode}", h.product)
		mux.HandleFunc("/v1/products/{barcode}", methodNotAllowed(http.MethodGet+", "+http.MethodHead))
	}
	mux.HandleFunc("GET /v1/config", h.config)
	mux.HandleFunc("/v1/config", methodNotAllowed(http.MethodGet+", "+http.MethodHead))
	mux.HandleFunc("GET /healthz", h.healthz)
	mux.HandleFunc("/healthz", methodNotAllowed(http.MethodGet+", "+http.MethodHead))
	mux.HandleFunc("/", notFound)

	// Outermost first: request id, then logging/metrics, then panic recovery.
	var handler http.Handler = mux
	handler = recoverMiddleware(d.Logger, handler)
	handler = observeMiddleware(d.Logger, d.Observer, d.Now, handler)
	handler = requestIDMiddleware(handler)
	return handler
}
