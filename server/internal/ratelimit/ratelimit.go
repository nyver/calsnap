// Package ratelimit implements per-client token buckets with a bounded number
// of tracked clients.
package ratelimit

import (
	"context"
	"math"
	"net"
	"net/http"
	"net/netip"
	"strings"
	"sync"
	"time"

	"golang.org/x/time/rate"
)

// Config configures a Limiter.
type Config struct {
	PerMinute  float64       // sustained rate per client
	Burst      int           // bucket size per client
	MaxClients int           // upper bound on tracked clients
	IdleTTL    time.Duration // idle clients older than this are dropped by Sweep
	Now        func() time.Time
}

type client struct {
	lim      *rate.Limiter
	lastSeen time.Time
}

// Limiter hands out one token bucket per client key. When MaxClients is
// reached, further new clients share a single overflow bucket instead of
// growing the map, so an attacker cycling through addresses cannot exhaust
// memory or reset the buckets of tracked clients.
type Limiter struct {
	cfg      Config
	perSec   rate.Limit
	mu       sync.Mutex
	clients  map[string]*client
	overflow *rate.Limiter
}

// New creates a Limiter. Zero Now uses time.Now.
func New(cfg Config) *Limiter {
	if cfg.Now == nil {
		cfg.Now = time.Now
	}
	perSec := rate.Limit(cfg.PerMinute / 60)
	return &Limiter{
		cfg:      cfg,
		perSec:   perSec,
		clients:  make(map[string]*client),
		overflow: rate.NewLimiter(perSec, cfg.Burst),
	}
}

// Allow consumes a token for key. When the bucket is empty it returns false and
// the time after which a retry can succeed.
func (l *Limiter) Allow(key string) (bool, time.Duration) {
	now := l.cfg.Now()

	l.mu.Lock()
	defer l.mu.Unlock()

	lim := l.overflow
	if c, ok := l.clients[key]; ok {
		c.lastSeen = now
		lim = c.lim
	} else if len(l.clients) < l.cfg.MaxClients {
		c := &client{lim: rate.NewLimiter(l.perSec, l.cfg.Burst), lastSeen: now}
		l.clients[key] = c
		lim = c.lim
	}

	r := lim.ReserveN(now, 1)
	if !r.OK() {
		return false, time.Minute
	}
	if delay := r.DelayFrom(now); delay > 0 {
		r.CancelAt(now) // do not consume a token for a rejected request
		return false, delay
	}
	return true, 0
}

// Sweep drops clients idle for longer than IdleTTL.
func (l *Limiter) Sweep() {
	cutoff := l.cfg.Now().Add(-l.cfg.IdleTTL)
	l.mu.Lock()
	defer l.mu.Unlock()
	for k, c := range l.clients {
		if c.lastSeen.Before(cutoff) {
			delete(l.clients, k)
		}
	}
}

// Len returns the number of tracked clients.
func (l *Limiter) Len() int {
	l.mu.Lock()
	defer l.mu.Unlock()
	return len(l.clients)
}

// Run sweeps idle clients every interval until ctx is cancelled. The caller
// owns the goroutine and must wait for Run to return during shutdown.
func (l *Limiter) Run(ctx context.Context, interval time.Duration) {
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			l.Sweep()
		}
	}
}

// RetryAfterSeconds converts a delay to whole seconds for the Retry-After
// header (at least 1).
func RetryAfterSeconds(d time.Duration) int {
	return max(1, int(math.Ceil(d.Seconds())))
}

// ClientKey identifies the client of a request. It is the address of the direct
// peer, unless that peer is a trusted proxy: then it is the first address in
// X-Forwarded-For (scanning from the right) that is not itself a trusted proxy.
// Forwarded headers from untrusted peers are ignored, so they cannot be used to
// dodge the limit. IPv6 clients are grouped by /64.
func ClientKey(r *http.Request, trusted []netip.Prefix) string {
	peer, ok := parseHost(r.RemoteAddr)
	if !ok {
		return r.RemoteAddr
	}
	addr := peer
	if isTrusted(peer, trusted) {
		hops := strings.Split(strings.Join(r.Header.Values("X-Forwarded-For"), ","), ",")
		for i := len(hops) - 1; i >= 0; i-- {
			hop, err := netip.ParseAddr(strings.TrimSpace(hops[i]))
			if err != nil {
				break
			}
			hop = hop.Unmap()
			addr = hop
			if !isTrusted(hop, trusted) {
				break
			}
		}
	}
	if addr.Is6() {
		return netip.PrefixFrom(addr, 64).Masked().String()
	}
	return addr.String()
}

func parseHost(hostport string) (netip.Addr, bool) {
	host, _, err := net.SplitHostPort(hostport)
	if err != nil {
		host = hostport
	}
	addr, err := netip.ParseAddr(host)
	if err != nil {
		return netip.Addr{}, false
	}
	return addr.Unmap(), true
}

func isTrusted(addr netip.Addr, trusted []netip.Prefix) bool {
	for _, p := range trusted {
		if p.Contains(addr) {
			return true
		}
	}
	return false
}
