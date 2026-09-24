import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/domain/nutrition.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/ids.dart';
import '../domain/meal.dart';
import '../domain/meal_draft.dart';
import '../domain/meal_repository.dart';
import '../domain/nutrition_calculator.dart';
import '../domain/portion_calibration.dart';

/// Meals over Drift/SQLite. Writes run in one transaction each, so a failure
/// leaves previously stored data unchanged.
class DriftMealRepository implements MealRepository {
  DriftMealRepository(
    this._db, {
    this._ids = const IdGenerator(),
    Clock? clock,
    this._zone = const TimeZoneRules(),
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final IdGenerator _ids;
  final Clock _clock;
  final TimeZoneRules _zone;

  @override
  Stream<List<Meal>> watchDay(DateTime day) {
    final range = TimeRange.day(day, zone: _zone);
    final query = _db.select(_db.meals)
      ..where(
        (m) =>
            m.mealTime.isBiggerOrEqualValue(range.startMs) &
            m.mealTime.isSmallerThanValue(range.endMs),
      )
      ..orderBy([
        (m) => OrderingTerm.asc(m.mealTime),
        (m) => OrderingTerm.asc(m.id),
      ]);
    return query.watch().map(
      (rows) => [for (final r in rows) _toMeal(r, const [])],
    );
  }

  @override
  Stream<List<Meal>> watchRange(DateTime start, DateTime end) {
    final query = _db.select(_db.meals)
      ..where(
        (m) =>
            m.mealTime.isBiggerOrEqualValue(_zone.toEpochMs(start)) &
            m.mealTime.isSmallerThanValue(_zone.toEpochMs(end)),
      )
      ..orderBy([
        (m) => OrderingTerm.asc(m.mealTime),
        (m) => OrderingTerm.asc(m.id),
      ]);
    return query.watch().map(
      (rows) => [for (final r in rows) _toMeal(r, const [])],
    );
  }

  @override
  Stream<Set<int>> watchDaysWithMeals(DateTime month) {
    final range = TimeRange.month(month, zone: _zone);
    final query = _db.selectOnly(_db.meals)
      ..addColumns([_db.meals.mealTime])
      ..where(
        _db.meals.mealTime.isBiggerOrEqualValue(range.startMs) &
            _db.meals.mealTime.isSmallerThanValue(range.endMs),
      );
    return query.watch().map(
      (rows) => {
        for (final r in rows)
          _zone.fromEpochMs(r.read(_db.meals.mealTime)!).day,
      },
    );
  }

  @override
  Future<List<Meal>> mealsWithItems({DateTime? start, DateTime? end}) async {
    final query = _db.select(_db.meals);
    if (start != null || end != null) {
      query.where((m) {
        Expression<bool> cond = const Constant(true);
        if (start != null) {
          cond = cond & m.mealTime.isBiggerOrEqualValue(_zone.toEpochMs(start));
        }
        if (end != null) {
          cond = cond & m.mealTime.isSmallerThanValue(_zone.toEpochMs(end));
        }
        return cond;
      });
    }
    query.orderBy([
      (m) => OrderingTerm.asc(m.mealTime),
      (m) => OrderingTerm.asc(m.id),
    ]);
    final meals = await query.get();
    if (meals.isEmpty) return const [];

    final itemRows =
        await (_db.select(_db.mealItems)
              ..where((i) => i.mealId.isIn(meals.map((m) => m.id)))
              ..orderBy([
                (i) => OrderingTerm.asc(i.createdAt),
                (i) => OrderingTerm.asc(i.id),
              ]))
            .get();
    final corrected = await _correctedIds(itemRows.map((i) => i.id));
    final byMeal = <String, List<MealItem>>{};
    for (final row in itemRows) {
      byMeal
          .putIfAbsent(row.mealId, () => [])
          .add(_toItem(row, corrected.contains(row.id)));
    }
    return [for (final m in meals) _toMeal(m, byMeal[m.id] ?? const [])];
  }

  @override
  Future<Meal?> getMeal(String id) async {
    final row = await (_db.select(
      _db.meals,
    )..where((m) => m.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    final items =
        await (_db.select(_db.mealItems)
              ..where((i) => i.mealId.equals(id))
              ..orderBy([
                (i) => OrderingTerm.asc(i.createdAt),
                (i) => OrderingTerm.asc(i.id),
              ]))
            .get();
    final corrected = await _correctedIds(items.map((i) => i.id));
    return _toMeal(row, [
      for (final i in items) _toItem(i, corrected.contains(i.id)),
    ]);
  }

  Future<Set<String>> _correctedIds(Iterable<String> itemIds) async {
    final ids = itemIds.toList();
    if (ids.isEmpty) return const {};
    final rows = await (_db.select(
      _db.aiCorrections,
    )..where((c) => c.id.isIn(ids))).get();
    return {for (final r in rows) r.id};
  }

  /// Rows scanned for learning; older corrections no longer influence the
  /// moving average anyway.
  static const int _maxCorrectionSamples = 1000;

  @override
  Future<List<CorrectionSample>> correctionSamples() async {
    final rows =
        await (_db.select(_db.aiCorrections)
              ..orderBy([
                (c) => OrderingTerm.desc(c.createdAt),
                (c) => OrderingTerm.desc(c.id),
              ])
              ..limit(_maxCorrectionSamples))
            .get();
    if (rows.isEmpty) return const [];

    // Foods are looked up by name once, not per row. A catalog row wins over
    // a cached AI estimate, as everywhere else.
    final names = {for (final r in rows) r.normalizedFoodName}.toList();
    final foodRows = await (_db.select(
      _db.foods,
    )..where((f) => f.normalizedName.isIn(names))).get();
    final categories = <String, PortionCategory>{};
    for (final f in foodRows..sort(_catalogFirst)) {
      categories.putIfAbsent(
        f.normalizedName!,
        () => PortionCategory.of(
          Nutrition(
            kcal: f.kcalPer100g,
            protein: f.proteinPer100g,
            fat: f.fatPer100g,
            carbs: f.carbsPer100g,
          ),
        ),
      );
    }
    return [
      for (final r in rows.reversed)
        CorrectionSample(
          normalizedName: r.normalizedFoodName,
          aiWeightG: r.aiWeightG,
          userWeightG: r.userWeightG,
          createdAtMs: r.createdAt,
          category: categories[r.normalizedFoodName],
        ),
    ];
  }

  static int _catalogFirst(FoodRow a, FoodRow b) =>
      (a.source == NutritionSourceName.catalog ? 0 : 1).compareTo(
        b.source == NutritionSourceName.catalog ? 0 : 1,
      );

  @override
  Future<String> save(MealDraft draft, {String? photoPath}) async {
    final mealId = draft.editingMealId ?? _ids.newId();
    final nowMs = _clock().toUtc().millisecondsSinceEpoch;
    final items = [
      for (final it in draft.items)
        _ItemToWrite(
          id: it.id,
          name: it.name,
          estimatedWeightG: it.estimatedWeightG,
          weightG: it.weightG,
          per100: it.per100,
          confidence: it.confidence,
          source: it.source,
          wasCorrected: it.wasCorrected,
          weightCorrected: it.weightCorrected,
          foodId: it.foodId,
          nutritionSource: it.nutritionSource,
          normalizedName: it.normalizedName,
        ),
    ];
    await _write(
      mealId: mealId,
      mealTimeMs: _zone.toEpochMs(draft.mealTime),
      mealType: draft.mealType,
      photoPath: photoPath ?? draft.photoPath,
      createdAtMs: draft.createdAt?.toUtc().millisecondsSinceEpoch,
      nowMs: nowMs,
      items: items,
    );
    return mealId;
  }

  @override
  Future<Meal?> delete(String id) async {
    final snapshot = await getMeal(id);
    if (snapshot == null) return null;
    await _db.transaction(() async {
      // Items are removed by the foreign key cascade.
      for (final item in snapshot.items) {
        await (_db.delete(
          _db.aiCorrections,
        )..where((c) => c.id.equals(item.id))).go();
      }
      await (_db.delete(_db.meals)..where((m) => m.id.equals(id))).go();
    });
    return snapshot;
  }

  @override
  Future<void> restore(Meal snapshot) => _write(
    mealId: snapshot.id,
    mealTimeMs: _zone.toEpochMs(snapshot.mealTime),
    mealType: snapshot.mealType,
    photoPath: snapshot.photoPath,
    createdAtMs: snapshot.createdAt.toUtc().millisecondsSinceEpoch,
    nowMs: snapshot.updatedAt.toUtc().millisecondsSinceEpoch,
    items: [
      for (final it in snapshot.items)
        _ItemToWrite(
          id: it.id,
          name: it.name,
          estimatedWeightG: it.estimatedWeightG,
          weightG: it.weightG,
          per100: it.per100,
          confidence: it.confidence,
          source: it.recognitionSource,
          wasCorrected: it.wasCorrected,
          weightCorrected: it.weightCorrected,
          foodId: it.foodId,
          createdAtMs: it.createdAt.toUtc().millisecondsSinceEpoch,
        ),
    ],
  );

  /// The shared transactional write behind [save] and [restore]: meal row,
  /// replaced items, recomputed totals, corrections and the food cache.
  Future<void> _write({
    required String mealId,
    required int mealTimeMs,
    required MealType? mealType,
    required String? photoPath,
    required int? createdAtMs,
    required int nowMs,
    required List<_ItemToWrite> items,
  }) => _db.transaction(() async {
    final existingMeal = await (_db.select(
      _db.meals,
    )..where((m) => m.id.equals(mealId))).getSingleOrNull();
    final oldItems = {
      for (final row in await (_db.select(
        _db.mealItems,
      )..where((i) => i.mealId.equals(mealId))).get())
        row.id: row,
    };

    final totals = NutritionCalculator.total(
      items.map((i) => NutritionCalculator.forWeight(i.weightG, i.per100)),
    );
    await _db
        .into(_db.meals)
        .insertOnConflictUpdate(
          MealsCompanion(
            id: Value(mealId),
            mealTime: Value(mealTimeMs),
            mealType: Value(mealType?.name),
            photoPath: Value(photoPath),
            totalKcal: Value(totals.kcal),
            totalProtein: Value(totals.protein),
            totalFat: Value(totals.fat),
            totalCarbs: Value(totals.carbs),
            createdAt: Value(existingMeal?.createdAt ?? createdAtMs ?? nowMs),
            updatedAt: Value(nowMs),
          ),
        );

    await (_db.delete(
      _db.mealItems,
    )..where((i) => i.mealId.equals(mealId))).go();
    for (final removed in oldItems.keys.where(
      (id) => !items.any((i) => i.id == id),
    )) {
      await (_db.delete(
        _db.aiCorrections,
      )..where((c) => c.id.equals(removed))).go();
    }

    for (final item in items) {
      final foodId = await _resolveFoodId(item, nowMs);
      final values = NutritionCalculator.forWeight(item.weightG, item.per100);
      await _db
          .into(_db.mealItems)
          .insert(
            MealItemsCompanion.insert(
              id: item.id,
              mealId: mealId,
              foodId: Value(foodId),
              name: item.name,
              estimatedWeightG: Value(item.estimatedWeightG),
              weightG: item.weightG,
              kcalPer100g: Value(item.per100.kcal),
              proteinPer100g: Value(item.per100.protein),
              fatPer100g: Value(item.per100.fat),
              carbsPer100g: Value(item.per100.carbs),
              kcal: Value(values.kcal),
              protein: Value(values.protein),
              fat: Value(values.fat),
              carbs: Value(values.carbs),
              confidence: Value(item.confidence),
              recognitionSource: Value(item.source?.name),
              wasCorrected: Value(item.wasCorrected),
              createdAt:
                  item.createdAtMs ?? oldItems[item.id]?.createdAt ?? nowMs,
              updatedAt: nowMs,
            ),
          );
      await _syncCorrection(item, foodId, nowMs);
    }
  });

  /// Exactly one correction row per corrected AI item, keyed by the item id.
  Future<void> _syncCorrection(
    _ItemToWrite item,
    String? foodId,
    int nowMs,
  ) async {
    final estimate = item.estimatedWeightG;
    if (!item.weightCorrected || estimate == null) {
      await (_db.delete(
        _db.aiCorrections,
      )..where((c) => c.id.equals(item.id))).go();
      return;
    }
    final previous = await (_db.select(
      _db.aiCorrections,
    )..where((c) => c.id.equals(item.id))).getSingleOrNull();
    final normalized =
        item.normalizedName ??
        previous?.normalizedFoodName ??
        await _normalizedNameOf(foodId) ??
        item.name.toLowerCase().trim().split(RegExp(r'\s+')).join('_');
    await _db
        .into(_db.aiCorrections)
        .insertOnConflictUpdate(
          AiCorrectionsCompanion(
            id: Value(item.id),
            normalizedFoodName: Value(normalized),
            aiWeightG: Value(estimate),
            userWeightG: Value(item.weightG),
            createdAt: Value(previous?.createdAt ?? nowMs),
          ),
        );
  }

  Future<String?> _normalizedNameOf(String? foodId) async {
    if (foodId == null) return null;
    final row = await (_db.select(
      _db.foods,
    )..where((f) => f.id.equals(foodId))).getSingleOrNull();
    return row?.normalizedName;
  }

  /// Links an AI item to its cached food. Catalog rows are only looked up;
  /// `ai_estimate` rows are created or overwritten by the newest save.
  Future<String?> _resolveFoodId(_ItemToWrite item, int nowMs) async {
    if (item.source != RecognitionSource.ai) return item.foodId;
    final key = item.normalizedName;
    if (key == null) return item.foodId;

    if (item.nutritionSource == NutritionSourceName.catalog) {
      final row =
          await (_db.select(_db.foods)..where(
                (f) =>
                    f.source.equals(NutritionSourceName.catalog) &
                    f.sourceId.equals(key),
              ))
              .getSingleOrNull();
      return row?.id ?? item.foodId;
    }
    if (item.nutritionSource != NutritionSourceName.aiEstimate) {
      return item.foodId;
    }

    final existing =
        await (_db.select(_db.foods)..where(
              (f) =>
                  f.source.equals(NutritionSourceName.aiEstimate) &
                  f.normalizedName.equals(key),
            ))
            .getSingleOrNull();
    final id = existing?.id ?? _ids.newId();
    await _db
        .into(_db.foods)
        .insertOnConflictUpdate(
          FoodsCompanion(
            id: Value(id),
            name: Value(item.name),
            normalizedName: Value(key),
            kcalPer100g: Value(item.per100.kcal),
            proteinPer100g: Value(item.per100.protein),
            fatPer100g: Value(item.per100.fat),
            carbsPer100g: Value(item.per100.carbs),
            source: const Value(NutritionSourceName.aiEstimate),
            sourceId: Value(key),
            updatedAt: Value(nowMs),
          ),
        );
    return id;
  }

  Meal _toMeal(MealRow r, List<MealItem> items) => Meal(
    id: r.id,
    mealTime: _zone.fromEpochMs(r.mealTime),
    mealType: MealType.fromName(r.mealType),
    photoPath: r.photoPath,
    totals: Nutrition(
      kcal: r.totalKcal,
      protein: r.totalProtein,
      fat: r.totalFat,
      carbs: r.totalCarbs,
    ),
    items: items,
    createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(r.updatedAt),
  );

  MealItem _toItem(MealItemRow r, bool weightCorrected) => MealItem(
    id: r.id,
    mealId: r.mealId,
    foodId: r.foodId,
    name: r.name,
    estimatedWeightG: r.estimatedWeightG,
    weightG: r.weightG,
    per100: Nutrition(
      kcal: r.kcalPer100g,
      protein: r.proteinPer100g,
      fat: r.fatPer100g,
      carbs: r.carbsPer100g,
    ),
    confidence: r.confidence,
    recognitionSource: RecognitionSource.fromName(r.recognitionSource),
    wasCorrected: r.wasCorrected,
    weightCorrected: weightCorrected,
    createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(r.updatedAt),
  );
}

/// Persistence view of an item, shared by save and restore.
class _ItemToWrite {
  const _ItemToWrite({
    required this.id,
    required this.name,
    required this.weightG,
    required this.per100,
    required this.source,
    required this.wasCorrected,
    required this.weightCorrected,
    this.estimatedWeightG,
    this.confidence,
    this.foodId,
    this.nutritionSource,
    this.normalizedName,
    this.createdAtMs,
  });

  final String id;
  final String name;
  final double? estimatedWeightG;
  final double weightG;
  final Nutrition per100;
  final double? confidence;
  final RecognitionSource? source;
  final bool wasCorrected;
  final bool weightCorrected;
  final String? foodId;
  final String? nutritionSource;
  final String? normalizedName;
  final int? createdAtMs;
}
