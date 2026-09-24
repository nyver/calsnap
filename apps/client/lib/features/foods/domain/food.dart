import '../../../core/domain/nutrition.dart';

/// A product in the local food cache.
class Food {
  const Food({
    required this.id,
    required this.name,
    required this.per100,
    required this.source,
    this.nameRu,
    this.normalizedName,
    this.aliases = const [],
    this.sourceId,
    this.gramsPerPiece,
    this.gramsPerPortion,
    this.densityGPerMl,
  });

  final String id;
  final String name;
  final String? nameRu;
  final String? normalizedName;
  final List<String> aliases;
  final Nutrition per100;

  /// `catalog`, `ai_estimate` or `user`.
  final String source;
  final String? sourceId;
  final double? gramsPerPiece;
  final double? gramsPerPortion;
  final double? densityGPerMl;

  /// Name in the given language code, falling back to the base name.
  String displayName(String languageCode) {
    if (languageCode == 'ru' && nameRu != null && nameRu!.isNotEmpty) {
      return nameRu!;
    }
    return name;
  }
}

/// Input for creating a custom product. Validated by [validate].
class CustomFoodInput {
  const CustomFoodInput({required this.name, required this.per100});

  final String name;
  final Nutrition per100;

  /// Returns the first problem, or null when valid.
  CustomFoodProblem? validate() {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 100) {
      return CustomFoodProblem.name;
    }
    final n = per100;
    if (!_inRange(n.kcal, 0, 900)) return CustomFoodProblem.kcal;
    if (!_inRange(n.protein, 0, 100) ||
        !_inRange(n.fat, 0, 100) ||
        !_inRange(n.carbs, 0, 100)) {
      return CustomFoodProblem.macros;
    }
    return null;
  }

  static bool _inRange(double v, double min, double max) =>
      v.isFinite && v >= min && v <= max;
}

enum CustomFoodProblem { name, kcal, macros }
