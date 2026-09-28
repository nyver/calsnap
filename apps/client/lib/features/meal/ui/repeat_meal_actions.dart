import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../../app/router.dart';
import '../../../shared/l10n_x.dart';
import '../domain/repeat_meal_use_case.dart';
import 'meal_draft_notifier.dart';
import 'recent_meals_screen.dart' show recentMealsProvider;

final _log = Logger('RepeatMeal');

/// Starts a repeat of [mealId] and opens it in the meal editor. On
/// [RepeatMealFailure.notFound] the recent meals list is refreshed; any other
/// failure is logged without meal content and shown as a generic message.
/// Uses `pushReplacement` instead of `push` when [replace] is set (from the
/// saved-meal editor, so Back returns to the diary, not a stale edit screen).
Future<void> startRepeatAndOpen(
  BuildContext context,
  WidgetRef ref,
  String mealId, {
  bool replace = false,
}) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(mealDraftProvider.notifier).startRepeat(mealId);
  } on RepeatMealException catch (e) {
    if (e.failure == RepeatMealFailure.notFound) {
      ref.invalidate(recentMealsProvider);
      messenger.showSnackBar(SnackBar(content: Text(l10n.repeatMealNotFound)));
    } else {
      messenger.showSnackBar(SnackBar(content: Text(l10n.repeatMealFailed)));
    }
    return;
  } catch (e) {
    _log.warning('Failed to start a repeat', e);
    messenger.showSnackBar(SnackBar(content: Text(l10n.repeatMealFailed)));
    return;
  }
  if (!context.mounted) return;
  if (replace) {
    context.pushReplacement(Routes.newMeal);
  } else {
    unawaited(context.push<Object?>(Routes.newMeal));
  }
}
