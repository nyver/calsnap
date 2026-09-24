/// Calories and macronutrients. Used both for values per 100 g and for
/// absolute amounts (item, meal and day totals).
class Nutrition {
  const Nutrition({
    this.kcal = 0,
    this.protein = 0,
    this.fat = 0,
    this.carbs = 0,
  });

  static const Nutrition zero = Nutrition();

  final double kcal;
  final double protein;
  final double fat;
  final double carbs;

  Nutrition operator +(Nutrition other) => Nutrition(
    kcal: kcal + other.kcal,
    protein: protein + other.protein,
    fat: fat + other.fat,
    carbs: carbs + other.carbs,
  );

  Nutrition copyWith({
    double? kcal,
    double? protein,
    double? fat,
    double? carbs,
  }) => Nutrition(
    kcal: kcal ?? this.kcal,
    protein: protein ?? this.protein,
    fat: fat ?? this.fat,
    carbs: carbs ?? this.carbs,
  );

  @override
  bool operator ==(Object other) =>
      other is Nutrition &&
      other.kcal == kcal &&
      other.protein == protein &&
      other.fat == fat &&
      other.carbs == carbs;

  @override
  int get hashCode => Object.hash(kcal, protein, fat, carbs);

  @override
  String toString() =>
      'Nutrition(kcal: $kcal, protein: $protein, fat: $fat, carbs: $carbs)';
}
