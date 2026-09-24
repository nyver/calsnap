import 'dart:convert';

import '../../settings/domain/settings_repository.dart';
import '../domain/analysis.dart';
import 'analysis_api.dart';

/// Client tunables from `GET /v1/config`, cached in `user_settings`. It never
/// blocks the capture flow: defaults apply when nothing is cached.
class RemoteConfigRepository {
  RemoteConfigRepository(this._settings, this._api);

  final SettingsRepository _settings;
  final AnalysisApi _api;

  Future<RemoteConfig> current() async {
    final raw = await _settings.getRaw(SettingKeys.remoteConfigJson);
    if (raw == null) return const RemoteConfig();
    try {
      return RemoteConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return const RemoteConfig();
    }
  }

  /// Fetches the configuration and caches it. Failures are ignored on purpose:
  /// the app works with the cached or default values.
  Future<void> refresh() async {
    try {
      final config = await _api.fetchConfig();
      await _settings.setRaw(
        SettingKeys.remoteConfigJson,
        jsonEncode(config.toJson()),
      );
    } catch (_) {
      // Offline or backend down: keep using the previous values.
    }
  }
}
