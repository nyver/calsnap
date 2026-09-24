import 'dart:convert';
import 'dart:isolate';

import '../../meal/domain/meal.dart';
import '../../settings/domain/user_settings.dart';

/// Version of the JSON export document.
const int exportFormatVersion = 1;

/// Renders meals as RFC 4180 CSV (CRLF rows, `.` decimals, UTF-8 by the
/// caller) with one row per meal item, ordered by meal time.
String buildCsv(List<Meal> meals) {
  final sorted = [...meals]..sort((a, b) => a.mealTime.compareTo(b.mealTime));
  final rows = <List<String>>[
    [
      'date',
      'meal_type',
      'food',
      'weight_g',
      'kcal',
      'protein',
      'fat',
      'carbs',
    ],
    for (final meal in sorted)
      for (final item in meal.items)
        [
          _isoWithOffset(meal.mealTime),
          meal.mealType?.name ?? '',
          item.name,
          _num(item.weightG),
          _num(item.values.kcal),
          _num(item.values.protein),
          _num(item.values.fat),
          _num(item.values.carbs),
        ],
  ];
  return '${rows.map((r) => r.map(_csvCell).join(',')).join('\r\n')}\r\n';
}

/// Renders the versioned JSON export.
String buildJson(
  List<Meal> meals, {
  required AppSettings settings,
  required DateTime exportedAt,
  required String appVersion,
}) {
  final sorted = [...meals]..sort((a, b) => a.mealTime.compareTo(b.mealTime));
  Map<String, Object?> nutrition(double kcal, double p, double f, double c) => {
    'kcal': _round(kcal),
    'protein': _round(p),
    'fat': _round(f),
    'carbs': _round(c),
  };
  final doc = <String, Object?>{
    'format': 'calsnap-export',
    'formatVersion': exportFormatVersion,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'appVersion': appVersion,
    'settings': {
      'dailyKcalTarget': settings.dailyKcalTarget,
      'dailyProteinTargetG': settings.dailyProteinTargetG,
      'dailyFatTargetG': settings.dailyFatTargetG,
      'dailyCarbsTargetG': settings.dailyCarbsTargetG,
      'plateDiameterCm': settings.plateDiameterCm,
      'savePhotos': settings.savePhotos,
      'language': settings.language.name,
      'unitSystem': settings.unitSystem,
    },
    'meals': [
      for (final meal in sorted)
        {
          'id': meal.id,
          'mealTime': _isoWithOffset(meal.mealTime),
          'mealType': meal.mealType?.name,
          'photoPath': meal.photoPath,
          'totals': nutrition(
            meal.totals.kcal,
            meal.totals.protein,
            meal.totals.fat,
            meal.totals.carbs,
          ),
          'items': [
            for (final item in meal.items)
              {
                'id': item.id,
                'name': item.name,
                'estimatedWeightG': item.estimatedWeightG,
                'weightG': item.weightG,
                'per100g': nutrition(
                  item.per100.kcal,
                  item.per100.protein,
                  item.per100.fat,
                  item.per100.carbs,
                ),
                'values': nutrition(
                  item.values.kcal,
                  item.values.protein,
                  item.values.fat,
                  item.values.carbs,
                ),
                'confidence': item.confidence,
                'recognitionSource': item.recognitionSource?.name,
                'wasCorrected': item.wasCorrected,
              },
          ],
        },
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(doc);
}

/// Runs [buildCsv] off the UI isolate.
Future<String> buildCsvInBackground(List<Meal> meals) =>
    Isolate.run(() => buildCsv(meals));

/// Runs [buildJson] off the UI isolate.
Future<String> buildJsonInBackground(
  List<Meal> meals, {
  required AppSettings settings,
  required DateTime exportedAt,
  required String appVersion,
}) => Isolate.run(
  () => buildJson(
    meals,
    settings: settings,
    exportedAt: exportedAt,
    appVersion: appVersion,
  ),
);

/// Quotes a CSV cell when needed and neutralizes spreadsheet formulas: cells
/// that start with `=`, `+`, `-`, `@` (or a tab / carriage return) get a
/// leading apostrophe.
String _csvCell(String value) {
  var cell = value;
  if (cell.isNotEmpty && '=+-@\t\r'.contains(cell[0])) {
    cell = "'$cell";
  }
  if (cell.contains(RegExp(r'[",\r\n]'))) {
    cell = '"${cell.replaceAll('"', '""')}"';
  }
  return cell;
}

/// Numbers with one decimal at most and `.` as separator, regardless of locale.
String _num(double v) {
  final r = _round(v);
  return r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
}

double _round(double v) => (v * 10).round() / 10;

/// Local date-time with UTC offset: `2026-03-10T12:30:00+03:00`.
String _isoWithOffset(DateTime local) {
  String two(int v) => v.toString().padLeft(2, '0');
  final offset = local.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final abs = offset.abs();
  return '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-${two(local.day)}'
      'T${two(local.hour)}:${two(local.minute)}:${two(local.second)}'
      '$sign${two(abs.inHours)}:${two(abs.inMinutes.remainder(60))}';
}
