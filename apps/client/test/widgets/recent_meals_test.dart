import 'package:calsnap/core/domain/nutrition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../support/fixtures.dart';

DateTime at(int h, [int m = 0, int day = 10]) => DateTime(2026, 3, day, h, m);

/// Every item weighs 100 g at 1 kcal/g, so N items total N * 100 kcal.
Future<String> seedMeal(
  TestApp app, {
  required List<String> names,
  String idPrefix = 'i',
  DateTime? time,
}) => app.saveMeal(
  draftOf([
    for (var i = 0; i < names.length; i++)
      manualItem(
        '$idPrefix$i',
        name: names[i],
        weight: 100,
        per100: const Nutrition(kcal: 100),
      ),
  ], time: time ?? at(13)),
);

Future<void> openRecentMeals(WidgetTester tester, TestApp app) async {
  await tester.pumpWidget(app.app());
  await settle(tester);
  await push(tester, '/meal/repeat');
}

void main() {
  group('empty state', () {
    appTest('offers a photo action when there is nothing to repeat', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      await openRecentMeals(tester, app);

      expect(find.text('Nothing to repeat yet'), findsOneWidget);
      expect(find.byKey(const Key('repeatEmptyAction')), findsOneWidget);

      await tapKey(tester, 'repeatEmptyAction');
      await settle(tester);
      expect(find.text('Take a photo'), findsWidgets);
    });
  });

  group('card content', () {
    appTest('up to three items are shown with no +N', (tester, app) async {
      await app.completeOnboarding();
      await seedMeal(app, names: ['Oatmeal', 'Banana', 'Coffee']);
      await openRecentMeals(tester, app);

      expect(find.textContaining('Oatmeal, Banana, Coffee'), findsOneWidget);
      expect(find.textContaining('+'), findsNothing);
    });

    appTest('more than three items are truncated with a +N', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      await seedMeal(
        app,
        names: ['Oatmeal', 'Banana', 'Coffee', 'Milk', 'Honey'],
      );
      await openRecentMeals(tester, app);

      expect(
        find.textContaining('Oatmeal, Banana, Coffee, +2'),
        findsOneWidget,
      );
    });

    appTest('a single item is shown without a separator', (tester, app) async {
      await app.completeOnboarding();
      await seedMeal(app, names: ['Apple']);
      await openRecentMeals(tester, app);

      expect(find.textContaining('Apple'), findsOneWidget);
    });
  });

  group('large text and long names', () {
    appTest('long Russian and English names do not overflow', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      await seedMeal(
        app,
        names: [
          'A very long English product name that keeps going and going',
          'Очень длинное название продукта на русском языке, которое не помещается',
        ],
      );
      await openRecentMeals(tester, app);

      expect(tester.takeException(), isNull);
    });

    appTest('a 2x text scale shows all content without overflow', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      await seedMeal(app, names: ['Oatmeal', 'Banana', 'Coffee', 'Milk']);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: app.app(),
        ),
      );
      await settle(tester);
      await push(tester, '/meal/repeat');

      expect(tester.takeException(), isNull);
    });
  });

  group('accessibility', () {
    appTest('the card and the repeat button expose distinct semantics', (
      tester,
      app,
    ) async {
      final handle = tester.ensureSemantics();
      await app.completeOnboarding();
      final id = await seedMeal(app, names: ['Oatmeal', 'Banana', 'Coffee']);
      await openRecentMeals(tester, app);

      expect(
        find.bySemanticsLabel(
          'Eat this again: Oatmeal, Banana, Coffee, 300 kilocalories',
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.byKey(Key('repeatMeal-$id'))).tooltip,
        'Repeat meal',
        reason: 'the button is announced separately from the card label',
      );
      final button = tester.getSize(find.byKey(Key('repeatMeal-$id')));
      expect(button.width, greaterThanOrEqualTo(48));
      expect(button.height, greaterThanOrEqualTo(48));
      handle.dispose();
    });
  });

  group('repeating', () {
    appTest(
      'tapping repeat opens the editor with the Eat this again title and no AI markers',
      (tester, app) async {
        await app.completeOnboarding();
        final id = await app.saveMeal(
          draftOf([aiItem('rice', estimated: 170, weight: 170)], time: at(13)),
        );
        await openRecentMeals(tester, app);

        await tapKey(tester, 'repeatMeal-$id');
        await settle(tester, frames: 15);

        expect(find.text('Eat this again'), findsOneWidget);
        expect(find.text('Rice'), findsOneWidget);
        expect(find.textContaining('estimate'), findsNothing);
        expect(find.textContaining('adjusted'), findsNothing);
        expect(find.textContaining('Please check'), findsNothing);
      },
    );

    appTest(
      'a source deleted before the tap shows a message and drops from the list',
      (tester, app) async {
        await app.completeOnboarding();
        final id = await seedMeal(app, names: ['Toast']);
        await openRecentMeals(tester, app);
        expect(find.byKey(Key('recentMeal-$id')), findsOneWidget);

        await app.real(() => app.services.meals.delete(id));
        await tapKey(tester, 'repeatMeal-$id');
        await settle(tester, frames: 10);

        expect(find.text('This meal no longer exists'), findsOneWidget);
        expect(find.byKey(Key('recentMeal-$id')), findsNothing);
      },
    );
  });

  group('routing', () {
    appTest('navigating to /meal/repeat shows the recent meals list', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      await seedMeal(app, names: ['Toast']);
      await openRecentMeals(tester, app);

      expect(find.text('Recent meals'), findsOneWidget);
      expect(find.byKey(const Key('recentMealsList')), findsOneWidget);
    });
  });
}
