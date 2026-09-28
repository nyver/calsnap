import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../balanced_plate/domain/balanced_plate_analyzer.dart';
import '../../balanced_plate/domain/plate_analysis.dart';
import 'meal_draft_notifier.dart';

const _analyzer = BalancedPlateAnalyzer();

/// The balanced-plate analysis of the current meal draft, recomputed
/// synchronously on every draft change. Null when there is no draft or it
/// has no items; the analyzer itself performs no repository or network
/// access.
final plateAnalysisProvider = Provider<PlateAnalysis?>((ref) {
  final draft = ref.watch(mealDraftProvider);
  if (draft == null || draft.items.isEmpty) return null;
  return _analyzer.analyze([
    for (final item in draft.items)
      PlatePortion(
        group: item.plateGroup,
        quality: item.plateQuality,
        weightG: item.weightG,
      ),
  ]);
});
