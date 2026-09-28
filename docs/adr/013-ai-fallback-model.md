# 013. Optional fallback AI model

## Context

A meal-analysis or label-reading request can fail against the configured model in ways a different model would not: the model is temporarily overloaded past the transient-retry budget, a specific model rejects the request (an unsupported model id, a content-policy block on that model, a quota tied to that model), or it keeps answering with something that fails validation. Operators asked for a way to keep serving these requests with a second model under the same account, without introducing a second AI vendor or provider abstraction.

## Decision

Each AI provider section (`ai.gemini`, `ai.openrouter`, `ai.routerai`) gains an optional `fallback_model` (default empty, disabled). When set, the composition root in `cmd/calsnap-server` builds a second `FoodVisionProvider` (and, when the provider also implements `label.Reader`, a second label reader) with the same `base_url` and API key, differing only in model. Validation rejects `fallback_model == model`.

The retry loop already living in `analysis.Service.callProvider` and its copy in `label.Service.Read` owns the switch: once the primary model's own retry budget is exhausted (`ErrInvalidResponse` after its one retry, `ErrUnavailable`/a call timeout after its two retries) or the primary model rejects the request outright (`ErrRejected`), the service switches to the fallback provider, if configured and not already used, resets its own retry counters, and gives the fallback the same full retry budget. A second failure, from either model, is never chased further: at most one switch happens per request. `analysis.Metrics.AIFallbackUsed()` counts every switch (`calsnap_ai_fallback_used_total`), and the switch is logged with the reason and the underlying error, at the same `request_id`-scoped logger used for the existing retry warnings.

The switch lives in the retry loop, not as a `FoodVisionProvider` wrapper, so the existing per-attempt logging, metrics and backoff apply unchanged to both models, and a request that never needs the fallback behaves exactly as before (`VisionFallback`/`ReaderFallback` nil is the default and preserves every existing retry test).

*Alternative considered:* a wrapper implementing `FoodVisionProvider` that internally calls primary-then-fallback. Rejected: the outer retry loop cannot tell how many real HTTP calls a single `Analyze` call already made, so its own retry/backoff accounting would either double up or lose visibility into which model actually failed.

## Consequences

- Opt-in and backward compatible: omitting `fallback_model` leaves every existing behavior, test and metric unchanged.
- The fallback shares the primary's API key and account; it does not add a second vendor, a second set of credentials, or cross-account routing.
- A request can now make up to twice the usual number of provider calls (the primary's full retry budget, then the fallback's), so `ai.overall_timeout` must comfortably cover that; the existing `server.write_timeout > ai.overall_timeout` check still enforces this, but operators enabling a fallback should re-check the budget.
- Nothing changes for the client: it never learns which model, primary or fallback, produced a result.
