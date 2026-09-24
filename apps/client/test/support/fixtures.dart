import 'dart:io';

import 'package:calsnap/core/database/app_database.dart';
import 'package:calsnap/core/domain/nutrition.dart';
import 'package:calsnap/core/utils/clock.dart';
import 'package:calsnap/features/foods/data/drift_food_repository.dart';
import 'package:calsnap/features/meal/data/drift_meal_repository.dart';
import 'package:calsnap/features/meal/domain/meal.dart';
import 'package:calsnap/features/meal/domain/meal_draft.dart';
import 'package:calsnap/features/settings/data/drift_settings_repository.dart';
import 'package:drift/native.dart';

/// Directory of the shared cross-language protocol fixtures.
final Directory protocolDir = Directory('../../protocol');

File protocolFile(String relative) => File('${protocolDir.path}/$relative');

String readCatalogJson() =>
    File('assets/catalog/foods.json').readAsStringSync();

/// An in-memory database with the production migration strategy.
AppDatabase createTestDatabase() => AppDatabase(NativeDatabase.memory());

/// A fixed-offset time zone for day-boundary tests. Local times are UTC-flagged
/// DateTimes whose fields are already shifted by [offset].
class FixedOffsetZone extends TimeZoneRules {
  const FixedOffsetZone(this.offset);

  final Duration offset;

  @override
  DateTime startOfDay(int year, int month, int day) =>
      DateTime.utc(year, month, day);

  @override
  DateTime fromEpochMs(int epochMs) =>
      DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true).add(offset);

  @override
  int toEpochMs(DateTime local) =>
      local.millisecondsSinceEpoch - offset.inMilliseconds;
}

/// A controllable clock.
class TestClock {
  TestClock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration d) => now = now.add(d);
}

/// Bundles the repositories over one in-memory database.
class TestRepos {
  TestRepos({TimeZoneRules zone = const TimeZoneRules(), DateTime? start})
    : db = createTestDatabase(),
      clock = TestClock(start ?? DateTime.utc(2026, 3, 10, 12)) {
    meals = DriftMealRepository(db, clock: clock.call, zone: zone);
    foods = DriftFoodRepository(db, clock: clock.call);
    settings = DriftSettingsRepository(db);
  }

  final AppDatabase db;
  final TestClock clock;
  late final DriftMealRepository meals;
  late final DriftFoodRepository foods;
  late final DriftSettingsRepository settings;

  Future<void> close() => db.close();
}

/// A recognized (AI) draft item.
DraftItem aiItem(
  String id, {
  String name = 'Rice',
  double estimated = 170,
  double? weight,
  Nutrition per100 = const Nutrition(
    kcal: 130,
    protein: 2.7,
    fat: 0.3,
    carbs: 28,
  ),
  String normalized = 'rice',
  String nutritionSource = NutritionSourceName.catalog,
  double confidence = 0.86,
}) => DraftItem(
  id: id,
  name: name,
  weightG: weight ?? estimated,
  per100: per100,
  source: RecognitionSource.ai,
  estimatedWeightG: estimated,
  confidence: confidence,
  nutritionSource: nutritionSource,
  normalizedName: normalized,
  originalName: name,
  originalPer100: per100,
);

DraftItem manualItem(
  String id, {
  String name = 'Olive oil',
  double weight = 10,
  Nutrition per100 = const Nutrition(kcal: 884, fat: 100),
}) => DraftItem.manual(id: id, name: name, weightG: weight, per100: per100);

MealDraft draftOf(
  List<DraftItem> items, {
  DateTime? time,
  MealType type = MealType.lunch,
  String? editing,
  DateTime? createdAt,
}) => MealDraft(
  mealTime: time ?? DateTime.utc(2026, 3, 10, 12),
  mealType: type,
  items: items,
  editingMealId: editing,
  createdAt: createdAt,
);
