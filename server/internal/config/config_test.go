package config

import (
	"strings"
	"testing"
	"time"
)

func env(vars map[string]string) func(string) string {
	return func(k string) string { return vars[k] }
}

const validGemini = `
server:
  allow_plain_http: true
`

func TestParseDefaultsAndSecret(t *testing.T) {
	t.Parallel()

	cfg, err := Parse([]byte(validGemini), env(map[string]string{"GEMINI_API_KEY": "secret-key"}))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if cfg.AI.Gemini.APIKey != "secret-key" {
		t.Errorf("api key not resolved from environment")
	}
	if cfg.Limits.MaxUploadBytes != 4<<20 || cfg.Limits.RatePerMinute != 10 || cfg.Limits.RateBurst != 3 {
		t.Errorf("unexpected limit defaults: %+v", cfg.Limits)
	}
	if cfg.AI.CallTimeout != 45*time.Second || cfg.AI.OverallTimeout != 60*time.Second {
		t.Errorf("unexpected AI timeout defaults: %+v", cfg.AI)
	}
	if cfg.Server.ShutdownTimeout != 30*time.Second {
		t.Errorf("unexpected shutdown timeout: %v", cfg.Server.ShutdownTimeout)
	}
}

func TestParseOverridesDurationsAndProxies(t *testing.T) {
	t.Parallel()

	yamlDoc := `
server:
  allow_plain_http: true
  trusted_proxies: ["10.0.0.0/8", "192.168.1.5"]
  shutdown_timeout: 5s
ai:
  provider: fake
`
	cfg, err := Parse([]byte(yamlDoc), env(nil))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if cfg.Server.ShutdownTimeout != 5*time.Second {
		t.Errorf("shutdown timeout = %v", cfg.Server.ShutdownTimeout)
	}
	prefixes, err := cfg.TrustedProxyPrefixes()
	if err != nil || len(prefixes) != 2 {
		t.Fatalf("prefixes = %v, err = %v", prefixes, err)
	}
	if prefixes[1].Bits() != 32 {
		t.Errorf("single address should become a /32, got %v", prefixes[1])
	}
}

func TestSelfSignedSatisfiesTLSRequirement(t *testing.T) {
	t.Parallel()

	cfg, err := Parse([]byte("server:\n  tls:\n    self_signed: true\n    self_signed_hosts: [\"calsnap.lan\", \"192.168.1.10\"]\nai:\n  provider: fake\n"), env(nil))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if !cfg.Server.TLS.Enabled() {
		t.Error("self-signed TLS must count as native TLS")
	}
	if cfg.Server.TLS.SelfSignedDir != "certs" {
		t.Errorf("default directory = %q", cfg.Server.TLS.SelfSignedDir)
	}
	if got := cfg.Server.TLS.SelfSignedHosts; len(got) != 2 || got[0] != "calsnap.lan" {
		t.Errorf("hosts = %v", got)
	}
}

func TestParseErrors(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		yaml    string
		env     map[string]string
		wantErr string
	}{
		{
			name:    "no TLS and no explicit plain HTTP",
			yaml:    "ai:\n  provider: fake\n",
			wantErr: "TLS is not configured",
		},
		{
			name:    "TLS files must come together",
			yaml:    "server:\n  tls:\n    cert_file: a.pem\nai:\n  provider: fake\n",
			wantErr: "must be set together",
		},
		{
			name:    "self-signed conflicts with certificate files",
			yaml:    "server:\n  tls:\n    self_signed: true\n    cert_file: a.pem\n    key_file: b.pem\nai:\n  provider: fake\n",
			wantErr: "cannot be combined",
		},
		{
			name:    "self-signed needs a directory",
			yaml:    "server:\n  tls:\n    self_signed: true\n    self_signed_dir: \"  \"\nai:\n  provider: fake\n",
			wantErr: "self_signed_dir must not be empty",
		},
		{
			name:    "self-signed host must be a name or address",
			yaml:    "server:\n  tls:\n    self_signed: true\n    self_signed_hosts: [\"ok.lan\", \"bad host/\"]\nai:\n  provider: fake\n",
			wantErr: "self_signed_hosts",
		},
		{
			name:    "fake provider forbidden in production",
			yaml:    "server:\n  allow_plain_http: true\n  environment: production\nai:\n  provider: fake\n",
			wantErr: "not allowed when server.environment",
		},
		{
			name:    "missing key names the variable but not a value",
			yaml:    validGemini,
			wantErr: "GEMINI_API_KEY",
		},
		{
			name:    "custom key variable is reported",
			yaml:    "server:\n  allow_plain_http: true\nai:\n  gemini:\n    api_key_env: MY_KEY\n",
			wantErr: "MY_KEY",
		},
		{
			name:    "unknown provider",
			yaml:    "server:\n  allow_plain_http: true\nai:\n  provider: openai\n",
			wantErr: "ai.provider must be",
		},
		{
			name:    "openrouter missing key names the variable",
			yaml:    "server:\n  allow_plain_http: true\nai:\n  provider: openrouter\n",
			wantErr: "OPENROUTER_API_KEY",
		},
		{
			name:    "routerai missing key names the variable",
			yaml:    "server:\n  allow_plain_http: true\nai:\n  provider: routerai\n",
			wantErr: "ROUTERAI_API_KEY",
		},
		{
			name:    "openrouter custom key variable is reported",
			yaml:    "server:\n  allow_plain_http: true\nai:\n  provider: openrouter\n  openrouter:\n    api_key_env: MY_ROUTER_KEY\n",
			wantErr: "MY_ROUTER_KEY",
		},
		{
			name:    "openrouter empty model",
			yaml:    "server:\n  allow_plain_http: true\nai:\n  provider: openrouter\n  openrouter:\n    model: \"\"\n",
			env:     map[string]string{"OPENROUTER_API_KEY": "k"},
			wantErr: "ai.openrouter.model",
		},
		{
			name:    "routerai invalid base url",
			yaml:    "server:\n  allow_plain_http: true\nai:\n  provider: routerai\n  routerai:\n    base_url: not-a-url\n",
			env:     map[string]string{"ROUTERAI_API_KEY": "k"},
			wantErr: "ai.routerai.base_url",
		},
		{
			name:    "routerai non-http scheme",
			yaml:    "server:\n  allow_plain_http: true\nai:\n  provider: routerai\n  routerai:\n    base_url: ftp://example.com\n",
			env:     map[string]string{"ROUTERAI_API_KEY": "k"},
			wantErr: "ai.routerai.base_url",
		},
		{
			name:    "unknown key is rejected",
			yaml:    "server:\n  allow_plain_http: true\n  lisen: \":1\"\n",
			wantErr: "field lisen not found",
		},
		{
			name:    "rate out of range",
			yaml:    "server:\n  allow_plain_http: true\nai:\n  provider: fake\nlimits:\n  rate_per_minute: 0\n",
			wantErr: "limits.rate_per_minute",
		},
		{
			name:    "upload limit too large",
			yaml:    "server:\n  allow_plain_http: true\nai:\n  provider: fake\nlimits:\n  max_upload_bytes: 999999999\n",
			wantErr: "limits.max_upload_bytes",
		},
		{
			name:    "client image side above server maximum",
			yaml:    "server:\n  allow_plain_http: true\nai:\n  provider: fake\nclient:\n  image_max_long_side_px: 9000\n",
			wantErr: "client.image_max_long_side_px",
		},
		{
			name:    "write timeout must exceed AI deadline",
			yaml:    "server:\n  allow_plain_http: true\n  write_timeout: 30s\nai:\n  provider: fake\n",
			wantErr: "server.write_timeout",
		},
		{
			name:    "bad proxy",
			yaml:    "server:\n  allow_plain_http: true\n  trusted_proxies: [\"nope\"]\nai:\n  provider: fake\n",
			wantErr: "trusted_proxies",
		},
		{
			name:    "bad log level",
			yaml:    "server:\n  allow_plain_http: true\nai:\n  provider: fake\nlog:\n  level: loud\n",
			wantErr: "log.level",
		},
		{
			name:    "bad environment",
			yaml:    "server:\n  allow_plain_http: true\n  environment: staging\nai:\n  provider: fake\n",
			wantErr: "server.environment",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			_, err := Parse([]byte(tt.yaml), env(tt.env))
			if err == nil {
				t.Fatalf("expected error containing %q", tt.wantErr)
			}
			if !strings.Contains(err.Error(), tt.wantErr) {
				t.Errorf("error %q does not contain %q", err, tt.wantErr)
			}
		})
	}
}

func TestErrorNeverContainsSecretValue(t *testing.T) {
	t.Parallel()

	yamlDoc := "server:\n  allow_plain_http: true\n  environment: staging\n"
	_, err := Parse([]byte(yamlDoc), env(map[string]string{"GEMINI_API_KEY": "super-secret-value"}))
	if err == nil {
		t.Fatal("expected an error")
	}
	if strings.Contains(err.Error(), "super-secret-value") {
		t.Errorf("error leaks the secret: %v", err)
	}
}

func TestExampleConfigIsValid(t *testing.T) {
	t.Parallel()

	cfg, err := Load("../../../config.example.yaml", env(map[string]string{"GEMINI_API_KEY": "placeholder"}))
	if err != nil {
		t.Fatalf("config.example.yaml must load: %v", err)
	}
	def := Default()
	def.AI.Gemini.APIKey = "placeholder"
	if cfg.Limits != def.Limits || cfg.AI != def.AI || cfg.Client != def.Client || cfg.Nutrition != def.Nutrition {
		t.Errorf("config.example.yaml values drifted from Default():\n got %+v\nwant %+v", cfg, def)
	}
}

func TestParseCompatProviders(t *testing.T) {
	t.Parallel()

	tests := []struct {
		provider, envVar, baseURL string
		pick                      func(AIConfig) CompatConfig
	}{
		{ProviderOpenRouter, "OPENROUTER_API_KEY", "https://openrouter.ai/api/v1", func(a AIConfig) CompatConfig { return a.OpenRouter }},
		{ProviderRouterAI, "ROUTERAI_API_KEY", "https://routerai.ru/api/v1", func(a AIConfig) CompatConfig { return a.RouterAI }},
	}
	for _, tt := range tests {
		t.Run(tt.provider, func(t *testing.T) {
			t.Parallel()
			doc := "server:\n  allow_plain_http: true\nai:\n  provider: " + tt.provider + "\n"
			cfg, err := Parse([]byte(doc), env(map[string]string{tt.envVar: "the-key"}))
			if err != nil {
				t.Fatalf("Parse: %v", err)
			}
			c := tt.pick(cfg.AI)
			if c.APIKey != "the-key" || c.BaseURL != tt.baseURL || c.Model == "" {
				t.Errorf("compat config = %+v", c)
			}
		})
	}
}

func TestCompatKeyIsOnlyResolvedForSelectedProvider(t *testing.T) {
	t.Parallel()

	doc := "server:\n  allow_plain_http: true\nai:\n  provider: openrouter\n"
	cfg, err := Parse([]byte(doc), env(map[string]string{"OPENROUTER_API_KEY": "a", "ROUTERAI_API_KEY": "b", "GEMINI_API_KEY": "c"}))
	if err != nil {
		t.Fatal(err)
	}
	if cfg.AI.RouterAI.APIKey != "" || cfg.AI.Gemini.APIKey != "" {
		t.Error("keys of unselected providers must not be loaded")
	}
}
