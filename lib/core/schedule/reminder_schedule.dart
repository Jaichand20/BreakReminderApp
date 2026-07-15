/// Pure schedule math — no plugins, no platform calls — so it can be unit
/// tested and reasoned about independently of the notification layer.
///
/// Reminders fire every [intervalMinutes] starting from an anchor (Start
/// work, last break end, or last skip). Work sessions are opened and closed
/// manually with Start work / End work, so there is no active-hours window
/// or active-days filter — while a session is running, the next break is
/// always exactly one interval after the last action.
class ReminderSchedule {
  final int intervalMinutes;

  const ReminderSchedule({required this.intervalMinutes});

  bool get isSchedulable => intervalMinutes > 0;

  /// The next `count` reminder instants strictly after `anchor`, each one
  /// interval apart. Empty when the interval is unusable.
  List<DateTime> nextOccurrences(DateTime anchor, {int count = 24}) {
    if (!isSchedulable) return const [];
    return [
      for (var i = 1; i <= count; i++)
        anchor.add(Duration(minutes: intervalMinutes * i)),
    ];
  }
}
