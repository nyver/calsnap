import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/l10n_x.dart';
import '../domain/photo_quality.dart';

/// Advice about the photo, shown above "Retake" and "Analyze". It never
/// blocks: the user can analyze the photo anyway.
class PhotoQualityBanner extends StatelessWidget {
  const PhotoQualityBanner({required this.issues, super.key});

  /// Shown most important first; at most [maxShown] are listed.
  final List<PhotoIssue> issues;

  static const int maxShown = 2;

  static String message(AppLocalizations l10n, PhotoIssue issue) =>
      switch (issue) {
        PhotoIssue.steepAngle => l10n.issueSteepAngle,
        PhotoIssue.plateCutOff => l10n.issuePlateCutOff,
        PhotoIssue.blurry => l10n.issueBlurry,
        PhotoIssue.tooDark => l10n.issueTooDark,
        PhotoIssue.tooBright => l10n.issueTooBright,
      };

  /// Geometry problems first: they matter most for the portion size.
  static int _rank(PhotoIssue issue) => switch (issue) {
    PhotoIssue.steepAngle => 0,
    PhotoIssue.plateCutOff => 1,
    PhotoIssue.blurry => 2,
    PhotoIssue.tooDark => 3,
    PhotoIssue.tooBright => 3,
  };

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final shown = ([
      ...issues,
    ]..sort((a, b) => _rank(a).compareTo(_rank(b)))).take(maxShown);
    return Container(
      key: const Key('photoQualityBanner'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: scheme.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.qualityTitle,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: scheme.onTertiaryContainer),
                ),
                for (final issue in shown)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      message(l10n, issue),
                      style: TextStyle(color: scheme.onTertiaryContainer),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
