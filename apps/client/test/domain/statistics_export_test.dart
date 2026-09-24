import 'dart:convert';

import 'package:calsnap/core/domain/nutrition.dart';
import 'package:calsnap/features/export/domain/exporters.dart';
import 'package:calsnap/features/meal/domain/meal.dart';
import 'package:calsnap/features/settings/domain/user_settings.dart';
import 'package:calsnap/features/statistics/domain/statistics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

Meal meal(
  DateTime time,
  double kcal, {
  String id = 'm',
  MealType? type = MealType.lunch,
  List<MealItem> items = const [],
  double protein = 0,
  double fat = 0,
  double carbs = 0,
}) => Meal(
  id: id,
  mealTime: time,
  mealType: type,
  totals: Nutrition(kcal: kcal, protein: protein, fat: fat, carbs: carbs),
  items: items,
  createdAt: time,
  updatedAt: time,
);

MealItem item(
  String name, {
  double weight = 100,
  Nutrition per100 = const Nutrition(kcal: 100),
  double? estimated,
  RecognitionSource? source,
  bool corrected = false,
  double? confidence,
}) => MealItem(
  id: 'i-$name',
  mealId: 'm',
  name: name,
  weightG: weight,
  estimatedWeightG: estimated,
  per100: per100,
  recognitionSource: source,
  wasCorrected: corrected,
  confidence: confidence,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

/// Minimal RFC 4180 parser for round-trip assertions.
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') {
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = [];
      i++;
    } else {
      cell.write(c);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}

void main() {
  group('weekly statistics', () {
    final today = DateTime.utc(2026, 3, 10);
    const utc = FixedOffsetZone(Duration.zero);

    WeekStats stats(List<Meal> meals, {int? target = 2000}) => computeWeekStats(
      meals: meals,
      today: today,
      kcalTarget: target,
      zone: utc,
    );

    test('has seven days ending today, oldest first', () {
      final s = stats(const []);
      expect(s.days, hasLength(7));
      expect(s.days.first.day, DateTime(2026, 3, 4));
      expect(s.days.last.day, DateTime(2026, 3, 10));
      expect(s.hasData, isFalse);
      expect(s.average, Nutrition.zero);
    });

    test('averages ignore empty days and show them as empty', () {
      final meals = [
        for (var d = 4; d <= 8; d++)
          meal(DateTime.utc(2026, 3, d, 12), 2000, id: 'm$d'),
      ];
      final s = stats(meals);
      expect(s.loggedDays, 5);
      expect(s.average.kcal, 2000);
      expect(s.days.where((d) => !d.hasMeals), hasLength(2));
      expect(s.days.last.hasMeals, isFalse);
      expect(s.today.kcal, 0);
    });

    test('sums several meals per day and averages macros', () {
      final s = stats([
        meal(
          DateTime.utc(2026, 3, 9, 8),
          500,
          id: 'a',
          protein: 30,
          fat: 10,
          carbs: 60,
        ),
        meal(
          DateTime.utc(2026, 3, 9, 19),
          700,
          id: 'b',
          protein: 50,
          fat: 20,
          carbs: 80,
        ),
        meal(
          DateTime.utc(2026, 3, 10, 13),
          400,
          id: 'c',
          protein: 20,
          fat: 10,
          carbs: 40,
        ),
      ]);
      expect(s.loggedDays, 2);
      expect(s.today.kcal, 400);
      expect(s.average.kcal, (1200 + 400) / 2);
      expect(s.average.protein, (80 + 20) / 2);
      expect(s.average.fat, (30 + 10) / 2);
      expect(s.average.carbs, (140 + 40) / 2);
    });

    test('adherence counts days within +-10% of the target', () {
      final s = stats([
        meal(DateTime.utc(2026, 3, 6, 12), 1850, id: 'a'),
        meal(DateTime.utc(2026, 3, 7, 12), 2150, id: 'b'),
        meal(DateTime.utc(2026, 3, 8, 12), 2400, id: 'c'),
        meal(DateTime.utc(2026, 3, 9, 12), 1700, id: 'd'),
      ]);
      expect(s.loggedDays, 4);
      expect(s.onTargetDays, 2);
    });

    test('the +-10% bounds are inclusive', () {
      final s = stats([
        meal(DateTime.utc(2026, 3, 8, 12), 1800, id: 'a'),
        meal(DateTime.utc(2026, 3, 9, 12), 2200, id: 'b'),
        meal(DateTime.utc(2026, 3, 10, 12), 2201, id: 'c'),
      ]);
      expect(s.onTargetDays, 2);
    });

    test('meals outside the window are ignored', () {
      final s = stats([
        meal(DateTime.utc(2026, 3, 3, 23, 59, 59), 999, id: 'old'),
        meal(DateTime.utc(2026, 3, 4), 100, id: 'first'),
        meal(DateTime.utc(2026, 3, 10, 23, 59, 59), 200, id: 'last'),
        meal(DateTime.utc(2026, 3, 11), 999, id: 'future'),
      ]);
      expect(s.loggedDays, 2);
      expect(s.average.kcal, 150);
    });

    test('day boundaries follow the time zone', () {
      const zone = FixedOffsetZone(Duration(hours: 5, minutes: 30));
      // Local (fields) times.
      final late = meal(DateTime.utc(2026, 3, 9, 23, 30), 300, id: 'late');
      final s = computeWeekStats(
        meals: [late],
        today: DateTime.utc(2026, 3, 10),
        kcalTarget: 2000,
        zone: zone,
      );
      expect(s.days[5].hasMeals, isTrue, reason: '9 March');
      expect(s.days[6].hasMeals, isFalse, reason: '10 March');
    });

    test('without a target nothing counts as on target', () {
      final s = stats([meal(DateTime.utc(2026, 3, 9, 12), 2000)], target: null);
      expect(s.onTargetDays, 0);
      expect(s.kcalTarget, isNull);
    });
  });

  group('CSV export', () {
    test('has the specified header and one row per item ordered by time', () {
      final late = meal(
        DateTime.utc(2026, 3, 10, 19, 5),
        0,
        id: 'late',
        type: MealType.dinner,
        items: [
          item(
            'Soup',
            weight: 250,
            per100: const Nutrition(
              kcal: 45,
              protein: 2.5,
              fat: 1.8,
              carbs: 5.2,
            ),
          ),
        ],
      );
      final early = meal(
        DateTime.utc(2026, 3, 10, 8),
        0,
        id: 'early',
        type: MealType.breakfast,
        items: [item('Egg', weight: 50), item('Bread', weight: 30)],
      );
      final rows = parseCsv(buildCsv([late, early]));
      expect(rows.first, [
        'date',
        'meal_type',
        'food',
        'weight_g',
        'kcal',
        'protein',
        'fat',
        'carbs',
      ]);
      expect(rows.skip(1).map((r) => r[2]), ['Egg', 'Bread', 'Soup']);
      expect(rows[1][0], '2026-03-10T08:00:00+00:00');
      expect(rows[1][1], 'breakfast');
      expect(rows[3], [
        '2026-03-10T19:05:00+00:00',
        'dinner',
        'Soup',
        '250',
        '112.5',
        '6.3',
        '4.5',
        '13',
      ]);
    });

    test('rows end with CRLF and numbers use a dot and one decimal', () {
      final csv = buildCsv([
        meal(
          DateTime.utc(2026, 3, 10, 8),
          0,
          items: [
            item(
              'Rice',
              weight: 82.55,
              per100: const Nutrition(
                kcal: 130,
                protein: 2.7,
                fat: 0.3,
                carbs: 28,
              ),
            ),
          ],
        ),
      ]);
      expect(csv.endsWith('\r\n'), isTrue);
      expect(csv.split('\r\n'), hasLength(3));
      final row = parseCsv(csv)[1];
      expect(row.sublist(3), ['82.6', '107.3', '2.2', '0.2', '23.1']);
      expect(csv.contains(','), isTrue);
    });

    test('quotes cells with commas, quotes and newlines', () {
      final csv = buildCsv([
        meal(
          DateTime.utc(2026, 3, 10, 8),
          0,
          items: [
            item('Rice, boiled'),
            item('The "best" soup'),
            item('two\nlines'),
          ],
        ),
      ]);
      expect(csv, contains('"Rice, boiled"'));
      expect(csv, contains('"The ""best"" soup"'));
      final foods = parseCsv(csv).skip(1).map((r) => r[2]).toList();
      expect(foods, ['Rice, boiled', 'The "best" soup', 'two\nlines']);
    });

    test('formula-like names are neutralized with a leading apostrophe', () {
      for (final name in ['=HYPERLINK("x")', '+1+1', '-2+3', '@SUM(A1)']) {
        final csv = buildCsv([
          meal(DateTime.utc(2026, 3, 10, 8), 0, items: [item(name)]),
        ]);
        final food = parseCsv(csv)[1][2];
        expect(food, "'$name");
        expect(food.startsWith("'"), isTrue);
      }
    });

    test('ordinary names are untouched and Cyrillic survives UTF-8', () {
      final csv = buildCsv([
        meal(DateTime.utc(2026, 3, 10, 8), 0, items: [item('Гречка')]),
      ]);
      final bytes = utf8.encode(csv);
      expect(parseCsv(utf8.decode(bytes))[1][2], 'Гречка');
      expect(parseCsv(csv)[1][2], isNot(startsWith("'")));
    });

    test('a null meal type is exported as an empty cell; empty diary has only the header', () {
      final csv = buildCsv([
        meal(DateTime.utc(2026, 3, 10, 8), 0, type: null, items: [item('X')]),
      ]);
      expect(parseCsv(csv)[1][1], '');
      expect(buildCsv(const []).trim().split('\r\n'), hasLength(1));
    });

    test('runs in a background isolate', () async {
      final meals = [
        meal(DateTime.utc(2026, 3, 10, 8), 0, items: [item('Egg')]),
      ];
      expect(await buildCsvInBackground(meals), buildCsv(meals));
    });
  });

  group('JSON export', () {
    final exportedAt = DateTime.utc(2026, 3, 10, 12);
    const settings = AppSettings(
      dailyKcalTarget: 2200,
      dailyProteinTargetG: 150,
      plateDiameterCm: 26,
      savePhotos: false,
      language: AppLanguage.ru,
    );

    Map<String, dynamic> export(List<Meal> meals) => jsonDecode(
      buildJson(
        meals,
        settings: settings,
        exportedAt: exportedAt,
        appVersion: '1.2.3',
      ),
    ) as Map<String, dynamic>;

    test('is versioned and self-describing', () {
      final doc = export(const []);
      expect(doc['format'], 'calsnap-export');
      expect(doc['formatVersion'], 1);
      expect(doc['exportedAt'], '2026-03-10T12:00:00.000Z');
      expect(doc['appVersion'], '1.2.3');
      expect(doc['meals'], isEmpty);
      final s = doc['settings'] as Map<String, dynamic>;
      expect(s['dailyKcalTarget'], 2200);
      expect(s['dailyFatTargetG'], isNull);
      expect(s['plateDiameterCm'], 26);
      expect(s['savePhotos'], false);
      expect(s['language'], 'ru');
      expect(s['unitSystem'], 'metric');
    });

    test('contains meals with items, estimated and final weights, values and flags', () {
      final doc = export([
        meal(
          DateTime.utc(2026, 3, 10, 8),
          195,
          id: 'meal-1',
          type: MealType.lunch,
          items: [
            item(
              'Rice',
              weight: 150,
              estimated: 170,
              per100: const Nutrition(
                kcal: 130,
                protein: 2.7,
                fat: 0.3,
                carbs: 28,
              ),
              source: RecognitionSource.ai,
              corrected: true,
              confidence: 0.86,
            ),
          ],
        ),
      ]);
      final m = (doc['meals'] as List<dynamic>).single as Map<String, dynamic>;
      expect(m['id'], 'meal-1');
      expect(m['mealType'], 'lunch');
      expect(m['mealTime'], '2026-03-10T08:00:00+00:00');
      expect((m['totals'] as Map<String, dynamic>)['kcal'], 195);
      final i = (m['items'] as List<dynamic>).single as Map<String, dynamic>;
      expect(i['estimatedWeightG'], 170);
      expect(i['weightG'], 150);
      expect((i['per100g'] as Map<String, dynamic>)['protein'], 2.7);
      expect((i['values'] as Map<String, dynamic>)['kcal'], 195);
      expect(i['confidence'], 0.86);
      expect(i['recognitionSource'], 'ai');
      expect(i['wasCorrected'], true);
      expect(jsonEncode(doc), isNot(contains('base64')));
    });

    test('runs in a background isolate', () async {
      final meals = [
        meal(DateTime.utc(2026, 3, 10, 8), 0, items: [item('Egg')]),
      ];
      final text = await buildJsonInBackground(
        meals,
        settings: settings,
        exportedAt: exportedAt,
        appVersion: '1',
      );
      expect(jsonDecode(text), isA<Map<String, dynamic>>());
    });
  });
}
