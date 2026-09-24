import 'dart:io';

import 'package:calsnap/core/di/providers.dart';
import 'package:calsnap/features/camera/data/gateways.dart';
import 'package:calsnap/features/meal/ui/meal_draft_notifier.dart';
import 'package:calsnap/features/recognition/domain/analysis.dart';
import 'package:calsnap/features/recognition/ui/analysis_controller.dart';
import 'package:calsnap/features/settings/domain/user_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../support/fixtures.dart';

String samplePhoto() => protocolFile('fixtures/sample.jpg').absolute.path;

List<Override> capture({
  required FakePermissions permissions,
  FakeGallery? gallery,
  FakeAnalysisApi? api,
  FakePreparer? preparer,
}) => [
  permissionGatewayProvider.overrideWithValue(permissions),
  galleryPickerProvider.overrideWithValue(gallery ?? FakeGallery()),
  if (api != null) analysisApiProvider.overrideWithValue(api),
  photoPreparerProvider.overrideWithValue(preparer ?? FakePreparer()),
];

Future<void> analyzeDirectly(
  WidgetTester tester, {
  String path = 'photo.jpg',
}) => push(tester, '/analysis', extra: AnalysisSource(path: path));

void main() {
  group('camera permission', () {
    appTest(
      'permanently denied: explains, offers settings, gallery and manual entry',
      (tester, app) async {
        await app.completeOnboarding();
        final permissions = FakePermissions(
          status: CameraAccess.permanentlyDenied,
        );
        await tester.pumpWidget(
          app.app(
            initialLocation: '/capture',
            overrides: capture(permissions: permissions),
          ),
        );
        await settle(tester);

        expect(find.text('Camera access is needed'), findsOneWidget);
        expect(
          find.textContaining(
            'choose a photo from the gallery or add the meal manually',
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('openSettings')), findsOneWidget);
        expect(find.byKey(const Key('chooseFromGallery')), findsOneWidget);
        expect(find.byKey(const Key('addManuallyFromCapture')), findsOneWidget);
        expect(find.byKey(const Key('allowCamera')), findsNothing);
        expect(
          permissions.requests,
          0,
          reason: 'a permanent denial is not asked again',
        );

        await tapKey(tester, 'openSettings');
        expect(permissions.settingsOpened, 1);
      },
    );

    appTest(
      'denied: the permission is requested at the point of use and the user can retry',
      (tester, app) async {
        await app.completeOnboarding();
        final permissions = FakePermissions(status: CameraAccess.denied);
        await tester.pumpWidget(
          app.app(
            initialLocation: '/capture',
            overrides: capture(permissions: permissions),
          ),
        );
        await settle(tester);

        expect(permissions.requests, 1, reason: 'the first camera open asks');
        expect(find.byKey(const Key('allowCamera')), findsOneWidget);
        await tapKey(tester, 'allowCamera');
        await settle(tester);
        expect(permissions.requests, 2);
      },
    );

    appTest('manual entry is offered when the camera cannot be used', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      final permissions = FakePermissions(
        status: CameraAccess.permanentlyDenied,
      );
      await tester.pumpWidget(
        app.app(
          initialLocation: '/capture',
          overrides: capture(permissions: permissions),
        ),
      );
      await settle(tester);

      await tapKey(tester, 'addManuallyFromCapture');
      await settle(tester, frames: 15);
      expect(find.text('New meal'), findsOneWidget);
    });

    appTest('gallery import shows the same preview with Retake and Analyze', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      final permissions = FakePermissions(
        status: CameraAccess.permanentlyDenied,
      );
      final gallery = FakeGallery(samplePhoto());
      await tester.pumpWidget(
        app.app(
          initialLocation: '/capture',
          overrides: capture(permissions: permissions, gallery: gallery),
        ),
      );
      await settle(tester);

      await tapKey(tester, 'chooseFromGallery');
      await settle(tester);
      expect(find.text('Check the photo'), findsOneWidget);
      expect(find.byKey(const Key('retake')), findsOneWidget);
      expect(find.byKey(const Key('analyze')), findsOneWidget);

      await tapKey(tester, 'retake');
      await settle(tester);
      expect(
        find.text('Take a photo'),
        findsOneWidget,
        reason: 'the viewfinder (here the permission screen) is back',
      );
      expect(
        File(samplePhoto()).existsSync(),
        isTrue,
        reason: 'gallery originals are never deleted',
      );
    });
  });

  group('analysis', () {
    appTest('success builds the recognition draft and opens the result', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      final api = FakeAnalysisApi(
        (_) async => fixtureAnalysis('analyze-response-full.json'),
      );
      final permissions = FakePermissions(
        status: CameraAccess.permanentlyDenied,
      );
      await tester.pumpWidget(
        app.app(
          overrides: capture(permissions: permissions, api: api),
        ),
      );
      await settle(tester);
      await analyzeDirectly(tester);
      await settle(tester, frames: 20);

      expect(find.text('Recognized'), findsOneWidget);
      expect(find.text('Рис'), findsOneWidget);
      expect(api.calls, hasLength(1));
      final draft = containerOf(tester).read(mealDraftProvider)!;
      expect(draft.items, hasLength(4));
      expect(draft.warnings, isEmpty);
    });

    appTest(
      'the request carries the app language, the plate diameter and a fresh id per analysis',
      (tester, app) async {
        await app.completeOnboarding(plate: 26, language: AppLanguage.en);
        var fail = true;
        final api = FakeAnalysisApi((_) async {
          if (fail) throw const UnavailableFailure();
          return fixtureAnalysis('analyze-response-full.json');
        });
        await tester.pumpWidget(
          app.app(
            overrides: capture(permissions: FakePermissions(), api: api),
          ),
        );
        await settle(tester);
        await analyzeDirectly(tester);
        await settle(tester, frames: 10);

        fail = false;
        await tapKey(tester, 'analysisRetry');
        await settle(tester, frames: 20);

        expect(api.calls, hasLength(2));
        expect(api.calls.map((c) => c.locale), ['en', 'en']);
        expect(api.calls.map((c) => c.plateDiameterCm), [26.0, 26.0]);
        expect(api.calls[0].requestId, isNot(api.calls[1].requestId));
        for (final call in api.calls) {
          expect(call.requestId, matches(RegExp(r'^[0-9a-f-]{36}$')));
        }
      },
    );

    appTest('a Russian app language is sent as locale=ru', (tester, app) async {
      await app.completeOnboarding(language: AppLanguage.ru);
      final api = FakeAnalysisApi(
        (_) async => fixtureAnalysis('analyze-response-full.json'),
      );
      await tester.pumpWidget(
        app.app(
          overrides: capture(permissions: FakePermissions(), api: api),
        ),
      );
      await settle(tester);
      await analyzeDirectly(tester);
      await settle(tester, frames: 20);
      expect(api.calls.single.locale, 'ru');
      expect(api.calls.single.plateDiameterCm, isNull);
    });

    appTest('progress messages are shown and the screen stays responsive', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      final pending = newCompleter<AnalysisResult>();
      final api = FakeAnalysisApi((_) => pending.future);
      await tester.pumpWidget(
        app.app(
          overrides: capture(permissions: FakePermissions(), api: api),
        ),
      );
      await settle(tester);
      await analyzeDirectly(tester);
      await settle(tester, frames: 6);

      expect(find.text('Analyzing your meal…'), findsOneWidget);
      expect(find.text('Identifying foods'), findsOneWidget);
      expect(find.text('Estimating portions'), findsOneWidget);
      expect(find.text('Calculating nutrition'), findsOneWidget);
      expect(find.byKey(const Key('analysisCancel')), findsOneWidget);
      await tester.pump(
        const Duration(seconds: 7),
      ); // the stage timer must not break anything
      pending.complete(fixtureAnalysis('analyze-response-full.json'));
      await settle(tester, frames: 20);
      expect(find.text('Recognized'), findsOneWidget);
    });

    appTest(
      'Cancel aborts the request, creates no meal and returns to the preview',
      (tester, app) async {
        await app.completeOnboarding();
        final pending = newCompleter<AnalysisResult>();
        final api = FakeAnalysisApi((call) {
          call.cancelToken!.whenCancel.then(pending.completeError);
          return pending.future;
        });
        final permissions = FakePermissions(
          status: CameraAccess.permanentlyDenied,
        );
        final gallery = FakeGallery(samplePhoto());
        await tester.pumpWidget(
          app.app(
            initialLocation: '/capture',
            overrides: capture(
              permissions: permissions,
              gallery: gallery,
              api: api,
            ),
          ),
        );
        await settle(tester);
        await tapKey(tester, 'chooseFromGallery');
        await settle(tester);
        await tapKey(tester, 'analyze');
        await settle(tester, frames: 10);
        expect(find.text('Analyzing your meal…'), findsOneWidget);

        await tapKey(tester, 'analysisCancel');
        await settle(tester, frames: 20);

        expect(api.calls.single.cancelToken!.isCancelled, isTrue);
        expect(
          find.text('Check the photo'),
          findsOneWidget,
          reason: 'back on the preview',
        );
        expect(find.byKey(const Key('analyze')), findsOneWidget);
        expect(await app.mealRows(), isEmpty);
        expect(containerOf(tester).read(mealDraftProvider), isNull);
      },
    );

    final failures =
        <
          String,
          ({AnalysisFailure failure, String message, List<String> buttons})
        >{
          'offline': (
            failure: const OfflineFailure(),
            message: 'No internet connection. The diary is available offline. Analyzing a new photo requires a network.',
            buttons: ['analysisRetry', 'analysisAddManually'],
          ),
          'timeout': (
            failure: const TimeoutFailure(),
            message: 'The analysis is taking too long. Please try again.',
            buttons: ['analysisRetry', 'analysisAddManually'],
          ),
          'rate limited': (
            failure: const RateLimitedFailure(),
            message: 'Too many requests. Please try again in a little while.',
            buttons: ['analysisRetry', 'analysisAddManually'],
          ),
          'unavailable': (
            failure: const UnavailableFailure(),
            message: 'The analysis service is temporarily unavailable. Please try again.',
            buttons: ['analysisRetry', 'analysisAddManually'],
          ),
          'unknown': (
            failure: const UnknownFailure(),
            message: 'Something went wrong. Please try again.',
            buttons: ['analysisRetry', 'analysisAddManually'],
          ),
          'nothing recognized': (
            failure: const NotRecognizedFailure(),
            message: 'Could not confidently recognize the dish.',
            buttons: ['tryAnotherPhoto', 'analysisAddManually'],
          ),
          'bad image': (
            failure: const BadImageFailure(),
            message: 'This photo cannot be analyzed. Try another photo.',
            buttons: ['tryAnotherPhoto', 'analysisAddManually'],
          ),
          'unreadable image': (
            failure: const BadImageFailure(BadImageReason.unreadable),
            message: 'This image cannot be read. Try another photo.',
            buttons: ['tryAnotherPhoto', 'analysisAddManually'],
          ),
        };
    failures.forEach((name, expected) {
      appTest(
        'failure "$name" shows a localized message with the right actions and no raw text',
        (tester, app) async {
          await app.completeOnboarding();
          final api = FakeAnalysisApi((_) async => throw expected.failure);
          await tester.pumpWidget(
            app.app(
              overrides: capture(permissions: FakePermissions(), api: api),
            ),
          );
          await settle(tester);
          await analyzeDirectly(tester);
          await settle(tester, frames: 10);

          expect(find.text(expected.message), findsOneWidget);
          for (final key in expected.buttons) {
            expect(find.byKey(Key(key)), findsOneWidget, reason: key);
          }
          expect(find.textContaining('Exception'), findsNothing);
          expect(find.textContaining('Instance of'), findsNothing);
          expect(find.byKey(const Key('analysisCancel')), findsNothing);
          expect(await app.mealRows(), isEmpty);
        },
      );
    });

    appTest('Add manually from a failure opens the manual editor', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      final api = FakeAnalysisApi((_) async => throw const OfflineFailure());
      await tester.pumpWidget(
        app.app(
          overrides: capture(permissions: FakePermissions(), api: api),
        ),
      );
      await settle(tester);
      await analyzeDirectly(tester);
      await settle(tester, frames: 10);

      await tapKey(tester, 'analysisAddManually');
      await settle(tester, frames: 20);
      expect(find.text('New meal'), findsOneWidget);
    });

    appTest('an image preparation failure is reported as an unreadable image', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      final broken = _ThrowingPreparer();
      await tester.pumpWidget(
        app.app(
          overrides: [
            permissionGatewayProvider.overrideWithValue(FakePermissions()),
            photoPreparerProvider.overrideWithValue(broken),
            analysisApiProvider.overrideWithValue(
              FakeAnalysisApi(
                (_) async => throw StateError('must not be called'),
              ),
            ),
          ],
        ),
      );
      await settle(tester);
      await analyzeDirectly(tester);
      await settle(tester, frames: 10);
      expect(
        find.text('This image cannot be read. Try another photo.'),
        findsOneWidget,
      );
    });
  });

  group('photo retention', () {
    Future<File> tempPhoto(TestApp app) => app.real(() async {
      final file = await app.services.photos.newTempFile();
      await file.writeAsBytes([1, 2, 3]);
      return file;
    });

    appTest(
      'with saving on, the prepared photo stays until the meal is saved',
      (tester, app) async {
        await app.completeOnboarding(savePhotos: true);
        final photo = await tempPhoto(app);
        final api = FakeAnalysisApi(
          (_) async => fixtureAnalysis('analyze-response-full.json'),
        );
        await tester.pumpWidget(
          app.app(
            overrides: capture(
              permissions: FakePermissions(),
              api: api,
              preparer: FakePreparer(tempFile: photo.path),
            ),
          ),
        );
        await settle(tester);
        await analyzeDirectly(tester);
        await settle(tester, frames: 20);

        expect(
          containerOf(tester).read(mealDraftProvider)!.tempPhotoFile,
          photo.path,
        );
        expect(await app.real(photo.exists), isTrue);

        await tapKey(tester, 'saveMeal');
        await pumpUntil(
          tester,
          () => find.byKey(const Key('kcalProgress')).evaluate().isNotEmpty,
        );
        final meal = (await app.mealRows()).single;
        expect(
          meal.photoPath,
          matches(RegExp(r'^meals/2026/03/10/[0-9a-f-]{36}\.jpg$')),
        );
        expect(app.services.photos.exists(meal.photoPath!), isTrue);
        expect(
          photo.existsSync(),
          isFalse,
          reason: 'the temporary copy is removed after a successful save',
        );
      },
    );

    appTest(
      'with saving off, no photo remains and the meal has no photo path',
      (tester, app) async {
        await app.completeOnboarding(savePhotos: false);
        final photo = await tempPhoto(app);
        final api = FakeAnalysisApi(
          (_) async => fixtureAnalysis('analyze-response-full.json'),
        );
        await tester.pumpWidget(
          app.app(
            overrides: capture(
              permissions: FakePermissions(),
              api: api,
              preparer: FakePreparer(tempFile: photo.path),
            ),
          ),
        );
        await settle(tester);
        await analyzeDirectly(tester);
        await pumpUntil(
          tester,
          () => containerOf(tester).read(mealDraftProvider) != null,
        );
        await settle(tester, frames: 20);

        expect(
          photo.existsSync(),
          isFalse,
          reason: 'deleted right after the successful analysis',
        );
        expect(
          containerOf(tester).read(mealDraftProvider)!.tempPhotoFile,
          isNull,
        );

        await tapKey(tester, 'saveMeal');
        await pumpUntil(
          tester,
          () => find.byKey(const Key('kcalProgress')).evaluate().isNotEmpty,
        );
        expect((await app.mealRows()).single.photoPath, isNull);
        final photosDir = Directory('${app.root.path}/docs/meals');
        expect(
          photosDir.existsSync()
              ? photosDir.listSync(recursive: true).whereType<File>()
              : <File>[],
          isEmpty,
        );
      },
    );

    appTest('discarding the result deletes the temporary photo', (
      tester,
      app,
    ) async {
      await app.completeOnboarding(savePhotos: true);
      final photo = await tempPhoto(app);
      final api = FakeAnalysisApi(
        (_) async => fixtureAnalysis('analyze-response-full.json'),
      );
      await tester.pumpWidget(
        app.app(
          overrides: capture(
            permissions: FakePermissions(),
            api: api,
            preparer: FakePreparer(tempFile: photo.path),
          ),
        ),
      );
      await settle(tester);
      await analyzeDirectly(tester);
      await settle(tester, frames: 20);

      await tester.pageBack();
      await settle(tester, frames: 10);
      await tapKey(tester, 'discardChanges');
      await pumpUntil(tester, () => !photo.existsSync());
      expect(photo.existsSync(), isFalse);
    });
  });
}

class _ThrowingPreparer implements PhotoPreparer {
  @override
  Future<PreparedPhoto> prepare(AnalysisSource source, RemoteConfig config) =>
      throw const FileSystemException('cannot read');
}
