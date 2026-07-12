/// Formats a minute total as "0m", "42m", or "1h 05m" (hours plus
/// zero-padded minutes once the total reaches an hour).
String formatMinutes(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}
