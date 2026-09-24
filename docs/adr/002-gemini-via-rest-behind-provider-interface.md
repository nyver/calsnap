# 002. Gemini through its REST API behind a provider interface

## Context

The backend needs structured food recognition from a multimodal model, and the model or vendor must be replaceable without an app release. The client must never learn the model name.

## Decision

The analysis use case defines a consumer-side interface `FoodVisionProvider.Analyze(ctx, image, context) (Result, error)` with typed errors: `ErrUnavailable` (transient, retried), `ErrInvalidResponse` (re-attempted once) and `ErrRejected` (not retried). The retry loop lives in the use case, so every provider shares it.

The MVP implements Gemini by calling `generateContent` directly with `net/http`: inline base64 image, `responseMimeType: application/json`, and a `responseSchema` that is kept in sync with `protocol/ai/food-vision-result.schema.json` by a test. The API key travels in the `x-goog-api-key` header (URLs get logged), the response body is bounded to 2 MiB, error bodies are never included in errors or logs, and token usage is exported as a metric. The prompt is versioned in code and treats text inside the photo as data.

We did not adopt the official SDK: it adds a large transitive dependency tree and gives less control over body limits and retries. This can be revisited.

A deterministic `fake` provider (canned results selected by image hash) serves development and client tests. Configuration refuses it in production.

The provider result is never trusted: strict JSON decoding, at most 20 items, name length, weight in (0, 3000] g, confidence in [0, 1], kcal in [0, 900], each macro in [0, 100], macros summing to at most 105.

## Consequences

* Model changes are a configuration change and a restart.
* A second provider is one new package implementing the interface (see [ADR 005](005-openai-compatible-providers.md), which added OpenRouter and RouterAI).
* The Gemini request id cannot be forwarded as metadata because the Developer API has no such field.
* `nutritionPer100g` is optional in the AI schema: when it is absent for a food without a catalog match the analysis fails with `NUTRITION_MATCH_FAILED` instead of guessing.
