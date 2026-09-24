import 'dart:io';

import 'package:calsnap/core/domain/nutrition.dart';
import 'package:calsnap/features/meal/domain/meal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../support/fixtures.dart';

DateTime at(int h, [int m = 0, int day = 10]) => DateTime(2026, 3, day, h, m);

/// A saved lunch: corrected rice (170 -> 150 g) and 30 g of manual bread.
Future<String> seedLunch(TestApp app, {String? photo}) => app.saveMeal(
  draftOf(
    [
      aiItem('rice', estimated: 170, weight: 150),
      manualItem(
        'bread',
        name: 'Bread',
        weight: 30,
        per100: const Nutrition(kcal: 250, protein: 8, carbs: 50),
      ),
    ],
    time: at(13),
    type: MealType.lunch,
  ),
  photoPath: photo,
);

Future<void> openDiaryAndMeal(
  WidgetTester tester,
  TestApp app,
  String id,
) async {
  await tester.pumpWidget(app.app());
  await settle(tester);
  await tester.tap(find.byKey(Key('meal-$id')));
  await settle(tester, frames: 20);
}

Future<File> createPhoto(TestApp app) => app.real(() async {
  final file = File('${app.root.path}/docs/meals/2026/03/10/p.jpg');
  await file.parent.create(recursive: true);
  await file.writeAsBytes([1, 2, 3]);
  return file;
});

void main() {
  group('editing a saved meal', () {
    appTest(
      'opens in the shared editor with the saved items and exact totals',
      (tester, app) async {
        await app.completeOnboarding();
        final id = await seedLunch(app);
        await openDiaryAndMeal(tester, app, id);

        expect(find.text('Edit meal'), findsOneWidget);
        expect(find.text('Rice'), findsOneWidget);
        expect(find.text('Bread'), findsOneWidget);
        expect(find.text('195 kcal'), findsWidgets); // rice 150 g * 130
        expect(find.text('75 kcal'), findsOneWidget); // bread 30 g * 250
        // Saved totals are exact, not approximate: 195 + 75.
        expect(find.text('270 kcal'), findsOneWidget);
        expect(find.textContaining('≈'), findsNothing);
      },
    );

    appTest('a changed quantity is saved, totals and the correction follow', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      final id = await seedLunch(app);
      await openDiaryAndMeal(tester, app, id);

      await tester.tap(find.widgetWithText(ActionChip, '150 g'));
      await settle(tester, frames: 10);
      await enterKey(tester, 'weightField', '140');
      await tapKey(tester, 'weightApply');
      await settle(tester, frames: 10);
      expect(find.text('257 kcal'), findsOneWidget); // 182 + 75
      await tapKey(tester, 'saveMeal');
      await pumpUntil(
        tester,
        () => find.byKey(const Key('kcalProgress')).evaluate().isNotEmpty,
      );

      expect(find.text('257 / 2200 kcal'), findsOneWidget);
      final corrections = await app.real(
        () => app.db.select(app.db.aiCorrections).get(),
      );
      expect(corrections, hasLength(1));
      expect(
        (corrections.single.aiWeightG, corrections.single.userWeightG),
        (170.0, 140.0),
      );
      expect((await app.mealRows()).single.totalKcal, closeTo(257, 1e-9));
    });

    appTest('replacing a product keeps the weight and takes the new values', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      final id = await seedLunch(app);
      await openDiaryAndMeal(tester, app, id);

      await tapKey(tester, 'edit-rice');
      await settle(tester, frames: 12);
      await tapKey(tester, 'replaceProduct');
      await settle(tester, frames: 12);
      await enterKey(tester, 'foodSearchField', 'buckwheat');
      await settle(tester, frames: 15);
      await tester.tap(find.text('Buckwheat').first);
      await settle(tester, frames: 15);

      expect(find.text('Buckwheat'), findsOneWidget);
      expect(find.text('Rice'), findsNothing);
      expect(
        find.widgetWithText(ActionChip, '150 g'),
        findsOneWidget,
        reason: 'the weight is kept',
      );
      expect(find.text('138 kcal'), findsOneWidget); // 150 g * 92 / 100
    });

    appTest(
      'date, time and meal type can be changed; the meal moves to the other day',
      (tester, app) async {
        await app.completeOnboarding();
        final photo = await createPhoto(app);
        final id = await seedLunch(app, photo: 'meals/2026/03/10/p.jpg');
        await openDiaryAndMeal(tester, app, id);

        await tester.scrollUntilVisible(find.byKey(const Key('pickDate')), 300);
        await tester.ensureVisible(find.byKey(const Key('pickDate')));
        await settle(tester, frames: 6);
        await tester.tap(find.byKey(const Key('pickDate')));
        await settle(tester, frames: 15);
        await tester.tap(find.text('9').last);
        await tester.pump();
        await tester.tap(find.text('OK'));
        await settle(tester, frames: 15);
        await tapKey(tester, 'saveMeal');
        await pumpUntil(
          tester,
          () => find.byKey(const Key('kcalProgress')).evaluate().isNotEmpty,
        );

        // After saving the diary shows the day of the meal: yesterday ...
        expect(find.text('Yesterday'), findsOneWidget);
        expect(find.text('270 / 2200 kcal'), findsOneWidget);
        // ... and today no longer has it. The photo file stays where it was.
        await tapKey(tester, 'goToToday');
        await settle(tester);
        expect(find.text('0 / 2200 kcal'), findsOneWidget);
        final row = (await app.mealRows()).single;
        expect(row.photoPath, 'meals/2026/03/10/p.jpg');
        expect(await app.real(photo.exists), isTrue);
      },
    );

    appTest('leaving with changes asks, leaving without changes does not', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      final id = await seedLunch(app);
      await openDiaryAndMeal(tester, app, id);

      await tester.pageBack();
      await settle(tester, frames: 15);
      expect(
        find.text('Discard changes?'),
        findsNothing,
        reason: 'nothing changed',
      );
      expect(find.byKey(const Key('kcalProgress')), findsOneWidget);

      await tester.tap(find.byKey(Key('meal-$id')));
      await settle(tester, frames: 20);
      await tester.tap(find.byKey(const Key('remove-bread')));
      await settle(tester, frames: 8);
      await tester.pageBack();
      await settle(tester, frames: 10);
      expect(find.text('Discard changes?'), findsOneWidget);
      await tapKey(tester, 'discardChanges');
      await settle(tester, frames: 15);
      // The stored meal is untouched.
      expect((await app.itemRows()), hasLength(2));
    });

    appTest('a meal without items cannot be saved and offers to delete it', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      final id = await seedLunch(app);
      await openDiaryAndMeal(tester, app, id);

      for (final itemId in ['rice', 'bread']) {
        await tester.tap(find.byKey(Key('remove-$itemId')));
        await settle(tester, frames: 8);
      }
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('saveMeal')))
            .onPressed,
        isNull,
      );
      expect(find.byKey(const Key('emptyMealOffer')), findsOneWidget);
      expect(find.text('The meal has no items'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Delete meal'));
      await settle(tester, frames: 10);
      await tapKey(tester, 'deleteMealConfirm');
      await settle(tester, frames: 20);
      expect(await app.mealRows(), isEmpty);
    });
  });

  group('deleting a meal', () {
    Future<void> deleteFromDiary(WidgetTester tester, String id) async {
      await tester.tap(find.byKey(Key('mealMenu-$id')));
      await settle(tester, frames: 8);
      await tester.tap(find.text('Delete').last);
      await settle(tester, frames: 10);
    }

    appTest('needs confirmation; cancelling keeps the meal', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      final id = await seedLunch(app);
      await tester.pumpWidget(app.app());
      await settle(tester);

      await deleteFromDiary(tester, id);
      expect(find.text('Delete this meal?'), findsOneWidget);
      await tapKey(tester, 'deleteMealCancel');
      await settle(tester, frames: 10);
      expect(await app.mealRows(), hasLength(1));
      expect(find.byKey(Key('meal-$id')), findsOneWidget);
    });

    appTest(
      'Undo within the window restores the meal, its items and its photo',
      (tester, app) async {
        await app.completeOnboarding();
        final photo = await createPhoto(app);
        final id = await seedLunch(app, photo: 'meals/2026/03/10/p.jpg');
        final before = (await app.getMeal(id))!;
        await tester.pumpWidget(app.app());
        await settle(tester);

        await deleteFromDiary(tester, id);
        await tapKey(tester, 'deleteMealConfirm');
        await settle(tester, frames: 10);
        expect(find.byKey(Key('meal-$id')), findsNothing);
        expect(find.text('Meal deleted'), findsOneWidget);
        expect(await app.itemRows(), isEmpty);
        expect(
          await app.real(photo.exists),
          isTrue,
          reason: 'the photo survives until the undo window is over',
        );

        await tester.tap(find.text('Undo'));
        await settle(tester, frames: 10);
        // Even after the window would have passed nothing is removed.
        await tester.pump(const Duration(seconds: 8));

        final after = (await app.getMeal(id))!;
        expect(
          after.items.map(
            (i) =>
                (i.id, i.name, i.weightG, i.estimatedWeightG, i.wasCorrected),
          ),
          before.items.map(
            (i) =>
                (i.id, i.name, i.weightG, i.estimatedWeightG, i.wasCorrected),
          ),
        );
        expect(after.totals, before.totals);
        expect(after.photoPath, before.photoPath);
        expect(find.byKey(Key('meal-$id')), findsOneWidget);
        expect(await app.real(photo.exists), isTrue);
      },
    );

    appTest('without Undo the photo is removed once the window has passed', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      final photo = await createPhoto(app);
      final id = await seedLunch(app, photo: 'meals/2026/03/10/p.jpg');
      await tester.pumpWidget(app.app());
      await settle(tester);

      await deleteFromDiary(tester, id);
      await tapKey(tester, 'deleteMealConfirm');
      await settle(tester, frames: 10);
      expect(await app.real(photo.exists), isTrue);

      await tester.pump(const Duration(seconds: 7));
      await pumpUntil(tester, () => !photo.existsSync());
      expect(photo.existsSync(), isFalse);
      expect(await app.mealRows(), isEmpty);
    });

    appTest(
      'deleting from the editor returns to the diary with Undo available',
      (tester, app) async {
        await app.completeOnboarding();
        final id = await seedLunch(app);
        await openDiaryAndMeal(tester, app, id);

        await tapKey(tester, 'deleteMealButton');
        await settle(tester, frames: 10);
        await tapKey(tester, 'deleteMealConfirm');
        await settle(tester, frames: 20);

        expect(find.byKey(const Key('kcalProgress')), findsOneWidget);
        expect(find.text('Meal deleted'), findsOneWidget);
        await tester.tap(find.text('Undo'));
        await settle(tester, frames: 10);
        expect(find.byKey(Key('meal-$id')), findsOneWidget);
      },
    );
  });
}
