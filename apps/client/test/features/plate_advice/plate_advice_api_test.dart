import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:calsnap/features/balanced_plate/domain/plate_group.dart';
import 'package:calsnap/features/plate_advice/data/plate_advice_api.dart';
import 'package:calsnap/features/plate_advice/domain/plate_advice_failure.dart';
import 'package:calsnap/features/plate_advice/domain/plate_advice_request.dart';
import 'package:calsnap/features/recognition/data/analysis_api.dart';
import 'package:calsnap/features/recognition/data/remote_config_repository.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';

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

/// Cooperates with a real [CancelToken]: it hangs until the token's future
/// completes, then throws the way Dio itself would.
class CancelAwareAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await cancelFuture;
    throw DioException(requestOptions: options, type: DioExceptionType.cancel);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(String body, int status) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

RemoteConfigRepository fakeRemoteConfig() => RemoteConfigRepository(
  TestRepos().settings,
  AnalysisApi(Dio(BaseOptions(baseUrl: 'https://unused.test'))),
);

PlateAdviceRequest testRequest() => const PlateAdviceRequest(
  locale: 'ru',
  mealType: 'lunch',
  items: [
    PlateAdviceItem(
      name: 'Гречка',
      weightG: 180,
      plateGroup: PlateGroup.complexCarbohydrate,
    ),
    PlateAdviceItem(
      name: 'Куриная грудка',
      weightG: 150,
      plateGroup: PlateGroup.protein,
    ),
    PlateAdviceItem(
      name: 'Помидор',
      weightG: 45,
      plateGroup: PlateGroup.vegetable,
    ),
  ],
  balance: PlateBalanceSnapshot(
    vegetablesFruit: BalanceStatus.low,
    protein: BalanceStatus.ok,
    complexCarbohydrates: BalanceStatus.ok,
  ),
);

PlateAdviceApi apiOf(FakeHttpAdapter adapter, {String requestId = 'id-1'}) =>
    PlateAdviceApi(
      Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..httpClientAdapter = adapter,
      fakeRemoteConfig(),
      newRequestId: () => requestId,
    );

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test(
    'posts the request as JSON with a fresh X-Request-Id per call',
    () async {
      var counter = 0;
      final adapter = FakeHttpAdapter(
        (_) => jsonBody(
          protocolFile('fixtures/plate-advice-response-ru.json')
              .readAsStringSync(),
          200,
        ),
      );
      final ids = ['id-1', 'id-2'];
      final api = PlateAdviceApi(
        Dio(BaseOptions(baseUrl: 'https://api.test'))
          ..httpClientAdapter = adapter,
        fakeRemoteConfig(),
        newRequestId: () => ids[counter++],
      );
      final request = testRequest();
      await api.getAdvice(request);
      await api.getAdvice(request);

      expect(adapter.requests, hasLength(2));
      expect(adapter.requests[0].path, '/v1/plate-advice');
      expect(adapter.requests[0].method, 'POST');
      expect(adapter.requests[0].headers['X-Request-Id'], 'id-1');
      expect(adapter.requests[1].headers['X-Request-Id'], 'id-2');
      expect(
        jsonEncode(adapter.requests[0].data),
        jsonEncode(request.toJson()),
      );
    },
  );

  test('the RU response parses', () async {
    final adapter = FakeHttpAdapter(
      (_) => jsonBody(
        protocolFile('fixtures/plate-advice-response-ru.json')
            .readAsStringSync(),
        200,
      ),
    );
    final advice = await apiOf(adapter).getAdvice(testRequest());
    expect(advice.summary, isNotEmpty);
    expect(advice.suggestions, isNotEmpty);
  });

  Future<Object?> errorOf(ResponseBody Function(RequestOptions) handler) async {
    try {
      await apiOf(FakeHttpAdapter(handler)).getAdvice(testRequest());
    } on Object catch (e) {
      return e;
    }
    return null;
  }

  test('429 gives rateLimited', () async {
    expect(
      await errorOf(
        (_) => jsonBody(
          protocolFile('fixtures/error-RATE_LIMITED.json').readAsStringSync(),
          429,
        ),
      ),
      isA<PlateAdviceRateLimited>(),
    );
  });

  test('502 AI_INVALID_RESPONSE gives invalidResponse', () async {
    expect(
      await errorOf(
        (_) => jsonBody(
          protocolFile('fixtures/error-AI_INVALID_RESPONSE.json')
              .readAsStringSync(),
          502,
        ),
      ),
      isA<PlateAdviceInvalidResponse>(),
    );
  });

  test('a malformed body gives invalidResponse', () async {
    expect(
      await errorOf((_) => jsonBody('{"weird":1}', 200)),
      isA<PlateAdviceInvalidResponse>(),
    );
    expect(
      await errorOf((_) => jsonBody('not json', 200)),
      isA<PlateAdviceInvalidResponse>(),
    );
  });

  test('503, 500 and a timeout give unavailable', () async {
    expect(
      await errorOf(
        (_) => jsonBody(
          protocolFile('fixtures/error-AI_PROVIDER_UNAVAILABLE.json')
              .readAsStringSync(),
          503,
        ),
      ),
      isA<PlateAdviceUnavailable>(),
    );
    expect(
      await errorOf(
        (_) => jsonBody(
          protocolFile('fixtures/error-INTERNAL_ERROR.json').readAsStringSync(),
          500,
        ),
      ),
      isA<PlateAdviceUnavailable>(),
    );
    expect(
      await errorOf(
        (options) => throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        ),
      ),
      isA<PlateAdviceUnavailable>(),
    );
  });

  test('a connection error gives offline', () async {
    expect(
      await errorOf(
        (o) => throw DioException.connectionError(
          requestOptions: o,
          reason: 'refused',
        ),
      ),
      isA<PlateAdviceOffline>(),
    );
  });

  test(
    'completing the cancel signal aborts the call without a failure state',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..httpClientAdapter = CancelAwareAdapter();
      final api = PlateAdviceApi(
        dio,
        fakeRemoteConfig(),
        newRequestId: () => 'id',
      );
      final cancel = Completer<void>();
      final future = api.getAdvice(testRequest(), cancel: cancel.future);
      cancel.complete();
      await expectLater(
        future,
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );
    },
  );
}
