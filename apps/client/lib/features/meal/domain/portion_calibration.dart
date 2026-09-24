import 'dart:math' as math;

import '../../../core/domain/nutrition.dart';

/// Coarse food class used when a food has too few corrections of its own.
///
/// NOTE: the nutrition catalog has no category field, so the class is derived
/// from the per-100 g values. That also works for AI-estimated and custom
/// foods, which never have a catalog category. "Side dishes" such as rice,
/// buckwheat, pasta and potatoes all land in [carb].
enum PortionCategory {
  /// Under 60 kcal per 100 g: vegetables, broths, drinks.
  light,
  carb,
  protein,
  fat,
  mixed;

  static const double _lightKcalPer100 = 60;

  static PortionCategory of(Nutrition per100) {
    if (per100.kcal < _lightKcalPer100) return PortionCategory.light;
    // Atwater factors; the shares are of the macro energy, not of `kcal`.
    final protein = per100.protein * 4;
    final carbs = per100.carbs * 4;
    final fat = per100.fat * 9;
    final total = protein + carbs + fat;
    if (total <= 0) return PortionCategory.mixed;
    if (carbs / total >= 0.55) return PortionCategory.carb;
    if (protein / total >= 0.4) return PortionCategory.protein;
    if (fat / total >= 0.55) return PortionCategory.fat;
    return PortionCategory.mixed;
  }
}

/// One recorded user correction of an AI weight estimate.
class CorrectionSample {
  const CorrectionSample({
    required this.normalizedName,
    required this.aiWeightG,
    required this.userWeightG,
    required this.createdAtMs,
    this.category,
  });

  final String normalizedName;
  final double aiWeightG;
  final double userWeightG;
  final int createdAtMs;

  /// Null when the food is not known locally.
  final PortionCategory? category;
}

/// Which group of corrections a factor was learned from, most specific first.
enum PortionScope { food, category, global }

/// A learned multiplier for AI weight estimates.
class PortionAdjustment {
  const PortionAdjustment({
    required this.factor,
    required this.scope,
    required this.sampleCount,
  });

  final double factor;
  final PortionScope scope;
  final int sampleCount;

  /// The weight to propose for an AI [estimateG], in whole grams.
  double apply(double estimateG) => (estimateG * factor).roundToDouble();
}

/// Learns how the user's real portions differ from the AI estimates.
///
/// A factor is the exponentially weighted average of `user / ai` weight ratios
/// (in log space, so that halving and doubling cancel out). It is looked up
/// for the specific food first, then for its [PortionCategory], then over all
/// foods, and the first level with at least [minSamples] corrections wins.
/// Everything is computed from the local correction records; nothing leaves
/// the device.
class PortionCalibration {
  PortionCalibration(Iterable<CorrectionSample> samples) {
    final ordered = [
      for (final s in samples)
        if (_usable(s)) s,
    ]..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
    final byFood = <String, List<double>>{};
    final byCategory = <PortionCategory, List<double>>{};
    final all = <double>[];
    for (final s in ordered) {
      final ratio = (s.userWeightG / s.aiWeightG)
          .clamp(_minSampleRatio, _maxSampleRatio)
          .toDouble();
      final logRatio = math.log(ratio);
      byFood.putIfAbsent(s.normalizedName, () => []).add(logRatio);
      final category = s.category;
      if (category != null) {
        byCategory.putIfAbsent(category, () => []).add(logRatio);
      }
      all.add(logRatio);
    }
    _food = {for (final e in byFood.entries) e.key: ?_learned(e.value)};
    _category = {for (final e in byCategory.entries) e.key: ?_learned(e.value)};
    _global = _learned(all);
  }

  /// Corrections needed before a level is trusted.
  static const int minSamples = 3;

  /// Bounds of the applied factor.
  static const double minFactor = 0.6;
  static const double maxFactor = 1.6;

  /// Factors closer to 1 than this are not worth changing the estimate for.
  static const double deadZone = 0.05;

  /// Weight of the newest correction in the moving average.
  static const double _alpha = 0.3;

  // A single typo (1800 g instead of 180 g) must not drag the average.
  static const double _minSampleRatio = 0.25;
  static const double _maxSampleRatio = 4;

  late final Map<String, _Learned> _food;
  late final Map<PortionCategory, _Learned> _category;
  late final _Learned? _global;

  static bool _usable(CorrectionSample s) =>
      s.aiWeightG.isFinite &&
      s.userWeightG.isFinite &&
      s.aiWeightG > 0 &&
      s.userWeightG > 0;

  static _Learned? _learned(List<double> logRatios) {
    if (logRatios.length < minSamples) return null;
    var ewma = logRatios.first;
    for (final r in logRatios.skip(1)) {
      ewma = _alpha * r + (1 - _alpha) * ewma;
    }
    return _Learned(
      math.exp(ewma).clamp(minFactor, maxFactor).toDouble(),
      logRatios.length,
    );
  }

  /// The adjustment for a recognized food, or null when nothing has been
  /// learned yet or the learned factor is too close to 1 to matter.
  ///
  /// A level with enough corrections is authoritative even when its factor is
  /// about 1: a user who agrees with the AI on buckwheat is not pushed toward a
  /// category-wide bias.
  PortionAdjustment? adjustmentFor({
    required String? normalizedName,
    required Nutrition per100,
  }) {
    final (learned, scope) = _pick(normalizedName, per100);
    if (learned == null || scope == null) return null;
    if ((learned.factor - 1).abs() < deadZone) return null;
    return PortionAdjustment(
      factor: learned.factor,
      scope: scope,
      sampleCount: learned.count,
    );
  }

  (_Learned?, PortionScope?) _pick(String? normalizedName, Nutrition per100) {
    final food = normalizedName == null ? null : _food[normalizedName];
    if (food != null) return (food, PortionScope.food);
    final category = _category[PortionCategory.of(per100)];
    if (category != null) return (category, PortionScope.category);
    if (_global != null) return (_global, PortionScope.global);
    return (null, null);
  }
}

class _Learned {
  const _Learned(this.factor, this.count);

  final double factor;
  final int count;
}
