import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/clock.dart';
import '../utils/ids.dart';

/// Meal photos and temporary files on the file system. Photos are never stored
/// in SQLite; only the relative path is.
class PhotoStorage {
  PhotoStorage({
    required this.documentsDir,
    required this.tempDir,
    required this.cacheDir,
    this._ids = const IdGenerator(),
    Clock? clock,
  }) : _clock = clock ?? DateTime.now;

  /// App-private documents directory (permanent photos live below `meals/`).
  final Directory documentsDir;

  /// Base of temporary capture files (`capture/` below).
  final Directory tempDir;

  /// Base of generated export files.
  final Directory cacheDir;

  final IdGenerator _ids;
  final Clock _clock;

  static const String mealsFolder = 'meals';
  static const String captureFolder = 'capture';
  static const String exportsFolder = 'exports';

  Directory get _captureDir => Directory(p.join(tempDir.path, captureFolder));

  Directory get exportsDir => Directory(p.join(cacheDir.path, exportsFolder));

  /// A new, not yet existing file in the temporary capture directory.
  Future<File> newTempFile({String extension = 'jpg'}) async {
    await _captureDir.create(recursive: true);
    return File(p.join(_captureDir.path, '${_ids.newId()}.$extension'));
  }

  /// Copies [temp] to `meals/YYYY/MM/DD/<uuid>.jpg` based on the local date of
  /// [date] and returns the path relative to the documents directory. The
  /// temporary file is kept so that a failed save can be retried; the caller
  /// deletes it once the meal is stored.
  Future<String> persist(File temp, DateTime date) async {
    final relative = p.posix.join(
      mealsFolder,
      date.year.toString().padLeft(4, '0'),
      date.month.toString().padLeft(2, '0'),
      date.day.toString().padLeft(2, '0'),
      '${_ids.newId()}.jpg',
    );
    final target = resolve(relative);
    await target.parent.create(recursive: true);
    await temp.copy(target.path);
    return relative;
  }

  /// Absolute file for a stored relative path. Paths that would leave the
  /// documents directory are rejected.
  File resolve(String relative) {
    final full = p.normalize(p.join(documentsDir.path, relative));
    if (!p.isWithin(documentsDir.path, full)) {
      throw ArgumentError.value(relative, 'relative', 'escapes documents dir');
    }
    return File(full);
  }

  /// Whether the stored photo still exists.
  bool exists(String relative) => resolve(relative).existsSync();

  Future<void> delete(String? relative) async {
    if (relative == null) return;
    await _deleteFile(resolve(relative));
  }

  Future<void> deleteTemp(String? absolutePath) async {
    if (absolutePath == null) return;
    await _deleteFile(File(absolutePath));
  }

  /// Best-effort delete: a file that is briefly locked (virus scanner, media
  /// indexer) is retried; a persistent failure is ignored, because an orphaned
  /// photo is preferable to a crash. Leftovers are swept on the next start.
  Future<void> _deleteFile(File file) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        if (file.existsSync()) await file.delete();
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
  }

  /// Removes leftover temporary capture files (abandoned drafts).
  Future<void> sweepTemp() => _deleteDirectory(_captureDir);

  /// Removes stale export files.
  Future<void> sweepExports() => _deleteDirectory(exportsDir);

  /// Deletes all stored meal photos.
  Future<void> clearPhotos() =>
      _deleteDirectory(Directory(p.join(documentsDir.path, mealsFolder)));

  Future<void> _deleteDirectory(Directory dir) async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  /// Name for an export file: `calsnap-export-YYYYMMDD-HHmm.<extension>`.
  File newExportFile(String extension) {
    final t = _clock();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${t.year.toString().padLeft(4, '0')}${two(t.month)}${two(t.day)}'
        '-${two(t.hour)}${two(t.minute)}';
    return File(p.join(exportsDir.path, 'calsnap-export-$stamp.$extension'));
  }
}
