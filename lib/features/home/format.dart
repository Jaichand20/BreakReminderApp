/// Formats a minute total as "0m", "42m", or "1h 05m" (hours plus
/// zero-padded minutes once the total reaches an hour).
String formatMinutes(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

/// Formats an instant as a 12-hour wall-clock time, e.g. "2:35 PM".
String formatClock(DateTime t) {
  final period = t.hour < 12 ? 'AM' : 'PM';
  var hour12 = t.hour % 12;
  if (hour12 == 0) hour12 = 12;
  return '$hour12:${t.minute.toString().padLeft(2, '0')} $period';
}
