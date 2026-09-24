import 'dart:convert';
import 'dart:typed_data';

import 'package:calsnap/core/network/retry_interceptor.dart';
import 'package:calsnap/features/recognition/data/analysis_api.dart';
import 'package:calsnap/features/recognition/domain/analysis.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

typedef Handler = Future<ResponseBody> Function(
  RequestOptions options,
  int call,
);

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final Handler handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    await requestStream?.drain<void>();
    return handler(options, requests.length);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(String json, int status) => ResponseBody.fromString(
  json,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ResponseBody fixtureBody(String name, int status) =>
    jsonBody(protocolFile('fixtures/$name').readAsStringSync(), status);

DioException connectionError(RequestOptions o) =>
    DioException.connectionError(requestOptions: o, reason: 'refused');

({AnalysisApi api, FakeAdapter adapter, List<Duration> sleeps}) build(
  Handler handler, {
  List<Duration> delays = const [Duration.zero, Duration.zero],
}) {
  final adapter = FakeAdapter(handler);
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
    ..httpClientAdapter = adapter;
  final sleeps = <Duration>[];
  dio.interceptors.add(
    RetryInterceptor(dio, delays: delays, sleep: (d) async => sleeps.add(d)),
  );
  return (api: AnalysisApi(dio), adapter: adapter, sleeps: sleeps);
}

Future<AnalysisResult> analyze(
  AnalysisApi api, {
  String id = '0190f7a2-1b2c-7d3e-8f40-123456789abc',
  double? plate,
  CancelToken? cancel,
}) => api.analyze(
  jpeg: Uint8List.fromList([1, 2, 3]),
  locale: 'ru',
  requestId: id,
  config: const RemoteConfig(),
  plateDiameterCm: plate,
  cancelToken: cancel,
);

void main() {
  group('response parsing', () {
    for (final name in ['full', 'partial', 'estimated']) {
      test('protocol fixture analyze-response-$name parses', () async {
        final t = build(
          (o, _) async => fixtureBody('analyze-response-$name.json', 200),
        );
        final result = await analyze(t.api);
        final raw = jsonDecode(
          protocolFile('fixtures/analyze-response-$name.json')
              .readAsStringSync(),
        ) as Map<String, dynamic>;
        expect(result.items, hasLength((raw['items'] as List<dynamic>).length));
        expect(result.warnings, (raw['warnings'] as List<dynamic>).toSet());
        expect(result.requestId, raw['requestId']);
      });
    }

    test('the full fixture carries per-100 g values', () async {
      final t = build(
        (o, _) async => fixtureBody('analyze-response-full.json', 200),
      );
      final rice = (await analyze(t.api)).items.first;
      expect(rice.name, 'Рис');
      expect(rice.normalizedName, 'rice');
      expect(rice.estimatedWeightG, 170);
      expect(rice.per100.kcal, 130);
      expect(rice.per100.protein, 2.7);
      expect(rice.nutritionSource, 'catalog');
      expect(rice.confidence, 0.86);
    });

    test('an empty result becomes NotRecognizedFailure', () async {
      final t = build(
        (o, _) async => fixtureBody('analyze-response-no-food.json', 200),
      );
      await expectLater(analyze(t.api), throwsA(isA<NotRecognizedFailure>()));
    });

    test('a malformed body becomes UnknownFailure', () async {
      final t = build((o, _) async => jsonBody('{"requestId": 5}', 200));
      await expectLater(analyze(t.api), throwsA(isA<UnknownFailure>()));
    });
  });

  group('request', () {
    test('sends a multipart image with locale, plate and request id', () async {
      final t = build(
        (o, _) async => fixtureBody('analyze-response-full.json', 200),
      );
      await analyze(t.api, plate: 26);
      final options = t.adapter.requests.single;
      expect(options.method, 'POST');
      expect(options.path, '/v1/meals/analyze');
      expect(
        options.headers['X-Request-Id'],
        '0190f7a2-1b2c-7d3e-8f40-123456789abc',
      );
      final form = options.data as FormData;
      expect(form.files.single.key, 'image');
      expect(form.files.single.value.filename, 'meal.jpg');
      expect(form.files.single.value.contentType.toString(), 'image/jpeg');
      expect(Map.fromEntries(form.fields), {
        'locale': 'ru',
        'plateDiameterCm': '26.0',
      });
    });

    test('omits the plate diameter when unknown', () async {
      final t = build(
        (o, _) async => fixtureBody('analyze-response-full.json', 200),
      );
      await analyze(t.api);
      final form = t.adapter.requests.single.data as FormData;
      expect(form.fields.map((e) => e.key), ['locale']);
    });

    test(
      'the receive timeout follows the server value plus a margin',
      () async {
        final t = build(
          (o, _) async => fixtureBody('analyze-response-full.json', 200),
        );
        await analyze(t.api);
        expect(
          t.adapter.requests.single.receiveTimeout,
          const Duration(seconds: 75),
        );
      },
    );
  });

  group('retries', () {
    test('a 503 is retried once with the same request id', () async {
      final t = build(
        (o, call) async => call == 1
            ? fixtureBody('error-AI_PROVIDER_UNAVAILABLE.json', 503)
            : fixtureBody('analyze-response-full.json', 200),
      );
      final result = await analyze(t.api);
      expect(result.items, isNotEmpty);
      expect(t.adapter.requests, hasLength(2));
      expect(t.adapter.requests.map((r) => r.headers['X-Request-Id']).toSet(), {
        '0190f7a2-1b2c-7d3e-8f40-123456789abc',
      });
      // Each attempt sends a complete image part.
      for (final r in t.adapter.requests) {
        expect((r.data as FormData).files, hasLength(1));
      }
    });

    test('at most two retries for connection errors, then offline', () async {
      final t = build((o, _) async => throw connectionError(o));
      await expectLater(analyze(t.api), throwsA(isA<OfflineFailure>()));
      expect(t.adapter.requests, hasLength(3));
    });

    test('502 and 504 are retried, 500 is not', () async {
      var t = build(
        (o, call) async => call < 3
            ? jsonBody('{}', call == 1 ? 502 : 504)
            : fixtureBody('analyze-response-full.json', 200),
      );
      await analyze(t.api);
      expect(t.adapter.requests, hasLength(3));

      t = build((o, _) async => fixtureBody('error-INTERNAL_ERROR.json', 500));
      await expectLater(analyze(t.api), throwsA(isA<UnavailableFailure>()));
      expect(t.adapter.requests, hasLength(1));
    });

    test('429 is not retried', () async {
      final t = build(
        (o, _) async => fixtureBody('error-RATE_LIMITED.json', 429),
      );
      await expectLater(analyze(t.api), throwsA(isA<RateLimitedFailure>()));
      expect(t.adapter.requests, hasLength(1));
    });

    test('client errors are not retried', () async {
      final t = build(
        (o, _) async => fixtureBody('error-INVALID_IMAGE.json', 400),
      );
      await expectLater(analyze(t.api), throwsA(isA<BadImageFailure>()));
      expect(t.adapter.requests, hasLength(1));
    });

    test('backoff uses 1 s then 3 s by default', () async {
      final t = build(
        (o, _) async => throw connectionError(o),
        delays: const [Duration(seconds: 1), Duration(seconds: 3)],
      );
      await expectLater(analyze(t.api), throwsA(isA<OfflineFailure>()));
      expect(t.sleeps, const [Duration(seconds: 1), Duration(seconds: 3)]);
    });
  });

  group('failure mapping', () {
    final cases = <String, (int, Type)>{
      'RATE_LIMITED': (429, RateLimitedFailure),
      'INVALID_IMAGE': (400, BadImageFailure),
      'IMAGE_TOO_LARGE': (413, BadImageFailure),
      'UNSUPPORTED_IMAGE_FORMAT': (415, BadImageFailure),
      'AI_PROVIDER_UNAVAILABLE': (503, UnavailableFailure),
      'AI_INVALID_RESPONSE': (502, UnavailableFailure),
      'NUTRITION_MATCH_FAILED': (502, UnavailableFailure),
      'IMAGE_ANALYSIS_FAILED': (502, UnavailableFailure),
      'INTERNAL_ERROR': (500, UnavailableFailure),
      'INVALID_REQUEST': (400, UnknownFailure),
    };
    cases.forEach((code, expected) {
      test('$code (${expected.$1}) maps to ${expected.$2}', () async {
        final t = build(
          (o, _) async => fixtureBody('error-$code.json', expected.$1),
        );
        await expectLater(
          analyze(t.api),
          throwsA(predicate((e) => e.runtimeType == expected.$2)),
        );
      });
    });

    test('timeouts map to TimeoutFailure and never to raw text', () async {
      final t = build(
        (o, _) async => throw DioException.receiveTimeout(
          timeout: const Duration(seconds: 1),
          requestOptions: o,
        ),
      );
      final error = await analyze(t.api)
          .then<Object>((_) => 'no error', onError: (Object e) => e);
      expect(error, isA<TimeoutFailure>());
      expect(
        t.adapter.requests,
        hasLength(1),
        reason: 'timeouts are not retried',
      );
    });
  });

  test('cancellation surfaces as a cancelled DioException', () async {
    final token = CancelToken();
    final t = build((o, _) async {
      token.cancel();
      throw DioException.requestCancelled(
        requestOptions: o,
        reason: 'cancelled',
      );
    });
    await expectLater(
      analyze(t.api, cancel: token),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
    expect(t.adapter.requests, hasLength(1));
  });

  group('RemoteConfig', () {
    test('defaults match the specification', () {
      const c = RemoteConfig();
      expect(c.imageMaxLongSidePx, 1280);
      expect(c.imageJpegQuality, 85);
      expect(c.analyzeTimeoutSeconds, 60);
    });

    test('parses the shared fixture', () {
      final json = jsonDecode(
        protocolFile('fixtures/config-default.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final c = RemoteConfig.fromJson(json);
      expect(c.imageMaxLongSidePx, 1280);
      expect(c.imageJpegQuality, 80);
      expect(c.maxUploadBytes, 4194304);
    });

    test('clamps the long side to 512-2048 and ignores junk', () {
      expect(
        RemoteConfig.fromJson({'imageMaxLongSidePx': 100}).imageMaxLongSidePx,
        512,
      );
      expect(
        RemoteConfig.fromJson({'imageMaxLongSidePx': 9000}).imageMaxLongSidePx,
        2048,
      );
      final junk = RemoteConfig.fromJson({
        'imageMaxLongSidePx': 'big',
        'imageJpegQuality': null,
      });
      expect(junk.imageMaxLongSidePx, 1280);
      expect(junk.imageJpegQuality, 85);
    });

    test('round-trips through JSON', () {
      const c = RemoteConfig(imageMaxLongSidePx: 1024, imageJpegQuality: 70);
      expect(RemoteConfig.fromJson(c.toJson()).imageMaxLongSidePx, 1024);
      expect(RemoteConfig.fromJson(c.toJson()).imageJpegQuality, 70);
    });
  });
}
