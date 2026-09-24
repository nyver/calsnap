package ratelimit

import (
	"context"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"sync"
	"testing"
	"time"
)

type clock struct {
	mu sync.Mutex
	t  time.Time
}

func (c *clock) now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.t
}

func (c *clock) advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.t = c.t.Add(d)
}

func newLimiter(c *clock, maxClients int) *Limiter {
	return New(Config{PerMinute: 10, Burst: 3, MaxClients: maxClients, IdleTTL: 5 * time.Minute, Now: c.now})
}

func TestBurstThenRateLimited(t *testing.T) {
	t.Parallel()

	c := &clock{t: time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)}
	l := newLimiter(c, 100)
	for i := range 3 {
		if ok, _ := l.Allow("a"); !ok {
			t.Fatalf("request %d within burst was rejected", i+1)
		}
	}
	ok, retry := l.Allow("a")
	if ok {
		t.Fatal("4th request must be rejected")
	}
	if retry <= 0 || retry > 7*time.Second {
		t.Errorf("retry after = %v, want about 6s", retry)
	}
	if secs := RetryAfterSeconds(retry); secs < 1 || secs > 7 {
		t.Errorf("Retry-After = %d", secs)
	}

	// Rejected calls must not consume tokens: after the advertised delay one request passes.
	c.advance(retry)
	if ok, _ := l.Allow("a"); !ok {
		t.Error("request after the retry delay must pass")
	}
	if ok, _ := l.Allow("a"); ok {
		t.Error("bucket should be empty again")
	}
}

func TestClientsAreIndependent(t *testing.T) {
	t.Parallel()

	c := &clock{t: time.Now()}
	l := newLimiter(c, 100)
	for range 3 {
		l.Allow("a")
	}
	if ok, _ := l.Allow("a"); ok {
		t.Fatal("a should be limited")
	}
	if ok, _ := l.Allow("b"); !ok {
		t.Fatal("b must not be affected by a")
	}
}

func TestBoundedClientsUseSharedOverflowBucket(t *testing.T) {
	t.Parallel()

	c := &clock{t: time.Now()}
	l := newLimiter(c, 2)
	l.Allow("a")
	l.Allow("b")
	if l.Len() != 2 {
		t.Fatalf("len = %d", l.Len())
	}
	// Any further clients share one bucket of burst 3 and never grow the map.
	allowed := 0
	for i := range 20 {
		if ok, _ := l.Allow(string(rune('c' + i))); ok {
			allowed++
		}
	}
	if allowed != 3 {
		t.Errorf("overflow bucket allowed %d requests, want 3", allowed)
	}
	if l.Len() != 2 {
		t.Errorf("map grew to %d", l.Len())
	}
	// Tracked clients are unaffected by overflow traffic.
	if ok, _ := l.Allow("a"); !ok {
		t.Error("tracked client must keep its own bucket")
	}
}

func TestSweepDropsIdleClients(t *testing.T) {
	t.Parallel()

	c := &clock{t: time.Now()}
	l := newLimiter(c, 100)
	l.Allow("old")
	c.advance(4 * time.Minute)
	l.Allow("recent")
	c.advance(2 * time.Minute)
	l.Sweep()
	if l.Len() != 1 {
		t.Fatalf("len = %d, want only the recent client", l.Len())
	}
}

func TestRunStopsWithContext(t *testing.T) {
	t.Parallel()

	l := newLimiter(&clock{t: time.Now()}, 10)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		l.Run(ctx, time.Hour)
		close(done)
	}()
	cancel()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("Run did not stop after context cancellation")
	}
}

func req(remote string, xff ...string) *http.Request {
	r := httptest.NewRequestWithContext(context.Background(), http.MethodPost, "/", nil)
	r.RemoteAddr = remote
	for _, v := range xff {
		r.Header.Add("X-Forwarded-For", v)
	}
	return r
}

func TestClientKey(t *testing.T) {
	t.Parallel()

	proxy := []netip.Prefix{netip.MustParsePrefix("10.0.0.0/8")}
	tests := []struct {
		name    string
		r       *http.Request
		trusted []netip.Prefix
		want    string
	}{
		{"direct client", req("203.0.113.7:5555"), nil, "203.0.113.7"},
		{"spoofed XFF ignored from untrusted peer", req("203.0.113.7:5555", "1.2.3.4"), proxy, "203.0.113.7"},
		{"varying spoofed XFF shares the real address", req("203.0.113.7:5555", "9.9.9.9, 8.8.8.8"), nil, "203.0.113.7"},
		{"trusted proxy forwards client", req("10.0.0.5:443", "198.51.100.9"), proxy, "198.51.100.9"},
		{"client-supplied prefix cannot spoof", req("10.0.0.5:443", "6.6.6.6, 198.51.100.9"), proxy, "198.51.100.9"},
		{"chain of trusted hops", req("10.0.0.5:443", "198.51.100.9, 10.0.0.9"), proxy, "198.51.100.9"},
		{"multiple header lines", req("10.0.0.5:443", "6.6.6.6", "198.51.100.9"), proxy, "198.51.100.9"},
		{"trusted proxy without header", req("10.0.0.5:443"), proxy, "10.0.0.5"},
		{"garbage in XFF falls back to peer", req("10.0.0.5:443", "not-an-ip"), proxy, "10.0.0.5"},
		{"ipv6 grouped by /64", req("[2001:db8:1:2:aaaa:bbbb:cccc:dddd]:1234"), nil, "2001:db8:1:2::/64"},
		{"ipv4-mapped ipv6 unmapped", req("[::ffff:203.0.113.7]:80"), nil, "203.0.113.7"},
		{"remote without port", req("203.0.113.7"), nil, "203.0.113.7"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			if got := ClientKey(tt.r, tt.trusted); got != tt.want {
				t.Errorf("ClientKey = %q, want %q", got, tt.want)
			}
		})
	}
}
