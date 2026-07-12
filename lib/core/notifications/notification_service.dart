import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../db/squat_repository.dart';
import '../settings/settings_repository.dart';

const int _reminderNotificationId = 1001;
const int _testNotificationId = 1002;
const String _channelId = 'squat_reminders';
const String _channelName = 'Squat reminders';
const String _channelDescription = 'Hourly reminders to do a few squats';

const String _actionDone = 'done';
const String _actionSkip = 'skip';

final FlutterLocalNotificationsPlugin _plugin =
    FlutterLocalNotificationsPlugin();

/// Wraps flutter_local_notifications for the "hourly Done/Skip reminder"
/// flow. Scheduling relies on `periodicallyShowWithDuration`, which uses
/// Android's AlarmManager under the hood and ships its own boot-receiver, so
/// reminders survive both app-kill and device reboot with no extra plugin.
class NotificationService {
  Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onForegroundResponse,
      onDidReceiveBackgroundNotificationResponse:
          onBackgroundNotificationResponse,
    );
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
  }

  AndroidNotificationDetails _details(int squatsPerReminder) {
    return AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      actions: [
        AndroidNotificationAction(
          _actionDone,
          'Done ✓ (+$squatsPerReminder)',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        const AndroidNotificationAction(
          _actionSkip,
          'Skip',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );
  }

  Future<void> scheduleReminders({
    required int intervalMinutes,
    required int squatsPerReminder,
  }) async {
    await _plugin.cancel(_reminderNotificationId);
    await _plugin.periodicallyShowWithDuration(
      _reminderNotificationId,
      'Time to move',
      '$squatsPerReminder squats. Thirty seconds.',
      Duration(minutes: intervalMinutes),
      NotificationDetails(android: _details(squatsPerReminder)),
      payload: squatsPerReminder.toString(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> cancelReminders() async {
    await _plugin.cancel(_reminderNotificationId);
  }

  /// Fires one reminder immediately, for verifying the flow without waiting
  /// out a full interval.
  Future<void> sendTestReminder(int squatsPerReminder) async {
    await _plugin.show(
      _testNotificationId,
      'Time to move',
      '$squatsPerReminder squats. Thirty seconds. (test)',
      NotificationDetails(android: _details(squatsPerReminder)),
      payload: squatsPerReminder.toString(),
    );
  }
}

void _onForegroundResponse(NotificationResponse response) {
  _handleResponse(response);
}

/// Fires when Done/Skip is tapped while the app isn't running. This isolate
/// has no Flutter engine attached, so only FFI-based packages (sqlite3) are
/// usable here — not shared_preferences, not path_provider.
@pragma('vm:entry-point')
void onBackgroundNotificationResponse(NotificationResponse response) {
  _handleResponse(response);
}

void _handleResponse(NotificationResponse response) {
  if (response.actionId != _actionDone) return;
  final parsed = int.tryParse(response.payload ?? '') ??
      SettingsRepository.defaultSquatsPerReminder;
  // The payload should always be a small positive int we set ourselves, but
  // this handler also runs headless where an uncaught throw kills the whole
  // isolate — so treat it as untrusted and never let an error escape.
  final count = parsed.clamp(1, 1000);
  SquatRepository? repo;
  try {
    repo = SquatRepository.open();
    repo.logCompletion(count);
  } catch (e, st) {
    debugPrint('squat_reminder: failed to log completion: $e\n$st');
  } finally {
    repo?.close();
  }
}
