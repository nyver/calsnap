import 'package:calsnap/core/database/app_database.dart';
import 'package:calsnap/core/domain/nutrition.dart';
import 'package:calsnap/core/utils/ids.dart';
import 'package:calsnap/features/balanced_plate/domain/plate_group.dart';
import 'package:calsnap/features/meal/domain/meal.dart';
import 'package:calsnap/features/meal/domain/meal_draft.dart';
import 'package:calsnap/features/meal/domain/meal_repository.dart';
import 'package:calsnap/features/meal/domain/repeat_meal_use_case.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

/// Deterministic, collision-free ids, in call order.
class _SeqIds extends IdGenerator {
  const _SeqIds();

  static int _next = 0;

  @override
  String newId() => 'gen-${_next++}';
}

/// A single canned meal, for a case that cannot round-trip through the real
/// (SQLite-backed) repository: a NaN weight is rejected by the NOT NULL
/// column it would be stored in, so the source has to be faked instead.
class _FakeMeals implements MealRepository {
  const _FakeMeals(this.meal);

  final Meal? meal;

  @override
  Future<Meal?> getMeal(String id) async => meal;

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late TestRepos r;
  late RepeatMealUseCase useCase;
  // Local (non-UTC), matching the real `clockProvider`; only this use case's
  // own clock, not the repository's save-time clock, so it can differ freely
  // from the UTC-flagged times `draftOf` uses for stored meals.
  final now = DateTime(2026, 3, 15, 18, 30);

  setUp(() {
    r = TestRepos();
    useCase = RepeatMealUseCase(
      meals: r.meals,
      foods: r.foods,
      ids: const _SeqIds(),
      clock: () => now,
    );
  });
  tearDown(() => r.close());

  test('a missing source meal throws notFound', () async {
    await expectLater(
      useCase('missing'),
      throwsA(
        isA<RepeatMealException>().having(
          (e) => e.failure,
          'failure',
          RepeatMealFailure.notFound,
        ),
      ),
    );
  });

  test('a source with no items throws unusable', () async {
    final id = await r.meals.save(draftOf(const []));
    await expectLater(
      useCase(id),
      throwsA(
        isA<RepeatMealException>().having(
          (e) => e.failure,
          'failure',
          RepeatMealFailure.unusable,
        ),
      ),
    );
  });

  test('a source item with a zero weight throws unusable', () async {
    final id = await r.meals.save(draftOf([manualItem('a', weight: 0)]));
    await expectLater(
      useCase(id),
      throwsA(
        isA<RepeatMealException>().having(
          (e) => e.failure,
          'failure',
          RepeatMealFailure.unusable,
        ),
      ),
    );
  });

  test('a source item with a NaN weight throws unusable', () async {
    final now0 = DateTime.utc(2026, 3, 1);
    final fake = RepeatMealUseCase(
      meals: _FakeMeals(
        Meal(
          id: 'src',
          mealTime: now0,
          totals: const Nutrition(),
          createdAt: now0,
          updatedAt: now0,
          items: [
            MealItem(
              id: 'a',
              mealId: 'src',
              name: 'Bad item',
              weightG: double.nan,
              per100: const Nutrition(kcal: 100),
              createdAt: now0,
              updatedAt: now0,
            ),
          ],
        ),
      ),
      foods: r.foods,
      ids: const _SeqIds(),
      clock: () => now,
    );
    await expectLater(
      fake('src'),
      throwsA(
        isA<RepeatMealException>().having(
          (e) => e.failure,
          'failure',
          RepeatMealFailure.unusable,
        ),
      ),
    );
  });

  group('with the catalog seeded', () {
    setUp(() => r.foods.seedCatalog(readCatalogJson()));

    test('copies every item, in order, from the final saved state', () async {
      final sourceId = await r.meals.save(
        draftOf([
          aiItem('a', estimated: 180, weight: 240),
          manualItem('b', name: 'Olive oil', weight: 12),
        ]),
      );
      final source = (await r.meals.getMeal(sourceId))!;

      final draft = await useCase(sourceId);

      expect(draft.items, hasLength(2));
      expect(draft.items[0].name, source.items[0].name);
      expect(draft.items[0].weightG, 240);
      expect(draft.items[0].per100, source.items[0].per100);
      expect(draft.items[0].foodId, isNotNull);
      expect(draft.items[1].name, 'Olive oil');
      expect(draft.items[1].weightG, 12);
    });

    test('mealTime is the injected now', () async {
      final sourceId = await r.meals.save(draftOf([aiItem('a')]));
      final draft = await useCase(sourceId);
      expect(draft.mealTime, now);
    });

    test('the source meal type is preserved', () async {
      final sourceId = await r.meals.save(
        draftOf([aiItem('a')], type: MealType.dinner),
      );
      final draft = await useCase(sourceId);
      expect(draft.mealType, MealType.dinner);
    });

    test(
      'a source without a meal type falls back to the time default',
      () async {
        final sourceId = await r.meals.save(draftOf([aiItem('a')]));
        await (r.db.update(r.db.meals)..where((m) => m.id.equals(sourceId)))
            .write(const MealsCompanion(mealType: Value(null)));

        final draft = await useCase(sourceId);
        expect(draft.mealType, defaultMealType(now));
      },
    );

    test('the draft has no photo', () async {
      final sourceId = await r.meals.save(
        draftOf([aiItem('a')]),
        photoPath: 'meals/2026/03/10/p.jpg',
      );
      final draft = await useCase(sourceId);
      expect(draft.photoPath, isNull);
      expect(draft.tempPhotoFile, isNull);
    });

    test('the source meal is unchanged after the call', () async {
      final sourceId = await r.meals.save(draftOf([aiItem('a', weight: 200)]));
      final before = (await r.meals.getMeal(sourceId))!;
      await useCase(sourceId);
      final after = (await r.meals.getMeal(sourceId))!;
      expect(after.items.single.weightG, before.items.single.weightG);
      expect(after.updatedAt, before.updatedAt);
    });

    test('the final saved weight is used, not the AI estimate', () async {
      // The AI estimated 190 g; a personalization proposal of 247 g was shown,
      // but the user saved 250 g.
      final sourceId = await r.meals.save(
        draftOf([aiItem('a', estimated: 190, weight: 250)]),
      );
      final draft = await useCase(sourceId);
      final item = draft.items.single;
      expect(item.weightG, 250);
      expect(item.suggestedWeightG, isNull);
      expect(item.adjustment, isNull);
    });

    test('items are manual, with no estimate or confidence', () async {
      final sourceId = await r.meals.save(
        draftOf([aiItem('a', estimated: 190, weight: 250)]),
      );
      final item = (await useCase(sourceId)).items.single;
      expect(item.source, RecognitionSource.manual);
      expect(item.estimatedWeightG, isNull);
      expect(item.confidence, isNull);
    });

    test('nutritionSource and plateGroup follow the local food', () async {
      final sourceId = await r.meals.save(draftOf([aiItem('a')]));
      final item = (await useCase(sourceId)).items.single;
      expect(item.nutritionSource, NutritionSourceName.catalog);
      expect(item.plateGroup, PlateGroup.complexCarbohydrate);
    });

    test('a missing food row keeps the snapshot with no link and an unknown plate group', () async {
      const ghostFoodId = 'gen-does-not-exist';
      final sourceId = await r.meals.save(
        draftOf([
          DraftItem.manual(
            id: 'src-1',
            name: 'Ghost product',
            weightG: 50,
            per100: const Nutrition(kcal: 200, protein: 5, fat: 5, carbs: 20),
            foodId: ghostFoodId,
          ),
        ]),
      );

      final item = (await useCase(sourceId)).items.single;
      expect(item.name, 'Ghost product');
      expect(item.weightG, 50);
      expect(item.foodId, isNull);
      expect(item.plateGroup, PlateGroup.unknown);
    });

    test('new meal and item ids, none equal to the source ids', () async {
      final sourceId = await r.meals.save(
        draftOf([aiItem('a'), manualItem('b')]),
      );
      final source = (await r.meals.getMeal(sourceId))!;
      final sourceItemIds = source.items.map((i) => i.id).toSet();

      final draft = await useCase(sourceId);

      expect(draft.editingMealId, isNull);
      for (final item in draft.items) {
        expect(sourceItemIds.contains(item.id), isFalse);
      }
      expect(draft.items.map((i) => i.id).toSet(), hasLength(2));
    });

    test('draft totals equal the source totals', () async {
      final sourceId = await r.meals.save(
        draftOf([
          aiItem('a', estimated: 180, weight: 240),
          manualItem('b', weight: 12),
        ]),
      );
      final source = (await r.meals.getMeal(sourceId))!;
      final draft = await useCase(sourceId);
      expect(draft.totals.kcal, closeTo(source.totals.kcal, 1e-9));
      expect(draft.totals.protein, closeTo(source.totals.protein, 1e-9));
      expect(draft.totals.fat, closeTo(source.totals.fat, 1e-9));
      expect(draft.totals.carbs, closeTo(source.totals.carbs, 1e-9));
    });
  });

  group('recentSince', () {
    test('is the calendar day 30 days before now', () {
      expect(useCase.recentSince(now), DateTime(2026, 2, 13));
    });
  });
}
