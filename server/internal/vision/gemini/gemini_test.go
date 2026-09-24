package gemini_test

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"sort"
	"strings"
	"testing"
	"time"

	"example.com/calsnap/server/internal/app/analysis"
	"example.com/calsnap/server/internal/testutil"
	"example.com/calsnap/server/internal/vision/gemini"
)

const testKey = "test-api-key-123"

var testImage = analysis.Image{Data: []byte("\xff\xd8\xffjpeg-bytes"), MIMEType: "image/jpeg", Width: 8, Height: 8}

// envelope wraps model text the way Gemini does.
func envelope(text, finish string) string {
	b, _ := json.Marshal(map[string]any{
		"candidates": []any{map[string]any{
			"content":      map[string]any{"parts": []any{map[string]any{"text": text}}},
			"finishReason": finish,
		}},
		"usageMetadata": map[string]any{"promptTokenCount": 1300, "candidatesTokenCount": 210},
	})
	return string(b)
}

func newProvider(t *testing.T, handler http.HandlerFunc) *gemini.Provider {
	t.Helper()
	srv := httptest.NewServer(handler)
	t.Cleanup(srv.Close)
	return gemini.New(gemini.Config{BaseURL: srv.URL + "/v1beta", Model: "test-model", APIKey: testKey},
		&http.Client{Timeout: 5 * time.Second})
}

func respond(status int, body string) http.HandlerFunc {
	return func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		_, _ = io.WriteString(w, body)
	}
}

func TestAnalyzeSuccessAndRequestShape(t *testing.T) {
	t.Parallel()

	var captured struct {
		path, key, query string
		body             map[string]any
		raw              string
	}
	valid := string(testutil.Fixture(t, "ai-result-full.json"))
	p := newProvider(t, func(w http.ResponseWriter, r *http.Request) {
		raw, _ := io.ReadAll(r.Body)
		captured.path, captured.key, captured.query, captured.raw = r.URL.Path, r.Header.Get("x-goog-api-key"), r.URL.RawQuery, string(raw)
		_ = json.Unmarshal(raw, &captured.body)
		respond(http.StatusOK, envelope(valid, "STOP"))(w, r)
	})

	res, err := p.Analyze(context.Background(), testImage, analysis.RequestContext{RequestID: "r1", Locale: "ru", PlateDiameterCm: 26})
	if err != nil {
		t.Fatalf("Analyze: %v", err)
	}
	if len(res.Items) != 4 || res.Usage.InputTokens != 1300 || res.Usage.OutputTokens != 210 {
		t.Errorf("result = %+v", res)
	}

	if captured.path != "/v1beta/models/test-model:generateContent" {
		t.Errorf("path = %q", captured.path)
	}
	if captured.key != testKey {
		t.Error("API key must be sent in the x-goog-api-key header")
	}
	if captured.query != "" || strings.Contains(captured.path, testKey) {
		t.Errorf("API key must not appear in the URL: %q %q", captured.path, captured.query)
	}
	if strings.Contains(captured.raw, testKey) {
		t.Error("API key must not appear in the request body")
	}
	if !strings.Contains(captured.raw, base64.StdEncoding.EncodeToString(testImage.Data)) {
		t.Error("image is not sent inline as base64")
	}
	for _, want := range []string{"image/jpeg", "responseSchema", `application/json`, "Russian", "26 cm"} {
		if !strings.Contains(captured.raw, want) {
			t.Errorf("request does not contain %q", want)
		}
	}
}

func TestAnalyzeSendsTheSideImageAfterTheMainOne(t *testing.T) {
	t.Parallel()

	side := analysis.Image{Data: []byte("side-bytes"), MIMEType: "image/png", Width: 8, Height: 8}
	var raw string
	p := newProvider(t, func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		raw = string(b)
		respond(http.StatusOK, envelope(`{"items":[]}`, "STOP"))(w, r)
	})
	if _, err := p.Analyze(context.Background(), testImage, analysis.RequestContext{Locale: "en", SideImage: &side}); err != nil {
		t.Fatal(err)
	}
	top := strings.Index(raw, base64.StdEncoding.EncodeToString(testImage.Data))
	sideAt := strings.Index(raw, base64.StdEncoding.EncodeToString(side.Data))
	if top < 0 || sideAt < 0 || top > sideAt {
		t.Errorf("images must be sent main first, side second (positions %d, %d)", top, sideAt)
	}
	for _, want := range []string{"image/png", "from above", "from the side"} {
		if !strings.Contains(raw, want) {
			t.Errorf("request does not contain %q", want)
		}
	}

	if _, err := p.Analyze(context.Background(), testImage, analysis.RequestContext{Locale: "en"}); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(raw, "from the side") || strings.Count(raw, "inlineData") != 1 {
		t.Errorf("a single photo request must stay single: %s", raw)
	}
}

func TestAnalyzeOmitsPlateWhenUnknown(t *testing.T) {
	t.Parallel()

	var raw string
	p := newProvider(t, func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		raw = string(b)
		respond(http.StatusOK, envelope(`{"items":[]}`, "STOP"))(w, r)
	})
	if _, err := p.Analyze(context.Background(), testImage, analysis.RequestContext{Locale: "en"}); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(raw, "plate diameter is") || !strings.Contains(raw, "English") {
		t.Errorf("unexpected prompt: %s", raw)
	}
}

func TestAnalyzeErrorClassification(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		handler http.HandlerFunc
		want    error
	}{
		{"429", respond(http.StatusTooManyRequests, `{"error":{"message":"quota secret detail"}}`), analysis.ErrUnavailable},
		{"500", respond(http.StatusInternalServerError, `oops`), analysis.ErrUnavailable},
		{"502", respond(http.StatusBadGateway, ``), analysis.ErrUnavailable},
		{"503", respond(http.StatusServiceUnavailable, ``), analysis.ErrUnavailable},
		{"504", respond(http.StatusGatewayTimeout, ``), analysis.ErrUnavailable},
		{"400", respond(http.StatusBadRequest, `{"error":{"message":"bad"}}`), analysis.ErrRejected},
		{"401", respond(http.StatusUnauthorized, ``), analysis.ErrRejected},
		{"403", respond(http.StatusForbidden, ``), analysis.ErrRejected},
		{"404", respond(http.StatusNotFound, ``), analysis.ErrRejected},
		{"prose instead of JSON", respond(http.StatusOK, envelope("I see rice.", "STOP")), analysis.ErrInvalidResponse},
		{"malformed envelope", respond(http.StatusOK, `not json`), analysis.ErrInvalidResponse},
		{"no candidates", respond(http.StatusOK, `{"candidates":[]}`), analysis.ErrInvalidResponse},
		{"truncated output", respond(http.StatusOK, envelope(`{"items":[`, "MAX_TOKENS")), analysis.ErrInvalidResponse},
		{"out-of-range values", respond(http.StatusOK, envelope(`{"items":[{"name":"a","displayName":"a","estimatedWeightG":-5,"confidence":1}]}`, "STOP")), analysis.ErrInvalidResponse},
		{"blocked prompt", respond(http.StatusOK, `{"promptFeedback":{"blockReason":"SAFETY"}}`), analysis.ErrRejected},
		{"oversized body", respond(http.StatusOK, strings.Repeat("x", 2<<20+10)), analysis.ErrInvalidResponse},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			p := newProvider(t, tt.handler)
			_, err := p.Analyze(context.Background(), testImage, analysis.RequestContext{})
			if !errors.Is(err, tt.want) {
				t.Fatalf("err = %v, want %v", err, tt.want)
			}
			if strings.Contains(err.Error(), "secret detail") || strings.Contains(err.Error(), testKey) {
				t.Errorf("error leaks provider body or key: %v", err)
			}
		})
	}
}

func TestAnalyzeNetworkFailureIsUnavailable(t *testing.T) {
	t.Parallel()

	srv := httptest.NewServer(http.NotFoundHandler())
	url := srv.URL
	srv.Close() // connection refused
	p := gemini.New(gemini.Config{BaseURL: url, Model: "m", APIKey: testKey}, &http.Client{Timeout: time.Second})
	_, err := p.Analyze(context.Background(), testImage, analysis.RequestContext{})
	if !errors.Is(err, analysis.ErrUnavailable) {
		t.Fatalf("err = %v, want ErrUnavailable", err)
	}
	if strings.Contains(err.Error(), url) {
		t.Errorf("error must not include the URL: %v", err)
	}
}

func TestAnalyzeHonorsContextCancellation(t *testing.T) {
	t.Parallel()

	release := make(chan struct{})
	p := newProvider(t, func(_ http.ResponseWriter, r *http.Request) {
		select {
		case <-release:
		case <-r.Context().Done():
		}
	})
	t.Cleanup(func() { close(release) })
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	_, err := p.Analyze(ctx, testImage, analysis.RequestContext{})
	if err == nil || !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("err = %v, want deadline exceeded", err)
	}
}

// TestResponseSchemaMatchesProtocol keeps the Gemini schema in sync with the
// published JSON Schema: same properties and same required lists.
func TestResponseSchemaMatchesProtocol(t *testing.T) {
	t.Parallel()

	var proto map[string]any
	if err := json.Unmarshal(testutil.ReadProtocol(t, "ai/food-vision-result.schema.json"), &proto); err != nil {
		t.Fatal(err)
	}
	raw, _ := json.Marshal(gemini.ResponseSchema())
	var got map[string]any
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatal(err)
	}

	var compare func(path string, want, have map[string]any)
	compare = func(path string, want, have map[string]any) {
		if names(want["required"]) != names(have["required"]) {
			t.Errorf("%s: required %s != %s", path, names(want["required"]), names(have["required"]))
		}
		wp, _ := want["properties"].(map[string]any)
		hp, _ := have["properties"].(map[string]any)
		if keys(wp) != keys(hp) {
			t.Errorf("%s: properties %s != %s", path, keys(wp), keys(hp))
		}
		for k, w := range wp {
			h, _ := hp[k].(map[string]any)
			wm, _ := w.(map[string]any)
			if wm["type"] == "object" {
				compare(path+"."+k, wm, h)
			}
			if wm["type"] == "array" {
				wi, _ := wm["items"].(map[string]any)
				hi, _ := h["items"].(map[string]any)
				compare(path+"."+k+"[]", wi, hi)
			}
		}
	}
	compare("$", proto, got)
}

func names(v any) string {
	list, _ := v.([]any)
	out := make([]string, 0, len(list))
	for _, x := range list {
		out = append(out, x.(string))
	}
	sort.Strings(out)
	return strings.Join(out, ",")
}

func keys(m map[string]any) string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return strings.Join(out, ",")
}
