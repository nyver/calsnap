import 'package:calsnap/core/database/app_database.dart';
import 'package:calsnap/core/di/providers.dart';
import 'package:calsnap/core/domain/nutrition.dart';
import 'package:calsnap/features/meal/domain/meal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../support/fixtures.dart';

Future<void> dayMeal(
  TestApp app,
  int day,
  double kcal, {
  String? id,
  double protein = 0,
  double fat = 0,
  double carbs = 0,
}) => app.saveMeal(
  draftOf(
    [
      manualItem(
        id ?? 'i$day',
        name: 'Food',
        weight: 100,
        per100: Nutrition(kcal: kcal, protein: protein, fat: fat, carbs: carbs),
      ),
    ],
    time: DateTime(2026, 3, day, 13),
    type: MealType.lunch,
  ),
);

void main() {
  group('statistics', () {
    appTest('shows today, the average over logged days and target adherence', (
      tester,
      app,
    ) async {
      await app.completeOnboarding(kcal: 2000);
      // Today is 10 March. Logged days: 1850, 2150, 2400, 1700.
      await dayMeal(app, 6, 1850, protein: 100, fat: 60, carbs: 200);
      await dayMeal(app, 7, 2150, protein: 120, fat: 70, carbs: 240);
      await dayMeal(app, 8, 2400);
      await dayMeal(app, 10, 1700);
      await tester.pumpWidget(app.app(initialLocation: '/statistics'));
      await settle(tester);

      expect(find.byKey(const Key('weekChart')), findsOneWidget);
      expect(find.text('1700 kcal'), findsOneWidget, reason: "today's kcal");
      // (1850 + 2150 + 2400 + 1700) / 4 = 2025, empty days are not zero intake.
      expect(find.text('2025 kcal'), findsOneWidget);
      expect(find.text('2 of 4 logged days on target'), findsOneWidget);
      expect(find.text('Target 2000 kcal'), findsOneWidget);
      expect(find.byKey(const Key('statsNoData')), findsNothing);
    });

    appTest('an empty week explains that nothing was logged', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      await tester.pumpWidget(app.app(initialLocation: '/statistics'));
      await settle(tester);

      expect(find.byKey(const Key('statsNoData')), findsOneWidget);
      expect(find.byKey(const Key('statsAdherence')), findsNothing);
      expect(find.text('0 kcal'), findsWidgets);
    });

    appTest('updates after a meal is saved and works from local data only', (
      tester,
      app,
    ) async {
      await app.completeOnboarding(kcal: 2000);
      await tester.pumpWidget(app.app(initialLocation: '/statistics'));
      await settle(tester);
      expect(find.byKey(const Key('statsNoData')), findsOneWidget);

      await dayMeal(app, 10, 1900);
      await settle(tester);
      expect(find.text('1900 kcal'), findsWidgets);
      expect(find.text('1 of 1 logged day on target'), findsOneWidget);
    });

    appTest('the chart is drawn for logged and empty days without errors', (
      tester,
      app,
    ) async {
      await app.completeOnboarding(kcal: 2000);
      await dayMeal(app, 9, 2600);
      await tester.pumpWidget(app.app(initialLocation: '/statistics'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      // A bar taller than the target: the chart scales to the largest value.
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });

  group('splash', () {
    appTest(
      'an initialization failure shows an understandable error with retry',
      (tester, app) async {
        var attempts = 0;
        await tester.pumpWidget(
          app.app(
            initialLocation: '/splash',
            overrideServices: false,
            overrides: [
              appServicesProvider.overrideWith((ref) async {
                attempts++;
                if (attempts == 1) {
                  throw StateError('disk exploded /secret/path');
                }
                return app.services;
              }),
            ],
          ),
        );
        await settle(tester);

        expect(find.text('CalSnap could not start'), findsOneWidget);
        expect(
          find.textContaining('Your data has not been changed'),
          findsOneWidget,
        );
        expect(
          find.textContaining('disk exploded'),
          findsNothing,
          reason: 'no raw exception text',
        );
        await tapKey(tester, 'initRetry');
        await settle(tester, frames: 20);
        expect(attempts, 2);
        expect(
          find.text('Step 1 of 5'),
          findsOneWidget,
          reason: 'after the retry the first launch continues',
        );
      },
    );

    appTest(
      'a database from a newer app version asks to update and does not continue',
      (tester, app) async {
        await tester.pumpWidget(
          app.app(
            initialLocation: '/splash',
            overrideServices: false,
            overrides: [
              appServicesProvider.overrideWith(
                (ref) async => throw const UnsupportedSchemaException(
                  found: 2,
                  supported: 1,
                ),
              ),
            ],
          ),
        );
        await settle(tester);

        expect(find.text('Please update CalSnap'), findsOneWidget);
        expect(find.textContaining('newer version'), findsOneWidget);
        expect(find.byKey(const Key('kcalProgress')), findsNothing);
        expect(find.text('Step 1 of 5'), findsNothing);
      },
    );
  });
}
