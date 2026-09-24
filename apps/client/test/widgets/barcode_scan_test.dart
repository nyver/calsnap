import 'package:calsnap/core/di/providers.dart';
import 'package:calsnap/core/domain/nutrition.dart';
import 'package:calsnap/features/barcode/domain/packaged_product.dart';
import 'package:calsnap/features/barcode/ui/scanner_view.dart';
import 'package:calsnap/features/camera/data/gateways.dart';
import 'package:calsnap/features/meal/domain/meal.dart';
import 'package:calsnap/features/meal/ui/meal_draft_notifier.dart';
import 'package:calsnap/features/recognition/domain/analysis.dart';
import 'package:calsnap/features/recognition/ui/analysis_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../barcode/barcode_domain_test.dart' show FakeSource, yogurt;
import '../support/app_harness.dart';

class _Config extends FakeRemoteConfigRepository {
  _Config(super.app, this.barcodeLookup);

  final bool barcodeLookup;

  @override
  Future<RemoteConfig> current() async =>
      RemoteConfig(barcodeLookup: barcodeLookup);
}

const goodCode = '4006381333931';
const misread = '4006381333932'; // fails the check digit

/// A stand-in for the camera: buttons that "read" a barcode.
Widget fakeScanner(BuildContext context, ValueChanged<String> onCode) => Column(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    TextButton(
      key: const Key('fakeScanGood'),
      onPressed: () => onCode(goodCode),
      child: const Text('read good'),
    ),
    TextButton(
      key: const Key('fakeScanMisread'),
      onPressed: () => onCode(misread),
      child: const Text('read misread'),
    ),
  ],
);

List<Override> overrides(
  TestApp app,
  FakeSource source, {
  bool supported = true,
  CameraAccess camera = CameraAccess.granted,
}) => [
  remoteConfigRepositoryProvider.overrideWithValue(_Config(app, supported)),
  productSourceProvider.overrideWithValue(source),
  barcodeScannerBuilderProvider.overrideWithValue(fakeScanner),
  permissionGatewayProvider.overrideWithValue(FakePermissions(status: camera)),
];

Future<void> open(WidgetTester tester, TestApp app, List<Override> o) async {
  await app.completeOnboarding();
  await tester.pumpWidget(app.app(overrides: o));
  await settle(tester);
}

Future<void> openScannerFromDiary(WidgetTester tester) async {
  await tapKey(tester, 'addMeal');
  await settle(tester);
  await tapKey(tester, 'addScanBarcode');
  await settle(tester);
}

FakeSource yogurtSource() => FakeSource((_, _) async => yogurt);

void main() {
  group('the entry point', () {
    appTest('"Scan barcode" is in the add sheet when the server supports it', (
      tester,
      app,
    ) async {
      await open(tester, app, overrides(app, yogurtSource()));
      await tapKey(tester, 'addMeal');
      await settle(tester);
      expect(find.byKey(const Key('addScanBarcode')), findsOneWidget);
      expect(find.text('Scan barcode'), findsOneWidget);
      expect(find.byKey(const Key('addTakePhoto')), findsOneWidget);
    });

    appTest('is hidden when the server has no barcode lookup', (
      tester,
      app,
    ) async {
      await open(tester, app, overrides(app, yogurtSource(), supported: false));
      await tapKey(tester, 'addMeal');
      await settle(tester);
      expect(find.byKey(const Key('addScanBarcode')), findsNothing);
      expect(find.byKey(const Key('addManually')), findsOneWidget);
    });
  });

  group('scanning a product', () {
    appTest(
      'a scan shows the product; adding it opens a meal with the serving',
      (tester, app) async {
        final source = yogurtSource();
        await open(tester, app, overrides(app, source));
        await openScannerFromDiary(tester);

        expect(find.byKey(const Key('scanHint')), findsOneWidget);
        await tapKey(tester, 'fakeScanGood');
        await settle(tester, frames: 15);

        expect(find.byKey(const Key('scanFound')), findsOneWidget);
        expect(find.text('Danone Plain yogurt'), findsOneWidget);
        expect(find.text('61 kcal / 100 g'), findsOneWidget);
        expect(find.textContaining('Protein 3.5'), findsOneWidget);
        expect(find.text('Serving: 150 g'), findsOneWidget);
        expect(find.textContaining('Open Food Facts'), findsOneWidget);
        expect(source.calls.single.barcode, goodCode);
        expect(source.calls.single.locale, 'en');

        await tapKey(tester, 'scanAdd');
        await settle(tester);
        // The serving is the starting quantity.
        await tapKey(tester, 'quantityApply');
        await settle(tester, frames: 15);

        expect(find.text('New meal'), findsOneWidget);
        expect(find.text('Danone Plain yogurt'), findsOneWidget);
        // 150 g of 61 kcal per 100 g.
        expect(find.text('92 kcal'), findsWidgets);

        await tapKey(tester, 'saveMeal');
        await pumpUntil(
          tester,
          () => find.byKey(const Key('kcalProgress')).evaluate().isNotEmpty,
        );
        await settle(tester);

        final items = await app.itemRows();
        expect(items, hasLength(1));
        expect(items.single.name, 'Danone Plain yogurt');
        expect(items.single.weightG, 150);
        expect(items.single.recognitionSource, 'manual');
        expect(items.single.kcalPer100g, 61);
        expect(items.single.proteinPer100g, 3.5);
        expect(items.single.foodId, isNotNull);
        final food = (await app.foodRows()).singleWhere(
          (f) => f.source == NutritionSourceName.packaged,
        );
        expect(food.sourceId, goodCode);
        expect(food.id, items.single.foodId);
      },
    );

    appTest('a misread code is ignored without a lookup', (tester, app) async {
      final source = yogurtSource();
      await open(tester, app, overrides(app, source));
      await openScannerFromDiary(tester);

      await tapKey(tester, 'fakeScanMisread');
      await settle(tester);
      expect(source.calls, isEmpty);
      expect(find.byKey(const Key('scanHint')), findsOneWidget);
      expect(find.byKey(const Key('scanError')), findsNothing);
    });

    appTest('the second scan of the same product needs no network', (
      tester,
      app,
    ) async {
      var offline = false;
      final source = FakeSource((_, _) async {
        if (offline) throw const OfflineFailure();
        return yogurt;
      });
      await open(tester, app, overrides(app, source));
      await openScannerFromDiary(tester);
      await tapKey(tester, 'fakeScanGood');
      await settle(tester, frames: 15);
      expect(find.byKey(const Key('scanFound')), findsOneWidget);

      offline = true;
      await tapKey(tester, 'scanAgain');
      await settle(tester);
      await tapKey(tester, 'fakeScanGood');
      await settle(tester, frames: 15);
      expect(find.byKey(const Key('scanFound')), findsOneWidget);
      expect(source.calls, hasLength(1));
    });
  });

  group('when the lookup fails', () {
    appTest('an unknown product says so and offers another scan', (
      tester,
      app,
    ) async {
      final source = FakeSource(
        (_, _) async => throw const ProductNotFoundException(),
      );
      await open(tester, app, overrides(app, source));
      await openScannerFromDiary(tester);
      await tapKey(tester, 'fakeScanGood');
      await settle(tester, frames: 15);

      expect(
        find.textContaining('No nutrition data was found for this product'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('scanRetry')),
        findsNothing,
        reason: 'retrying cannot help',
      );
      await tapKey(tester, 'scanAgain');
      await settle(tester);
      expect(find.byKey(const Key('scanHint')), findsOneWidget);
    });

    appTest('a network problem can be retried', (tester, app) async {
      var fail = true;
      final source = FakeSource((_, _) async {
        if (fail) throw const OfflineFailure();
        return yogurt;
      });
      await open(tester, app, overrides(app, source));
      await openScannerFromDiary(tester);
      await tapKey(tester, 'fakeScanGood');
      await settle(tester, frames: 15);
      expect(find.textContaining('No internet connection'), findsOneWidget);

      fail = false;
      await tapKey(tester, 'scanRetry');
      await settle(tester, frames: 15);
      expect(find.byKey(const Key('scanFound')), findsOneWidget);
      expect(source.calls, hasLength(2));
    });

    appTest('a busy or unavailable service is explained', (tester, app) async {
      final source = FakeSource(
        (_, _) async => throw const UnavailableFailure(),
      );
      await open(tester, app, overrides(app, source));
      await openScannerFromDiary(tester);
      await tapKey(tester, 'fakeScanGood');
      await settle(tester, frames: 15);
      expect(find.textContaining('temporarily unavailable'), findsOneWidget);
    });
  });

  group('typing the number', () {
    appTest('works next to the camera', (tester, app) async {
      final source = yogurtSource();
      await open(tester, app, overrides(app, source));
      await openScannerFromDiary(tester);

      await enterKey(tester, 'scanManualField', goodCode);
      await tapKey(tester, 'scanManualFind');
      await settle(tester, frames: 15);
      expect(find.byKey(const Key('scanFound')), findsOneWidget);
      expect(source.calls.single.barcode, goodCode);
    });

    appTest('checks the digits before asking anybody', (tester, app) async {
      final source = yogurtSource();
      await open(tester, app, overrides(app, source));
      await openScannerFromDiary(tester);

      await enterKey(tester, 'scanManualField', misread);
      await tapKey(tester, 'scanManualFind');
      await settle(tester);
      expect(find.textContaining('Enter a valid barcode'), findsOneWidget);
      expect(source.calls, isEmpty);

      await enterKey(tester, 'scanManualField', goodCode);
      await settle(tester);
      expect(find.textContaining('Enter a valid barcode'), findsNothing);
    });

    appTest('is the way in when the camera is not allowed', (
      tester,
      app,
    ) async {
      final source = yogurtSource();
      await open(
        tester,
        app,
        overrides(app, source, camera: CameraAccess.permanentlyDenied),
      );
      await openScannerFromDiary(tester);

      expect(find.byKey(const Key('scanPermission')), findsOneWidget);
      expect(find.byKey(const Key('scanOpenSettings')), findsOneWidget);
      expect(find.byKey(const Key('fakeScanGood')), findsNothing);
      await enterKey(tester, 'scanManualField', goodCode);
      await tapKey(tester, 'scanManualFind');
      await settle(tester, frames: 15);
      expect(find.byKey(const Key('scanFound')), findsOneWidget);
    });
  });

  group('from the food search', () {
    appTest('adds a scanned product to the meal being edited', (
      tester,
      app,
    ) async {
      final source = yogurtSource();
      await open(tester, app, overrides(app, source));
      containerOf(tester).read(mealDraftProvider.notifier).startManual();
      await push(tester, '/meal/new');
      await settle(tester);

      await tapKey(tester, 'addItem');
      await settle(tester);
      await tapKey(tester, 'scanBarcode');
      await settle(tester);
      await tapKey(tester, 'fakeScanGood');
      await settle(tester, frames: 15);
      await tapKey(tester, 'scanAdd');
      await settle(tester);
      await tapKey(tester, 'quantityApply');
      await settle(tester, frames: 15);

      expect(find.text('New meal'), findsOneWidget);
      final draft = containerOf(tester).read(mealDraftProvider)!;
      expect(draft.items.single.name, 'Danone Plain yogurt');
      expect(draft.items.single.weightG, 150);
      expect(draft.items.single.nutritionSource, NutritionSourceName.packaged);
      expect(
        draft.items.single.per100,
        const Nutrition(kcal: 61, protein: 3.5, fat: 2.1, carbs: 7.6),
      );
    });

    appTest('the scan button is missing without server support', (
      tester,
      app,
    ) async {
      await open(tester, app, overrides(app, yogurtSource(), supported: false));
      containerOf(tester).read(mealDraftProvider.notifier).startManual();
      await push(tester, '/meal/new');
      await settle(tester);
      await tapKey(tester, 'addItem');
      await settle(tester);
      expect(find.byKey(const Key('foodSearchField')), findsOneWidget);
      expect(find.byKey(const Key('scanBarcode')), findsNothing);
    });

    appTest('a cached product is found by name in the search', (
      tester,
      app,
    ) async {
      await open(tester, app, overrides(app, yogurtSource()));
      await openScannerFromDiary(tester);
      await tapKey(tester, 'fakeScanGood');
      await settle(tester, frames: 15);
      expect(find.byKey(const Key('scanFound')), findsOneWidget);

      final found = await app.real(
        () => app.services.foods.search('plain yogurt'),
      );
      expect(found.map((f) => f.name), contains('Danone Plain yogurt'));
    });
  });
}
