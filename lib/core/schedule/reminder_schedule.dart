/// Pure schedule math — no plugins, no platform calls — so it can be unit
/// tested and reasoned about independently of the notification layer.
///
/// The user picks which weekdays the app is active (`activeDays`, ISO
/// weekday numbers: 1 = Monday … 7 = Sunday) and a daily window
/// [`startMinutes`, `endMinutes`] in minutes from midnight. Reminders fire
/// every `intervalMinutes` starting from an anchor (last break end, last
/// skip, or "now" on app launch), but only inside the active window; a
/// reminder that would land outside it rolls forward to the next active
/// day's window start.
class ReminderSchedule {
  final Set<int> activeDays;
  final int startMinutes;
  final int endMinutes;
  final int intervalMinutes;

  const ReminderSchedule({
    required this.activeDays,
    required this.startMinutes,
    required this.endMinutes,
    required this.intervalMinutes,
  });

  bool get isSchedulable =>
      activeDays.isNotEmpty && endMinutes > startMinutes && intervalMinutes > 0;

  bool _isActiveDay(DateTime t) => activeDays.contains(t.weekday);

  int _minutesOfDay(DateTime t) => t.hour * 60 + t.minute;

  DateTime _atWindowStart(DateTime day) => DateTime(
      day.year, day.month, day.day, startMinutes ~/ 60, startMinutes % 60);

  /// Moves `t` forward to the nearest instant inside an active window
  /// (possibly `t` itself). Never moves backwards.
  DateTime rollIntoWindow(DateTime t) {
    var cursor = t;
    // Bounded loop: within any 8 consecutive days there is an active day
    // whenever activeDays is non-empty.
    for (var i = 0; i < 8; i++) {
      if (_isActiveDay(cursor) && _minutesOfDay(cursor) <= endMinutes) {
        if (_minutesOfDay(cursor) >= startMinutes) return cursor;
        return _atWindowStart(cursor);
      }
      cursor = _atWindowStart(
          DateTime(cursor.year, cursor.month, cursor.day)
              .add(const Duration(days: 1)));
    }
    return cursor;
  }

  /// The next `count` reminder instants strictly after `anchor`, each one
  /// interval apart, rolled into the active window. Empty when the schedule
  /// is unusable (no active days or an inverted window).
  List<DateTime> nextOccurrences(DateTime anchor, {int count = 24}) {
    if (!isSchedulable) return const [];
    final result = <DateTime>[];
    var t = anchor.add(Duration(minutes: intervalMinutes));
    for (var i = 0; i < count; i++) {
      t = rollIntoWindow(t);
      result.add(t);
      t = t.add(Duration(minutes: intervalMinutes));
    }
    return result;
  }
}
