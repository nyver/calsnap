import 'plate_group.dart';

/// One meal item reduced to what the analyzer needs: its plate group,
/// optional quality, and weight in grams. Deliberately independent of
/// `DraftItem`/`MealItem` so the domain has no dependency on the meal feature.
class PlatePortion {
  const PlatePortion({
    required this.group,
    this.quality,
    required this.weightG,
  });

  final PlateGroup group;
  final PlateQuality? quality;
  final double weightG;
}

enum PlateVerdict {
  insufficientData,
  improvable,
  nicelyBalanced,
  nearlyBalanced,
}

enum PlateRecommendationType {
  addVegetables,
  reduceCarbohydrateDominance,
  addProtein,
  addComplexCarbohydrates,
}

class PlateRecommendation {
  const PlateRecommendation({required this.type, required this.priority});

  final PlateRecommendationType type;
  final int priority;
}

/// Result of analyzing one meal's items. See `BalancedPlateAnalyzer.analyze`.
class PlateAnalysis {
  const PlateAnalysis({
    required this.verdict,
    required this.vegetableFruitRatio,
    required this.proteinRatio,
    required this.complexCarbohydrateRatio,
    required this.coverage,
    required this.eligibleWeightG,
    required this.healthyFatPresent,
    required this.recommendations,
  });

  final PlateVerdict verdict;
  final double vegetableFruitRatio;
  final double proteinRatio;
  final double complexCarbohydrateRatio;
  final double coverage;
  final double eligibleWeightG;
  final bool healthyFatPresent;
  final List<PlateRecommendation> recommendations;

  bool get isAnalyzable => verdict != PlateVerdict.insufficientData;

  /// The three ratios as whole-number percentages that always sum to 100,
  /// using largest-remainder rounding. Ties are broken in the fixed order
  /// vegetables & fruit, protein, complex carbohydrates.
  ///
  /// Returns `(0, 0, 0)` when the meal is not analyzable.
  (int vegetableFruit, int protein, int complexCarbohydrate) displayPercents() {
    if (!isAnalyzable) return (0, 0, 0);
    final raw = [vegetableFruitRatio, proteinRatio, complexCarbohydrateRatio];
    final scaled = raw.map((r) => r * 100).toList();
    final floors = scaled.map((v) => v.floor()).toList();
    var remainder = 100 - floors.reduce((a, b) => a + b);
    final order = List<int>.generate(3, (i) => i)
      ..sort((a, b) {
        final byFraction = (scaled[b] - floors[b]).compareTo(
          scaled[a] - floors[a],
        );
        if (byFraction != 0) return byFraction;
        return a.compareTo(b);
      });
    final result = List<int>.from(floors);
    for (final i in order) {
      if (remainder <= 0) break;
      result[i]++;
      remainder--;
    }
    return (result[0], result[1], result[2]);
  }
}
