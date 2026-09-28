import 'dart:io';
import 'dart:typed_data';

import 'package:calsnap/app/app.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../test/support/app_harness.dart' show settle, tapKey;
import '../test/support/fixtures.dart' show protocolFile;
import '../test/support/photo_flow.dart';

/// Serves `/v1/meals/analyze`, `/v1/config` (with `plateAdvice: true`) and
/// `/v1/plate-advice` from memory: no network is involved.
class PlateAdviceFixtureBackendAdapter extends FixtureBackendAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    await requestStream?.drain<void>();
    final String body;
    switch (options.path) {
      case '/v1/meals/analyze':
        body = analyzeFullJson;
      case '/v1/config':
        body =
            '{"imageMaxLongSidePx":1280,"imageJpegQuality":80,'
            '"maxUploadBytes":4194304,"analyzeTimeoutSeconds":60,'
            '"plateAdvice":true}';
      case '/v1/plate-advice':
        body = protocolFile('fixtures/plate-advice-response-en.json')
            .readAsStringSync();
      default:
        body = '{"code":"INVALID_REQUEST","message":"Unknown route.","requestId":"x"}';
    }
    return ResponseBody.fromString(
      body,
      options.path.startsWith('/v1/') ? 200 : 404,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Runs the plate-advice acceptance flow (spec's Integration test) on a
/// device or emulator with the real database, real file system and real
/// image pipeline. The camera is replaced by a photo generated on the fly
/// and the backend by an in-memory fixture server.
///
///   flutter test integration_test/plate_advice_flow_test.dart -d DEVICE_ID
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('open the editor, get AI suggestions, edit a weight, refresh', (
    tester,
  ) async {
    // A clean slate: earlier runs must not leave a diary behind.
    final support = await getApplicationSupportDirectory();
    for (final name in ['calsnap.db', 'calsnap.db-wal', 'calsnap.db-shm']) {
      final f = File(p.join(support.path, name));
      if (f.existsSync()) f.deleteSync();
    }
    final documents = await getApplicationDocumentsDirectory();
    final meals = Directory(p.join(documents.path, 'meals'));
    if (meals.existsSync()) meals.deleteSync(recursive: true);

    final temp = await getTemporaryDirectory();
    final photo = File(p.join(temp.path, 'integration-plate-advice.jpg'));
    await photo.writeAsBytes(samplePhotoBytes());

    final backend = PlateAdviceFixtureBackendAdapter();
    await tester.pumpWidget(
      scoped(
        fixtureBackendOverrides(photoPath: photo.path, backend: backend),
        const CalSnapApp(),
      ),
    );

    Future<void> waitFor(Finder finder, {int attempts = 80}) async {
      for (var i = 0; i < attempts && finder.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(finder, findsWidgets, reason: 'timed out waiting for $finder');
    }

    // Onboarding, then a photo through the gallery -> analysis.
    for (var i = 0; i < 80; i++) {
      if (find.byKey(const Key('onboardingNext')).evaluate().isNotEmpty ||
          find.byKey(const Key('kcalProgress')).evaluate().isNotEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 50));
    }
    if (find.byKey(const Key('onboardingNext')).evaluate().isNotEmpty) {
      await tapKey(tester, 'onboardingNext');
      await settle(tester, frames: 8);
      await tester.enterText(find.byKey(const Key('kcalField')), '2200');
      await tester.pump();
      await tapKey(tester, 'onboardingNext');
      await settle(tester, frames: 8);
      await tapKey(tester, 'onboardingSkip');
      await settle(tester, frames: 8);
      await tapKey(tester, 'onboardingSkip');
      await settle(tester, frames: 8);
      await tapKey(tester, 'onboardingSkipCamera');
    }
    await waitFor(find.byKey(const Key('kcalProgress')));

    await tapKey(tester, 'addMeal');
    await settle(tester, frames: 12);
    await tapKey(tester, 'addFromGallery');
    await waitFor(find.byKey(const Key('analyze')));
    await tapKey(tester, 'analyze');
    await waitFor(find.text('Recognized'));

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
    await waitFor(find.byKey(const Key('plateAdviceLoaded')));

    // 5. The request reached the backend.
    expect(
      backend.requests.where((r) => r.path == '/v1/plate-advice'),
      hasLength(1),
    );

    // 6. The advice card is shown.
    expect(find.byKey(const Key('plateAdviceLoaded')), findsOneWidget);

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

    // 9. Refresh.
    await tester.ensureVisible(find.byKey(const Key('plateAdviceRefresh')));
    await tester.pump();
    await tapKey(tester, 'plateAdviceRefresh');
    await waitFor(find.byKey(const Key('plateAdviceLoaded')));

    // 10. New advice, from a second request.
    expect(
      backend.requests.where((r) => r.path == '/v1/plate-advice'),
      hasLength(2),
    );
    expect(find.byKey(const Key('plateAdviceLoaded')), findsOneWidget);
    expect(find.byKey(const Key('plateAdviceStale')), findsNothing);
  });
}
