import 'package:flutter/material.dart';

import '../../core/db/break_repository.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/settings/settings_repository.dart';
import '../../theme.dart';
import '../break/break_screen.dart';
import '../settings/settings_screen.dart';
import 'format.dart';
import 'widgets/heatmap.dart';
import 'widgets/stat_tile.dart';
import 'widgets/trend_chart.dart';

class HomeScreen extends StatefulWidget {
  final BreakRepository repository;
  final NotificationService notifications;
  final SettingsRepository settings;
  final bool openBreakOnLaunch;

  const HomeScreen({
    super.key,
    required this.repository,
    required this.notifications,
    required this.settings,
    required this.openBreakOnLaunch,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _refreshTick = 0;
  bool _breakScreenOpen = false;
  bool _breakInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.notifications.startBreakRequests.addListener(_onStartBreakRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final activeStart = await widget.settings.activeBreakStart();
      if (!mounted) return;
      if (widget.openBreakOnLaunch || activeStart != null) {
        // Either the app was launched from a reminder's "Start break"
        // action, or a break was in progress when the app was killed.
        await _openBreakScreen();
      }
    });
  }

  @override
  void dispose() {
    widget.notifications.startBreakRequests
        .removeListener(_onStartBreakRequest);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Skips logged from a notification action while the app was
    // backgrounded need to show up when the user comes back.
    if (state == AppLifecycleState.resumed) {
      setState(() => _refreshTick++);
      _checkActiveBreak();
    }
  }

  void _onStartBreakRequest() {
    _openBreakScreen();
  }

  Future<void> _openBreakScreen() async {
    if (_breakScreenOpen || !mounted) return;
    _breakScreenOpen = true;
    setState(() => _breakInProgress = false);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BreakScreen(
        repository: widget.repository,
        notifications: widget.notifications,
        settings: widget.settings,
      ),
    ));
    _breakScreenOpen = false;
    if (!mounted) return;
    setState(() => _refreshTick++);
    await _checkActiveBreak();
  }

  /// A break can still be "in progress" while the user is on the home
  /// screen if they backed out of the break screen without ending it.
  Future<void> _checkActiveBreak() async {
    final activeStart = await widget.settings.activeBreakStart();
    if (!mounted) return;
    final inProgress = activeStart != null && !_breakScreenOpen;
    if (inProgress != _breakInProgress) {
      setState(() => _breakInProgress = inProgress);
    }
  }

  Future<void> _onRefresh() async {
    setState(() => _refreshTick++);
    await _checkActiveBreak();
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.repository.stats();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Break Reminder'),
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
            if (_breakInProgress) ...[
              _BreakInProgressBanner(onTap: _openBreakScreen),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _openBreakScreen,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.self_improvement, size: 22),
                label: const Text(
                  'Start break',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.7,
              children: [
                StatTile(
                    label: 'Breaks today', value: '${stats.todayCount}'),
                StatTile(
                    label: 'Time today',
                    value: formatMinutes(stats.todayMinutes)),
                StatTile(
                    label: 'Time this week',
                    value: formatMinutes(stats.weekMinutes)),
                StatTile(
                    label: 'Time all-time',
                    value: formatMinutes(stats.allTimeMinutes)),
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

class _BreakInProgressBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _BreakInProgressBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.accent.withOpacity(0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.accent.withOpacity(0.45)),
        ),
        child: Row(
          children: const [
            Icon(Icons.timer_outlined, size: 18, color: AppColors.accentLight),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Break in progress — tap to return',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkPrimary,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.inkSecondary),
          ],
        ),
      ),
    );
  }
}
