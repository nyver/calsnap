import '../../../core/database/app_database.dart';
import '../domain/settings_repository.dart';
import '../domain/user_settings.dart';

/// Stores settings as key/value rows of `user_settings`.
class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<AppSettings> watch() =>
      _db.select(_db.userSettings).watch().map(_fromRows);

  @override
  Future<AppSettings> read() async =>
      _fromRows(await _db.select(_db.userSettings).get());

  @override
  Future<void> save(AppSettings s) => _db.transaction(() async {
    await _put(SettingKeys.dailyKcalTarget, s.dailyKcalTarget?.toString());
    await _put(
      SettingKeys.dailyProteinTargetG,
      s.dailyProteinTargetG?.toString(),
    );
    await _put(SettingKeys.dailyFatTargetG, s.dailyFatTargetG?.toString());
    await _put(SettingKeys.dailyCarbsTargetG, s.dailyCarbsTargetG?.toString());
    await _put(SettingKeys.plateDiameterCm, s.plateDiameterCm?.toString());
    await _put(SettingKeys.savePhotos, s.savePhotos.toString());
    await _put(SettingKeys.language, s.language.name);
    await _put(SettingKeys.unitSystem, s.unitSystem);
    await _put(
      SettingKeys.onboardingCompleted,
      s.onboardingCompleted.toString(),
    );
    await _put(SettingKeys.apiBaseUrl, s.apiBaseUrl);
  });

  @override
  Future<String?> getRaw(String key) async {
    final row = await (_db.select(
      _db.userSettings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  @override
  Future<void> setRaw(String key, String value) => _put(key, value);

  Future<void> _put(String key, String? value) async {
    if (value == null) {
      await (_db.delete(
        _db.userSettings,
      )..where((t) => t.key.equals(key))).go();
      return;
    }
    await _db
        .into(_db.userSettings)
        .insertOnConflictUpdate(
          UserSettingsCompanion.insert(key: key, value: value),
        );
  }

  static AppSettings _fromRows(List<SettingRow> rows) {
    final map = {for (final r in rows) r.key: r.value};
    return AppSettings(
      dailyKcalTarget: _int(map[SettingKeys.dailyKcalTarget]),
      dailyProteinTargetG: _int(map[SettingKeys.dailyProteinTargetG]),
      dailyFatTargetG: _int(map[SettingKeys.dailyFatTargetG]),
      dailyCarbsTargetG: _int(map[SettingKeys.dailyCarbsTargetG]),
      plateDiameterCm: double.tryParse(map[SettingKeys.plateDiameterCm] ?? ''),
      // Photos are saved unless the user turned it off.
      savePhotos: map[SettingKeys.savePhotos] != 'false',
      language: AppLanguage.fromName(map[SettingKeys.language]),
      onboardingCompleted: map[SettingKeys.onboardingCompleted] == 'true',
      apiBaseUrl: map[SettingKeys.apiBaseUrl],
    );
  }

  static int? _int(String? v) => v == null ? null : int.tryParse(v);
}
