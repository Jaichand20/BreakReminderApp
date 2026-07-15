import 'package:sqlite3/sqlite3.dart';

import 'database.dart';

class BreakStats {
  final int todayCount;
  final int todayMinutes;
  final int weekMinutes;
  final int monthMinutes;
  final int allTimeCount;
  final int allTimeMinutes;

  const BreakStats({
    required this.todayCount,
    required this.todayMinutes,
    required this.weekMinutes,
    required this.monthMinutes,
    required this.allTimeCount,
    required this.allTimeMinutes,
  });
}

class BestDay {
  final String date;
  final int minutes;

  const BestDay({required this.date, required this.minutes});
}

class TrendResult {
  final String label;
  final List<String> dates;
  final List<int> values;

  const TrendResult({
    required this.label,
    required this.dates,
    required this.values,
  });
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String isoTimestamp(DateTime d) => d.toIso8601String().substring(0, 19);

/// Calendar-based day arithmetic. `add(Duration(days: n))` on a local
/// DateTime shifts by exactly n*24h, which lands on the wrong calendar day
/// around DST transitions; the constructor normalizes out-of-range days
/// without involving wall-clock time.
DateTime _daysFrom(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

/// All aggregates count completed breaks only; skips are logged for the
/// record but never shown in stats. Every date bucket is a half-open range
/// `[start, end)` on the first 10 characters of the ISO start timestamp,
/// and durations aggregate in seconds then round to minutes.
class BreakRepository {
  final Database _db;

  BreakRepository(this._db);

  factory BreakRepository.open() => BreakRepository(openBreaksDatabase());

  void close() => _db.dispose();

  void logBreak(DateTime start, DateTime end) {
    final seconds = end.difference(start).inSeconds;
    _db.execute(
      'INSERT INTO breaks (start_ts, end_ts, duration_seconds, status) '
      "VALUES (?, ?, ?, 'completed')",
      [isoTimestamp(start), isoTimestamp(end), seconds < 0 ? 0 : seconds],
    );
  }

  void logSkip([DateTime? at]) {
    _db.execute(
      'INSERT INTO breaks (start_ts, end_ts, duration_seconds, status) '
      "VALUES (?, NULL, 0, 'skipped')",
      [isoTimestamp(at ?? DateTime.now())],
    );
  }

  /// When the most recent skip was logged, or null if none ever was. Skips
  /// are written by the headless notification isolate, which can't touch the
  /// scheduled chain — the UI isolate reads this to re-anchor the cycle.
  DateTime? lastSkipTime() {
    final rows = _db.select(
        "SELECT start_ts FROM breaks WHERE status = 'skipped' "
        'ORDER BY start_ts DESC LIMIT 1');
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first.columnAt(0) as String);
  }

  /// How many reminders were skipped today, for the End work day summary.
  int todaySkipCount() {
    final row = _db.select(
      "SELECT COUNT(*) FROM breaks WHERE status = 'skipped' "
      'AND substr(start_ts, 1, 10) = ?',
      [_isoDate(DateTime.now())],
    ).first;
    return row.columnAt(0) as int;
  }

  static int _toMinutes(int seconds) => (seconds / 60).round();

  /// `[count, seconds]` of completed breaks whose start date is in
  /// `[startDate, endDate)`.
  List<int> _countAndSecondsBetween(String startDate, String endDate) {
    final row = _db.select(
      '''
      SELECT COUNT(*), COALESCE(SUM(duration_seconds), 0) FROM breaks
      WHERE status = 'completed'
        AND substr(start_ts, 1, 10) >= ? AND substr(start_ts, 1, 10) < ?
      ''',
      [startDate, endDate],
    ).first;
    return [row.columnAt(0) as int, row.columnAt(1) as int];
  }

  BreakStats stats() {
    final today = DateTime.now();
    final tomorrow = _isoDate(_daysFrom(today, 1));
    final weekStart = _isoDate(_daysFrom(today, -6));
    final monthStart = _isoDate(_daysFrom(today, -29));

    final todayRes = _countAndSecondsBetween(_isoDate(today), tomorrow);
    final weekRes = _countAndSecondsBetween(weekStart, tomorrow);
    final monthRes = _countAndSecondsBetween(monthStart, tomorrow);
    final allRow = _db.select('''
      SELECT COUNT(*), COALESCE(SUM(duration_seconds), 0) FROM breaks
      WHERE status = 'completed'
    ''').first;

    return BreakStats(
      todayCount: todayRes[0],
      todayMinutes: _toMinutes(todayRes[1]),
      weekMinutes: _toMinutes(weekRes[1]),
      monthMinutes: _toMinutes(monthRes[1]),
      allTimeCount: allRow.columnAt(0) as int,
      allTimeMinutes: _toMinutes(allRow.columnAt(1) as int),
    );
  }

  /// `{'YYYY-MM-DD': minutes}` for every date with a completed break in
  /// `[start, end)`.
  Map<String, int> dailyMinutes(String startDate, String endDate) {
    final rows = _db.select(
      '''
      SELECT substr(start_ts, 1, 10) AS d, SUM(duration_seconds)
      FROM breaks
      WHERE status = 'completed'
        AND substr(start_ts, 1, 10) >= ? AND substr(start_ts, 1, 10) < ?
      GROUP BY d
      ''',
      [startDate, endDate],
    );
    return {
      for (final r in rows)
        r.columnAt(0) as String: _toMinutes(r.columnAt(1) as int),
    };
  }

  /// 12 minute-totals, January through December, for the given year.
  List<int> monthlyMinutes(int year) {
    final rows = _db.select(
      '''
      SELECT substr(start_ts, 6, 2) AS m, SUM(duration_seconds)
      FROM breaks
      WHERE status = 'completed' AND substr(start_ts, 1, 4) = ?
      GROUP BY m
      ''',
      [year.toString().padLeft(4, '0')],
    );
    final totals = List<int>.filled(12, 0);
    for (final r in rows) {
      final m = int.parse(r.columnAt(0) as String);
      totals[m - 1] = _toMinutes(r.columnAt(1) as int);
    }
    return totals;
  }

  Map<String, int> yearDailyMinutes(int year) =>
      dailyMinutes('${year.toString().padLeft(4, '0')}-01-01',
          '${(year + 1).toString().padLeft(4, '0')}-01-01');

  /// Consecutive days with at least one completed break, counting back from
  /// today (or yesterday if today has none yet).
  int currentStreak() {
    final rows = _db.select(
        "SELECT DISTINCT substr(start_ts, 1, 10) FROM breaks WHERE status = 'completed'");
    final activeDays = {for (final r in rows) r.columnAt(0) as String};
    if (activeDays.isEmpty) return 0;

    final today = DateTime.now();
    var cursor = activeDays.contains(_isoDate(today))
        ? today
        : _daysFrom(today, -1);
    if (!activeDays.contains(_isoDate(cursor))) return 0;

    var streak = 0;
    while (activeDays.contains(_isoDate(cursor))) {
      streak += 1;
      cursor = _daysFrom(cursor, -1);
    }
    return streak;
  }

  BestDay? bestDay() {
    final rows = _db.select('''
      SELECT substr(start_ts, 1, 10) AS d, SUM(duration_seconds) AS total
      FROM breaks WHERE status = 'completed'
      GROUP BY d ORDER BY total DESC LIMIT 1
    ''');
    if (rows.isEmpty) return null;
    final row = rows.first;
    return BestDay(
        date: row.columnAt(0) as String,
        minutes: _toMinutes(row.columnAt(1) as int));
  }
}
