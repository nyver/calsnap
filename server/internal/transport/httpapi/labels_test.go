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

	"example.com/calsnap/server/internal/app/analysis"
	"example.com/calsnap/server/internal/app/label"
	"example.com/calsnap/server/internal/ratelimit"
	"example.com/calsnap/server/internal/testutil"
	"example.com/calsnap/server/internal/transport/httpapi"
)

func fptr(v float64) *float64 { return &v }

// stubLabels records requests and returns a scripted result or error.
type stubLabels struct {
	mu   sync.Mutex
	reqs []label.Request
	err  error
}

func (s *stubLabels) Read(_ context.Context, req label.Request) (label.Result, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.reqs = append(s.reqs, req)
	if s.err != nil {
		return label.Result{}, s.err
	}
	return label.Result{
		Name:      "Spread",
		Nutrition: label.Nutrition{Kcal: fptr(220), Protein: fptr(8.4), Fat: fptr(12.1), Carbs: fptr(18.2)},
	}, nil
}

func (s *stubLabels) setErr(err error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.err = err
}

func (s *stubLabels) last(t *testing.T) label.Request {
	t.Helper()
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.reqs) == 0 {
		t.Fatal("the label reader was not called")
	}
	return s.reqs[len(s.reqs)-1]
}

func (e *env) postLabel(t *testing.T, header map[string]string, parts ...part) *httptest.ResponseRecorder {
	t.Helper()
	ct, body := buildBody(t, parts...)
	req := httptest.NewRequestWithContext(context.Background(), http.MethodPost, "/v1/labels/analyze", body)
	req.Header.Set("Content-Type", ct)
	req.RemoteAddr = "203.0.113.10:4242"
	for k, v := range header {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	e.handler.ServeHTTP(rec, req)
	return rec
}

func TestLabelReturnsValuesPer100g(t *testing.T) {
	t.Parallel()

	e := newEnv(t)
	rec := e.postLabel(t, nil, imagePart(t, "sample.jpg"), part{name: "locale", content: "ru"})
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d: %s", rec.Code, rec.Body.String())
	}
	var body struct {
		RequestID string             `json:"requestId"`
		Name      string             `json:"name"`
		Nutrition map[string]float64 `json:"nutrition"`
		Warnings  []string           `json:"warnings"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.RequestID != rec.Header().Get("X-Request-Id") || body.Name != "Spread" || body.Warnings == nil ||
		body.Nutrition["kcalPer100g"] != 220 || body.Nutrition["carbsPer100g"] != 18.2 {
		t.Errorf("body = %s", rec.Body.String())
	}
	validateAgainstOpenAPI(t, "LabelResponse", mustJSON(t, rec.Body.Bytes()))
	got := e.labels.last(t)
	if got.Locale != "ru" || got.Image.MIMEType != "image/jpeg" || got.Image.Width != 64 || got.RequestID == "" {
		t.Errorf("request = %+v", got)
	}
}

func TestLabelRejectsBadInput(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name   string
		parts  []part
		status int
		code   string
	}{
		{"no image", []part{{name: "locale", content: "en"}}, 400, "INVALID_IMAGE"},
		{"gif", []part{imagePart(t, "sample.gif")}, 415, "UNSUPPORTED_IMAGE_FORMAT"},
		{"corrupt", []part{imagePart(t, "corrupt.jpg")}, 400, "INVALID_IMAGE"},
		{"oversized", []part{{name: "image", filename: "big.jpg", content: "\xff\xd8\xff" + strings.Repeat("A", 2*maxBytes)}}, 413, "IMAGE_TOO_LARGE"},
		{"a side image makes no sense", []part{imagePart(t, "sample.jpg"), sidePart(t, "sample.jpg")}, 400, "INVALID_REQUEST"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			e := newEnv(t)
			expectError(t, e.postLabel(t, nil, tt.parts...), tt.status, tt.code)
			if len(e.labels.reqs) != 0 {
				t.Error("rejected input must not reach the reader")
			}
		})
	}
}

func TestLabelErrors(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		err     error
		status  int
		code    string
		fixture string
	}{
		{"no table", label.ErrNotRecognized, 422, "LABEL_NOT_RECOGNIZED", "error-LABEL_NOT_RECOGNIZED.json"},
		{"provider down", analysis.ErrUnavailable, 503, "AI_PROVIDER_UNAVAILABLE", "error-AI_PROVIDER_UNAVAILABLE.json"},
		{"provider garbage", analysis.ErrInvalidResponse, 502, "AI_INVALID_RESPONSE", "error-AI_INVALID_RESPONSE.json"},
		{"provider refuses", analysis.ErrRejected, 502, "IMAGE_ANALYSIS_FAILED", "error-IMAGE_ANALYSIS_FAILED.json"},
		{"bug", errors.New("boom"), 500, "INTERNAL_ERROR", "error-INTERNAL_ERROR.json"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			e := newEnv(t)
			e.labels.setErr(tt.err)
			rec := e.postLabel(t, map[string]string{"X-Request-Id": safeID}, imagePart(t, "sample.jpg"))
			expectError(t, rec, tt.status, tt.code)
			validateAgainstOpenAPI(t, "Error", mustJSON(t, rec.Body.Bytes()))
			var got, want errResp
			_ = json.Unmarshal(rec.Body.Bytes(), &got)
			_ = json.Unmarshal(testutil.Fixture(t, tt.fixture), &want)
			if got != want {
				t.Errorf("got %+v, fixture %+v", got, want)
			}
			if tt.status == 503 && rec.Header().Get("Retry-After") == "" {
				t.Error("an unavailable provider should say when to come back")
			}
		})
	}
}

func TestLabelAbandonedRequestsAreNotAnswered(t *testing.T) {
	t.Parallel()

	e := newEnv(t)
	e.labels.setErr(context.Canceled)
	rec := e.postLabel(t, nil, imagePart(t, "sample.jpg"))
	if rec.Code != 499 || rec.Body.Len() != 0 {
		t.Errorf("status = %d, body %q", rec.Code, rec.Body.String())
	}
}

func TestLabelSharesTheAnalysisRateLimit(t *testing.T) {
	t.Parallel()

	e := newEnv(t, func(o *envOpts) { o.burst = 1 })
	if rec := e.postLabel(t, nil, imagePart(t, "sample.jpg")); rec.Code != 200 {
		t.Fatalf("first: %d", rec.Code)
	}
	rec := e.postLabel(t, nil, imagePart(t, "sample.jpg"))
	expectError(t, rec, 429, "RATE_LIMITED")
	if rec.Header().Get("Retry-After") == "" {
		t.Error("Retry-After is missing")
	}
}

func TestLabelRouteExistsOnlyWhenEnabled(t *testing.T) {
	t.Parallel()

	off := httpapi.NewHandler(plainDeps(nil))
	if rec := serve(off, http.MethodPost, "/v1/labels/analyze", nil); rec.Code != http.StatusNotFound {
		t.Errorf("disabled: status %d", rec.Code)
	}
	var cfg map[string]any
	if err := json.Unmarshal(serve(off, http.MethodGet, "/v1/config", nil).Body.Bytes(), &cfg); err != nil {
		t.Fatal(err)
	}
	if cfg["labelReading"] != false {
		t.Errorf("labelReading = %v, want false", cfg["labelReading"])
	}

	e := newEnv(t)
	expectError(t, serve(e.handler, http.MethodGet, "/v1/labels/analyze", nil), 405, "INVALID_REQUEST")
}

// scriptedLabels answers with a fixed extraction, like scriptedVision does.
type scriptedLabels struct{ ext label.Extraction }

func (s scriptedLabels) ReadLabel(context.Context, analysis.Image, analysis.RequestContext) (label.Extraction, error) {
	return s.ext, nil
}

// TestLabelMatchesProtocolFixtures runs the whole pipeline (handler, use case,
// normalization) with scripted provider output and compares the response with
// the shared fixtures that the client tests also consume.
func TestLabelMatchesProtocolFixtures(t *testing.T) {
	t.Parallel()

	tests := []struct{ ai, response string }{
		{"ai-label-per100g.json", "label-response-per100g.json"},
		{"ai-label-per-serving.json", "label-response-per-serving.json"},
		{"ai-label-partial.json", "label-response-partial.json"},
	}
	for _, tt := range tests {
		t.Run(tt.response, func(t *testing.T) {
			t.Parallel()
			ext, err := label.ParseExtraction(testutil.Fixture(t, tt.ai))
			if err != nil {
				t.Fatal(err)
			}
			svc := label.NewService(label.Config{
				ProviderName: "test", CallTimeout: 5 * time.Second, OverallTimeout: 10 * time.Second, MaxConcurrent: 2, QueueWait: 10 * time.Millisecond,
			}, label.Deps{Reader: scriptedLabels{ext: ext}})
			deps := plainDeps(nil)
			deps.Labels = svc
			deps.Limiter = ratelimit.New(ratelimit.Config{PerMinute: 600, Burst: 100, MaxClients: 10, IdleTTL: time.Minute})
			deps.Logger = slog.New(slog.DiscardHandler)
			h := httpapi.NewHandler(deps)

			ct, body := buildBody(t, imagePart(t, "sample.jpg"))
			req := httptest.NewRequestWithContext(context.Background(), http.MethodPost, "/v1/labels/analyze", body)
			req.Header.Set("Content-Type", ct)
			req.Header.Set("X-Request-Id", safeID)
			req.RemoteAddr = "203.0.113.10:1"
			rec := httptest.NewRecorder()
			h.ServeHTTP(rec, req)
			if rec.Code != 200 {
				t.Fatalf("status = %d: %s", rec.Code, rec.Body.String())
			}
			got, want := mustJSON(t, rec.Body.Bytes()), mustJSON(t, testutil.Fixture(t, tt.response))
			if !reflect.DeepEqual(got, want) {
				t.Errorf("response differs from the fixture\n got: %s\nwant: %s", rec.Body.String(), testutil.Fixture(t, tt.response))
			}
			validateAgainstOpenAPI(t, "LabelResponse", got)
		})
	}

	t.Run("a photo without a table", func(t *testing.T) {
		t.Parallel()
		ext, err := label.ParseExtraction(testutil.Fixture(t, "ai-label-not-found.json"))
		if err != nil {
			t.Fatal(err)
		}
		deps := plainDeps(nil)
		deps.Labels = label.NewService(label.Config{CallTimeout: time.Second, OverallTimeout: 2 * time.Second, MaxConcurrent: 1, QueueWait: time.Millisecond},
			label.Deps{Reader: scriptedLabels{ext: ext}})
		deps.Limiter = ratelimit.New(ratelimit.Config{PerMinute: 600, Burst: 100, MaxClients: 10, IdleTTL: time.Minute})
		h := httpapi.NewHandler(deps)
		ct, body := buildBody(t, imagePart(t, "sample.jpg"))
		req := httptest.NewRequestWithContext(context.Background(), http.MethodPost, "/v1/labels/analyze", body)
		req.Header.Set("Content-Type", ct)
		req.Header.Set("X-Request-Id", safeID)
		req.RemoteAddr = "203.0.113.10:1"
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		expectError(t, rec, 422, "LABEL_NOT_RECOGNIZED")
	})
}

func TestLabelLogsContainNoContent(t *testing.T) {
	t.Parallel()

	e := newEnv(t)
	e.postLabel(t, nil, imagePart(t, "sample.jpg"))
	e.labels.setErr(analysis.ErrUnavailable)
	e.postLabel(t, nil, imagePart(t, "sample.jpg"))

	out := e.logs.String()
	if !strings.Contains(out, `"route":"/v1/labels/analyze"`) {
		t.Fatalf("expected access log records, got:\n%s", out)
	}
	for _, needle := range []string{"Spread", "kcal", "220", "sample.jpg"} {
		if strings.Contains(out, needle) {
			t.Errorf("logs contain %q:\n%s", needle, out)
		}
	}
}
