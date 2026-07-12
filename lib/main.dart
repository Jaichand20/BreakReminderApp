import 'package:flutter/material.dart';

import 'core/db/squat_repository.dart';
import 'core/notifications/notification_service.dart';
import 'core/settings/settings_repository.dart';
import 'features/home/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final notifications = NotificationService();
  final settings = SettingsRepository();

  // A notification-plugin failure (e.g. permission revoked, OEM quirk) must
  // not prevent the app itself from launching — stats and settings still work.
  try {
    await notifications.init();
    final paused = await settings.isPaused();
    if (!paused) {
      await notifications.scheduleReminders(
        intervalMinutes: await settings.intervalMinutes(),
        squatsPerReminder: await settings.squatsPerReminder(),
      );
    }
  } catch (e, st) {
    debugPrint('squat_reminder: notification setup failed: $e\n$st');
  }

  final repository = SquatRepository.open();

  runApp(SquatReminderApp(
    repository: repository,
    notifications: notifications,
    settings: settings,
  ));
}

class SquatReminderApp extends StatelessWidget {
  final SquatRepository repository;
  final NotificationService notifications;
  final SettingsRepository settings;

  const SquatReminderApp({
    super.key,
    required this.repository,
    required this.notifications,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Squat Reminder',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: HomeScreen(
        repository: repository,
        notifications: notifications,
        settings: settings,
      ),
    );
  }
}
