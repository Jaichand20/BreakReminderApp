import 'package:flutter/material.dart';

import '../../core/db/squat_repository.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/settings/settings_repository.dart';
import '../../theme.dart';
import '../settings/settings_screen.dart';
import 'widgets/heatmap.dart';
import 'widgets/stat_tile.dart';
import 'widgets/trend_chart.dart';

class HomeScreen extends StatefulWidget {
  final SquatRepository repository;
  final NotificationService notifications;
  final SettingsRepository settings;

  const HomeScreen({
    super.key,
    required this.repository,
    required this.notifications,
    required this.settings,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _refreshTick = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Squats logged from a notification action while the app was
    // backgrounded need to show up when the user comes back.
    if (state == AppLifecycleState.resumed) {
      setState(() => _refreshTick++);
    }
  }

  Future<void> _onRefresh() async {
    setState(() => _refreshTick++);
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.repository.stats();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Squat Reminder'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SettingsScreen(
                  notifications: widget.notifications,
                  settings: widget.settings,
                ),
              ));
              if (!mounted) return;
              setState(() => _refreshTick++);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        color: AppColors.accent,
        backgroundColor: AppColors.surface,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.7,
              children: [
                StatTile(label: 'Today', value: stats.today),
                StatTile(label: 'This week', value: stats.week),
                StatTile(label: 'This month (30d)', value: stats.month),
                StatTile(label: 'All time', value: stats.allTime),
              ],
            ),
            const SizedBox(height: 14),
            TrendChart(
              key: ValueKey('trend-$_refreshTick'),
              repository: widget.repository,
            ),
            const SizedBox(height: 14),
            HeatmapCard(
              key: ValueKey('heatmap-$_refreshTick'),
              repository: widget.repository,
            ),
          ],
        ),
      ),
    );
  }
}
