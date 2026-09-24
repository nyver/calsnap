# Architecture overview

```text
Flutter Android app (local-first)                  Go backend (stateless)               AI provider
+--------------------------------------+           +------------------------------+     +-----------+
| ui -> domain <- data                 |  HTTPS    | httpapi (limits, validation) |     |           |
| Riverpod, GoRouter                   | --------> | -> analysis use case         | --> | Gemini    |
| Drift/SQLite, photo files            |           |    vision provider iface     |     | (or fake) |
| local calculation of all totals      |           |    nutrition provider iface  |     |           |
+--------------------------------------+           +------------------------------+     +-----------+
```

Principles: the diary lives on the device; the backend keeps no state beyond bounded in-memory caches; the AI key exists only on the backend; the AI proposes and the user confirms; all calories and macros shown to the user are computed locally from weight and per-100 g values.

## Backend (`server/`)

* `internal/transport/httpapi` – routing (`net/http` patterns), middleware (request id, panic recovery, structured access log, metrics), the multipart upload reader (streaming, in-memory, size/format/dimension checks) and the unified error format.
* `internal/app/analysis` – the use case. It defines the consumer-side interfaces `FoodVisionProvider`, `NutritionProvider` and `Metrics`. Flow: validate the provider result, retry policy (transient errors up to 2 times with exponential backoff and jitter, one re-attempt on invalid output, overall deadline, cancellation), confidence filtering, nutrition matching, warnings, ordering by weight. It also owns the global concurrency cap and the replay cache (singleflight by client request id plus image hash).
* `internal/vision/gemini` – Gemini REST provider (structured output through `responseSchema`, key in a header, bounded response body). `internal/vision/openai` – OpenAI-compatible chat-completions provider used for OpenRouter and RouterAI (data-URL image, `json_schema` response format, bearer key, bounded response body). `internal/vision/prompt` – the versioned prompt shared by all real providers. `internal/vision/fake` – deterministic canned results.
* `internal/nutrition` – the embedded catalog, name normalization, and the matching pipeline: exact id, alias, then fuzzy (token containment and Levenshtein similarity, with numbers in names required to agree and a length prefilter), falling back to the AI estimate. `NUTRITION_ESTIMATED` marks fallbacks.
* `internal/ratelimit`, `internal/metrics`, `internal/config` – token buckets with bounded memory, Prometheus collectors, YAML configuration with fail-fast validation.

The API contract is `protocol/api/openapi.yaml`; the AI output contract is `protocol/ai/food-vision-result.schema.json`. Tests compare handler output with `protocol/fixtures`.

## Client (`apps/client/`)

* `core/database` – Drift tables mirror the specification (TEXT UUIDv7 keys, epoch-millisecond UTC timestamps), foreign keys and WAL on every open, an explicit schema version, a guard against databases from newer versions, and a schema snapshot in `drift_schemas/` used by a migration test.
* `features/meal` – the domain model (`Meal`, `MealItem`, `MealDraft`), the pure `NutritionCalculator`, unit conversion, `SaveMealUseCase` and the transactional `MealRepository` (meal, items, totals, corrections, food cache in one transaction).
* `features/recognition` – `AnalysisApi` (Dio, retry interceptor for connection errors and 502/503/504 with the same request id), remote config cache, and the analysis controller (prepare, upload, cancel, map failures to localized messages).
* `features/camera` – capture screen (`camera`, `image_picker`, `permission_handler`) and image preparation in an isolate (decode, bake orientation, downscale, re-encode as JPEG without metadata).
* `features/diary`, `foods`, `statistics`, `export`, `settings`, `onboarding` – screens and their data access.
* One draft editor serves the recognition result, manual entry and editing of saved meals.

Dependency direction inside a feature: `ui -> domain <- data`.

## Data flow of the main path

1. Capture or pick a photo, then preview.
2. The photo is prepared in an isolate and uploaded with a fresh `X-Request-Id`. Optionally the user then adds a side photo ([ADR 008](../adr/008-optional-side-photo.md)); both photos go in one request and the result replaces the draft items.
3. The backend validates the upload, calls the AI provider, validates and filters the result, resolves nutrition and answers with items and warnings.
4. The client builds an in-memory `MealDraft`, proposing weights adjusted to the user's past corrections ([ADR 007](../adr/007-personal-portion-calibration.md)); the user edits it; totals are recomputed locally on every change.
5. Save writes the meal in one transaction, records AI corrections for weights that differ from what the app proposed, caches recognized foods, and stores the photo as a file (if enabled).

## Versioned formats

| Format | Version | Notes |
|---|---|---|
| HTTP API | `v1` | `protocol/api/openapi.yaml` |
| Client SQLite schema | 1 | Drift migrations, snapshots in `apps/client/drift_schemas/` |
| Nutrition catalog | `formatVersion` 1 | `catalogVersion` triggers re-seeding of catalog rows only |
| JSON export | `formatVersion` 1 | `format: calsnap-export` |
