import 'dart:io';

import '../../../core/files/photo_storage.dart';
import '../../settings/domain/settings_repository.dart';
import 'meal_draft.dart';
import 'meal_repository.dart';

/// Thrown when a draft without items is saved.
class EmptyMealException implements Exception {
  const EmptyMealException();
}

/// Result of a successful save.
class SavedMeal {
  const SavedMeal({required this.id, required this.mealTime});

  final String id;
  final DateTime mealTime;
}

/// Saves a draft: stores the photo according to the retention setting, writes
/// the meal in one transaction and cleans up temporary files. On failure the
/// draft (and its temporary photo) stay untouched so the user can retry.
class SaveMealUseCase {
  SaveMealUseCase({
    required this._meals,
    required this._photos,
    required this._settings,
  });

  final MealRepository _meals;
  final PhotoStorage _photos;
  final SettingsRepository _settings;

  Future<SavedMeal> call(MealDraft draft) async {
    if (draft.isEmpty) throw const EmptyMealException();

    var photoPath = draft.photoPath;
    String? storedNow;
    final temp = draft.tempPhotoFile;
    if (temp != null) {
      final keep = (await _settings.read()).savePhotos;
      final file = File(temp);
      if (keep && file.existsSync()) {
        storedNow = await _photos.persist(file, draft.mealTime);
        photoPath = storedNow;
      }
    }

    try {
      final id = await _meals.save(draft, photoPath: photoPath);
      await _photos.deleteTemp(temp);
      return SavedMeal(id: id, mealTime: draft.mealTime);
    } catch (_) {
      // Do not leave an orphaned photo behind; the temporary copy is kept.
      await _photos.delete(storedNow);
      rethrow;
    }
  }
}
