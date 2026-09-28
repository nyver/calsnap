import 'package:calsnap/core/di/providers.dart';
import 'package:calsnap/core/domain/nutrition.dart';
import 'package:calsnap/features/barcode/domain/packaged_product.dart';
import 'package:calsnap/features/barcode/domain/product_lookup.dart';
import 'package:calsnap/features/meal/domain/meal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../support/fixtures.dart';

DateTime at(int h, [int m = 0, int day = 10]) => DateTime(2026, 3, day, h, m);

/// A saved lunch: corrected rice (170 -> 150 g) and 30 g of manual bread.
Future<String> seedLunch(TestApp app) => app.saveMeal(
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
);

/// A [ProductSource] that fails every call, so a test can assert it was
/// never used.
class _FailingProductSource implements ProductSource {
  @override
  Future<PackagedProduct> fetch(String barcode, {required String locale}) =>
      throw StateError('no network call expected');
}

void main() {
  group('diary -> add sheet -> Eat this again', () {
    appTest('picking a meal, editing a weight and saving creates a second, '
        'independent meal', (tester, app) async {
      await app.completeOnboarding();
      final sourceId = await seedLunch(app);
      await tester.pumpWidget(app.app());
      await settle(tester);

      await tapKey(tester, 'addMeal');
      await settle(tester, frames: 10);
      await tapKey(tester, 'addEatAgain');
      await settle(tester, frames: 15);
      expect(find.text('Recent meals'), findsOneWidget);

      await tapKey(tester, 'repeatMeal-$sourceId');
      await settle(tester, frames: 15);
      expect(find.text('Eat this again'), findsOneWidget);
      expect(find.text('Rice'), findsOneWidget);
      expect(find.text('Bread'), findsOneWidget);

      await tester.tap(find.widgetWithText(ActionChip, '150 g'));
      await settle(tester, frames: 10);
      await enterKey(tester, 'weightField', '200');
      await tapKey(tester, 'weightApply');
      await settle(tester, frames: 10);

      await tapKey(tester, 'saveMeal');
      await pumpUntil(
        tester,
        () => find.byKey(const Key('kcalProgress')).evaluate().isNotEmpty,
      );
      await settle(tester);

      expect(find.text('Meal added'), findsOneWidget);
      expect(await app.mealRows(), hasLength(2));

      final source = (await app.getMeal(sourceId))!;
      expect(
        source.items.singleWhere((i) => i.id == 'rice').weightG,
        150,
        reason: 'the source meal is untouched',
      );
      final repeated = (await app.mealRows()).firstWhere(
        (m) => m.id != sourceId,
      );
      final repeatedItems = await app.itemRows();
      final repeatedRice = repeatedItems.firstWhere(
        (i) => i.mealId == repeated.id && i.name == 'Rice',
      );
      expect(repeatedRice.weightG, 200);
      expect(repeatedRice.recognitionSource, 'manual');
    });
  });

  group('diary card menu -> repeat', () {
    appTest('opens the editor with a cloned draft', (tester, app) async {
      await app.completeOnboarding();
      final sourceId = await seedLunch(app);
      await tester.pumpWidget(app.app());
      await settle(tester);

      await tester.tap(find.byKey(Key('mealMenu-$sourceId')));
      await settle(tester, frames: 8);
      await tester.tap(find.text('Eat this again').last);
      await settle(tester, frames: 15);

      expect(find.text('Eat this again'), findsOneWidget);
      expect(find.text('Rice'), findsOneWidget);
      expect(find.text('Bread'), findsOneWidget);
    });
  });

  group('edit screen -> Eat this again', () {
    appTest(
      'unsaved edits are discarded first, and the repeat is built from the '
      'saved state',
      (tester, app) async {
        await app.completeOnboarding();
        final sourceId = await seedLunch(app);
        await tester.pumpWidget(app.app());
        await settle(tester);
        await tester.tap(find.byKey(Key('meal-$sourceId')));
        await settle(tester, frames: 20);

        // An unsaved edit: remove the bread item.
        await tester.tap(find.byKey(const Key('remove-bread')));
        await settle(tester, frames: 8);
        expect(find.text('Bread'), findsNothing);

        await tapKey(tester, 'eatAgainButton');
        await settle(tester, frames: 10);
        expect(find.text('Discard changes?'), findsOneWidget);
        await tapKey(tester, 'discardChanges');
        await settle(tester, frames: 15);

        expect(find.text('Eat this again'), findsOneWidget);
        // The repeat draft is built from the last saved state, not the
        // discarded edit: both items are present.
        expect(find.text('Rice'), findsOneWidget);
        expect(find.text('Bread'), findsOneWidget);

        // The saved source meal itself is unchanged.
        final source = (await app.getMeal(sourceId))!;
        expect(source.items, hasLength(2));
      },
    );
  });

  group('leaving a repeat draft', () {
    appTest('Back with discard creates no meal', (tester, app) async {
      await app.completeOnboarding();
      final sourceId = await seedLunch(app);
      await tester.pumpWidget(app.app());
      await settle(tester);
      await push(tester, '/meal/repeat');
      await tapKey(tester, 'repeatMeal-$sourceId');
      await settle(tester, frames: 15);
      expect(find.text('Eat this again'), findsOneWidget);

      await tester.pageBack();
      await settle(tester, frames: 15);
      expect(find.text('Discard changes?'), findsOneWidget);
      await tapKey(tester, 'discardChanges');
      await settle(tester, frames: 15);

      expect(await app.mealRows(), hasLength(1), reason: 'only the source');
    });
  });

  group('balanced plate', () {
    appTest('the plate card is shown for a repeat of classified foods', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      await app.real(() => app.services.foods.seedCatalog(readCatalogJson()));
      final sourceId = await app.saveMeal(
        draftOf([
          aiItem('rice', estimated: 170, weight: 170),
          aiItem(
            'chicken',
            name: 'Chicken breast',
            normalized: 'chicken_breast',
            estimated: 150,
            weight: 150,
            per100: const Nutrition(kcal: 165, protein: 31, fat: 3.6),
          ),
        ], time: at(13)),
      );
      await tester.pumpWidget(app.app());
      await settle(tester);
      await push(tester, '/meal/repeat');
      await tapKey(tester, 'repeatMeal-$sourceId');
      await settle(tester, frames: 15);

      await tester.scrollUntilVisible(
        find.byKey(const Key('balancedPlateCard')),
        300,
      );
      expect(find.byKey(const Key('balancedPlateCard')), findsOneWidget);
    });
  });

  group('offline', () {
    appTest('no analysis or product request is made anywhere in the flow', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      final sourceId = await seedLunch(app);
      final failingAnalysis = FakeAnalysisApi(
        (_) async => throw StateError('no network call expected'),
      );
      await tester.pumpWidget(
        app.app(
          overrides: [
            analysisApiProvider.overrideWithValue(failingAnalysis),
            productSourceProvider.overrideWithValue(_FailingProductSource()),
          ],
        ),
      );
      await settle(tester);
      await push(tester, '/meal/repeat');
      await tapKey(tester, 'repeatMeal-$sourceId');
      await settle(tester, frames: 15);

      await tester.tap(find.widgetWithText(ActionChip, '150 g'));
      await settle(tester, frames: 10);
      await enterKey(tester, 'weightField', '160');
      await tapKey(tester, 'weightApply');
      await settle(tester, frames: 10);
      await tapKey(tester, 'saveMeal');
      await pumpUntil(
        tester,
        () => find.byKey(const Key('kcalProgress')).evaluate().isNotEmpty,
      );

      expect(failingAnalysis.calls, isEmpty);
      expect(await app.mealRows(), hasLength(2));
    });
  });
}
