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
  final repository = BreakRepository.open();
  var openBreakOnLaunch = false;

  // A notification-plugin failure (e.g. permission revoked, OEM quirk) must
  // not prevent the app itself from launching — stats and settings still work.
  try {
    await notifications.init();
    // Re-anchor after any Skip logged while the app wasn't running, and top
    // the chain up if it's running low.
    await notifications.syncSchedule(repository, settings);
    openBreakOnLaunch = await notifications.launchedByTakeBreak();
  } catch (e, st) {
    debugPrint('break_reminder: notification setup failed: $e\n$st');
  }

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
