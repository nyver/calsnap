import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/di/providers.dart';
import '../../../core/utils/clock.dart';
import '../../../shared/l10n_x.dart';
import '../domain/statistics.dart';

/// The last seven days as a stream that updates after every save, edit or delete.
final weekStatsProvider = StreamProvider.autoDispose<WeekStats>((ref) {
  final today = dateOnly(ref.watch(clockProvider)());
  final target = ref.watch(currentSettingsProvider).dailyKcalTarget;
  final start = addDays(today, -6);
  final end = addDays(today, 1);
  return ref
      .watch(mealRepositoryProvider)
      .watchRange(start, end)
      .map(
        (meals) =>
            computeWeekStats(meals: meals, today: today, kcalTarget: target),
      );
});

/// Basic 7-day statistics: calorie bars with the target line, averages and
/// adherence. Computed locally, works offline.
class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final stats = ref.watch(weekStatsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.statsTitle)),
      body: stats.when(
        data: (s) => _Content(stats: s),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.initErrorBody)),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.stats});

  final WeekStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fmt = context.fmt;
    final theme = Theme.of(context);
    final locale = context.localeName;

    Widget macro(String label, double value) => Expanded(
      child: Column(
        children: [
          Text(
            l10n.macroConsumed(fmt.macro(value)),
            style: theme.textTheme.titleMedium,
          ),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Semantics(
          label: l10n.statsChartLabel,
          child: SizedBox(
            height: 220,
            child: CustomPaint(
              key: const Key('weekChart'),
              painter: WeekChartPainter(
                days: stats.days,
                target: stats.kcalTarget,
                barColor: theme.colorScheme.primary,
                targetColor: theme.colorScheme.tertiary,
                textStyle:
                    theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11),
                weekdayLabels: [
                  for (final d in stats.days)
                    DateFormat.E(locale).format(d.day),
                ],
                emptyColor: theme.colorScheme.outlineVariant,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        if (stats.kcalTarget != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Container(
                  width: 16,
                  height: 2,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.statsTarget(fmt.kcal(stats.kcalTarget!.toDouble())),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        if (!stats.hasData)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              l10n.statsNoData,
              key: const Key('statsNoData'),
              textAlign: TextAlign.center,
            ),
          ),
        Card(
          child: ListTile(
            title: Text(l10n.statsToday),
            trailing: Text(
              l10n.totalKcal(fmt.kcal(stats.today.kcal)),
              key: const Key('statsToday'),
              style: theme.textTheme.titleLarge,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.statsAverage, style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Text(
                  l10n.totalKcal(fmt.kcal(stats.average.kcal)),
                  key: const Key('statsAverage'),
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    macro(l10n.proteinLabel, stats.average.protein),
                    macro(l10n.fatLabel, stats.average.fat),
                    macro(l10n.carbsLabel, stats.average.carbs),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (stats.kcalTarget != null && stats.hasData) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(
                l10n.statsAdherence(stats.onTargetDays, stats.loggedDays),
                key: const Key('statsAdherence'),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Bars of kcal per day with a dashed target line. Days without meals stay
/// empty (a thin baseline mark), they are not drawn as zero intake.
class WeekChartPainter extends CustomPainter {
  WeekChartPainter({
    required this.days,
    required this.target,
    required this.barColor,
    required this.targetColor,
    required this.emptyColor,
    required this.textStyle,
    required this.weekdayLabels,
  });

  final List<DayStats> days;
  final int? target;
  final Color barColor;
  final Color targetColor;
  final Color emptyColor;
  final TextStyle textStyle;
  final List<String> weekdayLabels;

  @override
  void paint(Canvas canvas, Size size) {
    const bottomLabel = 22.0;
    const topLabel = 16.0;
    final chartHeight = size.height - bottomLabel - topLabel;
    final maxKcal = math.max(
      math.max(target?.toDouble() ?? 0, 1),
      days.fold<double>(0, (m, d) => math.max(m, d.totals.kcal)),
    );
    final slot = size.width / days.length;
    final barWidth = slot * 0.55;
    final baseline = topLabel + chartHeight;

    for (var i = 0; i < days.length; i++) {
      final d = days[i];
      final x = slot * i + (slot - barWidth) / 2;
      if (d.hasMeals) {
        final h = chartHeight * (d.totals.kcal / maxKcal);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, baseline - h, barWidth, h),
            const Radius.circular(6),
          ),
          Paint()..color = barColor,
        );
        _text(
          canvas,
          d.totals.kcal.round().toString(),
          Offset(x + barWidth / 2, baseline - h - 14),
          center: true,
        );
      } else {
        canvas.drawRect(
          Rect.fromLTWH(x, baseline - 2, barWidth, 2),
          Paint()..color = emptyColor,
        );
      }
      _text(
        canvas,
        weekdayLabels[i],
        Offset(x + barWidth / 2, baseline + 4),
        center: true,
      );
    }

    final t = target;
    if (t != null) {
      final y = baseline - chartHeight * (t / maxKcal);
      final paint = Paint()
        ..color = targetColor
        ..strokeWidth = 2;
      for (double x = 0; x < size.width; x += 12) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + 6, size.width), y),
          paint,
        );
      }
    }
  }

  void _text(Canvas canvas, String text, Offset at, {bool center = false}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(canvas, center ? at - Offset(painter.width / 2, 0) : at);
  }

  @override
  bool shouldRepaint(WeekChartPainter old) =>
      old.days != days || old.target != target || old.barColor != barColor;
}
