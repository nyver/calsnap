import 'package:calsnap/core/domain/nutrition.dart';
import 'package:calsnap/core/utils/formatters.dart';
import 'package:calsnap/features/meal/domain/meal.dart';
import 'package:calsnap/features/meal/domain/meal_draft.dart';
import 'package:calsnap/features/meal/domain/nutrition_calculator.dart';
import 'package:calsnap/features/meal/domain/quantity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NutritionCalculator', () {
    test('formula: 180 g at 130 kcal/100 g is 234 kcal', () {
      final v = NutritionCalculator.forWeight(
        180,
        const Nutrition(kcal: 130, protein: 2.7, fat: 0.3, carbs: 28),
      );
      expect(v.kcal, closeTo(234, 1e-9));
      expect(v.protein, closeTo(4.86, 1e-9));
      expect(v.fat, closeTo(0.54, 1e-9));
      expect(v.carbs, closeTo(50.4, 1e-9));
    });

    test('uses unrounded values and sums them', () {
      const per100 = Nutrition(kcal: 33.3);
      final item = NutritionCalculator.forWeight(10, per100);
      final total = NutritionCalculator.total([item, item, item]);
      expect(total.kcal, closeTo(9.99, 1e-9));
    });

    test('empty total is zero', () {
      expect(NutritionCalculator.total(const []), Nutrition.zero);
    });

    test('removing a 120 kcal item from a 527 kcal draft gives 407', () {
      final items = [
        DraftItem.manual(
          id: 'a',
          name: 'A',
          weightG: 100,
          per100: const Nutrition(kcal: 407),
        ),
        DraftItem.manual(
          id: 'b',
          name: 'B',
          weightG: 100,
          per100: const Nutrition(kcal: 120),
        ),
      ];
      final draft = MealDraft(
        mealTime: DateTime(2026, 1, 1, 12),
        mealType: MealType.lunch,
        items: items,
      );
      expect(draft.totals.kcal, 527);
      expect(draft.copyWith(items: [items.first]).totals.kcal, 407);
    });
  });

  group('Quantity', () {
    test('grams pass through', () {
      expect(Quantity.toGrams(150, QuantityUnit.gram), 150);
    });

    test('milliliters use density, default 1.0', () {
      expect(
        Quantity.toGrams(200, QuantityUnit.milliliter, densityGPerMl: 1.03),
        closeTo(206, 1e-9),
      );
      expect(Quantity.toGrams(200, QuantityUnit.milliliter), 200);
      expect(
        Quantity.toGrams(200, QuantityUnit.milliliter, densityGPerMl: 0),
        200,
      );
    });

    test('2 pieces of 50 g are 100 g', () {
      expect(Quantity.toGrams(2, QuantityUnit.piece, gramsPerPiece: 50), 100);
    });

    test('pieces and portions need a defined weight', () {
      expect(Quantity.toGrams(2, QuantityUnit.piece), isNull);
      expect(Quantity.toGrams(1, QuantityUnit.portion), isNull);
      expect(
        Quantity.toGrams(1, QuantityUnit.portion, gramsPerPortion: 250),
        250,
      );
      expect(Quantity.availableUnits(), [
        QuantityUnit.gram,
        QuantityUnit.milliliter,
      ]);
      expect(
        Quantity.availableUnits(gramsPerPiece: 50),
        contains(QuantityUnit.piece),
      );
      expect(
        Quantity.availableUnits(gramsPerPortion: 50),
        contains(QuantityUnit.portion),
      );
    });

    test('weight validation accepts (0, 5000]', () {
      expect(Quantity.isValidWeight(0), isFalse);
      expect(Quantity.isValidWeight(-1), isFalse);
      expect(Quantity.isValidWeight(0.1), isTrue);
      expect(Quantity.isValidWeight(5000), isTrue);
      expect(Quantity.isValidWeight(5000.1), isFalse);
      expect(Quantity.isValidWeight(double.nan), isFalse);
      expect(Quantity.isValidWeight(double.infinity), isFalse);
      expect(Quantity.isValidWeight(null), isFalse);
    });

    test('non-positive amounts do not convert', () {
      expect(Quantity.toGrams(0, QuantityUnit.gram), isNull);
      expect(Quantity.toGrams(-5, QuantityUnit.gram), isNull);
      expect(Quantity.toGrams(double.nan, QuantityUnit.gram), isNull);
    });
  });

  group('NutritionFormatter', () {
    final en = NutritionFormatter('en');
    final ru = NutritionFormatter('ru');

    test('kcal is a whole number without grouping', () {
      expect(en.kcal(1460.4), '1460');
      expect(en.kcal(1460.5), '1461');
      expect(en.kcal(0), '0');
      expect(ru.kcal(2200), '2200');
    });

    test('macros: one decimal below 10 g, whole otherwise', () {
      expect(en.macro(3.64), '3.6');
      expect(en.macro(0.04), '0.0');
      expect(en.macro(9.94), '9.9');
      expect(en.macro(9.96), '10');
      expect(en.macro(10.4), '10');
      expect(en.macro(46.5), '47');
      expect(ru.macro(3.64), '3,6');
    });

    test('drafts are approximate to the nearest 10 kcal', () {
      expect(en.approximateKcal(643.4), '≈ 640');
      expect(en.approximateKcal(645), '≈ 650');
      expect(en.approximateKcal(4), '≈ 0');
      expect(ru.approximateKcal(527), '≈ 530');
    });

    test('weights keep at most one decimal', () {
      expect(en.weight(170), '170');
      expect(en.weight(82.5), '82.5');
      expect(en.weight(82.54), '82.5');
      expect(en.weight(99.96), '100');
    });
  });

  group('parseNumber', () {
    test('accepts comma and dot', () {
      expect(parseNumber('12,5'), 12.5);
      expect(parseNumber(' 12.5 '), 12.5);
      expect(parseNumber('150'), 150);
    });

    test('rejects garbage', () {
      expect(parseNumber(''), isNull);
      expect(parseNumber('abc'), isNull);
      expect(parseNumber('NaN'), isNull);
      expect(parseNumber('Infinity'), isNull);
      expect(parseNumber('1,2,3'), isNull);
    });
  });

  group('defaultMealType', () {
    test('follows the local time of day', () {
      MealType at(int h, [int m = 0]) =>
          defaultMealType(DateTime(2026, 1, 1, h, m));
      expect(at(4, 59), MealType.snack);
      expect(at(5), MealType.breakfast);
      expect(at(10, 59), MealType.breakfast);
      expect(at(11), MealType.lunch);
      expect(at(15, 59), MealType.lunch);
      expect(at(16), MealType.snack);
      expect(at(16, 59), MealType.snack);
      expect(at(17), MealType.dinner);
      expect(at(21, 59), MealType.dinner);
      expect(at(22), MealType.snack);
      expect(at(0), MealType.snack);
    });
  });

  group('DraftItem.wasCorrected', () {
    DraftItem ai() => const DraftItem(
      id: 'i',
      name: 'Rice',
      weightG: 170,
      per100: Nutrition(kcal: 130),
      source: RecognitionSource.ai,
      estimatedWeightG: 170,
      originalName: 'Rice',
      originalPer100: Nutrition(kcal: 130),
    );

    test('untouched AI item is not corrected', () {
      expect(ai().wasCorrected, isFalse);
    });

    test('weight, name or nutrition changes mark it corrected', () {
      expect(ai().copyWith(weightG: 150).wasCorrected, isTrue);
      expect(ai().copyWith(name: 'Basmati').wasCorrected, isTrue);
      expect(
        ai().copyWith(per100: const Nutrition(kcal: 140)).wasCorrected,
        isTrue,
      );
    });

    test('setting the weight back clears the flag for a fresh draft', () {
      expect(
        ai().copyWith(weightG: 150).copyWith(weightG: 170).wasCorrected,
        isFalse,
      );
    });

    test('manual items are never marked as corrected', () {
      final manual = DraftItem.manual(
        id: 'm',
        name: 'Oil',
        weightG: 10,
        per100: const Nutrition(kcal: 884),
      );
      expect(manual.copyWith(weightG: 20).wasCorrected, isFalse);
    });
  });
}
