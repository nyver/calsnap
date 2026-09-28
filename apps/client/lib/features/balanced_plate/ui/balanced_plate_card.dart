import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/l10n_x.dart';
import '../domain/plate_analysis.dart';
import 'balanced_plate_info_sheet.dart';

extension _VerdictText on AppLocalizations {
  String verdict(PlateVerdict v) => switch (v) {
    PlateVerdict.insufficientData => balancedPlateInsufficientData,
    PlateVerdict.improvable => balancedPlateVerdictImprovable,
    PlateVerdict.nicelyBalanced => balancedPlateVerdictBalanced,
    PlateVerdict.nearlyBalanced => balancedPlateVerdictNearlyBalanced,
  };

  String recommendation(PlateRecommendationType t) => switch (t) {
    PlateRecommendationType.addVegetables => balancedPlateRecAddVegetables,
    PlateRecommendationType.reduceCarbohydrateDominance =>
      balancedPlateRecReduceCarbohydrateDominance,
    PlateRecommendationType.addProtein => balancedPlateRecAddProtein,
    PlateRecommendationType.addComplexCarbohydrates =>
      balancedPlateRecAddComplexCarbohydrates,
  };
}

/// The "Balance of the plate" card: local, deterministic guidance on the
/// composition of the current meal. Grows with its content; shown by the
/// caller only when there is something to analyze.
class BalancedPlateCard extends StatelessWidget {
  const BalancedPlateCard({required this.analysis, super.key});

  final PlateAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Card(
      key: const Key('balancedPlateCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pie_chart_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.balancedPlateTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton(
                    key: const Key('balancedPlateInfo'),
                    tooltip: l10n.balancedPlateInfoTooltip,
                    icon: const Icon(Icons.info_outline),
                    onPressed: () => showBalancedPlateInfoSheet(context),
                  ),
                ),
              ],
            ),
            if (!analysis.isAnalyzable)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.balancedPlateInsufficientData,
                  key: const Key('balancedPlateInsufficientData'),
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              _AnalyzableBody(analysis: analysis, l10n: l10n, theme: theme),
          ],
        ),
      ),
    );
  }
}

class _AnalyzableBody extends StatelessWidget {
  const _AnalyzableBody({
    required this.analysis,
    required this.l10n,
    required this.theme,
  });

  final PlateAnalysis analysis;
  final AppLocalizations l10n;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final (veg, protein, carb) = analysis.displayPercents();
    final recommendations = analysis.recommendations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(l10n.verdict(analysis.verdict), style: theme.textTheme.bodyLarge),
        const SizedBox(height: 12),
        _PlateShareRow(
          label: l10n.balancedPlateGroupVegetablesFruit,
          percent: veg,
          color: theme.colorScheme.primary,
          l10n: l10n,
        ),
        const SizedBox(height: 8),
        _PlateShareRow(
          label: l10n.balancedPlateGroupProtein,
          percent: protein,
          color: theme.colorScheme.secondary,
          l10n: l10n,
        ),
        const SizedBox(height: 8),
        _PlateShareRow(
          label: l10n.balancedPlateGroupComplexCarbohydrates,
          percent: carb,
          color: theme.colorScheme.tertiary,
          l10n: l10n,
        ),
        if (analysis.coverage < 0.90) ...[
          const SizedBox(height: 8),
          Text(
            l10n.balancedPlateCoverage((analysis.coverage * 100).round()),
            key: const Key('balancedPlateCoverageNote'),
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (recommendations.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final rec in recommendations)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.recommendation(rec.type),
                      key: Key('balancedPlateRec-${rec.type.name}'),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _PlateShareRow extends StatelessWidget {
  const _PlateShareRow({
    required this.label,
    required this.percent,
    required this.color,
    required this.l10n,
  });

  final String label;
  final int percent;
  final Color color;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: l10n.balancedPlateShareSemantics(label, percent),
      container: true,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              Text('$percent%', style: theme.textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 6,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }
}
