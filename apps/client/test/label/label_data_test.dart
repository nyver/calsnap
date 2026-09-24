import 'dart:convert';
import 'dart:typed_data';

import 'package:calsnap/core/database/app_database.dart';
import 'package:calsnap/core/domain/nutrition.dart';
import 'package:calsnap/features/foods/domain/food.dart';
import 'package:calsnap/features/label/data/label_api.dart';
import 'package:calsnap/features/label/domain/label_reading.dart';
import 'package:calsnap/features/meal/domain/meal.dart';
import 'package:calsnap/features/recognition/domain/analysis.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(protocolFile('fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(String body, int status) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

LabelApi api(FakeHttpAdapter adapter) => LabelApi(
  Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter,
  newRequestId: () => '0190f7a2-1b2c-7d3e-8f40-123456789abc',
);

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  group('LabelReading', () {
    test('parses the shared protocol fixtures', () {
      final full = LabelReading.fromJson(
        fixture('label-response-per100g.json'),
      );
      expect(full.name, 'Chocolate hazelnut spread');
      expect(
        (full.kcal, full.protein, full.fat, full.carbs),
        (220.0, 8.4, 12.1, 18.2),
      );
      expect(full.servingSizeG, isNull);
      expect(full.warnings, isEmpty);
      expect(full.isComplete, isTrue);

      final converted = LabelReading.fromJson(
        fixture('label-response-per-serving.json'),
      );
      expect(converted.servingSizeG, 30);
      expect(converted.kcal, 399.9);
      expect(converted.warnings, {LabelWarning.valuesConverted});

      final partial = LabelReading.fromJson(
        fixture('label-response-partial.json'),
      );
      expect(partial.kcal, isNull, reason: 'unknown, not zero');
      expect(partial.carbs, isNull);
      expect((partial.protein, partial.fat), (8.4, 12.1));
      expect(partial.isComplete, isFalse);
      expect(partial.warnings, {LabelWarning.lowConfidence});
    });

    test('a malformed payload is a format error', () {
      expect(
        () => LabelReading.fromJson({'nutrition': 5}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('LabelApi', () {
    Future<Object?> errorOf(
      ResponseBody Function(RequestOptions) handler,
    ) async {
      try {
        await api(FakeHttpAdapter(handler)).read(
          Uint8List.fromList([1, 2, 3]),
          locale: 'ru',
          config: const RemoteConfig(),
        );
      } on Object catch (e) {
        return e;
      }
      return null;
    }

    test('sends the photo and the language as a form', () async {
      final adapter = FakeHttpAdapter(
        (_) => json(
          protocolFile('fixtures/label-response-per100g.json')
              .readAsStringSync(),
          200,
        ),
      );
      final reading = await api(adapter).read(
        Uint8List.fromList([1, 2, 3]),
        locale: 'ru',
        config: const RemoteConfig(),
      );
      expect(reading.kcal, 220);
      final request = adapter.requests.single;
      expect(request.path, '/v1/labels/analyze');
      expect(request.method, 'POST');
      expect(
        request.headers['X-Request-Id'],
        '0190f7a2-1b2c-7d3e-8f40-123456789abc',
      );
      final form = request.data as FormData;
      expect([for (final f in form.files) f.key], ['image']);
      expect(form.files.single.value.filename, 'label.jpg');
      expect({for (final f in form.fields) f.key: f.value}, {'locale': 'ru'});
    });

    test('a photo without a table is its own outcome', () async {
      final error = await errorOf(
        (_) => json(
          protocolFile('fixtures/error-LABEL_NOT_RECOGNIZED.json')
              .readAsStringSync(),
          422,
        ),
      );
      expect(error, isA<LabelNotRecognizedException>());
    });

    test('other failures use the shared categories', () async {
      expect(
        await errorOf(
          (_) => json(
            protocolFile('fixtures/error-AI_PROVIDER_UNAVAILABLE.json')
                .readAsStringSync(),
            503,
          ),
        ),
        isA<UnavailableFailure>(),
      );
      expect(
        await errorOf(
          (_) => json(
            protocolFile('fixtures/error-RATE_LIMITED.json').readAsStringSync(),
            429,
          ),
        ),
        isA<RateLimitedFailure>(),
      );
      expect(
        await errorOf(
          (o) => throw DioException.connectionError(
            requestOptions: o,
            reason: 'refused',
          ),
        ),
        isA<OfflineFailure>(),
      );
      expect(
        await errorOf((_) => json('{"weird":1}', 200)),
        isA<AnalysisFailure>(),
      );
      expect(
        await errorOf((_) => json('{"nutrition":', 200)),
        isA<AnalysisFailure>(),
      );
    });
  });

  group('custom products with a barcode', () {
    late TestRepos r;
    setUp(() => r = TestRepos());
    tearDown(() => r.close());

    const nutrition = Nutrition(
      kcal: 220,
      protein: 8.4,
      fat: 12.1,
      carbs: 18.2,
    );

    test(
      'are found by the barcode, also offline, and keep the serving',
      () async {
        final created = await r.foods.createCustom(
          const CustomFoodInput(
            name: 'Spread',
            per100: nutrition,
            servingSizeG: 30,
            barcode: '4006381333931',
          ),
        );
        expect(created.source, NutritionSourceName.user);
        expect(created.sourceId, '4006381333931');
        expect(created.gramsPerPortion, 30);

        final found = await r.foods.findByBarcode('4006381333931');
        expect(found?.id, created.id);
        expect(found?.per100, nutrition);
        expect((await r.foods.search('4006381333931')).single.id, created.id);
      },
    );

    test('creating one again for the same barcode replaces it', () async {
      final first = await r.foods.createCustom(
        const CustomFoodInput(
          name: 'Spread',
          per100: nutrition,
          barcode: '4006381333931',
        ),
      );
      final second = await r.foods.createCustom(
        CustomFoodInput(
          name: 'Spread, corrected',
          per100: nutrition.copyWith(kcal: 230),
          barcode: '4006381333931',
        ),
      );
      expect(second.id, first.id);
      expect(second.per100.kcal, 230);
      expect(await r.db.select(r.db.foods).get(), hasLength(1));
    });

    test('products without a barcode are unaffected', () async {
      final a = await r.foods.createCustom(
        const CustomFoodInput(name: 'A', per100: nutrition),
      );
      final b = await r.foods.createCustom(
        const CustomFoodInput(name: 'B', per100: nutrition),
      );
      expect(a.id, isNot(b.id));
      expect(a.sourceId, isNull);
      expect(await r.foods.findByBarcode('4006381333931'), isNull);
    });

    test('the serving is validated', () {
      CustomFoodProblem? problem(double? serving) => CustomFoodInput(
        name: 'X',
        per100: nutrition,
        servingSizeG: serving,
      ).validate();
      expect(problem(null), isNull);
      expect(problem(30), isNull);
      expect(problem(0), CustomFoodProblem.serving);
      expect(problem(-5), CustomFoodProblem.serving);
      expect(problem(2001), CustomFoodProblem.serving);
      expect(problem(double.nan), CustomFoodProblem.serving);
    });

    test('a correction by the user wins over a cached product', () async {
      // Both exist for one barcode only through a hand-made row, but the rule
      // keeps the user's version in front.
      await r.db
          .into(r.db.foods)
          .insert(
            FoodsCompanion.insert(
              id: 'cached',
              name: 'Cached',
              kcalPer100g: 100,
              source: const Value(NutritionSourceName.packaged),
              sourceId: const Value('4006381333931'),
              updatedAt: 1,
            ),
          );
      final mine = await r.foods.createCustom(
        const CustomFoodInput(
          name: 'Mine',
          per100: nutrition,
          barcode: '4006381333931',
        ),
      );
      expect((await r.foods.findByBarcode('4006381333931'))?.id, mine.id);
    });
  });
}
