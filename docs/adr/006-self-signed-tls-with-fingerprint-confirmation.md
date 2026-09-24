# 006. Self-signed TLS with fingerprint confirmation

## Context

Home and private-network deployments have no domain and no CA-issued certificate, yet release builds of the app talk HTTPS only ([ADR 004](004-tls-modes-and-debug-cleartext.md)). Operators need a way to run HTTPS without setting up Caddy or a certificate authority, and the app must be able to trust such a server without ever turning certificate verification off.

## Decision

**Server.** A self-signed certificate is generated in two situations:

* `cert_file` and `key_file` are configured and **both files are missing**: the pair is created at those paths. Files that exist are never overwritten: an operator's certificate is used as it is (even close to expiry, renewing it is the operator's job), a half-present pair or unreadable files are a startup error rather than a reason to generate. Only a certificate this package generated (recognized by its subject and by being self-issued) is renewed in place.
* `server.tls.self_signed: true` makes the server own a dedicated directory: it generates a certificate on first start and reuses it afterwards, and replaces an unusable pair. It cannot be combined with `cert_file`/`key_file`.

Generating at configured paths is convenient but means a mount mistake (the CA certificate is not mounted) silently yields a self-signed certificate instead of a failure. The server logs a warning with the fingerprint whenever it generates one, and clients refuse it until the user confirms the fingerprint, so the mistake is visible and not exploitable.

* In the `self_signed` mode key and certificate are stored in `server.tls.self_signed_dir` (default `certs`, files `selfsigned.crt` and `selfsigned.key`); key files are mode 0600 on Unix and written atomically in both cases. The location has to be persistent: in Docker it is a named volume, see `docker/compose.yaml`.
* ECDSA P-256, random 128-bit serial, `ExtKeyUsage` server auth, not a CA, valid for two years. The subject alternative names are `localhost`, the host name, the addresses of the local interfaces and `server.tls.self_signed_hosts`.
* An existing valid certificate is never regenerated (its fingerprint is pinned by clients). A generated one is replaced only when it is unreadable, does not match its key, is not yet valid or expires within 30 days. The new certificate has a new fingerprint, so clients ask the user again.
* At startup the server logs the certificate's SHA-256 fingerprint (public information) so the operator can compare it with what the app shows.
* TLS 1.2 is still the minimum version.

**Client.** The system trust store stays in charge. Only when the system rejects a certificate, the app may accept one specific certificate the user confirmed:

* When the user applies an `https://` server address in the settings, the app connects once, sends no data, and looks at the certificate. If the system trusts it (or the server is unreachable) the address is saved as before. If not, a dialog shows the SHA-256 fingerprint (rows of eight bytes), the subject and the expiry. Nothing is saved until the user taps Trust; cancelling or dismissing the dialog is a refusal.
* The confirmed certificate is stored as `host:port|FINGERPRINT` in `user_settings` (key `trusted_certificate`, no schema migration). It is accepted only for exactly that host and port and only while the server presents a certificate with exactly that fingerprint (`HttpClient.badCertificateCallback`). Host name matching is skipped for it, because trust rests on the fingerprint.
* If the server later presents another certificate (regenerated, or an attacker), requests fail with a dedicated message that leads to the server settings. Applying the address again shows the dialog with a stronger "certificate changed" warning.
* A damaged stored value is treated as "not trusted".

`InsecureSkipVerify` and its Dart equivalents are still not used anywhere: the server test client verifies the fingerprint itself, and the app callback returns true only on a full fingerprint match.

## Consequences

* A self-hosted server can serve HTTPS with one config line and no external tooling.
* The user has to compare the fingerprint out of band (server log, or the certificate file). If they do not, trust on first use applies and a man-in-the-middle on the first connection would be accepted. The dialog says to compare, and a later change is flagged.
* Only one confirmed certificate is kept: switching between two self-signed servers asks again.
* Fingerprints are computed the same way on both sides (SHA-256 of the DER certificate, upper-case hex with colons); a shared fixture in `protocol/fixtures/tls-selfsigned.*` checks that Go and Dart agree.
* Rotation is a normal event: regenerate (delete the two files or wait for expiry), restart, confirm the new fingerprint in the app.
