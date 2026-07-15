import 'package:shared_preferences/shared_preferences.dart';

import '../schedule/reminder_schedule.dart';

/// Backed by shared_preferences (MethodChannel-based) — this must only ever
/// be read or written from the UI isolate, never from the background
/// notification-response handler.
class SettingsRepository {
  static const _kPaused = 'paused';
  static const _kIntervalMinutes = 'interval_minutes';
  static const _kActiveBreakStart = 'active_break_start';
  static const _kLastAnchor = 'last_anchor';
  static const _kWorkStartedAt = 'work_started_at';

  static const int defaultIntervalMinutes = 60;

  Future<bool> isPaused() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kPaused) ?? false;
  }

  Future<void> setPaused(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPaused, value);
  }

  Future<int> intervalMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kIntervalMinutes) ?? defaultIntervalMinutes;
  }

  Future<void> setIntervalMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kIntervalMinutes, minutes);
  }

  Future<ReminderSchedule> schedule() async {
    return ReminderSchedule(intervalMinutes: await intervalMinutes());
  }

  /// When a break is in progress, the instant it started — persisted so the
  /// stopwatch survives the app being killed mid-break. Null otherwise.
  Future<DateTime?> activeBreakStart() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kActiveBreakStart);
    if (stored == null) return null;
    return DateTime.tryParse(stored);
  }

  Future<void> setActiveBreakStart(DateTime? start) async {
    final prefs = await SharedPreferences.getInstance();
    if (start == null) {
      await prefs.remove(_kActiveBreakStart);
    } else {
      await prefs.setString(_kActiveBreakStart, start.toIso8601String());
    }
  }

  /// The instant the reminder cycle was last anchored at (Start work, break
  /// end, or a reconciled skip) — the next break is one interval after this.
  /// Null while not working (before the first Start work, or after End
  /// work); no reminders are scheduled then.
  Future<DateTime?> lastAnchor() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kLastAnchor);
    if (stored == null) return null;
    return DateTime.tryParse(stored);
  }

  Future<void> setLastAnchor(DateTime? anchor) async {
    final prefs = await SharedPreferences.getInstance();
    if (anchor == null) {
      await prefs.remove(_kLastAnchor);
    } else {
      await prefs.setString(_kLastAnchor, anchor.toIso8601String());
    }
  }

  /// When the current work session began (the Start work press that opened
  /// it) — used for the End work day summary. Null when not working.
  Future<DateTime?> workStartedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kWorkStartedAt);
    if (stored == null) return null;
    return DateTime.tryParse(stored);
  }

  Future<void> setWorkStartedAt(DateTime? start) async {
    final prefs = await SharedPreferences.getInstance();
    if (start == null) {
      await prefs.remove(_kWorkStartedAt);
    } else {
      await prefs.setString(_kWorkStartedAt, start.toIso8601String());
    }
  }
}
