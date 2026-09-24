package selfsigned

import (
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"example.com/calsnap/server/internal/testutil"
)

var fixedNow = time.Date(2026, 3, 10, 12, 0, 0, 0, time.UTC)

// managed returns options for a directory owned by the server.
func managed(dir string, hosts []string, now time.Time) Options {
	return Options{
		CertFile: filepath.Join(dir, CertFileName),
		KeyFile:  filepath.Join(dir, KeyFileName),
		Managed:  true,
		Hosts:    hosts,
		Now:      func() time.Time { return now },
	}
}

// unmanaged returns options for operator-configured paths.
func unmanaged(dir string, now time.Time) Options {
	return Options{
		CertFile: filepath.Join(dir, "sub", "server.crt"),
		KeyFile:  filepath.Join(dir, "sub", "server.key"),
		Now:      func() time.Time { return now },
	}
}

func parseCert(t *testing.T, path string) *x509.Certificate {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	block, _ := pem.Decode(data)
	if block == nil {
		t.Fatalf("%s holds no PEM block", path)
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		t.Fatal(err)
	}
	return cert
}

func TestEnsureCreatesUsableCertificate(t *testing.T) {
	t.Parallel()

	dir := filepath.Join(t.TempDir(), "nested", "tls")
	res, err := Ensure(managed(dir, []string{"calsnap.lan", "192.168.1.10", "::1", "CalSnap.LAN", " ", ""}, fixedNow))
	if err != nil {
		t.Fatalf("Ensure: %v", err)
	}
	if !res.Created {
		t.Error("a first call must create the certificate")
	}
	if _, err := tls.LoadX509KeyPair(res.CertFile, res.KeyFile); err != nil {
		t.Fatalf("key pair is not loadable: %v", err)
	}

	cert := parseCert(t, res.CertFile)
	if got := Fingerprint(cert.Raw); got != res.Fingerprint {
		t.Errorf("fingerprint = %s, want %s", res.Fingerprint, got)
	}
	if !regexp.MustCompile(`^([0-9A-F]{2}:){31}[0-9A-F]{2}$`).MatchString(res.Fingerprint) {
		t.Errorf("fingerprint %q is not colon-separated upper-case SHA-256", res.Fingerprint)
	}
	if cert.IsCA {
		t.Error("the certificate must not be a CA")
	}
	if len(cert.ExtKeyUsage) != 1 || cert.ExtKeyUsage[0] != x509.ExtKeyUsageServerAuth {
		t.Errorf("ext key usage = %v", cert.ExtKeyUsage)
	}
	if len(cert.DNSNames) != 1 || cert.DNSNames[0] != "calsnap.lan" {
		t.Errorf("DNS names = %v (duplicates and blanks must be dropped)", cert.DNSNames)
	}
	if len(cert.IPAddresses) != 2 {
		t.Errorf("IP addresses = %v", cert.IPAddresses)
	}
	if !cert.NotBefore.Before(fixedNow) || !cert.NotAfter.After(fixedNow.Add(365*24*time.Hour)) {
		t.Errorf("validity %v..%v does not surround the current time", cert.NotBefore, cert.NotAfter)
	}
	if !res.NotAfter.Equal(cert.NotAfter) {
		t.Errorf("NotAfter = %v, want %v", res.NotAfter, cert.NotAfter)
	}
	if err := cert.VerifyHostname("192.168.1.10"); err != nil {
		t.Errorf("the certificate must cover the configured IP: %v", err)
	}
}

func TestEnsureReusesValidCertificate(t *testing.T) {
	t.Parallel()

	opts := managed(t.TempDir(), []string{"a.example"}, fixedNow)
	first, err := Ensure(opts)
	if err != nil {
		t.Fatal(err)
	}
	// Different hosts and a later time inside the validity window: the pinned
	// certificate must stay as it is.
	opts.Hosts = []string{"b.example"}
	opts.Now = func() time.Time { return fixedNow.Add(200 * 24 * time.Hour) }
	second, err := Ensure(opts)
	if err != nil {
		t.Fatal(err)
	}
	if second.Created {
		t.Error("a valid certificate must not be regenerated")
	}
	if second.Fingerprint != first.Fingerprint {
		t.Errorf("fingerprint changed from %s to %s", first.Fingerprint, second.Fingerprint)
	}
}

func TestEnsureRegenerates(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name   string
		later  time.Duration
		mutate func(t *testing.T, res Result)
	}{
		{name: "expires soon", later: 2*365*24*time.Hour - 10*24*time.Hour},
		{name: "expired", later: 3 * 365 * 24 * time.Hour},
		{
			name: "key does not match",
			mutate: func(t *testing.T, res Result) {
				other, err := Ensure(managed(t.TempDir(), nil, fixedNow))
				if err != nil {
					t.Fatal(err)
				}
				data, err := os.ReadFile(other.KeyFile)
				if err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(res.KeyFile, data, 0o600); err != nil {
					t.Fatal(err)
				}
			},
		},
		{
			name: "certificate file is garbage",
			mutate: func(t *testing.T, res Result) {
				if err := os.WriteFile(res.CertFile, []byte("not a certificate"), 0o600); err != nil {
					t.Fatal(err)
				}
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			now := fixedNow
			opts := managed(t.TempDir(), nil, fixedNow)
			opts.Now = func() time.Time { return now }
			first, err := Ensure(opts)
			if err != nil {
				t.Fatal(err)
			}
			if tt.mutate != nil {
				tt.mutate(t, first)
			}
			now = fixedNow.Add(tt.later)
			second, err := Ensure(opts)
			if err != nil {
				t.Fatal(err)
			}
			if !second.Created || second.Fingerprint == first.Fingerprint {
				t.Errorf("expected a new certificate, got created=%v same=%v", second.Created, second.Fingerprint == first.Fingerprint)
			}
			if _, err := tls.LoadX509KeyPair(second.CertFile, second.KeyFile); err != nil {
				t.Errorf("regenerated pair is not loadable: %v", err)
			}
		})
	}
}

func TestEnsureRejectsEmptyPaths(t *testing.T) {
	t.Parallel()

	if _, err := Ensure(Options{}); err == nil {
		t.Fatal("empty paths must be rejected")
	}
}

func TestEnsureCreatesMissingConfiguredFiles(t *testing.T) {
	t.Parallel()

	opts := unmanaged(t.TempDir(), fixedNow)
	first, err := Ensure(opts)
	if err != nil {
		t.Fatalf("Ensure: %v", err)
	}
	if !first.Created || first.CertFile != opts.CertFile || first.KeyFile != opts.KeyFile {
		t.Fatalf("unexpected result %+v", first)
	}
	if _, err := tls.LoadX509KeyPair(opts.CertFile, opts.KeyFile); err != nil {
		t.Fatalf("generated pair is not loadable: %v", err)
	}

	second, err := Ensure(opts)
	if err != nil {
		t.Fatal(err)
	}
	if second.Created || second.Fingerprint != first.Fingerprint {
		t.Errorf("the generated pair must be reused, got created=%v", second.Created)
	}

	// A generated certificate that is about to expire is renewed in place.
	opts.Now = func() time.Time { return fixedNow.Add(2*365*24*time.Hour - 10*24*time.Hour) }
	third, err := Ensure(opts)
	if err != nil {
		t.Fatal(err)
	}
	if !third.Created || third.Fingerprint == first.Fingerprint {
		t.Error("an expiring generated certificate must be renewed")
	}
}

// Files the operator provides are never overwritten, even when they look wrong.
func TestEnsureLeavesForeignFilesAlone(t *testing.T) {
	t.Parallel()

	certPEM := testutil.Fixture(t, "tls-selfsigned.crt")
	keyPEM := testutil.Fixture(t, "tls-selfsigned.key")
	write := func(t *testing.T, opts Options, cert, key []byte) {
		t.Helper()
		if err := os.MkdirAll(filepath.Dir(opts.CertFile), 0o700); err != nil {
			t.Fatal(err)
		}
		if cert != nil {
			if err := os.WriteFile(opts.CertFile, cert, 0o600); err != nil {
				t.Fatal(err)
			}
		}
		if key != nil {
			if err := os.WriteFile(opts.KeyFile, key, 0o600); err != nil {
				t.Fatal(err)
			}
		}
	}
	unchanged := func(t *testing.T, path string, want []byte) {
		t.Helper()
		got, err := os.ReadFile(path)
		if err != nil || string(got) != string(want) {
			t.Errorf("%s was modified (err=%v)", path, err)
		}
	}

	t.Run("a valid foreign pair is used even when it is expired", func(t *testing.T) {
		t.Parallel()
		// The fixture expires in 2126; the clock is after that.
		opts := unmanaged(t.TempDir(), time.Date(2200, 1, 1, 0, 0, 0, 0, time.UTC))
		write(t, opts, certPEM, keyPEM)
		res, err := Ensure(opts)
		if err != nil {
			t.Fatalf("Ensure: %v", err)
		}
		if res.Created {
			t.Error("a foreign certificate must not be replaced")
		}
		unchanged(t, opts.CertFile, certPEM)
	})

	t.Run("only the key exists", func(t *testing.T) {
		t.Parallel()
		opts := unmanaged(t.TempDir(), fixedNow)
		write(t, opts, nil, keyPEM)
		if _, err := Ensure(opts); err == nil {
			t.Error("a half-present pair must be an error, not a reason to generate")
		}
		unchanged(t, opts.KeyFile, keyPEM)
	})

	t.Run("only the certificate exists", func(t *testing.T) {
		t.Parallel()
		opts := unmanaged(t.TempDir(), fixedNow)
		write(t, opts, certPEM, nil)
		if _, err := Ensure(opts); err == nil {
			t.Error("a half-present pair must be an error, not a reason to generate")
		}
		unchanged(t, opts.CertFile, certPEM)
	})

	t.Run("a foreign certificate that does not match its key", func(t *testing.T) {
		t.Parallel()
		other, err := Ensure(managed(t.TempDir(), nil, fixedNow))
		if err != nil {
			t.Fatal(err)
		}
		otherKey, err := os.ReadFile(other.KeyFile)
		if err != nil {
			t.Fatal(err)
		}
		opts := unmanaged(t.TempDir(), fixedNow)
		write(t, opts, certPEM, otherKey)
		if _, err := Ensure(opts); err == nil {
			t.Error("a mismatching foreign pair must be an error")
		}
		unchanged(t, opts.CertFile, certPEM)
	})

	t.Run("garbage in the certificate file", func(t *testing.T) {
		t.Parallel()
		opts := unmanaged(t.TempDir(), fixedNow)
		write(t, opts, []byte("not a certificate"), keyPEM)
		if _, err := Ensure(opts); err == nil {
			t.Error("unreadable foreign files must be an error")
		}
		unchanged(t, opts.CertFile, []byte("not a certificate"))
	})
}

func TestFingerprintIsStable(t *testing.T) {
	t.Parallel()

	// SHA-256 of the empty input.
	const want = "E3:B0:C4:42:98:FC:1C:14:9A:FB:F4:C8:99:6F:B9:24:27:AE:41:E4:64:9B:93:4C:A4:95:99:1B:78:52:B8:55"
	if got := Fingerprint(nil); got != want {
		t.Errorf("Fingerprint(nil) = %s, want %s", got, want)
	}
}

// The app computes the same fingerprint in Dart; both sides are checked against
// the value openssl produced for the shared fixture certificate.
func TestFingerprintMatchesSharedFixture(t *testing.T) {
	t.Parallel()

	block, _ := pem.Decode(testutil.Fixture(t, "tls-selfsigned.crt"))
	if block == nil {
		t.Fatal("fixture holds no PEM block")
	}
	want := strings.TrimSpace(string(testutil.Fixture(t, "tls-selfsigned.fingerprint.txt")))
	if got := Fingerprint(block.Bytes); got != want {
		t.Errorf("Fingerprint = %s, want %s", got, want)
	}
}

func TestLocalHostsIncludesLoopback(t *testing.T) {
	t.Parallel()

	got := map[string]bool{}
	for _, h := range LocalHosts() {
		got[h] = true
	}
	for _, want := range []string{"localhost", "127.0.0.1", "::1"} {
		if !got[want] {
			t.Errorf("LocalHosts is missing %s", want)
		}
	}
}
