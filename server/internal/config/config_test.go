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
