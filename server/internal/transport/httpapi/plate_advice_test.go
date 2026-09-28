package httpapi_test

import (
	"bytes"
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"example.com/calsnap/server/internal/app/analysis"
	"example.com/calsnap/server/internal/app/plateadvice"
	"example.com/calsnap/server/internal/ratelimit"
	"example.com/calsnap/server/internal/testutil"
	"example.com/calsnap/server/internal/transport/httpapi"
	"example.com/calsnap/server/internal/vision/gemini"
)

func mustUnmarshal(t *testing.T, data []byte, v any) {
	t.Helper()
	if err := json.Unmarshal(data, v); err != nil {
		t.Fatal(err)
	}
}

func mustMarshal(t *testing.T, v any) []byte {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

// setPath sets a dotted path (map keys or, for a slice, numeric indices) to
// value, mutating the decoded JSON tree in place.
func setPath(root map[string]any, path string, value any) {
	segs := strings.Split(path, ".")
	var cur any = root
	for i := 0; i < len(segs)-1; i++ {
		switch c := cur.(type) {
		case map[string]any:
			cur = c[segs[i]]
		case []any:
			idx, _ := strconv.Atoi(segs[i])
			cur = c[idx]
		}
	}
	last := segs[len(segs)-1]
	switch c := cur.(type) {
	case map[string]any:
		c[last] = value
	case []any:
		idx, _ := strconv.Atoi(last)
		c[idx] = value
	}
}

// stubPlateAdviser records requests and returns a scripted advice or error.
type stubPlateAdviser struct {
	mu   sync.Mutex
	reqs []plateadvice.Request
	resp plateadvice.Advice
	err  error
}

func (s *stubPlateAdviser) Advise(_ context.Context, req plateadvice.Request) (plateadvice.Advice, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.reqs = append(s.reqs, req)
	if s.err != nil {
		return plateadvice.Advice{}, s.err
	}
	if len(s.resp.Suggestions) == 0 {
		return plateadvice.Advice{
			Summary: "Add a few more vegetables.",
			Suggestions: []plateadvice.Suggestion{
				{Action: plateadvice.ActionAdd, TargetGroup: plateadvice.GroupVegetable, Title: "Add vegetables", Reason: "Vegetables and fruit are low."},
			},
		}, nil
	}
	return s.resp, nil
}

func (s *stubPlateAdviser) setErr(err error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.err = err
}

func (s *stubPlateAdviser) setResp(a plateadvice.Advice) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.resp = a
}

func (s *stubPlateAdviser) last(t *testing.T) plateadvice.Request {
	t.Helper()
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.reqs) == 0 {
		t.Fatal("the plate adviser was not called")
	}
	return s.reqs[len(s.reqs)-1]
}

func (s *stubPlateAdviser) calls() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.reqs)
}

func (e *env) postPlateAdvice(t *testing.T, header map[string]string, body []byte) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequestWithContext(context.Background(), http.MethodPost, "/v1/plate-advice", strings.NewReader(string(body)))
	req.Header.Set("Content-Type", "application/json")
	req.RemoteAddr = "203.0.113.10:4242"
	for k, v := range header {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	e.handler.ServeHTTP(rec, req)
	return rec
}

func TestPlateAdviceReturnsSuggestions(t *testing.T) {
	t.Parallel()

	for _, tc := range []struct {
		locale, request, aiFixture, response string
	}{
		{"ru", "plate-advice-request-ru.json", "ai-plate-advice-valid-ru.json", "plate-advice-response-ru.json"},
		{"en", "plate-advice-request-en.json", "ai-plate-advice-valid-en.json", "plate-advice-response-en.json"},
	} {
		t.Run(tc.locale, func(t *testing.T) {
			t.Parallel()
			e := newEnv(t)
			advice, err := plateadvice.ParseAdvice(testutil.Fixture(t, tc.aiFixture))
			if err != nil {
				t.Fatal(err)
			}
			e.plateAdvice.setResp(advice)

			rec := e.postPlateAdvice(t, map[string]string{"X-Request-Id": safeID}, testutil.Fixture(t, tc.request))
			if rec.Code != http.StatusOK {
				t.Fatalf("status = %d: %s", rec.Code, rec.Body.String())
			}
			got, want := mustJSON(t, rec.Body.Bytes()), mustJSON(t, testutil.Fixture(t, tc.response))
			if !reflect.DeepEqual(got, want) {
				t.Errorf("got %v, want %v", got, want)
			}
			validateAgainstOpenAPI(t, "PlateAdviceResponse", got)

			req := e.plateAdvice.last(t)
			if req.RequestID != safeID || req.ClientRequestID != safeID {
				t.Errorf("request id = %q, client id = %q", req.RequestID, req.ClientRequestID)
			}
		})
	}
}

func TestPlateAdviceRejectsBadInput(t *testing.T) {
	t.Parallel()

	mutate := func(t *testing.T, base string, field string, value any) []byte {
		t.Helper()
		var m map[string]any
		mustUnmarshal(t, testutil.Fixture(t, base), &m)
		setPath(m, field, value)
		return mustMarshal(t, m)
	}

	tests := []struct {
		name string
		body []byte
	}{
		{"bad locale", mutate(t, "plate-advice-request-ru.json", "locale", "de")},
		{"bad meal type", mutate(t, "plate-advice-request-ru.json", "mealType", "brunch")},
		{"31 items", func() []byte {
			var m map[string]any
			mustUnmarshal(t, testutil.Fixture(t, "plate-advice-request-ru.json"), &m)
			items := m["items"].([]any)
			extra := make([]any, 0, 31)
			base := items[0].(map[string]any)
			for range 31 {
				clone := map[string]any{}
				for k, v := range base {
					clone[k] = v
				}
				extra = append(extra, clone)
			}
			m["items"] = extra
			return mustMarshal(t, m)
		}()},
		{"121-rune name", mutate(t, "plate-advice-request-ru.json", "items.0.name", strings.Repeat("a", 121))},
		{"non-positive weight", mutate(t, "plate-advice-request-ru.json", "items.0.weightG", 0)},
		{"unknown group", mutate(t, "plate-advice-request-ru.json", "items.0.plateGroup", "sweets")},
		{"unknown balance status", mutate(t, "plate-advice-request-ru.json", "balance.protein", "medium")},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			e := newEnv(t)
			expectError(t, e.postPlateAdvice(t, nil, tt.body), http.StatusBadRequest, "INVALID_REQUEST")
			if e.plateAdvice.calls() != 0 {
				t.Error("rejected input must not reach the adviser")
			}
		})
	}
}

func TestPlateAdviceMultipartRejected(t *testing.T) {
	t.Parallel()

	e := newEnv(t)
	req := httptest.NewRequestWithContext(context.Background(), http.MethodPost, "/v1/plate-advice", strings.NewReader("--x--"))
	req.Header.Set("Content-Type", "multipart/form-data; boundary=x")
	req.RemoteAddr = "203.0.113.10:4242"
	rec := httptest.NewRecorder()
	e.handler.ServeHTTP(rec, req)
	expectError(t, rec, http.StatusUnsupportedMediaType, "INVALID_REQUEST")
	if e.plateAdvice.calls() != 0 {
		t.Error("a multipart body must never reach the adviser")
	}
}

func TestPlateAdviceOversizedBodyRejected(t *testing.T) {
	t.Parallel()

	e := newEnv(t)
	huge := strings.Repeat("a", 70<<10)
	body := []byte(`{"locale":"en","mealType":"lunch","items":[{"name":"` + huge + `","weightG":100,"plateGroup":"other"}],"balance":{"vegetablesFruit":"low","protein":"ok","complexCarbohydrates":"ok"}}`)
	rec := e.postPlateAdvice(t, nil, body)
	expectError(t, rec, http.StatusRequestEntityTooLarge, "INVALID_REQUEST")
	if e.plateAdvice.calls() != 0 {
		t.Error("an oversized body must never reach the adviser")
	}
}

func TestPlateAdviceAllUnknownBalanceGives422(t *testing.T) {
	t.Parallel()

	var m map[string]any
	mustUnmarshal(t, testutil.Fixture(t, "plate-advice-request-en.json"), &m)
	setPath(m, "balance", map[string]any{"vegetablesFruit": "unknown", "protein": "unknown", "complexCarbohydrates": "unknown"})
	body := mustMarshal(t, m)

	e := newEnv(t)
	rec := e.postPlateAdvice(t, map[string]string{"X-Request-Id": safeID}, body)
	expectError(t, rec, http.StatusUnprocessableEntity, "BALANCE_NOT_EVALUABLE")
	got, want := mustJSON(t, rec.Body.Bytes()), mustJSON(t, testutil.Fixture(t, "error-BALANCE_NOT_EVALUABLE.json"))
	gm, wm := got.(map[string]any), want.(map[string]any)
	if gm["code"] != wm["code"] || gm["message"] != wm["message"] {
		t.Errorf("got %v, want %v", got, want)
	}
	if e.plateAdvice.calls() != 0 {
		t.Error("a non-evaluable balance must never reach the adviser")
	}
}

func TestPlateAdviceRateLimiting(t *testing.T) {
	t.Parallel()

	e := newEnv(t, func(o *envOpts) { o.plateAdviceBurst = 3 })
	body := testutil.Fixture(t, "plate-advice-request-en.json")
	for range 3 {
		rec := e.postPlateAdvice(t, nil, body)
		if rec.Code != http.StatusOK {
			t.Fatalf("status = %d: %s", rec.Code, rec.Body.String())
		}
	}
	rec := e.postPlateAdvice(t, nil, body)
	expectError(t, rec, http.StatusTooManyRequests, "RATE_LIMITED")
	if rec.Header().Get("Retry-After") == "" {
		t.Error("missing Retry-After")
	}

	// The meal analysis bucket is unaffected.
	analyzeRec := e.post(t, nil, imagePart(t, "sample.jpg"))
	if analyzeRec.Code != http.StatusOK {
		t.Errorf("meal analysis status = %d, want 200 (separate bucket)", analyzeRec.Code)
	}
}

func TestPlateAdviceProviderErrors(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		err     error
		status  int
		code    string
		fixture string
	}{
		{"provider down", analysis.ErrUnavailable, http.StatusServiceUnavailable, "AI_PROVIDER_UNAVAILABLE", "error-AI_PROVIDER_UNAVAILABLE.json"},
		{"provider garbage", analysis.ErrInvalidResponse, http.StatusBadGateway, "AI_INVALID_RESPONSE", "error-AI_INVALID_RESPONSE.json"},
		{"provider refuses", analysis.ErrRejected, http.StatusBadGateway, "IMAGE_ANALYSIS_FAILED", "error-IMAGE_ANALYSIS_FAILED.json"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			e := newEnv(t)
			e.plateAdvice.setErr(tt.err)
			rec := e.postPlateAdvice(t, map[string]string{"X-Request-Id": safeID}, testutil.Fixture(t, "plate-advice-request-en.json"))
			expectError(t, rec, tt.status, tt.code)
			if tt.status == http.StatusServiceUnavailable && rec.Header().Get("Retry-After") == "" {
				t.Error("an unavailable provider should say when to come back")
			}
		})
	}
}

func TestPlateAdviceAbandonedRequestsAreNotAnswered(t *testing.T) {
	t.Parallel()

	e := newEnv(t)
	e.plateAdvice.setErr(context.Canceled)
	rec := e.postPlateAdvice(t, nil, testutil.Fixture(t, "plate-advice-request-en.json"))
	if rec.Code != 499 || rec.Body.Len() != 0 {
		t.Errorf("status = %d, body %q", rec.Code, rec.Body.String())
	}
}

func TestPlateAdviceDisabledGives404AndHidesCapability(t *testing.T) {
	t.Parallel()

	h := httpapi.NewHandler(httpapi.Deps{
		Analyzer: &stubAnalyzer{}, Observer: &observer{}, Logger: slog.New(slog.DiscardHandler),
		Limiter:        ratelimit.New(ratelimit.Config{PerMinute: 10, Burst: 10, MaxClients: 10, IdleTTL: time.Minute}),
		MaxUploadBytes: maxBytes, MaxImageDimensionPx: 4096,
	})
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequestWithContext(context.Background(), http.MethodGet, "/v1/config", nil))
	got := mustJSON(t, rec.Body.Bytes()).(map[string]any)
	if got["plateAdvice"] != false {
		t.Errorf("plateAdvice = %v, want false", got["plateAdvice"])
	}

	rec2 := httptest.NewRecorder()
	req := httptest.NewRequestWithContext(context.Background(), http.MethodPost, "/v1/plate-advice", strings.NewReader("{}"))
	req.Header.Set("Content-Type", "application/json")
	h.ServeHTTP(rec2, req)
	if rec2.Code != http.StatusNotFound {
		t.Errorf("status = %d, want 404", rec2.Code)
	}
}

// TestPlateAdviceEnabledAdvertisesCapability checks the flag on an env with
// the use case wired in; TestClientConfigMatchesFixture (contract_test.go)
// separately checks the whole body against config-default.json.
func TestPlateAdviceEnabledAdvertisesCapability(t *testing.T) {
	t.Parallel()

	e := newEnv(t)
	rec := httptest.NewRecorder()
	e.handler.ServeHTTP(rec, httptest.NewRequestWithContext(context.Background(), http.MethodGet, "/v1/config", nil))
	got := mustJSON(t, rec.Body.Bytes()).(map[string]any)
	if got["plateAdvice"] != true {
		t.Errorf("plateAdvice = %v, want true", got["plateAdvice"])
	}
}

// TestPlateAdviceLogsContainNoContent runs the real handler and service
// (with a real gemini.Provider against a fake upstream, so the prompt is
// actually built) over a success, an invalid AI response and a validation
// failure, and checks that no log record contains a food name from the
// fixture, prompt text, or any summary, title, reason or example text.
func TestPlateAdviceLogsContainNoContent(t *testing.T) {
	t.Parallel()

	var mu sync.Mutex
	fail := false
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		mu.Lock()
		defer mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		if fail {
			_, _ = w.Write([]byte(`{"candidates":[{"content":{"parts":[{"text":"not valid json"}]},"finishReason":"STOP"}]}`))
			return
		}
		text := string(testutil.Fixture(t, "ai-plate-advice-valid-ru.json"))
		body, _ := json.Marshal(map[string]any{"candidates": []any{map[string]any{
			"content":      map[string]any{"parts": []any{map[string]any{"text": text}}},
			"finishReason": "STOP",
		}}})
		_, _ = w.Write(body)
	}))
	defer upstream.Close()

	logs := &bytes.Buffer{}
	log := slog.New(slog.NewJSONHandler(&syncWriter{w: logs}, &slog.HandlerOptions{Level: slog.LevelDebug}))
	provider := gemini.New(gemini.Config{BaseURL: upstream.URL, Model: "m", APIKey: "test-key"}, &http.Client{Timeout: 5 * time.Second})
	svc := plateadvice.NewService(plateadvice.Config{
		ProviderName: "test", CallTimeout: 5 * time.Second, OverallTimeout: 10 * time.Second,
		MaxConcurrent: 4, QueueWait: 10 * time.Millisecond, ReplayTTL: time.Minute, ReplayMaxEntries: 10,
	}, plateadvice.Deps{
		Advisor: provider, Logger: log,
		Sleep: func(context.Context, time.Duration) error { return nil },
	})
	h := httpapi.NewHandler(httpapi.Deps{
		Analyzer: &stubAnalyzer{}, Observer: &observer{}, Logger: log,
		Limiter:            ratelimit.New(ratelimit.Config{PerMinute: 600, Burst: 100, MaxClients: 10, IdleTTL: time.Minute}),
		PlateAdvice:        svc,
		PlateAdviceLimiter: ratelimit.New(ratelimit.Config{PerMinute: 600, Burst: 100, MaxClients: 10, IdleTTL: time.Minute}),
		MaxUploadBytes:     maxBytes, MaxImageDimensionPx: 4096,
	})

	post := func(requestID string, body []byte) *httptest.ResponseRecorder {
		req := httptest.NewRequestWithContext(context.Background(), http.MethodPost, "/v1/plate-advice", strings.NewReader(string(body)))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Request-Id", requestID)
		req.RemoteAddr = "203.0.113.10:1"
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		return rec
	}

	if rec := post(safeID, testutil.Fixture(t, "plate-advice-request-ru.json")); rec.Code != http.StatusOK {
		t.Fatalf("success case: status %d: %s", rec.Code, rec.Body.String())
	}
	mu.Lock()
	fail = true
	mu.Unlock()
	if rec := post("0190f7a2-1b2c-7d3e-8f40-000000000002", testutil.Fixture(t, "plate-advice-request-ru.json")); rec.Code != http.StatusBadGateway {
		t.Fatalf("invalid AI response case: status %d: %s", rec.Code, rec.Body.String())
	}
	if rec := post("0190f7a2-1b2c-7d3e-8f40-000000000003", []byte(`{"locale":"de","mealType":"lunch","items":[],"balance":{}}`)); rec.Code != http.StatusBadRequest {
		t.Fatalf("validation failure case: status %d: %s", rec.Code, rec.Body.String())
	}

	out := logs.String()
	if !strings.Contains(out, `"request_id"`) || !strings.Contains(out, `"status":200`) || !strings.Contains(out, `"status":502`) {
		t.Fatalf("expected access log records, got:\n%s", out)
	}
	forbidden := map[string]string{
		"API key":            "test-key",
		"food name (ru)":     "Гречка",
		"food name (ru2)":    "Куриная грудка",
		"prompt marker":      "BEGIN_MEAL_DATA",
		"summary text":       "Добавьте немного овощей",
		"suggestion title":   "Добавьте овощи",
		"suggestion reason":  "Овощей и фруктов сейчас мало",
		"suggestion example": "огуречно-томатный салат",
	}
	for what, needle := range forbidden {
		if strings.Contains(out, needle) {
			t.Errorf("logs contain %s (%q):\n%s", what, needle, out)
		}
	}
}

func TestPlateAdviceGETNotAllowed(t *testing.T) {
	t.Parallel()

	e := newEnv(t)
	rec := httptest.NewRecorder()
	e.handler.ServeHTTP(rec, httptest.NewRequestWithContext(context.Background(), http.MethodGet, "/v1/plate-advice", nil))
	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("status = %d, want 405", rec.Code)
	}
}
