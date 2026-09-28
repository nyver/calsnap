import 'plate_analysis.dart';
import 'plate_group.dart';

/// Named thresholds of the balanced plate model. Kept here, not in UI code,
/// so every consumer (analyzer, tests, card) reads the same constants.
abstract final class PlateThresholds {
  /// Below this eligible weight, a verdict would be based on too little food.
  static const double minEligibleWeightG = 80;

  /// Below this fraction of classified weight, the analysis is unreliable.
  static const double minCoverage = 0.60;

  /// Below this coverage, the card adds a "based on N%" note.
  static const double coverageNoteThreshold = 0.90;

  /// Healthy fat is reported present above this total weight.
  static const double healthyFatPresenceThresholdG = 3;

  static const double lowVegetableFruitRatio = 0.30;
  static const double carbohydrateDominanceRatio = 0.50;
  static const double lowProteinRatio = 0.15;
  static const double lowComplexCarbohydrateRatio = 0.10;

  static const double nicelyBalancedVegetableFruitMin = 0.40;
  static const double nicelyBalancedVegetableFruitMax = 0.60;
  static const double nicelyBalancedProteinMin = 0.15;
  static const double nicelyBalancedProteinMax = 0.35;
  static const double nicelyBalancedComplexCarbohydrateMin = 0.15;
  static const double nicelyBalancedComplexCarbohydrateMax = 0.35;

  static const int maxRecommendations = 2;
}

/// Pure, deterministic analyzer of a meal's plate balance. Has no Flutter,
/// Riverpod or meal-model dependency: it operates on [PlatePortion] tuples
/// only, so it is trivially unit-testable and independent of how the caller
/// obtains weights and plate groups.
///
/// This is a concrete class, not an interface: there is exactly one
/// implementation, and AGENTS.md forbids single-implementation interfaces.
class BalancedPlateAnalyzer {
  const BalancedPlateAnalyzer();

  PlateAnalysis analyze(Iterable<PlatePortion> portions) {
    final valid = portions.where((p) => p.weightG.isFinite && p.weightG > 0);

    double totalWeight = 0;
    double vegetableFruitWeight = 0;
    double proteinWeight = 0;
    double complexCarbohydrateWeight = 0;
    double healthyFatWeight = 0;
    double unclassifiedWeight = 0;

    for (final p in valid) {
      totalWeight += p.weightG;
      switch (p.group) {
        case PlateGroup.vegetable:
        case PlateGroup.fruit:
          vegetableFruitWeight += p.weightG;
        case PlateGroup.protein:
          proteinWeight += p.weightG;
        case PlateGroup.complexCarbohydrate:
          complexCarbohydrateWeight += p.weightG;
        case PlateGroup.healthyFat:
          healthyFatWeight += p.weightG;
        case PlateGroup.dairy:
          break;
        case PlateGroup.other:
          if (p.quality == PlateQuality.mixed) unclassifiedWeight += p.weightG;
        case PlateGroup.unknown:
          unclassifiedWeight += p.weightG;
      }
    }

    final eligibleWeight =
        vegetableFruitWeight + proteinWeight + complexCarbohydrateWeight;
    // NOTE: coverage excludes unknown and other/mixed weight from the
    // numerator instead of using knownEligible/total (design.md Decision 4).
    // An ordinary drink or sauce (group `other`, no `mixed` quality) would
    // otherwise push an ordinary plate below the coverage gate.
    final coverage = totalWeight > 0
        ? (totalWeight - unclassifiedWeight) / totalWeight
        : 0.0;
    final healthyFatPresent =
        healthyFatWeight > PlateThresholds.healthyFatPresenceThresholdG;

    if (eligibleWeight < PlateThresholds.minEligibleWeightG ||
        coverage < PlateThresholds.minCoverage) {
      return const PlateAnalysis(
        verdict: PlateVerdict.insufficientData,
        vegetableFruitRatio: 0,
        proteinRatio: 0,
        complexCarbohydrateRatio: 0,
        coverage: 0,
        eligibleWeightG: 0,
        healthyFatPresent: false,
        recommendations: [],
      );
    }

    final vegetableFruitRatio = vegetableFruitWeight / eligibleWeight;
    final proteinRatio = proteinWeight / eligibleWeight;
    final complexCarbohydrateRatio = complexCarbohydrateWeight / eligibleWeight;

    final recommendations = <PlateRecommendation>[];
    final lowVegetables =
        vegetableFruitRatio < PlateThresholds.lowVegetableFruitRatio;
    final carbohydrateDominance =
        complexCarbohydrateRatio > PlateThresholds.carbohydrateDominanceRatio;
    final lowProtein = proteinRatio < PlateThresholds.lowProteinRatio;
    if (lowVegetables) {
      recommendations.add(
        const PlateRecommendation(
          type: PlateRecommendationType.addVegetables,
          priority: 100,
        ),
      );
    }
    if (carbohydrateDominance) {
      recommendations.add(
        const PlateRecommendation(
          type: PlateRecommendationType.reduceCarbohydrateDominance,
          priority: 90,
        ),
      );
    }
    if (lowProtein) {
      recommendations.add(
        const PlateRecommendation(
          type: PlateRecommendationType.addProtein,
          priority: 80,
        ),
      );
    }
    if (complexCarbohydrateRatio <
            PlateThresholds.lowComplexCarbohydrateRatio &&
        vegetableFruitRatio >= PlateThresholds.lowVegetableFruitRatio &&
        proteinRatio >= PlateThresholds.lowProteinRatio) {
      recommendations.add(
        const PlateRecommendation(
          type: PlateRecommendationType.addComplexCarbohydrates,
          priority: 10,
        ),
      );
    }
    recommendations.sort((a, b) => b.priority.compareTo(a.priority));
    final limited = recommendations
        .take(PlateThresholds.maxRecommendations)
        .toList();

    // NOTE: priorities are addVegetables 100 > reduceCarbohydrateDominance 90
    // > addProtein 80 > addComplexCarbohydrates 10 (design.md Decision 4).
    // BALANCED_PLATE.md §11.1 ranks protein above carbohydrate dominance, but
    // its own acceptance case (§26.1: 50/50/300 -> addVegetables +
    // reduceCarbohydrateDominance) requires the order used here.
    final nicelyBalanced =
        vegetableFruitRatio >=
            PlateThresholds.nicelyBalancedVegetableFruitMin &&
        vegetableFruitRatio <=
            PlateThresholds.nicelyBalancedVegetableFruitMax &&
        proteinRatio >= PlateThresholds.nicelyBalancedProteinMin &&
        proteinRatio <= PlateThresholds.nicelyBalancedProteinMax &&
        complexCarbohydrateRatio >=
            PlateThresholds.nicelyBalancedComplexCarbohydrateMin &&
        complexCarbohydrateRatio <=
            PlateThresholds.nicelyBalancedComplexCarbohydrateMax;

    final PlateVerdict verdict;
    if (lowVegetables || carbohydrateDominance || lowProtein) {
      verdict = PlateVerdict.improvable;
    } else if (nicelyBalanced) {
      verdict = PlateVerdict.nicelyBalanced;
    } else {
      // NOTE: "reasonably balanced" (nearlyBalanced) is a fourth verdict not
      // named in BALANCED_PLATE.md §10, added for analyzable meals that
      // trigger no corrective rule but fall outside the strict nicely-balanced
      // ranges (design.md Decision 4). Without it, such a meal would show
      // "could be more balanced" with no recommendation to justify it.
      verdict = PlateVerdict.nearlyBalanced;
    }

    return PlateAnalysis(
      verdict: verdict,
      vegetableFruitRatio: vegetableFruitRatio,
      proteinRatio: proteinRatio,
      complexCarbohydrateRatio: complexCarbohydrateRatio,
      coverage: coverage,
      eligibleWeightG: eligibleWeight,
      healthyFatPresent: healthyFatPresent,
      recommendations: limited,
    );
  }
}
