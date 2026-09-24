import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../core/di/providers.dart';
import '../../../shared/l10n_x.dart';
import '../../diary/ui/diary_providers.dart';
import '../../foods/domain/food.dart';
import '../../recognition/domain/analysis.dart';
import '../../recognition/ui/analysis_controller.dart';
import '../domain/meal.dart';
import '../domain/meal_draft.dart';
import '../domain/save_meal_use_case.dart';
import 'item_edit_sheet.dart';
import 'meal_deletion.dart';
import 'meal_draft_notifier.dart';

/// Which flow the editor serves. All three share one editing UI.
enum EditorMode { recognition, manual, edit }

/// Confidence classes: high >= 0.75, medium >= 0.5, low below.
enum ConfidenceLevel {
  high,
  medium,
  low;

  static ConfidenceLevel of(double value) => value >= 0.75
      ? ConfidenceLevel.high
      : value >= 0.5
      ? ConfidenceLevel.medium
      : ConfidenceLevel.low;
}

final saveMealUseCaseProvider = Provider<SaveMealUseCase>(
  (ref) => SaveMealUseCase(
    meals: ref.watch(mealRepositoryProvider),
    photos: ref.watch(photoStorageProvider),
    settings: ref.watch(settingsRepositoryProvider),
  ),
);

/// Review and edit a meal: the recognition result, a manual entry or a saved
/// meal. Totals are recalculated locally after every change.
class DraftEditorScreen extends ConsumerStatefulWidget {
  const DraftEditorScreen({required this.mode, this.mealId, super.key});

  final EditorMode mode;
  final String? mealId;

  @override
  ConsumerState<DraftEditorScreen> createState() => _DraftEditorScreenState();
}

class _DraftEditorScreenState extends ConsumerState<DraftEditorScreen> {
  bool _saving = false;
  bool _leaving = false;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final notifier = ref.read(mealDraftProvider.notifier);
      switch (widget.mode) {
        case EditorMode.edit:
          final found = await notifier.startEdit(widget.mealId!);
          if (!found && mounted) setState(() => _missing = true);
        case EditorMode.manual:
          if (ref.read(mealDraftProvider) == null) notifier.startManual();
        case EditorMode.recognition:
          break;
      }
    });
  }

  /// Removes the draft and its temporary photo. Safe to call repeatedly.
  Future<void> _cleanup() async {
    // Everything is read before the first await: the screen may be gone by then.
    final draft = ref.read(mealDraftProvider);
    final notifier = ref.read(mealDraftProvider.notifier);
    final photos = ref.read(photoStorageProvider);
    if (draft == null) return;
    await photos.deleteTemp(draft.tempPhotoFile);
    notifier.clear();
  }

  Future<void> _leave() async {
    await _cleanup();
    if (!mounted) return;
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.canPop()) context.pop();
    });
  }

  Future<void> _onPop(bool didPop) async {
    if (didPop) {
      // Left without a prompt (nothing to lose): tidy up.
      unawaited(_cleanup());
      return;
    }
    final l10n = context.l10n;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.discardTitle),
        content: Text(l10n.discardBody),
        actions: [
          TextButton(
            key: const Key('keepEditing'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.keepEditing),
          ),
          FilledButton(
            key: const Key('discardChanges'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.discard),
          ),
        ],
      ),
    );
    if (discard == true) await _leave();
  }

  Future<void> _save(MealDraft draft) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final saved = await ref.read(saveMealUseCaseProvider)(draft);
      ref.read(mealDraftProvider.notifier).clear();
      ref.read(selectedDayProvider.notifier).select(saved.mealTime);
      messenger.showSnackBar(SnackBar(content: Text(l10n.mealSaved)));
      if (mounted) {
        setState(() => _leaving = true);
        context.go(Routes.diary);
      }
    } on EmptyMealException {
      if (mounted) setState(() => _saving = false);
    } catch (_) {
      // The draft stays as it is so that the user can retry.
      messenger.showSnackBar(SnackBar(content: Text(l10n.saveFailed)));
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addItem() async {
    final food = await context.push<Food>(Routes.foodSearch);
    if (food == null || !mounted) return;
    final languageCode = ref.read(effectiveLanguageCodeProvider);
    final grams = await showQuantityDialog(
      context,
      name: food.displayName(languageCode),
      initialGrams: food.gramsPerPortion ?? 100,
      units: FoodUnits(
        gramsPerPiece: food.gramsPerPiece,
        gramsPerPortion: food.gramsPerPortion,
        densityGPerMl: food.densityGPerMl,
      ),
    );
    if (grams == null) return;
    ref.read(mealDraftProvider.notifier).addFood(food, grams);
  }

  /// Offers the side photo. Edited items are replaced by the new result, so
  /// the user confirms first; cancelling keeps everything as it is.
  Future<void> _improveAccuracy() async {
    if (ref.read(mealDraftProvider.notifier).hasItemEdits) {
      final l10n = context.l10n;
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.replaceEditsTitle),
          content: Text(l10n.replaceEditsBody),
          actions: [
            TextButton(
              key: const Key('replaceEditsCancel'),
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              key: const Key('replaceEditsConfirm'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.replaceEditsAction),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    await context.push<void>(Routes.captureSide);
  }

  Future<void> _editItem(DraftItem item) async {
    final result = await showItemEditSheet(context, item);
    if (!mounted) return;
    final notifier = ref.read(mealDraftProvider.notifier);
    switch (result) {
      case ItemEdited(:final name, :final weightG, :final per100):
        notifier.updateItem(
          item.id,
          name: name,
          weightG: weightG,
          per100: per100,
        );
      case ItemReplaceRequested():
        final food = await context.push<Food>(Routes.foodSearch);
        if (food != null) notifier.replaceFood(item.id, food);
      case null:
        break;
    }
  }

  Future<void> _pickDate(MealDraft draft) async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: draft.mealTime.isAfter(today) ? today : draft.mealTime,
      firstDate: DateTime(2000),
      lastDate: today,
    );
    if (picked == null) return;
    final t = draft.mealTime;
    ref
        .read(mealDraftProvider.notifier)
        .setMealTime(
          DateTime(picked.year, picked.month, picked.day, t.hour, t.minute),
        );
  }

  Future<void> _pickTime(MealDraft draft) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(draft.mealTime),
    );
    if (picked == null) return;
    final t = draft.mealTime;
    ref
        .read(mealDraftProvider.notifier)
        .setMealTime(
          DateTime(t.year, t.month, t.day, picked.hour, picked.minute),
        );
  }

  String _title(BuildContext context) {
    final l10n = context.l10n;
    return switch (widget.mode) {
      EditorMode.recognition => l10n.resultTitle,
      EditorMode.manual => l10n.newMealTitle,
      EditorMode.edit => l10n.editMealTitle,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final draft = ref.watch(mealDraftProvider);
    final dirty = ref.read(mealDraftProvider.notifier).isDirty;

    return PopScope(
      canPop: _leaving || !dirty,
      onPopInvokedWithResult: (didPop, _) => _onPop(didPop),
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title(context)),
          actions: [
            if (widget.mode == EditorMode.edit && draft != null)
              IconButton(
                key: const Key('deleteMealButton'),
                tooltip: l10n.deleteMeal,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(draft),
              ),
          ],
        ),
        body: draft == null
            ? Center(
                child: _missing
                    ? TextButton(
                        onPressed: () => context.pop(),
                        child: Text(l10n.back),
                      )
                    : const CircularProgressIndicator(),
              )
            : _Editor(
                draft: draft,
                mode: widget.mode,
                onWeightTap: (item) async {
                  final grams = await showWeightDialog(context, item);
                  if (grams != null) {
                    ref
                        .read(mealDraftProvider.notifier)
                        .setWeight(item.id, grams);
                  }
                },
                onEdit: _editItem,
                onRemove: (item) =>
                    ref.read(mealDraftProvider.notifier).removeItem(item.id),
                onAdd: _addItem,
                onImprove: _improveAccuracy,
                onPickDate: () => _pickDate(draft),
                onPickTime: () => _pickTime(draft),
                onDelete: () => _delete(draft),
              ),
        bottomNavigationBar: draft == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton(
                    key: const Key('saveMeal'),
                    onPressed: draft.isEmpty || _saving
                        ? null
                        : () => _save(draft),
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.save),
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _delete(MealDraft draft) async {
    final id = draft.editingMealId;
    if (id == null) return;
    final deleted = await confirmAndDeleteMeal(context, ref, id);
    if (deleted) {
      ref.read(mealDraftProvider.notifier).clear();
      if (mounted) {
        setState(() => _leaving = true);
        context.pop();
      }
    }
  }
}

class _Editor extends ConsumerWidget {
  const _Editor({
    required this.draft,
    required this.mode,
    required this.onWeightTap,
    required this.onEdit,
    required this.onRemove,
    required this.onAdd,
    required this.onImprove,
    required this.onPickDate,
    required this.onPickTime,
    required this.onDelete,
  });

  final MealDraft draft;
  final EditorMode mode;
  final Future<void> Function(DraftItem) onWeightTap;
  final Future<void> Function(DraftItem) onEdit;
  final void Function(DraftItem) onRemove;
  final VoidCallback onAdd;
  final VoidCallback onImprove;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final photo = draft.tempPhotoFile ?? draft.photoPath;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (photo != null) _PhotoHeader(draft: draft),
        if (draft.warnings.contains(WarningCode.partialRecognition))
          _Banner(
            key: const Key('partialBanner'),
            icon: Icons.warning_amber_rounded,
            text: l10n.partialBanner,
          ),
        if (draft.fromRecognition)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              draft.withSidePhoto
                  ? '${l10n.estimateNotice} ${l10n.twoPhotoNote}'
                  : l10n.estimateNotice,
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (draft.fromRecognition &&
            !draft.withSidePhoto &&
            draft.sourceJpeg != null &&
            (ref.watch(sidePhotoSupportedProvider).value ?? false))
          _ImproveAccuracy(onTap: onImprove),
        for (final item in draft.items) ...[
          _ItemCard(
            item: item,
            onWeightTap: () => onWeightTap(item),
            onEdit: () => onEdit(item),
            onRemove: () => onRemove(item),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          key: const Key('addItem'),
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: Text(l10n.addItem),
        ),
        if (draft.isEmpty) ...[
          const SizedBox(height: 12),
          if (mode == EditorMode.edit)
            Card(
              child: ListTile(
                key: const Key('emptyMealOffer'),
                leading: const Icon(Icons.info_outline),
                title: Text(l10n.emptyMealTitle),
                subtitle: Text(l10n.emptyMealBody),
                trailing: TextButton(
                  onPressed: onDelete,
                  child: Text(l10n.deleteMeal),
                ),
              ),
            )
          else
            Text(
              l10n.noItemsHint,
              key: const Key('noItemsHint'),
              style: theme.textTheme.bodyMedium,
            ),
        ],
        const SizedBox(height: 16),
        _TotalsCard(draft: draft),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('pickDate'),
                onPressed: onPickDate,
                icon: const Icon(Icons.event),
                label: Text(
                  DateFormat.yMMMd(context.localeName).format(draft.mealTime),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('pickTime'),
                onPressed: onPickTime,
                icon: const Icon(Icons.schedule),
                label: Text(timeLabel(context, draft.mealTime)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<MealType>(
          key: const Key('mealTypeField'),
          initialValue: draft.mealType,
          decoration: InputDecoration(labelText: l10n.mealTypeFieldLabel),
          items: [
            for (final t in MealType.values)
              DropdownMenuItem(value: t, child: Text(l10n.mealTypeLabel(t))),
          ],
          onChanged: (t) {
            if (t != null) ref.read(mealDraftProvider.notifier).setMealType(t);
          },
        ),
      ],
    );
  }
}

/// A quiet offer next to the estimate, not a step in the flow: the usual
/// single-photo path never needs it.
class _ImproveAccuracy extends StatelessWidget {
  const _ImproveAccuracy({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              key: const Key('improveAccuracy'),
              onPressed: onTap,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(l10n.improveAccuracy),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                l10n.improveAccuracyHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoHeader extends ConsumerWidget {
  const _PhotoHeader({required this.draft});

  final MealDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final File? file = draft.tempPhotoFile != null
        ? File(draft.tempPhotoFile!)
        : draft.photoPath != null
        ? ref.read(photoStorageProvider).resolve(draft.photoPath!)
        : null;
    if (file == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.file(
          file,
          height: 160,
          width: double.infinity,
          fit: BoxFit.cover,
          semanticLabel: context.l10n.mealPhoto,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: scheme.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.onWeightTap,
    required this.onEdit,
    required this.onRemove,
  });

  final DraftItem item;
  final VoidCallback onWeightTap;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fmt = context.fmt;
    final theme = Theme.of(context);
    final confidence = item.confidence == null
        ? null
        : ConfidenceLevel.of(item.confidence!);
    final low = confidence == ConfidenceLevel.low;
    final isEstimate =
        item.source == RecognitionSource.ai &&
        item.weightG == item.estimatedWeightG;
    final personalized = item.isPersonalized;

    return Card(
      key: Key('item-${item.id}'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: low
            ? BorderSide(color: theme.colorScheme.tertiary, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    key: Key('itemName-${item.id}'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  l10n.totalKcal(fmt.kcal(item.values.kcal)),
                  key: Key('itemKcal-${item.id}'),
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            if (low)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  key: Key('lowConfidence-${item.id}'),
                  children: [
                    Icon(
                      Icons.help_outline,
                      size: 16,
                      color: theme.colorScheme.tertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.pleaseCheck,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  ],
                ),
              ),
            if (item.nutritionSource == NutritionSourceName.aiEstimate)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.estimatedNutritionNote,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (personalized)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.personalizedWeightNote(
                    fmt.weight(item.estimatedWeightG!),
                  ),
                  key: Key('personalized-${item.id}'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ActionChip(
                      key: Key('weight-${item.id}'),
                      avatar: const Icon(Icons.scale_outlined, size: 18),
                      label: Text(
                        '${fmt.weight(item.weightG)} ${l10n.gramsUnit}'
                        '${isEstimate ? ' · ${l10n.estimatedWeight}' : ''}'
                        '${personalized ? ' · ${l10n.personalizedWeight}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: onWeightTap,
                    ),
                  ),
                ),
                IconButton(
                  key: Key('edit-${item.id}'),
                  tooltip: l10n.editItemTitle,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: onEdit,
                ),
                IconButton(
                  key: Key('remove-${item.id}'),
                  tooltip: l10n.removeItem,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onRemove,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.draft});

  final MealDraft draft;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fmt = context.fmt;
    final theme = Theme.of(context);
    final totals = draft.totals;
    Widget macro(String label, double v) => Expanded(
      child: Column(
        children: [
          Text(
            l10n.macroConsumed(fmt.macro(v)),
            style: theme.textTheme.titleMedium,
          ),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              // Unsaved AI results are shown as an approximation.
              draft.fromRecognition
                  ? l10n.approxKcal(fmt.approximateKcal(totals.kcal))
                  : l10n.totalKcal(fmt.kcal(totals.kcal)),
              key: const Key('draftTotal'),
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                macro(l10n.proteinLabel, totals.protein),
                macro(l10n.fatLabel, totals.fat),
                macro(l10n.carbsLabel, totals.carbs),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
