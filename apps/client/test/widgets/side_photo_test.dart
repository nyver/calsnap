import 'dart:typed_data';

import 'package:calsnap/core/di/providers.dart';
import 'package:calsnap/features/camera/data/gateways.dart';
import 'package:calsnap/features/meal/domain/meal.dart';
import 'package:calsnap/features/meal/ui/meal_draft_notifier.dart';
import 'package:calsnap/features/recognition/domain/analysis.dart';
import 'package:calsnap/features/recognition/ui/analysis_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../support/fixtures.dart';

/// The main photo of the draft; a side photo is prepared as [1, 2, 3].
final Uint8List mainJpeg = Uint8List.fromList([9, 9, 9]);

class _Config extends FakeRemoteConfigRepository {
  _Config(super.app, this.maxImages);

  final int maxImages;

  @override
  Future<RemoteConfig> current() async => RemoteConfig(maxImages: maxImages);
}

/// The result of the two-photo analysis: the rice is bigger than first thought.
AnalysisResult refined() {
  final first = fixtureAnalysis('analyze-response-full.json');
  return AnalysisResult(
    requestId: first.requestId,
    warnings: first.warnings,
    items: [
      for (final it in first.items)
        RecognizedItem(
          id: it.id,
          name: it.name,
          normalizedName: it.normalizedName,
          estimatedWeightG: it.normalizedName == 'rice'
              ? 230
              : it.estimatedWeightG,
          confidence: it.confidence,
          nutritionSource: it.nutritionSource,
          per100: it.per100,
        ),
    ],
  );
}

/// Opens the result screen of a fresh recognition of the full fixture.
Future<FakeAnalysisApi> openResult(
  WidgetTester tester,
  TestApp app, {
  int maxImages = 2,
  Uint8List? sourceJpeg,
  Future<AnalysisResult> Function(FakeAnalysisCall call)? handler,
}) async {
  await app.completeOnboarding();
  final api = FakeAnalysisApi(handler ?? (_) async => refined());
  await tester.pumpWidget(
    app.app(
      overrides: [
        permissionGatewayProvider.overrideWithValue(
          FakePermissions(status: CameraAccess.permanentlyDenied),
        ),
        galleryPickerProvider.overrideWithValue(
          FakeGallery(protocolFile('fixtures/sample.jpg').absolute.path),
        ),
        analysisApiProvider.overrideWithValue(api),
        photoPreparerProvider.overrideWithValue(FakePreparer()),
        remoteConfigRepositoryProvider.overrideWithValue(
          _Config(app, maxImages),
        ),
      ],
    ),
  );
  await settle(tester);
  final notifier = containerOf(tester).read(mealDraftProvider.notifier);
  await realAsync(
    tester,
    () => notifier.startFromRecognition(
      fixtureAnalysis('analyze-response-full.json'),
      sourceJpeg: sourceJpeg ?? mainJpeg,
    ),
  );
  await push(tester, '/result');
  await settle(tester);
  return api;
}

Future<void> takeSidePhotoAndAnalyze(WidgetTester tester) async {
  await tapKey(tester, 'improveAccuracy');
  await settle(tester);
  await tapKey(tester, 'chooseFromGallery');
  await settle(tester);
  await tapKey(tester, 'analyze');
  await settle(tester, frames: 20);
}

void main() {
  const improve = Key('improveAccuracy');

  group('the offer', () {
    appTest('is a quiet button under the estimate when the server allows it', (
      tester,
      app,
    ) async {
      await openResult(tester, app);

      expect(find.byKey(improve), findsOneWidget);
      expect(find.text('Improve accuracy'), findsOneWidget);
      expect(find.textContaining('rice, pasta, potatoes'), findsOneWidget);
      // The usual flow is untouched: the save button is still the only action.
      expect(find.byKey(const Key('saveMeal')), findsOneWidget);
    });

    appTest('is absent when the server accepts one photo only', (
      tester,
      app,
    ) async {
      await openResult(tester, app, maxImages: 1);
      expect(find.byKey(improve), findsNothing);
    });

    appTest('is absent without the analyzed photo, e.g. for a manual meal', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      await tester.pumpWidget(
        app.app(
          overrides: [
            remoteConfigRepositoryProvider.overrideWithValue(_Config(app, 2)),
          ],
        ),
      );
      await settle(tester);
      containerOf(tester).read(mealDraftProvider.notifier).startManual();
      await push(tester, '/meal/new');
      await settle(tester);
      expect(find.byKey(improve), findsNothing);
    });
  });

  group('taking the side photo', () {
    appTest(
      'sends both photos, replaces the result and keeps the meal details',
      (tester, app) async {
        final api = await openResult(tester, app);
        final container = containerOf(tester);
        container.read(mealDraftProvider.notifier).setMealType(MealType.dinner);
        final before = container.read(mealDraftProvider)!;

        await tapKey(tester, 'improveAccuracy');
        await settle(tester);
        expect(find.text('Side photo'), findsOneWidget);
        expect(find.byKey(const Key('addManuallyFromCapture')), findsNothing);
        await tapKey(tester, 'chooseFromGallery');
        await settle(tester);
        await tapKey(tester, 'analyze');
        await settle(tester, frames: 20);

        expect(api.calls, hasLength(1));
        expect(api.calls.single.jpeg, mainJpeg);
        expect(api.calls.single.sideJpeg, [1, 2, 3]);

        expect(find.text('Recognized'), findsOneWidget);
        expect(find.widgetWithText(ActionChip, '230 g · estimate'), findsOne);
        expect(find.textContaining('Estimated from two photos.'), findsOne);
        expect(
          find.byKey(improve),
          findsNothing,
          reason: 'the offer is made once',
        );

        final after = container.read(mealDraftProvider)!;
        expect(after.withSidePhoto, isTrue);
        expect(after.fromRecognition, isTrue);
        expect(after.mealType, MealType.dinner);
        expect(after.mealTime, before.mealTime);
        expect(after.sourceJpeg, mainJpeg);
        expect(after.items.map((i) => i.estimatedWeightG), contains(230));
      },
    );

    appTest('the refined draft saves like any other', (tester, app) async {
      await openResult(tester, app);
      await takeSidePhotoAndAnalyze(tester);

      await tapKey(tester, 'saveMeal');
      await pumpUntil(
        tester,
        () => find.byKey(const Key('kcalProgress')).evaluate().isNotEmpty,
      );
      await settle(tester);

      final items = await app.itemRows();
      final rice = items.firstWhere((i) => i.name == 'Рис');
      expect(
        (rice.estimatedWeightG, rice.weightG, rice.wasCorrected),
        (230.0, 230.0, false),
      );
      expect(await app.mealRows(), hasLength(1));
    });

    appTest('edited items are replaced only after a confirmation', (
      tester,
      app,
    ) async {
      final api = await openResult(tester, app);
      final notifier = containerOf(tester).read(mealDraftProvider.notifier);
      final rice = containerOf(tester).read(mealDraftProvider)!.items.first;
      notifier.setWeight(rice.id, 150);
      await settle(tester);

      await tapKey(tester, 'improveAccuracy');
      await settle(tester);
      expect(find.text('Replace your changes?'), findsOneWidget);
      await tapKey(tester, 'replaceEditsCancel');
      await settle(tester);
      expect(find.text('Side photo'), findsNothing);
      expect(find.widgetWithText(ActionChip, '150 g'), findsOneWidget);
      expect(api.calls, isEmpty);

      await tapKey(tester, 'improveAccuracy');
      await settle(tester);
      await tapKey(tester, 'replaceEditsConfirm');
      await settle(tester);
      expect(find.text('Side photo'), findsOneWidget);
    });

    appTest('a failure keeps the first result and offers no manual restart', (
      tester,
      app,
    ) async {
      final api = await openResult(
        tester,
        app,
        handler: (_) async => throw const UnavailableFailure(),
      );

      await takeSidePhotoAndAnalyze(tester);
      expect(find.byKey(const Key('analysisError')), findsOneWidget);
      expect(find.byKey(const Key('analysisAddManually')), findsNothing);
      expect(find.byKey(const Key('analysisRetry')), findsOneWidget);

      await tapKey(tester, 'analysisKeepFirst');
      await settle(tester, frames: 20);

      expect(api.calls, hasLength(1));
      expect(find.text('Recognized'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, '170 g · estimate'), findsOne);
      final draft = containerOf(tester).read(mealDraftProvider)!;
      expect(draft.withSidePhoto, isFalse);
      expect(find.byKey(improve), findsOneWidget, reason: 'can try again');
    });
  });
}
