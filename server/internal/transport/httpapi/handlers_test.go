package httpapi_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"io"
	"log/slog"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"net/textproto"
	"regexp"
	"strings"
	"sync"
	"testing"
	"time"

	"example.com/calsnap/server/internal/app/analysis"
	"example.com/calsnap/server/internal/ratelimit"
	"example.com/calsnap/server/internal/testutil"
	"example.com/calsnap/server/internal/transport/httpapi"
)

const (
	safeID   = "0190f7a2-1b2c-7d3e-8f40-123456789abc"
	maxBytes = 1 << 20 // 1 MiB keeps oversize tests fast
)

// stubAnalyzer records requests and returns a scripted response or error.
type stubAnalyzer struct {
	mu   sync.Mutex
	reqs []analysis.Request
	resp analysis.Response
	err  error
	fn   func(analysis.Request) (analysis.Response, error)
}

func (s *stubAnalyzer) Analyze(_ context.Context, req analysis.Request) (analysis.Response, error) {
	s.mu.Lock()
	s.reqs = append(s.reqs, req)
	s.mu.Unlock()
	if s.fn != nil {
		return s.fn(req)
	}
	if s.err != nil {
		return analysis.Response{}, s.err
	}
	resp := s.resp
	resp.RequestID = req.RequestID
	return resp, nil
}

func (s *stubAnalyzer) last(t *testing.T) analysis.Request {
	t.Helper()
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.reqs) == 0 {
		t.Fatal("analyzer was not called")
	}
	return s.reqs[len(s.reqs)-1]
}

func (s *stubAnalyzer) calls() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.reqs)
}

type observer struct {
	mu          sync.Mutex
	statuses    []int
	rateLimited int
}

func (o *observer) ObserveRequest(_, _ string, status int, _ float64) {
	o.mu.Lock()
	defer o.mu.Unlock()
	o.statuses = append(o.statuses, status)
}

func (o *observer) RateLimited() {
	o.mu.Lock()
	defer o.mu.Unlock()
	o.rateLimited++
}

type env struct {
	handler  http.Handler
	analyzer *stubAnalyzer
	products *stubProducts
	obs      *observer
	logs     *bytes.Buffer
}

type envOpts struct {
	burst        int
	productBurst int
}

func newEnv(t *testing.T, opts ...func(*envOpts)) *env {
	t.Helper()
	o := envOpts{burst: 1000, productBurst: 1000}
	for _, f := range opts {
		f(&o)
	}
	an := &stubAnalyzer{resp: analysis.Response{Items: []analysis.ResponseItem{{
		ID: "temp-1", Name: "Rice", NormalizedName: "rice", EstimatedWeightG: 150, Confidence: 0.9,
		NutritionSource: analysis.SourceCatalog, Nutrition: analysis.Nutrition{Kcal: 130, Protein: 2.7, Fat: 0.3, Carbs: 28},
	}}, Warnings: []string{}}}
	obs := &observer{}
	logs := &bytes.Buffer{}
	log := slog.New(slog.NewJSONHandler(&syncWriter{w: logs}, &slog.HandlerOptions{Level: slog.LevelDebug}))
	lim := ratelimit.New(ratelimit.Config{PerMinute: 10, Burst: o.burst, MaxClients: 100, IdleTTL: time.Minute})
	productLim := ratelimit.New(ratelimit.Config{PerMinute: 10, Burst: o.productBurst, MaxClients: 100, IdleTTL: time.Minute})
	products := &stubProducts{}
	return &env{
		analyzer: an, products: products, obs: obs, logs: logs,
		handler: httpapi.NewHandler(httpapi.Deps{
			Analyzer: an, Limiter: lim, Observer: obs, Logger: log,
			Products: products, ProductLimiter: productLim,
			MaxUploadBytes: maxBytes, MaxImageDimensionPx: 4096,
			ClientConfig: httpapi.ClientConfig{ImageMaxLongSidePx: 1280, ImageJPEGQuality: 80, MaxUploadBytes: maxBytes, AnalyzeTimeoutSeconds: 60},
		}),
	}
}

type syncWriter struct {
	mu sync.Mutex
	w  io.Writer
}

func (s *syncWriter) Write(p []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.w.Write(p)
}

// multipartBody builds a multipart body; each part is {name, filename, content}.
type part struct{ name, filename, content string }

func buildBody(t *testing.T, parts ...part) (string, *bytes.Buffer) {
	t.Helper()
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	for _, p := range parts {
		h := textproto.MIMEHeader{}
		disp := fmt.Sprintf(`form-data; name="%s"`, p.name)
		if p.filename != "" {
			disp += fmt.Sprintf(`; filename="%s"`, p.filename)
			h.Set("Content-Type", "application/octet-stream")
		}
		h.Set("Content-Disposition", disp)
		w, err := mw.CreatePart(h)
		if err != nil {
			t.Fatal(err)
		}
		_, _ = io.WriteString(w, p.content)
	}
	if err := mw.Close(); err != nil {
		t.Fatal(err)
	}
	return mw.FormDataContentType(), &buf
}

func (e *env) post(t *testing.T, header map[string]string, parts ...part) *httptest.ResponseRecorder {
	t.Helper()
	ct, body := buildBody(t, parts...)
	req := httptest.NewRequestWithContext(context.Background(), http.MethodPost, "/v1/meals/analyze", body)
	req.Header.Set("Content-Type", ct)
	req.RemoteAddr = "203.0.113.10:4242"
	for k, v := range header {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	e.handler.ServeHTTP(rec, req)
	return rec
}

func imagePart(t *testing.T, fixture string) part {
	t.Helper()
	return part{name: "image", filename: fixture, content: string(testutil.Fixture(t, fixture))}
}

type errResp struct {
	Code      string `json:"code"`
	Message   string `json:"message"`
	RequestID string `json:"requestId"`
}

func decodeError(t *testing.T, rec *httptest.ResponseRecorder) errResp {
	t.Helper()
	var e errResp
	if err := json.Unmarshal(rec.Body.Bytes(), &e); err != nil {
		t.Fatalf("error body is not JSON: %v\n%s", err, rec.Body.String())
	}
	if e.RequestID == "" || e.RequestID != rec.Header().Get("X-Request-Id") {
		t.Errorf("requestId %q must equal the X-Request-Id header %q", e.RequestID, rec.Header().Get("X-Request-Id"))
	}
	return e
}

func expectError(t *testing.T, rec *httptest.ResponseRecorder, status int, code string) {
	t.Helper()
	if rec.Code != status {
		t.Fatalf("status = %d, want %d; body: %s", rec.Code, status, rec.Body.String())
	}
	if e := decodeError(t, rec); e.Code != code {
		t.Fatalf("code = %s, want %s", e.Code, code)
	}
}

func TestAnalyzeAcceptsSupportedFormats(t *testing.T) {
	t.Parallel()

	for _, fx := range []string{"sample.jpg", "sample.png", "sample.webp"} {
		t.Run(fx, func(t *testing.T) {
			t.Parallel()
			e := newEnv(t)
			rec := e.post(t, nil, imagePart(t, fx), part{name: "locale", content: "ru"})
			if rec.Code != http.StatusOK {
				t.Fatalf("status = %d: %s", rec.Code, rec.Body.String())
			}
			var body struct {
				RequestID string           `json:"requestId"`
				Items     []map[string]any `json:"items"`
				Warnings  []string         `json:"warnings"`
			}
			if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
				t.Fatal(err)
			}
			if body.RequestID == "" || len(body.Items) != 1 || body.Warnings == nil {
				t.Errorf("body = %s", rec.Body.String())
			}
			got := e.analyzer.last(t)
			wantMIME := map[string]string{"sample.jpg": "image/jpeg", "sample.png": "image/png", "sample.webp": "image/webp"}[fx]
			if got.Image.MIMEType != wantMIME || got.Image.Width != 64 || got.Image.Height != 48 || got.Locale != "ru" {
				t.Errorf("analysis request = %+v", got)
			}
		})
	}
}

func TestAnalyzeIgnoresDeclaredNameAndType(t *testing.T) {
	t.Parallel()

	e := newEnv(t)
	p := imagePart(t, "sample.png")
	p.filename = "photo.gif" // the file name must not matter
	if rec := e.post(t, nil, p); rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
}

func TestAnalyzeRejectsBadImages(t *testing.T) {
	t.Parallel()

	tall := new(bytes.Buffer)
	if err := png.Encode(tall, image.NewGray(image.Rect(0, 0, 5000, 4))); err != nil { // 5000 px wide, tiny file
		t.Fatal(err)
	}
	inner := image.NewNRGBA(image.Rect(0, 0, 2, 2))
	inner.Set(0, 0, color.White)
	small := new(bytes.Buffer)
	_ = png.Encode(small, inner)

	tests := []struct {
		name   string
		parts  []part
		status int
		code   string
	}{
		{"gif", []part{imagePart(t, "sample.gif")}, 415, "UNSUPPORTED_IMAGE_FORMAT"},
		{"arbitrary bytes", []part{{name: "image", filename: "x.jpg", content: "hello world, not an image"}}, 415, "UNSUPPORTED_IMAGE_FORMAT"},
		{"corrupt jpeg", []part{imagePart(t, "corrupt.jpg")}, 400, "INVALID_IMAGE"},
		{"missing image", []part{{name: "locale", content: "en"}}, 400, "INVALID_IMAGE"},
		{"empty image", []part{{name: "image", filename: "a.jpg", content: ""}}, 400, "INVALID_IMAGE"},
		{"two image parts", []part{imagePart(t, "sample.jpg"), imagePart(t, "sample.png")}, 400, "INVALID_IMAGE"},
		{"extra file part", []part{imagePart(t, "sample.jpg"), {name: "other", filename: "b.jpg", content: "zzz"}}, 400, "INVALID_IMAGE"},
		{"oversized dimensions", []part{{name: "image", filename: "wide.png", content: tall.String()}}, 413, "IMAGE_TOO_LARGE"},
		{"oversized body", []part{{name: "image", filename: "big.jpg", content: "\xff\xd8\xff" + strings.Repeat("A", 2*maxBytes)}}, 413, "IMAGE_TOO_LARGE"},
		{"image just over limit", []part{{name: "image", filename: "big.jpg", content: "\xff\xd8\xff" + strings.Repeat("A", maxBytes)}}, 413, "IMAGE_TOO_LARGE"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			e := newEnv(t)
			rec := e.post(t, nil, tt.parts...)
			expectError(t, rec, tt.status, tt.code)
			if e.analyzer.calls() != 0 {
				t.Error("rejected input must not reach the analyzer")
			}
		})
	}
}

func sidePart(t *testing.T, fixture string) part {
	t.Helper()
	p := imagePart(t, fixture)
	p.name = "sideImage"
	return p
}

func TestAnalyzeForwardsTheSideImage(t *testing.T) {
	t.Parallel()

	e := newEnv(t)
	rec := e.post(t, nil, imagePart(t, "sample.jpg"), sidePart(t, "sample.png"), part{name: "locale", content: "ru"})
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d: %s", rec.Code, rec.Body.String())
	}
	got := e.analyzer.last(t)
	if got.Image.MIMEType != "image/jpeg" {
		t.Errorf("main image = %+v", got.Image)
	}
	if got.SideImage == nil || got.SideImage.MIMEType != "image/png" || got.SideImage.Width != 64 || got.SideImage.Height != 48 {
		t.Errorf("side image = %+v", got.SideImage)
	}
}

func TestAnalyzeWithoutSideImageStaysSingle(t *testing.T) {
	t.Parallel()

	e := newEnv(t)
	if rec := e.post(t, nil, imagePart(t, "sample.jpg")); rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	if got := e.analyzer.last(t); got.SideImage != nil {
		t.Errorf("side image = %+v, want nil", got.SideImage)
	}
}

func TestAnalyzeRejectsBadSideImages(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name   string
		parts  []part
		status int
		code   string
	}{
		{"side without main", []part{sidePart(t, "sample.jpg")}, 400, "INVALID_IMAGE"},
		{"two side parts", []part{imagePart(t, "sample.jpg"), sidePart(t, "sample.jpg"), sidePart(t, "sample.png")}, 400, "INVALID_IMAGE"},
		{"empty side", []part{imagePart(t, "sample.jpg"), {name: "sideImage", filename: "s.jpg", content: ""}}, 400, "INVALID_IMAGE"},
		{"side gif", []part{imagePart(t, "sample.jpg"), sidePart(t, "sample.gif")}, 415, "UNSUPPORTED_IMAGE_FORMAT"},
		{"side corrupt", []part{imagePart(t, "sample.jpg"), sidePart(t, "corrupt.jpg")}, 400, "INVALID_IMAGE"},
		{"side over the limit", []part{imagePart(t, "sample.jpg"), {name: "sideImage", filename: "s.jpg", content: "ÿØÿ" + strings.Repeat("A", maxBytes)}}, 413, "IMAGE_TOO_LARGE"},
		{"a third file part", []part{imagePart(t, "sample.jpg"), sidePart(t, "sample.jpg"), {name: "other", filename: "c.jpg", content: "zzz"}}, 400, "INVALID_IMAGE"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			e := newEnv(t)
			expectError(t, e.post(t, nil, tt.parts...), tt.status, tt.code)
			if e.analyzer.calls() != 0 {
				t.Error("rejected input must not reach the analyzer")
			}
		})
	}
}

func TestAnalyzeAllowsTwoFullSizeImages(t *testing.T) {
	t.Parallel()

	// Each image may use the whole upload limit, so the body limit covers both.
	e := newEnv(t)
	main := imagePart(t, "sample.jpg")
	side := sidePart(t, "sample.jpg")
	pad := strings.Repeat("A", maxBytes-len(main.content)-10)
	main.content += pad
	side.content += pad
	if rec := e.post(t, nil, main, side); rec.Code != http.StatusOK {
		t.Fatalf("status = %d: %s", rec.Code, rec.Body.String())
	}
}

func TestAnalyzeRejectsWrongContentType(t *testing.T) {
	t.Parallel()

	e := newEnv(t)
	req := httptest.NewRequestWithContext(context.Background(), http.MethodPost, "/v1/meals/analyze", strings.NewReader(`{"image":"x"}`))
	req.Header.Set("Content-Type", "application/json")
	req.RemoteAddr = "203.0.113.10:1"
	rec := httptest.NewRecorder()
	e.handler.ServeHTTP(rec, req)
	expectError(t, rec, 400, "INVALID_REQUEST")
}

func TestAnalyzeContextValidation(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name       string
		fields     []part
		wantStatus int
		wantLocale string
		wantPlate  float64
	}{
		{"defaults", nil, 200, "en", 0},
		{"ru locale", []part{{name: "locale", content: "ru"}}, 200, "ru", 0},
		{"unknown locale falls back to en", []part{{name: "locale", content: "de"}}, 200, "en", 0},
		{"plate 26", []part{{name: "plateDiameterCm", content: "26"}}, 200, "en", 26},
		{"plate 10 inclusive", []part{{name: "plateDiameterCm", content: "10"}}, 200, "en", 10},
		{"plate 40 inclusive", []part{{name: "plateDiameterCm", content: "40.0"}}, 200, "en", 40},
		{"empty plate is absent", []part{{name: "plateDiameterCm", content: ""}}, 200, "en", 0},
		{"plate 120 rejected", []part{{name: "plateDiameterCm", content: "120"}}, 400, "", 0},
		{"plate 9.9 rejected", []part{{name: "plateDiameterCm", content: "9.9"}}, 400, "", 0},
		{"plate not a number", []part{{name: "plateDiameterCm", content: "abc"}}, 400, "", 0},
		{"plate NaN", []part{{name: "plateDiameterCm", content: "NaN"}}, 400, "", 0},
		{"plate Inf", []part{{name: "plateDiameterCm", content: "Inf"}}, 400, "", 0},
		{"oversized field", []part{{name: "locale", content: strings.Repeat("x", 100)}}, 400, "", 0},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			e := newEnv(t)
			rec := e.post(t, nil, append([]part{imagePart(t, "sample.jpg")}, tt.fields...)...)
			if rec.Code != tt.wantStatus {
				t.Fatalf("status = %d, want %d: %s", rec.Code, tt.wantStatus, rec.Body.String())
			}
			if tt.wantStatus != 200 {
				expectError(t, rec, 400, "INVALID_REQUEST")
				return
			}
			got := e.analyzer.last(t)
			if got.Locale != tt.wantLocale || got.PlateDiameterCm != tt.wantPlate {
				t.Errorf("locale=%q plate=%v", got.Locale, got.PlateDiameterCm)
			}
		})
	}
}

func TestRequestIDHandling(t *testing.T) {
	t.Parallel()

	uuidV7 := regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`)
	tests := []struct {
		name       string
		header     string
		wantEcho   bool
		wantClient bool
	}{
		{"safe id echoed", safeID, true, true},
		{"minimum length", "abcdefgh", true, true},
		{"too short", "abc", false, false},
		{"path traversal and markup", "../../etc<script>", false, false},
		{"too long", strings.Repeat("a", 65), false, false},
		{"missing", "", false, false},
		{"underscore not allowed", "abcd_efgh", false, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			e := newEnv(t)
			hdr := map[string]string{}
			if tt.header != "" {
				hdr["X-Request-Id"] = tt.header
			}
			rec := e.post(t, hdr, imagePart(t, "sample.jpg"))
			got := rec.Header().Get("X-Request-Id")
			var body struct {
				RequestID string `json:"requestId"`
			}
			_ = json.Unmarshal(rec.Body.Bytes(), &body)
			if body.RequestID != got {
				t.Errorf("body requestId %q != header %q", body.RequestID, got)
			}
			if tt.wantEcho {
				if got != tt.header {
					t.Errorf("id = %q, want echo of %q", got, tt.header)
				}
			} else if !uuidV7.MatchString(got) {
				t.Errorf("replacement id %q is not a UUIDv7", got)
			}
			req := e.analyzer.last(t)
			if (req.ClientRequestID != "") != tt.wantClient {
				t.Errorf("ClientRequestID = %q, want set=%v", req.ClientRequestID, tt.wantClient)
			}
			if !strings.Contains(e.logs.String(), `"request_id":"`+got+`"`) {
				t.Error("access log lacks the request id")
			}
		})
	}
}

func TestRequestIDOnErrors(t *testing.T) {
	t.Parallel()

	e := newEnv(t)
	rec := e.post(t, map[string]string{"X-Request-Id": safeID}, imagePart(t, "sample.gif"))
	expectError(t, rec, 415, "UNSUPPORTED_IMAGE_FORMAT")
	if got := decodeError(t, rec).RequestID; got != safeID {
		t.Errorf("error requestId = %q", got)
	}
}

func TestDomainErrorMapping(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name   string
		err    error
		status int
		code   string
	}{
		{"unavailable", fmt.Errorf("x: %w", analysis.ErrUnavailable), 503, "AI_PROVIDER_UNAVAILABLE"},
		{"deadline", context.DeadlineExceeded, 503, "AI_PROVIDER_UNAVAILABLE"},
		{"invalid response", fmt.Errorf("x: %w", analysis.ErrInvalidResponse), 502, "AI_INVALID_RESPONSE"},
		{"match failed", analysis.ErrMatchFailed, 502, "NUTRITION_MATCH_FAILED"},
		{"rejected", fmt.Errorf("http 400: %w", analysis.ErrRejected), 502, "IMAGE_ANALYSIS_FAILED"},
		{"unexpected", errors.New("secret internal detail: db password"), 500, "INTERNAL_ERROR"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			e := newEnv(t)
			e.analyzer.err = tt.err
			rec := e.post(t, nil, imagePart(t, "sample.jpg"))
			expectError(t, rec, tt.status, tt.code)
			if strings.Contains(rec.Body.String(), "secret") || strings.Contains(rec.Body.String(), "http 400") {
				t.Errorf("error body leaks details: %s", rec.Body.String())
			}
			if tt.code == "AI_PROVIDER_UNAVAILABLE" && rec.Header().Get("Retry-After") == "" {
				t.Error("503 should carry Retry-After")
			}
		})
	}
}

func TestClientCancellationIsNotAnError(t *testing.T) {
	t.Parallel()

	e := newEnv(t)
	e.analyzer.err = context.Canceled
	rec := e.post(t, nil, imagePart(t, "sample.jpg"))
	if rec.Code != 499 {
		t.Fatalf("status = %d, want 499", rec.Code)
	}
}

func TestPanicBecomesInternalError(t *testing.T) {
	t.Parallel()

	e := newEnv(t)
	e.analyzer.fn = func(analysis.Request) (analysis.Response, error) { panic("kaboom secret-value") }
	rec := e.post(t, map[string]string{"X-Request-Id": safeID}, imagePart(t, "sample.jpg"))
	expectError(t, rec, 500, "INTERNAL_ERROR")
	if strings.Contains(rec.Body.String(), "kaboom") {
		t.Error("panic value leaked to the client")
	}
	if decodeError(t, rec).Message != "Internal error." {
		t.Errorf("message = %q", decodeError(t, rec).Message)
	}
	if !strings.Contains(e.logs.String(), "panic while handling request") {
		t.Error("panic must be logged")
	}
	if got := e.obs.statuses; len(got) != 1 || got[0] != 500 {
		t.Errorf("observed statuses = %v", got)
	}
}

func TestUnknownRouteAndMethods(t *testing.T) {
	t.Parallel()

	e := newEnv(t)
	do := func(method, path string) *httptest.ResponseRecorder {
		req := httptest.NewRequestWithContext(context.Background(), method, path, nil)
		rec := httptest.NewRecorder()
		e.handler.ServeHTTP(rec, req)
		return rec
	}
	expectError(t, do(http.MethodGet, "/v1/unknown"), 404, "INVALID_REQUEST")
	expectError(t, do(http.MethodGet, "/"), 404, "INVALID_REQUEST")
	rec := do(http.MethodGet, "/v1/meals/analyze")
	expectError(t, rec, 405, "INVALID_REQUEST")
	if rec.Header().Get("Allow") != "POST" {
		t.Errorf("Allow = %q", rec.Header().Get("Allow"))
	}
	expectError(t, do(http.MethodPost, "/v1/config"), 405, "INVALID_REQUEST")
	expectError(t, do(http.MethodDelete, "/healthz"), 405, "INVALID_REQUEST")
}

func TestConfigAndHealth(t *testing.T) {
	t.Parallel()

	e := newEnv(t)
	rec := httptest.NewRecorder()
	e.handler.ServeHTTP(rec, httptest.NewRequestWithContext(context.Background(), http.MethodGet, "/v1/config", nil))
	if rec.Code != 200 {
		t.Fatalf("status = %d", rec.Code)
	}
	var got map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	want := map[string]any{"imageMaxLongSidePx": 1280.0, "imageJpegQuality": 80.0, "maxUploadBytes": float64(maxBytes), "analyzeTimeoutSeconds": 60.0, "maxImages": 2.0, "barcodeLookup": true}
	if fmt.Sprint(got) != fmt.Sprint(want) {
		t.Errorf("config = %v, want %v", got, want)
	}
	for k := range got {
		if strings.Contains(strings.ToLower(k), "model") || strings.Contains(strings.ToLower(k), "provider") {
			t.Errorf("config exposes %q", k)
		}
	}

	rec = httptest.NewRecorder()
	e.handler.ServeHTTP(rec, httptest.NewRequestWithContext(context.Background(), http.MethodGet, "/healthz", nil))
	if rec.Code != 200 || !strings.Contains(rec.Body.String(), `"ok"`) {
		t.Errorf("healthz = %d %s", rec.Code, rec.Body.String())
	}
}

func TestRateLimiting(t *testing.T) {
	t.Parallel()

	e := newEnv(t, func(o *envOpts) { o.burst = 3 })
	var statuses []int
	var retryAfter string
	for i := range 5 {
		// Varying X-Forwarded-For from an untrusted peer must not help.
		rec := e.post(t, map[string]string{"X-Forwarded-For": fmt.Sprintf("1.2.3.%d", i)}, imagePart(t, "sample.jpg"))
		statuses = append(statuses, rec.Code)
		if rec.Code == 429 {
			retryAfter = rec.Header().Get("Retry-After")
			expectError(t, rec, 429, "RATE_LIMITED")
		}
	}
	if fmt.Sprint(statuses) != "[200 200 200 429 429]" {
		t.Errorf("statuses = %v", statuses)
	}
	if retryAfter == "" || retryAfter == "0" {
		t.Errorf("Retry-After = %q", retryAfter)
	}
	if e.obs.rateLimited != 2 {
		t.Errorf("rate limited metric = %d", e.obs.rateLimited)
	}
	if e.analyzer.calls() != 3 {
		t.Errorf("analyzer calls = %d, want 3", e.analyzer.calls())
	}
}

func TestResponsesAreNotCacheable(t *testing.T) {
	t.Parallel()

	e := newEnv(t)
	rec := e.post(t, nil, imagePart(t, "sample.jpg"))
	if rec.Header().Get("Cache-Control") != "no-store" || rec.Header().Get("X-Content-Type-Options") != "nosniff" {
		t.Errorf("headers = %v", rec.Header())
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
		t.Errorf("content type = %q", ct)
	}
}
