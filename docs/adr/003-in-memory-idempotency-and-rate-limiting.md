# 003. In-memory idempotency and rate limiting

## Context

The backend is stateless (no database) and unauthenticated, yet every analysis costs money. Mobile networks lose responses, so the client retries with the same request id; a retry must not call the AI again. Abuse must be bounded without accounts.

## Decision

All protection state is per process and in memory:

* **Replay cache**: bounded LRU with a 10-minute TTL that stores only successful response structs, never images. The key is the client request id **plus a hash of the image**, so knowing or guessing an id can never return someone else's result. Concurrent requests with the same key are merged with `singleflight`; if the owner of the shared call disconnects, waiters run their own attempt. Failures are not cached.
* **Rate limit**: token bucket per client key (remote address, or the first untrusted `X-Forwarded-For` entry only when the direct peer is a configured trusted proxy; IPv6 grouped by /64). The number of tracked clients is bounded; extra clients share one overflow bucket so that an attacker cycling addresses can neither grow memory nor reset the buckets of tracked clients. A janitor goroutine owned by `main` sweeps idle entries and stops with the process context.
* **Concurrency cap**: a global semaphore for in-flight AI analyses with a short bounded wait, then `503 AI_PROVIDER_UNAVAILABLE`.

## Consequences

* Simple and dependency-free; correct for a single instance.
* State is lost on restart and not shared between instances. Scaling out requires a shared store (for example Redis) or sticky routing; that is deliberately out of scope.
* Without authentication the limits are the primary cost control. Metrics expose rate-limited requests and token usage so that operators can alert. App attestation (Play Integrity) is the documented next step.
