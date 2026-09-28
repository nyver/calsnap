import 'package:calsnap/core/domain/nutrition.dart';
import 'package:calsnap/features/meal/domain/meal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../support/fixtures.dart';

DateTime at(int h, [int m = 0]) => DateTime(2026, 3, 10, h, m);

Future<void> seedMeals(TestApp app) async {
  await app.saveMeal(
    draftOf(
      [
        manualItem(
          'o1',
          name: 'Oatmeal',
          weight: 250,
          per100: const Nutrition(kcal: 68, protein: 2.4, fat: 1.4, carbs: 12),
        ),
        manualItem(
          'o2',
          name: 'Banana',
          weight: 120,
          per100: const Nutrition(kcal: 89, protein: 1.1, fat: 0.3, carbs: 23),
        ),
        manualItem(
          'o3',
          name: 'Coffee',
          weight: 200,
          per100: const Nutrition(kcal: 2),
        ),
      ],
      time: at(8),
      type: MealType.breakfast,
    ),
  );
  await app.saveMeal(
    draftOf(
      [
        manualItem(
          'l1',
          name: 'Grilled chicken',
          weight: 150,
          per100: const Nutrition(kcal: 165, protein: 31, fat: 3.6),
        ),
        manualItem(
          'l2',
          name: 'Rice',
          weight: 180,
          per100: const Nutrition(kcal: 130, protein: 2.7, fat: 0.3, carbs: 28),
        ),
        manualItem(
          'l3',
          name: 'Broccoli',
          weight: 100,
          per100: const Nutrition(kcal: 34, protein: 2.8, carbs: 7),
        ),
        manualItem(
          'l4',
          name: 'Olive oil',
          weight: 10,
          per100: const Nutrition(kcal: 884, fat: 100),
        ),
      ],
      time: at(13),
      type: MealType.lunch,
    ),
  );
}

void main() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    Future<void> render(
      WidgetTester tester,
      TestApp app,
      String name, {
      Widget Function(Widget)? wrap,
    }) async {
      tester.platformDispatcher.platformBrightnessTestValue = dark
          ? Brightness.dark
          : Brightness.light;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      var widget = app.app(initialLocation: '/meal/repeat');
      if (wrap != null) widget = wrap(widget);
      await tester.pumpWidget(widget);
      await settle(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/repeat_meal_${name}_$mode.png'),
      );
    }

    group('Repeat meal golden ($mode)', () {
      appTest('empty', (tester, app) async {
        await app.completeOnboarding();
        await render(tester, app, 'empty');
      });

      appTest('list', (tester, app) async {
        await app.completeOnboarding();
        await seedMeals(app);
        await render(tester, app, 'list');
      });

      appTest('large text', (tester, app) async {
        await app.completeOnboarding();
        await seedMeals(app);
        await render(
          tester,
          app,
          'large_text',
          wrap: (child) => MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: child,
          ),
        );
      });
    });
  }
}
