import 'dart:convert';
import 'dart:typed_data';

import 'package:calsnap/core/domain/nutrition.dart';
import 'package:calsnap/features/barcode/data/product_api.dart';
import 'package:calsnap/features/barcode/domain/gtin.dart';
import 'package:calsnap/features/barcode/domain/packaged_product.dart';
import 'package:calsnap/features/barcode/domain/product_lookup.dart';
import 'package:calsnap/features/meal/domain/meal.dart';
import 'package:calsnap/features/recognition/domain/analysis.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

const yogurt = PackagedProduct(
  barcode: '4006381333931',
  name: 'Plain yogurt',
  brand: 'Danone',
  servingSizeG: 150,
  per100: Nutrition(kcal: 61, protein: 3.5, fat: 2.1, carbs: 7.6),
);

class FakeSource implements ProductSource {
  FakeSource(this.handler);

  final Future<PackagedProduct> Function(String barcode, String locale) handler;
  final List<({String barcode, String locale})> calls = [];

  @override
  Future<PackagedProduct> fetch(String barcode, {required String locale}) {
    calls.add((barcode: barcode, locale: locale));
    return handler(barcode, locale);
  }
}

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

ProductApi api(FakeHttpAdapter adapter) => ProductApi(
  Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter,
);

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  group('Gtin.normalize', () {
    // The same cases as the backend tests.
    const valid = {
      '4006381333931': '4006381333931',
      ' 4006381333931 ': '4006381333931',
      '96385074': '96385074',
      '036000291452': '0036000291452', // UPC-A becomes EAN-13
      '10012345678902': '10012345678902',
    };
    valid.forEach((input, expected) {
      test('accepts "$input"', () => expect(Gtin.normalize(input), expected));
    });

    for (final input in [
      '4006381333932', // wrong check digit
      '1234567',
      '123456789',
      '123456789012345',
      '40063813339A1',
      '4006381-33931',
      '',
      '٤٠٠٦٣٨١٣٣٣٩٣١', // Arabic-Indic digits
    ]) {
      test('rejects "$input"', () => expect(Gtin.normalize(input), isNull));
    }
  });

  group('PackagedProduct', () {
    test('parses the shared protocol fixture', () {
      final product = PackagedProduct.fromJson(
        jsonDecode(
          protocolFile('fixtures/product-response.json').readAsStringSync(),
        ) as Map<String, dynamic>,
      );
      expect(product.barcode, '4006381333931');
      expect(product.name, 'Plain yogurt');
      expect(product.brand, 'Danone');
      expect(product.servingSizeG, 150);
      expect(product.per100.kcal, 61);
      expect(product.per100.carbs, 7.6);
    });

    test('optional fields may be missing', () {
      final product = PackagedProduct.fromJson({
        'barcode': '96385074',
        'name': 'Water',
        'nutrition': {
          'kcalPer100g': 0,
          'proteinPer100g': 0,
          'fatPer100g': 0,
          'carbsPer100g': 0,
        },
        'source': 'openfoodfacts',
      });
      expect(product.brand, isNull);
      expect(product.servingSizeG, isNull);
    });

    test('a malformed payload is a format error', () {
      expect(
        () => PackagedProduct.fromJson({'barcode': 1}),
        throwsA(isA<FormatException>()),
      );
    });

    test('the brand is shown once', () {
      expect(yogurt.displayName, 'Danone Plain yogurt');
      const branded = PackagedProduct(
        barcode: '1',
        name: 'Danone Activia',
        brand: 'danone',
        per100: Nutrition(),
      );
      expect(branded.displayName, 'Danone Activia');
      const plain = PackagedProduct(
        barcode: '1',
        name: 'Water',
        per100: Nutrition(),
      );
      expect(plain.displayName, 'Water');
    });
  });

  group('ProductApi', () {
    ResponseBody fixture() => json(
      protocolFile('fixtures/product-response.json').readAsStringSync(),
      200,
    );

    test('asks the backend for the barcode in the given language', () async {
      final adapter = FakeHttpAdapter((_) => fixture());
      final product = await api(adapter).fetch('4006381333931', locale: 'ru');
      expect(product.name, 'Plain yogurt');
      final request = adapter.requests.single;
      expect(request.path, '/v1/products/4006381333931');
      expect(request.queryParameters, {'locale': 'ru'});
      expect(request.method, 'GET');
    });

    Future<Object?> errorOf(
      ResponseBody Function(RequestOptions) handler,
    ) async {
      try {
        await api(FakeHttpAdapter(handler))
            .fetch('4006381333931', locale: 'en');
      } on Object catch (e) {
        return e;
      }
      return null;
    }

    test('an unknown product is its own outcome', () async {
      final error = await errorOf(
        (_) => json(
          protocolFile('fixtures/error-PRODUCT_NOT_FOUND.json')
              .readAsStringSync(),
          404,
        ),
      );
      expect(error, isA<ProductNotFoundException>());
    });

    test('other failures use the shared categories', () async {
      expect(
        await errorOf(
          (_) => json(
            protocolFile('fixtures/error-PRODUCT_SOURCE_UNAVAILABLE.json')
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
        await errorOf((_) => json('{"barcode":', 200)),
        isA<AnalysisFailure>(),
      );
      expect(
        await errorOf((_) => json('{"weird":1}', 200)),
        isA<UnknownFailure>(),
      );
    });
  });

  group('ProductLookup', () {
    late TestRepos r;
    setUp(() => r = TestRepos());
    tearDown(() => r.close());

    ProductLookup lookupOver(FakeSource source) =>
        ProductLookup(foods: r.foods, source: source);

    test('asks the source once, then answers from the cache', () async {
      final source = FakeSource((_, _) async => yogurt);
      final lookup = lookupOver(source);

      final first = await lookup('4006381333931', locale: 'en');
      expect(first.name, 'Danone Plain yogurt');
      expect(first.source, NutritionSourceName.packaged);
      expect(first.sourceId, '4006381333931');
      expect(first.gramsPerPortion, 150);
      expect(first.per100.kcal, 61);

      final second = await lookup('4006381333931', locale: 'ru');
      expect(second.id, first.id);
      expect(
        source.calls,
        hasLength(1),
        reason: 'the second scan is offline-safe',
      );
    });

    test('a scanned product keeps working without a network', () async {
      final online = FakeSource((_, _) async => yogurt);
      await lookupOver(online)('4006381333931', locale: 'en');

      final offline = FakeSource((_, _) async => throw const OfflineFailure());
      final food = await lookupOver(offline)('4006381333931', locale: 'en');
      expect(food.name, 'Danone Plain yogurt');
      expect(offline.calls, isEmpty);
    });

    test('a UPC-A code is looked up as the equivalent EAN-13', () async {
      final source = FakeSource(
        (barcode, _) async => PackagedProduct(
          barcode: barcode,
          name: 'Cereal',
          per100: const Nutrition(kcal: 380),
        ),
      );
      final food = await lookupOver(source)('036000291452', locale: 'en');
      expect(source.calls.single.barcode, '0036000291452');
      expect(food.sourceId, '0036000291452');
    });

    test('the cached product is found by searching for its digits', () async {
      await lookupOver(FakeSource((_, _) async => yogurt))(
        '4006381333931',
        locale: 'en',
      );
      expect(
        (await r.foods.search('4006381333931')).single.name,
        'Danone Plain yogurt',
      );
      expect((await r.foods.search('yogurt')), hasLength(1));
    });

    test('failures and unknown products are not cached', () async {
      var call = 0;
      final source = FakeSource((_, _) async {
        call++;
        if (call == 1) throw const ProductNotFoundException();
        if (call == 2) throw const UnavailableFailure();
        return yogurt;
      });
      final lookup = lookupOver(source);
      await expectLater(
        lookup('4006381333931', locale: 'en'),
        throwsA(isA<ProductNotFoundException>()),
      );
      await expectLater(
        lookup('4006381333931', locale: 'en'),
        throwsA(isA<UnavailableFailure>()),
      );
      expect(
        (await lookup('4006381333931', locale: 'en')).name,
        contains('yogurt'),
      );
      expect(source.calls, hasLength(3));
    });

    test('an invalid barcode never reaches the source', () async {
      final source = FakeSource((_, _) async => yogurt);
      await expectLater(
        lookupOver(source)('4006381333932', locale: 'en'),
        throwsArgumentError,
      );
      expect(source.calls, isEmpty);
    });

    test('saving a product again updates it and keeps its id', () async {
      final first = await r.foods.savePackaged(yogurt);
      final again = await r.foods.savePackaged(
        const PackagedProduct(
          barcode: '4006381333931',
          name: 'Plain yogurt',
          brand: 'Danone',
          per100: Nutrition(kcal: 70, protein: 4, fat: 3, carbs: 8),
        ),
      );
      expect(again.id, first.id);
      expect(again.per100.kcal, 70);
      expect(again.gramsPerPortion, isNull);
      expect(await r.db.select(r.db.foods).get(), hasLength(1));
    });

    test('packaged products survive a catalog re-seed', () async {
      await r.foods.savePackaged(yogurt);
      await r.foods.seedCatalog(readCatalogJson());
      expect(await r.foods.findPackaged('4006381333931'), isNotNull);
    });
  });
}
