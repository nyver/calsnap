/// Build-time configuration passed with `--dart-define`.
abstract final class AppConfig {
  /// Base URL of the CalSnap backend, e.g. `https://calsnap.example.com`.
  /// Release builds must use HTTPS; the default points at the Android emulator
  /// host alias and only works with a debug build (cleartext exception).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );

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

  /// Fails fast when a release build would talk to the backend in cleartext.
  static void validate({
    required bool isReleaseMode,
    String baseUrl = apiBaseUrl,
  }) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('API_BASE_URL is not a valid URL: $baseUrl');
    }
    if (isReleaseMode && uri.scheme != 'https') {
      throw StateError(
        'Release builds require an https:// API_BASE_URL (got ${uri.scheme}).',
      );
    }
  }
}
