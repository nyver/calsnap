# 005. OpenRouter and RouterAI through one OpenAI-compatible provider

## Context

Operators want to choose the vision model without code changes and without one vendor account per model. OpenRouter and RouterAI expose many models behind the OpenAI chat-completions protocol (`POST {base_url}/chat/completions`, bearer key, image input as a data URL).

## Decision

* One package, `internal/vision/openai`, implements `FoodVisionProvider` for both services. `ai.provider: openrouter` and `ai.provider: routerai` differ only in their config section (`model`, `api_key_env`, `base_url`) and defaults. No per-service code exists.
* The system and user prompts moved to `internal/vision/prompt` and are shared with Gemini, so prompt changes stay in one place. The prompt version is unchanged.
* The request asks for `response_format: json_schema` with `strict: false` (the contract has optional properties, which strict mode does not allow). Models that ignore structured output are handled by tolerating a Markdown fence and message content sent as a list of parts. Everything is still validated by `analysis.ParseResult`, so the provider output is never trusted.
* Error mapping follows the existing typed errors: HTTP 408, 429 and 5xx are `ErrUnavailable` (retried by the use case); other non-200 statuses (bad request, bad key, no credit, unknown model) are `ErrRejected`; unparsable output, `finish_reason` of `length` or `content_filter`, and an oversized body are `ErrInvalidResponse`. Routers may answer HTTP 200 with an `error` object; its numeric code is classified the same way.
* Security is unchanged from Gemini: the key is read only from the environment variable named by `api_key_env` and sent in the `Authorization` header (never in the URL); the response body is bounded to 2 MiB; upstream error bodies and URLs are never included in errors or logs. `base_url` must be an http(s) URL.
* The RouterAI default base URL and model id format are assumptions based on its OpenAI-compatible API and must be verified by the operator; both are configurable.

## Consequences

* Any vision-capable model offered by these routers works through configuration only.
* The photo now passes through the router and the upstream model vendor. The privacy note says so and tells operators to review both sets of terms.
* Output quality and JSON conformance vary by model; the validation layer and one re-attempt on invalid output remain the safety net. Operators should try a model with sample photos before switching production.
* Adding another OpenAI-compatible service needs only a new config section and a `case` in `build()`.
