import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/di/providers.dart';
import '../../../core/domain/nutrition.dart';
import '../../foods/domain/food.dart';
import '../../recognition/domain/analysis.dart';
import '../domain/meal.dart';
import '../domain/meal_draft.dart';
import '../domain/portion_calibration.dart';

/// Holds the meal that is being built or edited. One draft exists at a time:
/// the recognition result, a manual entry or a saved meal opened for editing.
/// It survives in-app navigation but not process death.
final _log = Logger('MealDraft');

class MealDraftNotifier extends Notifier<MealDraft?> {
  MealDraft? _initial;

  @override
  MealDraft? build() => null;

  DateTime _now() => ref.read(clockProvider)();

  /// Starts a draft from a successful analysis. Unit data (pieces, portions,
  /// density) is looked up in the local food cache. Unless the user turned it
  /// off, the proposed weights are adjusted to their past corrections; the raw
  /// AI estimate is kept on each item.
  Future<void> startFromRecognition(
    AnalysisResult result, {
    String? tempPhotoFile,
  }) async {
    final ids = ref.read(idsProvider);
    final foods = ref.read(foodRepositoryProvider);
    final calibration = await _loadCalibration();
    final items = <DraftItem>[];
    for (final it in result.items) {
      final food = await foods.findByNormalizedName(it.normalizedName);
      var adjustment = calibration?.adjustmentFor(
        normalizedName: it.normalizedName,
        per100: it.per100,
      );
      var proposed = adjustment?.apply(it.estimatedWeightG);
      if (proposed == it.estimatedWeightG) {
        // Rounding on a tiny portion can cancel the factor out.
        adjustment = null;
        proposed = null;
      }
      items.add(
        DraftItem(
          id: ids.newId(),
          foodId: food?.id,
          name: it.name,
          weightG: proposed ?? it.estimatedWeightG,
          suggestedWeightG: proposed,
          adjustment: adjustment,
          per100: it.per100,
          source: RecognitionSource.ai,
          estimatedWeightG: it.estimatedWeightG,
          confidence: it.confidence,
          nutritionSource: it.nutritionSource,
          normalizedName: it.normalizedName,
          originalName: it.name,
          originalPer100: it.per100,
          units: _unitsOf(food),
        ),
      );
    }
    final now = _now();
    _setInitial(
      MealDraft(
        mealTime: now,
        mealType: defaultMealType(now),
        items: items,
        tempPhotoFile: tempPhotoFile,
        warnings: result.warnings,
        fromRecognition: true,
      ),
    );
  }

  /// Null when personalization is off or fails: the draft then simply starts
  /// from the AI estimates.
  Future<PortionCalibration?> _loadCalibration() async {
    try {
      final settings = await ref.read(settingsRepositoryProvider).read();
      if (!settings.personalizePortions) return null;
      return PortionCalibration(
        await ref.read(mealRepositoryProvider).correctionSamples(),
      );
    } on Exception catch (e) {
      _log.warning('Portion personalization skipped', e);
      return null;
    }
  }

  /// Starts an empty draft for manual entry.
  void startManual() {
    final now = _now();
    _setInitial(
      MealDraft(mealTime: now, mealType: defaultMealType(now), items: const []),
    );
  }

  /// Loads a saved meal for editing. Returns false when it does not exist.
  Future<bool> startEdit(String mealId) async {
    final meal = await ref.read(mealRepositoryProvider).getMeal(mealId);
    if (meal == null) return false;
    final foods = ref.read(foodRepositoryProvider);
    final items = <DraftItem>[];
    for (final it in meal.items) {
      final food = it.foodId == null ? null : await foods.getById(it.foodId!);
      items.add(
        DraftItem(
          id: it.id,
          foodId: it.foodId,
          name: it.name,
          weightG: it.weightG,
          per100: it.per100,
          source: it.recognitionSource ?? RecognitionSource.manual,
          estimatedWeightG: it.estimatedWeightG,
          confidence: it.confidence,
          nutritionSource: food?.source,
          normalizedName: food?.normalizedName,
          originalName: it.name,
          originalPer100: it.per100,
          previouslyCorrected: it.wasCorrected,
          // A weight the user never changed is what the app proposed; only a
          // recorded correction is measured against the raw AI estimate.
          suggestedWeightG: it.weightCorrected
              ? it.estimatedWeightG
              : it.weightG,
          units: _unitsOf(food),
        ),
      );
    }
    _setInitial(
      MealDraft(
        editingMealId: meal.id,
        mealTime: meal.mealTime,
        mealType: meal.mealType ?? MealType.other,
        items: items,
        photoPath: meal.photoPath,
        createdAt: meal.createdAt,
      ),
    );
    return true;
  }

  void _setInitial(MealDraft draft) {
    _initial = draft;
    state = draft;
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

  /// True when there is something to lose: any unsaved recognition result,
  /// or a draft that differs from what was loaded.
  bool get isDirty {
    final draft = state;
    final initial = _initial;
    if (draft == null || initial == null) return false;
    if (draft.fromRecognition) return true;
    if (!draft.isEditing) return draft.items.isNotEmpty;
    if (draft.mealTime != initial.mealTime ||
        draft.mealType != initial.mealType ||
        draft.items.length != initial.items.length) {
      return true;
    }
    for (var i = 0; i < draft.items.length; i++) {
      final a = draft.items[i];
      final b = initial.items[i];
      if (a.id != b.id ||
          a.name != b.name ||
          a.weightG != b.weightG ||
          a.per100 != b.per100) {
        return true;
      }
    }
    return false;
  }

  void _update(MealDraft Function(MealDraft d) change) {
    final current = state;
    if (current != null) state = change(current);
  }

  void _mapItem(String id, DraftItem Function(DraftItem item) change) {
    _update(
      (d) => d.copyWith(
        items: [for (final it in d.items) it.id == id ? change(it) : it],
      ),
    );
  }

  void setWeight(String itemId, double grams) =>
      _mapItem(itemId, (it) => it.copyWith(weightG: grams));

  void rename(String itemId, String name) =>
      _mapItem(itemId, (it) => it.copyWith(name: name.trim()));

  void setPer100(String itemId, Nutrition per100) =>
      _mapItem(itemId, (it) => it.copyWith(per100: per100));

  /// Applies name, weight and nutrition of the item editor in one step.
  void updateItem(
    String itemId, {
    required String name,
    required double weightG,
    required Nutrition per100,
  }) => _mapItem(
    itemId,
    (it) => it.copyWith(name: name.trim(), weightG: weightG, per100: per100),
  );

  void removeItem(String itemId) => _update(
    (d) => d.copyWith(
      items: [
        for (final it in d.items)
          if (it.id != itemId) it,
      ],
    ),
  );

  /// Adds a food from search or a custom product as a manual item.
  void addFood(Food food, double weightG) {
    final languageCode = ref.read(effectiveLanguageCodeProvider);
    final id = ref.read(idsProvider).newId();
    _update(
      (d) => d.copyWith(
        items: [
          ...d.items,
          DraftItem.manual(
            id: id,
            name: food.displayName(languageCode),
            weightG: weightG,
            per100: food.per100,
            foodId: food.id,
            nutritionSource: food.source,
            normalizedName: food.normalizedName,
            units: _unitsOf(food),
          ),
        ],
      ),
    );
  }

  /// Replaces the product of an item, keeping its weight.
  void replaceFood(String itemId, Food food) {
    final languageCode = ref.read(effectiveLanguageCodeProvider);
    _mapItem(
      itemId,
      (it) => it.copyWith(
        name: food.displayName(languageCode),
        per100: food.per100,
        foodId: food.id,
        nutritionSource: food.source,
        normalizedName: food.normalizedName,
        units: _unitsOf(food) ?? const FoodUnits(),
      ),
    );
  }

  void setMealTime(DateTime time) => _update((d) => d.copyWith(mealTime: time));

  void setMealType(MealType type) => _update((d) => d.copyWith(mealType: type));

  void clear() {
    _initial = null;
    state = null;
  }
}

final mealDraftProvider = NotifierProvider<MealDraftNotifier, MealDraft?>(
  MealDraftNotifier.new,
);
