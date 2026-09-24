import 'package:calsnap/features/meal/ui/meal_draft_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../support/fixtures.dart';

/// Recognition result of the full fixture (rice 170 g, chicken 135 g, cucumber
/// 80 g, tomato 65 g): 221 + 222.75 + 12 + 11.7 = 467.45 kcal.
Future<void> openFullResult(WidgetTester tester, TestApp app) async {
  await app.completeOnboarding();
  await tester.pumpWidget(app.app());
  await settle(tester);
  await openRecognition(tester, 'analyze-response-full.json');
}

Finder weightChip(String text) => find.widgetWithText(ActionChip, text);

Future<void> setWeight(WidgetTester tester, Finder chip, String grams) async {
  await tester.tap(chip);
  await settle(tester, frames: 8);
  await enterKey(tester, 'weightField', grams);
  await tapKey(tester, 'weightApply');
  await settle(tester, frames: 8);
}

/// Three earlier meals in which the user raised the rice from 170 g to 220 g.
Future<void> seedRiceCorrections(TestApp app) async {
  for (var i = 0; i < 3; i++) {
    await app.saveMeal(
      draftOf([
        aiItem('seed$i', estimated: 170, weight: 220),
      ], time: DateTime(2026, 3, 1 + i, 12)),
    );
  }
}

Future<void> openFullResultAfterSeeding(
  WidgetTester tester,
  TestApp app,
) async {
  await app.completeOnboarding();
  await seedRiceCorrections(app);
  await tester.pumpWidget(app.app());
  await settle(tester);
  await openRecognition(tester, 'analyze-response-full.json');
}

void main() {
  group('personalized weights', () {
    appTest('past corrections adjust the proposed weights and say so', (
      tester,
      app,
    ) async {
      await openFullResultAfterSeeding(tester, app);

      // Rice has its own factor (220 / 170); the other foods use the global one.
      expect(weightChip('220 g · adjusted'), findsOneWidget);
      expect(weightChip('175 g · adjusted'), findsOneWidget);
      expect(
        find.text('AI estimated 170 g. Adjusted to your usual portions.'),
        findsOneWidget,
      );
      expect(weightChip('170 g · estimate'), findsNothing);
    });

    appTest(
      'accepting the proposal saves the AI estimate and adds no correction',
      (tester, app) async {
        await openFullResultAfterSeeding(tester, app);
        await tapKey(tester, 'saveMeal');
        await pumpUntil(
          tester,
          () => find.byKey(const Key('kcalProgress')).evaluate().isNotEmpty,
        );
        await settle(tester);

        final rice = (await app.itemRows()).firstWhere(
          (i) => i.name == 'Рис' && i.weightG == 220,
        );
        expect(
          (rice.estimatedWeightG, rice.weightG, rice.wasCorrected),
          (170.0, 220.0, false),
        );
        final corrections = await app.real(
          () => app.db.select(app.db.aiCorrections).get(),
        );
        expect(corrections, hasLength(3), reason: 'only the seeded ones');
      },
    );

    appTest('changing the proposal is recorded against the raw AI estimate', (
      tester,
      app,
    ) async {
      await openFullResultAfterSeeding(tester, app);
      await setWeight(tester, weightChip('220 g · adjusted'), '200');
      expect(weightChip('200 g'), findsOneWidget);
      expect(find.textContaining('Adjusted to your usual'), findsNWidgets(3));

      await tapKey(tester, 'saveMeal');
      await pumpUntil(
        tester,
        () => find.byKey(const Key('kcalProgress')).evaluate().isNotEmpty,
      );
      await settle(tester);

      final corrections = await app.real(
        () => app.db.select(app.db.aiCorrections).get(),
      );
      expect(
        corrections.map((c) => (c.aiWeightG, c.userWeightG)),
        contains((170.0, 200.0)),
      );
    });

    appTest('turning the setting off starts from the AI estimates again', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      await seedRiceCorrections(app);
      final settings = await app.settings();
      await app.real(
        () => app.services.settings.save(
          settings.copyWith(personalizePortions: false),
        ),
      );
      await tester.pumpWidget(app.app());
      await settle(tester);
      await openRecognition(tester, 'analyze-response-full.json');

      expect(weightChip('170 g · estimate'), findsOneWidget);
      expect(find.textContaining('Adjusted to your usual'), findsNothing);
    });
  });

  group('recognition result', () {
    appTest(
      'lists the recognized items with estimated weights and an approximate total',
      (tester, app) async {
        await openFullResult(tester, app);

        expect(find.text('Recognized'), findsOneWidget);
        expect(find.text('Рис'), findsOneWidget);
        expect(find.text('Куриная грудка'), findsOneWidget);
        expect(weightChip('170 g · estimate'), findsOneWidget);
        expect(weightChip('135 g · estimate'), findsOneWidget);
        expect(find.text('221 kcal'), findsOneWidget);
        expect(find.byKey(const Key('draftTotal')), findsOneWidget);
        expect(find.text('≈ 470 kcal'), findsOneWidget);
        expect(find.textContaining('Weights are estimates'), findsOneWidget);
        expect(find.byKey(const Key('partialBanner')), findsNothing);
        // Protein 2.7*1.7 + 31*1.35 + 0.7*.8 + .9*.65 = 4.59 + 41.85 + .56 + .585
        expect(find.text('48 g'), findsOneWidget);
      },
    );

    appTest('changing a weight updates the item and all totals immediately', (
      tester,
      app,
    ) async {
      await openFullResult(tester, app);

      await setWeight(tester, weightChip('170 g · estimate'), '150');

      expect(
        weightChip('150 g'),
        findsOneWidget,
        reason: 'an edited weight is no longer labelled as an estimate',
      );
      expect(find.text('195 kcal'), findsOneWidget);
      // 195 + 222.75 + 12 + 11.7 = 441.45
      expect(find.text('≈ 440 kcal'), findsOneWidget);
    });

    appTest('weights outside (0, 5000] are rejected and not applied', (
      tester,
      app,
    ) async {
      await openFullResult(tester, app);
      await tester.tap(weightChip('170 g · estimate'));
      await settle(tester, frames: 8);

      for (final bad in ['0', '5001', '.', '']) {
        await enterKey(tester, 'weightField', bad);
        expect(
          find.text('Enter a weight above 0 and up to 5000 g.'),
          findsOneWidget,
          reason: 'input "$bad"',
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('weightApply')))
              .onPressed,
          isNull,
          reason: 'input "$bad"',
        );
      }
      await enterKey(tester, 'weightField', '5000');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('weightApply')))
            .onPressed,
        isNotNull,
      );
      await tapKey(tester, 'weightCancel');
      await settle(tester, frames: 8);
      expect(
        weightChip('170 g · estimate'),
        findsOneWidget,
        reason: 'cancel keeps the estimate',
      );
    });

    appTest('a weight can be entered in pieces when the food defines them', (
      tester,
      app,
    ) async {
      await openFullResult(tester, app);
      // Cucumber (a catalog food with 120 g per piece) offers pieces.
      await tester.tap(weightChip('80 g · estimate'));
      await settle(tester, frames: 8);
      await tester.tap(find.byKey(const Key('unitDropdown')));
      await settle(tester, frames: 8);
      expect(find.text('pcs'), findsWidgets);
      await tester.tap(find.text('pcs').last);
      await settle(tester, frames: 8);
      await enterKey(tester, 'weightField', '2');
      expect(find.text('= 240 g'), findsOneWidget);
      await tapKey(tester, 'weightApply');
      await settle(tester, frames: 8);
      expect(weightChip('240 g'), findsOneWidget);
    });

    appTest('an item can be removed and totals follow', (tester, app) async {
      await openFullResult(tester, app);

      expect(find.text('≈ 470 kcal'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.delete_outline).last); // tomato
      await settle(tester, frames: 8);
      expect(find.text('Помидор'), findsNothing);
      // 467.45 - 11.7 = 455.75
      expect(find.text('≈ 460 kcal'), findsOneWidget);
    });

    appTest('name and per-100 g values can be edited', (tester, app) async {
      await openFullResult(tester, app);

      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await settle(tester, frames: 10);
      expect(find.text('Edit item'), findsOneWidget);
      await enterKey(tester, 'itemNameField', 'Basmati rice');
      await enterKey(tester, 'kcalPer100Field', '150');
      await tester.pump();
      await tapKey(tester, 'itemApply');
      await settle(tester, frames: 10);

      expect(find.text('Basmati rice'), findsOneWidget);
      expect(find.text('Рис'), findsNothing);
      expect(find.text('255 kcal'), findsOneWidget); // 170 g * 150 / 100
    });

    appTest('the item editor validates name, weight and nutrition', (
      tester,
      app,
    ) async {
      await openFullResult(tester, app);
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await settle(tester, frames: 10);

      bool applyEnabled() =>
          tester
              .widget<FilledButton>(find.byKey(const Key('itemApply')))
              .onPressed !=
          null;
      expect(applyEnabled(), isTrue);
      await enterKey(tester, 'itemNameField', '   ');
      expect(applyEnabled(), isFalse);
      await enterKey(tester, 'itemNameField', 'Rice');
      await enterKey(tester, 'kcalPer100Field', '950');
      expect(
        find.text('Calories must be between 0 and 900 per 100 g.'),
        findsOneWidget,
      );
      expect(applyEnabled(), isFalse);
      await enterKey(tester, 'kcalPer100Field', '130');
      await enterKey(tester, 'fatPer100Field', '150');
      expect(
        find.text('Each value must be between 0 and 100 g.'),
        findsOneWidget,
      );
      expect(applyEnabled(), isFalse);
      await enterKey(tester, 'fatPer100Field', '0.3');
      expect(applyEnabled(), isTrue);
    });

    appTest('a missing item can be added from the food search', (
      tester,
      app,
    ) async {
      await openFullResult(tester, app);

      await tapKey(tester, 'addItem');
      await settle(tester, frames: 10);
      await enterKey(tester, 'foodSearchField', 'olive oil');
      await settle(tester, frames: 15);
      await tester.tap(find.text('Olive oil').first);
      await settle(tester, frames: 10);
      await enterKey(tester, 'weightField', '10');
      await tapKey(tester, 'quantityApply');
      await settle(tester, frames: 10);

      expect(find.text('Olive oil'), findsOneWidget);
      expect(find.text('88 kcal'), findsOneWidget);
      expect(weightChip('10 g'), findsOneWidget);
      // 467.45 + 88.4 = 555.85
      expect(find.text('≈ 560 kcal'), findsOneWidget);
    });

    appTest(
      'low confidence, partial recognition and estimated nutrition are flagged',
      (tester, app) async {
        await app.completeOnboarding();
        await tester.pumpWidget(app.app());
        await settle(tester);
        await openRecognition(tester, 'analyze-response-partial.json');

        expect(find.byKey(const Key('partialBanner')), findsOneWidget);
        expect(
          find.text(
            'Some ingredients may have been missed. Check the result before saving.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Please check'),
          findsOneWidget,
          reason: 'only the 0.35 item is low confidence',
        );
        expect(find.text('Pasta'), findsOneWidget);
      },
    );

    appTest('estimated nutrition gets a note', (tester, app) async {
      await app.completeOnboarding();
      await tester.pumpWidget(app.app());
      await settle(tester);
      await openRecognition(tester, 'analyze-response-estimated.json');

      expect(
        find.text('Nutrition values for this item are estimated.'),
        findsOneWidget,
      );
      expect(find.text("Grandma's special casserole"), findsOneWidget);
      expect(
        find.text('Please check'),
        findsNothing,
        reason: '0.55 is medium confidence',
      );
    });

    appTest('saving is disabled without items', (tester, app) async {
      await openFullResult(tester, app);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byIcon(Icons.delete_outline).first);
        await settle(tester, frames: 6);
      }
      expect(find.byKey(const Key('noItemsHint')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('saveMeal')))
            .onPressed,
        isNull,
      );
    });
  });

  group('saving a recognized meal', () {
    appTest('persists the meal, marks corrections and navigates to the diary', (
      tester,
      app,
    ) async {
      await openFullResult(tester, app);
      await setWeight(tester, weightChip('170 g · estimate'), '150');

      await tapKey(tester, 'saveMeal');
      await pumpUntil(
        tester,
        () => find.byKey(const Key('kcalProgress')).evaluate().isNotEmpty,
      );
      await settle(tester);

      final meals = await app.mealRows();
      expect(meals, hasLength(1));
      expect(meals.single.aiProvider, isNull);
      expect(meals.single.aiModel, isNull);
      expect(meals.single.mealType, 'lunch', reason: '12:30 defaults to lunch');
      expect(meals.single.totalKcal, closeTo(441.45, 1e-6));

      final items = await app.itemRows();
      expect(items, hasLength(4));
      final rice = items.firstWhere((i) => i.name == 'Рис');
      expect(
        (
          rice.estimatedWeightG,
          rice.weightG,
          rice.wasCorrected,
          rice.recognitionSource,
        ),
        (170.0, 150.0, true, 'ai'),
      );
      final chicken = items.firstWhere((i) => i.name == 'Куриная грудка');
      expect(
        (chicken.estimatedWeightG, chicken.weightG, chicken.wasCorrected),
        (135.0, 135.0, false),
      );
      expect(rice.confidence, 0.86);
      final corrections = await app.real(
        () => app.db.select(app.db.aiCorrections).get(),
      );
      expect(corrections.single.aiWeightG, 170);
      expect(corrections.single.userWeightG, 150);
      expect(corrections.single.normalizedFoodName, 'rice');

      expect(find.text('441 / 2200 kcal'), findsOneWidget);
      expect(find.text('Lunch'), findsOneWidget);
      expect(containerOf(tester).read(mealDraftProvider), isNull);
    });

    appTest('manually added items are stored as manual', (tester, app) async {
      await openFullResult(tester, app);
      await tapKey(tester, 'addItem');
      await settle(tester, frames: 10);
      await enterKey(tester, 'foodSearchField', 'olive oil');
      await settle(tester, frames: 15);
      await tester.tap(find.text('Olive oil').first);
      await settle(tester, frames: 10);
      await tapKey(tester, 'quantityApply');
      await settle(tester, frames: 10);

      await tapKey(tester, 'saveMeal');
      await pumpUntil(
        tester,
        () => find.byKey(const Key('kcalProgress')).evaluate().isNotEmpty,
      );

      final items = await app.itemRows();
      final oil = items.firstWhere((i) => i.name == 'Olive oil');
      expect(oil.recognitionSource, 'manual');
      expect(oil.estimatedWeightG, isNull);
      expect(oil.wasCorrected, isFalse);
      expect(oil.weightG, 100);
    });

    appTest('the meal type can be changed before saving', (tester, app) async {
      await openFullResult(tester, app);
      await tester.scrollUntilVisible(
        find.byKey(const Key('mealTypeField')),
        300,
      );
      await tester.ensureVisible(find.byKey(const Key('mealTypeField')));
      await settle(tester, frames: 6);
      await tester.tap(find.byKey(const Key('mealTypeField')));
      await settle(tester, frames: 12);
      await tester.tap(find.text('Dinner').last);
      await settle(tester, frames: 8);
      await tapKey(tester, 'saveMeal');
      await pumpUntil(
        tester,
        () => find.byKey(const Key('kcalProgress')).evaluate().isNotEmpty,
      );

      expect((await app.mealRows()).single.mealType, 'dinner');
    });

    appTest('an unsaved result asks before it is discarded', (
      tester,
      app,
    ) async {
      await openFullResult(tester, app);

      await tester.pageBack();
      await settle(tester, frames: 10);
      expect(find.text('Discard changes?'), findsOneWidget);

      await tapKey(tester, 'keepEditing');
      await settle(tester, frames: 10);
      expect(find.text('Recognized'), findsOneWidget);

      await tester.pageBack();
      await settle(tester, frames: 10);
      await tapKey(tester, 'discardChanges');
      await settle(tester, frames: 15);
      expect(find.text('Recognized'), findsNothing);
      expect(await app.mealRows(), isEmpty);
      expect(containerOf(tester).read(mealDraftProvider), isNull);
    });
  });

  group('manual entry', () {
    appTest('adds a food by search and saves it offline', (tester, app) async {
      await app.completeOnboarding();
      await tester.pumpWidget(app.app());
      await settle(tester);
      await tapKey(tester, 'addMeal');
      await settle(tester, frames: 10);
      await tapKey(tester, 'addManually');
      await settle(tester, frames: 15);

      expect(find.text('New meal'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('saveMeal')))
            .onPressed,
        isNull,
      );
      await tapKey(tester, 'addItem');
      await settle(tester, frames: 10);
      await enterKey(tester, 'foodSearchField', 'греч');
      await settle(tester, frames: 15);
      await tester.tap(find.text('Buckwheat').first);
      await settle(tester, frames: 10);
      await enterKey(tester, 'weightField', '200');
      await tapKey(tester, 'quantityApply');
      await settle(tester, frames: 10);

      // Manual totals are exact, not approximate: 200 g * 92 / 100.
      expect(find.text('184 kcal'), findsWidgets);
      expect(find.textContaining('≈'), findsNothing);
      await tapKey(tester, 'saveMeal');
      await pumpUntil(
        tester,
        () => find.byKey(const Key('kcalProgress')).evaluate().isNotEmpty,
      );

      expect(find.text('184 / 2200 kcal'), findsOneWidget);
      final item = (await app.itemRows()).single;
      expect(
        (
          item.name,
          item.weightG,
          item.recognitionSource,
          item.estimatedWeightG,
        ),
        ('Buckwheat', 200.0, 'manual', null),
      );
    });

    appTest('a custom product is validated and stored for later searches', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      await tester.pumpWidget(app.app());
      await settle(tester);
      containerOf(tester).read(mealDraftProvider.notifier).startManual();
      await push(tester, '/meal/new');
      await tapKey(tester, 'addItem');
      await settle(tester, frames: 10);
      await tapKey(tester, 'createCustomProduct');
      await settle(tester, frames: 10);

      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('customCreate')))
            .onPressed,
        isNull,
      );
      await enterKey(tester, 'customNameField', 'Protein bar');
      await enterKey(tester, 'customKcalField', '380');
      await enterKey(tester, 'customFatField', '150');
      expect(
        find.text('Each value must be between 0 and 100 g.'),
        findsWidgets,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('customCreate')))
            .onPressed,
        isNull,
      );
      await enterKey(tester, 'customFatField', '12');
      await enterKey(tester, 'customProteinField', '30');
      await enterKey(tester, 'customCarbsField', '40');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('customCreate')))
            .onPressed,
        isNotNull,
      );
      await tapKey(tester, 'customCreate');
      await settle(tester, frames: 15);
      await tapKey(tester, 'quantityApply');
      await settle(tester, frames: 10);

      expect(find.text('Protein bar'), findsOneWidget);
      final foods = await app.foodRows();
      expect(foods.where((f) => f.source == 'user').single.name, 'Protein bar');
    });
  });
}
