import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../core/utils/formatters.dart';
import '../features/meal/domain/meal.dart';
import '../l10n/app_localizations.dart';

extension BuildContextL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// Number formatter for the active locale.
  NutritionFormatter get fmt =>
      NutritionFormatter(Localizations.localeOf(this).toString());

  String get localeName => Localizations.localeOf(this).toString();
}

extension MealTypeL10n on AppLocalizations {
  String mealTypeLabel(MealType? type) => switch (type) {
    MealType.breakfast => mealBreakfast,
    MealType.lunch => mealLunch,
    MealType.dinner => mealDinner,
    MealType.snack => mealSnack,
    MealType.other => mealOther,
    null => mealUnnamed,
  };
}

/// "Today", "Yesterday" or a localized full date.
String dayLabel(BuildContext context, DateTime day, DateTime today) {
  final l10n = context.l10n;
  final d = DateTime(day.year, day.month, day.day);
  final t = DateTime(today.year, today.month, today.day);
  final diff = t.difference(d).inDays;
  if (diff == 0) return l10n.today;
  if (diff == 1) return l10n.yesterday;
  return DateFormat.MMMMEEEEd(context.localeName).format(d);
}

String timeLabel(BuildContext context, DateTime time) =>
    DateFormat.Hm(context.localeName).format(time);
