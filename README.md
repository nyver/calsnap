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
  internal/             config, transport/httpapi, app/analysis, vision (gemini, openai, fake),
                        nutrition (catalog + matching), ratelimit, metrics
protocol/           contracts shared by both sides: OpenAPI, AI result JSON Schema,
                    nutrition catalog, cross-language fixtures
docs/               architecture overview, privacy note, ADRs
docker/             Dockerfile, compose (optional Caddy TLS proxy, commented out by default)
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
                                        # (OPENROUTER_API_KEY / ROUTERAI_API_KEY for those providers)
```

Every key is documented in [config.example.yaml](config.example.yaml). The important ones:

* `ai.provider` – `gemini`, `openrouter`, `routerai` or `fake`. `fake` returns canned results without network access and is refused when `server.environment: production`. Only the section of the selected provider is validated and its key read.
* `ai.gemini.model`, `ai.openrouter.model`, `ai.routerai.model` – the model is chosen here; the app never learns it, so it can change without an app release. Each provider section also has `api_key_env` (the name of the environment variable holding the key) and `base_url`.
* OpenRouter and RouterAI use the OpenAI-compatible chat-completions API, so any vision-capable model they offer works, for example `google/gemini-2.5-flash`. Note that the router forwards the photo to the upstream model vendor (see the [privacy note](docs/security/privacy.md)). The RouterAI defaults (`https://routerai.ru/api/v1`, model id format) are assumptions: check them against your account and override `base_url` and `model` if needed.
* `server.tls.*` – native HTTPS (TLS 1.2 minimum): either `cert_file` + `key_file` (created as a self-signed pair when both files are missing), or `self_signed: true` for a certificate the server generates itself (see [TLS modes](#tls-modes)). Without any of them the server only starts when `server.allow_plain_http: true` (behind a TLS-terminating reverse proxy, or locally) and logs a warning.
* `server.trusted_proxies` – proxies whose `X-Forwarded-For` is trusted for per-client rate limiting.
* `limits.*` – upload size (default 4 MiB), image dimensions, rate limit (10/min, burst 3), concurrent AI calls (16), replay window (10 min).
* `client.*` – values the app fetches from `GET /v1/config` (image long side, JPEG quality, timeout).

### Run

```bash
cd server
go run ./cmd/calsnap-server -config ../config.yaml
# switch provider, e.g. OpenRouter (config.yaml: ai.provider: openrouter):
#   OPENROUTER_API_KEY=... go run ./cmd/calsnap-server -config ../config.yaml
# local development without an AI key:
#   ai.provider: fake  +  server.allow_plain_http: true
```

`-version` prints the build version (set with `-ldflags "-X main.version=1.0.0"`).

### TLS modes

| Mode | Configuration |
|---|---|
| Native TLS | `server.tls.cert_file` + `key_file`; if both files are missing the server generates a self-signed pair there |
| Self-signed (no domain, private network) | `server.tls.self_signed: true`, optionally `self_signed_dir` and `self_signed_hosts` |
| Behind a proxy (Caddy, nginx) | `server.allow_plain_http: true`, `server.trusted_proxies: [proxy CIDR]` |
| Local development | `allow_plain_http: true`; the debug Android build may reach `10.0.2.2` / `localhost` over cleartext |

Release builds of the app refuse `http://` backends. See [ADR 004](docs/adr/004-tls-modes-and-debug-cleartext.md).

#### Self-signed certificate

There are two ways to get one. If `server.tls.cert_file` and `key_file` are set but **both files are missing**, the server generates a self-signed pair at those paths on startup (their directories are created); existing files are used untouched and never overwritten, and a pair with only one file is a startup error. With `server.tls.self_signed: true` the server creates an ECDSA P-256 certificate on the first start, stores it in `server.tls.self_signed_dir` (default `certs/`, keep it persistent) and reuses it on every restart. It is valid for two years and replaced automatically 30 days before it expires (or when the files are damaged); deleting the two files forces a new one. Put the address clients use into `server.tls.self_signed_hosts` (the local interface addresses and the host name are added automatically, but inside Docker these are the container's, not the host's).

The startup log prints the SHA-256 fingerprint:

```text
serving a self-signed certificate: confirm this SHA-256 fingerprint in the app when connecting fingerprint=AB:CD:...
```

In the app, enter `https://<address>:8445` under Settings → Server. Because the system does not trust the certificate, the app shows its fingerprint, subject and expiry. Compare the fingerprint with the log (or `openssl x509 -in certs/selfsigned.crt -noout -fingerprint -sha256`) and tap **Trust** only if they are identical. The app then accepts exactly that certificate for that host and port; certificate verification is never disabled. If the server later presents a different certificate, requests fail with a message that leads back to the server settings, where a "certificate changed" warning asks for confirmation again. Details and limits (trust on first use, one confirmed certificate at a time) are in [ADR 006](docs/adr/006-self-signed-tls-with-fingerprint-confirmation.md).

### Docker

```bash
docker build -f docker/Dockerfile -t calsnap-server --build-arg VERSION=1.0.0 .
# optional automatic HTTPS through Caddy: see the header of docker/compose.yaml
docker compose -f docker/compose.yaml up -d --build
```

The image is a static, non-root, distroless binary. The key is passed through the environment, never written to the image. For a self-signed certificate set `server.tls.self_signed: true` and `server.tls.self_signed_dir: /var/lib/calsnap/tls` in `config.yaml`; compose mounts the `calsnap_tls` volume there so that the certificate survives restarts and rebuilds.

### Observability, cost and abuse

* `GET /healthz` – liveness.
* Prometheus metrics on `metrics.listen` (default `127.0.0.1:9090`, keep it private): request counts and latency by route and status class, AI latency, AI errors by kind, invalid AI responses, nutrition match kinds and failures, rate-limited requests and AI token usage (`calsnap_ai_tokens_total`, a cost proxy).
* Alert on `calsnap_ai_tokens_total` growth, `calsnap_rate_limited_total`, and 5xx ratios. The endpoint is unauthenticated; abuse is bounded by the per-client rate limit, the global concurrency cap, the upload limits and request-id replay protection. App attestation is a documented follow-up.
* Logs are structured (`slog`) and contain request id, route, status, sizes, durations and error codes only: never photos, prompts, AI output, food names or keys.

The rate limiter and the replay cache are per process, so run a single instance ([ADR 003](docs/adr/003-in-memory-idempotency-and-rate-limiting.md)).

## Build script (Windows)

`scripts/build.bat [debug|release] [all|server|android]` builds everything into `dist\` (ignored by Git): the server for Windows and Linux (`amd64`, no CGO) and the Android APKs (`release` is split per ABI). Configure it with environment variables:

```bat
set API_BASE_URL=https://calsnap.example.com   rem optional default address, https:// for release
set PRIVACY_POLICY_URL=https://calsnap.example.com/privacy
set VERSION=1.0.0                              rem default 0.0.0-dev
scripts/build.bat release
scripts/build.bat debug android               rem emulator build (the app defaults to http://10.0.2.2:8445)
```

It needs Go and Flutter (with the Android toolchain) on `PATH`. Without `apps/client/android/key.properties` the release APKs are signed with the debug key and the script warns about it. The script only builds; run the tests separately.

## Android app

### Build

The backend address is set **in the app** (Settings -> Server address) and stored on the device. `--dart-define=API_BASE_URL` only provides an optional default that applies until the user sets one; debug builds default to `http://10.0.2.2:8445` (the emulator host). Release builds accept `https://` addresses only. Without any address the app asks for one when a photo is analyzed; the diary works offline regardless.

```bash
cd apps/client
flutter pub get
dart run build_runner build          # only after changing Drift tables (generated files are committed)

# debug (emulator; the debug build may use http://10.0.2.2:8445 with the fake provider)
flutter build apk --debug

# release (add --dart-define=API_BASE_URL=https://... to preset the server address)
flutter build apk --release --split-per-abi \
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

* **"The server address is not set" when analyzing a photo** – open Settings -> Server address and enter your `https://` address (release builds reject `http://`).
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
