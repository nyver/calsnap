package metrics

import (
	"context"
	"net/http/httptest"
	"strings"
	"testing"
)

func scrape(t *testing.T, m *Metrics) string {
	t.Helper()
	rec := httptest.NewRecorder()
	m.Handler().ServeHTTP(rec, httptest.NewRequestWithContext(context.Background(), "GET", "/metrics", nil))
	if rec.Code != 200 {
		t.Fatalf("status = %d", rec.Code)
	}
	return rec.Body.String()
}

func TestCountersAndLabels(t *testing.T) {
	t.Parallel()

	m := New()
	m.ObserveRequest("POST /v1/meals/analyze", "POST", 503, 0.5)
	m.ObserveRequest("POST /v1/meals/analyze", "POST", 200, 0.5)
	m.AIError("unavailable")
	m.InvalidAIResponse()
	m.NutritionMatch("fallback")
	m.NutritionMatchFailed()
	m.RateLimited()
	m.ObserveAICall("gemini", 1.5)
	m.AIUsage(100, 20)
	m.AIUsage(0, 0)

	out := scrape(t, m)
	for _, want := range []string{
		`calsnap_http_requests_total{method="POST",route="POST /v1/meals/analyze",status_class="5xx"} 1`,
		`calsnap_http_requests_total{method="POST",route="POST /v1/meals/analyze",status_class="2xx"} 1`,
		`calsnap_ai_errors_total{kind="unavailable"} 1`,
		`calsnap_ai_errors_total{kind="rejected"} 0`,
		`calsnap_ai_invalid_responses_total 1`,
		`calsnap_nutrition_matches_total{kind="fallback"} 1`,
		`calsnap_nutrition_match_failed_total 1`,
		`calsnap_rate_limited_total 1`,
		`calsnap_ai_call_duration_seconds_count{provider="gemini"} 1`,
		`calsnap_ai_tokens_total{direction="input"} 100`,
		`calsnap_ai_tokens_total{direction="output"} 20`,
		`go_goroutines`,
	} {
		if !strings.Contains(out, want) {
			t.Errorf("metrics output lacks %q", want)
		}
	}
}

func TestStatusClass(t *testing.T) {
	t.Parallel()

	for status, want := range map[int]string{100: "1xx", 200: "2xx", 204: "2xx", 301: "3xx", 404: "4xx", 429: "4xx", 500: "5xx", 503: "5xx"} {
		if got := statusClass(status); got != want {
			t.Errorf("statusClass(%d) = %s, want %s", status, got, want)
		}
	}
}
