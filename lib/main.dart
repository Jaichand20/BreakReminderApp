import 'package:flutter/material.dart';

import 'core/db/break_repository.dart';
import 'core/notifications/notification_service.dart';
import 'core/settings/settings_repository.dart';
import 'features/home/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final notifications = NotificationService();
  final settings = SettingsRepository();
  var openBreakOnLaunch = false;

  // A notification-plugin failure (e.g. permission revoked, OEM quirk) must
  // not prevent the app itself from launching — stats and settings still work.
  try {
    await notifications.init();
    final paused = await settings.isPaused();
    if (!paused) {
      // Top the chain up only when it's running low — rescheduling on every
      // launch would re-anchor the cadence each time the app is opened.
      final pending = await notifications.pendingChainCount();
      if (pending < 8) {
        await notifications.rescheduleChain(
            await settings.schedule(), DateTime.now());
      }
    }
    openBreakOnLaunch = await notifications.launchedByStartBreak();
  } catch (e, st) {
    debugPrint('break_reminder: notification setup failed: $e\n$st');
  }
  final repository = BreakRepository.open();

  runApp(BreakReminderApp(
    repository: repository,
    notifications: notifications,
    settings: settings,
    openBreakOnLaunch: openBreakOnLaunch,
  ));
}

class BreakReminderApp extends StatelessWidget {
  final BreakRepository repository;
  final NotificationService notifications;
  final SettingsRepository settings;
  final bool openBreakOnLaunch;

  const BreakReminderApp({
    super.key,
    required this.repository,
    required this.notifications,
    required this.settings,
    required this.openBreakOnLaunch,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Break Reminder',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: HomeScreen(
        repository: repository,
        notifications: notifications,
        settings: settings,
        openBreakOnLaunch: openBreakOnLaunch,
      ),
    );
  }
}
