package product

import (
	"container/list"
	"context"
	"errors"
	"sync"
	"time"
)

// notFoundTTL is how long an unknown product is remembered. It is short
// because people add missing products to the source all the time.
const notFoundTTL = 10 * time.Minute

// Config tunes the use case.
type Config struct {
	// CacheTTL is how long a found product is served from memory.
	CacheTTL time.Duration
	// CacheMaxEntries bounds the cache; the least recently used entry goes first.
	CacheMaxEntries int
}

// Service is the product lookup use case. It is safe for concurrent use.
type Service struct {
	cfg   Config
	src   Source
	cache *cache
}

// NewService creates the use case. now may be nil (time.Now).
func NewService(cfg Config, src Source, now func() time.Time) *Service {
	if now == nil {
		now = time.Now
	}
	return &Service{cfg: cfg, src: src, cache: newCache(cfg.CacheMaxEntries, now)}
}

// Lookup validates the barcode and returns the product. Errors are
// ErrInvalidBarcode, ErrNotFound, ErrUnavailable or the context error.
func (s *Service) Lookup(ctx context.Context, rawBarcode, locale string) (Product, error) {
	code, err := NormalizeBarcode(rawBarcode)
	if err != nil {
		return Product{}, err
	}
	if locale != LocaleRU {
		locale = LocaleEN
	}
	key := code + "|" + locale
	if e, ok := s.cache.get(key); ok {
		if e.notFound {
			return Product{}, ErrNotFound
		}
		return e.product, nil
	}

	p, err := s.src.Lookup(ctx, code, locale)
	switch {
	case err == nil:
		s.cache.put(key, entry{product: p}, s.cfg.CacheTTL)
		return p, nil
	case errors.Is(err, ErrNotFound):
		s.cache.put(key, entry{notFound: true}, notFoundTTL)
		return Product{}, ErrNotFound
	default:
		// Failures are never cached: the next scan should try again.
		return Product{}, err
	}
}

type entry struct {
	product  Product
	notFound bool
}

// cache is a bounded LRU with per-entry expiry.
type cache struct {
	mu   sync.Mutex
	max  int
	now  func() time.Time
	ll   *list.List // front = most recently used
	byID map[string]*list.Element
}

type cacheItem struct {
	key     string
	value   entry
	expires time.Time
}

func newCache(maxEntries int, now func() time.Time) *cache {
	return &cache{max: maxEntries, now: now, ll: list.New(), byID: make(map[string]*list.Element)}
}

func (c *cache) get(key string) (entry, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	el, ok := c.byID[key]
	if !ok {
		return entry{}, false
	}
	it := el.Value.(*cacheItem)
	if !c.now().Before(it.expires) {
		c.remove(el)
		return entry{}, false
	}
	c.ll.MoveToFront(el)
	return it.value, true
}

func (c *cache) put(key string, value entry, ttl time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if el, ok := c.byID[key]; ok {
		c.remove(el)
	}
	c.byID[key] = c.ll.PushFront(&cacheItem{key: key, value: value, expires: c.now().Add(ttl)})
	for c.ll.Len() > c.max {
		c.remove(c.ll.Back())
	}
}

func (c *cache) remove(el *list.Element) {
	delete(c.byID, el.Value.(*cacheItem).key)
	c.ll.Remove(el)
}
