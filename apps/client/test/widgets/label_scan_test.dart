import 'dart:io';
import 'dart:typed_data';

import 'package:calsnap/core/di/providers.dart';
import 'package:calsnap/features/barcode/domain/packaged_product.dart';
import 'package:calsnap/features/camera/data/gateways.dart';
import 'package:calsnap/features/camera/data/photo_analyzer.dart';
import 'package:calsnap/features/camera/domain/photo_quality.dart';
import 'package:calsnap/features/label/domain/label_reading.dart';
import 'package:calsnap/features/label/ui/label_reader.dart';
import 'package:calsnap/features/meal/domain/meal.dart';
import 'package:calsnap/features/meal/ui/meal_draft_notifier.dart';
import 'package:calsnap/features/recognition/domain/analysis.dart';
import 'package:calsnap/features/recognition/ui/analysis_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../barcode/barcode_domain_test.dart' show FakeSource;
import '../support/app_harness.dart';
import '../support/fixtures.dart';

class _Config extends FakeRemoteConfigRepository {
  _Config(super.app, {this.label = true});

  final bool label;

  @override
  Future<RemoteConfig> current() async =>
      RemoteConfig(barcodeLookup: true, labelReading: label);
}

class FakeLabelSource implements LabelSource {
  FakeLabelSource(this.handler);

  Future<LabelReading> Function(Uint8List jpeg, String locale) handler;
  final List<({Uint8List jpeg, String locale})> calls = [];

  @override
  Future<LabelReading> read(
    Uint8List jpeg, {
    required String locale,
    required RemoteConfig config,
  }) {
    calls.add((jpeg: jpeg, locale: locale));
    return handler(jpeg, locale);
  }
}

/// Records how the label photo was checked.
class Checks {
  final List<({String path, bool checkPlate})> calls = [];

  Future<PhotoQuality?> call(String path, {required bool checkPlate}) async {
    calls.add((path: path, checkPlate: checkPlate));
    return const PhotoQuality(
      sharpness: 100,
      meanLuma: 120,
      clippedFraction: 0,
      issues: [],
    );
  }
}

const unknownCode = '4006381333931';

const spread = LabelReading(
  name: 'Chocolate hazelnut spread',
  kcal: 220,
  protein: 8.4,
  fat: 12.1,
  carbs: 18.2,
);

class Setup {
  Setup(
    this.app, {
    LabelReading reading = spread,
    this.label = true,
    String? tempFile,
  }) : labelSource = FakeLabelSource((_, _) async => reading),
       productSource = FakeSource(
         (_, _) async => throw const ProductNotFoundException(),
       ),
       checks = Checks(),
       photo = FakePreparer(tempFile: tempFile);

  final TestApp app;
  final bool label;
  final FakeLabelSource labelSource;
  final FakeSource productSource;
  final Checks checks;
  final FakePreparer photo;

  List<Override> get overrides => [
    remoteConfigRepositoryProvider.overrideWithValue(
      _Config(app, label: label),
    ),
    productSourceProvider.overrideWithValue(productSource),
    labelSourceProvider.overrideWithValue(labelSource),
    photoPreparerProvider.overrideWithValue(photo),
    photoQualityProvider.overrideWithValue(checks.call),
    // No camera in tests: the capture screen offers the gallery instead.
    permissionGatewayProvider.overrideWithValue(
      FakePermissions(status: CameraAccess.permanentlyDenied),
    ),
    galleryPickerProvider.overrideWithValue(
      FakeGallery(protocolFile('fixtures/sample.jpg').absolute.path),
    ),
  ];
}

Future<void> openScannerFromDiary(
  WidgetTester tester,
  TestApp app,
  Setup setup,
) async {
  await app.completeOnboarding();
  await tester.pumpWidget(app.app(overrides: setup.overrides));
  await settle(tester);
  await tapKey(tester, 'addMeal');
  await settle(tester);
  await tapKey(tester, 'addScanBarcode');
  await settle(tester);
}

/// The camera is not allowed in these tests (the label camera would need a
/// real one), so the barcode is typed; the scanner has its own tests.
Future<void> scanUnknownBarcode(WidgetTester tester) async {
  await enterKey(tester, 'scanManualField', unknownCode);
  await tapKey(tester, 'scanManualFind');
  await settle(tester, frames: 15);
}

/// Photographs the label from the gallery and reads it.
Future<void> readLabelFromGallery(WidgetTester tester) async {
  await tapKey(tester, 'chooseFromGallery');
  await settle(tester);
  await tapKey(tester, 'analyze');
  await settle(tester, frames: 15);
}

String fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

bool createEnabled(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.byKey(const Key('customCreate')))
        .onPressed !=
    null;

void main() {
  group('the chain from an unknown barcode', () {
    appTest('scan, read the label, confirm, save locally, add to the meal', (
      tester,
      app,
    ) async {
      final setup = Setup(app);
      await openScannerFromDiary(tester, app, setup);
      await scanUnknownBarcode(tester);

      expect(
        find.textContaining('No nutrition data was found'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('scanRetry')), findsNothing);
      await tapKey(tester, 'scanLabel');
      await settle(tester);

      // The label camera: no plate guide, no manual entry, a hint for tables.
      expect(find.text('Nutrition label'), findsOneWidget);
      expect(find.byKey(const Key('addManuallyFromCapture')), findsNothing);
      await tapKey(tester, 'chooseFromGallery');
      await settle(tester);
      expect(find.text('Read label'), findsOneWidget);
      expect(find.byKey(const Key('plateChip')), findsNothing);
      await tapKey(tester, 'analyze');
      await settle(tester, frames: 15);

      // Confirmation: the values are filled in, but nothing is saved yet.
      expect(fieldText(tester, 'customNameField'), 'Chocolate hazelnut spread');
      expect(fieldText(tester, 'customKcalField'), '220');
      expect(fieldText(tester, 'customProteinField'), '8.4');
      expect(fieldText(tester, 'customFatField'), '12.1');
      expect(fieldText(tester, 'customCarbsField'), '18.2');
      expect(find.text('Barcode $unknownCode'), findsOneWidget);
      expect(
        find.text('Check every value against the package before saving.'),
        findsOneWidget,
      );
      expect(
        await app.foodRows().then((r) => r.where((f) => f.source == 'user')),
        isEmpty,
      );

      await tapKey(tester, 'customCreate');
      await settle(tester, frames: 15);
      // The product goes on into the meal: quantity, then the new meal.
      await tapKey(tester, 'quantityApply');
      await settle(tester, frames: 15);
      expect(find.text('New meal'), findsOneWidget);
      expect(find.text('Chocolate hazelnut spread'), findsOneWidget);
      expect(find.text('220 kcal'), findsWidgets);

      final food = (await app.foodRows()).singleWhere(
        (f) => f.source == 'user',
      );
      expect(
        (food.sourceId, food.kcalPer100g, food.proteinPer100g),
        (unknownCode, 220.0, 8.4),
      );
      expect(food.aliases, unknownCode);

      await tapKey(tester, 'saveMeal');
      await pumpUntil(
        tester,
        () => find.byKey(const Key('kcalProgress')).evaluate().isNotEmpty,
      );
      final item = (await app.itemRows()).single;
      expect(item.foodId, food.id);
      expect(item.recognitionSource, 'manual');
      expect((item.weightG, item.kcalPer100g), (100.0, 220.0));

      // The label photo was sent as prepared, in the app language, and judged
      // for blur and light only.
      expect(setup.labelSource.calls.single.locale, 'en');
      expect(setup.labelSource.calls.single.jpeg, [1, 2, 3]);
      expect(setup.checks.calls.single.checkPlate, isFalse);
    });

    appTest('the next scan of that barcode is answered on the device', (
      tester,
      app,
    ) async {
      final setup = Setup(app);
      await openScannerFromDiary(tester, app, setup);
      await scanUnknownBarcode(tester);
      await tapKey(tester, 'scanLabel');
      await settle(tester);
      await readLabelFromGallery(tester);
      await tapKey(tester, 'customCreate');
      await settle(tester, frames: 15);
      await tapKey(tester, 'quantityApply');
      await settle(tester, frames: 15);
      await tapKey(tester, 'saveMeal');
      await pumpUntil(
        tester,
        () => find.byKey(const Key('kcalProgress')).evaluate().isNotEmpty,
      );
      await settle(tester);
      expect(setup.productSource.calls, hasLength(1));
      // Let the "saved" snackbar go: it covers the add button.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 2));
      }

      await tapKey(tester, 'addMeal');
      await settle(tester);
      await tapKey(tester, 'addScanBarcode');
      await settle(tester);
      await scanUnknownBarcode(tester);

      expect(find.byKey(const Key('scanFound')), findsOneWidget);
      expect(find.text('Chocolate hazelnut spread'), findsOneWidget);
      expect(find.text('Saved by you'), findsOneWidget);
      expect(find.textContaining('Open Food Facts'), findsNothing);
      expect(
        setup.productSource.calls,
        hasLength(1),
        reason: 'no backend call',
      );
    });

    appTest('a label without the serving and a per-serving conversion say so', (
      tester,
      app,
    ) async {
      final setup = Setup(
        app,
        reading: const LabelReading(
          servingSizeG: 30,
          kcal: 400,
          protein: 10,
          fat: 20,
          carbs: 45,
          warnings: {LabelWarning.valuesConverted, LabelWarning.energyMismatch},
        ),
      );
      await openScannerFromDiary(tester, app, setup);
      await scanUnknownBarcode(tester);
      await tapKey(tester, 'scanLabel');
      await settle(tester);
      await readLabelFromGallery(tester);

      expect(fieldText(tester, 'customServingField'), '30');
      expect(find.textContaining('converted to 100 g'), findsOneWidget);
      expect(find.textContaining('does not match'), findsOneWidget);
      expect(fieldText(tester, 'customNameField'), isEmpty);
      expect(createEnabled(tester), isFalse, reason: 'a name is required');
      await enterKey(tester, 'customNameField', 'Granola bar');
      expect(createEnabled(tester), isTrue);
    });

    appTest(
      'values the photo did not show stay empty until the user fills them',
      (tester, app) async {
        final setup = Setup(
          app,
          reading: const LabelReading(
            name: 'Spread',
            protein: 8.4,
            fat: 12.1,
            warnings: {LabelWarning.lowConfidence},
          ),
        );
        await openScannerFromDiary(tester, app, setup);
        await scanUnknownBarcode(tester);
        await tapKey(tester, 'scanLabel');
        await settle(tester);
        await readLabelFromGallery(tester);

        expect(fieldText(tester, 'customKcalField'), isEmpty);
        expect(fieldText(tester, 'customCarbsField'), isEmpty);
        expect(fieldText(tester, 'customProteinField'), '8.4');
        expect(find.textContaining('could not be read'), findsOneWidget);
        expect(find.textContaining('hard to read'), findsOneWidget);
        expect(createEnabled(tester), isFalse);

        await enterKey(tester, 'customKcalField', '215');
        expect(
          createEnabled(tester),
          isFalse,
          reason: 'carbohydrates are still missing',
        );
        await enterKey(tester, 'customCarbsField', '18');
        expect(createEnabled(tester), isTrue);
      },
    );

    appTest('nothing is saved when the confirmation is dismissed', (
      tester,
      app,
    ) async {
      final setup = Setup(app);
      await openScannerFromDiary(tester, app, setup);
      await scanUnknownBarcode(tester);
      await tapKey(tester, 'scanLabel');
      await settle(tester);
      await readLabelFromGallery(tester);
      expect(find.byKey(const Key('customCreate')), findsOneWidget);

      await tester.tapAt(const Offset(200, 40)); // outside the sheet
      await settle(tester);
      expect(
        await app.foodRows().then((r) => r.where((f) => f.source == 'user')),
        isEmpty,
      );
      expect(
        find.byKey(const Key('scanLabel')),
        findsOneWidget,
        reason: 'still on the not-found screen',
      );
    });
  });

  group('when the label cannot be read', () {
    appTest('a photo without a table explains what to do and can be retaken', (
      tester,
      app,
    ) async {
      final setup = Setup(app);
      setup.labelSource.handler = (_, _) async =>
          throw const LabelNotRecognizedException();
      await openScannerFromDiary(tester, app, setup);
      await scanUnknownBarcode(tester);
      await tapKey(tester, 'scanLabel');
      await settle(tester);
      await readLabelFromGallery(tester);

      expect(find.byKey(const Key('readError')), findsOneWidget);
      expect(
        find.textContaining('No nutrition table was found in this photo'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('analyze')),
        findsOneWidget,
        reason: 'still on the preview',
      );
      expect(find.byKey(const Key('customCreate')), findsNothing);

      setup.labelSource.handler = (_, _) async => spread;
      await tapKey(tester, 'retake');
      await settle(tester);
      expect(find.byKey(const Key('readError')), findsNothing);
      await readLabelFromGallery(tester);
      expect(fieldText(tester, 'customKcalField'), '220');
      expect(setup.labelSource.calls, hasLength(2));
    });

    appTest('a network problem keeps the photo and can be retried', (
      tester,
      app,
    ) async {
      final setup = Setup(app);
      setup.labelSource.handler = (_, _) async => throw const OfflineFailure();
      await openScannerFromDiary(tester, app, setup);
      await scanUnknownBarcode(tester);
      await tapKey(tester, 'scanLabel');
      await settle(tester);
      await readLabelFromGallery(tester);
      expect(find.textContaining('No internet connection'), findsOneWidget);

      setup.labelSource.handler = (_, _) async => spread;
      await tapKey(tester, 'analyze');
      await settle(tester, frames: 15);
      expect(fieldText(tester, 'customNameField'), 'Chocolate hazelnut spread');
      expect(setup.labelSource.calls, hasLength(2));
    });

    appTest('the temporary copy of the photo is always removed', (
      tester,
      app,
    ) async {
      final temp = File('${app.root.path}/tmp/label-prepared.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final setup = Setup(app, tempFile: temp.path);
      setup.labelSource.handler = (_, _) async =>
          throw const UnavailableFailure();
      await openScannerFromDiary(tester, app, setup);
      await scanUnknownBarcode(tester);
      await tapKey(tester, 'scanLabel');
      await settle(tester);
      await readLabelFromGallery(tester);
      await pumpUntil(tester, () => !temp.existsSync(), attempts: 10);
      expect(temp.existsSync(), isFalse, reason: 'also after a failure');
    });
  });

  group('without server support', () {
    appTest('the label scan is not offered', (tester, app) async {
      final setup = Setup(app, label: false);
      await openScannerFromDiary(tester, app, setup);
      await scanUnknownBarcode(tester);
      expect(
        find.textContaining('No nutrition data was found'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('scanLabel')), findsNothing);
      expect(find.byKey(const Key('scanAgain')), findsOneWidget);
    });

    appTest('the custom product form has no label button', (tester, app) async {
      final setup = Setup(app, label: false);
      await app.completeOnboarding();
      await tester.pumpWidget(app.app(overrides: setup.overrides));
      await settle(tester);
      containerOf(tester).read(mealDraftProvider.notifier).startManual();
      await push(tester, '/meal/new');
      await settle(tester);
      await tapKey(tester, 'addItem');
      await settle(tester);
      await tapKey(tester, 'createCustomProduct');
      await settle(tester);
      expect(find.byKey(const Key('customNameField')), findsOneWidget);
      expect(find.byKey(const Key('customFillFromLabel')), findsNothing);
    });
  });

  group('from the custom product form', () {
    appTest('a label photo fills the fields of a product without a barcode', (
      tester,
      app,
    ) async {
      final setup = Setup(app);
      await app.completeOnboarding();
      await tester.pumpWidget(app.app(overrides: setup.overrides));
      await settle(tester);
      containerOf(tester).read(mealDraftProvider.notifier).startManual();
      await push(tester, '/meal/new');
      await settle(tester);
      await tapKey(tester, 'addItem');
      await settle(tester);
      await tapKey(tester, 'createCustomProduct');
      await settle(tester);

      await tapKey(tester, 'customFillFromLabel');
      await settle(tester);
      await readLabelFromGallery(tester);

      // Back in the same form, now filled in.
      expect(fieldText(tester, 'customNameField'), 'Chocolate hazelnut spread');
      expect(fieldText(tester, 'customKcalField'), '220');
      expect(find.byKey(const Key('customBarcode')), findsNothing);
      expect(find.byKey(const Key('customNotes')), findsOneWidget);

      await tapKey(tester, 'customCreate');
      await settle(tester, frames: 15);
      await tapKey(tester, 'quantityApply');
      await settle(tester, frames: 15);
      final draft = containerOf(tester).read(mealDraftProvider)!;
      expect(draft.items.single.name, 'Chocolate hazelnut spread');
      expect(draft.items.single.per100.kcal, 220);
      final food = (await app.foodRows()).singleWhere(
        (f) => f.source == 'user',
      );
      expect(food.sourceId, isNull);
    });

    appTest('a name typed before the scan is kept', (tester, app) async {
      final setup = Setup(app);
      await app.completeOnboarding();
      await tester.pumpWidget(app.app(overrides: setup.overrides));
      await settle(tester);
      containerOf(tester).read(mealDraftProvider.notifier).startManual();
      await push(tester, '/meal/new');
      await settle(tester);
      await tapKey(tester, 'addItem');
      await settle(tester);
      await tapKey(tester, 'createCustomProduct');
      await settle(tester);
      await enterKey(tester, 'customNameField', 'My spread');
      await tapKey(tester, 'customFillFromLabel');
      await settle(tester);
      await readLabelFromGallery(tester);
      expect(fieldText(tester, 'customNameField'), 'My spread');
    });
  });

  test('Nutrition sources include packaged and user products', () {
    expect(NutritionSourceName.packaged, 'packaged');
    expect(NutritionSourceName.user, 'user');
  });
}
