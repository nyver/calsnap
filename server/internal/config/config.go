// Package config loads, defaults and validates the server configuration.
package config

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/netip"
	"net/url"
	"os"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

// Environment names accepted in server.environment.
const (
	EnvDevelopment = "development"
	EnvProduction  = "production"
)

// AI provider names accepted in ai.provider.
const (
	ProviderGemini     = "gemini"
	ProviderOpenRouter = "openrouter"
	ProviderRouterAI   = "routerai"
	ProviderFake       = "fake"
)

// Config is the complete server configuration.
type Config struct {
	Server    ServerConfig    `yaml:"server"`
	Limits    LimitsConfig    `yaml:"limits"`
	Client    ClientConfig    `yaml:"client"`
	AI        AIConfig        `yaml:"ai"`
	Nutrition NutritionConfig `yaml:"nutrition"`
	Products  ProductsConfig  `yaml:"products"`
	Metrics   MetricsConfig   `yaml:"metrics"`
	Log       LogConfig       `yaml:"log"`
}

// ServerConfig describes the listener, transport security and timeouts.
type ServerConfig struct {
	Listen          string        `yaml:"listen"`
	Environment     string        `yaml:"environment"`
	AllowPlainHTTP  bool          `yaml:"allow_plain_http"`
	TLS             TLSConfig     `yaml:"tls"`
	TrustedProxies  []string      `yaml:"trusted_proxies"`
	ReadHeaderTime  time.Duration `yaml:"read_header_timeout"`
	ReadTimeout     time.Duration `yaml:"read_timeout"`
	WriteTimeout    time.Duration `yaml:"write_timeout"`
	IdleTimeout     time.Duration `yaml:"idle_timeout"`
	ShutdownTimeout time.Duration `yaml:"shutdown_timeout"`
}

// TLSConfig configures native TLS: either a certificate the operator provides
// or a self-signed one the server generates and keeps.
type TLSConfig struct {
	CertFile string `yaml:"cert_file"`
	KeyFile  string `yaml:"key_file"`

	// SelfSigned makes the server generate a certificate on first start and
	// reuse it afterwards. Clients must pin its fingerprint, see ADR 006.
	SelfSigned bool `yaml:"self_signed"`
	// SelfSignedDir is where the generated certificate and key are stored.
	SelfSignedDir string `yaml:"self_signed_dir"`
	// SelfSignedHosts are extra DNS names and IPs for the certificate, on top
	// of localhost, the host name and the addresses of the local interfaces.
	SelfSignedHosts []string `yaml:"self_signed_hosts"`
}

// Enabled reports whether native TLS is configured.
func (t TLSConfig) Enabled() bool {
	return t.SelfSigned || (t.CertFile != "" && t.KeyFile != "")
}

// LimitsConfig bounds uploads, request rate and concurrency.
type LimitsConfig struct {
	MaxUploadBytes        int64         `yaml:"max_upload_bytes"`
	MaxImageDimensionPx   int           `yaml:"max_image_dimension_px"`
	RatePerMinute         float64       `yaml:"rate_per_minute"`
	RateBurst             int           `yaml:"rate_burst"`
	MaxTrackedClients     int           `yaml:"max_tracked_clients"`
	MaxConcurrentAnalyses int           `yaml:"max_concurrent_analyses"`
	QueueWait             time.Duration `yaml:"queue_wait"`
	ReplayTTL             time.Duration `yaml:"replay_ttl"`
	ReplayMaxEntries      int           `yaml:"replay_max_entries"`

	// Barcode lookups are cheap and often come in bursts (scanning a whole
	// shopping bag), so they get their own, more generous bucket.
	ProductRatePerMinute float64 `yaml:"product_rate_per_minute"`
	ProductRateBurst     int     `yaml:"product_rate_burst"`
}

// ClientConfig contains values exposed to the client through GET /v1/config.
type ClientConfig struct {
	ImageMaxLongSidePx    int `yaml:"image_max_long_side_px"`
	ImageJPEGQuality      int `yaml:"image_jpeg_quality"`
	AnalyzeTimeoutSeconds int `yaml:"analyze_timeout_seconds"`
}

// AIConfig selects and tunes the food vision provider.
type AIConfig struct {
	Provider       string        `yaml:"provider"`
	MinConfidence  float64       `yaml:"min_confidence"`
	CallTimeout    time.Duration `yaml:"call_timeout"`
	OverallTimeout time.Duration `yaml:"overall_timeout"`
	Gemini         GeminiConfig  `yaml:"gemini"`
	OpenRouter     CompatConfig  `yaml:"openrouter"`
	RouterAI       CompatConfig  `yaml:"routerai"`
}

// GeminiConfig configures the Gemini REST provider. The API key is never read
// from the file: APIKeyEnv names the environment variable that holds it.
type GeminiConfig struct {
	Model     string `yaml:"model"`
	APIKeyEnv string `yaml:"api_key_env"`
	BaseURL   string `yaml:"base_url"`

	// APIKey is resolved from the environment by Load.
	APIKey string `yaml:"-"`
}

// CompatConfig configures a provider that speaks the OpenAI chat-completions
// protocol (OpenRouter, RouterAI). The API key is read from the environment
// variable named by APIKeyEnv, never from the file.
type CompatConfig struct {
	// Model is the provider's model slug, e.g. "google/gemini-2.5-flash".
	Model     string `yaml:"model"`
	APIKeyEnv string `yaml:"api_key_env"`
	// BaseURL is the API root without /chat/completions.
	BaseURL string `yaml:"base_url"`

	// APIKey is resolved from the environment by Load.
	APIKey string `yaml:"-"`
}

// NutritionConfig tunes nutrition matching.
type NutritionConfig struct {
	FuzzyThreshold float64 `yaml:"fuzzy_threshold"`
}

// ProductsConfig configures the barcode lookup (GET /v1/products/{barcode}),
// which reads Open Food Facts. The data is crowd-sourced and ODbL-licensed.
type ProductsConfig struct {
	// Enabled turns the endpoint on. The server then makes outbound HTTPS
	// requests to base_url; disable it on hosts that must not.
	Enabled bool `yaml:"enabled"`
	// BaseURL is the Open Food Facts root, or a compatible mirror.
	BaseURL string `yaml:"base_url"`
	// UserAgent identifies this server to Open Food Facts (it asks for an app
	// name and a contact). Empty selects "CalSnap-server/<version>".
	UserAgent string `yaml:"user_agent"`
	// Timeout bounds one request to the product source.
	Timeout time.Duration `yaml:"timeout"`
	// CacheTTL is how long a found product is served from memory.
	CacheTTL time.Duration `yaml:"cache_ttl"`
	// CacheMaxEntries bounds that cache.
	CacheMaxEntries int `yaml:"cache_max_entries"`
}

// MetricsConfig configures the Prometheus listener.
type MetricsConfig struct {
	Listen string `yaml:"listen"`
}

// LogConfig configures structured logging.
type LogConfig struct {
	Level  string `yaml:"level"`
	Format string `yaml:"format"`
}

// Default returns the configuration used for every key the file omits.
func Default() Config {
	return Config{
		Server: ServerConfig{
			Listen:          ":8445",
			Environment:     EnvDevelopment,
			ReadHeaderTime:  10 * time.Second,
			ReadTimeout:     60 * time.Second,
			WriteTimeout:    90 * time.Second,
			IdleTimeout:     120 * time.Second,
			ShutdownTimeout: 30 * time.Second,
			TLS:             TLSConfig{SelfSignedDir: "certs"},
		},
		Limits: LimitsConfig{
			MaxUploadBytes:        4 << 20,
			MaxImageDimensionPx:   4096,
			RatePerMinute:         10,
			RateBurst:             3,
			MaxTrackedClients:     10000,
			MaxConcurrentAnalyses: 16,
			QueueWait:             2 * time.Second,
			ReplayTTL:             10 * time.Minute,
			ReplayMaxEntries:      1000,
			ProductRatePerMinute:  60,
			ProductRateBurst:      10,
		},
		Client: ClientConfig{
			ImageMaxLongSidePx:    1280,
			ImageJPEGQuality:      80,
			AnalyzeTimeoutSeconds: 60,
		},
		AI: AIConfig{
			Provider:       ProviderGemini,
			MinConfidence:  0.2,
			CallTimeout:    45 * time.Second,
			OverallTimeout: 60 * time.Second,
			Gemini: GeminiConfig{ //nolint:gosec // APIKeyEnv is an environment variable name, not a credential
				Model:     "gemini-2.5-flash",
				APIKeyEnv: "GEMINI_API_KEY",
				BaseURL:   "https://generativelanguage.googleapis.com/v1beta",
			},
			OpenRouter: CompatConfig{ //nolint:gosec // APIKeyEnv is an environment variable name, not a credential
				Model:     "google/gemini-2.5-flash",
				APIKeyEnv: "OPENROUTER_API_KEY",
				BaseURL:   "https://openrouter.ai/api/v1",
			},
			RouterAI: CompatConfig{ //nolint:gosec // APIKeyEnv is an environment variable name, not a credential
				Model:     "google/gemini-2.5-flash",
				APIKeyEnv: "ROUTERAI_API_KEY",
				BaseURL:   "https://routerai.ru/api/v1",
			},
		},
		Nutrition: NutritionConfig{FuzzyThreshold: 0.85},
		Products: ProductsConfig{
			Enabled:         true,
			BaseURL:         "https://world.openfoodfacts.org",
			Timeout:         5 * time.Second,
			CacheTTL:        24 * time.Hour,
			CacheMaxEntries: 5000,
		},
		Metrics: MetricsConfig{Listen: "127.0.0.1:9090"},
		Log:     LogConfig{Level: "info", Format: "json"},
	}
}

// Load reads the YAML file at path (an empty path means defaults only),
// resolves secrets through getenv and validates the result.
func Load(path string, getenv func(string) string) (*Config, error) {
	var data []byte
	if path != "" {
		b, err := os.ReadFile(path) //nolint:gosec // path comes from the operator's -config flag
		if err != nil {
			return nil, fmt.Errorf("read config: %w", err)
		}
		data = b
	}
	return Parse(data, getenv)
}

// Parse decodes YAML data over the defaults, resolves secrets and validates.
func Parse(data []byte, getenv func(string) string) (*Config, error) {
	cfg := Default()
	if len(bytes.TrimSpace(data)) > 0 {
		dec := yaml.NewDecoder(bytes.NewReader(data))
		dec.KnownFields(true)
		if err := dec.Decode(&cfg); err != nil && !errors.Is(err, io.EOF) {
			return nil, fmt.Errorf("parse config: %w", err)
		}
	}
	// Only the selected provider's key is read from the environment.
	switch cfg.AI.Provider {
	case ProviderGemini:
		if cfg.AI.Gemini.APIKeyEnv != "" {
			cfg.AI.Gemini.APIKey = getenv(cfg.AI.Gemini.APIKeyEnv)
		}
	case ProviderOpenRouter:
		if cfg.AI.OpenRouter.APIKeyEnv != "" {
			cfg.AI.OpenRouter.APIKey = getenv(cfg.AI.OpenRouter.APIKeyEnv)
		}
	case ProviderRouterAI:
		if cfg.AI.RouterAI.APIKeyEnv != "" {
			cfg.AI.RouterAI.APIKey = getenv(cfg.AI.RouterAI.APIKeyEnv)
		}
	}
	if err := cfg.Validate(); err != nil {
		return nil, err
	}
	return &cfg, nil
}

// Validate checks every value and returns all problems joined together.
func (c *Config) Validate() error {
	var errs []error
	bad := func(format string, args ...any) { errs = append(errs, fmt.Errorf(format, args...)) }

	s := c.Server
	if s.Listen == "" {
		bad("server.listen must not be empty")
	}
	if s.Environment != EnvDevelopment && s.Environment != EnvProduction {
		bad("server.environment must be %q or %q, got %q", EnvDevelopment, EnvProduction, s.Environment)
	}
	if (s.TLS.CertFile == "") != (s.TLS.KeyFile == "") {
		bad("server.tls.cert_file and server.tls.key_file must be set together")
	}
	if s.TLS.SelfSigned {
		if s.TLS.CertFile != "" || s.TLS.KeyFile != "" {
			bad("server.tls.self_signed cannot be combined with server.tls.cert_file/key_file")
		}
		if strings.TrimSpace(s.TLS.SelfSignedDir) == "" {
			bad("server.tls.self_signed_dir must not be empty when server.tls.self_signed is true")
		}
	}
	for _, h := range s.TLS.SelfSignedHosts {
		if !validCertHost(h) {
			bad("server.tls.self_signed_hosts: %q is not a DNS name or IP address", h)
		}
	}
	if !s.TLS.Enabled() && !s.AllowPlainHTTP {
		bad("TLS is not configured: set server.tls.cert_file and key_file, or server.tls.self_signed: true, or set server.allow_plain_http: true behind a TLS-terminating proxy")
	}
	if _, err := c.TrustedProxyPrefixes(); err != nil {
		bad("%v", err)
	}
	for name, d := range map[string]time.Duration{
		"server.read_header_timeout": s.ReadHeaderTime,
		"server.read_timeout":        s.ReadTimeout,
		"server.write_timeout":       s.WriteTimeout,
		"server.idle_timeout":        s.IdleTimeout,
		"server.shutdown_timeout":    s.ShutdownTimeout,
		"limits.queue_wait":          c.Limits.QueueWait,
		"limits.replay_ttl":          c.Limits.ReplayTTL,
		"ai.call_timeout":            c.AI.CallTimeout,
		"ai.overall_timeout":         c.AI.OverallTimeout,
	} {
		if d <= 0 {
			bad("%s must be positive", name)
		}
	}

	l := c.Limits
	if l.MaxUploadBytes < 1024 || l.MaxUploadBytes > 32<<20 {
		bad("limits.max_upload_bytes must be between 1024 and 33554432, got %d", l.MaxUploadBytes)
	}
	if l.MaxImageDimensionPx < 64 || l.MaxImageDimensionPx > 16384 {
		bad("limits.max_image_dimension_px must be between 64 and 16384, got %d", l.MaxImageDimensionPx)
	}
	if l.RatePerMinute <= 0 || l.RatePerMinute > 6000 {
		bad("limits.rate_per_minute must be in (0, 6000], got %v", l.RatePerMinute)
	}
	if l.RateBurst < 1 || l.RateBurst > 1000 {
		bad("limits.rate_burst must be between 1 and 1000, got %d", l.RateBurst)
	}
	if l.MaxTrackedClients < 1 {
		bad("limits.max_tracked_clients must be at least 1")
	}
	if l.MaxConcurrentAnalyses < 1 || l.MaxConcurrentAnalyses > 1024 {
		bad("limits.max_concurrent_analyses must be between 1 and 1024, got %d", l.MaxConcurrentAnalyses)
	}
	if l.ReplayMaxEntries < 1 {
		bad("limits.replay_max_entries must be at least 1")
	}
	if l.ProductRatePerMinute <= 0 || l.ProductRatePerMinute > 6000 {
		bad("limits.product_rate_per_minute must be in (0, 6000], got %v", l.ProductRatePerMinute)
	}
	if l.ProductRateBurst < 1 || l.ProductRateBurst > 1000 {
		bad("limits.product_rate_burst must be between 1 and 1000, got %d", l.ProductRateBurst)
	}

	cl := c.Client
	if cl.ImageMaxLongSidePx < 256 || cl.ImageMaxLongSidePx > l.MaxImageDimensionPx {
		bad("client.image_max_long_side_px must be between 256 and limits.max_image_dimension_px, got %d", cl.ImageMaxLongSidePx)
	}
	if cl.ImageJPEGQuality < 30 || cl.ImageJPEGQuality > 100 {
		bad("client.image_jpeg_quality must be between 30 and 100, got %d", cl.ImageJPEGQuality)
	}
	if cl.AnalyzeTimeoutSeconds < 1 {
		bad("client.analyze_timeout_seconds must be at least 1")
	}

	a := c.AI
	switch a.Provider {
	case ProviderGemini:
		if a.Gemini.Model == "" {
			bad("ai.gemini.model must not be empty")
		}
		if a.Gemini.BaseURL == "" {
			bad("ai.gemini.base_url must not be empty")
		}
		if a.Gemini.APIKeyEnv == "" {
			bad("ai.gemini.api_key_env must name an environment variable")
		} else if a.Gemini.APIKey == "" {
			bad("environment variable %s (ai.gemini.api_key_env) is empty or not set", a.Gemini.APIKeyEnv)
		}
	case ProviderOpenRouter:
		validateCompat(a.OpenRouter, "ai.openrouter", bad)
	case ProviderRouterAI:
		validateCompat(a.RouterAI, "ai.routerai", bad)
	case ProviderFake:
		if s.Environment == EnvProduction {
			bad("ai.provider %q is not allowed when server.environment is %q", ProviderFake, EnvProduction)
		}
	default:
		bad("ai.provider must be %q, %q, %q or %q, got %q",
			ProviderGemini, ProviderOpenRouter, ProviderRouterAI, ProviderFake, a.Provider)
	}
	if a.MinConfidence < 0 || a.MinConfidence > 1 {
		bad("ai.min_confidence must be between 0 and 1, got %v", a.MinConfidence)
	}
	if a.OverallTimeout < a.CallTimeout {
		bad("ai.overall_timeout must not be shorter than ai.call_timeout")
	}
	if s.WriteTimeout <= a.OverallTimeout {
		bad("server.write_timeout must be longer than ai.overall_timeout so responses can be written")
	}

	if t := c.Nutrition.FuzzyThreshold; t <= 0 || t > 1 {
		bad("nutrition.fuzzy_threshold must be in (0, 1], got %v", t)
	}
	if p := c.Products; p.Enabled {
		if u, err := url.Parse(p.BaseURL); err != nil || u.Host == "" || (u.Scheme != "https" && u.Scheme != "http") {
			bad("products.base_url must be an http(s) URL")
		}
		if p.Timeout <= 0 {
			bad("products.timeout must be positive")
		}
		if p.CacheTTL <= 0 {
			bad("products.cache_ttl must be positive")
		}
		if p.CacheMaxEntries < 1 {
			bad("products.cache_max_entries must be at least 1")
		}
		if strings.ContainsAny(p.UserAgent, "\r\n") {
			bad("products.user_agent must be a single line")
		}
	}
	if c.Metrics.Listen == "" {
		bad("metrics.listen must not be empty")
	}
	if _, err := ParseLevel(c.Log.Level); err != nil {
		bad("%v", err)
	}
	if c.Log.Format != "json" && c.Log.Format != "text" {
		bad("log.format must be \"json\" or \"text\", got %q", c.Log.Format)
	}
	return errors.Join(errs...)
}

// validCertHost accepts an IP address or a plain ASCII host name. A wildcard
// label ("*.lan") is allowed. Certificates cannot carry anything else.
func validCertHost(h string) bool {
	if _, err := netip.ParseAddr(h); err == nil {
		return true
	}
	if h == "" || len(h) > 253 {
		return false
	}
	for _, r := range h {
		ok := r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '-' || r == '.' || r == '*' || r == '_'
		if !ok {
			return false
		}
	}
	return true
}

func validateCompat(c CompatConfig, section string, bad func(string, ...any)) {
	if c.Model == "" {
		bad("%s.model must not be empty", section)
	}
	if u, err := url.Parse(c.BaseURL); err != nil || u.Host == "" || (u.Scheme != "https" && u.Scheme != "http") {
		bad("%s.base_url must be an http(s) URL", section)
	}
	switch {
	case c.APIKeyEnv == "":
		bad("%s.api_key_env must name an environment variable", section)
	case c.APIKey == "":
		bad("environment variable %s (%s.api_key_env) is empty or not set", c.APIKeyEnv, section)
	}
}

// TrustedProxyPrefixes parses server.trusted_proxies. Entries may be single
// addresses or CIDR prefixes.
func (c *Config) TrustedProxyPrefixes() ([]netip.Prefix, error) {
	prefixes := make([]netip.Prefix, 0, len(c.Server.TrustedProxies))
	for _, raw := range c.Server.TrustedProxies {
		raw = strings.TrimSpace(raw)
		if p, err := netip.ParsePrefix(raw); err == nil {
			prefixes = append(prefixes, p.Masked())
			continue
		}
		addr, err := netip.ParseAddr(raw)
		if err != nil {
			return nil, fmt.Errorf("server.trusted_proxies: %q is not an IP address or CIDR prefix", raw)
		}
		prefixes = append(prefixes, netip.PrefixFrom(addr, addr.BitLen()))
	}
	return prefixes, nil
}

// ParseLevel converts a level name into a slog level.
func ParseLevel(name string) (slog.Level, error) {
	var lvl slog.Level
	switch strings.ToLower(name) {
	case "debug":
		lvl = slog.LevelDebug
	case "info":
		lvl = slog.LevelInfo
	case "warn":
		lvl = slog.LevelWarn
	case "error":
		lvl = slog.LevelError
	default:
		return lvl, fmt.Errorf("log.level must be one of debug, info, warn, error, got %q", name)
	}
	return lvl, nil
}
