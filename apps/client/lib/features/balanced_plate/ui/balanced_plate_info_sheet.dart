import 'package:flutter/material.dart';

import '../../../shared/l10n_x.dart';

/// Explains the balanced-plate model and shows the disclaimer. Opened from
/// the card's info button; never shown unprompted.
Future<void> showBalancedPlateInfoSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _BalancedPlateInfoSheet(),
    );

class _BalancedPlateInfoSheet extends StatelessWidget {
  const _BalancedPlateInfoSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.balancedPlateTitle, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(l10n.balancedPlateInfoBody),
              const SizedBox(height: 16),
              Text(
                l10n.balancedPlateDisclaimer,
                key: const Key('balancedPlateDisclaimer'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
