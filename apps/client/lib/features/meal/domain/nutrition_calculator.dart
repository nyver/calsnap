import '../../../core/domain/nutrition.dart';

/// Pure nutrition arithmetic. All values are computed from unrounded numbers;
/// rounding happens only when displaying.
abstract final class NutritionCalculator {
  /// `nutrient = weight_g × nutrient_per_100g / 100`.
  static Nutrition forWeight(double weightG, Nutrition per100) => Nutrition(
    kcal: weightG * per100.kcal / 100,
    protein: weightG * per100.protein / 100,
    fat: weightG * per100.fat / 100,
    carbs: weightG * per100.carbs / 100,
  );

  /// Sum of unrounded values (meal totals from items, day totals from meals).
  static Nutrition total(Iterable<Nutrition> values) =>
      values.fold(Nutrition.zero, (sum, v) => sum + v);
}
