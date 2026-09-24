import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:calsnap/app/app.dart';
import 'package:calsnap/core/database/app_database.dart';
import 'package:calsnap/core/di/providers.dart';
import 'package:calsnap/core/files/photo_storage.dart';
import 'package:calsnap/features/camera/data/gateways.dart';
import 'package:calsnap/features/export/data/export_service.dart';
import 'package:calsnap/features/foods/data/drift_food_repository.dart';
import 'package:calsnap/features/meal/data/drift_meal_repository.dart';
import 'package:calsnap/features/meal/domain/meal.dart';
import 'package:calsnap/features/meal/domain/meal_draft.dart';
import 'package:calsnap/features/meal/ui/meal_draft_notifier.dart';
import 'package:calsnap/features/recognition/data/analysis_api.dart';
import 'package:calsnap/features/recognition/data/remote_config_repository.dart';
import 'package:calsnap/features/recognition/domain/analysis.dart';
import 'package:calsnap/features/recognition/ui/analysis_controller.dart';
import 'package:calsnap/features/settings/data/drift_settings_repository.dart';
import 'package:calsnap/features/settings/domain/user_settings.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'fixtures.dart';

/// Services over an in-memory database and temporary directories.
class TestApp {
  TestApp._(this.services, this.root, this.clock);

  final AppServices services;
  final Directory root;
  final TestClock clock;

  AppDatabase get db => services.db;

  /// Set by [appTest]; database work is run in real async so that it completes
  /// while the widget test uses fake time.
  late WidgetTester tester;

  Future<T> real<T>(Future<T> Function() body) => realAsync(tester, body);

  Future<AppSettings> settings() => real(services.settings.read);

  Future<List<MealRow>> mealRows() => real(() => db.select(db.meals).get());

  Future<List<MealItemRow>> itemRows() =>
      real(() => db.select(db.mealItems).get());

  Future<List<FoodRow>> foodRows() => real(() => db.select(db.foods).get());

  Future<String> saveMeal(MealDraft draft, {String? photoPath}) =>
      real(() => services.meals.save(draft, photoPath: photoPath));

  Future<Meal?> getMeal(String id) => real(() => services.meals.getMeal(id));

  static Future<TestApp> create({
    DateTime? now,
    bool seedCatalog = true,
  }) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final root = Directory.systemTemp.createTempSync('calsnap_app_');
    Directory('${root.path}/docs').createSync();
    Directory('${root.path}/tmp').createSync();
    Directory('${root.path}/cache').createSync();
    final clock = TestClock(now ?? DateTime(2026, 3, 10, 12, 30));
    final db = createTestDatabase();
    final photos = PhotoStorage(
      documentsDir: Directory('${root.path}/docs'),
      tempDir: Directory('${root.path}/tmp'),
      cacheDir: Directory('${root.path}/cache'),
      clock: clock.call,
    );
    final foods = DriftFoodRepository(db, clock: clock.call);
    final catalog = readCatalogJson();
    if (seedCatalog) await foods.seedCatalog(catalog);
    return TestApp._(
      AppServices(
        db: db,
        photos: photos,
        meals: DriftMealRepository(db, clock: clock.call),
        foods: foods,
        settings: DriftSettingsRepository(db),
        loadCatalogJson: () async => catalog,
      ),
      root,
      clock,
    );
  }

  /// Stores settings as a finished onboarding would.
  Future<void> completeOnboarding({
    int kcal = 2200,
    int? protein = 150,
    int? fat = 75,
    int? carbs = 240,
    double? plate,
    bool savePhotos = true,
    AppLanguage language = AppLanguage.en,
  }) => real(
    () => services.settings.save(
      AppSettings(
        dailyKcalTarget: kcal,
        dailyProteinTargetG: protein,
        dailyFatTargetG: fat,
        dailyCarbsTargetG: carbs,
        plateDiameterCm: plate,
        savePhotos: savePhotos,
        language: language,
        onboardingCompleted: true,
      ),
    ),
  );

  Future<void> dispose() async {
    await db.close();
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // Best effort.
    }
  }

  /// Overrides that point the app at these services and the test clock.
  List<Override> baseOverrides() => [
    appServicesProvider.overrideWith((ref) => services),
    clockProvider.overrideWithValue(clock.call),
  ];

  /// The whole app over these services.
  Widget app({
    String initialLocation = '/diary',
    List<Override> overrides = const [],
    bool overrideServices = true,
  }) => ProviderScope(
    // Same as main(): failures are shown, not retried in the background.
    retry: (retryCount, error) => null,
    overrides: [
      // A synchronous value resolves immediately, so screens can be the first route.
      if (overrideServices) appServicesProvider.overrideWith((ref) => services),
      clockProvider.overrideWithValue(clock.call),
      ...overrides,
    ],
    child: CalSnapApp(initialLocation: initialLocation),
  );
}

class FakePermissions implements PermissionGateway {
  FakePermissions({this.status = CameraAccess.granted, this.requestResult});

  CameraAccess status;
  CameraAccess? requestResult;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<CameraAccess> cameraStatus() async => status;

  @override
  Future<CameraAccess> requestCamera() async {
    requests++;
    return status = requestResult ?? status;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}

class FakeGallery implements GalleryPicker {
  FakeGallery([this.path]);

  String? path;

  @override
  Future<String?> pick() async => path;
}

class FakeShare implements ShareGateway {
  final List<({String path, String mimeType, String subject})> shared = [];

  @override
  Future<void> shareFile(
    String path, {
    required String mimeType,
    required String subject,
  }) async => shared.add((path: path, mimeType: mimeType, subject: subject));
}

/// Answers the analysis without any network.
class FakeAnalysisApi implements AnalysisApi {
  FakeAnalysisApi(this.handler);

  final Future<AnalysisResult> Function(FakeAnalysisCall call) handler;
  final List<FakeAnalysisCall> calls = [];

  @override
  Future<AnalysisResult> analyze({
    required Uint8List jpeg,
    required String locale,
    required String requestId,
    required RemoteConfig config,
    Uint8List? sideJpeg,
    double? plateDiameterCm,
    CancelToken? cancelToken,
  }) {
    final call = FakeAnalysisCall(
      locale: locale,
      requestId: requestId,
      jpeg: jpeg,
      sideJpeg: sideJpeg,
      plateDiameterCm: plateDiameterCm,
      cancelToken: cancelToken,
    );
    calls.add(call);
    return handler(call);
  }

  @override
  Future<RemoteConfig> fetchConfig({CancelToken? cancelToken}) async =>
      const RemoteConfig();
}

class FakeAnalysisCall {
  FakeAnalysisCall({
    required this.locale,
    required this.requestId,
    required this.jpeg,
    this.sideJpeg,
    this.plateDiameterCm,
    this.cancelToken,
  });

  final String locale;
  final String requestId;
  final Uint8List jpeg;
  final Uint8List? sideJpeg;
  final double? plateDiameterCm;
  final CancelToken? cancelToken;
}

class FakePreparer implements PhotoPreparer {
  FakePreparer({this.tempFile});

  final String? tempFile;
  int prepared = 0;

  @override
  Future<PreparedPhoto> prepare(
    AnalysisSource source,
    RemoteConfig config,
  ) async {
    prepared++;
    return PreparedPhoto(
      jpeg: Uint8List.fromList([1, 2, 3]),
      tempFile: tempFile,
    );
  }
}

class FakeRemoteConfigRepository extends RemoteConfigRepository {
  FakeRemoteConfigRepository(TestApp app)
    : super(
        app.services.settings,
        FakeAnalysisApi((_) async => throw UnimplementedError()),
      );

  @override
  Future<RemoteConfig> current() async => const RemoteConfig();

  @override
  Future<void> refresh() async {}
}

AnalysisResult fixtureAnalysis(String name) => AnalysisResult.fromJson(
  jsonDecode(protocolFile('fixtures/$name').readAsStringSync())
      as Map<String, dynamic>,
);

/// Pumps until animations and async work settle (bounded, so a spinner cannot hang a test).
Future<void> settle(WidgetTester tester, {int frames = 30}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Alternates pumping (fake time, microtasks) with real waiting until
/// [condition] holds. For flows that mix isolates or file IO with widgets.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int attempts = 40,
}) async {
  for (var i = 0; i < attempts && !condition(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await realAsync(
      tester,
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }
  await tester.pump();
}

/// Lets real asynchronous work (isolates, file IO) complete inside a widget test.
Future<T> realAsync<T>(WidgetTester tester, Future<T> Function() body) async {
  final result = await tester.runAsync(body);
  return result as T;
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
}

Future<void> enterKey(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pump();
}

/// Runs [body] with the phone-sized surface used by the widget and golden tests.
void useSmallPhone(WidgetTester tester, {double height = 891}) {
  tester.view.physicalSize = Size(411 * 2, height * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

Completer<T> newCompleter<T>() => Completer<T>();

/// The provider container of the running app.
ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

/// Pushes a route on the running app.
Future<void> push(WidgetTester tester, String location, {Object? extra}) async {
  unawaited(
    GoRouter.of(tester.element(find.byType(Scaffold).first))
        .push<Object?>(location, extra: extra),
  );
  await settle(tester, frames: 12);
}

/// Starts a recognition draft from a protocol fixture and opens the result screen.
Future<void> openRecognition(
  WidgetTester tester,
  String fixture, {
  String? tempPhotoFile,
}) async {
  final result = fixtureAnalysis(fixture);
  final notifier = containerOf(tester).read(mealDraftProvider.notifier);
  await realAsync(
    tester,
    () => notifier.startFromRecognition(result, tempPhotoFile: tempPhotoFile),
  );
  await push(tester, '/result');
}

/// A widget test over a fresh [TestApp]. The widget tree is unmounted and the
/// database closed afterwards (drift schedules timers while streams close, which
/// must be flushed before the test ends).
void appTest(
  String description,
  Future<void> Function(WidgetTester tester, TestApp app) body, {
  DateTime? now,
  bool seedCatalog = true,
  double height = 891,
}) {
  testWidgets(description, (tester) async {
    useSmallPhone(tester, height: height);
    final app = await realAsync(
      tester,
      () => TestApp.create(now: now, seedCatalog: seedCatalog),
    );
    app.tester = tester;
    try {
      await body(tester, app);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await realAsync(tester, app.dispose);
    }
  });
}
