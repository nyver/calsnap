import '../../../core/network/server_certificate.dart';

/// What has to happen before a newly entered backend address is saved.
sealed class AddressCheck {
  const AddressCheck();
}

/// Nothing to confirm: the address is plain (debug), its certificate is
/// trusted by the system or already confirmed, or the server is unreachable
/// (the address is still saved so that it can be configured offline).
class AddressReady extends AddressCheck {
  const AddressReady();
}

/// The server presents a certificate the system does not trust. The user has to
/// confirm [info] first. [changed] is true when a different certificate was
/// confirmed for this same server before.
class AddressNeedsTrust extends AddressCheck {
  const AddressNeedsTrust(this.info, {required this.changed});

  final CertificateInfo info;
  final bool changed;
}

/// Looks at the certificate of [url] (a normalized `https://` address) and
/// decides whether the user must confirm it. [pinned] is the certificate
/// confirmed earlier, if any.
Future<AddressCheck> checkServerAddress(
  String url, {
  required TrustedCertificate? pinned,
  required CertificateProbe probe,
}) async {
  final uri = Uri.parse(url);
  if (uri.scheme != 'https') return const AddressReady();
  final result = await probe(uri.host, uri.port);
  if (result is! CertificateUntrusted) return const AddressReady();
  final samePinned = pinned != null && pinned.isFor(url);
  if (samePinned && pinned.fingerprint == result.info.fingerprint) {
    return const AddressReady();
  }
  return AddressNeedsTrust(result.info, changed: samePinned);
}
