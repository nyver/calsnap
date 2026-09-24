import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/files/photo_storage.dart';
import '../../../shared/l10n_x.dart';
import '../domain/meal.dart';

/// Time during which a deleted meal can be restored.
const Duration undoWindow = Duration(seconds: 5);

/// Deletes meals with an undo window. The photo file is removed only after the
/// window has passed, so that an undo brings back the complete meal.
class MealDeletionController {
  MealDeletionController(this._ref) : _photos = _ref.read(photoStorageProvider);

  final Ref _ref;

  /// Captured up front: providers cannot be read while the controller is
  /// being disposed.
  final PhotoStorage _photos;
  final Map<String, Timer> _photoTimers = {};
  final Map<String, String> _photoPaths = {};

  /// Deletes the meal and returns its snapshot for [undo].
  Future<Meal?> delete(String mealId) async {
    final snapshot = await _ref.read(mealRepositoryProvider).delete(mealId);
    final photo = snapshot?.photoPath;
    if (snapshot != null && photo != null) {
      _photoPaths[mealId] = photo;
      _photoTimers[mealId] = Timer(
        undoWindow + const Duration(seconds: 1),
        () => _removePhoto(mealId),
      );
    }
    return snapshot;
  }

  Future<void> undo(Meal snapshot) async {
    _photoTimers.remove(snapshot.id)?.cancel();
    _photoPaths.remove(snapshot.id);
    await _ref.read(mealRepositoryProvider).restore(snapshot);
  }

  Future<void> _removePhoto(String mealId) async {
    _photoTimers.remove(mealId);
    final path = _photoPaths.remove(mealId);
    if (path != null) {
      await _photos.delete(path);
    }
  }

  /// Completes pending photo deletions (the app is going away).
  void dispose() {
    for (final id in _photoTimers.keys.toList()) {
      _photoTimers.remove(id)?.cancel();
      final path = _photoPaths.remove(id);
      if (path != null) {
        unawaited(_photos.delete(path));
      }
    }
  }
}

final mealDeletionProvider = Provider<MealDeletionController>((ref) {
  final controller = MealDeletionController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

/// Asks for confirmation, deletes the meal and offers "Undo". Returns true when
/// the meal was deleted.
Future<bool> confirmAndDeleteMeal(
  BuildContext context,
  WidgetRef ref,
  String mealId,
) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final controller = ref.read(mealDeletionProvider);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.deleteMealTitle),
      content: Text(l10n.deleteMealBody),
      actions: [
        TextButton(
          key: const Key('deleteMealCancel'),
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('deleteMealConfirm'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  final snapshot = await controller.delete(mealId);
  if (snapshot == null) return false;
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(l10n.mealDeleted),
        duration: undoWindow,
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () => controller.undo(snapshot),
        ),
      ),
    );
  return true;
}
