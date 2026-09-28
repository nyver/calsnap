import 'dart:io';

import 'package:calsnap/app/app.dart';
import 'package:calsnap/core/di/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../test/support/app_harness.dart' show realAsync, settle;
import '../test/support/photo_flow.dart' show scoped;

/// Runs the "Eat this again" flow on a device or emulator with the real
/// database and file system, and no backend adapter at all: the flow never
/// makes a network call, so nothing stands in for one.
///
///   flutter test integration_test/repeat_meal_flow_test.dart -d DEVICE_ID
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'manual meal -> open -> Eat this again -> edit a weight -> save -> two '
    'independent meals',
    (tester) async {
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

      // A clean slate: earlier runs must not leave a diary behind.
      final support = await getApplicationSupportDirectory();
      for (final name in ['calsnap.db', 'calsnap.db-wal', 'calsnap.db-shm']) {
        final f = File(p.join(support.path, name));
        if (f.existsSync()) f.deleteSync();
      }
      final documents = await getApplicationDocumentsDirectory();
      final meals = Directory(p.join(documents.path, 'meals'));
      if (meals.existsSync()) meals.deleteSync(recursive: true);

      await tester.pumpWidget(scoped([], const CalSnapApp()));

      // The splash screen initializes the app and routes to onboarding or
      // the diary.
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

      // Add a manual meal: 150 g of rice from the bundled catalog.
      await tap('addMeal');
      await settle(tester, frames: 10);
      await tap('addManually');
      await waitFor(key('addItem'));
      await tap('addItem');
      await waitFor(key('foodSearchField'));
      await tester.enterText(key('foodSearchField'), 'Rice');
      await settle(tester, frames: 15);
      await tester.tap(find.text('Rice').first);
      await settle(tester, frames: 10);
      await waitFor(key('quantityApply'));
      await tester.enterText(key('weightField'), '150');
      await tester.pump();
      await tap('quantityApply');
      await settle(tester, frames: 10);
      await tap('saveMeal');
      await waitFor(find.text('195 / 2200 kcal')); // 150 g * 130 kcal/100 g

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      final afterFirstSave = await container
          .read(mealRepositoryProvider)
          .mealsWithItems();
      expect(afterFirstSave, hasLength(1));
      final sourceId = afterFirstSave.single.id;

      // Open the saved meal and repeat it.
      await tester.tap(find.byKey(Key('meal-$sourceId')));
      await settle(tester, frames: 20);
      expect(find.text('Rice'), findsOneWidget);
      await tap('eatAgainButton');
      await settle(tester, frames: 15);
      expect(find.text('Eat this again'), findsOneWidget);
      expect(find.text('Rice'), findsOneWidget);

      // Change the weight of the repeated item and save it.
      await tester.tap(find.widgetWithText(ActionChip, '150 g'));
      await settle(tester, frames: 10);
      await tester.enterText(key('weightField'), '200');
      await tester.pump();
      await tap('weightApply');
      await settle(tester, frames: 10);
      await tap('saveMeal');
      await waitFor(find.text('Meal added'));

      final afterRepeat = await container
          .read(mealRepositoryProvider)
          .mealsWithItems();
      expect(afterRepeat, hasLength(2));
      final source = afterRepeat.firstWhere((m) => m.id == sourceId);
      expect(
        source.items.single.weightG,
        150,
        reason: 'the source meal is untouched',
      );
      final repeated = afterRepeat.firstWhere((m) => m.id != sourceId);
      expect(repeated.items.single.weightG, 200);
      expect(repeated.items.single.recognitionSource?.name, 'manual');
    },
  );
}
