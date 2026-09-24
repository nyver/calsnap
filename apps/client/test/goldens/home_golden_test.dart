import 'package:calsnap/core/domain/nutrition.dart';
import 'package:calsnap/features/meal/domain/meal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../support/fixtures.dart';

DateTime at(int h, [int m = 0]) => DateTime(2026, 3, 10, h, m);

Future<void> meal(
  TestApp app,
  String id,
  double kcal,
  DateTime time,
  MealType type,
) => app.saveMeal(
  draftOf(
    [
      manualItem(
        id,
        name: 'Food',
        weight: 100,
        per100: Nutrition(
          kcal: kcal,
          protein: kcal / 20,
          fat: kcal / 30,
          carbs: kcal / 8,
        ),
      ),
    ],
    time: time,
    type: type,
  ),
);

void main() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    Future<void> render(WidgetTester tester, TestApp app, String name) async {
      tester.platformDispatcher.platformBrightnessTestValue = dark
          ? Brightness.dark
          : Brightness.light;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpWidget(app.app());
      await settle(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/home_${name}_$mode.png'),
      );
    }

    group('Home golden ($mode)', () {
      appTest('empty day', (tester, app) async {
        await app.completeOnboarding();
        await render(tester, app, 'empty');
      });

      appTest('normal day', (tester, app) async {
        await app.completeOnboarding();
        await meal(app, 'b', 430, at(8), MealType.breakfast);
        await meal(app, 'l', 610, at(13), MealType.lunch);
        await meal(app, 's', 180, at(16), MealType.snack);
        await meal(app, 'd', 240, at(19), MealType.dinner);
        await render(tester, app, 'normal');
      });

      appTest('over the target', (tester, app) async {
        await app.completeOnboarding();
        await meal(app, 'l', 1500, at(13), MealType.lunch);
        await meal(app, 'd', 900, at(19), MealType.dinner);
        await render(tester, app, 'over');
      });
    });
  }
}
