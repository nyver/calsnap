import 'dart:io';

import 'package:calsnap/core/di/providers.dart';
import 'package:calsnap/features/camera/data/gateways.dart';
import 'package:calsnap/features/camera/data/photo_analyzer.dart';
import 'package:calsnap/features/camera/domain/photo_quality.dart';
import 'package:calsnap/features/camera/ui/plate_guide.dart';
import 'package:calsnap/features/recognition/ui/analysis_controller.dart';
import 'package:calsnap/features/settings/domain/user_settings.dart';
import 'package:calsnap/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../support/fixtures.dart';

String samplePhoto() => protocolFile('fixtures/sample.jpg').absolute.path;

PhotoQuality quality(List<PhotoIssue> issues) => PhotoQuality(
  sharpness: 100,
  meanLuma: 120,
  clippedFraction: 0,
  issues: issues,
);

/// Records how the photo was checked.
class Checks {
  Checks(this.issues);

  List<PhotoIssue> issues;

  /// False simulates a photo that cannot be decoded.
  bool judgeable = true;
  final List<({String path, bool checkPlate})> calls = [];

  Future<PhotoQuality?> call(String path, {required bool checkPlate}) async {
    calls.add((path: path, checkPlate: checkPlate));
    return judgeable ? quality(issues) : null;
  }
}

List<Override> overrides(Checks checks, {FakeAnalysisApi? api}) => [
  permissionGatewayProvider.overrideWithValue(
    FakePermissions(status: CameraAccess.permanentlyDenied),
  ),
  galleryPickerProvider.overrideWithValue(FakeGallery(samplePhoto())),
  photoQualityProvider.overrideWithValue(checks.call),
  photoPreparerProvider.overrideWithValue(FakePreparer()),
  if (api != null) analysisApiProvider.overrideWithValue(api),
];

Future<void> openPreview(
  WidgetTester tester,
  TestApp app,
  List<Override> overrides,
) async {
  await tester.pumpWidget(
    app.app(initialLocation: '/capture', overrides: overrides),
  );
  await settle(tester);
  await tapKey(tester, 'chooseFromGallery');
  await settle(tester);
}

void main() {
  group('the viewfinder guide', () {
    testWidgets('shows a plate outline and what to do', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: Scaffold(
            body: SizedBox(width: 300, height: 400, child: PlateGuide()),
          ),
        ),
      );
      expect(find.byKey(const Key('plateGuideOutline')), findsOneWidget);
      expect(
        find.text('Hold the camera directly above the plate'),
        findsOneWidget,
      );
    });

    testWidgets('never takes touches away from the shutter', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => taps++,
                    behavior: HitTestBehavior.opaque,
                  ),
                ),
                const Positioned.fill(child: PlateGuide()),
              ],
            ),
          ),
        ),
      );
      await tester.tapAt(const Offset(400, 300));
      expect(taps, 1);
    });
  });

  group('advice about the photo', () {
    appTest(
      'a steeply angled plate is explained and the photo can still be used',
      (tester, app) async {
        await app.completeOnboarding();
        final checks = Checks([PhotoIssue.steepAngle]);
        final api = FakeAnalysisApi(
          (_) async => fixtureAnalysis('analyze-response-full.json'),
        );
        await openPreview(tester, app, overrides(checks, api: api));

        expect(find.byKey(const Key('photoQualityBanner')), findsOneWidget);
        expect(find.text('Retake for a better estimate?'), findsOneWidget);
        expect(
          find.textContaining(
            'The plate is shot at a steep angle. For a more accurate',
          ),
          findsOneWidget,
        );
        expect(checks.calls.single.path, samplePhoto());
        expect(checks.calls.single.checkPlate, isTrue);

        // Advice, not a gate: Analyze still works.
        await tapKey(tester, 'analyze');
        await settle(tester, frames: 20);
        expect(api.calls, hasLength(1));
        expect(find.text('Recognized'), findsOneWidget);
      },
    );

    appTest('a good photo shows no banner', (tester, app) async {
      await app.completeOnboarding();
      await openPreview(tester, app, overrides(Checks(const [])));
      expect(find.byKey(const Key('photoQualityBanner')), findsNothing);
      expect(find.byKey(const Key('analyze')), findsOneWidget);
    });

    appTest('at most two problems are listed, the geometry ones first', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      final checks = Checks([
        PhotoIssue.tooDark,
        PhotoIssue.blurry,
        PhotoIssue.steepAngle,
      ]);
      await openPreview(tester, app, overrides(checks));

      expect(find.textContaining('steep angle'), findsOneWidget);
      expect(find.textContaining('blurry'), findsOneWidget);
      expect(find.textContaining('too dark'), findsNothing);
    });

    appTest('advice is in Russian for the Russian app language', (
      tester,
      app,
    ) async {
      await app.completeOnboarding(language: AppLanguage.ru);
      await openPreview(
        tester,
        app,
        overrides(Checks([PhotoIssue.steepAngle])),
      );
      expect(
        find.textContaining('Тарелка снята под большим углом'),
        findsOneWidget,
      );
      expect(find.textContaining('сфотографируйте сверху'), findsOneWidget);
    });

    appTest('a new photo is checked again and the old advice goes away', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      final checks = Checks([PhotoIssue.blurry]);
      await openPreview(tester, app, overrides(checks));
      expect(find.byKey(const Key('photoQualityBanner')), findsOneWidget);

      checks.issues = const [];
      await tapKey(tester, 'retake');
      await settle(tester);
      expect(find.byKey(const Key('photoQualityBanner')), findsNothing);
      await tapKey(tester, 'chooseFromGallery');
      await settle(tester);
      expect(checks.calls, hasLength(2));
      expect(find.byKey(const Key('photoQualityBanner')), findsNothing);
    });

    appTest('a photo that cannot be judged gets no advice', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      final checks = Checks([PhotoIssue.blurry])..judgeable = false;
      await openPreview(tester, app, overrides(checks));
      expect(find.byKey(const Key('photoQualityBanner')), findsNothing);
      expect(find.byKey(const Key('analyze')), findsOneWidget);
    });
  });

  group('my usual plate', () {
    Future<void> choose(
      WidgetTester tester, {
      int? preset,
      String? custom,
      bool remember = true,
    }) async {
      await tapKey(tester, 'plateChip');
      await settle(tester);
      if (preset != null) await tapKey(tester, 'platePreset-$preset');
      if (custom != null) await enterKey(tester, 'plateCustom', custom);
      if (!remember) await tapKey(tester, 'plateRemember');
      await settle(tester);
    }

    appTest(
      'the chip invites to add a size, and a preset is saved as the usual plate',
      (tester, app) async {
        await app.completeOnboarding();
        await openPreview(tester, app, overrides(Checks(const [])));
        expect(find.text('Add plate size'), findsOneWidget);

        await choose(tester, preset: 26);
        await tapKey(tester, 'plateApply');
        await settle(tester);

        expect((await app.settings()).plateDiameterCm, 26);
        expect(find.text('My usual plate: 26 cm'), findsOneWidget);
      },
    );

    appTest(
      'a size for this photo only leaves the saved plate alone and is sent',
      (tester, app) async {
        await app.completeOnboarding(plate: 26);
        final api = FakeAnalysisApi(
          (_) async => fixtureAnalysis('analyze-response-full.json'),
        );
        await openPreview(tester, app, overrides(Checks(const []), api: api));
        expect(find.text('My usual plate: 26 cm'), findsOneWidget);

        await choose(tester, preset: 24, remember: false);
        await tapKey(tester, 'plateApply');
        await settle(tester);
        expect(find.text('Plate for this photo: 24 cm'), findsOneWidget);
        expect((await app.settings()).plateDiameterCm, 26);

        await tapKey(tester, 'analyze');
        await settle(tester, frames: 20);
        expect(api.calls.single.plateDiameterCm, 24);
      },
    );

    appTest('the saved plate is what the analysis sends by default', (
      tester,
      app,
    ) async {
      await app.completeOnboarding(plate: 26);
      final api = FakeAnalysisApi(
        (_) async => fixtureAnalysis('analyze-response-full.json'),
      );
      await openPreview(tester, app, overrides(Checks(const []), api: api));
      await tapKey(tester, 'analyze');
      await settle(tester, frames: 20);
      expect(api.calls.single.plateDiameterCm, 26);
    });

    appTest('"No plate size" for one photo sends none', (tester, app) async {
      await app.completeOnboarding(plate: 26);
      final api = FakeAnalysisApi(
        (_) async => fixtureAnalysis('analyze-response-full.json'),
      );
      await openPreview(tester, app, overrides(Checks(const []), api: api));
      await tapKey(tester, 'plateChip');
      await settle(tester);
      await tapKey(tester, 'plateRemember');
      await tapKey(tester, 'plateNone');
      await settle(tester);
      expect(find.text('Add plate size'), findsOneWidget);
      expect((await app.settings()).plateDiameterCm, 26);

      await tapKey(tester, 'analyze');
      await settle(tester, frames: 20);
      expect(api.calls.single.plateDiameterCm, isNull);
    });

    appTest('a custom size is validated like the setting', (tester, app) async {
      await app.completeOnboarding();
      await openPreview(tester, app, overrides(Checks(const [])));

      await choose(tester, custom: '5');
      expect(
        find.textContaining('Enter a value from 10 to 40 cm'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('plateApply')))
            .onPressed,
        isNull,
      );

      await enterKey(tester, 'plateCustom', '27.5');
      await settle(tester);
      await tapKey(tester, 'plateApply');
      await settle(tester);
      expect((await app.settings()).plateDiameterCm, 27.5);
    });

    appTest('the setting is called "My usual plate"', (tester, app) async {
      await app.completeOnboarding(plate: 24);
      await tester.pumpWidget(app.app(initialLocation: '/settings'));
      await settle(tester);
      expect(find.text('My usual plate'), findsOneWidget);
    });
  });

  group('checking a photo file', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('calsnap_quality_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('an unreadable or missing file cannot be judged', () {
      File('${dir.path}/broken.jpg').writeAsBytesSync([1, 2, 3, 4]);
      expect(
        assessPhotoFileSync('${dir.path}/broken.jpg', checkPlate: true),
        isNull,
      );
      expect(
        assessPhotoFileSync('${dir.path}/none.jpg', checkPlate: true),
        isNull,
      );
    });

    test('the isolate version answers like the synchronous one', () async {
      File('${dir.path}/broken.jpg').writeAsBytesSync([1, 2, 3, 4]);
      expect(
        await assessPhotoFile('${dir.path}/broken.jpg', checkPlate: true),
        isNull,
      );
    });
  });
}
