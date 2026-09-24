import 'package:intl/intl.dart';

/// Locale-aware number formatting without false precision.
class NutritionFormatter {
  NutritionFormatter(this.locale)
    : _whole = NumberFormat('0', locale),
      _oneDecimal = NumberFormat('0.0', locale);

  final String locale;
  final NumberFormat _whole;
  final NumberFormat _oneDecimal;

  /// Calories as a whole number, without digit grouping ("1460").
  String kcal(double value) => _whole.format(value.round());

  /// Grams of a macronutrient: one decimal place below 10 g, whole numbers
  /// otherwise.
  String macro(double value) {
    final rounded = (value * 10).round() / 10;
    if (rounded.abs() < 10) return _oneDecimal.format(rounded);
    return _whole.format(value.round());
  }

  /// Total of an unsaved AI result: rounded to the nearest 10 kcal and
  /// prefixed with an approximation sign ("≈ 640").
  String approximateKcal(double value) =>
      '≈ ${_whole.format((value / 10).round() * 10)}';

  /// Weight in grams: whole when possible, otherwise one decimal.
  String weight(double grams) {
    final rounded = (grams * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? _whole.format(rounded.round())
        : _oneDecimal.format(rounded);
  }
}

/// Parses user input as a finite number. Accepts a comma or a dot as decimal
/// separator (Russian keyboards) and rejects everything else.
double? parseNumber(String input) {
  final text = input.trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  final value = double.tryParse(text);
  if (value == null || !value.isFinite) return null;
  return value;
}

/// Parses a whole number (no fractional part).
int? parseWholeNumber(String input) => int.tryParse(input.trim());
