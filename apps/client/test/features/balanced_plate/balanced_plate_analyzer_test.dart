import 'package:calsnap/features/balanced_plate/domain/balanced_plate_analyzer.dart';
import 'package:calsnap/features/balanced_plate/domain/plate_analysis.dart';
import 'package:calsnap/features/balanced_plate/domain/plate_group.dart';
import 'package:flutter_test/flutter_test.dart';

const analyzer = BalancedPlateAnalyzer();

PlatePortion portion(
  PlateGroup group,
  double weightG, {
  PlateQuality? quality,
}) => PlatePortion(group: group, quality: quality, weightG: weightG);

void main() {
  group('BalancedPlateAnalyzer.analyze', () {
    test('balanced 200/100/100 has equal ratios and no recommendation', () {
      final a = analyzer.analyze([
        portion(PlateGroup.vegetable, 200),
        portion(PlateGroup.protein, 100),
        portion(PlateGroup.complexCarbohydrate, 100),
      ]);
      expect(a.vegetableFruitRatio, closeTo(0.50, 1e-9));
      expect(a.proteinRatio, closeTo(0.25, 1e-9));
      expect(a.complexCarbohydrateRatio, closeTo(0.25, 1e-9));
      expect(a.verdict, PlateVerdict.nicelyBalanced);
      expect(a.recommendations, isEmpty);
    });

    test('healthy fat does not distort ratios but is reported present', () {
      final a = analyzer.analyze([
        portion(PlateGroup.vegetable, 200),
        portion(PlateGroup.protein, 100),
        portion(PlateGroup.complexCarbohydrate, 100),
        portion(PlateGroup.healthyFat, 20),
      ]);
      expect(a.eligibleWeightG, 400);
      expect(a.vegetableFruitRatio, closeTo(0.50, 1e-9));
      expect(a.proteinRatio, closeTo(0.25, 1e-9));
      expect(a.complexCarbohydrateRatio, closeTo(0.25, 1e-9));
      expect(a.healthyFatPresent, isTrue);
    });

    test('healthy fat at or below the 3 g threshold is not present', () {
      final a = analyzer.analyze([
        portion(PlateGroup.vegetable, 200),
        portion(PlateGroup.protein, 100),
        portion(PlateGroup.complexCarbohydrate, 100),
        portion(PlateGroup.healthyFat, 3),
      ]);
      expect(a.healthyFatPresent, isFalse);
    });

    test('invalid, zero and NaN weights are ignored', () {
      final a = analyzer.analyze([
        portion(PlateGroup.vegetable, 200),
        portion(PlateGroup.protein, 100),
        portion(PlateGroup.complexCarbohydrate, 100),
        portion(PlateGroup.protein, 0),
        portion(PlateGroup.protein, -50),
        portion(PlateGroup.protein, double.nan),
        portion(PlateGroup.protein, double.infinity),
      ]);
      expect(a.eligibleWeightG, 400);
      expect(a.proteinRatio, closeTo(0.25, 1e-9));
    });

    test('an empty meal is insufficient data', () {
      final a = analyzer.analyze(const []);
      expect(a.verdict, PlateVerdict.insufficientData);
      expect(a.recommendations, isEmpty);
      expect(a.isAnalyzable, isFalse);
    });

    test('an all-unknown meal is insufficient data', () {
      final a = analyzer.analyze([portion(PlateGroup.unknown, 500)]);
      expect(a.verdict, PlateVerdict.insufficientData);
    });

    test(
      'a 60 g snack is insufficient data (below the eligible-weight floor)',
      () {
        final a = analyzer.analyze([portion(PlateGroup.fruit, 60)]);
        expect(a.verdict, PlateVerdict.insufficientData);
        expect(a.recommendations, isEmpty);
      },
    );

    test(
      '200 g classified + 300 g unknown has 0.40 coverage: insufficient data',
      () {
        final a = analyzer.analyze([
          portion(PlateGroup.protein, 200),
          portion(PlateGroup.unknown, 300),
        ]);
        expect(a.verdict, PlateVerdict.insufficientData);
      },
    );

    test('a mixed dish counts as unclassified, not as a single group', () {
      final a = analyzer.analyze([
        portion(PlateGroup.other, 400, quality: PlateQuality.mixed),
      ]);
      expect(a.verdict, PlateVerdict.insufficientData);
    });

    test('a drink classified other (not mixed) does not reduce coverage', () {
      final a = analyzer.analyze([
        portion(PlateGroup.vegetable, 200),
        portion(PlateGroup.protein, 100),
        portion(PlateGroup.complexCarbohydrate, 100),
        portion(PlateGroup.other, 300),
      ]);
      expect(a.coverage, 1.0);
      expect(a.verdict, PlateVerdict.nicelyBalanced);
    });

    test('dairy is excluded from the eligible weight', () {
      final a = analyzer.analyze([
        portion(PlateGroup.vegetable, 200),
        portion(PlateGroup.protein, 100),
        portion(PlateGroup.complexCarbohydrate, 100),
        portion(PlateGroup.dairy, 500),
      ]);
      expect(a.eligibleWeightG, 400);
    });

    // BALANCED_PLATE.md Example A: 180 g broccoli, 70 g tomato, 120 g chicken
    // breast, 120 g buckwheat, 8 g olive oil.
    test('Example A is nicely balanced with no recommendations', () {
      final a = analyzer.analyze([
        portion(PlateGroup.vegetable, 180),
        portion(PlateGroup.vegetable, 70),
        portion(PlateGroup.protein, 120),
        portion(PlateGroup.complexCarbohydrate, 120),
        portion(PlateGroup.healthyFat, 8),
      ]);
      expect(a.verdict, PlateVerdict.nicelyBalanced);
      expect(a.recommendations, isEmpty);
      expect(a.healthyFatPresent, isTrue);

      final (veg, protein, carb) = a.displayPercents();
      expect(veg + protein + carb, 100);
    });

    // BALANCED_PLATE.md §32 Example C: an unknown mixed dish.
    test('Example C (unknown homemade casserole) is insufficient data', () {
      final a = analyzer.analyze([portion(PlateGroup.unknown, 400)]);
      expect(a.verdict, PlateVerdict.insufficientData);
      expect(a.recommendations, isEmpty);
    });
  });

  group('PlateAnalysis.displayPercents', () {
    test('sums to 100 for Example A', () {
      final a = analyzer.analyze([
        portion(PlateGroup.vegetable, 180),
        portion(PlateGroup.vegetable, 70),
        portion(PlateGroup.protein, 120),
        portion(PlateGroup.complexCarbohydrate, 120),
        portion(PlateGroup.healthyFat, 8),
      ]);
      final (veg, protein, carb) = a.displayPercents();
      expect(veg + protein + carb, 100);
    });

    test('is (0, 0, 0) when not analyzable', () {
      final a = analyzer.analyze(const []);
      expect(a.displayPercents(), (0, 0, 0));
    });
  });
}
