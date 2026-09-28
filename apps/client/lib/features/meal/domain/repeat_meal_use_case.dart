import '../../../core/utils/clock.dart';
import '../../../core/utils/ids.dart';
import '../../balanced_plate/domain/plate_group.dart';
import '../../foods/domain/food.dart';
import '../../foods/domain/food_repository.dart';
import 'meal.dart';
import 'meal_draft.dart';
import 'meal_repository.dart';

/// Recent meals are offered for repeat only within this many days.
const int repeatMealLookbackDays = 30;

/// At most this many recent meals are offered for repeat.
const int repeatMealMaxResults = 50;

/// Why a repeat could not be started.
enum RepeatMealFailure {
  /// The source meal no longer exists.
  notFound,

  /// The source meal has no items, or an item has no usable positive weight.
  unusable,
}

class RepeatMealException implements Exception {
  const RepeatMealException(this.failure);

  final RepeatMealFailure failure;

  @override
  String toString() => 'RepeatMealException(${failure.name})';
}

/// Clones a saved meal into a new, unsaved [MealDraft]: the current time,
/// the source's items and meal type, no photo, and no AI provenance. Reads
/// local data only; makes no network, AI, barcode or Open Food Facts call.
class RepeatMealUseCase {
  RepeatMealUseCase({
    required this._meals,
    required this._foods,
    required this._ids,
    required this._clock,
  });

  final MealRepository _meals;
  final FoodRepository _foods;
  final IdGenerator _ids;
  final Clock _clock;

  /// The start of the recent-meals lookback window for [now].
  DateTime recentSince(DateTime now) => addDays(now, -repeatMealLookbackDays);

  Future<MealDraft> call(String sourceMealId, {DateTime? now}) async {
    final meal = await _meals.getMeal(sourceMealId);
    if (meal == null) {
      throw const RepeatMealException(RepeatMealFailure.notFound);
    }
    if (meal.items.isEmpty ||
        meal.items.any((it) => !it.weightG.isFinite || it.weightG <= 0)) {
      throw const RepeatMealException(RepeatMealFailure.unusable);
    }

    final effectiveNow = now ?? _clock();
    final items = <DraftItem>[];
    for (final source in meal.items) {
      final food = source.foodId == null
          ? null
          : await _foods.getById(source.foodId!);
      items.add(
        DraftItem(
          id: _ids.newId(),
          // NOTE: repeated items are always `manual`, never `ai`: the copied
          // weight is a value the user already confirmed, not a new estimate.
          // This keeps them out of correction learning and personalization by
          // construction, without a special case in the save path.
          source: RecognitionSource.manual,
          name: source.name,
          originalName: source.name,
          weightG: source.weightG,
          per100: source.per100,
          originalPer100: source.per100,
          // A missing food row drops the link; the item stays editable from
          // its own snapshot (spec: degraded and stale sources).
          foodId: food?.id,
          nutritionSource: food?.source,
          normalizedName: food?.normalizedName,
          units: _unitsOf(food),
          plateGroup: food?.plateGroup ?? PlateGroup.unknown,
          plateQuality: food?.plateQuality,
        ),
      );
    }

    return MealDraft(
      mealTime: effectiveNow,
      // NOTE: a source without a meal type falls back to the time-based
      // default, which is more useful for a new entry than `other`.
      mealType: meal.mealType ?? defaultMealType(effectiveNow),
      items: items,
      repeatedFromMealId: meal.id,
    );
  }

  static FoodUnits? _unitsOf(Food? food) {
    if (food == null) return null;
    if (food.gramsPerPiece == null &&
        food.gramsPerPortion == null &&
        food.densityGPerMl == null) {
      return null;
    }
    return FoodUnits(
      gramsPerPiece: food.gramsPerPiece,
      gramsPerPortion: food.gramsPerPortion,
      densityGPerMl: food.densityGPerMl,
    );
  }
}
