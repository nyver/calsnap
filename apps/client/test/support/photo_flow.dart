import 'dart:convert';
import 'dart:typed_data';

import 'package:calsnap/core/di/providers.dart';
import 'package:calsnap/features/camera/data/gateways.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'app_harness.dart';

/// The `analyze-response-full.json` protocol fixture, inlined so that the flow
/// also runs on a device, where the repository files are not available.
const String analyzeFullJson = '''
{
  "requestId": "0190f7a2-1b2c-7d3e-8f40-123456789abc",
  "items": [
    {"id": "temp-1", "name": "Rice", "normalizedName": "rice", "estimatedWeightG": 170, "confidence": 0.86,
     "nutritionSource": "catalog",
     "nutrition": {"kcalPer100g": 130, "proteinPer100g": 2.7, "fatPer100g": 0.3, "carbsPer100g": 28}},
    {"id": "temp-2", "name": "Chicken breast", "normalizedName": "chicken_breast", "estimatedWeightG": 135, "confidence": 0.92,
     "nutritionSource": "catalog",
     "nutrition": {"kcalPer100g": 165, "proteinPer100g": 31, "fatPer100g": 3.6, "carbsPer100g": 0}},
    {"id": "temp-3", "name": "Cucumber", "normalizedName": "cucumber", "estimatedWeightG": 80, "confidence": 0.81,
     "nutritionSource": "catalog",
     "nutrition": {"kcalPer100g": 15, "proteinPer100g": 0.7, "fatPer100g": 0.1, "carbsPer100g": 3.6}},
    {"id": "temp-4", "name": "Tomato", "normalizedName": "tomato", "estimatedWeightG": 65, "confidence": 0.78,
     "nutritionSource": "catalog",
     "nutrition": {"kcalPer100g": 18, "proteinPer100g": 0.9, "fatPer100g": 0.2, "carbsPer100g": 3.9}}
  ],
  "warnings": []
}
''';

/// Serves the backend contract from memory: no network is involved.
class FixtureBackendAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    await requestStream?.drain<void>();
    final body = switch (options.path) {
      '/v1/meals/analyze' => analyzeFullJson,
      '/v1/config' => jsonEncode({
        'imageMaxLongSidePx': 1280,
        'imageJpegQuality': 80,
        'maxUploadBytes': 4194304,
        'analyzeTimeoutSeconds': 60,
      }),
      _ =>
        '{"code":"INVALID_REQUEST","message":"Unknown route.","requestId":"x"}',
    };
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

/// Overrides that replace the camera (a fixture photo from the gallery picker)
/// and the network (an in-memory backend).
List<Override> fixtureBackendOverrides({
  required String photoPath,
  required FixtureBackendAdapter backend,
}) => [
  dioProvider.overrideWith((ref) {
    final dio = Dio(BaseOptions(baseUrl: 'https://backend.invalid'))
      ..httpClientAdapter = backend;
    return dio;
  }),
  galleryPickerProvider.overrideWithValue(_FixedGallery(photoPath)),
  permissionGatewayProvider.overrideWithValue(
    FakePermissions(
      status: CameraAccess.denied,
      requestResult: CameraAccess.denied,
    ),
  ),
];

class _FixedGallery implements GalleryPicker {
  const _FixedGallery(this.path);

  final String path;

  @override
  Future<String?> pick() async => path;
}

/// The acceptance flow of the MVP, driven through the UI only:
/// onboarding (when needed) -> gallery photo instead of the camera -> analysis
/// against the fixture backend -> change a weight -> save -> app restart ->
/// the diary, the history calendar and the statistics still show the meal.
///
/// [buildApp] must create a NEW provider scope each time it is called, so that
/// the second call simulates a restart of the app process.
Future<void> runPhotoFlow(
  WidgetTester tester, {
  required Widget Function() buildApp,
  DateTime? today,
}) async {
  Finder key(String k) => find.byKey(Key(k));
  Future<void> tap(String k) async {
    await tester.tap(key(k));
    await tester.pump();
  }

  Future<void> waitFor(Finder finder, {int attempts = 80}) async {
    for (var i = 0; i < attempts && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await realAsync(
        tester,
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    }
    expect(finder, findsWidgets, reason: 'timed out waiting for $finder');
  }

  await tester.pumpWidget(buildApp());
  // The splash screen initializes the app and routes to onboarding or the diary.
  for (var i = 0; i < 80; i++) {
    if (key('onboardingNext').evaluate().isNotEmpty ||
        key('kcalProgress').evaluate().isNotEmpty) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 50));
    await realAsync(
      tester,
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }

  // First launch: onboarding without any account.
  if (key('onboardingNext').evaluate().isNotEmpty) {
    await tap('onboardingNext'); // intro
    await settle(tester, frames: 8);
    await tester.enterText(key('kcalField'), '2200');
    await tester.pump();
    await tap('onboardingNext'); // target
    await settle(tester, frames: 8);
    await tap('onboardingSkip'); // macros
    await settle(tester, frames: 8);
    await tap('onboardingSkip'); // plate
    await settle(tester, frames: 8);
    await tap('onboardingSkipCamera');
  }
  await waitFor(key('kcalProgress'));
  expect(find.text('0 / 2200 kcal'), findsOneWidget);

  // Add -> gallery -> preview -> analyze.
  await tap('addMeal');
  await settle(tester, frames: 12);
  await tap('addFromGallery');
  await waitFor(key('analyze'));
  await tap('analyze');
  await waitFor(find.text('Recognized'));
  expect(find.text('Rice'), findsOneWidget);
  expect(find.text('≈ 470 kcal'), findsOneWidget);

  // Edit the weight of the rice in one action, then save.
  await tester.tap(find.widgetWithText(ActionChip, '170 g · estimate'));
  await settle(tester, frames: 10);
  await tester.enterText(key('weightField'), '150');
  await tester.pump();
  await tap('weightApply');
  await settle(tester, frames: 10);
  expect(find.text('≈ 440 kcal'), findsOneWidget);
  await tap('saveMeal');
  await waitFor(find.text('441 / 2200 kcal'));

  // Restart: a brand new provider scope (nothing survives but the disk).
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 200));
  await realAsync(
    tester,
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pumpWidget(buildApp());
  await waitFor(find.text('441 / 2200 kcal'));

  // History marks the day, statistics reflect it.
  await tester.tap(find.text('History'));
  await settle(tester, frames: 15);
  await waitFor(key('marker-${(today ?? DateTime.now()).day}'));
  await tester.tap(find.text('Statistics'));
  await settle(tester, frames: 15);
  await waitFor(find.text('441 kcal'));
  expect(
    find.text('1 of 1 logged day on target'),
    findsNothing,
    reason: '441 kcal is far from the 2200 kcal target',
  );
  expect(find.text('0 of 1 logged day on target'), findsOneWidget);
}

/// A small valid JPEG (64x48 gradient) for runs where no fixture file exists.
Uint8List samplePhotoBytes() {
  final image = img.Image(width: 64, height: 48);
  for (final px in image) {
    px
      ..r = px.x * 4 % 256
      ..g = px.y * 5 % 256
      ..b = (px.x + px.y) * 2 % 256;
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 80));
}

/// Scope with the same settings as main().
Widget scoped(List<Override> overrides, Widget child) => ProviderScope(
  retry: (retryCount, error) => null,
  overrides: overrides,
  child: child,
);
