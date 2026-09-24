import 'package:calsnap/features/camera/data/gateways.dart';
import 'package:calsnap/features/export/data/export_service.dart';
import 'package:calsnap/features/settings/domain/user_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../support/fixtures.dart';

void settingsTest(
  String name,
  Future<void> Function(WidgetTester, TestApp) body,
) => appTest(name, body, height: 2400);

void main() {
  group('onboarding', () {
    appTest(
      'the first launch shows the estimate notice and asks for no account',
      (tester, app) async {
        await tester.pumpWidget(app.app(initialLocation: '/splash'));
        await settle(tester);

        expect(
          find.textContaining('estimates, not exact measurements'),
          findsOneWidget,
        );
        expect(find.text('Step 1 of 5'), findsOneWidget);
        expect(find.textContaining('sign', findRichText: true), findsNothing);
      },
    );

    appTest('an invalid calorie target blocks the step', (tester, app) async {
      await tester.pumpWidget(app.app(initialLocation: '/splash'));
      await settle(tester);

      await tapKey(tester, 'onboardingNext');
      await settle(tester);
      expect(find.byKey(const Key('kcalField')), findsOneWidget);

      await enterKey(tester, 'kcalField', '100');
      expect(find.text('Enter a value from 800 to 6000 kcal.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('onboardingNext')))
            .onPressed,
        isNull,
      );

      await enterKey(tester, 'kcalField', '6001');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('onboardingNext')))
            .onPressed,
        isNull,
      );
      await enterKey(tester, 'kcalField', '800');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('onboardingNext')))
            .onPressed,
        isNotNull,
      );
      await enterKey(tester, 'kcalField', '');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('onboardingNext')))
            .onPressed,
        isNull,
      );
    });

    appTest('optional steps can be skipped and onboarding completes', (
      tester,
      app,
    ) async {
      final permissions = FakePermissions(status: CameraAccess.denied);
      await tester.pumpWidget(
        app.app(
          initialLocation: '/splash',
          overrides: [permissionGatewayProvider.overrideWithValue(permissions)],
        ),
      );
      await settle(tester);

      await tapKey(tester, 'onboardingNext'); // intro -> target
      await settle(tester);
      await enterKey(tester, 'kcalField', '2200');
      await tapKey(tester, 'onboardingNext'); // target -> macros
      await settle(tester);
      await tapKey(tester, 'onboardingSkip'); // skip macros
      await settle(tester);
      await tapKey(tester, 'onboardingSkip'); // skip plate
      await settle(tester);
      expect(find.text('Camera access'), findsOneWidget);
      await tapKey(tester, 'onboardingSkipCamera');
      await settle(tester);

      final settings = await app.settings();
      expect(settings.onboardingCompleted, isTrue);
      expect(settings.dailyKcalTarget, 2200);
      expect(settings.dailyProteinTargetG, isNull);
      expect(settings.dailyFatTargetG, isNull);
      expect(settings.dailyCarbsTargetG, isNull);
      expect(settings.plateDiameterCm, isNull);
      expect(
        permissions.requests,
        0,
        reason: 'skipping must not ask for the permission',
      );
      expect(
        find.text('0 / 2200 kcal'),
        findsOneWidget,
        reason: 'the diary shows the 2200 kcal target',
      );
    });

    appTest(
      'all values are validated and stored, and the camera permission is requested at the end',
      (tester, app) async {
        final permissions = FakePermissions(
          status: CameraAccess.denied,
          requestResult: CameraAccess.granted,
        );
        await tester.pumpWidget(
          app.app(
            initialLocation: '/splash',
            overrides: [
              permissionGatewayProvider.overrideWithValue(permissions),
            ],
          ),
        );
        await settle(tester);

        await tapKey(tester, 'onboardingNext');
        await settle(tester);
        await enterKey(tester, 'kcalField', '1900');
        await tapKey(tester, 'onboardingNext');
        await settle(tester);
        await enterKey(tester, 'proteinField', '120');
        await enterKey(tester, 'fatField', '600');
        expect(
          find.text('Enter 0 to 500 g or leave the field empty.'),
          findsOneWidget,
        );
        await enterKey(tester, 'fatField', '60');
        await enterKey(tester, 'carbsField', '200');
        await tapKey(tester, 'onboardingNext');
        await settle(tester);
        await enterKey(tester, 'plateField', '5');
        expect(
          find.text('Enter a value from 10 to 40 cm or leave the field empty.'),
          findsOneWidget,
        );
        await enterKey(tester, 'plateField', '26,5');
        await tapKey(tester, 'onboardingNext');
        await settle(tester);
        await tapKey(tester, 'onboardingAllowCamera');
        await settle(tester);

        final s = await app.settings();
        expect(
          (
            s.dailyKcalTarget,
            s.dailyProteinTargetG,
            s.dailyFatTargetG,
            s.dailyCarbsTargetG,
          ),
          (1900, 120, 60, 200),
        );
        expect(s.plateDiameterCm, 26.5);
        expect(s.onboardingCompleted, isTrue);
        expect(permissions.requests, 1);
      },
    );

    appTest('a returning user opens the diary directly', (tester, app) async {
      await app.completeOnboarding(kcal: 2000);

      await tester.pumpWidget(app.app(initialLocation: '/splash'));
      await settle(tester);

      expect(find.byKey(const Key('kcalProgress')), findsOneWidget);
      expect(find.text('Today'), findsWidgets);
    });
  });

  group('settings', () {
    Future<void> openSettings(
      WidgetTester tester,
      TestApp app, {
      List<Override> overrides = const [],
    }) async {
      await tester.pumpWidget(
        app.app(initialLocation: '/settings', overrides: overrides),
      );
      await settle(tester);
    }

    settingsTest('a changed calorie target is applied immediately', (
      tester,
      app,
    ) async {
      await app.completeOnboarding(kcal: 2200);
      await openSettings(tester, app);

      expect(find.text('2200 kcal'), findsOneWidget);
      await tapKey(tester, 'settingKcal');
      await settle(tester);
      await enterKey(tester, 'numberDialogField', '100');
      expect(find.text('Enter a value from 800 to 6000 kcal.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('numberDialogApply')))
            .onPressed,
        isNull,
      );
      await enterKey(tester, 'numberDialogField', '1800');
      await tapKey(tester, 'numberDialogApply');
      await settle(tester);

      expect(find.text('1800 kcal'), findsOneWidget);
      expect((await app.settings()).dailyKcalTarget, 1800);

      // The diary immediately shows progress against the new target.
      await tester.tap(find.text('Diary'));
      await settle(tester);
      expect(find.text('0 / 1800 kcal'), findsOneWidget);
    });

    settingsTest('the server address is validated, saved and can be reset', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      await openSettings(tester, app);
      // Debug test builds start with the emulator default.
      expect(find.text('http://10.0.2.2:8445'), findsOneWidget);

      await tapKey(tester, 'settingServerUrl');
      await settle(tester);
      await enterKey(tester, 'serverUrlField', 'calsnap.example.com');
      expect(find.textContaining('full address'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('serverUrlApply')))
            .onPressed,
        isNull,
      );

      await enterKey(
        tester,
        'serverUrlField',
        ' https://calsnap.example.com/ ',
      );
      await tapKey(tester, 'serverUrlApply');
      await settle(tester);
      expect(find.text('https://calsnap.example.com'), findsOneWidget);
      expect((await app.settings()).apiBaseUrl, 'https://calsnap.example.com');

      // An empty value removes the override and the build default applies again.
      await tapKey(tester, 'settingServerUrl');
      await settle(tester);
      await enterKey(tester, 'serverUrlField', '');
      await tapKey(tester, 'serverUrlApply');
      await settle(tester);
      expect((await app.settings()).apiBaseUrl, isNull);
      expect(find.text('http://10.0.2.2:8445'), findsOneWidget);
    });

    settingsTest(
      'macro targets can be set and cleared, the plate diameter is validated',
      (tester, app) async {
        await app.completeOnboarding(protein: null, fat: null, carbs: null);
        await openSettings(tester, app);

        await tapKey(tester, 'settingProtein');
        await settle(tester);
        await enterKey(tester, 'numberDialogField', '140');
        await tapKey(tester, 'numberDialogApply');
        await settle(tester);
        expect(find.text('140 g'), findsOneWidget);
        expect((await app.settings()).dailyProteinTargetG, 140);

        await tapKey(tester, 'settingProtein');
        await settle(tester);
        await enterKey(tester, 'numberDialogField', '');
        await tapKey(tester, 'numberDialogApply');
        await settle(tester);
        expect((await app.settings()).dailyProteinTargetG, isNull);

        await tapKey(tester, 'settingPlate');
        await settle(tester);
        await enterKey(tester, 'numberDialogField', '50');
        expect(
          find.text('Enter a value from 10 to 40 cm or leave the field empty.'),
          findsOneWidget,
        );
        await enterKey(tester, 'numberDialogField', '28');
        await tapKey(tester, 'numberDialogApply');
        await settle(tester);
        expect((await app.settings()).plateDiameterCm, 28);
      },
    );

    settingsTest('turning photo saving off is stored', (tester, app) async {
      await app.completeOnboarding();
      await openSettings(tester, app);

      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('settingSavePhotos')))
            .value,
        isTrue,
      );
      await tapKey(tester, 'settingSavePhotos');
      await settle(tester);
      expect((await app.settings()).savePhotos, isFalse);
    });

    settingsTest('the language can be switched to Russian and back', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      await openSettings(tester, app);

      expect(find.text('Settings'), findsWidgets);
      await tester.tap(find.text('Русский'));
      await settle(tester);
      expect((await app.settings()).language, AppLanguage.ru);
      expect(find.text('Настройки'), findsWidgets);
      expect(find.text('Цель по калориям'), findsOneWidget);

      await tester.tap(find.text('English'));
      await settle(tester);
      expect(find.text('Calorie target'), findsOneWidget);
    });

    settingsTest(
      'clearing data needs confirmation, then wipes everything and returns to onboarding',
      (tester, app) async {
        await app.completeOnboarding();
        await app.saveMeal(draftOf([aiItem('a')]));
        await openSettings(tester, app);

        await tapKey(tester, 'clearData');
        await settle(tester);
        expect(find.text('Clear all data?'), findsOneWidget);
        expect(find.textContaining('cannot be undone'), findsOneWidget);
        expect(find.textContaining('exporting'), findsOneWidget);

        // Cancelling keeps everything.
        await tapKey(tester, 'clearCancel');
        await settle(tester);
        expect(await app.mealRows(), hasLength(1));

        await tapKey(tester, 'clearData');
        await settle(tester);
        await tapKey(tester, 'clearConfirm');
        await settle(tester);

        expect(await app.mealRows(), isEmpty);
        expect(await app.itemRows(), isEmpty);
        expect((await app.settings()).onboardingCompleted, isFalse);
        expect(
          await app.foodRows(),
          isNotEmpty,
          reason: 'the catalog is seeded again',
        );
        expect(
          find.text('Step 1 of 5'),
          findsOneWidget,
          reason: 'back in onboarding',
        );
      },
    );

    settingsTest('export opens the share sheet with the generated file', (
      tester,
      app,
    ) async {
      await app.completeOnboarding();
      final share = FakeShare();
      await openSettings(
        tester,
        app,
        overrides: [shareGatewayProvider.overrideWithValue(share)],
      );

      await tester.tap(find.byKey(const Key('exportCsv')));
      // Export runs in an isolate and writes a file: give real time to finish.
      await pumpUntil(tester, () => share.shared.isNotEmpty);

      expect(share.shared, hasLength(1));
      expect(share.shared.single.mimeType, 'text/csv');
      expect(share.shared.single.path, endsWith('.csv'));
    });

    settingsTest(
      'privacy information is available offline and the version is shown',
      (tester, app) async {
        await app.completeOnboarding();
        await openSettings(tester, app);

        expect(find.textContaining('Version'), findsOneWidget);
        await tapKey(tester, 'openPrivacy');
        await settle(tester);
        expect(
          find.text('Your diary is stored only on this device.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('does not store your photos'),
          findsOneWidget,
        );
        expect(find.textContaining('without metadata'), findsOneWidget);
        expect(find.byKey(const Key('privacyPolicyLink')), findsOneWidget);
      },
    );
  });
}
