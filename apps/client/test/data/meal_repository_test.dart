import 'package:calsnap/core/database/app_database.dart';
import 'package:calsnap/core/domain/nutrition.dart';
import 'package:calsnap/core/utils/ids.dart';
import 'package:calsnap/features/barcode/domain/packaged_product.dart';
import 'package:calsnap/features/foods/domain/food.dart';
import 'package:calsnap/features/meal/data/drift_meal_repository.dart';
import 'package:calsnap/features/meal/domain/meal.dart';
import 'package:calsnap/features/meal/domain/meal_draft.dart';
import 'package:calsnap/features/meal/domain/portion_calibration.dart';
import 'package:calsnap/features/meal/domain/repeat_meal_use_case.dart';
import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

/// Counts `SELECT` statements executed through the wrapped executor, to
/// assert that a batch read stays at a fixed number of queries.
class _SelectCounter extends QueryInterceptor {
  int count = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    count++;
    return executor.runSelect(statement, args);
  }
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late TestRepos r;
  setUp(() => r = TestRepos());
  tearDown(() => r.close());

  group('save', () {
    test('stores meal, items and totals computed from the items', () async {
      final id = await r.meals.save(
        draftOf([
          aiItem('i1', estimated: 170, weight: 150),
          manualItem('i2', weight: 10),
        ]),
        photoPath: 'meals/2026/03/10/p.jpg',
      );
      final meal = (await r.meals.getMeal(id))!;

      expect(meal.mealType, MealType.lunch);
      expect(meal.photoPath, 'meals/2026/03/10/p.jpg');
      expect(meal.items.map((i) => i.id), ['i1', 'i2']);
      // 150 g * 130 + 10 g * 884 per 100 g.
      expect(meal.totals.kcal, closeTo(195 + 88.4, 1e-9));
      expect(meal.totals.fat, closeTo(0.45 + 10, 1e-9));

      final rice = meal.items.first;
      expect(rice.estimatedWeightG, 170);
      expect(rice.weightG, 150);
      expect(rice.recognitionSource, RecognitionSource.ai);
      expect(rice.wasCorrected, isTrue);
      expect(rice.confidence, 0.86);
      expect(rice.values.kcal, closeTo(195, 1e-9));
      expect(meal.items.last.recognitionSource, RecognitionSource.manual);
      expect(meal.items.last.estimatedWeightG, isNull);
    });

    test('ai_provider and ai_model stay null', () async {
      final id = await r.meals.save(draftOf([aiItem('i1')]));
      final row = await (r.db.select(
        r.db.meals,
      )..where((m) => m.id.equals(id))).getSingle();
      expect(row.aiProvider, isNull);
      expect(row.aiModel, isNull);
    });

    test('later meals get ids that sort after earlier ones', () async {
      final a = await r.meals.save(draftOf([aiItem('i1')]));
      final b = await r.meals.save(draftOf([aiItem('i2')]));
      expect(a.compareTo(b), lessThan(0));
    });

    test(
      'a failure on the third of four items rolls everything back',
      () async {
        final draft = draftOf([
          aiItem('a'),
          aiItem('b'),
          aiItem('a'), // duplicate primary key fails here
          aiItem('d'),
        ]);
        await expectLater(r.meals.save(draft), throwsA(anything));
        expect(await r.db.select(r.db.meals).get(), isEmpty);
        expect(await r.db.select(r.db.mealItems).get(), isEmpty);
        expect(await r.db.select(r.db.foods).get(), isEmpty);
      },
    );

    test('a failing edit keeps the previous items and totals', () async {
      final id = await r.meals.save(
        draftOf([
          aiItem('a'),
          aiItem('b', name: 'Tomato', normalized: 'tomato'),
        ]),
      );
      final before = (await r.meals.getMeal(id))!;

      final broken = draftOf(
        [aiItem('x', weight: 50), aiItem('y'), aiItem('x')],
        editing: id,
        createdAt: before.createdAt,
      );
      await expectLater(r.meals.save(broken), throwsA(anything));

      final after = (await r.meals.getMeal(id))!;
      expect(after.items.map((i) => i.id), ['a', 'b']);
      expect(after.totals.kcal, before.totals.kcal);
    });

    test(
      'editing replaces items, keeps created_at and updates totals',
      () async {
        final id = await r.meals.save(draftOf([aiItem('a'), manualItem('b')]));
        final first = (await r.meals.getMeal(id))!;
        r.clock.advance(const Duration(hours: 1));

        await r.meals.save(
          draftOf(
            [
              aiItem('a', weight: 100),
              manualItem('c', name: 'Bread', weight: 30),
            ],
            editing: id,
            type: MealType.dinner,
            createdAt: first.createdAt,
          ),
        );
        final edited = (await r.meals.getMeal(id))!;
        expect(edited.items.map((i) => i.id), ['a', 'c']);
        expect(edited.mealType, MealType.dinner);
        expect(edited.createdAt, first.createdAt);
        expect(edited.updatedAt.isAfter(first.updatedAt), isTrue);
        expect(edited.totals.kcal, closeTo(130 + 265.2, 1e-9));
        // The item created before keeps its creation time.
        expect(edited.items.first.createdAt, first.items.first.createdAt);
      },
    );
  });

  group('corrections', () {
    Future<List<Map<String, Object?>>> corrections() async => [
      for (final c in await r.db.select(r.db.aiCorrections).get())
        {
          'id': c.id,
          'name': c.normalizedFoodName,
          'ai': c.aiWeightG,
          'user': c.userWeightG,
        },
    ];

    test(
      'exactly one row is kept per corrected item and follows later edits',
      () async {
        final id = await r.meals.save(
          draftOf([aiItem('rice1', estimated: 170, weight: 150)]),
        );
        expect(await corrections(), [
          {'id': 'rice1', 'name': 'rice', 'ai': 170.0, 'user': 150.0},
        ]);

        final meal = (await r.meals.getMeal(id))!;
        await r.meals.save(
          draftOf(
            [aiItem('rice1', estimated: 170, weight: 140)],
            editing: id,
            createdAt: meal.createdAt,
          ),
        );
        expect(await corrections(), [
          {'id': 'rice1', 'name': 'rice', 'ai': 170.0, 'user': 140.0},
        ]);

        await r.meals.save(
          draftOf(
            [aiItem('rice1', estimated: 170, weight: 170)],
            editing: id,
            createdAt: meal.createdAt,
          ),
        );
        expect(
          await corrections(),
          isEmpty,
          reason: 'set back to the estimate',
        );
      },
    );

    test('uncorrected and manual items have no row', () async {
      await r.meals.save(draftOf([aiItem('a'), manualItem('b', weight: 99)]));
      expect(await corrections(), isEmpty);
    });

    test('removing the item or deleting the meal removes the row; undo restores it', () async {
      final id = await r.meals.save(
        draftOf([
          aiItem('a', estimated: 170, weight: 120),
          aiItem(
            'b',
            estimated: 100,
            weight: 80,
            name: 'Tomato',
            normalized: 'tomato',
          ),
        ]),
      );
      expect(await corrections(), hasLength(2));

      final meal = (await r.meals.getMeal(id))!;
      await r.meals.save(
        draftOf(
          [aiItem('a', estimated: 170, weight: 120)],
          editing: id,
          createdAt: meal.createdAt,
        ),
      );
      expect((await corrections()).single['id'], 'a');

      final snapshot = (await r.meals.delete(id))!;
      expect(await corrections(), isEmpty);

      await r.meals.restore(snapshot);
      expect((await corrections()).single, {
        'id': 'a',
        'name': 'rice',
        'ai': 170.0,
        'user': 120.0,
      });
    });
  });

  group('personalized weights', () {
    // The AI said 170 g; the app proposed 220 g from earlier corrections.
    DraftItem proposed(String id, {double? weight}) => DraftItem(
      id: id,
      name: 'Rice',
      weightG: weight ?? 220,
      per100: const Nutrition(kcal: 130, protein: 2.7, fat: 0.3, carbs: 28),
      source: RecognitionSource.ai,
      estimatedWeightG: 170,
      suggestedWeightG: 220,
      confidence: 0.86,
      nutritionSource: NutritionSourceName.catalog,
      normalizedName: 'rice',
      originalName: 'Rice',
      originalPer100: const Nutrition(
        kcal: 130,
        protein: 2.7,
        fat: 0.3,
        carbs: 28,
      ),
    );

    test(
      'accepting the proposal keeps the raw estimate and records nothing',
      () async {
        final id = await r.meals.save(draftOf([proposed('p1')]));
        final item = (await r.meals.getMeal(id))!.items.single;
        expect((item.estimatedWeightG, item.weightG), (170.0, 220.0));
        expect(item.wasCorrected, isFalse);
        expect(item.weightCorrected, isFalse);
        expect(await r.db.select(r.db.aiCorrections).get(), isEmpty);
      },
    );

    test(
      'changing the proposal records the raw estimate against the new weight',
      () async {
        await r.meals.save(draftOf([proposed('p1', weight: 200)]));
        final row = (await r.db.select(r.db.aiCorrections).get()).single;
        expect((row.aiWeightG, row.userWeightG), (170.0, 200.0));
      },
    );

    test(
      're-saving an accepted proposal does not turn it into a correction',
      () async {
        final id = await r.meals.save(draftOf([proposed('p1')]));
        final meal = (await r.meals.getMeal(id))!;
        final loaded = meal.items.single;
        // What the editor builds for a saved item that was never corrected.
        final reopened = DraftItem(
          id: loaded.id,
          name: loaded.name,
          weightG: loaded.weightG,
          per100: loaded.per100,
          source: RecognitionSource.ai,
          estimatedWeightG: loaded.estimatedWeightG,
          suggestedWeightG: loaded.weightCorrected
              ? loaded.estimatedWeightG
              : loaded.weightG,
          nutritionSource: NutritionSourceName.catalog,
          normalizedName: 'rice',
          originalName: loaded.name,
          originalPer100: loaded.per100,
        );
        await r.meals.save(
          draftOf([reopened], editing: id, createdAt: meal.createdAt),
        );
        expect(await r.db.select(r.db.aiCorrections).get(), isEmpty);

        // Now the user really changes it.
        await r.meals.save(
          draftOf(
            [reopened.copyWith(weightG: 250)],
            editing: id,
            createdAt: meal.createdAt,
          ),
        );
        final row = (await r.db.select(r.db.aiCorrections).get()).single;
        expect((row.aiWeightG, row.userWeightG), (170.0, 250.0));
      },
    );

    test('undo of a deleted meal restores an accepted proposal without a correction', () async {
      final id = await r.meals.save(draftOf([proposed('p1')]));
      final snapshot = (await r.meals.delete(id))!;
      expect(snapshot.items.single.weightCorrected, isFalse);
      await r.meals.restore(snapshot);
      expect(await r.db.select(r.db.aiCorrections).get(), isEmpty);
    });
  });

  group('correction samples', () {
    test('are ordered oldest first and carry the food category', () async {
      await r.foods.seedCatalog(readCatalogJson());
      await r.meals.save(draftOf([aiItem('a', estimated: 170, weight: 200)]));
      r.clock.advance(const Duration(hours: 1));
      await r.meals.save(
        draftOf([
          aiItem(
            'b',
            name: 'Chicken breast',
            normalized: 'chicken_breast',
            estimated: 100,
            weight: 150,
            per100: const Nutrition(kcal: 165, protein: 31, fat: 3.6),
          ),
        ]),
      );
      r.clock.advance(const Duration(hours: 1));
      await r.meals.save(
        draftOf([
          aiItem(
            'c',
            name: 'Mystery',
            normalized: 'mystery',
            estimated: 100,
            weight: 90,
          ),
        ]),
      );

      final samples = await r.meals.correctionSamples();
      expect(samples.map((s) => s.normalizedName), [
        'rice',
        'chicken_breast',
        'mystery',
      ]);
      expect(samples.map((s) => (s.aiWeightG, s.userWeightG)), [
        (170.0, 200.0),
        (100.0, 150.0),
        (100.0, 90.0),
      ]);
      expect(samples[0].category, PortionCategory.carb);
      expect(samples[1].category, PortionCategory.protein);
      expect(samples[2].category, isNull, reason: 'not a known food');
    });

    test('deleting the meal removes its samples', () async {
      final id = await r.meals.save(
        draftOf([aiItem('a', estimated: 170, weight: 200)]),
      );
      expect(await r.meals.correctionSamples(), hasLength(1));
      await r.meals.delete(id);
      expect(await r.meals.correctionSamples(), isEmpty);
    });

    test('an empty history gives an empty list', () async {
      expect(await r.meals.correctionSamples(), isEmpty);
    });
  });

  group('food cache', () {
    test(
      'ai_estimate items are cached and overwritten by the newest save',
      () async {
        const casserole = Nutrition(kcal: 180, protein: 8, fat: 9, carbs: 17);
        await r.meals.save(
          draftOf([
            aiItem(
              'c1',
              name: "Grandma's casserole",
              normalized: 'grandmas_casserole',
              nutritionSource: NutritionSourceName.aiEstimate,
              per100: casserole,
            ),
          ]),
        );
        var foods = await r.db.select(r.db.foods).get();
        expect(foods.single.source, 'ai_estimate');
        expect(foods.single.normalizedName, 'grandmas_casserole');
        expect(foods.single.kcalPer100g, 180);
        final firstId = foods.single.id;

        r.clock.advance(const Duration(days: 1));
        await r.meals.save(
          draftOf([
            aiItem(
              'c2',
              name: "Grandma's casserole",
              normalized: 'grandmas_casserole',
              nutritionSource: NutritionSourceName.aiEstimate,
              per100: casserole.copyWith(kcal: 200),
            ),
          ]),
        );
        foods = await r.db.select(r.db.foods).get();
        expect(foods, hasLength(1));
        expect(foods.single.id, firstId);
        expect(foods.single.kcalPer100g, 200);
      },
    );

    test(
      'a recognized food is found offline by a later manual search',
      () async {
        await r.meals.save(
          draftOf([
            aiItem(
              'c1',
              name: "Grandma's casserole",
              normalized: 'grandmas_casserole',
              nutritionSource: NutritionSourceName.aiEstimate,
            ),
          ]),
        );
        final found = await r.foods.search('casserole');
        expect(found.map((f) => f.name), contains("Grandma's casserole"));
      },
    );

    test('catalog items link to the seeded row and never change it', () async {
      await r.foods.seedCatalog(readCatalogJson());
      final riceRow = await (r.db.select(
        r.db.foods,
      )..where((f) => f.sourceId.equals('rice'))).getSingle();
      final id = await r.meals.save(
        draftOf([aiItem('i1', per100: const Nutrition(kcal: 999))]),
      );
      final item = (await r.meals.getMeal(id))!.items.single;
      expect(item.foodId, riceRow.id);
      final after = await (r.db.select(
        r.db.foods,
      )..where((f) => f.id.equals(riceRow.id))).getSingle();
      expect(after.kcalPer100g, riceRow.kcalPer100g);
    });
  });

  group('diary queries', () {
    test('a late-night meal belongs to its local day only', () async {
      const tz = FixedOffsetZone(Duration(hours: 5, minutes: 30));
      final repos = TestRepos(zone: tz);
      addTearDown(repos.close);
      // 23:30 local on 9 March (UTC+5:30) is 18:00 UTC.
      await repos.meals.save(
        draftOf([aiItem('a')], time: DateTime.utc(2026, 3, 9, 23, 30)),
      );
      final day9 = await repos.meals.watchDay(DateTime.utc(2026, 3, 9)).first;
      final day10 = await repos.meals.watchDay(DateTime.utc(2026, 3, 10)).first;
      expect(day9, hasLength(1));
      expect(day10, isEmpty);
      expect(day9.single.mealTime.hour, 23);
    });

    for (final offset in [
      const Duration(hours: -8),
      Duration.zero,
      const Duration(hours: 5, minutes: 30),
      const Duration(hours: 13),
    ]) {
      test('day boundaries hold for UTC$offset', () async {
        final tz = FixedOffsetZone(offset);
        final repos = TestRepos(zone: tz);
        addTearDown(repos.close);
        final times = [
          DateTime.utc(2026, 3, 9, 23, 59, 59), // last second of the 9th
          DateTime.utc(2026, 3, 10), // first instant of the 10th
          DateTime.utc(2026, 3, 10, 23, 59, 59),
          DateTime.utc(2026, 3, 11), // first instant of the 11th
        ];
        for (var i = 0; i < times.length; i++) {
          await repos.meals.save(draftOf([aiItem('i$i')], time: times[i]));
        }
        int count(List<dynamic> l) => l.length;
        expect(
          count(await repos.meals.watchDay(DateTime.utc(2026, 3, 9)).first),
          1,
        );
        expect(
          count(await repos.meals.watchDay(DateTime.utc(2026, 3, 10)).first),
          2,
        );
        expect(
          count(await repos.meals.watchDay(DateTime.utc(2026, 3, 11)).first),
          1,
        );
        expect(
          await repos.meals.watchDaysWithMeals(DateTime.utc(2026, 3, 15)).first,
          {9, 10, 11},
        );
      });
    }

    test('meals are ordered by time and the stream reacts to saves', () async {
      final emissions = <List<String>>[];
      final sub = r.meals
          .watchDay(DateTime.utc(2026, 3, 10))
          .listen(
            (meals) =>
                emissions.add([for (final m in meals) m.mealType?.name ?? '-']),
          );
      addTearDown(sub.cancel);
      await pumpEvents();
      await r.meals.save(
        draftOf(
          [aiItem('a')],
          time: DateTime.utc(2026, 3, 10, 16),
          type: MealType.snack,
        ),
      );
      await pumpEvents();
      await r.meals.save(
        draftOf(
          [aiItem('b')],
          time: DateTime.utc(2026, 3, 10, 13),
          type: MealType.lunch,
        ),
      );
      await pumpEvents();
      expect(emissions.first, isEmpty);
      expect(emissions.last, ['lunch', 'snack']);
    });

    test('mealsWithItems supports a time range', () async {
      await r.meals.save(
        draftOf([aiItem('a')], time: DateTime.utc(2026, 3, 1, 12)),
      );
      await r.meals.save(
        draftOf([
          aiItem('b'),
          aiItem('c'),
        ], time: DateTime.utc(2026, 3, 20, 12)),
      );
      final all = await r.meals.mealsWithItems();
      expect(all.map((m) => m.items.length), [1, 2]);
      final late = await r.meals.mealsWithItems(
        start: DateTime.utc(2026, 3, 10),
      );
      expect(late, hasLength(1));
      final early = await r.meals.mealsWithItems(
        end: DateTime.utc(2026, 3, 10),
      );
      expect(early, hasLength(1));
    });
  });

  group('delete and restore', () {
    test(
      'delete returns a snapshot and restore brings back identical data',
      () async {
        final id = await r.meals.save(
          draftOf([aiItem('a', weight: 120), manualItem('b')]),
          photoPath: 'meals/2026/03/10/p.jpg',
        );
        final before = (await r.meals.getMeal(id))!;

        final snapshot = await r.meals.delete(id);
        expect(snapshot, isNotNull);
        expect(await r.meals.getMeal(id), isNull);
        expect(await r.db.select(r.db.mealItems).get(), isEmpty);

        await r.meals.restore(snapshot!);
        final after = (await r.meals.getMeal(id))!;
        expect(after.photoPath, before.photoPath);
        expect(after.mealTime, before.mealTime);
        expect(after.totals, before.totals);
        expect(after.createdAt, before.createdAt);
        expect(
          after.items.map(
            (i) => (
              i.id,
              i.name,
              i.weightG,
              i.estimatedWeightG,
              i.wasCorrected,
              i.foodId,
            ),
          ),
          before.items.map(
            (i) => (
              i.id,
              i.name,
              i.weightG,
              i.estimatedWeightG,
              i.wasCorrected,
              i.foodId,
            ),
          ),
        );
      },
    );

    test('deleting an unknown meal is a no-op', () async {
      expect(await r.meals.delete('nope'), isNull);
    });
  });

  group('recentMeals', () {
    test('newest first', () async {
      await r.meals.save(
        draftOf([aiItem('a')], time: DateTime.utc(2026, 3, 8, 8)),
      );
      await r.meals.save(
        draftOf([aiItem('b')], time: DateTime.utc(2026, 3, 9, 13)),
      );
      await r.meals.save(
        draftOf([aiItem('c')], time: DateTime.utc(2026, 3, 5)),
      );

      final list = await r.meals.recentMeals(
        since: DateTime.utc(2026, 2, 1),
        limit: 50,
      );
      expect(list.map((m) => m.items.single.id), ['b', 'a', 'c']);
    });

    test('the 30-day window includes 29 days ago and excludes 31', () async {
      final now = DateTime.utc(2026, 3, 10, 12);
      await r.meals.save(
        draftOf([aiItem('a')], time: now.subtract(const Duration(days: 29))),
      );
      await r.meals.save(
        draftOf([aiItem('b')], time: now.subtract(const Duration(days: 31))),
      );

      final list = await r.meals.recentMeals(
        since: now.subtract(const Duration(days: 30)),
        limit: 50,
      );
      expect(list.map((m) => m.items.single.id), ['a']);
    });

    test('the limit keeps only the newest meals', () async {
      for (var i = 0; i < 60; i++) {
        await r.meals.save(
          draftOf([aiItem('i$i')], time: DateTime.utc(2026, 3, 10, 0, i)),
        );
      }
      final list = await r.meals.recentMeals(
        since: DateTime.utc(2026, 1, 1),
        limit: 50,
      );
      expect(list, hasLength(50));
      expect(list.first.items.single.id, 'i59');
      expect(list.last.items.single.id, 'i10');
    });

    test('a deleted meal is not returned', () async {
      final id = await r.meals.save(draftOf([aiItem('a')]));
      await r.meals.delete(id);
      expect(
        await r.meals.recentMeals(since: DateTime.utc(2026, 1, 1), limit: 50),
        isEmpty,
      );
    });

    test('a meal without items is not returned', () async {
      await r.meals.save(draftOf(const []));
      expect(
        await r.meals.recentMeals(since: DateTime.utc(2026, 1, 1), limit: 50),
        isEmpty,
      );
    });

    test('custom and packaged items are returned from local data, with no network fake involved', () async {
      final custom = await r.foods.createCustom(
        const CustomFoodInput(
          name: 'Homemade granola',
          per100: Nutrition(kcal: 450, protein: 10, fat: 18, carbs: 55),
        ),
      );
      final packaged = await r.foods.savePackaged(
        const PackagedProduct(
          barcode: '4006381333931',
          name: 'Snack bar',
          per100: Nutrition(kcal: 400, protein: 8, fat: 15, carbs: 55),
        ),
      );
      await r.meals.save(
        draftOf([
          DraftItem.manual(
            id: 'c1',
            name: custom.name,
            weightG: 40,
            per100: custom.per100,
            foodId: custom.id,
            nutritionSource: custom.source,
          ),
          DraftItem.manual(
            id: 'p1',
            name: packaged.name,
            weightG: 35,
            per100: packaged.per100,
            foodId: packaged.id,
            nutritionSource: packaged.source,
          ),
        ]),
      );

      final list = await r.meals.recentMeals(
        since: DateTime.utc(2026, 1, 1),
        limit: 50,
      );
      expect(list, hasLength(1));
      final items = list.single.items;
      expect(items.map((i) => i.id), ['c1', 'p1']);
      expect(items[0].weightG, 40);
      expect(items[0].foodId, custom.id);
      expect(items[1].weightG, 35);
      expect(items[1].foodId, packaged.id);
    });

    test('does the same number of SELECTs for 1 and for 50 meals', () async {
      Future<int> selectsFor(int mealCount) async {
        final counter = _SelectCounter();
        final db = AppDatabase(NativeDatabase.memory().interceptWith(counter));
        final repo = DriftMealRepository(
          db,
          clock: () => DateTime.utc(2026, 3, 10, 12),
        );
        for (var i = 0; i < mealCount; i++) {
          await repo.save(
            draftOf([aiItem('i$i')], time: DateTime.utc(2026, 3, 10, 0, i)),
          );
        }
        counter.count = 0;
        await repo.recentMeals(since: DateTime.utc(2026, 1, 1), limit: 50);
        await db.close();
        return counter.count;
      }

      expect(await selectsFor(1), await selectsFor(50));
    });
  });

  group('repeat and save (regression)', () {
    test('repeating an AI-sourced meal, editing it and saving keeps ai_corrections '
        'unchanged and both meals independent', () async {
      final sourceId = await r.meals.save(
        draftOf([aiItem('rice1', estimated: 170, weight: 150)]),
      );
      final useCase = RepeatMealUseCase(
        meals: r.meals,
        foods: r.foods,
        ids: const IdGenerator(),
        clock: () => DateTime.utc(2026, 3, 12, 9),
      );
      final draft = await useCase(sourceId);
      final edited = draft.copyWith(
        items: [draft.items.single.copyWith(weightG: 200)],
      );
      final before = await r.db.select(r.db.aiCorrections).get();

      final repeatedId = await r.meals.save(edited);

      expect(repeatedId, isNot(sourceId));
      final after = await r.db.select(r.db.aiCorrections).get();
      expect(
        after.map((c) => (c.id, c.aiWeightG, c.userWeightG)),
        before.map((c) => (c.id, c.aiWeightG, c.userWeightG)),
      );

      final source = (await r.meals.getMeal(sourceId))!;
      expect(source.items.single.weightG, 150);
      final repeated = (await r.meals.getMeal(repeatedId))!;
      expect(repeated.items.single.weightG, 200);

      await r.meals.delete(sourceId);
      final stillThere = (await r.meals.getMeal(repeatedId))!;
      expect(stillThere.items.single.weightG, 200);
    });
  });
}

/// Lets pending stream events run.
Future<void> pumpEvents() =>
    Future<void>.delayed(const Duration(milliseconds: 30));
