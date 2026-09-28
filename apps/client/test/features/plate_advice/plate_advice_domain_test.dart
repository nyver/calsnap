import 'dart:convert';

import 'package:calsnap/features/balanced_plate/domain/plate_analysis.dart';
import 'package:calsnap/features/balanced_plate/domain/plate_group.dart';
import 'package:calsnap/features/meal/domain/meal.dart';
import 'package:calsnap/features/meal/domain/meal_draft.dart';
import 'package:calsnap/features/plate_advice/domain/get_plate_advice_use_case.dart';
import 'package:calsnap/features/plate_advice/domain/plate_advice.dart';
import 'package:calsnap/features/plate_advice/domain/plate_advice_repository.dart';
import 'package:calsnap/features/plate_advice/domain/plate_advice_request.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(protocolFile('fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

PlateAnalysis analysisOf({
  double veg = 0.35,
  double protein = 0.25,
  double carb = 0.25,
}) => PlateAnalysis(
  verdict: PlateVerdict.nearlyBalanced,
  vegetableFruitRatio: veg,
  proteinRatio: protein,
  complexCarbohydrateRatio: carb,
  coverage: 1,
  eligibleWeightG: 300,
  healthyFatPresent: false,
  recommendations: const [],
);

const insufficientAnalysis = PlateAnalysis(
  verdict: PlateVerdict.insufficientData,
  vegetableFruitRatio: 0,
  proteinRatio: 0,
  complexCarbohydrateRatio: 0,
  coverage: 0,
  eligibleWeightG: 0,
  healthyFatPresent: false,
  recommendations: [],
);

class FakeRepository implements PlateAdviceRepository {
  PlateAdviceRequest? lastRequest;
  Object? error;
  PlateAdvice response = const PlateAdvice(summary: 's', suggestions: []);

  @override
  Future<PlateAdvice> getAdvice(
    PlateAdviceRequest request, {
    Future<void>? cancel,
  }) async {
    lastRequest = request;
    if (error != null) throw error!;
    return response;
  }
}

void main() {
  group('PlateBalanceSnapshot.fromAnalysis', () {
    test('vegetablesFruit is low below 0.30, ok at and above', () {
      expect(
        PlateBalanceSnapshot.fromAnalysis(analysisOf(veg: 0.29))
            .vegetablesFruit,
        BalanceStatus.low,
      );
      expect(
        PlateBalanceSnapshot.fromAnalysis(analysisOf(veg: 0.30))
            .vegetablesFruit,
        BalanceStatus.ok,
      );
      expect(
        PlateBalanceSnapshot.fromAnalysis(analysisOf(veg: 0.31))
            .vegetablesFruit,
        BalanceStatus.ok,
      );
    });

    test('protein is low below 0.15, ok at and above', () {
      expect(
        PlateBalanceSnapshot.fromAnalysis(analysisOf(protein: 0.14)).protein,
        BalanceStatus.low,
      );
      expect(
        PlateBalanceSnapshot.fromAnalysis(analysisOf(protein: 0.15)).protein,
        BalanceStatus.ok,
      );
    });

    test(
      'complexCarbohydrates is low below 0.10, ok between, high above 0.50',
      () {
        expect(
          PlateBalanceSnapshot.fromAnalysis(analysisOf(carb: 0.09))
              .complexCarbohydrates,
          BalanceStatus.low,
        );
        expect(
          PlateBalanceSnapshot.fromAnalysis(analysisOf(carb: 0.10))
              .complexCarbohydrates,
          BalanceStatus.ok,
        );
        expect(
          PlateBalanceSnapshot.fromAnalysis(analysisOf(carb: 0.50))
              .complexCarbohydrates,
          BalanceStatus.ok,
        );
        expect(
          PlateBalanceSnapshot.fromAnalysis(analysisOf(carb: 0.51))
              .complexCarbohydrates,
          BalanceStatus.high,
        );
      },
    );
  });

  group('PlateAdviceRequest.tryCreate', () {
    test('is null for a non-evaluable analysis', () {
      final draft = draftOf([aiItem('a')]);
      expect(
        PlateAdviceRequest.tryCreate(
          draft: draft,
          analysis: insufficientAnalysis,
          locale: 'en',
        ),
        isNull,
      );
    });

    test('carries locale, mealType, items and balance only', () {
      final draft = MealDraft(
        mealTime: DateTime.utc(2026, 3, 10, 13),
        mealType: MealType.lunch,
        items: [
          aiItem(
            'a',
            name: 'Buckwheat',
            weight: 180,
          ).copyWith(plateGroup: PlateGroup.complexCarbohydrate),
          aiItem(
            'b',
            name: 'Chicken breast',
            weight: 150,
          ).copyWith(plateGroup: PlateGroup.protein),
          aiItem(
            'c',
            name: 'Tomato',
            weight: 45,
          ).copyWith(plateGroup: PlateGroup.vegetable),
        ],
      );
      final analysis = analysisOf(veg: 0.12, protein: 0.4, carb: 0.48);
      final req = PlateAdviceRequest.tryCreate(
        draft: draft,
        analysis: analysis,
        locale: 'ru',
      )!;
      expect(req.locale, 'ru');
      expect(req.mealType, 'lunch');
      expect(req.items, hasLength(3));
      final json = req.toJson();
      expect(json.keys.toSet(), {'locale', 'mealType', 'items', 'balance'});
      final itemJson = (json['items'] as List).first as Map<String, dynamic>;
      expect(itemJson.keys.toSet(), {'name', 'weightG', 'plateGroup'});
    });

    test('a custom food without a plate group is sent as unknown', () {
      final draft = draftOf([manualItem('m', name: 'Homemade soup')]);
      final req = PlateAdviceRequest.tryCreate(
        draft: draft,
        analysis: analysisOf(),
        locale: 'en',
      )!;
      expect(req.items.single.plateGroup, PlateGroup.unknown);
      expect(req.items.single.toJson()['plateGroup'], 'unknown');
    });

    test('a non-positive weight item is dropped', () {
      final draft = draftOf([
        aiItem('a', name: 'Rice', weight: 100),
        aiItem('b', name: 'Ghost', weight: 0),
      ]);
      final req = PlateAdviceRequest.tryCreate(
        draft: draft,
        analysis: analysisOf(),
        locale: 'en',
      )!;
      expect(req.items.map((i) => i.name), ['Rice']);
    });

    test('names longer than 120 characters are truncated', () {
      final longName = 'a' * 200;
      final draft = draftOf([aiItem('a', name: longName, weight: 100)]);
      final req = PlateAdviceRequest.tryCreate(
        draft: draft,
        analysis: analysisOf(),
        locale: 'en',
      )!;
      expect(req.items.single.name.length, 120);
    });

    test('the 30 heaviest of 35 items are kept', () {
      final items = [
        for (var i = 1; i <= 35; i++)
          aiItem('item-$i', name: 'Food $i', weight: i.toDouble()),
      ];
      final draft = draftOf(items);
      final req = PlateAdviceRequest.tryCreate(
        draft: draft,
        analysis: analysisOf(),
        locale: 'en',
      )!;
      expect(req.items, hasLength(30));
      final keptWeights = req.items.map((i) => i.weightG).toSet();
      for (var w = 6; w <= 35; w++) {
        expect(keptWeights, contains(w.toDouble()));
      }
    });
  });

  group('PlateAdviceRequest.fingerprint', () {
    PlateAdviceRequest reqOf(List<DraftItem> items, {String locale = 'en'}) =>
        PlateAdviceRequest.tryCreate(
          draft: draftOf(items),
          analysis: analysisOf(),
          locale: locale,
        )!;

    test('changes when a weight, name, group or locale changes', () {
      final base = reqOf([aiItem('a', name: 'Rice', weight: 150)]);
      expect(
        reqOf([aiItem('a', name: 'Rice', weight: 160)]).fingerprint,
        isNot(base.fingerprint),
      );
      expect(
        reqOf([aiItem('a', name: 'Pasta', weight: 150)]).fingerprint,
        isNot(base.fingerprint),
      );
      expect(
        reqOf([
          aiItem(
            'a',
            name: 'Rice',
            weight: 150,
          ).copyWith(plateGroup: PlateGroup.complexCarbohydrate),
        ]).fingerprint,
        isNot(base.fingerprint),
      );
      expect(
        reqOf([
          aiItem('a', name: 'Rice', weight: 150),
        ], locale: 'ru').fingerprint,
        isNot(base.fingerprint),
      );
    });

    test('changes when the meal type changes', () {
      final lunch = PlateAdviceRequest.tryCreate(
        draft: draftOf([aiItem('a')], type: MealType.lunch),
        analysis: analysisOf(),
        locale: 'en',
      )!;
      final dinner = PlateAdviceRequest.tryCreate(
        draft: draftOf([aiItem('a')], type: MealType.dinner),
        analysis: analysisOf(),
        locale: 'en',
      )!;
      expect(lunch.fingerprint, isNot(dinner.fingerprint));
    });

    test('does not change on item order', () {
      final a = reqOf([
        aiItem('a', name: 'Rice', weight: 100),
        aiItem('b', name: 'Chicken', weight: 150),
      ]);
      final b = reqOf([
        aiItem('b', name: 'Chicken', weight: 150),
        aiItem('a', name: 'Rice', weight: 100),
      ]);
      expect(a.fingerprint, b.fingerprint);
    });

    test('does not change on sub-gram weight noise', () {
      final a = reqOf([aiItem('a', name: 'Rice', weight: 100.4)]);
      final b = reqOf([aiItem('a', name: 'Rice', weight: 100.2)]);
      expect(a.fingerprint, b.fingerprint);
    });
  });

  group('GetPlateAdviceUseCase', () {
    test('throws on a non-evaluable analysis', () {
      final useCase = GetPlateAdviceUseCase(FakeRepository());
      expect(
        () => useCase.execute(
          draft: draftOf([aiItem('a')]),
          analysis: insufficientAnalysis,
          locale: 'en',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('passes the built request through to the repository', () async {
      final repo = FakeRepository();
      final useCase = GetPlateAdviceUseCase(repo);
      final advice = await useCase.execute(
        draft: draftOf([aiItem('a', name: 'Rice', weight: 150)]),
        analysis: analysisOf(),
        locale: 'ru',
      );
      expect(advice, repo.response);
      expect(repo.lastRequest?.locale, 'ru');
      expect(repo.lastRequest?.items.single.name, 'Rice');
    });
  });

  group('PlateAdvice.fromJson', () {
    test('parses the shared response fixtures', () {
      for (final name in [
        'plate-advice-response-ru.json',
        'plate-advice-response-en.json',
      ]) {
        final advice = PlateAdvice.fromJson(fixture(name));
        expect(advice.summary, isNotEmpty);
        expect(advice.suggestions, isNotEmpty);
        for (final s in advice.suggestions) {
          expect(s.title, isNotEmpty);
          expect(s.reason, isNotEmpty);
        }
      }
    });

    test('drops a suggestion with an unknown action', () {
      final advice = PlateAdvice.fromJson({
        'summary': 's',
        'suggestions': [
          {
            'action': 'ADD',
            'targetGroup': 'vegetable',
            'title': 't',
            'reason': 'r',
            'examples': <String>[],
          },
          {'action': 'REMOVE', 'title': 't2', 'reason': 'r2'},
        ],
      });
      expect(advice.suggestions, hasLength(1));
      expect(advice.suggestions.single.action, PlateAdviceAction.add);
    });

    test(
      'nulls an unknown targetGroup instead of rejecting the suggestion',
      () {
        final advice = PlateAdvice.fromJson({
          'summary': 's',
          'suggestions': [
            {
              'action': 'KEEP',
              'targetGroup': 'sweets',
              'title': 't',
              'reason': 'r',
            },
          ],
        });
        expect(advice.suggestions.single.targetGroup, isNull);
      },
    );
  });
}
