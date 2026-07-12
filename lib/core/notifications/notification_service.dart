import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../db/break_repository.dart';
import '../schedule/reminder_schedule.dart';

/// The reminder cycle re-anchors whenever a break ends, so a single
/// repeating notification can't model it. Instead we keep a chain of
/// one-shot scheduled notifications (the next [_chainLength] occurrences):
/// - Ignoring or skipping a reminder costs nothing — the rest of the chain
///   still fires on the old cadence.
/// - Ending a break (always in the UI isolate, since the stopwatch lives in
///   the app) cancels the chain and reschedules it anchored at break end.
/// - The chain is topped back up every app launch/resume, so it can't run
///   dry in normal use.
const int _chainLength = 24;
const int _chainBaseId = 2000;
const int _testNotificationId = 1002;

const String _channelId = 'break_reminders';
const String _channelName = 'Break reminders';
const String _channelDescription = 'Reminders to take a break';

const String actionStartBreak = 'start_break';
const String actionSkip = 'skip';

final FlutterLocalNotificationsPlugin _plugin =
    FlutterLocalNotificationsPlugin();

class NotificationService {
  /// Bumped every time the user taps "Start break" on a notification while
  /// the app is alive; the home screen listens and opens the break screen.
  final ValueNotifier<int> startBreakRequests = ValueNotifier(0);

  Future<void> init() async {
    tz_data.initializeTimeZones();
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

  void _onForegroundResponse(NotificationResponse response) {
    if (response.actionId == actionStartBreak ||
        response.actionId == null && response.payload == 'reminder') {
      startBreakRequests.value += 1;
    }
  }

  /// True when the app process was launched by a "Start break" tap (or a tap
  /// on the reminder body) on a notification — the caller should open the
  /// break screen immediately.
  Future<bool> launchedByStartBreak() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return false;
    final response = details!.notificationResponse;
    if (response == null) return false;
    return response.actionId == actionStartBreak ||
        response.actionId == null && response.payload == 'reminder';
  }

  NotificationDetails _details() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        actions: [
          AndroidNotificationAction(
            actionStartBreak,
            'Start break',
            showsUserInterface: true,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            actionSkip,
            'Skip',
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ],
      ),
    );
  }

  /// Cancels the existing chain and schedules the next [_chainLength]
  /// reminders per [schedule], anchored at [anchor] (break end, or "now").
  Future<void> rescheduleChain(ReminderSchedule schedule, DateTime anchor) async {
    await cancelChain();
    final occurrences = schedule.nextOccurrences(anchor, count: _chainLength);
    for (var i = 0; i < occurrences.length; i++) {
      // TZDateTime.from with an explicit UTC location pins the absolute
      // instant, which is all a one-shot alarm needs — no device-timezone
      // lookup plugin required.
      final when = tz.TZDateTime.from(occurrences[i].toUtc(), tz.UTC);
      await _plugin.zonedSchedule(
        _chainBaseId + i,
        'Time for a break',
        'Step away for a few minutes.',
        when,
        _details(),
        payload: 'reminder',
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  /// How many reminders of the chain are still pending. Used at app launch
  /// to top the chain up only when it is running low, so that merely opening
  /// the app doesn't re-anchor the cadence.
  Future<int> pendingChainCount() async {
    final pending = await _plugin.pendingNotificationRequests();
    return pending
        .where((p) =>
            p.id >= _chainBaseId && p.id < _chainBaseId + _chainLength)
        .length;
  }

  Future<void> cancelChain() async {
    for (var i = 0; i < _chainLength; i++) {
      await _plugin.cancel(_chainBaseId + i);
    }
  }

  /// Fires one reminder immediately, for verifying the flow without waiting
  /// out a full interval.
  Future<void> sendTestReminder() async {
    await _plugin.show(
      _testNotificationId,
      'Time for a break',
      'Step away for a few minutes. (test)',
      _details(),
      payload: 'reminder',
    );
  }
}

/// Fires when Skip is tapped while the app isn't in the foreground. This
/// isolate has no Flutter engine attached, so only FFI-based packages
/// (sqlite3) are usable here — not shared_preferences, not path_provider.
/// "Start break" never lands here: it has showsUserInterface true, so it
/// launches/resumes the app instead.
@pragma('vm:entry-point')
void onBackgroundNotificationResponse(NotificationResponse response) {
  if (response.actionId != actionSkip) return;
  final repo = BreakRepository.open();
  try {
    repo.logSkip();
  } finally {
    repo.close();
  }
}
