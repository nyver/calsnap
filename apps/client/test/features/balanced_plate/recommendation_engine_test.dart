import 'package:calsnap/features/balanced_plate/domain/balanced_plate_analyzer.dart';
import 'package:calsnap/features/balanced_plate/domain/plate_analysis.dart';
import 'package:calsnap/features/balanced_plate/domain/plate_group.dart';
import 'package:flutter_test/flutter_test.dart';

const analyzer = BalancedPlateAnalyzer();

PlatePortion portion(PlateGroup group, double weightG) =>
    PlatePortion(group: group, weightG: weightG);

List<PlateRecommendationType> recTypes(PlateAnalysis a) =>
    a.recommendations.map((r) => r.type).toList();

void main() {
  group('recommendation rules', () {
    test('low vegetables (< 0.30) recommends adding vegetables', () {
      final a = analyzer.analyze([
        portion(PlateGroup.vegetable, 50),
        portion(PlateGroup.protein, 150),
        portion(PlateGroup.complexCarbohydrate, 200),
      ]);
      expect(recTypes(a), [PlateRecommendationType.addVegetables]);
      expect(a.verdict, PlateVerdict.improvable);
    });

    test('low protein (< 0.15) recommends adding a protein source', () {
      final a = analyzer.analyze([
        portion(PlateGroup.vegetable, 200),
        portion(PlateGroup.protein, 30),
        portion(PlateGroup.complexCarbohydrate, 170),
      ]);
      expect(recTypes(a), [PlateRecommendationType.addProtein]);
      expect(a.verdict, PlateVerdict.improvable);
    });

    test(
      'carbohydrate dominance: 50/50/300 recommends exactly addVegetables '
      'then reduceCarbohydrateDominance (addProtein dropped by the limit)',
      () {
        final a = analyzer.analyze([
          portion(PlateGroup.vegetable, 50),
          portion(PlateGroup.protein, 50),
          portion(PlateGroup.complexCarbohydrate, 300),
        ]);
        expect(recTypes(a), [
          PlateRecommendationType.addVegetables,
          PlateRecommendationType.reduceCarbohydrateDominance,
        ]);
      },
    );

    // BALANCED_PLATE.md §32 Example B — pasta-heavy.
    test('Example B (pasta-heavy) recommends vegetables then reducing carb dominance', () {
      final a = analyzer.analyze([
        portion(PlateGroup.complexCarbohydrate, 300),
        portion(PlateGroup.protein, 80),
        portion(PlateGroup.vegetable, 40),
      ]);
      expect(recTypes(a), [
        PlateRecommendationType.addVegetables,
        PlateRecommendationType.reduceCarbohydrateDominance,
      ]);
    });

    test('low complex carbohydrates is optional and only fires alone', () {
      final a = analyzer.analyze([
        portion(PlateGroup.vegetable, 300),
        portion(PlateGroup.protein, 150),
        portion(PlateGroup.complexCarbohydrate, 20),
      ]);
      expect(recTypes(a), [PlateRecommendationType.addComplexCarbohydrates]);
    });

    test(
      'the tolerant zone (350/100/50) shows no corrective recommendation',
      () {
        final a = analyzer.analyze([
          portion(PlateGroup.vegetable, 350),
          portion(PlateGroup.protein, 100),
          portion(PlateGroup.complexCarbohydrate, 50),
        ]);
        expect(a.recommendations, isEmpty);
        expect(a.verdict, PlateVerdict.nearlyBalanced);
      },
    );

    test('editing weights from improvable to balanced changes the verdict', () {
      final before = analyzer.analyze([
        portion(PlateGroup.vegetable, 100),
        portion(PlateGroup.protein, 200),
        portion(PlateGroup.complexCarbohydrate, 100),
      ]);
      expect(before.verdict, PlateVerdict.improvable);
      expect(recTypes(before), [PlateRecommendationType.addVegetables]);

      final after = analyzer.analyze([
        portion(PlateGroup.vegetable, 200),
        portion(PlateGroup.protein, 100),
        portion(PlateGroup.complexCarbohydrate, 100),
      ]);
      expect(after.verdict, PlateVerdict.nicelyBalanced);
      expect(after.recommendations, isEmpty);
    });

    test('the same input always produces an equal result (determinism)', () {
      final portions = [
        portion(PlateGroup.vegetable, 50),
        portion(PlateGroup.protein, 50),
        portion(PlateGroup.complexCarbohydrate, 300),
      ];
      final a = analyzer.analyze(portions);
      final b = analyzer.analyze(portions);
      expect(a.verdict, b.verdict);
      expect(a.vegetableFruitRatio, b.vegetableFruitRatio);
      expect(a.proteinRatio, b.proteinRatio);
      expect(a.complexCarbohydrateRatio, b.complexCarbohydrateRatio);
      expect(recTypes(a), recTypes(b));
    });
  });
}
