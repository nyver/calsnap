package analysis

import (
	"fmt"
	"testing"
	"time"
)

func TestReplayCacheBoundedAndLRU(t *testing.T) {
	t.Parallel()

	now := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	c := newReplayCache(time.Minute, 3, func() time.Time { return now })
	for i := range 3 {
		c.put(fmt.Sprint("k", i), Response{RequestID: fmt.Sprint("r", i)})
	}
	if _, ok := c.get("k0"); !ok { // k0 becomes most recently used
		t.Fatal("k0 missing")
	}
	c.put("k3", Response{})
	if c.len() != 3 {
		t.Fatalf("len = %d, want 3", c.len())
	}
	if _, ok := c.get("k1"); ok {
		t.Error("k1 should have been evicted as least recently used")
	}
	for _, k := range []string{"k0", "k2", "k3"} {
		if _, ok := c.get(k); !ok {
			t.Errorf("%s missing", k)
		}
	}
}

func TestReplayCacheExpiry(t *testing.T) {
	t.Parallel()

	now := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	c := newReplayCache(time.Minute, 10, func() time.Time { return now })
	c.put("a", Response{})
	now = now.Add(59 * time.Second)
	if _, ok := c.get("a"); !ok {
		t.Fatal("entry expired too early")
	}
	now = now.Add(2 * time.Second)
	if _, ok := c.get("a"); ok {
		t.Fatal("entry should have expired")
	}
	if c.len() != 0 {
		t.Errorf("expired entry not removed, len = %d", c.len())
	}

	c.put("old", Response{})
	now = now.Add(2 * time.Minute)
	c.put("new", Response{})
	if c.len() != 1 {
		t.Errorf("put must drop expired entries, len = %d", c.len())
	}
}
