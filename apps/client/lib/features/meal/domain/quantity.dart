/// Units in which a quantity can be entered. Storage and calculations always
/// use grams.
enum QuantityUnit { gram, milliliter, piece, portion }

/// Conversion of entered quantities to grams and weight validation.
abstract final class Quantity {
  /// Weights are accepted in the range (0, 5000] g.
  static const double maxWeightG = 5000;

  static bool isValidWeight(double? grams) =>
      grams != null && grams.isFinite && grams > 0 && grams <= maxWeightG;

  /// Units offered for a food. Pieces and portions only exist when the food
  /// defines their weight.
  static List<QuantityUnit> availableUnits({
    double? gramsPerPiece,
    double? gramsPerPortion,
  }) => [
    QuantityUnit.gram,
    QuantityUnit.milliliter,
    if (gramsPerPiece != null && gramsPerPiece > 0) QuantityUnit.piece,
    if (gramsPerPortion != null && gramsPerPortion > 0) QuantityUnit.portion,
  ];

  /// Converts [amount] in [unit] to grams, or null when the unit is not
  /// available for the food or the amount is not a finite positive number.
  /// Milliliters use [densityGPerMl], or 1.0 when unknown.
  static double? toGrams(
    double amount,
    QuantityUnit unit, {
    double? densityGPerMl,
    double? gramsPerPiece,
    double? gramsPerPortion,
  }) {
    if (!amount.isFinite || amount <= 0) return null;
    switch (unit) {
      case QuantityUnit.gram:
        return amount;
      case QuantityUnit.milliliter:
        final density = (densityGPerMl != null && densityGPerMl > 0)
            ? densityGPerMl
            : 1.0;
        return amount * density;
      case QuantityUnit.piece:
        if (gramsPerPiece == null || gramsPerPiece <= 0) return null;
        return amount * gramsPerPiece;
      case QuantityUnit.portion:
        if (gramsPerPortion == null || gramsPerPortion <= 0) return null;
        return amount * gramsPerPortion;
    }
  }
}
