import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/barcode/data/product_api.dart';
import '../../features/barcode/domain/product_lookup.dart';
import '../../features/foods/data/drift_food_repository.dart';
import '../../features/foods/domain/food_repository.dart';
import '../../features/meal/data/drift_meal_repository.dart';
import '../../features/meal/domain/meal_repository.dart';
import '../../features/recognition/data/analysis_api.dart';
import '../../features/settings/data/drift_settings_repository.dart';
import '../../features/settings/domain/settings_repository.dart';
import '../../features/settings/domain/user_settings.dart';
import '../config/api_base_url.dart';
import '../config/app_config.dart';
import '../database/app_database.dart';
import '../database/database_opener.dart';
import '../files/photo_storage.dart';
import '../network/dio_factory.dart';
import '../network/server_certificate.dart';
import '../utils/clock.dart';
import '../utils/ids.dart';

/// Asset with the bundled nutrition catalog (copy of protocol/nutrition).
const String catalogAssetPath = 'assets/catalog/foods.json';

/// Everything that needs the database or the file system.
class AppServices {
  AppServices({
    required this.db,
    required this.photos,
    required this.meals,
    required this.foods,
    required this.settings,
    required this.loadCatalogJson,
  });

  final AppDatabase db;
  final PhotoStorage photos;
  final MealRepository meals;
  final FoodRepository foods;
  final SettingsRepository settings;

  /// Reads the bundled catalog (an asset in the app, a file in tests).
  final Future<String> Function() loadCatalogJson;

  /// Deletes all local data (meals, items, corrections, foods, settings and
  /// photos) and seeds the catalog again.
  Future<void> clearAllData() async {
    await db.wipe();
    await photos.clearPhotos();
    await photos.sweepTemp();
    await photos.sweepExports();
    await foods.seedCatalog(await loadCatalogJson());
  }
}

final clockProvider = Provider<Clock>((ref) => DateTime.now);

final idsProvider = Provider<IdGenerator>((ref) => const IdGenerator());

/// Opens the database, seeds the catalog and sweeps stale temporary files.
/// Failures (for example an unsupported schema) are shown by the splash
/// screen, which can invalidate this provider to retry.
final appServicesProvider = FutureProvider<AppServices>((ref) async {
  final support = await getApplicationSupportDirectory();
  final documents = await getApplicationDocumentsDirectory();
  final temp = await getTemporaryDirectory();
  final cache = await getApplicationCacheDirectory();
  await support.create(recursive: true);

  final db = await openAppDatabase(File(p.join(support.path, 'calsnap.db')));
  ref.onDispose(db.close);
  final photos = PhotoStorage(
    documentsDir: documents,
    tempDir: temp,
    cacheDir: cache,
  );
  final foods = DriftFoodRepository(db);
  Future<String> loadCatalog() => rootBundle.loadString(catalogAssetPath);

  await foods.seedCatalog(await loadCatalog());
  await photos.sweepTemp();
  await photos.sweepExports();

  return AppServices(
    db: db,
    photos: photos,
    meals: DriftMealRepository(db),
    foods: foods,
    settings: DriftSettingsRepository(db),
    loadCatalogJson: loadCatalog,
  );
});

/// Synchronous access for screens shown after initialization succeeded.
final servicesProvider = Provider<AppServices>(
  (ref) => ref.watch(appServicesProvider).requireValue,
);

final mealRepositoryProvider = Provider<MealRepository>(
  (ref) => ref.watch(servicesProvider).meals,
);

final foodRepositoryProvider = Provider<FoodRepository>(
  (ref) => ref.watch(servicesProvider).foods,
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => ref.watch(servicesProvider).settings,
);

final photoStorageProvider = Provider<PhotoStorage>(
  (ref) => ref.watch(servicesProvider).photos,
);

/// Live settings. Every change is visible immediately.
final settingsProvider = StreamProvider<AppSettings>(
  (ref) => ref.watch(settingsRepositoryProvider).watch(),
);

/// Current settings, or defaults while they load.
final currentSettingsProvider = Provider<AppSettings>(
  (ref) => ref.watch(settingsProvider).value ?? const AppSettings(),
);

/// Language override; null follows the system locale.
final localeProvider = Provider<ui.Locale?>((ref) {
  final services = ref.watch(appServicesProvider);
  if (!services.hasValue) return null;
  final language = ref.watch(currentSettingsProvider).language;
  return switch (language) {
    AppLanguage.system => null,
    AppLanguage.ru => const ui.Locale('ru'),
    AppLanguage.en => const ui.Locale('en'),
  };
});

/// `ru` when the effective language is Russian, otherwise `en`.
final effectiveLanguageCodeProvider = Provider<String>((ref) {
  final override = ref.watch(localeProvider);
  final code =
      override?.languageCode ??
      ui.PlatformDispatcher.instance.locale.languageCode;
  return code == 'ru' ? 'ru' : 'en';
});

/// The backend address in effect: the one from the settings, otherwise the
/// build-time default. Null when neither is usable, so that the app can ask
/// for it instead of sending photos to a bad address.
final apiBaseUrlProvider = Provider<String?>((ref) {
  final saved = ref.watch(currentSettingsProvider.select((s) => s.apiBaseUrl));
  for (final candidate in [saved, AppConfig.defaultApiBaseUrl]) {
    if (candidate == null) continue;
    final parsed = parseApiBaseUrl(
      candidate,
      requireHttps: AppConfig.requireHttps,
    );
    if (parsed.url != null) return parsed.url;
  }
  return null;
});

/// The confirmed self-signed certificate, only while it belongs to the backend
/// address in effect.
final trustedCertificateProvider = Provider<TrustedCertificate?>((ref) {
  final url = ref.watch(apiBaseUrlProvider);
  final pin = ref.watch(
    currentSettingsProvider.select((s) => s.trustedCertificate),
  );
  return url != null && pin != null && pin.isFor(url) ? pin : null;
});

/// Looks at the backend certificate when the user enters the address. Tests
/// override it to avoid the network.
final certificateProbeProvider = Provider<CertificateProbe>(
  (ref) => probeServerCertificate,
);

/// Rebuilt (and the old client closed) when the backend address or its
/// confirmed certificate changes.
final dioProvider = Provider<Dio>((ref) {
  final dio = createDio(
    baseUrl: ref.watch(apiBaseUrlProvider) ?? '',
    trusted: ref.watch(trustedCertificateProvider),
  );
  ref.onDispose(() => dio.close(force: true));
  return dio;
});

final analysisApiProvider = Provider<AnalysisApi>(
  (ref) => AnalysisApi(ref.watch(dioProvider)),
);

final productSourceProvider = Provider<ProductSource>(
  (ref) => ProductApi(ref.watch(dioProvider)),
);

/// The barcode lookup: local cache first, then the backend.
final productLookupProvider = Provider<ProductLookup>(
  (ref) => ProductLookup(
    foods: ref.watch(foodRepositoryProvider),
    source: ref.watch(productSourceProvider),
  ),
);
