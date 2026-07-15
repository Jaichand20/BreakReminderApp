import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../db/break_repository.dart';
import '../schedule/reminder_schedule.dart';
import '../settings/settings_repository.dart';

/// The reminder cycle re-anchors whenever the user acts (Start work, Skip,
/// End break), so a single repeating notification can't model it. Instead we
/// keep a chain of one-shot scheduled notifications (the next [_chainLength]
/// occurrences):
/// - Start work / End break happen in the UI isolate: cancel the chain and
///   reschedule it anchored at that instant.
/// - Skip fires in a headless isolate where the plugin can't reschedule, so
///   it only logs; [syncSchedule] re-anchors at the skip the next time the
///   app runs. Until then the chain's own cadence (each link one interval
///   after the previous) already approximates "one interval after skip",
///   because the insistent buzz makes the user act within seconds of firing.
const int _chainLength = 24;
const int _chainBaseId = 2000;
const int _testNotificationId = 1002;

/// v2: the original channel had no vibration pattern, and Android channel
/// settings are immutable once created — a new id is the only way to change
/// them. The old channel is deleted in [NotificationService.init].
const String _channelId = 'break_reminders_v2';
const String _legacyChannelId = 'break_reminders';
const String _channelName = 'Break reminders';
const String _channelDescription = 'Reminders to take a break';

const String actionTakeBreak = 'take_break';
const String actionSkip = 'skip';

/// Notification.FLAG_INSISTENT — repeats the channel's sound/vibration in a
/// loop ("constant buzz") until the notification is cancelled, which happens
/// when the user picks Take break or Skip (both set cancelNotification) or
/// taps the body (autoCancel).
const int _flagInsistent = 4;

final FlutterLocalNotificationsPlugin _plugin =
    FlutterLocalNotificationsPlugin();

class NotificationService {
  /// Bumped every time the user taps "Take break" on a reminder while the
  /// app is alive; the home screen listens and opens the break screen.
  final ValueNotifier<int> takeBreakRequests = ValueNotifier(0);

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
    await androidImpl?.deleteNotificationChannel(_legacyChannelId);
    await androidImpl?.requestNotificationsPermission();
  }

  void _onForegroundResponse(NotificationResponse response) {
    if (response.actionId == actionTakeBreak ||
        response.actionId == null && response.payload == 'reminder') {
      takeBreakRequests.value += 1;
    }
  }

  /// True when the app process was launched by a "Take break" tap (or a tap
  /// on the reminder body) on a notification — the caller should open the
  /// break screen immediately.
  Future<bool> launchedByTakeBreak() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return false;
    final response = details!.notificationResponse;
    if (response == null) return false;
    return response.actionId == actionTakeBreak ||
        response.actionId == null && response.payload == 'reminder';
  }

  NotificationDetails _details() {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 700, 350, 700, 350, 700]),
        additionalFlags: Int32List.fromList([_flagInsistent]),
        // Can't be swiped away — the buzz only stops via Take break, Skip,
        // or tapping the body (which opens the break screen).
        ongoing: true,
        autoCancel: true,
        actions: const [
          AndroidNotificationAction(
            actionTakeBreak,
            'Take break',
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

  /// Exact delivery when permitted (USE_EXACT_ALARM is auto-granted on
  /// Android 13+), so the break lands exactly one interval after the anchor;
  /// otherwise fall back to inexact rather than crash.
  Future<AndroidScheduleMode> _scheduleMode() async {
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final canExact =
        await androidImpl?.canScheduleExactNotifications() ?? false;
    return canExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  /// Cancels the existing chain and schedules the next [_chainLength]
  /// reminders per [schedule], anchored at [anchor] (Start work, break end,
  /// or a reconciled skip).
  Future<void> rescheduleChain(
      ReminderSchedule schedule, DateTime anchor) async {
    await cancelChain();
    final now = DateTime.now();
    var occurrences = schedule
        .nextOccurrences(anchor, count: _chainLength)
        .where((t) => t.isAfter(now))
        .toList();
    // An anchor far in the past (e.g. a skip from days ago reconciled only
    // now) can leave nothing in the future — restart the cycle from now.
    if (occurrences.isEmpty) {
      occurrences = schedule.nextOccurrences(now, count: _chainLength);
    }
    final mode = await _scheduleMode();
    for (var i = 0; i < occurrences.length; i++) {
      // TZDateTime.from with an explicit UTC location pins the absolute
      // instant, which is all a one-shot alarm needs — no device-timezone
      // lookup plugin required.
      final when = tz.TZDateTime.from(occurrences[i].toUtc(), tz.UTC);
      await _plugin.zonedSchedule(
        _chainBaseId + i,
        'Time for a break',
        'Take a break now, or skip until the next one.',
        when,
        _details(),
        payload: 'reminder',
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  /// Re-anchors the whole cycle at [anchor]: remembers the anchor (so the
  /// home screen can show the next break time and [syncSchedule] can compare
  /// against later skips) and reschedules the chain unless paused.
  Future<void> restartCycle(
      SettingsRepository settings, DateTime anchor) async {
    await settings.setLastAnchor(anchor);
    if (await settings.isPaused()) return;
    await rescheduleChain(await settings.schedule(), anchor);
  }

  /// Brings the chain in line with events that happened while the app wasn't
  /// running. Called at launch and on resume:
  /// - A Skip tapped from the shade only logs (the headless isolate can't
  ///   reschedule) — if one is newer than the current anchor, re-anchor the
  ///   cycle at the skip instant.
  /// - If work was never started, nothing should be scheduled.
  /// - If the chain is running low, top it up from now.
  Future<void> syncSchedule(
      BreakRepository repository, SettingsRepository settings) async {
    // Mid-break, the cycle re-anchors at End break — leave it alone.
    if (await settings.activeBreakStart() != null) return;
    if (await settings.isPaused()) return;

    final anchor = await settings.lastAnchor();
    if (anchor == null) {
      // Not working (never started, or work was ended) — nothing should be
      // scheduled, and old skips must not resurrect the cycle.
      await cancelChain();
      return;
    }
    final lastSkip = repository.lastSkipTime();
    if (lastSkip != null && lastSkip.isAfter(anchor)) {
      await restartCycle(settings, lastSkip);
      return;
    }
    if (await pendingChainCount() < 8) {
      await restartCycle(settings, DateTime.now());
    }
  }

  /// How many reminders of the chain are still pending. Used to top the
  /// chain up only when it is running low, so that merely opening the app
  /// doesn't re-anchor the cadence.
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

  /// Silences and clears every reminder (including a currently-buzzing one).
  /// Called when a break starts — no reminder should fire mid-break; the
  /// cycle is rescheduled when the break ends.
  Future<void> cancelAllReminders() async {
    await cancelChain();
    await _plugin.cancel(_testNotificationId);
  }

  /// Fires one reminder immediately, for verifying the flow without waiting
  /// out a full interval.
  Future<void> sendTestReminder() async {
    await _plugin.show(
      _testNotificationId,
      'Time for a break',
      'Take a break now, or skip until the next one. (test)',
      _details(),
      payload: 'reminder',
    );
  }
}

/// Fires when Skip is tapped, always in a headless isolate (actions without
/// showsUserInterface never reach the app engine). No Flutter engine is
/// attached, so only FFI-based packages (sqlite3) are usable here — not
/// shared_preferences, and not the notifications plugin itself, which is why
/// the re-anchor happens later in [NotificationService.syncSchedule].
/// "Take break" never lands here: it has showsUserInterface true, so it
/// launches/resumes the app instead.
@pragma('vm:entry-point')
void onBackgroundNotificationResponse(NotificationResponse response) {
  if (response.actionId != actionSkip) return;
  // An uncaught throw here kills the whole headless isolate — never let a
  // DB error escape.
  BreakRepository? repo;
  try {
    repo = BreakRepository.open();
    repo.logSkip();
  } catch (e, st) {
    debugPrint('break_reminder: failed to log skip: $e\n$st');
  } finally {
    repo?.close();
  }
}
