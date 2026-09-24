import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../shared/l10n_x.dart';

/// What is stored where, and what is sent when a photo is analyzed. The text is
/// bundled with the app (localization resources), so it is available offline.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  Future<void> _openPolicy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final unavailable = context.l10n.privacyPolicyUnavailable;
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(AppConfig.privacyPolicyUrl),
        mode: LaunchMode.externalApplication,
      );
    } on Exception {
      opened = false;
    }
    if (!opened) messenger.showSnackBar(SnackBar(content: Text(unavailable)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final points = [
      (Icons.phone_android, l10n.privacyDiary),
      (Icons.cloud_upload_outlined, l10n.privacyAnalysis),
      (Icons.no_photography_outlined, l10n.privacyNoStorage),
      (Icons.gavel_outlined, l10n.privacyProvider),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.privacyTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final (icon, text) in points)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      text,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('privacyPolicyLink'),
            onPressed: () => _openPolicy(context),
            icon: const Icon(Icons.open_in_new),
            label: Text(l10n.privacyPolicyLink),
          ),
        ],
      ),
    );
  }
}
