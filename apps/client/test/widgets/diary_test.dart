import 'package:calsnap/core/domain/nutrition.dart';
import 'package:calsnap/features/meal/domain/meal.dart';
import 'package:calsnap/features/settings/domain/user_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../support/fixtures.dart';

DateTime at(int h, [int m = 0, int day = 10]) => DateTime(2026, 3, day, h, m);

Future<void> addMeal(
  TestApp app, {
  required double kcal,
  required DateTime time,
  required MealType type,
  String id = 'i',
  String name = 'Food',
  double protein = 0,
  double fat = 0,
  double carbs = 0,
  String? photo,
}) => app.saveMeal(
  draftOf(
    [
      manualItem(
        id,
        name: name,
        weight: 100,
        per100: Nutrition(kcal: kcal, protein: protein, fat: fat, carbs: carbs),
      ),
    ],
    time: time,
    type: type,
  ),
  photoPath: photo,
);

/// The example day of the specification: 1460 kcal in four meals.
Future<void> seedNormalDay(TestApp app, {int day = 10}) async {
  await addMeal(
    app,
    id: 'b',
    kcal: 430,
    time: at(8, 0, day),
    type: MealType.breakfast,
    protein: 30,
    fat: 12,
    carbs: 50,
  );
  await addMeal(
    app,
    id: 'l',
    kcal: 610,
    time: at(13, 0, day),
    type: MealType.lunch,
    protein: 40,
    fat: 20,
    carbs: 60,
  );
  await addMeal(
    app,
    id: 's',
    kcal: 180,
    time: at(16, 0, day),
    type: MealType.snack,
    protein: 8,
    fat: 6,
    carbs: 20,
  );
  await addMeal(
    app,
    id: 'd',
    kcal: 240,
    time: at(19, 0, day),
    type: MealType.dinner,
    protein: 30,
    fat: 16,
    carbs: 2,
  );
}

void main() {
  group('Today screen', () {
    appTest('shows progress against the target and the remaining calories', (
      tester,
      app,
    ) async {
      await app.completeOnboarding(
        kcal: 2200,
        protein: 150,
        fat: 75,
        carbs: 240,
      );
      await seedNormalDay(app);
      await tester.pumpWidget(app.app());
      await settle(tester);

      expect(find.text('1460 / 2200 kcal'), findsOneWidget);
      expect(find.text('740 kcal remaining'), findsOneWidget);
      // Macro progress against the targets.
      expect(find.text('108 / 150 g'), findsOneWidget);
      expect(find.text('54 / 75 g'), findsOneWidget);
      expect(find.text('132 / 240 g'), findsOneWidget);
      expect(find.text('Today'), findsWidgets);
    });

    appTest('over the target is reported without an error style', (
      tester,
      app,
    ) async {
      await app.completeOnboarding(kcal: 2200);
      await addMeal(app, kcal: 2400, time: at(13), type: MealType.lunch);
      await tester.pumpWidget(app.app());
      await settle(tester);

      expect(find.text('200 kcal over the target'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator).first,
      );
      final scheme = Theme.of(
        tester.element(find.byKey(const Key('kcalProgress'))),
      ).colorScheme;
      expect(bar.color, scheme.tertiary);
      expect(bar.color, isNot(scheme.error));
      expect(bar.value, 1.0);
    });

    appTest('without macro targets only the consumed values are shown', (
      tester,
      app,
    ) async {
      await app.completeOnboarding(protein: null, fat: null, carbs: null);
      await addMeal(
        app,
        kcal: 500,
        time: at(13),
        type: MealType.lunch,
        protein: 25.5,
        fat: 9.4,
        carbs: 60,
      );
      await tester.pumpWidget(app.app());
      await settle(tester);

      expect(find.text('26 g'), findsOneWidget);
      expect(find.text('9.4 g'), findsOneWidget);
      expect(find.text('60 g'), findsOneWidget);
      expect(
        find.textContaining(' / '),
        findsOneWidget,
        reason: 'only the calorie line has a target',
      );
    });

    appTest('an empty day invites the user to take a photo or add manually', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      await tester.pumpWidget(app.app());
      await settle(tester);

      expect(find.byKey(const Key('emptyDay')), findsOneWidget);
      expect(find.text('No meals yet'), findsOneWidget);
      expect(find.text('0 / 2200 kcal'), findsOneWidget);
    });

    appTest('meals are listed chronologically with their type and calories', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      await addMeal(
        app,
        id: 'snack',
        kcal: 180,
        time: at(16),
        type: MealType.snack,
      );
      await addMeal(
        app,
        id: 'lunch',
        kcal: 610,
        time: at(13),
        type: MealType.lunch,
      );
      await tester.pumpWidget(app.app());
      await settle(tester);

      final lunchY = tester.getTopLeft(find.text('Lunch')).dy;
      final snackY = tester.getTopLeft(find.text('Snack')).dy;
      expect(lunchY, lessThan(snackY));
      expect(find.text('610 kcal'), findsOneWidget);
      expect(find.text('13:00'), findsOneWidget);
    });

    appTest('a missing photo file shows a placeholder and no error', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      await addMeal(
        app,
        kcal: 300,
        time: at(13),
        type: MealType.lunch,
        photo: 'meals/2026/03/10/gone.jpg',
      );
      await tester.pumpWidget(app.app());
      await settle(tester);

      // Loading the missing file fails asynchronously (real IO).
      await pumpUntil(
        tester,
        () => find.byIcon(Icons.restaurant).evaluate().isNotEmpty,
      );
      expect(find.byIcon(Icons.restaurant), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    appTest('the add sheet offers photo, gallery and manual entry', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      await tester.pumpWidget(app.app());
      await settle(tester);

      await tapKey(tester, 'addMeal');
      await settle(tester);
      expect(find.text('Take photo'), findsOneWidget);
      expect(find.text('Choose from gallery'), findsOneWidget);
      expect(find.text('Add manually'), findsOneWidget);
    });
  });

  group('day switching', () {
    appTest('buttons move between days and the future is not selectable', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      await addMeal(
        app,
        id: 'y',
        kcal: 700,
        time: at(13, 0, 9),
        type: MealType.lunch,
      );
      await tester.pumpWidget(app.app());
      await settle(tester);

      expect(
        tester.widget<IconButton>(find.byKey(const Key('nextDay'))).onPressed,
        isNull,
        reason: 'today is the last day',
      );

      await tapKey(tester, 'prevDay');
      await settle(tester);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('700 / 2200 kcal'), findsOneWidget);
      expect(find.byKey(const Key('goToToday')), findsOneWidget);

      await tapKey(tester, 'prevDay');
      await settle(tester);
      expect(find.text('0 / 2200 kcal'), findsOneWidget);
      expect(find.text('Yesterday'), findsNothing);

      await tapKey(tester, 'goToToday');
      await settle(tester);
      expect(find.byKey(const Key('goToToday')), findsNothing);
      expect(find.text('Today'), findsWidgets);
    });

    appTest('swiping horizontally changes the day', (tester, app) async {
      await app.completeOnboarding();
      await addMeal(
        app,
        id: 'y',
        kcal: 700,
        time: at(13, 0, 9),
        type: MealType.lunch,
      );
      await tester.pumpWidget(app.app());
      await settle(tester);

      await tester.fling(
        find.byKey(const Key('kcalProgress')),
        const Offset(300, 0),
        1200,
      );
      await settle(tester);
      expect(
        find.text('700 / 2200 kcal'),
        findsOneWidget,
        reason: 'swipe right shows the previous day',
      );

      await tester.fling(
        find.byKey(const Key('kcalProgress')),
        const Offset(-300, 0),
        1200,
      );
      await settle(tester);
      expect(
        find.text('0 / 2200 kcal'),
        findsOneWidget,
        reason: 'swipe left returns to today',
      );

      await tester.fling(
        find.byKey(const Key('kcalProgress')),
        const Offset(-300, 0),
        1200,
      );
      await settle(tester);
      expect(
        find.text('Today'),
        findsWidgets,
        reason: 'the future stays out of reach',
      );
    });

    appTest('the diary reacts to new meals without a manual refresh', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      await tester.pumpWidget(app.app());
      await settle(tester);
      expect(find.text('0 / 2200 kcal'), findsOneWidget);

      await addMeal(app, kcal: 500, time: at(9), type: MealType.breakfast);
      await settle(tester);
      expect(find.text('500 / 2200 kcal'), findsOneWidget);
    });
  });

  group('history calendar', () {
    appTest('marks days with meals and jumps to the picked day', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      await addMeal(
        app,
        id: 'a',
        kcal: 800,
        time: at(12, 0, 3),
        type: MealType.lunch,
      );
      await addMeal(
        app,
        id: 'b',
        kcal: 400,
        time: at(12, 0, 5),
        type: MealType.lunch,
      );
      await tester.pumpWidget(app.app(initialLocation: '/history'));
      await settle(tester);

      expect(find.byKey(const Key('marker-3')), findsOneWidget);
      expect(find.byKey(const Key('marker-5')), findsOneWidget);
      expect(find.byKey(const Key('marker-4')), findsNothing);

      // Future days are not selectable.
      expect(
        tester.widget<InkWell>(find.byKey(const Key('day-11'))).onTap,
        isNull,
      );
      expect(
        tester.widget<InkWell>(find.byKey(const Key('day-10'))).onTap,
        isNotNull,
      );

      await tapKey(tester, 'day-3');
      await settle(tester);
      expect(find.text('800 / 2200 kcal'), findsOneWidget);
    });

    appTest('the previous month is reachable and marked separately', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      await addMeal(
        app,
        id: 'f',
        kcal: 300,
        time: DateTime(2026, 2, 14, 12),
        type: MealType.lunch,
      );
      await tester.pumpWidget(app.app(initialLocation: '/history'));
      await settle(tester);

      expect(
        tester.widget<IconButton>(find.byKey(const Key('nextMonth'))).onPressed,
        isNull,
      );
      await tapKey(tester, 'prevMonth');
      await settle(tester);
      expect(find.byKey(const Key('marker-14')), findsOneWidget);
      await tapKey(tester, 'day-14');
      await settle(tester);
      expect(find.text('300 / 2200 kcal'), findsOneWidget);
    });
  });

  group('localization', () {
    appTest('the diary renders in Russian with a localized date', (
      tester,
      app,
    ) async {
      await app.completeOnboarding(language: AppLanguage.ru);
      await tester.pumpWidget(app.app());
      await settle(tester);
      expect(find.text('Сегодня'), findsWidgets);
      expect(find.text('Добавить'), findsOneWidget);

      await tapKey(tester, 'prevDay');
      await tapKey(tester, 'prevDay');
      await settle(tester);
      // 8 March 2026 is a Sunday: "воскресенье, 8 марта".
      expect(find.text('воскресенье, 8 марта'), findsOneWidget);
      expect(find.text('0 / 2200 ккал'), findsOneWidget);
    });
  });

  group('offline', () {
    appTest('the diary works from local data only', (tester, app) async {
      // No network provider is involved anywhere on this screen: it renders
      // from the database alone (airplane mode behaves identically).
      await app.completeOnboarding();
      await seedNormalDay(app);
      await tester.pumpWidget(app.app(initialLocation: '/splash'));
      await settle(tester);
      expect(find.text('1460 / 2200 kcal'), findsOneWidget);
    });
  });
}
