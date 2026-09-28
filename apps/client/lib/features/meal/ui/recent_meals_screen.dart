import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/di/providers.dart';
import '../../../shared/l10n_x.dart';
import '../domain/meal.dart';
import '../domain/repeat_meal_use_case.dart';
import 'repeat_meal_actions.dart';

/// Saved meals from the last [repeatMealLookbackDays] days, newest first, at
/// most [repeatMealMaxResults] meals: the source list for "Eat this again".
final recentMealsProvider = FutureProvider.autoDispose<List<Meal>>((ref) {
  final useCase = ref.watch(repeatMealUseCaseProvider);
  final now = ref.watch(clockProvider)();
  return ref
      .watch(mealRepositoryProvider)
      .recentMeals(
        since: useCase.recentSince(now),
        limit: repeatMealMaxResults,
      );
});

/// Lets the user pick a previously saved meal to repeat.
class RecentMealsScreen extends ConsumerWidget {
  const RecentMealsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final meals = ref.watch(recentMealsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.recentMealsHeader)),
      body: meals.when(
        data: (list) => list.isEmpty
            ? const _EmptyState()
            : ListView.builder(
                key: const Key('recentMealsList'),
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _RecentMealCard(meal: list[index]),
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            _ErrorState(onRetry: () => ref.invalidate(recentMealsProvider)),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        key: const Key('repeatEmptyState'),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              l10n.repeatEmptyTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(l10n.repeatEmptyBody, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('repeatEmptyAction'),
              onPressed: () => context.pushReplacement(Routes.capture),
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(l10n.repeatEmptyAction),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        key: const Key('recentMealsErrorState'),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.recentMealsError, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('recentMealsRetry'),
              onPressed: onRetry,
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentMealCard extends ConsumerWidget {
  const _RecentMealCard({required this.meal});

  final Meal meal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final fmt = context.fmt;
    final theme = Theme.of(context);
    final today = ref.watch(clockProvider)();
    final names = [for (final item in meal.items) item.name];
    final shown = names.take(3).join(', ');
    final more = names.length - 3;
    final itemsLine = more > 0 ? '$shown, ${l10n.moreItems(more)}' : shown;
    final kcal = meal.totals.kcal.round();

    return Card(
      key: Key('recentMeal-${meal.id}'),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => startRepeatAndOpen(context, ref, meal.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                // Replaces the descendant texts' own semantics with the
                // single combined label from the spec, so the card announces
                // one clear string instead of every line separately.
                child: Semantics(
                  label: l10n.eatAgainSemantics(shown, kcal),
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${dayLabel(context, meal.mealTime, today)} · '
                        '${timeLabel(context, meal.mealTime)} · '
                        '${l10n.mealTypeLabel(meal.mealType)}',
                        style: theme.textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        itemsLine,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.totalKcal(fmt.kcal(meal.totals.kcal)),
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 12,
                        runSpacing: 2,
                        children: [
                          Text(
                            '${l10n.proteinLabel}: ${fmt.macro(meal.totals.protein)}',
                            style: theme.textTheme.bodySmall,
                          ),
                          Text(
                            '${l10n.fatLabel}: ${fmt.macro(meal.totals.fat)}',
                            style: theme.textTheme.bodySmall,
                          ),
                          Text(
                            '${l10n.carbsLabel}: ${fmt.macro(meal.totals.carbs)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                key: Key('repeatMeal-${meal.id}'),
                tooltip: l10n.repeatMeal,
                icon: const Icon(Icons.replay),
                onPressed: () => startRepeatAndOpen(context, ref, meal.id),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
