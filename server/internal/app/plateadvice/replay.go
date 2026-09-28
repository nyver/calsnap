package plateadvice

import (
	"container/list"
	"slices"
	"sync"
	"time"
)

// replayCache is a bounded LRU cache with a TTL that holds only successful
// advice (never the request), so a client retry after a lost response does
// not trigger a second AI call. It mirrors internal/app/analysis's
// replayCache; see design.md Decision 6 for why it is not shared directly.
type replayCache struct {
	mu   sync.Mutex
	ttl  time.Duration
	max  int
	now  func() time.Time
	ll   *list.List // front = most recently used
	byID map[string]*list.Element
}

type replayEntry struct {
	key     string
	advice  Advice
	expires time.Time
}

func newReplayCache(ttl time.Duration, maxEntries int, now func() time.Time) *replayCache {
	return &replayCache{
		ttl:  ttl,
		max:  maxEntries,
		now:  now,
		ll:   list.New(),
		byID: make(map[string]*list.Element),
	}
}

func (c *replayCache) get(key string) (Advice, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()

	el, ok := c.byID[key]
	if !ok {
		return Advice{}, false
	}
	e := el.Value.(*replayEntry) //nolint:errcheck // the map only ever holds *replayEntry
	if !c.now().Before(e.expires) {
		c.remove(el)
		return Advice{}, false
	}
	c.ll.MoveToFront(el)
	return cloneAdvice(e.advice), true
}

func (c *replayCache) put(key string, advice Advice) {
	c.mu.Lock()
	defer c.mu.Unlock()

	now := c.now()
	if el, ok := c.byID[key]; ok {
		c.remove(el)
	}
	c.byID[key] = c.ll.PushFront(&replayEntry{key: key, advice: cloneAdvice(advice), expires: now.Add(c.ttl)})

	// Drop expired entries from the cold end, then enforce the size bound.
	for el := c.ll.Back(); el != nil; el = c.ll.Back() {
		e := el.Value.(*replayEntry) //nolint:errcheck // the map only ever holds *replayEntry
		if now.Before(e.expires) {
			break
		}
		c.remove(el)
	}
	for c.ll.Len() > c.max {
		c.remove(c.ll.Back())
	}
}

func (c *replayCache) len() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.ll.Len()
}

func (c *replayCache) remove(el *list.Element) {
	delete(c.byID, el.Value.(*replayEntry).key) //nolint:errcheck // the map only ever holds *replayEntry
	c.ll.Remove(el)
}

func cloneAdvice(a Advice) Advice {
	a.Suggestions = slices.Clone(a.Suggestions)
	for i := range a.Suggestions {
		a.Suggestions[i].Examples = slices.Clone(a.Suggestions[i].Examples)
	}
	return a
}
