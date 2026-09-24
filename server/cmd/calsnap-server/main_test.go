package main

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"io"
	"log/slog"
	"math/big"
	"mime/multipart"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"example.com/calsnap/server/internal/config"
	"example.com/calsnap/server/internal/testutil"
)

func testConfig(t *testing.T, extraYAML string) *config.Config {
	t.Helper()
	cfg, err := config.Parse([]byte("ai:\n  provider: fake\n"+extraYAML), func(string) string { return "" })
	if err != nil {
		t.Fatalf("config: %v", err)
	}
	return cfg
}

func listen(t *testing.T) net.Listener {
	t.Helper()
	ln, err := (&net.ListenConfig{}).Listen(context.Background(), "tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	return ln
}

func multipartImage(t *testing.T) (string, io.Reader) {
	t.Helper()
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	w, err := mw.CreateFormFile("image", "sample.jpg")
	if err != nil {
		t.Fatal(err)
	}
	_, _ = w.Write(testutil.Fixture(t, "sample.jpg"))
	_ = mw.Close()
	return mw.FormDataContentType(), &buf
}

func TestGracefulShutdownLetsInFlightRequestFinish(t *testing.T) {
	t.Parallel()

	cfg := testConfig(t, "server:\n  allow_plain_http: true\n  shutdown_timeout: 10s\n")
	rt, err := build(cfg, slog.New(slog.DiscardHandler))
	if err != nil {
		t.Fatal(err)
	}
	started, release := make(chan struct{}), make(chan struct{})
	inner := rt.api.Handler
	rt.api.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		close(started)
		<-release
		inner.ServeHTTP(w, r)
	})

	apiLn, metricsLn := listen(t), listen(t)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	served := make(chan error, 1)
	go func() { served <- rt.serve(ctx, apiLn, metricsLn) }()

	type result struct {
		status int
		err    error
	}
	got := make(chan result, 1)
	go func() {
		ct, body := multipartImage(t)
		req, _ := http.NewRequestWithContext(context.Background(), http.MethodPost, "http://"+apiLn.Addr().String()+"/v1/meals/analyze", body)
		req.Header.Set("Content-Type", ct)
		resp, err := (&http.Client{Timeout: 15 * time.Second}).Do(req)
		if err != nil {
			got <- result{err: err}
			return
		}
		defer resp.Body.Close()
		_, _ = io.Copy(io.Discard, resp.Body)
		got <- result{status: resp.StatusCode}
	}()

	<-started
	cancel() // simulates SIGTERM

	select {
	case err := <-served:
		t.Fatalf("server exited while a request was in flight (err=%v)", err)
	case <-time.After(200 * time.Millisecond):
	}

	close(release)
	if r := <-got; r.err != nil || r.status != http.StatusOK {
		t.Fatalf("in-flight request: status=%d err=%v", r.status, r.err)
	}
	select {
	case err := <-served:
		if err != nil {
			t.Fatalf("serve returned %v, want nil (exit status 0)", err)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("server did not stop after the request finished")
	}

	if conn, err := (&net.Dialer{Timeout: time.Second}).DialContext(context.Background(), "tcp", apiLn.Addr().String()); err == nil {
		_ = conn.Close()
		t.Error("new connections must be refused after shutdown")
	}
}

func selfSignedCert(t *testing.T, dir string) (certFile, keyFile string, pool *x509.CertPool) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	tmpl := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: "localhost"},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(time.Hour),
		KeyUsage:              x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		DNSNames:              []string{"localhost"},
		IPAddresses:           []net.IP{net.ParseIP("127.0.0.1")},
		BasicConstraintsValid: true,
		IsCA:                  true,
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	keyDER, err := x509.MarshalECPrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	certFile, keyFile = filepath.Join(dir, "cert.pem"), filepath.Join(dir, "key.pem")
	if err := os.WriteFile(certFile, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(keyFile, pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: keyDER}), 0o600); err != nil {
		t.Fatal(err)
	}
	pool = x509.NewCertPool()
	cert, _ := x509.ParseCertificate(der)
	pool.AddCert(cert)
	return certFile, keyFile, pool
}

func TestTLSRequiresVersion12(t *testing.T) {
	t.Parallel()

	certFile, keyFile, pool := selfSignedCert(t, t.TempDir())
	cfg := testConfig(t, "server:\n  tls:\n    cert_file: "+filepath.ToSlash(certFile)+"\n    key_file: "+filepath.ToSlash(keyFile)+"\n")
	rt, err := build(cfg, slog.New(slog.DiscardHandler))
	if err != nil {
		t.Fatal(err)
	}
	apiLn, metricsLn := listen(t), listen(t)
	ctx, cancel := context.WithCancel(context.Background())
	served := make(chan error, 1)
	go func() { served <- rt.serve(ctx, apiLn, metricsLn) }()
	t.Cleanup(func() {
		cancel()
		if err := <-served; err != nil {
			t.Errorf("serve: %v", err)
		}
	})

	addr := apiLn.Addr().String()
	dial := func(lowest, highest uint16) error {
		d := &tls.Dialer{Config: &tls.Config{RootCAs: pool, ServerName: "localhost", MinVersion: lowest, MaxVersion: highest}}
		conn, err := d.DialContext(context.Background(), "tcp", addr)
		if err == nil {
			_ = conn.Close()
		}
		return err
	}
	if err := dial(tls.VersionTLS12, tls.VersionTLS13); err != nil {
		t.Errorf("TLS 1.2+ handshake failed: %v", err)
	}
	if err := dial(tls.VersionTLS10, tls.VersionTLS11); err == nil {
		t.Error("TLS 1.1 handshake must be rejected")
	}

	client := &http.Client{Timeout: 5 * time.Second, Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: pool, ServerName: "localhost"}}}
	resp, err := client.Get("https://" + addr + "/healthz") //nolint:noctx // test against a local listener
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Errorf("healthz status = %d", resp.StatusCode)
	}
}

func TestRunConfigurationErrors(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	write := func(name, content string) string {
		p := filepath.Join(dir, name)
		if err := os.WriteFile(p, []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
		return p
	}
	noKey := func(string) string { return "" }

	tests := []struct {
		name     string
		args     []string
		wantCode int
		wantOut  string
		wantErr  string
	}{
		{"version", []string{"-version"}, exitOK, "calsnap-server", ""},
		{"no TLS and no explicit flag", []string{"-config", write("a.yaml", "ai:\n  provider: fake\n")}, exitUsage, "", "TLS is not configured"},
		{"missing key", []string{"-config", write("b.yaml", "server:\n  allow_plain_http: true\n")}, exitUsage, "", "GEMINI_API_KEY"},
		{"fake in production", []string{"-config", write("c.yaml", "server:\n  allow_plain_http: true\n  environment: production\nai:\n  provider: fake\n")}, exitUsage, "", "not allowed"},
		{"unreadable config", []string{"-config", filepath.Join(dir, "missing.yaml")}, exitUsage, "", "read config"},
		{"bad flag", []string{"-nope"}, exitUsage, "", "flag provided but not defined"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			var stdout, stderr bytes.Buffer
			code := run(tt.args, &stdout, &stderr, noKey)
			if code != tt.wantCode {
				t.Fatalf("exit code = %d, want %d (stderr: %s)", code, tt.wantCode, stderr.String())
			}
			if !strings.Contains(stdout.String(), tt.wantOut) || !strings.Contains(stderr.String(), tt.wantErr) {
				t.Errorf("stdout=%q stderr=%q", stdout.String(), stderr.String())
			}
		})
	}
}
