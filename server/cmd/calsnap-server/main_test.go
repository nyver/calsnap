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
	"errors"
	"io"
	"log/slog"
	"math/big"
	"mime/multipart"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"example.com/calsnap/server/internal/config"
	"example.com/calsnap/server/internal/selfsigned"
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

func TestSelfSignedServesHTTPSWithStablePinnedFingerprint(t *testing.T) {
	t.Parallel()

	dir := filepath.ToSlash(t.TempDir())
	cfg := testConfig(t, "server:\n  tls:\n    self_signed: true\n    self_signed_dir: "+dir+"\n")

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

	first := readFingerprint(t, filepath.Join(dir, selfsigned.CertFileName))
	addr := apiLn.Addr().String()

	// A client that trusts only the pinned fingerprint, like the app after the
	// user confirmed it. System roots must not be involved.
	pinned := func(fingerprint string) *http.Client {
		return &http.Client{Timeout: 5 * time.Second, Transport: &http.Transport{TLSClientConfig: &tls.Config{
			InsecureSkipVerify: true, //nolint:gosec // verification is replaced by the fingerprint check below
			VerifyPeerCertificate: func(raw [][]byte, _ [][]*x509.Certificate) error {
				if got := selfsigned.Fingerprint(raw[0]); got != fingerprint {
					return errors.New("fingerprint mismatch: " + got)
				}
				return nil
			},
		}}}
	}
	resp, err := pinned(first).Get("https://" + addr + "/healthz") //nolint:noctx // test against a local listener
	if err != nil {
		t.Fatalf("pinned client: %v", err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Errorf("healthz status = %d", resp.StatusCode)
	}

	// A default client (system roots) must refuse the certificate.
	plain := &http.Client{Timeout: 5 * time.Second}
	if resp, err := plain.Get("https://" + addr + "/healthz"); err == nil { //nolint:noctx // test against a local listener
		_ = resp.Body.Close()
		t.Error("a client without the pin must reject the self-signed certificate")
	}

	// A second start over the same directory keeps the certificate, so the
	// fingerprint the user confirmed stays valid across restarts.
	if _, err := build(cfg, slog.New(slog.DiscardHandler)); err != nil {
		t.Fatal(err)
	}
	if again := readFingerprint(t, filepath.Join(dir, selfsigned.CertFileName)); again != first {
		t.Errorf("fingerprint changed across restarts: %s -> %s", first, again)
	}
}

func TestMissingCertificateFilesAreGenerated(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	certFile := filepath.Join(dir, "tls", "server.crt")
	keyFile := filepath.Join(dir, "tls", "server.key")
	cfg := testConfig(t, "server:\n  tls:\n    cert_file: "+filepath.ToSlash(certFile)+"\n    key_file: "+filepath.ToSlash(keyFile)+"\n")

	rt, err := build(cfg, slog.New(slog.DiscardHandler))
	if err != nil {
		t.Fatalf("build must create the missing files: %v", err)
	}
	if rt.api.TLSConfig == nil || filepath.ToSlash(rt.certFile) != filepath.ToSlash(certFile) || filepath.ToSlash(rt.keyFile) != filepath.ToSlash(keyFile) {
		t.Fatalf("expected native TLS with the configured paths, got %+v", rt)
	}
	first := readFingerprint(t, certFile)

	// The next start finds the files and keeps them.
	if _, err := build(cfg, slog.New(slog.DiscardHandler)); err != nil {
		t.Fatal(err)
	}
	if again := readFingerprint(t, certFile); again != first {
		t.Errorf("fingerprint changed across restarts: %s -> %s", first, again)
	}
}

func readFingerprint(t *testing.T, certFile string) string {
	t.Helper()
	data, err := os.ReadFile(certFile)
	if err != nil {
		t.Fatal(err)
	}
	block, _ := pem.Decode(data)
	if block == nil {
		t.Fatal("no PEM block in " + certFile)
	}
	return selfsigned.Fingerprint(block.Bytes)
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

func TestBarcodeLookupEndToEnd(t *testing.T) {
	t.Parallel()

	var hits int
	var agent string
	off := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits++
		agent = r.Header.Get("User-Agent")
		_, _ = io.WriteString(w, `{"status":1,"product":{"product_name_en":"Plain yogurt","brands":"Danone","serving_quantity":150,`+
			`"nutriments":{"energy-kcal_100g":61,"proteins_100g":3.5,"fat_100g":2.1,"carbohydrates_100g":7.6}}}`)
	}))
	defer off.Close()

	cfg := testConfig(t, "server:\n  allow_plain_http: true\nproducts:\n  base_url: "+off.URL+"\n")
	rt, err := build(cfg, slog.New(slog.DiscardHandler))
	if err != nil {
		t.Fatal(err)
	}
	apiLn, metricsLn := listen(t), listen(t)
	ctx, cancel := context.WithCancel(context.Background())
	served := make(chan error, 1)
	go func() { served <- rt.serve(ctx, apiLn, metricsLn) }()
	defer func() {
		cancel()
		<-served
	}()

	get := func(path string) (int, string) {
		req, _ := http.NewRequestWithContext(context.Background(), http.MethodGet, "http://"+apiLn.Addr().String()+path, http.NoBody)
		resp, err := (&http.Client{Timeout: 5 * time.Second}).Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		b, _ := io.ReadAll(resp.Body)
		return resp.StatusCode, string(b)
	}

	status, body := get("/v1/products/4006381333931")
	if status != http.StatusOK || !strings.Contains(body, `"name":"Plain yogurt"`) || !strings.Contains(body, `"servingSizeG":150`) {
		t.Fatalf("lookup: %d %s", status, body)
	}
	if status, _ = get("/v1/products/4006381333931"); status != http.StatusOK || hits != 1 {
		t.Errorf("the second lookup must come from the cache: status %d, source hits %d", status, hits)
	}
	if !strings.HasPrefix(agent, "CalSnap-server/") {
		t.Errorf("User-Agent = %q", agent)
	}
	if status, body = get("/v1/products/4006381333932"); status != http.StatusBadRequest {
		t.Errorf("bad check digit: %d %s", status, body)
	}
	if _, body = get("/v1/config"); !strings.Contains(body, `"barcodeLookup":true`) || !strings.Contains(body, `"labelReading":true`) {
		t.Errorf("config = %s", body)
	}
}

func TestBarcodeLookupCanBeDisabled(t *testing.T) {
	t.Parallel()

	cfg := testConfig(t, "server:\n  allow_plain_http: true\nproducts:\n  enabled: false\n")
	rt, err := build(cfg, slog.New(slog.DiscardHandler))
	if err != nil {
		t.Fatal(err)
	}
	for path, want := range map[string]struct {
		status int
		body   string
	}{
		"/v1/products/4006381333931": {http.StatusNotFound, ""},
		"/v1/config":                 {http.StatusOK, `"barcodeLookup":false`},
	} {
		rec := httptest.NewRecorder()
		rt.api.Handler.ServeHTTP(rec, httptest.NewRequestWithContext(context.Background(), http.MethodGet, path, http.NoBody))
		if rec.Code != want.status || !strings.Contains(rec.Body.String(), want.body) {
			t.Errorf("%s: %d %s", path, rec.Code, rec.Body.String())
		}
	}
}

func TestLabelReadingEndToEnd(t *testing.T) {
	t.Parallel()

	cfg := testConfig(t, "server:\n  allow_plain_http: true\n")
	rt, err := build(cfg, slog.New(slog.DiscardHandler))
	if err != nil {
		t.Fatal(err)
	}
	ct, body := multipartImage(t)
	req := httptest.NewRequestWithContext(context.Background(), http.MethodPost, "/v1/labels/analyze", body)
	req.Header.Set("Content-Type", ct)
	rec := httptest.NewRecorder()
	rt.api.Handler.ServeHTTP(rec, req)
	// The fake provider answers with one of its canned tables, or with a photo
	// that has none; both go through the real use case and transport.
	switch rec.Code {
	case http.StatusOK:
		if !strings.Contains(rec.Body.String(), `"nutrition"`) {
			t.Errorf("body = %s", rec.Body.String())
		}
	case http.StatusUnprocessableEntity:
		if !strings.Contains(rec.Body.String(), "LABEL_NOT_RECOGNIZED") {
			t.Errorf("body = %s", rec.Body.String())
		}
	default:
		t.Errorf("status = %d: %s", rec.Code, rec.Body.String())
	}
}
