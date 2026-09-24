import 'package:calsnap/app/app.dart';
import 'package:calsnap/core/di/providers.dart';
import 'package:calsnap/features/settings/domain/user_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../support/fixtures.dart';
import '../support/photo_flow.dart';

void main() {
  group('apiBaseUrlProvider', () {
    ProviderContainer containerWith(AppSettings settings) {
      final c = ProviderContainer(
        overrides: [currentSettingsProvider.overrideWithValue(settings)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('the saved address wins', () {
      final c = containerWith(
        const AppSettings(apiBaseUrl: 'https://backend.example.com/'),
      );
      expect(c.read(apiBaseUrlProvider), 'https://backend.example.com');
    });

    test('an unusable saved address falls back to the build default', () {
      final c = containerWith(const AppSettings(apiBaseUrl: 'garbage'));
      // Tests run in debug mode, where the default is the emulator alias.
      expect(c.read(apiBaseUrlProvider), 'http://10.0.2.2:8080');
    });

    test('nothing saved uses the build default', () {
      final c = containerWith(const AppSettings());
      expect(c.read(apiBaseUrlProvider), 'http://10.0.2.2:8080');
    });
  });

  appTest(
    'without a server address the analysis asks for it and sends nothing',
    (tester, app) async {
      await app.completeOnboarding();
      final backend = FixtureBackendAdapter();
      final photo = protocolFile('fixtures/sample.jpg').absolute.path;
      Finder key(String k) => find.byKey(Key(k));

      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 80 && finder.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await realAsync(
            tester,
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
        }
        expect(finder, findsWidgets, reason: 'timed out waiting for $finder');
      }

      await tester.pumpWidget(
        scoped([
          ...fixtureBackendOverrides(photoPath: photo, backend: backend),
          apiBaseUrlProvider.overrideWithValue(null),
          ...app.baseOverrides(),
        ], const CalSnapApp()),
      );
      await waitFor(key('kcalProgress'));
      await tester.tap(key('addMeal'));
      await settle(tester, frames: 12);
      await tester.tap(key('addFromGallery'));
      await waitFor(key('analyze'));
      await tester.tap(key('analyze'));
      await waitFor(key('analysisError'));

      expect(find.textContaining('server address is not set'), findsOneWidget);
      expect(key('analysisRetry'), findsNothing);
      expect(
        backend.requests.where((r) => r.path == '/v1/meals/analyze'),
        isEmpty,
      );

      await tester.tap(key('openServerSettings'));
      await waitFor(key('settingServerUrl'));
    },
  );
}
