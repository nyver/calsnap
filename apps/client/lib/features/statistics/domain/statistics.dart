import '../../../core/domain/nutrition.dart';
import '../../../core/utils/clock.dart';
import '../../meal/domain/meal.dart';
import '../../meal/domain/nutrition_calculator.dart';

/// Totals of one local day.
class DayStats {
  const DayStats({
    required this.day,
    required this.totals,
    required this.hasMeals,
  });

  final DateTime day;
  final Nutrition totals;

  /// Days without meals are empty, not zero intake.
  final bool hasMeals;
}

/// The last seven local days including today.
class WeekStats {
  const WeekStats({
    required this.days,
    required this.average,
    required this.loggedDays,
    required this.onTargetDays,
    required this.today,
    required this.kcalTarget,
  });

  /// Oldest first, exactly seven entries.
  final List<DayStats> days;

  /// Average over days that have at least one meal (zero when none).
  final Nutrition average;
  final int loggedDays;
  final int onTargetDays;
  final Nutrition today;
  final int? kcalTarget;

  bool get hasData => loggedDays > 0;
}

/// A logged day counts as on target when its kcal are within +-10% of the target.
const double adherenceTolerance = 0.10;

/// Computes the weekly statistics from meals of the last seven days.
WeekStats computeWeekStats({
  required List<Meal> meals,
  required DateTime today,
  required int? kcalTarget,
  TimeZoneRules zone = const TimeZoneRules(),
}) {
  final first = zone.startOfDay(today.year, today.month, today.day - 6);
  final days = <DayStats>[];
  for (var i = 0; i < 7; i++) {
    final start = zone.startOfDay(first.year, first.month, first.day + i);
    final end = zone.startOfDay(first.year, first.month, first.day + i + 1);
    final startMs = zone.toEpochMs(start);
    final endMs = zone.toEpochMs(end);
    final ofDay = [
      for (final m in meals)
        if (zone.toEpochMs(m.mealTime) >= startMs &&
            zone.toEpochMs(m.mealTime) < endMs)
          m,
    ];
    days.add(
      DayStats(
        day: DateTime(start.year, start.month, start.day),
        totals: NutritionCalculator.total(ofDay.map((m) => m.totals)),
        hasMeals: ofDay.isNotEmpty,
      ),
    );
  }

  final logged = [
    for (final d in days)
      if (d.hasMeals) d,
  ];
  final sum = NutritionCalculator.total(logged.map((d) => d.totals));
  final n = logged.length;
  final average = n == 0
      ? Nutrition.zero
      : Nutrition(
          kcal: sum.kcal / n,
          protein: sum.protein / n,
          fat: sum.fat / n,
          carbs: sum.carbs / n,
        );
  final onTarget = kcalTarget == null
      ? 0
      : logged
            .where(
              (d) =>
                  (d.totals.kcal - kcalTarget).abs() <=
                  kcalTarget * adherenceTolerance + 1e-9,
            )
            .length;
  return WeekStats(
    days: days,
    average: average,
    loggedDays: n,
    onTargetDays: onTarget,
    today: days.last.totals,
    kcalTarget: kcalTarget,
  );
}
