import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/utils/clock.dart';
import '../../meal/domain/meal.dart';

/// The day shown on the diary screen (local date, never in the future).
class SelectedDayNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => dateOnly(ref.read(clockProvider)());

  DateTime get _today => dateOnly(ref.read(clockProvider)());

  bool get isToday => state == _today;

  void select(DateTime day) {
    final d = dateOnly(day);
    state = d.isAfter(_today) ? _today : d;
  }

  void previous() => state = addDays(state, -1);

  void next() {
    if (state.isBefore(_today)) state = addDays(state, 1);
  }

  void goToToday() => state = _today;
}

final selectedDayProvider = NotifierProvider<SelectedDayNotifier, DateTime>(
  SelectedDayNotifier.new,
);

/// Meals of a day; updates immediately after saves, edits and deletions.
final dayMealsProvider = StreamProvider.autoDispose
    .family<List<Meal>, DateTime>(
      (ref, day) => ref.watch(mealRepositoryProvider).watchDay(day),
    );

/// Days of a month that have at least one meal.
final monthDaysProvider = StreamProvider.autoDispose.family<Set<int>, DateTime>(
  (ref, month) => ref.watch(mealRepositoryProvider).watchDaysWithMeals(month),
);
