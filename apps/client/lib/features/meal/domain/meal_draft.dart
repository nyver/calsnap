import '../../../core/domain/nutrition.dart';
import 'meal.dart';
import 'nutrition_calculator.dart';
import 'portion_calibration.dart';

/// Unit conversion data of a food (not persisted with meal items).
class FoodUnits {
  const FoodUnits({
    this.gramsPerPiece,
    this.gramsPerPortion,
    this.densityGPerMl,
  });

  final double? gramsPerPiece;
  final double? gramsPerPortion;
  final double? densityGPerMl;
}

/// One editable item of a [MealDraft]. Immutable; edits create copies.
class DraftItem {
  const DraftItem({
    required this.id,
    required this.name,
    required this.weightG,
    required this.per100,
    required this.source,
    required this.originalName,
    required this.originalPer100,
    this.foodId,
    this.estimatedWeightG,
    this.confidence,
    this.nutritionSource,
    this.normalizedName,
    this.previouslyCorrected = false,
    this.units,
    this.suggestedWeightG,
    this.adjustment,
  });

  /// A manually added item (from search or a custom product).
  factory DraftItem.manual({
    required String id,
    required String name,
    required double weightG,
    required Nutrition per100,
    String? foodId,
    String? nutritionSource,
    String? normalizedName,
    FoodUnits? units,
  }) => DraftItem(
    id: id,
    name: name,
    weightG: weightG,
    per100: per100,
    source: RecognitionSource.manual,
    originalName: name,
    originalPer100: per100,
    foodId: foodId,
    nutritionSource: nutritionSource,
    normalizedName: normalizedName,
    units: units,
  );

  /// The item id equals the id of the persisted meal item.
  final String id;
  final String? foodId;
  final String name;
  final double weightG;
  final Nutrition per100;
  final RecognitionSource source;

  /// The raw AI weight estimate; null for manual items. Personalization never
  /// changes it, so that recorded corrections stay comparable to the AI.
  final double? estimatedWeightG;
  final double? confidence;

  /// `catalog`, `ai_estimate`, `user` or null when unknown (saved items).
  final String? nutritionSource;

  /// Stable key of the recognized food, used to cache it in `foods`.
  final String? normalizedName;

  /// Snapshot used to detect user corrections of AI items.
  final String originalName;
  final Nutrition originalPer100;

  /// True when the persisted item was already marked as corrected.
  final bool previouslyCorrected;

  /// Piece, portion and density data, when the food is known locally.
  final FoodUnits? units;

  /// The weight the app proposed to the user. Null means the AI estimate.
  /// An accepted proposal is not a correction; only a different weight is.
  final double? suggestedWeightG;

  /// The learned portion factor behind [suggestedWeightG], for a new
  /// recognition only (it is not persisted).
  final PortionAdjustment? adjustment;

  /// True when the user changed the proposed weight of an AI item.
  bool get weightCorrected {
    final estimate = estimatedWeightG;
    return source == RecognitionSource.ai &&
        estimate != null &&
        weightG != (suggestedWeightG ?? estimate);
  }

  /// True while the item still carries a personalized proposal.
  bool get isPersonalized => adjustment != null && weightG == suggestedWeightG;

  Nutrition get values => NutritionCalculator.forWeight(weightG, per100);

  /// An AI item counts as corrected once its weight, name or nutrition was
  /// changed by the user. The flag never reverts on its own for saved items.
  bool get wasCorrected =>
      source == RecognitionSource.ai &&
      (previouslyCorrected ||
          weightCorrected ||
          name != originalName ||
          per100 != originalPer100);

  DraftItem copyWith({
    String? name,
    double? weightG,
    Nutrition? per100,
    String? foodId,
    bool clearFoodId = false,
    String? nutritionSource,
    String? normalizedName,
    FoodUnits? units,
  }) => DraftItem(
    id: id,
    foodId: clearFoodId ? null : (foodId ?? this.foodId),
    name: name ?? this.name,
    weightG: weightG ?? this.weightG,
    per100: per100 ?? this.per100,
    source: source,
    estimatedWeightG: estimatedWeightG,
    confidence: confidence,
    nutritionSource: nutritionSource ?? this.nutritionSource,
    normalizedName: normalizedName ?? this.normalizedName,
    originalName: originalName,
    originalPer100: originalPer100,
    previouslyCorrected: previouslyCorrected,
    units: units ?? this.units,
    suggestedWeightG: suggestedWeightG,
    adjustment: adjustment,
  );
}

/// The in-memory meal under construction: the recognition result, a manual
/// entry, or a saved meal opened for editing.
class MealDraft {
  const MealDraft({
    required this.mealTime,
    required this.mealType,
    required this.items,
    this.editingMealId,
    this.tempPhotoFile,
    this.photoPath,
    this.warnings = const {},
    this.fromRecognition = false,
    this.createdAt,
  });

  /// Set when an existing meal is being edited.
  final String? editingMealId;
  final DateTime mealTime;
  final MealType mealType;
  final List<DraftItem> items;

  /// Absolute path of the prepared temporary photo of a new recognition.
  final String? tempPhotoFile;

  /// Relative path of the stored photo of an edited meal.
  final String? photoPath;

  /// Warning codes reported by the backend.
  final Set<String> warnings;

  /// True for a fresh AI result (its totals are shown as approximations).
  final bool fromRecognition;

  /// Creation time of the meal being edited, kept on save.
  final DateTime? createdAt;

  bool get isEditing => editingMealId != null;
  bool get isEmpty => items.isEmpty;

  Nutrition get totals =>
      NutritionCalculator.total(items.map((item) => item.values));

  MealDraft copyWith({
    DateTime? mealTime,
    MealType? mealType,
    List<DraftItem>? items,
  }) => MealDraft(
    editingMealId: editingMealId,
    mealTime: mealTime ?? this.mealTime,
    mealType: mealType ?? this.mealType,
    items: items ?? this.items,
    tempPhotoFile: tempPhotoFile,
    photoPath: photoPath,
    warnings: warnings,
    fromRecognition: fromRecognition,
    createdAt: createdAt,
  );
}
