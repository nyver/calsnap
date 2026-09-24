import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/network/server_certificate.dart';
import '../../../shared/l10n_x.dart';

/// Asks whether to trust the certificate a server presented. Pops true only when
/// the user explicitly confirms; everything else (cancel, back, tap outside) is
/// a refusal. [changed] is set when another certificate was confirmed for the
/// same server before, which is a stronger warning.
class CertificateDialog extends StatelessWidget {
  const CertificateDialog({
    super.key,
    required this.host,
    required this.info,
    required this.changed,
  });

  final String host;
  final CertificateInfo info;
  final bool changed;

  /// The fingerprint in rows of eight bytes, so that it fits a phone screen and
  /// can be compared row by row.
  static String fingerprintRows(String fingerprint) {
    final bytes = fingerprint.split(':');
    return [
      for (var i = 0; i < bytes.length; i += 8) bytes.skip(i).take(8).join(':'),
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final validUntil = DateFormat.yMMMd(context.localeName)
        .format(info.validTo);
    return AlertDialog(
      key: const Key('certificateDialog'),
      icon: Icon(
        changed ? Icons.gpp_maybe_outlined : Icons.verified_user_outlined,
        color: changed ? theme.colorScheme.error : null,
      ),
      title: Text(changed ? l10n.certChangedTitle : l10n.certTrustTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              changed ? l10n.certChangedBody(host) : l10n.certTrustBody(host),
            ),
            const SizedBox(height: 16),
            Text(l10n.certFingerprintLabel, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            SelectableText(
              fingerprintRows(info.fingerprint),
              key: const Key('certificateFingerprint'),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${l10n.certSubjectLabel}: ${info.subject}',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              l10n.certValidUntil(validUntil),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('certificateCancel'),
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('certificateTrust'),
          style: changed
              ? FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.certTrustAction),
        ),
      ],
    );
  }
}
