import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/di/providers.dart';
import '../../../core/domain/nutrition.dart';
import '../../../shared/l10n_x.dart';
import '../../barcode/ui/barcode_providers.dart';
import '../../foods/domain/food.dart';
import '../../meal/domain/meal.dart';
import '../../meal/domain/nutrition_calculator.dart';
import '../../meal/ui/item_edit_sheet.dart';
import '../../meal/ui/meal_deletion.dart';
import '../../meal/ui/meal_draft_notifier.dart';
import '../../settings/domain/user_settings.dart';
import 'diary_providers.dart';

/// Today / diary: progress against the targets and the meals of a day.
class DiaryScreen extends ConsumerWidget {
  const DiaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final day = ref.watch(selectedDayProvider);
    final today = ref.watch(clockProvider)();
    final isToday = day == DateTime(today.year, today.month, today.day);
    final meals = ref.watch(dayMealsProvider(day));
    final settings = ref.watch(currentSettingsProvider);
    final notifier = ref.read(selectedDayProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(dayLabel(context, day, today), key: const Key('dayTitle')),
        actions: [
          IconButton(
            key: const Key('prevDay'),
            tooltip: l10n.previousDay,
            icon: const Icon(Icons.chevron_left),
            onPressed: notifier.previous,
          ),
          IconButton(
            key: const Key('nextDay'),
            tooltip: l10n.nextDay,
            icon: const Icon(Icons.chevron_right),
            onPressed: isToday ? null : notifier.next,
          ),
          if (!isToday)
            TextButton(
              key: const Key('goToToday'),
              onPressed: notifier.goToToday,
              child: Text(l10n.today),
            ),
          IconButton(
            key: const Key('openCalendar'),
            tooltip: l10n.openCalendar,
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => context.go(Routes.history),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('addMeal'),
        onPressed: () => _showAddSheet(context, ref),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: Text(l10n.addMeal),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v > 300) notifier.previous();
          if (v < -300) notifier.next();
        },
        child: meals.when(
          data: (list) =>
              _DayContent(day: day, meals: list, settings: settings),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(child: Text(l10n.initErrorBody)),
        ),
      ),
    );
  }

  /// A packaged product goes straight into a new manual meal: scan, choose
  /// the quantity, review, save. No photo of the plate is needed.
  Future<void> _scanToNewMeal(BuildContext context, WidgetRef ref) async {
    final food = await context.push<Food>(Routes.scan);
    if (food == null || !context.mounted) return;
    final grams = await askFoodQuantity(
      context,
      food: food,
      languageCode: ref.read(effectiveLanguageCodeProvider),
    );
    if (grams == null || !context.mounted) return;
    ref.read(mealDraftProvider.notifier)
      ..startManual()
      ..addFood(food, grams);
    unawaited(context.push(Routes.newMeal));
  }

  Future<void> _showAddSheet(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('addTakePhoto'),
              leading: const Icon(Icons.photo_camera),
              title: Text(l10n.takePhoto),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push(Routes.capture);
              },
            ),
            ListTile(
              key: const Key('addFromGallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.chooseFromGallery),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push(Routes.capture, extra: true);
              },
            ),
            Consumer(
              builder: (_, sheetRef, _) =>
                  (sheetRef.watch(barcodeSupportedProvider).value ?? false)
                  ? ListTile(
                      key: const Key('addScanBarcode'),
                      leading: const Icon(Icons.qr_code_scanner),
                      title: Text(l10n.scanBarcode),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        unawaited(_scanToNewMeal(context, ref));
                      },
                    )
                  : const SizedBox.shrink(),
            ),
            ListTile(
              key: const Key('addManually'),
              leading: const Icon(Icons.edit_note),
              title: Text(l10n.addManually),
              onTap: () {
                Navigator.pop(sheetContext);
                ref.read(mealDraftProvider.notifier).startManual();
                context.push(Routes.newMeal);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DayContent extends ConsumerWidget {
  const _DayContent({
    required this.day,
    required this.meals,
    required this.settings,
  });

  final DateTime day;
  final List<Meal> meals;
  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = NutritionCalculator.total(meals.map((m) => m.totals));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        DaySummary(totals: totals, settings: settings),
        const SizedBox(height: 16),
        if (meals.isEmpty)
          const _EmptyDay()
        else
          for (final meal in meals) ...[
            _MealTile(meal: meal),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

/// Calories and macros of a day against the targets.
class DaySummary extends StatelessWidget {
  const DaySummary({required this.totals, required this.settings, super.key});

  final Nutrition totals;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fmt = context.fmt;
    final theme = Theme.of(context);
    final target = settings.dailyKcalTarget;
    final consumed = totals.kcal;
    final over = target != null && consumed > target;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              target == null
                  ? l10n.kcalConsumedOnly(fmt.kcal(consumed))
                  : l10n.kcalProgress(fmt.kcal(consumed), '$target'),
              key: const Key('kcalProgress'),
              style: theme.textTheme.headlineMedium,
            ),
            if (target != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  minHeight: 10,
                  value: (consumed / target).clamp(0.0, 1.0),
                  // Being over the target is information, not an error.
                  color: over ? theme.colorScheme.tertiary : null,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                over
                    ? l10n.kcalOver(fmt.kcal(consumed - target))
                    : l10n.kcalRemaining(fmt.kcal(target - consumed)),
                key: const Key('kcalRemaining'),
                style: theme.textTheme.bodyLarge,
              ),
            ],
            const SizedBox(height: 16),
            _MacroRow(
              label: l10n.proteinLabel,
              value: totals.protein,
              target: settings.dailyProteinTargetG,
            ),
            _MacroRow(
              label: l10n.fatLabel,
              value: totals.fat,
              target: settings.dailyFatTargetG,
            ),
            _MacroRow(
              label: l10n.carbsLabel,
              value: totals.carbs,
              target: settings.dailyCarbsTargetG,
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroRow extends StatelessWidget {
  const _MacroRow({
    required this.label,
    required this.value,
    required this.target,
  });

  final String label;
  final double value;
  final int? target;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fmt = context.fmt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(
                target == null
                    ? l10n.macroConsumed(fmt.macro(value))
                    : l10n.macroProgress(fmt.macro(value), '$target'),
              ),
            ],
          ),
          if (target != null && target! > 0) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: (value / target!).clamp(0.0, 1.0),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      key: const Key('emptyDay'),
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.restaurant_outlined,
            size: 64,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(l10n.emptyDayTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(l10n.emptyDayBody, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _MealTile extends ConsumerWidget {
  const _MealTile({required this.meal});

  final Meal meal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final fmt = context.fmt;
    return Card(
      child: ListTile(
        key: Key('meal-${meal.id}'),
        contentPadding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        leading: MealThumbnail(photoPath: meal.photoPath),
        title: Text(l10n.mealTypeLabel(meal.mealType)),
        subtitle: Text(timeLabel(context, meal.mealTime)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.totalKcal(fmt.kcal(meal.totals.kcal)),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            PopupMenuButton<String>(
              key: Key('mealMenu-${meal.id}'),
              onSelected: (value) {
                if (value == 'edit') {
                  context.push(Routes.editMeal(meal.id));
                } else {
                  confirmAndDeleteMeal(context, ref, meal.id);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'edit', child: Text(l10n.edit)),
                PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
              ],
            ),
          ],
        ),
        onTap: () => context.push(Routes.editMeal(meal.id)),
      ),
    );
  }
}

/// Photo thumbnail with a placeholder for meals without (or with a missing) photo.
class MealThumbnail extends ConsumerWidget {
  const MealThumbnail({required this.photoPath, this.size = 48, super.key});

  final String? photoPath;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.restaurant, color: scheme.outline),
    );
    final path = photoPath;
    if (path == null) return placeholder;
    final File file;
    try {
      file = ref.read(photoStorageProvider).resolve(path);
    } on ArgumentError {
      return placeholder;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.file(
        file,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 3).round(),
        semanticLabel: context.l10n.mealPhoto,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}
