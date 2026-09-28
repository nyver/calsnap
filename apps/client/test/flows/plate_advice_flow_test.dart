import 'dart:typed_data';

import 'package:calsnap/core/di/providers.dart';
import 'package:calsnap/features/balanced_plate/domain/plate_group.dart';
import 'package:calsnap/features/recognition/data/remote_config_repository.dart';
import 'package:calsnap/features/recognition/domain/analysis.dart';
import 'package:calsnap/features/recognition/ui/analysis_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../support/fixtures.dart';

/// Serves `/v1/plate-advice` (and reports the capability on `/v1/config`) from
/// memory: no network is involved. [offline] simulates a lost connection.
class PlateAdviceBackendAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  bool offline = false;
  String responseFixture = 'plate-advice-response-en.json';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    await requestStream?.drain<void>();
    if (offline && options.path == '/v1/plate-advice') {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'no network',
      );
    }
    final body = switch (options.path) {
      '/v1/plate-advice' => protocolFile(
        'fixtures/$responseFixture',
      ).readAsStringSync(),
      _ =>
        '{"code":"INVALID_REQUEST","message":"Unknown route.","requestId":"x"}',
    };
    return ResponseBody.fromString(
      body,
      options.path == '/v1/plate-advice' ? 200 : 404,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A [RemoteConfigRepository] that always reports `plateAdvice: true`, so the
/// flow does not need a real `/v1/config` round trip.
class _PlateAdviceRemoteConfig extends RemoteConfigRepository {
  _PlateAdviceRemoteConfig(TestApp app)
    : super(
        app.services.settings,
        FakeAnalysisApi((_) async => throw UnimplementedError()),
      );

  @override
  Future<RemoteConfig> current() async => const RemoteConfig(plateAdvice: true);
}

List<Override> _plateAdviceOverrides(
  TestApp app,
  PlateAdviceBackendAdapter backend,
) => [
  dioProvider.overrideWith((ref) {
    final dio = Dio(BaseOptions(baseUrl: 'https://backend.invalid'))
      ..httpClientAdapter = backend;
    return dio;
  }),
  remoteConfigRepositoryProvider.overrideWith(
    (ref) => _PlateAdviceRemoteConfig(app),
  ),
];

void main() {
  appTest('open the editor, get AI suggestions, edit a weight, refresh', (
    tester,
    app,
  ) async {
    await app.completeOnboarding();
    final backend = PlateAdviceBackendAdapter();
    await tester.pumpWidget(
      app.app(overrides: _plateAdviceOverrides(app, backend)),
    );
    await settle(tester);

    // 1-2. Open the editor with classified foods (from the shared fixture,
    // resolved against the real catalog: rice, chicken breast, cucumber,
    // tomato).
    await openRecognition(tester, 'analyze-response-full.json');
    await settle(tester, frames: 15);

    // 3. The local Balance card is evaluable and visible.
    await tester.scrollUntilVisible(
      find.byKey(const Key('balancedPlateCard')),
      300,
    );
    expect(find.byKey(const Key('balancedPlateCard')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('plateAdviceButton')));
    await tester.pump();
    expect(find.byKey(const Key('plateAdviceButton')), findsOneWidget);

    // 4. Tap "Get AI suggestions" and accept the one-time notice.
    await tapKey(tester, 'plateAdviceButton');
    await settle(tester, frames: 5);
    expect(find.byKey(const Key('plateAdviceNotice')), findsOneWidget);
    await tapKey(tester, 'plateAdviceNoticeContinue');
    await settle(tester, frames: 15);

    // 5. The request reached the backend.
    expect(
      backend.requests.where((r) => r.path == '/v1/plate-advice'),
      hasLength(1),
    );

    // 6. The advice card is shown.
    expect(find.byKey(const Key('plateAdviceLoaded')), findsOneWidget);
    expect(find.byKey(const Key('plateAdviceStale')), findsNothing);

    // 7. Change an item's weight.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 5000));
    await settle(tester, frames: 10);
    await tester.tap(find.widgetWithText(ActionChip, '170 g · estimate'));
    await settle(tester, frames: 10);
    await tester.enterText(find.byKey(const Key('weightField')), '220');
    await tester.pump();
    await tapKey(tester, 'weightApply');
    await settle(tester, frames: 10);

    // 8. The advice becomes stale.
    await tester.scrollUntilVisible(
      find.byKey(const Key('plateAdviceStale')),
      300,
    );
    expect(find.byKey(const Key('plateAdviceStale')), findsOneWidget);
    expect(find.byKey(const Key('plateAdviceLoaded')), findsNothing);

    // 9. Refresh.
    await tester.ensureVisible(find.byKey(const Key('plateAdviceRefresh')));
    await tester.pump();
    await tapKey(tester, 'plateAdviceRefresh');
    await settle(tester, frames: 15);

    // 10. New advice is shown, from a second request (no notice this time).
    expect(find.byKey(const Key('plateAdviceNotice')), findsNothing);
    expect(
      backend.requests.where((r) => r.path == '/v1/plate-advice'),
      hasLength(2),
    );
    expect(find.byKey(const Key('plateAdviceLoaded')), findsOneWidget);
    expect(find.byKey(const Key('plateAdviceStale')), findsNothing);
  });

  appTest('offline: the local card works, AI shows a friendly error', (
    tester,
    app,
  ) async {
    await app.completeOnboarding();
    final draft = draftOf([
      aiItem(
        'a',
        name: 'Rice',
        weight: 170,
      ).copyWith(plateGroup: PlateGroup.complexCarbohydrate),
      aiItem(
        'b',
        name: 'Chicken breast',
        weight: 135,
      ).copyWith(plateGroup: PlateGroup.protein),
      aiItem(
        'c',
        name: 'Cucumber',
        weight: 80,
      ).copyWith(plateGroup: PlateGroup.vegetable),
    ]);
    final mealId = await app.saveMeal(draft);

    final backend = PlateAdviceBackendAdapter()..offline = true;
    await tester.pumpWidget(
      app.app(
        initialLocation: '/meal/$mealId',
        overrides: _plateAdviceOverrides(app, backend),
      ),
    );
    await settle(tester, frames: 15);

    await tester.scrollUntilVisible(
      find.byKey(const Key('balancedPlateCard')),
      300,
    );
    expect(find.byKey(const Key('balancedPlateCard')), findsOneWidget);
    final percentBefore = find.textContaining('%').evaluate().length;
    expect(percentBefore, greaterThan(0));

    await tester.ensureVisible(find.byKey(const Key('plateAdviceButton')));
    await tester.pump();
    await tapKey(tester, 'plateAdviceButton');
    await settle(tester, frames: 5);
    await tapKey(tester, 'plateAdviceNoticeContinue');
    await settle(tester, frames: 15);

    expect(
      find.text('AI suggestions require a connection to the CalSnap server.'),
      findsOneWidget,
    );
    // The local card is unaffected.
    await tester.scrollUntilVisible(
      find.byKey(const Key('balancedPlateCard')),
      300,
    );
    expect(find.byKey(const Key('balancedPlateCard')), findsOneWidget);
    expect(find.textContaining('%').evaluate().length, percentBefore);
  });
}
