# 004. TLS modes and debug-only cleartext

## Context

Photos travel from the phone to the backend, so production traffic must be HTTPS with TLS 1.2 or newer. Operators often terminate TLS in a reverse proxy, and developers need to reach a local backend from an emulator, where a certificate is impractical.

## Decision

**Backend.** With `server.tls.cert_file` and `key_file` the server serves HTTPS with `MinVersion: TLS 1.2`. Without them it refuses to start unless `server.allow_plain_http: true`, which is meant for a proxy-terminated deployment or local development and logs a warning. The `fake` AI provider is refused when `server.environment: production`. Server timeouts (read header, read, write, idle) are always configured.

**Android release.** The base URL is chosen by the user in the settings and stored on the device; `--dart-define=API_BASE_URL` only provides an optional default. In release mode the settings dialog and the URL resolution accept `https://` addresses only (credentials, query and fragment are refused too), and without a usable address the app asks for one instead of sending a photo. Cleartext traffic is disabled in the main manifest (`usesCleartextTraffic="false"`), there is no network security config, and cloud backup is off.

**Android debug.** `android/app/src/debug/` adds a network security config that permits cleartext only for `10.0.2.2` and `localhost`, so the debug build can talk to a local backend running the `fake` provider. The files live in the debug source set only; the release build verification checks that the merged release manifest has no cleartext permission and the release APK has no network security config.

TLS certificate verification is never disabled anywhere in the code.

## Consequences

* Development stays convenient without weakening release builds.
* A misconfigured production deployment (no TLS, no proxy flag) fails at startup instead of silently serving plain HTTP.
* Certificate pinning is not used: it is not justified by the threat model and would need a rotation plan; it can be added later.
