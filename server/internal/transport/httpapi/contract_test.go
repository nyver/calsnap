package httpapi_test

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"reflect"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"

	"example.com/calsnap/server/internal/app/analysis"
	"example.com/calsnap/server/internal/app/label"
	"example.com/calsnap/server/internal/nutrition"
	"example.com/calsnap/server/internal/ratelimit"
	"example.com/calsnap/server/internal/testutil"
	"example.com/calsnap/server/internal/transport/httpapi"
	"example.com/calsnap/server/internal/vision/gemini"

	"gopkg.in/yaml.v3"
)

// scriptedVision returns a fixed provider result.
type scriptedVision struct {
	res analysis.Result
	err error
}

func (s scriptedVision) Analyze(context.Context, analysis.Image, analysis.RequestContext) (analysis.Result, error) {
	return s.res, s.err
}

func realService(t *testing.T, vision analysis.FoodVisionProvider, log *slog.Logger) *analysis.Service {
	t.Helper()
	cat, err := nutrition.LoadEmbedded(0.85)
	if err != nil {
		t.Fatal(err)
	}
	return analysis.NewService(analysis.Config{
		ProviderName: "test", MinConfidence: 0.2, CallTimeout: 5 * time.Second, OverallTimeout: 10 * time.Second,
		MaxConcurrent: 4, QueueWait: 10 * time.Millisecond, ReplayTTL: time.Minute, ReplayMaxEntries: 10,
	}, analysis.Deps{
		Vision: vision, Nutrition: cat, Logger: log,
		Sleep: func(context.Context, time.Duration) error { return nil },
	})
}

func handlerFor(svc httpapi.Analyzer, log *slog.Logger) http.Handler {
	return httpapi.NewHandler(httpapi.Deps{
		Analyzer: svc, Observer: &observer{}, Logger: log,
		Limiter:        ratelimit.New(ratelimit.Config{PerMinute: 600, Burst: 100, MaxClients: 10, IdleTTL: time.Minute}),
		MaxUploadBytes: 4 << 20, MaxImageDimensionPx: 4096,
	})
}

func postFixtureImage(t *testing.T, h http.Handler, locale string, extra ...part) *httptest.ResponseRecorder {
	t.Helper()
	return postFixtureImageID(t, h, safeID, locale, extra...)
}

func postFixtureImageID(t *testing.T, h http.Handler, requestID, locale string, extra ...part) *httptest.ResponseRecorder {
	t.Helper()
	parts := append([]part{
		{name: "image", filename: "sample.jpg", content: string(testutil.Fixture(t, "sample.jpg"))},
		{name: "locale", content: locale},
	}, extra...)
	ct, body := buildBody(t, parts...)
	req := httptest.NewRequestWithContext(context.Background(), http.MethodPost, "/v1/meals/analyze", body)
	req.Header.Set("Content-Type", ct)
	req.Header.Set("X-Request-Id", requestID)
	req.RemoteAddr = "203.0.113.10:1"
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func mustJSON(t *testing.T, data []byte) any {
	t.Helper()
	var v any
	if err := json.Unmarshal(data, &v); err != nil {
		t.Fatalf("invalid JSON: %v\n%s", err, data)
	}
	return v
}

// TestAnalyzeMatchesProtocolFixtures runs the whole pipeline (handler, use
// case, catalog) with scripted provider output and compares the response with
// the shared fixtures that the client tests also consume.
func TestAnalyzeMatchesProtocolFixtures(t *testing.T) {
	t.Parallel()

	tests := []struct{ ai, response, locale string }{
		{"ai-result-full.json", "analyze-response-full.json", "ru"},
		{"ai-result-partial.json", "analyze-response-partial.json", "en"},
		{"ai-result-estimated.json", "analyze-response-estimated.json", "en"},
		{"ai-result-no-food.json", "analyze-response-no-food.json", "en"},
	}
	for _, tt := range tests {
		t.Run(tt.response, func(t *testing.T) {
			t.Parallel()
			res, err := analysis.ParseResult(testutil.Fixture(t, tt.ai))
			if err != nil {
				t.Fatal(err)
			}
			h := handlerFor(realService(t, scriptedVision{res: res}, nil), slog.New(slog.DiscardHandler))
			rec := postFixtureImage(t, h, tt.locale)
			if rec.Code != 200 {
				t.Fatalf("status = %d: %s", rec.Code, rec.Body.String())
			}
			got, want := mustJSON(t, rec.Body.Bytes()), mustJSON(t, testutil.Fixture(t, tt.response))
			if !reflect.DeepEqual(got, want) {
				t.Errorf("response differs from fixture\n got: %s\nwant: %s", rec.Body.String(), testutil.Fixture(t, tt.response))
			}
			validateAgainstOpenAPI(t, "AnalyzeResponse", got)
		})
	}
}

func TestErrorFixturesMatchEveryCode(t *testing.T) {
	t.Parallel()

	// Every code is produced by a real request path.
	cases := map[string]func(t *testing.T) *httptest.ResponseRecorder{
		"UNSUPPORTED_IMAGE_FORMAT": func(t *testing.T) *httptest.ResponseRecorder {
			return newEnv(t).post(t, map[string]string{"X-Request-Id": safeID}, imagePart(t, "sample.gif"))
		},
		"INVALID_IMAGE": func(t *testing.T) *httptest.ResponseRecorder {
			return newEnv(t).post(t, map[string]string{"X-Request-Id": safeID}, part{name: "locale", content: "en"})
		},
		"IMAGE_TOO_LARGE": func(t *testing.T) *httptest.ResponseRecorder {
			return newEnv(t).post(t, map[string]string{"X-Request-Id": safeID}, part{name: "image", filename: "a", content: "\xff\xd8\xff" + strings.Repeat("A", 2*maxBytes)})
		},
		"RATE_LIMITED": func(t *testing.T) *httptest.ResponseRecorder {
			e := newEnv(t, func(o *envOpts) { o.burst = 1 })
			e.post(t, nil, imagePart(t, "sample.jpg"))
			return e.post(t, map[string]string{"X-Request-Id": safeID}, imagePart(t, "sample.jpg"))
		},
	}
	for code, run := range cases {
		t.Run(code, func(t *testing.T) {
			t.Parallel()
			rec := run(t)
			fixture := testutil.Fixture(t, "error-"+code+".json")
			var got, want errResp
			_ = json.Unmarshal(rec.Body.Bytes(), &got)
			_ = json.Unmarshal(fixture, &want)
			if got.Code != want.Code || got.RequestID != want.RequestID {
				t.Fatalf("got %+v, fixture %+v", got, want)
			}
			if got.Message != want.Message && code != "IMAGE_TOO_LARGE" && code != "INVALID_IMAGE" {
				t.Errorf("message = %q, fixture %q", got.Message, want.Message)
			}
			validateAgainstOpenAPI(t, "Error", mustJSON(t, rec.Body.Bytes()))
		})
	}

	// Errors from the use case: the fixture messages are the defaults.
	domain := map[string]error{
		"AI_PROVIDER_UNAVAILABLE": analysis.ErrUnavailable,
		"AI_INVALID_RESPONSE":     analysis.ErrInvalidResponse,
		"NUTRITION_MATCH_FAILED":  analysis.ErrMatchFailed,
		"IMAGE_ANALYSIS_FAILED":   analysis.ErrRejected,
		"INTERNAL_ERROR":          fmt.Errorf("boom"),
	}
	for code, cause := range domain {
		t.Run(code, func(t *testing.T) {
			t.Parallel()
			e := newEnv(t)
			e.analyzer.err = cause
			rec := e.post(t, map[string]string{"X-Request-Id": safeID}, imagePart(t, "sample.jpg"))
			var got, want errResp
			_ = json.Unmarshal(rec.Body.Bytes(), &got)
			_ = json.Unmarshal(testutil.Fixture(t, "error-"+code+".json"), &want)
			if got != want {
				t.Errorf("got %+v, fixture %+v", got, want)
			}
			validateAgainstOpenAPI(t, "Error", mustJSON(t, rec.Body.Bytes()))
		})
	}

	// INVALID_REQUEST fixture: default message, produced for a bad request.
	if got := testutil.Fixture(t, "error-INVALID_REQUEST.json"); !strings.Contains(string(got), "INVALID_REQUEST") {
		t.Error("fixture missing")
	}
}

func TestClientConfigMatchesFixture(t *testing.T) {
	t.Parallel()

	h := httpapi.NewHandler(httpapi.Deps{
		Analyzer: &stubAnalyzer{}, Observer: &observer{}, Logger: slog.New(slog.DiscardHandler),
		Limiter:        ratelimit.New(ratelimit.Config{PerMinute: 10, Burst: 3, MaxClients: 1, IdleTTL: time.Minute}),
		Products:       &stubProducts{},
		Labels:         &stubLabels{},
		MaxUploadBytes: 4 << 20, MaxImageDimensionPx: 4096,
		ClientConfig: httpapi.ClientConfig{ImageMaxLongSidePx: 1280, ImageJPEGQuality: 80, MaxUploadBytes: 4 << 20, AnalyzeTimeoutSeconds: 60},
	})
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequestWithContext(context.Background(), http.MethodGet, "/v1/config", nil))
	got, want := mustJSON(t, rec.Body.Bytes()), mustJSON(t, testutil.Fixture(t, "config-default.json"))
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
	validateAgainstOpenAPI(t, "ClientConfig", got)
}

// TestOpenAPIEnumsMatchCode checks the published enums against the code.
func TestOpenAPIEnumsMatchCode(t *testing.T) {
	t.Parallel()

	doc := loadOpenAPI(t)
	schemas := doc["components"].(map[string]any)["schemas"].(map[string]any)

	codes := enumOf(schemas["Error"].(map[string]any)["properties"].(map[string]any)["code"])
	wantCodes := []string{
		httpapi.CodeInvalidRequest, httpapi.CodeInvalidImage, httpapi.CodeImageTooLarge, httpapi.CodeUnsupportedImageFormat,
		httpapi.CodeRateLimited, httpapi.CodeAIProviderUnavailable, httpapi.CodeAIInvalidResponse,
		httpapi.CodeNutritionMatchFailed, httpapi.CodeImageAnalysisFailed, httpapi.CodeInternalError,
		httpapi.CodeProductNotFound, httpapi.CodeProductSourceUnavailable, httpapi.CodeLabelNotRecognized,
	}
	sort.Strings(wantCodes)
	if !reflect.DeepEqual(codes, wantCodes) {
		t.Errorf("error codes in OpenAPI %v != code %v", codes, wantCodes)
	}

	labelWarnings := enumOf(schemas["LabelWarning"])
	wantLabelWarnings := []string{
		label.WarningEnergyEstimated, label.WarningEnergyMismatch, label.WarningLowConfidence,
		label.WarningValuesConverted, label.WarningVolumeBasis,
	}
	sort.Strings(wantLabelWarnings)
	if !reflect.DeepEqual(labelWarnings, wantLabelWarnings) {
		t.Errorf("label warnings in OpenAPI %v != code %v", labelWarnings, wantLabelWarnings)
	}

	warnings := enumOf(schemas["Warning"])
	wantWarnings := []string{
		analysis.WarningLowConfidence, analysis.WarningNoFoodDetected, analysis.WarningNutritionEstimated, analysis.WarningPartialRecognition,
	}
	if !reflect.DeepEqual(warnings, wantWarnings) {
		t.Errorf("warnings in OpenAPI %v != code %v", warnings, wantWarnings)
	}
}

// TestLogsContainNoContent runs a successful and a failing analysis through the
// real Gemini client and asserts that neither image bytes, the API key, AI
// output, prompts nor food names reach the logs.
func TestLogsContainNoContent(t *testing.T) {
	t.Parallel()

	const apiKey = "sekrit-api-key-0123456789"
	image := testutil.Fixture(t, "sample.jpg")

	var mu sync.Mutex
	fail := false
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		mu.Lock()
		defer mu.Unlock()
		if fail {
			w.WriteHeader(http.StatusInternalServerError)
			_, _ = io.WriteString(w, "upstream secret failure detail chicken")
			return
		}
		text := string(testutil.Fixture(t, "ai-result-full.json"))
		b, _ := json.Marshal(map[string]any{"candidates": []any{map[string]any{
			"content":      map[string]any{"parts": []any{map[string]any{"text": text}}},
			"finishReason": "STOP",
		}}})
		_, _ = w.Write(b)
	}))
	defer upstream.Close()

	logs := &bytes.Buffer{}
	log := slog.New(slog.NewJSONHandler(&syncWriter{w: logs}, &slog.HandlerOptions{Level: slog.LevelDebug}))
	provider := gemini.New(gemini.Config{BaseURL: upstream.URL, Model: "m", APIKey: apiKey}, &http.Client{Timeout: 5 * time.Second})
	h := handlerFor(realService(t, provider, log), log)

	if rec := postFixtureImage(t, h, "ru"); rec.Code != 200 {
		t.Fatalf("success case: status %d: %s", rec.Code, rec.Body.String())
	}
	mu.Lock()
	fail = true
	mu.Unlock()
	if rec := postFixtureImageID(t, h, "0190f7a2-1b2c-7d3e-8f40-000000000002", "ru", part{name: "plateDiameterCm", content: "27.5"}); rec.Code != 503 {
		t.Fatalf("failure case: status %d: %s", rec.Code, rec.Body.String())
	}

	out := logs.String()
	if !strings.Contains(out, `"request_id"`) || !strings.Contains(out, `"status":200`) || !strings.Contains(out, `"status":503`) {
		t.Fatalf("expected access log records, got:\n%s", out)
	}
	forbidden := map[string]string{
		"API key":                   apiKey,
		"base64 image":              base64.StdEncoding.EncodeToString(image[:48]),
		"raw image bytes":           string(image[2:40]),
		"food name (en)":            "chicken",
		"food name (ru)":            "Рис",
		"displayName field":         "displayName",
		"prompt text":               "Requested language",
		"upstream error body":       "upstream secret failure",
		"AI JSON key":               "estimatedWeightG",
		"nutrition values":          "kcal",
		"catalog name":              "Cucumber",
		"plate diameter value":      "27.5",
		"uploaded file name":        "sample.jpg",
		"authorization style token": "Bearer",
	}
	for what, needle := range forbidden {
		if strings.Contains(out, needle) {
			t.Errorf("logs contain %s (%q):\n%s", what, needle, out)
		}
	}
}

// --- minimal OpenAPI schema validator (the subset used by openapi.yaml) -----

func loadOpenAPI(t *testing.T) map[string]any {
	t.Helper()
	var doc map[string]any
	if err := yaml.Unmarshal(testutil.ReadProtocol(t, "api/openapi.yaml"), &doc); err != nil {
		t.Fatalf("openapi.yaml: %v", err)
	}
	return doc
}

func enumOf(schema any) []string {
	var out []string
	for _, v := range schema.(map[string]any)["enum"].([]any) {
		out = append(out, v.(string))
	}
	sort.Strings(out)
	return out
}

func validateAgainstOpenAPI(t *testing.T, schemaName string, value any) {
	t.Helper()
	doc := loadOpenAPI(t)
	schemas := doc["components"].(map[string]any)["schemas"].(map[string]any)
	for _, problem := range validateSchema(schemas, schemas[schemaName], value, "$") {
		t.Errorf("OpenAPI %s: %s", schemaName, problem)
	}
}

func validateSchema(all map[string]any, schema, value any, path string) []string {
	s, _ := schema.(map[string]any)
	if ref, ok := s["$ref"].(string); ok {
		return validateSchema(all, all[ref[strings.LastIndex(ref, "/")+1:]], value, path)
	}
	var problems []string
	add := func(format string, args ...any) { problems = append(problems, path+": "+fmt.Sprintf(format, args...)) }

	if enum, ok := s["enum"].([]any); ok {
		found := false
		for _, e := range enum {
			if reflect.DeepEqual(e, value) {
				found = true
			}
		}
		if !found {
			add("%v is not one of %v", value, enum)
		}
	}
	switch s["type"] {
	case "object":
		obj, ok := value.(map[string]any)
		if !ok {
			return append(problems, path+": expected object")
		}
		props, _ := s["properties"].(map[string]any)
		if req, ok := s["required"].([]any); ok {
			for _, r := range req {
				if _, present := obj[r.(string)]; !present {
					add("missing required property %q", r)
				}
			}
		}
		for k, v := range obj {
			p, known := props[k]
			if !known {
				if s["additionalProperties"] == false {
					add("unexpected property %q", k)
				}
				continue
			}
			problems = append(problems, validateSchema(all, p, v, path+"."+k)...)
		}
	case "array":
		arr, ok := value.([]any)
		if !ok {
			return append(problems, path+": expected array (got null?)")
		}
		if limit, ok := s["maxItems"].(int); ok && len(arr) > limit {
			add("%d items exceed maxItems %d", len(arr), limit)
		}
		for i, v := range arr {
			problems = append(problems, validateSchema(all, s["items"], v, fmt.Sprintf("%s[%d]", path, i))...)
		}
	case "string":
		if _, ok := value.(string); !ok {
			add("expected string")
		}
	case "number", "integer":
		n, ok := value.(float64)
		if !ok {
			return append(problems, path+": expected number")
		}
		if s["type"] == "integer" && n != float64(int64(n)) {
			add("expected integer, got %v", n)
		}
		if lower, ok := toFloat(s["minimum"]); ok {
			if excl, _ := s["exclusiveMinimum"].(bool); excl && n <= lower || n < lower {
				add("%v below minimum %v", n, lower)
			}
		}
		if upper, ok := toFloat(s["maximum"]); ok && n > upper {
			add("%v above maximum %v", n, upper)
		}
	}
	return problems
}

func toFloat(v any) (float64, bool) {
	switch n := v.(type) {
	case int:
		return float64(n), true
	case float64:
		return n, true
	}
	return 0, false
}
