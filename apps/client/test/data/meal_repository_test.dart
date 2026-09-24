import 'package:calsnap/core/domain/nutrition.dart';
import 'package:calsnap/features/meal/domain/meal.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

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
}

/// Lets pending stream events run.
Future<void> pumpEvents() =>
    Future<void>.delayed(const Duration(milliseconds: 30));
