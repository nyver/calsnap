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

  /// `catalog`, `ai_estimate`, `user` or `packaged`. A product with a barcode
  /// has it as [sourceId].
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

/// Values to start the custom product form with, for example what a label
/// scan read. A null value is one the source did not have; the form leaves it
/// empty for the user to fill in.
class CustomFoodPrefill {
  const CustomFoodPrefill({
    this.name,
    this.kcal,
    this.protein,
    this.fat,
    this.carbs,
    this.servingSizeG,
    this.notes = const [],
  });

  final String? name;
  final double? kcal;
  final double? protein;
  final double? fat;
  final double? carbs;
  final double? servingSizeG;

  /// What the user should double-check, already localized.
  final List<String> notes;
}

/// Input for creating a custom product. Validated by [validate].
class CustomFoodInput {
  const CustomFoodInput({
    required this.name,
    required this.per100,
    this.servingSizeG,
    this.barcode,
  });

  final String name;
  final Nutrition per100;

  /// The declared serving in grams, when known.
  final double? servingSizeG;

  /// The normalized barcode of the package, so that a later scan finds the
  /// product locally.
  final String? barcode;

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
    final serving = servingSizeG;
    if (serving != null &&
        !(serving.isFinite && serving > 0 && serving <= 2000)) {
      return CustomFoodProblem.serving;
    }
    return null;
  }

  static bool _inRange(double v, double min, double max) =>
      v.isFinite && v >= min && v <= max;
}

enum CustomFoodProblem { name, kcal, macros, serving }
