# CalSnap

CalSnap is an Android app for logging food with a photo: take a picture, get a draft list of foods with estimated weights, correct it, save it, and see calories and macros. The diary is stored on the device. A small stateless Go backend forwards the photo to an AI vision provider, so the AI API key never ships in the APK.

> Calories computed from a photo are **estimates**. Portion size from a single photo is the least accurate part of the system, so every value is editable in one tap.

## Repository layout

```text
apps/client/        Flutter app (Android only)
  lib/app/          entry widget, router, theme
  lib/core/         database (Drift), network (Dio), files, config, logging, DI
  lib/features/     onboarding, diary, meal, camera, recognition, foods, statistics, settings, export
                    (each: domain/ data/ ui/)
  assets/catalog/   copy of the nutrition catalog
  drift_schemas/    exported database schema snapshots (one per released version)
  integration_test/ acceptance flow for a device or emulator
server/             Go module (stateless API)
  cmd/calsnap-server/   main: flags, wiring, graceful shutdown
  internal/             config, transport/httpapi, app/analysis, vision (gemini, fake),
                        nutrition (catalog + matching), ratelimit, metrics
protocol/           contracts shared by both sides: OpenAPI, AI result JSON Schema,
                    nutrition catalog, cross-language fixtures
docs/               architecture overview, privacy note, ADRs
docker/             Dockerfile, compose with a Caddy TLS proxy
scripts/            sync-catalog.sh
config.example.yaml every server option with its default
```

Go commands run from `server/`, Flutter commands from `apps/client/`.

## Requirements

Verified with:

| Tool | Version |
|---|---|
| Go | 1.26 |
| gofumpt / golangci-lint | 0.11 / 2.13 |
| Flutter / Dart | 3.47 / 3.13 |
| Android SDK | platform 37, build-tools 36, JDK 17+ (Gradle uses the JDK of Android Studio) |
| Docker (optional) | to build the backend image |

`compileSdk` is 37 because `permission_handler_android` requires it; `minSdk` is 24 and `targetSdk` follows the Flutter toolchain.

## Backend

### Configure

```bash
cp config.example.yaml config.yaml      # config.yaml is ignored by Git
export GEMINI_API_KEY=...               # the key is read only from the environment
```

Every key is documented in [config.example.yaml](config.example.yaml). The important ones:

* `ai.provider` – `gemini` or `fake`. `fake` returns canned results without network access and is refused when `server.environment: production`.
* `ai.gemini.model` – the model is chosen here; the app never learns it, so it can change without an app release.
* `server.tls.*` – native HTTPS (TLS 1.2 minimum). Without TLS files the server only starts when `server.allow_plain_http: true` (behind a TLS-terminating reverse proxy, or locally) and logs a warning.
* `server.trusted_proxies` – proxies whose `X-Forwarded-For` is trusted for per-client rate limiting.
* `limits.*` – upload size (default 4 MiB), image dimensions, rate limit (10/min, burst 3), concurrent AI calls (16), replay window (10 min).
* `client.*` – values the app fetches from `GET /v1/config` (image long side, JPEG quality, timeout).

### Run

```bash
cd server
go run ./cmd/calsnap-server -config ../config.yaml
# local development without an AI key:
#   ai.provider: fake  +  server.allow_plain_http: true
```

`-version` prints the build version (set with `-ldflags "-X main.version=1.0.0"`).

### TLS modes

| Mode | Configuration |
|---|---|
| Native TLS | `server.tls.cert_file` + `key_file` |
| Behind a proxy (Caddy, nginx) | `server.allow_plain_http: true`, `server.trusted_proxies: [proxy CIDR]` |
| Local development | `allow_plain_http: true`; the debug Android build may reach `10.0.2.2` / `localhost` over cleartext |

Release builds of the app refuse `http://` backends. See [ADR 004](docs/adr/004-tls-modes-and-debug-cleartext.md).

### Docker

```bash
docker build -f docker/Dockerfile -t calsnap-server --build-arg VERSION=1.0.0 .
# with automatic HTTPS through Caddy: see the header of docker/compose.yaml
docker compose -f docker/compose.yaml up -d --build
```

The image is a static, non-root, distroless binary. The key is passed through the environment, never written to the image.

### Observability, cost and abuse

* `GET /healthz` – liveness.
* Prometheus metrics on `metrics.listen` (default `127.0.0.1:9090`, keep it private): request counts and latency by route and status class, AI latency, AI errors by kind, invalid AI responses, nutrition match kinds and failures, rate-limited requests and AI token usage (`calsnap_ai_tokens_total`, a cost proxy).
* Alert on `calsnap_ai_tokens_total` growth, `calsnap_rate_limited_total`, and 5xx ratios. The endpoint is unauthenticated; abuse is bounded by the per-client rate limit, the global concurrency cap, the upload limits and request-id replay protection. App attestation is a documented follow-up.
* Logs are structured (`slog`) and contain request id, route, status, sizes, durations and error codes only: never photos, prompts, AI output, food names or keys.

The rate limiter and the replay cache are per process, so run a single instance ([ADR 003](docs/adr/003-in-memory-idempotency-and-rate-limiting.md)).

## Android app

### Build

The backend URL is a build-time constant:

```bash
cd apps/client
flutter pub get
dart run build_runner build          # only after changing Drift tables (generated files are committed)

# debug (emulator; the debug build may use http://10.0.2.2:8080 with the fake provider)
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8080

# release: an https:// URL is mandatory, the app refuses to start otherwise
flutter build apk --release --split-per-abi \
  --dart-define=API_BASE_URL=https://calsnap.example.com \
  --dart-define=PRIVACY_POLICY_URL=https://calsnap.example.com/privacy \
  --dart-define=APP_VERSION=1.0.0
```

Signing: create `apps/client/android/key.properties` (never committed) with `storeFile`, `storePassword`, `keyAlias`, `keyPassword`. Without it the release build is signed with the debug key and must not be published. R8 is enabled for release builds; project rules live in `android/app/proguard-rules.pro`.

The release manifest requests only `INTERNET` and `CAMERA`, disables cleartext traffic and cloud auto-backup (the diary must stay on the device; use the export in settings as the backup path). The application id `app.calsnap.android` is a placeholder to confirm before the first store upload.

### Data and privacy

Meals, items, foods, settings and AI correction records live in SQLite on the device (Drift, schema version 1, WAL, foreign keys on). Photos are files under `meals/YYYY/MM/DD/`, never BLOBs. See [docs/security/privacy.md](docs/security/privacy.md).

### Export format

Settings offers CSV (RFC 4180, one row per item, spreadsheet-formula guard) and JSON (`format: calsnap-export`, `formatVersion: 1`). Photos are not embedded.

## Tests

```bash
# backend (from server/)
gofumpt -l .
go vet ./...
golangci-lint run
go build ./...
GOOS=windows GOARCH=amd64 go build ./...
go test ./... -count=1
go test ./... -race -count=1        # needs cgo/a C toolchain (Linux/macOS or MinGW)

# client (from apps/client/)
dart format --set-exit-if-changed .
flutter analyze
flutter test
flutter test integration_test/photo_flow_test.dart -d <device-id>   # emulator or device
```

Golden files live in `apps/client/test/goldens/goldens`; refresh them with `flutter test --update-goldens` after intentional layout changes.

The protocol fixtures in `protocol/fixtures` are consumed by both test suites, so a contract change breaks whichever side falls behind.

### Nutrition catalog

`protocol/nutrition/catalog.json` is the canonical catalog (about 200 common foods, English and Russian names, per-100 g values from typical USDA FoodData Central values). `go:embed` and Flutter assets cannot read files outside their package, so both sides keep a byte-identical copy:

```bash
scripts/sync-catalog.sh          # copy the canonical file to server/ and apps/client/
scripts/sync-catalog.sh --check  # verify (both test suites also fail on drift)
```

## Troubleshooting

* **Release app closes immediately** – the release build needs `--dart-define=API_BASE_URL=https://...`.
* **"Analysis service temporarily unavailable"** – check the backend logs by request id; the app shows the same id in nothing user-visible, but the `X-Request-Id` header is echoed by the API.
* **Backend exits at startup** – the error names the invalid key (for example the environment variable that should hold the API key, never its value).
* **Kotlin/Gradle errors like "Storage already registered" on Windows** – the project and the pub cache are on different drives; `kotlin.incremental=false` in `android/gradle.properties` works around it.
* **`Access is denied` running `go test` on Windows for a package called `analyze`** – the host blocks executables with that name, which is why the use case package is called `analysis`.
* **A diary written by a newer app version** – the app shows an update screen and does not touch the data.

## Known limitations

* The unauthenticated backend relies on rate limits; there is no app attestation yet.
* The in-progress recognition result is not persisted across process death; retake the photo.
* Personal correction coefficients are recorded but not applied.
* The Go module path is a placeholder (`example.com/calsnap/server`).
