import '../../../core/domain/nutrition.dart';
import 'nutrition_calculator.dart';

enum MealType {
  breakfast,
  lunch,
  dinner,
  snack,
  other;

  static MealType? fromName(String? name) {
    for (final t in MealType.values) {
      if (t.name == name) return t;
    }
    return null;
  }
}

/// Where an item came from.
enum RecognitionSource {
  ai,
  manual;

  static RecognitionSource? fromName(String? name) {
    for (final s in RecognitionSource.values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// Origin of the nutrition values of an item, as reported by the backend, or
/// `user` for custom products.
abstract final class NutritionSourceName {
  static const String catalog = 'catalog';
  static const String aiEstimate = 'ai_estimate';
  static const String user = 'user';

  /// A packaged product looked up by barcode.
  static const String packaged = 'packaged';
}

/// A saved food item of a meal.
class MealItem {
  const MealItem({
    required this.id,
    required this.mealId,
    required this.name,
    required this.weightG,
    required this.per100,
    required this.createdAt,
    required this.updatedAt,
    this.foodId,
    this.estimatedWeightG,
    this.confidence,
    this.recognitionSource,
    this.wasCorrected = false,
    this.weightCorrected = false,
  });

  final String id;
  final String mealId;
  final String? foodId;
  final String name;

  /// The original AI weight estimate, null for manual items.
  final double? estimatedWeightG;
  final double weightG;
  final Nutrition per100;
  final double? confidence;
  final RecognitionSource? recognitionSource;
  final bool wasCorrected;

  /// True when the user changed the weight the app proposed, i.e. a correction
  /// record exists. An accepted personalized weight differs from
  /// [estimatedWeightG] but is not a correction.
  final bool weightCorrected;
  final DateTime createdAt;
  final DateTime updatedAt;

  Nutrition get values => NutritionCalculator.forWeight(weightG, per100);
}

/// A saved meal. Lists of meals may carry an empty [items] list; use
/// `MealRepository.getMeal` for the full meal.
class Meal {
  const Meal({
    required this.id,
    required this.mealTime,
    required this.totals,
    required this.createdAt,
    required this.updatedAt,
    this.mealType,
    this.photoPath,
    this.items = const [],
  });

  final String id;

  /// Local time of the meal.
  final DateTime mealTime;
  final MealType? mealType;

  /// Path relative to the app documents directory, or null.
  final String? photoPath;
  final Nutrition totals;
  final List<MealItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// Default meal type by local time of day: 05:00-10:59 breakfast,
/// 11:00-15:59 lunch, 17:00-21:59 dinner, otherwise snack.
MealType defaultMealType(DateTime local) {
  final minutes = local.hour * 60 + local.minute;
  if (minutes >= 5 * 60 && minutes < 11 * 60) return MealType.breakfast;
  if (minutes >= 11 * 60 && minutes < 16 * 60) return MealType.lunch;
  if (minutes >= 17 * 60 && minutes < 22 * 60) return MealType.dinner;
  return MealType.snack;
}
