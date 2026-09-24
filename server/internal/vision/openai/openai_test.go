package openai_test

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
	"example.com/calsnap/server/internal/vision/openai"
)

const testKey = "sk-or-test-key-123"

var testImage = analysis.Image{Data: []byte("\xff\xd8\xffjpeg-bytes"), MIMEType: "image/jpeg", Width: 8, Height: 8}

// completion wraps model text the way chat-completions services do.
func completion(content, finish string) string {
	b, _ := json.Marshal(map[string]any{
		"choices": []any{map[string]any{
			"message":       map[string]any{"role": "assistant", "content": content},
			"finish_reason": finish,
		}},
		"usage": map[string]any{"prompt_tokens": 1500, "completion_tokens": 220},
	})
	return string(b)
}

func newProvider(t *testing.T, handler http.HandlerFunc) *openai.Provider {
	t.Helper()
	srv := httptest.NewServer(handler)
	t.Cleanup(srv.Close)
	return openai.New(openai.Config{BaseURL: srv.URL + "/api/v1/", Model: "google/gemini-2.5-flash", APIKey: testKey},
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
		path, auth, query, raw string
		body                   map[string]any
	}
	valid := string(testutil.Fixture(t, "ai-result-full.json"))
	p := newProvider(t, func(w http.ResponseWriter, r *http.Request) {
		raw, _ := io.ReadAll(r.Body)
		captured.path, captured.auth, captured.query, captured.raw = r.URL.Path, r.Header.Get("Authorization"), r.URL.RawQuery, string(raw)
		_ = json.Unmarshal(raw, &captured.body)
		respond(http.StatusOK, completion(valid, "stop"))(w, r)
	})

	res, err := p.Analyze(context.Background(), testImage, analysis.RequestContext{Locale: "ru", PlateDiameterCm: 26})
	if err != nil {
		t.Fatalf("Analyze: %v", err)
	}
	if len(res.Items) != 4 || res.Usage.InputTokens != 1500 || res.Usage.OutputTokens != 220 {
		t.Errorf("result = %+v", res)
	}
	if captured.path != "/api/v1/chat/completions" {
		t.Errorf("path = %q", captured.path)
	}
	if captured.auth != "Bearer "+testKey {
		t.Error("API key must be sent as a bearer token")
	}
	if captured.query != "" || strings.Contains(captured.path, testKey) || strings.Contains(captured.raw, testKey) {
		t.Error("API key must not appear in the URL or the body")
	}
	if captured.body["model"] != "google/gemini-2.5-flash" {
		t.Errorf("model = %v", captured.body["model"])
	}
	wantImage := "data:image/jpeg;base64," + base64.StdEncoding.EncodeToString(testImage.Data)
	for _, want := range []string{wantImage, "json_schema", "food_vision_result", "Russian", "26 cm", "image_url"} {
		if !strings.Contains(captured.raw, want) {
			t.Errorf("request does not contain %q", want)
		}
	}
}

func TestAnalyzeAcceptsFencedAndPartListContent(t *testing.T) {
	t.Parallel()

	valid := string(testutil.Fixture(t, "ai-result-no-food.json"))
	parts, _ := json.Marshal(map[string]any{"choices": []any{map[string]any{
		"message":       map[string]any{"content": []any{map[string]any{"type": "text", "text": valid}}},
		"finish_reason": "stop",
	}}})
	tests := map[string]string{
		"json fence":         completion("```json\n"+valid+"\n```", "stop"),
		"plain fence":        completion("```\n"+valid+"\n```", "stop"),
		"surrounding spaces": completion("  \n"+valid+"\n ", "stop"),
		"list of parts":      string(parts),
	}
	for name, body := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			p := newProvider(t, respond(http.StatusOK, body))
			res, err := p.Analyze(context.Background(), testImage, analysis.RequestContext{})
			if err != nil || len(res.Items) != 0 {
				t.Fatalf("res=%+v err=%v", res, err)
			}
		})
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
		{"408", respond(http.StatusRequestTimeout, ``), analysis.ErrUnavailable},
		{"500", respond(http.StatusInternalServerError, `oops`), analysis.ErrUnavailable},
		{"502", respond(http.StatusBadGateway, ``), analysis.ErrUnavailable},
		{"503", respond(http.StatusServiceUnavailable, ``), analysis.ErrUnavailable},
		{"400", respond(http.StatusBadRequest, `{"error":{"message":"bad"}}`), analysis.ErrRejected},
		{"401", respond(http.StatusUnauthorized, ``), analysis.ErrRejected},
		{"402 no credit", respond(http.StatusPaymentRequired, ``), analysis.ErrRejected},
		{"403", respond(http.StatusForbidden, ``), analysis.ErrRejected},
		{"404 unknown model", respond(http.StatusNotFound, ``), analysis.ErrRejected},
		{"200 with embedded 429", respond(http.StatusOK, `{"error":{"code":429,"message":"upstream secret detail"}}`), analysis.ErrUnavailable},
		{"200 with embedded 502", respond(http.StatusOK, `{"error":{"code":502}}`), analysis.ErrUnavailable},
		{"200 with embedded 400", respond(http.StatusOK, `{"error":{"code":400}}`), analysis.ErrRejected},
		{"200 with textual error code", respond(http.StatusOK, `{"error":{"code":"content_policy"}}`), analysis.ErrRejected},
		{"prose instead of JSON", respond(http.StatusOK, completion("I see rice.", "stop")), analysis.ErrInvalidResponse},
		{"malformed envelope", respond(http.StatusOK, `not json`), analysis.ErrInvalidResponse},
		{"no choices", respond(http.StatusOK, `{"choices":[]}`), analysis.ErrInvalidResponse},
		{"null content", respond(http.StatusOK, `{"choices":[{"message":{"content":null},"finish_reason":"stop"}]}`), analysis.ErrInvalidResponse},
		{"truncated output", respond(http.StatusOK, completion(`{"items":[`, "length")), analysis.ErrInvalidResponse},
		{"filtered output", respond(http.StatusOK, completion(``, "content_filter")), analysis.ErrInvalidResponse},
		{"out-of-range values", respond(http.StatusOK, completion(`{"items":[{"name":"a","displayName":"a","estimatedWeightG":-5,"confidence":1}]}`, "stop")), analysis.ErrInvalidResponse},
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
	p := openai.New(openai.Config{BaseURL: url, Model: "m", APIKey: testKey}, &http.Client{Timeout: time.Second})
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
	if _, err := p.Analyze(ctx, testImage, analysis.RequestContext{}); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("err = %v, want deadline exceeded", err)
	}
}

// TestResponseSchemaMatchesProtocol keeps the schema in sync with the published
// one: same properties and required lists at every level.
func TestResponseSchemaMatchesProtocol(t *testing.T) {
	t.Parallel()

	var proto map[string]any
	if err := json.Unmarshal(testutil.ReadProtocol(t, "ai/food-vision-result.schema.json"), &proto); err != nil {
		t.Fatal(err)
	}
	raw, _ := json.Marshal(openai.ResponseSchema())
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
			wm, _ := w.(map[string]any)
			h, _ := hp[k].(map[string]any)
			switch wm["type"] {
			case "object":
				compare(path+"."+k, wm, h)
			case "array":
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
