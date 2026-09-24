/// Returns the current instant. Injected so that tests control time.
typedef Clock = DateTime Function();

/// Conversions between UTC epoch milliseconds and local calendar time. The
/// default follows the device time zone; tests inject fixed-offset zones to
/// verify day-boundary logic for arbitrary zones.
class TimeZoneRules {
  const TimeZoneRules();

  /// Local midnight of the given calendar day. Day overflow (e.g. day 32) is
  /// normalized.
  DateTime startOfDay(int year, int month, int day) =>
      DateTime(year, month, day);

  /// Local date and time of an instant.
  DateTime fromEpochMs(int epochMs) =>
      DateTime.fromMillisecondsSinceEpoch(epochMs);

  /// UTC epoch milliseconds of a local date and time.
  int toEpochMs(DateTime local) => local.toUtc().millisecondsSinceEpoch;
}

/// Half-open interval [startMs, endMs) in UTC epoch milliseconds.
class TimeRange {
  const TimeRange(this.startMs, this.endMs);

  /// The local calendar day that contains [date].
  factory TimeRange.day(
    DateTime date, {
    TimeZoneRules zone = const TimeZoneRules(),
  }) {
    final start = zone.startOfDay(date.year, date.month, date.day);
    final end = zone.startOfDay(date.year, date.month, date.day + 1);
    return TimeRange(zone.toEpochMs(start), zone.toEpochMs(end));
  }

  /// The local calendar month that contains [date].
  factory TimeRange.month(
    DateTime date, {
    TimeZoneRules zone = const TimeZoneRules(),
  }) {
    final start = zone.startOfDay(date.year, date.month, 1);
    final end = zone.startOfDay(date.year, date.month + 1, 1);
    return TimeRange(zone.toEpochMs(start), zone.toEpochMs(end));
  }

  final int startMs;
  final int endMs;

  bool contains(int epochMs) => epochMs >= startMs && epochMs < endMs;
}

/// Strips the time of day (local).
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Adds [days] calendar days, unaffected by DST changes.
DateTime addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);
