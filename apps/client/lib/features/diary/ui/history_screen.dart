import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../core/di/providers.dart';
import '../../../core/utils/clock.dart';
import '../../../shared/l10n_x.dart';
import 'diary_providers.dart';

/// Calendar of the diary: days with meals are marked; tapping a day opens it.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final selected = ref.read(selectedDayProvider);
    _month = DateTime(selected.year, selected.month);
  }

  void _shiftMonth(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final today = dateOnly(ref.watch(clockProvider)());
    final selected = ref.watch(selectedDayProvider);
    final marked = ref.watch(monthDaysProvider(_month)).value ?? const <int>{};
    final locale = context.localeName;
    final currentMonth = DateTime(today.year, today.month);
    final isCurrentMonth = !_month.isBefore(currentMonth);

    final materialL10n = MaterialLocalizations.of(context);
    final firstWeekday = materialL10n.firstDayOfWeekIndex; // 0 = Sunday
    final leadingBlanks =
        (DateTime(_month.year, _month.month).weekday % 7 - firstWeekday + 7) %
        7;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final weekdayLabels = [
      for (var i = 0; i < 7; i++)
        DateFormat.E(locale).format(
          // 2023-01-01 was a Sunday.
          DateTime(2023, 1, 1 + (firstWeekday + i) % 7),
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.historyTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('prevMonth'),
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _shiftMonth(-1),
              ),
              Expanded(
                child: Text(
                  DateFormat.yMMMM(locale).format(_month),
                  key: const Key('monthTitle'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                key: const Key('nextMonth'),
                icon: const Icon(Icons.chevron_right),
                onPressed: isCurrentMonth ? null : () => _shiftMonth(1),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final label in weekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
              for (var day = 1; day <= daysInMonth; day++)
                _DayCell(
                  date: DateTime(_month.year, _month.month, day),
                  hasMeals: marked.contains(day),
                  isToday: DateTime(_month.year, _month.month, day) == today,
                  isSelected:
                      DateTime(_month.year, _month.month, day) == selected,
                  isFuture: DateTime(
                    _month.year,
                    _month.month,
                    day,
                  ).isAfter(today),
                  onTap: () {
                    ref
                        .read(selectedDayProvider.notifier)
                        .select(DateTime(_month.year, _month.month, day));
                    context.go(Routes.diary);
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(l10n.historyHint, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.hasMeals,
    required this.isToday,
    required this.isSelected,
    required this.isFuture,
    required this.onTap,
  });

  final DateTime date;
  final bool hasMeals;
  final bool isToday;
  final bool isSelected;
  final bool isFuture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textColor = isFuture
        ? scheme.outline.withValues(alpha: 0.5)
        : isSelected
        ? scheme.onPrimary
        : null;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        key: Key('day-${date.day}'),
        borderRadius: BorderRadius.circular(12),
        onTap: isFuture ? null : onTap,
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? scheme.primary : null,
            border: isToday && !isSelected
                ? Border.all(color: scheme.primary, width: 1.5)
                : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${date.day}', style: TextStyle(color: textColor)),
              const SizedBox(height: 2),
              SizedBox(
                height: 6,
                child: hasMeals
                    ? Container(
                        key: Key('marker-${date.day}'),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? scheme.onPrimary
                              : scheme.tertiary,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
