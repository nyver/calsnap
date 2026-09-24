import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';

void main() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    Future<void> open(WidgetTester tester, TestApp app, String fixture) async {
      tester.platformDispatcher.platformBrightnessTestValue = dark
          ? Brightness.dark
          : Brightness.light;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await app.completeOnboarding();
      await tester.pumpWidget(app.app());
      await settle(tester);
      await openRecognition(tester, fixture);
      await settle(tester, frames: 20);
    }

    group('Recognition result golden ($mode)', () {
      appTest('full result', (tester, app) async {
        await open(tester, app, 'analyze-response-full.json');
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/result_full_$mode.png'),
        );
      });

      appTest('partial recognition with a low-confidence item', (
        tester,
        app,
      ) async {
        await open(tester, app, 'analyze-response-partial.json');
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/result_partial_$mode.png'),
        );
      });
    });

    group('Edit food item golden ($mode)', () {
      appTest('item editor sheet', (tester, app) async {
        await open(tester, app, 'analyze-response-full.json');
        await tester.tap(find.byIcon(Icons.edit_outlined).first);
        await settle(tester, frames: 20);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/edit_item_$mode.png'),
        );
      });
    });
  }
}
