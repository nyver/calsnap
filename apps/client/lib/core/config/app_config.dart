import 'package:flutter/foundation.dart';

/// Build-time configuration passed with `--dart-define`.
abstract final class AppConfig {
  /// Backend address used until the user sets one in the settings. Debug builds
  /// default to the Android emulator host alias (cleartext is allowed there
  /// only); release builds have no default unless `API_BASE_URL` is defined.
  static const String defaultApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: kDebugMode ? 'http://10.0.2.2:8080' : '',
  );

  /// Release builds talk to the backend over HTTPS only.
  static const bool requireHttps = kReleaseMode;

  /// Location of the full privacy policy, shown on the privacy screen.
  static const String privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
    defaultValue: 'https://calsnap.example.com/privacy',
  );

  /// Shown in settings and included in exports.
  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0',
  );
}
