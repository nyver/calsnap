import 'package:calsnap/core/domain/nutrition.dart';
import 'package:calsnap/features/meal/domain/meal.dart';
import 'package:calsnap/features/meal/domain/meal_draft.dart';
import 'package:calsnap/features/meal/domain/portion_calibration.dart';
import 'package:flutter_test/flutter_test.dart';

const buckwheat = Nutrition(kcal: 110, protein: 3.4, fat: 0.6, carbs: 21);
const chicken = Nutrition(kcal: 165, protein: 31, fat: 3.6);
const rice = Nutrition(kcal: 130, protein: 2.7, fat: 0.3, carbs: 28);

var _clock = 0;

CorrectionSample sample(
  String name,
  double ai,
  double user, {
  PortionCategory? category,
  int? at,
}) => CorrectionSample(
  normalizedName: name,
  aiWeightG: ai,
  userWeightG: user,
  createdAtMs: at ?? _clock++,
  category: category,
);

void main() {
  setUp(() => _clock = 0);

  group('PortionCategory.of', () {
    test('classifies typical foods', () {
      expect(PortionCategory.of(buckwheat), PortionCategory.carb);
      expect(PortionCategory.of(rice), PortionCategory.carb);
      expect(PortionCategory.of(chicken), PortionCategory.protein);
      expect(
        PortionCategory.of(const Nutrition(kcal: 884, fat: 100)),
        PortionCategory.fat,
      );
      expect(
        PortionCategory.of(
          const Nutrition(kcal: 15, protein: 0.7, fat: 0.1, carbs: 3),
        ),
        PortionCategory.light,
      );
      expect(
        PortionCategory.of(
          const Nutrition(kcal: 266, protein: 11, fat: 10, carbs: 33),
        ),
        PortionCategory.mixed,
      );
    });

    test('a food without macros is mixed', () {
      expect(
        PortionCategory.of(const Nutrition(kcal: 100)),
        PortionCategory.mixed,
      );
    });
  });

  group('the food level', () {
    test(
      '180 corrected to 240, 170 to 220 and 200 to 250 yields about 1.3',
      () {
        final calibration = PortionCalibration([
          sample('buckwheat', 180, 240),
          sample('buckwheat', 170, 220),
          sample('buckwheat', 200, 250),
        ]);
        final adjustment = calibration.adjustmentFor(
          normalizedName: 'buckwheat',
          per100: buckwheat,
        )!;
        // Mean ratio 1.29; the newest correction weighs a little more.
        expect(adjustment.factor, closeTo(1.29, 0.03));
        expect(adjustment.scope, PortionScope.food);
        expect(adjustment.sampleCount, 3);
        expect(adjustment.apply(190), closeTo(246, 4));
      },
    );

    test('nothing is applied before three corrections', () {
      final calibration = PortionCalibration([
        sample('buckwheat', 180, 240),
        sample('buckwheat', 170, 220),
      ]);
      expect(
        calibration.adjustmentFor(
          normalizedName: 'buckwheat',
          per100: buckwheat,
        ),
        isNull,
      );
    });

    test('newer corrections weigh more than older ones', () {
      final drifting = PortionCalibration([
        for (var i = 0; i < 6; i++) sample('rice', 100, 150),
        for (var i = 0; i < 6; i++) sample('rice', 100, 100),
        for (var i = 0; i < 3; i++) sample('rice', 100, 80),
      ]);
      final adjustment = drifting.adjustmentFor(
        normalizedName: 'rice',
        per100: rice,
      )!;
      expect(adjustment.factor, lessThan(1));
    });

    test('order comes from the timestamp, not from the input order', () {
      final samples = [
        sample('rice', 100, 150, at: 1),
        sample('rice', 100, 150, at: 2),
        sample('rice', 100, 150, at: 3),
        sample('rice', 100, 60, at: 4),
        sample('rice', 100, 60, at: 5),
      ];
      final a = PortionCalibration(samples)
          .adjustmentFor(normalizedName: 'rice', per100: rice);
      final b = PortionCalibration(samples.reversed)
          .adjustmentFor(normalizedName: 'rice', per100: rice);
      expect(a!.factor, b!.factor);
    });

    test('the factor is clamped to 0.6 .. 1.6', () {
      final big = PortionCalibration([
        for (var i = 0; i < 4; i++) sample('rice', 100, 300),
      ]);
      final small = PortionCalibration([
        for (var i = 0; i < 4; i++) sample('rice', 100, 20),
      ]);
      expect(
        big.adjustmentFor(normalizedName: 'rice', per100: rice)!.factor,
        PortionCalibration.maxFactor,
      );
      expect(
        small.adjustmentFor(normalizedName: 'rice', per100: rice)!.factor,
        PortionCalibration.minFactor,
      );
    });

    test('one typo does not dominate the average', () {
      // 1800 g instead of 180 g counts as at most 4x, then the clamp applies.
      final calibration = PortionCalibration([
        sample('rice', 180, 180),
        sample('rice', 180, 180),
        sample('rice', 180, 1800),
      ]);
      final factor = calibration
          .adjustmentFor(normalizedName: 'rice', per100: rice)!
          .factor;
      expect(factor, lessThan(1.6 + 1e-9));
      expect(factor, closeTo(1.5, 0.15));
    });

    test('unusable samples are ignored', () {
      final calibration = PortionCalibration([
        sample('rice', 0, 100),
        sample('rice', 100, 0),
        sample('rice', double.nan, 100),
        sample('rice', 100, double.infinity),
        sample('rice', 100, 150),
        sample('rice', 100, 150),
      ]);
      expect(
        calibration.adjustmentFor(normalizedName: 'rice', per100: rice),
        isNull,
        reason: 'only two usable samples',
      );
    });

    test('a factor close to 1 changes nothing', () {
      final calibration = PortionCalibration([
        for (var i = 0; i < 4; i++) sample('rice', 100, 103),
      ]);
      expect(
        calibration.adjustmentFor(normalizedName: 'rice', per100: rice),
        isNull,
      );
    });

    test('whole grams', () {
      const adjustment = PortionAdjustment(
        factor: 1.263,
        scope: PortionScope.food,
        sampleCount: 3,
      );
      expect(adjustment.apply(190), 240);
    });
  });

  group('falling back', () {
    // Corrections of rice, pasta and potatoes: side dishes that are usually
    // bigger than the AI thinks.
    final sides = [
      for (final name in ['rice', 'pasta', 'potato'])
        sample(name, 150, 210, category: PortionCategory.carb),
    ];

    test('an unseen food of the same category uses the category factor', () {
      final adjustment = PortionCalibration(sides)
          .adjustmentFor(normalizedName: 'buckwheat', per100: buckwheat)!;
      expect(adjustment.scope, PortionScope.category);
      expect(adjustment.factor, closeTo(1.4, 0.01));
      expect(adjustment.sampleCount, 3);
    });

    test('a food of another category uses the global factor', () {
      final calibration = PortionCalibration([
        ...sides,
        sample('rice', 150, 210, category: PortionCategory.carb),
      ]);
      final adjustment = calibration.adjustmentFor(
        normalizedName: 'chicken_breast',
        per100: chicken,
      )!;
      expect(adjustment.scope, PortionScope.global);
      expect(adjustment.sampleCount, 4);
    });

    test('the food level beats the category level', () {
      final calibration = PortionCalibration([
        ...sides,
        for (var i = 0; i < 3; i++)
          sample('buckwheat', 150, 120, category: PortionCategory.carb),
      ]);
      final adjustment = calibration.adjustmentFor(
        normalizedName: 'buckwheat',
        per100: buckwheat,
      )!;
      expect(adjustment.scope, PortionScope.food);
      expect(adjustment.factor, closeTo(0.8, 0.01));
    });

    test('a food that agrees with the AI is not pushed by the category', () {
      final calibration = PortionCalibration([
        ...sides,
        for (var i = 0; i < 3; i++)
          sample('buckwheat', 150, 150, category: PortionCategory.carb),
      ]);
      expect(
        calibration.adjustmentFor(
          normalizedName: 'buckwheat',
          per100: buckwheat,
        ),
        isNull,
      );
    });

    test('an empty history adjusts nothing', () {
      expect(
        PortionCalibration(const [])
            .adjustmentFor(normalizedName: 'rice', per100: rice),
        isNull,
      );
    });
  });

  group('DraftItem corrections against a personalized proposal', () {
    DraftItem personalized() => const DraftItem(
      id: 'i',
      name: 'Rice',
      weightG: 220,
      per100: Nutrition(kcal: 130),
      source: RecognitionSource.ai,
      estimatedWeightG: 170,
      suggestedWeightG: 220,
      adjustment: PortionAdjustment(
        factor: 1.3,
        scope: PortionScope.food,
        sampleCount: 3,
      ),
      originalName: 'Rice',
      originalPer100: Nutrition(kcal: 130),
    );

    test('accepting the proposal is not a correction', () {
      final item = personalized();
      expect(item.weightCorrected, isFalse);
      expect(item.wasCorrected, isFalse);
      expect(item.isPersonalized, isTrue);
    });

    test('any other weight is one, including the raw AI estimate', () {
      expect(personalized().copyWith(weightG: 200).weightCorrected, isTrue);
      final back = personalized().copyWith(weightG: 170);
      expect(back.weightCorrected, isTrue);
      expect(back.isPersonalized, isFalse);
    });

    test('an untouched item without a proposal still compares to the AI', () {
      const item = DraftItem(
        id: 'i',
        name: 'Rice',
        weightG: 170,
        per100: Nutrition(kcal: 130),
        source: RecognitionSource.ai,
        estimatedWeightG: 170,
        originalName: 'Rice',
        originalPer100: Nutrition(kcal: 130),
      );
      expect(item.weightCorrected, isFalse);
      expect(item.copyWith(weightG: 150).weightCorrected, isTrue);
    });
  });
}
