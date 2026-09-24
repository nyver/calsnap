// Package metrics exposes Prometheus counters and histograms. Labels are
// restricted to route patterns, methods, status classes and enumerated kinds:
// no image content, food names or client addresses ever reach a metric.
package metrics

import (
	"net/http"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Metrics owns a private registry and all collectors of the server.
type Metrics struct {
	reg *prometheus.Registry

	httpRequests    *prometheus.CounterVec
	httpDuration    *prometheus.HistogramVec
	rateLimited     prometheus.Counter
	aiDuration      *prometheus.HistogramVec
	aiErrors        *prometheus.CounterVec
	aiInvalid       prometheus.Counter
	aiTokens        *prometheus.CounterVec
	nutritionMatch  *prometheus.CounterVec
	nutritionFailed prometheus.Counter
}

// New creates and registers all collectors.
func New() *Metrics {
	m := &Metrics{
		reg: prometheus.NewRegistry(),
		httpRequests: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "calsnap_http_requests_total",
			Help: "HTTP requests by route pattern, method and status class.",
		}, []string{"route", "method", "status_class"}),
		httpDuration: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Name:    "calsnap_http_request_duration_seconds",
			Help:    "HTTP request latency by route pattern and method.",
			Buckets: []float64{0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 20, 40, 60},
		}, []string{"route", "method"}),
		rateLimited: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "calsnap_rate_limited_total",
			Help: "Analyze requests rejected by the per-client rate limit.",
		}),
		aiDuration: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Name:    "calsnap_ai_call_duration_seconds",
			Help:    "Latency of single AI provider calls.",
			Buckets: []float64{0.5, 1, 2, 4, 8, 15, 30, 45},
		}, []string{"provider"}),
		aiErrors: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "calsnap_ai_errors_total",
			Help: "AI provider call failures by kind (unavailable, invalid_response, rejected).",
		}, []string{"kind"}),
		aiInvalid: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "calsnap_ai_invalid_responses_total",
			Help: "AI results that were not valid JSON or failed range validation.",
		}),
		aiTokens: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "calsnap_ai_tokens_total",
			Help: "Tokens consumed at the AI provider, when reported (cost proxy).",
		}, []string{"direction"}),
		nutritionMatch: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "calsnap_nutrition_matches_total",
			Help: "Nutrition lookups by result kind (exact, alias, fuzzy, fallback).",
		}, []string{"kind"}),
		nutritionFailed: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "calsnap_nutrition_match_failed_total",
			Help: "Items without any nutrition profile.",
		}),
	}
	m.reg.MustRegister(
		collectors.NewGoCollector(),
		collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}),
		m.httpRequests, m.httpDuration, m.rateLimited, m.aiDuration, m.aiErrors,
		m.aiInvalid, m.aiTokens, m.nutritionMatch, m.nutritionFailed,
	)
	// Pre-create the enumerated series so that dashboards and alerts see zeros.
	for _, kind := range []string{"unavailable", "invalid_response", "rejected"} {
		m.aiErrors.WithLabelValues(kind)
	}
	for _, kind := range []string{"exact", "alias", "fuzzy", "fallback"} {
		m.nutritionMatch.WithLabelValues(kind)
	}
	m.aiTokens.WithLabelValues("input")
	m.aiTokens.WithLabelValues("output")
	return m
}

// Handler serves the registry in the Prometheus text format.
func (m *Metrics) Handler() http.Handler {
	return promhttp.HandlerFor(m.reg, promhttp.HandlerOpts{})
}

// ObserveRequest records one finished HTTP request.
func (m *Metrics) ObserveRequest(route, method string, status int, seconds float64) {
	m.httpRequests.WithLabelValues(route, method, statusClass(status)).Inc()
	m.httpDuration.WithLabelValues(route, method).Observe(seconds)
}

// RateLimited records a rejected analyze request.
func (m *Metrics) RateLimited() { m.rateLimited.Inc() }

// ObserveAICall implements analysis.Metrics.
func (m *Metrics) ObserveAICall(provider string, seconds float64) {
	m.aiDuration.WithLabelValues(provider).Observe(seconds)
}

// AIError implements analysis.Metrics.
func (m *Metrics) AIError(kind string) { m.aiErrors.WithLabelValues(kind).Inc() }

// InvalidAIResponse implements analysis.Metrics.
func (m *Metrics) InvalidAIResponse() { m.aiInvalid.Inc() }

// NutritionMatch implements analysis.Metrics.
func (m *Metrics) NutritionMatch(kind string) { m.nutritionMatch.WithLabelValues(kind).Inc() }

// NutritionMatchFailed implements analysis.Metrics.
func (m *Metrics) NutritionMatchFailed() { m.nutritionFailed.Inc() }

// AIUsage implements analysis.Metrics.
func (m *Metrics) AIUsage(inputTokens, outputTokens int) {
	if inputTokens > 0 {
		m.aiTokens.WithLabelValues("input").Add(float64(inputTokens))
	}
	if outputTokens > 0 {
		m.aiTokens.WithLabelValues("output").Add(float64(outputTokens))
	}
}

func statusClass(status int) string {
	switch {
	case status >= 500:
		return "5xx"
	case status >= 400:
		return "4xx"
	case status >= 300:
		return "3xx"
	case status >= 200:
		return "2xx"
	default:
		return "1xx"
	}
}
