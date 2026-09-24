import '../../../core/network/server_certificate.dart';

/// User preferences stored in `user_settings`.
class AppSettings {
  const AppSettings({
    this.dailyKcalTarget,
    this.dailyProteinTargetG,
    this.dailyFatTargetG,
    this.dailyCarbsTargetG,
    this.plateDiameterCm,
    this.savePhotos = true,
    this.language = AppLanguage.system,
    this.onboardingCompleted = false,
    this.apiBaseUrl,
    this.trustedCertificate,
  });

  static const int defaultKcalTarget = 2000;

  final int? dailyKcalTarget;
  final int? dailyProteinTargetG;
  final int? dailyFatTargetG;
  final int? dailyCarbsTargetG;
  final double? plateDiameterCm;
  final bool savePhotos;
  final AppLanguage language;
  final bool onboardingCompleted;

  /// Backend address chosen by the user; null falls back to the build default.
  final String? apiBaseUrl;

  /// Self-signed backend certificate the user confirmed, if any.
  final TrustedCertificate? trustedCertificate;

  /// Metric units are the only unit system in the MVP.
  String get unitSystem => 'metric';

  /// Optional targets are passed as closures so that null can be set
  /// explicitly (`() => null` clears a target).
  AppSettings copyWith({
    int? Function()? dailyKcalTarget,
    int? Function()? dailyProteinTargetG,
    int? Function()? dailyFatTargetG,
    int? Function()? dailyCarbsTargetG,
    double? Function()? plateDiameterCm,
    bool? savePhotos,
    AppLanguage? language,
    bool? onboardingCompleted,
    String? Function()? apiBaseUrl,
    TrustedCertificate? Function()? trustedCertificate,
  }) => AppSettings(
    dailyKcalTarget: dailyKcalTarget != null
        ? dailyKcalTarget()
        : this.dailyKcalTarget,
    dailyProteinTargetG: dailyProteinTargetG != null
        ? dailyProteinTargetG()
        : this.dailyProteinTargetG,
    dailyFatTargetG: dailyFatTargetG != null
        ? dailyFatTargetG()
        : this.dailyFatTargetG,
    dailyCarbsTargetG: dailyCarbsTargetG != null
        ? dailyCarbsTargetG()
        : this.dailyCarbsTargetG,
    plateDiameterCm: plateDiameterCm != null
        ? plateDiameterCm()
        : this.plateDiameterCm,
    savePhotos: savePhotos ?? this.savePhotos,
    language: language ?? this.language,
    onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    apiBaseUrl: apiBaseUrl != null ? apiBaseUrl() : this.apiBaseUrl,
    trustedCertificate: trustedCertificate != null
        ? trustedCertificate()
        : this.trustedCertificate,
  );
}

enum AppLanguage {
  system,
  ru,
  en;

  static AppLanguage fromName(String? name) {
    for (final l in AppLanguage.values) {
      if (l.name == name) return l;
    }
    return AppLanguage.system;
  }
}

/// Validation ranges shared by onboarding and settings.
abstract final class SettingsLimits {
  static const int minKcal = 800;
  static const int maxKcal = 6000;
  static const int maxMacroG = 500;
  static const double minPlateCm = 10;
  static const double maxPlateCm = 40;

  static bool validKcal(int? v) => v != null && v >= minKcal && v <= maxKcal;
  static bool validMacro(int? v) => v != null && v >= 0 && v <= maxMacroG;
  static bool validPlate(double? v) =>
      v != null && v.isFinite && v >= minPlateCm && v <= maxPlateCm;
}
