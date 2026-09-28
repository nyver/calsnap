import 'package:calsnap/core/di/providers.dart';
import 'package:calsnap/core/domain/nutrition.dart';
import 'package:calsnap/features/balanced_plate/domain/plate_group.dart';
import 'package:calsnap/features/foods/domain/food.dart';
import 'package:calsnap/features/meal/ui/meal_draft_notifier.dart';
import 'package:calsnap/features/meal/ui/plate_analysis_provider.dart';
import 'package:calsnap/features/recognition/domain/analysis.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';

RecognizedItem recognized(
  String id,
  String normalizedName, {
  String name = 'Item',
  double weightG = 150,
  String nutritionSource = 'catalog',
  Nutrition per100 = const Nutrition(kcal: 100, protein: 5, fat: 5, carbs: 10),
}) => RecognizedItem(
  id: id,
  name: name,
  normalizedName: normalizedName,
  estimatedWeightG: weightG,
  confidence: 0.9,
  nutritionSource: nutritionSource,
  per100: per100,
);

void main() {
  appTest('a recognized catalog item resolves to its group', (
    tester,
    app,
  ) async {
    await tester.pumpWidget(app.app());
    await settle(tester);
    final container = containerOf(tester);
    await app.real(
      () => container
          .read(mealDraftProvider.notifier)
          .startFromRecognition(
            AnalysisResult(
              requestId: 'r1',
              items: [
                recognized('temp-1', 'chicken_breast', name: 'Chicken breast'),
              ],
              warnings: const {},
            ),
          ),
    );
    final draft = container.read(mealDraftProvider)!;
    expect(draft.items.single.plateGroup, PlateGroup.protein);
  });

  appTest('an ai_estimate item without a catalog match is unknown', (
    tester,
    app,
  ) async {
    await tester.pumpWidget(app.app());
    await settle(tester);
    final container = containerOf(tester);
    await app.real(
      () => container
          .read(mealDraftProvider.notifier)
          .startFromRecognition(
            AnalysisResult(
              requestId: 'r1',
              items: [
                recognized(
                  'temp-1',
                  'grandmas_special_casserole',
                  name: "Grandma's special casserole",
                  nutritionSource: 'ai_estimate',
                ),
              ],
              warnings: const {},
            ),
          ),
    );
    final draft = container.read(mealDraftProvider)!;
    expect(draft.items.single.plateGroup, PlateGroup.unknown);
  });

  appTest('replacing a food changes the group, including back to unknown', (
    tester,
    app,
  ) async {
    await tester.pumpWidget(app.app());
    await settle(tester);
    final container = containerOf(tester);
    final notifier = container.read(mealDraftProvider.notifier);
    notifier.startManual();

    final chicken = (await app.real(
      () => app.services.foods.search('chicken breast'),
    )).firstWhere((f) => f.normalizedName == 'chicken_breast');
    notifier.addFood(chicken, 150);
    final itemId = container.read(mealDraftProvider)!.items.single.id;
    expect(
      container.read(mealDraftProvider)!.items.single.plateGroup,
      PlateGroup.protein,
    );

    final broccoli = (await app.real(
      () => app.services.foods.search('broccoli'),
    )).firstWhere((f) => f.normalizedName == 'broccoli');
    notifier.replaceFood(itemId, broccoli);
    expect(
      container.read(mealDraftProvider)!.items.single.plateGroup,
      PlateGroup.vegetable,
    );

    final custom = await app.real(
      () => app.services.foods.createCustom(
        const CustomFoodInput(
          name: 'Homemade mix',
          per100: Nutrition(kcal: 300),
        ),
      ),
    );
    notifier.replaceFood(itemId, custom);
    expect(
      container.read(mealDraftProvider)!.items.single.plateGroup,
      PlateGroup.unknown,
    );
  });

  appTest(
    'a saved meal reopened resolves plate groups locally, without any API call',
    (tester, app) async {
      await tester.pumpWidget(app.app());
      await settle(tester);
      final container = containerOf(tester);
      final notifier = container.read(mealDraftProvider.notifier);
      await app.real(
        () => notifier.startFromRecognition(
          AnalysisResult(
            requestId: 'r1',
            items: [
              recognized('temp-1', 'chicken_breast', name: 'Chicken breast'),
            ],
            warnings: const {},
          ),
        ),
      );
      final mealId = await app.saveMeal(container.read(mealDraftProvider)!);
      notifier.clear();

      final failingApi = FakeAnalysisApi(
        (_) async => throw StateError('no network call expected'),
      );
      final reopenedContainer = ProviderContainer(
        overrides: [
          ...app.baseOverrides(),
          analysisApiProvider.overrideWithValue(failingApi),
        ],
      );
      addTearDown(reopenedContainer.dispose);
      final reopened = reopenedContainer.read(mealDraftProvider.notifier);
      final found = await app.real(() => reopened.startEdit(mealId));
      expect(found, isTrue);
      expect(failingApi.calls, isEmpty);
      final draft = reopenedContainer.read(mealDraftProvider)!;
      expect(draft.items.single.plateGroup, PlateGroup.protein);
    },
  );

  appTest(
    'a reopened ai_estimate item keeps the group of its catalog namesake',
    (tester, app) async {
      await tester.pumpWidget(app.app());
      await settle(tester);
      final container = containerOf(tester);
      final notifier = container.read(mealDraftProvider.notifier);
      await app.real(
        () => notifier.startFromRecognition(
          AnalysisResult(
            requestId: 'r1',
            items: [
              recognized(
                'temp-1',
                'chicken_breast',
                name: 'Chicken breast',
                nutritionSource: 'ai_estimate',
              ),
            ],
            warnings: const {},
          ),
        ),
      );
      expect(
        container.read(mealDraftProvider)!.items.single.plateGroup,
        PlateGroup.protein,
      );
      final mealId = await app.saveMeal(container.read(mealDraftProvider)!);
      notifier.clear();

      await app.real(() => notifier.startEdit(mealId));
      final edited = container.read(mealDraftProvider)!.items.single;
      expect(edited.plateGroup, PlateGroup.protein);
      notifier.clear();

      await app.real(() => notifier.startRepeat(mealId));
      final repeated = container.read(mealDraftProvider)!.items.single;
      expect(repeated.plateGroup, PlateGroup.protein);
    },
  );

  appTest(
    'a weight edit updates the plate analysis immediately, with no repository call',
    (tester, app) async {
      await tester.pumpWidget(app.app());
      await settle(tester);
      final container = containerOf(tester);
      final notifier = container.read(mealDraftProvider.notifier);
      notifier.startManual();
      final chicken = (await app.real(
        () => app.services.foods.search('chicken breast'),
      )).firstWhere((f) => f.normalizedName == 'chicken_breast');
      final broccoli = (await app.real(
        () => app.services.foods.search('broccoli'),
      )).firstWhere((f) => f.normalizedName == 'broccoli');
      notifier.addFood(broccoli, 50);
      notifier.addFood(chicken, 150);

      final before = container.read(plateAnalysisProvider)!;
      expect(before.vegetableFruitRatio, closeTo(50 / 200, 1e-9));

      // Pure state mutation: no await, so any hidden async I/O would show up
      // as a pending future rather than an immediate provider update.
      final itemId = container.read(mealDraftProvider)!.items.first.id;
      notifier.setWeight(itemId, 150);

      final after = container.read(plateAnalysisProvider)!;
      expect(after.vegetableFruitRatio, closeTo(150 / 300, 1e-9));
    },
  );
}
