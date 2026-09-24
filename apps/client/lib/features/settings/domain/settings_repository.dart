import 'user_settings.dart';

/// Typed access to `user_settings`.
abstract interface class SettingsRepository {
  Stream<AppSettings> watch();
  Future<AppSettings> read();

  /// Persists the settings; null targets are removed.
  Future<void> save(AppSettings settings);

  /// Opaque cached values (remote config, catalog version).
  Future<String?> getRaw(String key);
  Future<void> setRaw(String key, String value);
}

/// Keys of `user_settings`.
abstract final class SettingKeys {
  static const dailyKcalTarget = 'daily_kcal_target';
  static const dailyProteinTargetG = 'daily_protein_target_g';
  static const dailyFatTargetG = 'daily_fat_target_g';
  static const dailyCarbsTargetG = 'daily_carbs_target_g';
  static const plateDiameterCm = 'plate_diameter_cm';
  static const savePhotos = 'save_meal_photos';
  static const language = 'language';
  static const unitSystem = 'unit_system';
  static const onboardingCompleted = 'onboarding_completed';
  static const apiBaseUrl = 'api_base_url';
  static const catalogVersion = 'catalog_version';
  static const remoteConfigJson = 'remote_config_json';
}
