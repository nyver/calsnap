package analysis

import (
	"container/list"
	"slices"
	"sync"
	"time"
)

// replayCache is a bounded LRU cache with a TTL that holds only successful
// responses (never images) so that a client retry after a lost response does
// not trigger a second AI call.
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
	resp    Response
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

func (c *replayCache) get(key string) (Response, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()

	el, ok := c.byID[key]
	if !ok {
		return Response{}, false
	}
	e := el.Value.(*replayEntry)
	if !c.now().Before(e.expires) {
		c.remove(el)
		return Response{}, false
	}
	c.ll.MoveToFront(el)
	return cloneResponse(e.resp), true
}

func (c *replayCache) put(key string, resp Response) {
	c.mu.Lock()
	defer c.mu.Unlock()

	now := c.now()
	if el, ok := c.byID[key]; ok {
		c.remove(el)
	}
	c.byID[key] = c.ll.PushFront(&replayEntry{key: key, resp: cloneResponse(resp), expires: now.Add(c.ttl)})

	// Drop expired entries from the cold end, then enforce the size bound.
	for el := c.ll.Back(); el != nil; el = c.ll.Back() {
		if e := el.Value.(*replayEntry); now.Before(e.expires) {
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
	delete(c.byID, el.Value.(*replayEntry).key)
	c.ll.Remove(el)
}

func cloneResponse(r Response) Response {
	r.Items = slices.Clone(r.Items)
	r.Warnings = slices.Clone(r.Warnings)
	return r
}
