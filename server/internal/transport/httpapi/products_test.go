package httpapi_test

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	"example.com/calsnap/server/internal/app/product"
	"example.com/calsnap/server/internal/ratelimit"
	"example.com/calsnap/server/internal/testutil"
	"example.com/calsnap/server/internal/transport/httpapi"
)

const yogurtCode = "4006381333931"

// yogurt mirrors protocol/fixtures/product-response.json.
var yogurt = product.Product{
	Barcode: yogurtCode, Name: "Plain yogurt", Brand: "Danone", ServingSizeG: 150,
	Nutrition: product.Nutrition{Kcal: 61, Protein: 3.5, Fat: 2.1, Carbs: 7.6},
}

type lookupCall struct{ barcode, locale string }

// stubProducts records lookups and returns a scripted product or error.
type stubProducts struct {
	mu    sync.Mutex
	calls []lookupCall
	err   error
	bare  bool
}

func (s *stubProducts) Lookup(_ context.Context, barcode, locale string) (product.Product, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.calls = append(s.calls, lookupCall{barcode, locale})
	if s.err != nil {
		return product.Product{}, s.err
	}
	if s.bare {
		return product.Product{Barcode: barcode, Name: "Water"}, nil
	}
	return yogurt, nil
}

func (s *stubProducts) last(t *testing.T) lookupCall {
	t.Helper()
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.calls) == 0 {
		t.Fatal("the lookup was not called")
	}
	return s.calls[len(s.calls)-1]
}

func (s *stubProducts) setErr(err error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.err = err
}

func serve(h http.Handler, method, target string, header map[string]string) *httptest.ResponseRecorder {
	req := httptest.NewRequestWithContext(context.Background(), method, target, http.NoBody)
	req.RemoteAddr = "203.0.113.10:4242"
	for k, v := range header {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func (e *env) get(target string, header map[string]string) *httptest.ResponseRecorder {
	return serve(e.handler, http.MethodGet, target, header)
}

func plainDeps(products httpapi.ProductLookup) httpapi.Deps {
	return httpapi.Deps{
		Analyzer: &stubAnalyzer{}, Observer: &observer{}, Logger: slog.New(slog.DiscardHandler),
		Limiter:        ratelimit.New(ratelimit.Config{PerMinute: 10, Burst: 3, MaxClients: 1, IdleTTL: time.Minute}),
		Products:       products,
		MaxUploadBytes: maxBytes, MaxImageDimensionPx: 4096,
	}
}

func TestProductMatchesTheProtocolFixture(t *testing.T) {
	t.Parallel()

	e := newEnv(t)
	rec := e.get("/v1/products/"+yogurtCode+"?locale=ru", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d: %s", rec.Code, rec.Body.String())
	}
	got, want := mustJSON(t, rec.Body.Bytes()), mustJSON(t, testutil.Fixture(t, "product-response.json"))
	if !reflect.DeepEqual(got, want) {
		t.Errorf("response differs from the fixture\n got: %s\nwant: %s", rec.Body.String(), testutil.Fixture(t, "product-response.json"))
	}
	validateAgainstOpenAPI(t, "Product", got)
	if call := e.products.last(t); call.barcode != yogurtCode || call.locale != "ru" {
		t.Errorf("lookup = %+v", call)
	}
	if rec.Header().Get("X-Request-Id") == "" {
		t.Error("the request id header is missing")
	}
}

func TestProductOptionalFieldsAreOmitted(t *testing.T) {
	t.Parallel()

	e := newEnv(t)
	e.products.bare = true
	rec := e.get("/v1/products/"+yogurtCode, nil)
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"brand", "servingSizeG"} {
		if _, ok := body[key]; ok {
			t.Errorf("%s must be omitted when unknown: %v", key, body)
		}
	}
	validateAgainstOpenAPI(t, "Product", mustJSON(t, rec.Body.Bytes()))
	if got := e.products.last(t).locale; got != "en" {
		t.Errorf("default locale = %q", got)
	}
}

func TestProductErrors(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		err     error
		status  int
		code    string
		fixture string
	}{
		{"invalid barcode", product.ErrInvalidBarcode, 400, "INVALID_REQUEST", ""},
		{"not found", product.ErrNotFound, 404, "PRODUCT_NOT_FOUND", "error-PRODUCT_NOT_FOUND.json"},
		{"source down", product.ErrUnavailable, 503, "PRODUCT_SOURCE_UNAVAILABLE", "error-PRODUCT_SOURCE_UNAVAILABLE.json"},
		{"source too slow", context.DeadlineExceeded, 503, "PRODUCT_SOURCE_UNAVAILABLE", ""},
		{"wrapped errors still map", errors.Join(errors.New("ctx"), product.ErrNotFound), 404, "PRODUCT_NOT_FOUND", ""},
		{"anything else", errors.New("boom"), 500, "INTERNAL_ERROR", ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			e := newEnv(t)
			e.products.setErr(tt.err)
			rec := e.get("/v1/products/"+yogurtCode, map[string]string{"X-Request-Id": safeID})
			expectError(t, rec, tt.status, tt.code)
			validateAgainstOpenAPI(t, "Error", mustJSON(t, rec.Body.Bytes()))
			if tt.fixture != "" {
				var got, want errResp
				_ = json.Unmarshal(rec.Body.Bytes(), &got)
				_ = json.Unmarshal(testutil.Fixture(t, tt.fixture), &want)
				if got != want {
					t.Errorf("got %+v, fixture %+v", got, want)
				}
			}
			if tt.status == 503 && rec.Header().Get("Retry-After") == "" {
				t.Error("an unavailable source should say when to come back")
			}
		})
	}
}

func TestProductAbandonedRequestsAreNotAnswered(t *testing.T) {
	t.Parallel()

	e := newEnv(t)
	e.products.setErr(context.Canceled)
	rec := e.get("/v1/products/"+yogurtCode, nil)
	if rec.Code != 499 || rec.Body.Len() != 0 {
		t.Errorf("status = %d, body %q", rec.Code, rec.Body.String())
	}
}

func TestProductsHaveTheirOwnRateLimit(t *testing.T) {
	t.Parallel()

	e := newEnv(t, func(o *envOpts) { o.productBurst = 2; o.burst = 1 })
	for i := range 2 {
		if rec := e.get("/v1/products/"+yogurtCode, nil); rec.Code != 200 {
			t.Fatalf("lookup %d: status %d", i+1, rec.Code)
		}
	}
	rec := e.get("/v1/products/"+yogurtCode, nil)
	expectError(t, rec, 429, "RATE_LIMITED")
	if rec.Header().Get("Retry-After") == "" {
		t.Error("Retry-After is missing")
	}
	// The analysis bucket is untouched by lookups.
	if rec := e.post(t, nil, imagePart(t, "sample.jpg")); rec.Code != 200 {
		t.Errorf("analysis after lookups: %d", rec.Code)
	}
}

func TestProductRouteExistsOnlyWhenEnabled(t *testing.T) {
	t.Parallel()

	off := httpapi.NewHandler(plainDeps(nil))
	if rec := serve(off, http.MethodGet, "/v1/products/"+yogurtCode, nil); rec.Code != http.StatusNotFound {
		t.Errorf("disabled lookup: status %d", rec.Code)
	}
	var cfg map[string]any
	if err := json.Unmarshal(serve(off, http.MethodGet, "/v1/config", nil).Body.Bytes(), &cfg); err != nil {
		t.Fatal(err)
	}
	if cfg["barcodeLookup"] != false {
		t.Errorf("barcodeLookup = %v, want false", cfg["barcodeLookup"])
	}

	on := httpapi.NewHandler(plainDeps(&stubProducts{}))
	if rec := serve(on, http.MethodGet, "/v1/products/"+yogurtCode, nil); rec.Code != http.StatusOK {
		t.Errorf("enabled lookup without a limiter: status %d", rec.Code)
	}
}

func TestProductRejectsOtherMethods(t *testing.T) {
	t.Parallel()

	e := newEnv(t)
	rec := serve(e.handler, http.MethodPost, "/v1/products/"+yogurtCode, nil)
	expectError(t, rec, 405, "INVALID_REQUEST")
}

func TestLogsNeverContainTheBarcode(t *testing.T) {
	t.Parallel()

	e := newEnv(t)
	e.get("/v1/products/"+yogurtCode, nil)
	e.products.setErr(product.ErrNotFound)
	e.get("/v1/products/"+yogurtCode, nil)
	e.products.setErr(errors.New("boom"))
	e.get("/v1/products/"+yogurtCode, nil)

	out := e.logs.String()
	if !strings.Contains(out, `"route":"/v1/products/{barcode}"`) {
		t.Fatalf("expected access log records with the route pattern, got:\n%s", out)
	}
	for _, needle := range []string{yogurtCode, "Plain yogurt", "Danone"} {
		if strings.Contains(out, needle) {
			t.Errorf("logs contain %q:\n%s", needle, out)
		}
	}
}
