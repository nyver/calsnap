package plateadvice

import (
	"testing"
	"time"
)

func TestReplayCacheTTLExpiry(t *testing.T) {
	t.Parallel()

	now := time.Unix(0, 0)
	c := newReplayCache(time.Minute, 10, func() time.Time { return now })
	c.put("k", Advice{Summary: "s"})
	if _, ok := c.get("k"); !ok {
		t.Fatal("expected a hit before expiry")
	}
	now = now.Add(2 * time.Minute)
	if _, ok := c.get("k"); ok {
		t.Fatal("expected a miss after expiry")
	}
	if c.len() != 0 {
		t.Errorf("len = %d, want 0 after the expired entry is evicted", c.len())
	}
}

func TestReplayCacheSizeBound(t *testing.T) {
	t.Parallel()

	now := time.Unix(0, 0)
	c := newReplayCache(time.Minute, 2, func() time.Time { return now })
	c.put("a", Advice{Summary: "a"})
	c.put("b", Advice{Summary: "b"})
	c.put("c", Advice{Summary: "c"})
	if c.len() != 2 {
		t.Fatalf("len = %d, want 2", c.len())
	}
	if _, ok := c.get("a"); ok {
		t.Error("the oldest entry should have been evicted")
	}
	if _, ok := c.get("c"); !ok {
		t.Error("the newest entry should still be present")
	}
}

func TestReplayCacheGetClonesSoCallersCannotMutateTheCache(t *testing.T) {
	t.Parallel()

	c := newReplayCache(time.Minute, 10, time.Now)
	c.put("k", Advice{Summary: "s", Suggestions: []Suggestion{{Examples: []string{"a"}}}})
	got, ok := c.get("k")
	if !ok {
		t.Fatal("expected a hit")
	}
	got.Suggestions[0].Examples[0] = "mutated"
	again, _ := c.get("k")
	if again.Suggestions[0].Examples[0] != "a" {
		t.Errorf("cache entry was mutated through the returned value: %q", again.Suggestions[0].Examples[0])
	}
}
