import 'package:shared_preferences/shared_preferences.dart';

/// Backed by shared_preferences (MethodChannel-based) — this must only ever
/// be read or written from the UI isolate, never from the background
/// notification-response handler.
class SettingsRepository {
  static const _kPaused = 'paused';
  static const _kIntervalMinutes = 'interval_minutes';
  static const _kSquatsPerReminder = 'squats_per_reminder';

  static const int defaultIntervalMinutes = 60;
  static const int defaultSquatsPerReminder = 10;

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

  Future<int> squatsPerReminder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kSquatsPerReminder) ?? defaultSquatsPerReminder;
  }

  Future<void> setSquatsPerReminder(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSquatsPerReminder, count);
  }
}
