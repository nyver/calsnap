import 'dart:io';

import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';

import 'app_database.dart';

/// Opens the on-device database.
///
/// The schema version stored in the file is read first with a read-only
/// connection: a database written by a newer app version is rejected with
/// [UnsupportedSchemaException] before anything is written to it.
Future<AppDatabase> openAppDatabase(File file) async {
  if (file.existsSync()) {
    final raw = sqlite3.open(file.path, mode: OpenMode.readOnly);
    try {
      final version = raw.select('PRAGMA user_version').first.values.first;
      if (version is int && version > AppDatabase.currentSchemaVersion) {
        throw UnsupportedSchemaException(
          found: version,
          supported: AppDatabase.currentSchemaVersion,
        );
      }
    } finally {
      raw.close();
    }
  }
  return AppDatabase(NativeDatabase.createInBackground(file));
}
