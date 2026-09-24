// Package testutil gives tests access to the cross-language protocol fixtures.
package testutil

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

// ProtocolDir returns the absolute path of the repository's protocol directory.
func ProtocolDir(t testing.TB) string {
	t.Helper()
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("cannot determine test helper location")
	}
	// file is <repo>/server/internal/testutil/fixtures.go
	return filepath.Join(filepath.Dir(file), "..", "..", "..", "protocol")
}

// Fixture reads protocol/fixtures/<name>.
func Fixture(t testing.TB, name string) []byte {
	t.Helper()
	return ReadProtocol(t, filepath.Join("fixtures", name))
}

// ReadProtocol reads a file relative to the protocol directory.
func ReadProtocol(t testing.TB, rel string) []byte {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(ProtocolDir(t), rel)) //nolint:gosec // test helper with fixed layout
	if err != nil {
		t.Fatalf("read protocol file %s: %v", rel, err)
	}
	return data
}
