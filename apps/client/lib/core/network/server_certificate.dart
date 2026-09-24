import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// SHA-256 of a DER certificate as colon-separated upper-case hex
/// (`AB:CD:...`). The backend logs the same value at startup, so the user can
/// compare the two.
String certificateFingerprint(List<int> der) => sha256
    .convert(der)
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(':');

/// A self-signed (or otherwise untrusted) server certificate the user has
/// confirmed. It is accepted only for exactly this [host] and [port] and only
/// while the server presents a certificate with this [fingerprint].
class TrustedCertificate {
  const TrustedCertificate({
    required this.host,
    required this.port,
    required this.fingerprint,
  });

  /// Reads the stored form; null when it is missing or malformed, so that a
  /// damaged value means "not trusted" rather than a crash.
  static TrustedCertificate? tryParse(String? stored) {
    if (stored == null) return null;
    final match = _stored.firstMatch(stored);
    if (match == null) return null;
    final port = int.tryParse(match.group(2)!);
    if (port == null || port < 1 || port > 65535) return null;
    return TrustedCertificate(
      host: match.group(1)!.toLowerCase(),
      port: port,
      fingerprint: match.group(3)!.toUpperCase(),
    );
  }

  /// `host:port|FINGERPRINT`. Host names cannot contain `|`, and IPv6 hosts
  /// are stored without brackets, so the last `:` before `|` separates the port.
  static final RegExp _stored = RegExp(
    r'^(.+):(\d{1,5})\|((?:[0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2})$',
  );

  /// The certificate pin of the server at [baseUrl], for [fingerprint].
  factory TrustedCertificate.forUrl(String baseUrl, String fingerprint) {
    final uri = Uri.parse(baseUrl);
    return TrustedCertificate(
      host: uri.host.toLowerCase(),
      port: uri.port,
      fingerprint: fingerprint.toUpperCase(),
    );
  }

  final String host;
  final int port;
  final String fingerprint;

  String get stored => '$host:$port|$fingerprint';

  /// Whether this pin applies to the server at [baseUrl].
  bool isFor(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.toLowerCase() == host &&
        uri.port == port;
  }

  /// Signature of [HttpClient.badCertificateCallback].
  bool acceptsCertificate(
    X509Certificate cert,
    String certHost,
    int certPort,
  ) =>
      certHost.toLowerCase() == host &&
      certPort == port &&
      certificateFingerprint(cert.der) == fingerprint;

  @override
  bool operator ==(Object other) =>
      other is TrustedCertificate &&
      other.host == host &&
      other.port == port &&
      other.fingerprint == fingerprint;

  @override
  int get hashCode => Object.hash(host, port, fingerprint);
}

/// What the user needs to see to decide whether to trust a certificate.
class CertificateInfo {
  const CertificateInfo({
    required this.fingerprint,
    required this.subject,
    required this.validFrom,
    required this.validTo,
  });

  factory CertificateInfo.fromX509(X509Certificate cert) => CertificateInfo(
    fingerprint: certificateFingerprint(cert.der),
    subject: cert.subject,
    validFrom: cert.startValidity,
    validTo: cert.endValidity,
  );

  final String fingerprint;
  final String subject;
  final DateTime validFrom;
  final DateTime validTo;
}

/// Outcome of connecting to a server only to look at its certificate.
sealed class CertificateProbeResult {
  const CertificateProbeResult();
}

/// The certificate is accepted by the system (or the connection is not TLS).
class CertificateTrusted extends CertificateProbeResult {
  const CertificateTrusted();
}

/// The system does not trust the certificate; the user may confirm [info].
class CertificateUntrusted extends CertificateProbeResult {
  const CertificateUntrusted(this.info);

  final CertificateInfo info;
}

/// The server could not be reached, so nothing is known about its certificate.
class CertificateProbeFailed extends CertificateProbeResult {
  const CertificateProbeFailed();
}

/// Connects to `host:port` over TLS and reports what the server presents.
/// No application data is sent.
typedef CertificateProbe = Future<CertificateProbeResult> Function(
  String host,
  int port,
);

/// The default [CertificateProbe].
Future<CertificateProbeResult> probeServerCertificate(
  String host,
  int port,
) async {
  X509Certificate? rejected;
  try {
    final socket = await SecureSocket.connect(
      host,
      port,
      timeout: const Duration(seconds: 10),
      onBadCertificate: (cert) {
        rejected = cert;
        // Never accept here: only the user's confirmation may do that.
        return false;
      },
    );
    await socket.close();
    socket.destroy();
    return const CertificateTrusted();
  } on TlsException {
    final cert = rejected;
    return cert == null
        ? const CertificateProbeFailed()
        : CertificateUntrusted(CertificateInfo.fromX509(cert));
  } on IOException {
    return const CertificateProbeFailed();
  } on TimeoutException {
    return const CertificateProbeFailed();
  }
}

/// An [HttpClient] that, in addition to the system trust store, accepts the
/// pinned certificate. With no [pin] it behaves like a default client.
HttpClient createPinnedHttpClient(TrustedCertificate? pin) {
  final client = HttpClient();
  if (pin != null) {
    client.badCertificateCallback = pin.acceptsCertificate;
  }
  return client;
}
