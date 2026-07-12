import 'package:sqlite3/sqlite3.dart';

import 'database.dart';

class DailyStats {
  final int today;
  final int week;
  final int month;
  final int allTime;

  const DailyStats({
    required this.today,
    required this.week,
    required this.month,
    required this.allTime,
  });
}

class BestDay {
  final String date;
  final int count;

  const BestDay({required this.date, required this.count});
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

/// Calendar-based day arithmetic. `add(Duration(days: n))` on a local
/// DateTime shifts by exactly n*24h, which lands on the wrong calendar day
/// around DST transitions; the constructor normalizes out-of-range days
/// without involving wall-clock time.
DateTime _daysFrom(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

/// Ported 1:1 from the original app's `squat_db.py`. Every date bucket is a
/// half-open range `[start, end)` on the first 10 characters of the ISO
/// timestamp, exactly matching the Python implementation.
class SquatRepository {
  final Database _db;

  SquatRepository(this._db);

  factory SquatRepository.open() => SquatRepository(openSquatsDatabase());

  void close() => _db.dispose();

  void logCompletion(int count) {
    _db.execute(
      'INSERT INTO squats (timestamp, count) VALUES (?, ?)',
      [DateTime.now().toIso8601String().substring(0, 19), count],
    );
  }

  int _sumBetween(String startDate, String endDate) {
    final row = _db.select(
      '''
      SELECT COALESCE(SUM(count), 0) FROM squats
      WHERE substr(timestamp, 1, 10) >= ? AND substr(timestamp, 1, 10) < ?
      ''',
      [startDate, endDate],
    ).first;
    return row.columnAt(0) as int;
  }

  int todaysTotal() {
    final today = DateTime.now();
    return _sumBetween(_isoDate(today), _isoDate(_daysFrom(today, 1)));
  }

  int allTimeTotal() {
    final row =
        _db.select('SELECT COALESCE(SUM(count), 0) FROM squats').first;
    return row.columnAt(0) as int;
  }

  DailyStats stats() {
    final today = DateTime.now();
    final tomorrow = _isoDate(_daysFrom(today, 1));
    final weekStart = _isoDate(_daysFrom(today, -6));
    final monthStart = _isoDate(_daysFrom(today, -29));
    return DailyStats(
      today: _sumBetween(_isoDate(today), tomorrow),
      week: _sumBetween(weekStart, tomorrow),
      month: _sumBetween(monthStart, tomorrow),
      allTime: allTimeTotal(),
    );
  }

  /// `{'YYYY-MM-DD': total}` for every date with activity in `[start, end)`.
  Map<String, int> dailyTotals(String startDate, String endDate) {
    final rows = _db.select(
      '''
      SELECT substr(timestamp, 1, 10) AS d, SUM(count)
      FROM squats
      WHERE substr(timestamp, 1, 10) >= ? AND substr(timestamp, 1, 10) < ?
      GROUP BY d
      ''',
      [startDate, endDate],
    );
    return {
      for (final r in rows) r.columnAt(0) as String: r.columnAt(1) as int
    };
  }

  /// 12 totals, January through December, for the given year.
  List<int> monthlyTotals(int year) {
    final rows = _db.select(
      '''
      SELECT substr(timestamp, 6, 2) AS m, SUM(count)
      FROM squats
      WHERE substr(timestamp, 1, 4) = ?
      GROUP BY m
      ''',
      [year.toString().padLeft(4, '0')],
    );
    final totals = List<int>.filled(12, 0);
    for (final r in rows) {
      final m = int.parse(r.columnAt(0) as String);
      totals[m - 1] = r.columnAt(1) as int;
    }
    return totals;
  }

  Map<String, int> yearDailyTotals(int year) =>
      dailyTotals('${year.toString().padLeft(4, '0')}-01-01',
          '${(year + 1).toString().padLeft(4, '0')}-01-01');

  int currentStreak() {
    final rows =
        _db.select('SELECT DISTINCT substr(timestamp, 1, 10) FROM squats');
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
      SELECT substr(timestamp, 1, 10) AS d, SUM(count) AS total
      FROM squats GROUP BY d ORDER BY total DESC LIMIT 1
    ''');
    if (rows.isEmpty) return null;
    final row = rows.first;
    return BestDay(
        date: row.columnAt(0) as String, count: row.columnAt(1) as int);
  }
}
