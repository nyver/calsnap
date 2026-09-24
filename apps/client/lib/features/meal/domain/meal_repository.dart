import 'meal.dart';
import 'meal_draft.dart';
import 'portion_calibration.dart';

/// Access to saved meals. Every write is a single transaction.
abstract interface class MealRepository {
  /// Meals of the local calendar day containing [day], ordered by time.
  /// The lists carry no items.
  Stream<List<Meal>> watchDay(DateTime day);

  /// Local calendar days (day of month) of the month containing [month] that
  /// have at least one meal.
  Stream<Set<int>> watchDaysWithMeals(DateTime month);

  /// Meals in [start, end) (local times), ordered by time, without items.
  Stream<List<Meal>> watchRange(DateTime start, DateTime end);

  /// Meals in [start, end) (local times), each with its items.
  Future<List<Meal>> mealsWithItems({DateTime? start, DateTime? end});

  Future<Meal?> getMeal(String id);

  /// Creates or replaces a meal from [draft]: writes the meal row, replaces its
  /// items, recomputes totals, upserts or deletes correction records and caches
  /// recognized foods. [photoPath] is the relative path of the stored photo.
  /// Returns the id of the meal.
  Future<String> save(MealDraft draft, {String? photoPath});

  /// Deletes the meal with its items and returns a snapshot for undo.
  Future<Meal?> delete(String id);

  /// Re-creates a deleted meal from its snapshot.
  Future<void> restore(Meal snapshot);

  /// The most recent weight corrections, oldest first, for learning portion
  /// factors. Bounded, so the cost stays flat as the diary grows.
  Future<List<CorrectionSample>> correctionSamples();
}
