import 'package:calsnap/features/balanced_plate/domain/plate_analysis.dart';
import 'package:calsnap/features/balanced_plate/ui/balanced_plate_card.dart';
import 'package:calsnap/l10n/app_localizations.dart';
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

    testWidgets('Balanced plate card golden ($mode)', (tester) async {
      const analysis = PlateAnalysis(
        verdict: PlateVerdict.improvable,
        vegetableFruitRatio: 0.125,
        proteinRatio: 0.125,
        complexCarbohydrateRatio: 0.75,
        coverage: 0.72,
        eligibleWeightG: 400,
        healthyFatPresent: false,
        recommendations: [
          PlateRecommendation(
            type: PlateRecommendationType.addVegetables,
            priority: 100,
          ),
          PlateRecommendation(
            type: PlateRecommendationType.reduceCarbohydrateDominance,
            priority: 90,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: BalancedPlateCard(analysis: analysis),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/balanced_plate_card_$mode.png'),
      );
    });
  }
}
