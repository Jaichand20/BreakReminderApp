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
  bool _startingWork = false;
  DateTime? _nextBreakAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.notifications.takeBreakRequests.addListener(_onTakeBreakRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refreshNextBreak();
      final activeStart = await widget.settings.activeBreakStart();
      if (!mounted) return;
      if (widget.openBreakOnLaunch || activeStart != null) {
        // Either the app was launched from a reminder's "Take break"
        // action, or a break was in progress when the app was killed.
        await _openBreakScreen();
      }
    });
  }

  @override
  void dispose() {
    widget.notifications.takeBreakRequests
        .removeListener(_onTakeBreakRequest);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Skips logged from a notification action while the app was
    // backgrounded need to show up (and re-anchor the cycle) when the user
    // comes back.
    if (state == AppLifecycleState.resumed) {
      setState(() => _refreshTick++);
      _syncAndRefresh();
    }
  }

  Future<void> _syncAndRefresh() async {
    try {
      await widget.notifications
          .syncSchedule(widget.repository, widget.settings);
    } catch (e, st) {
      debugPrint('break_reminder: schedule sync failed: $e\n$st');
    }
    await _checkActiveBreak();
    await _refreshNextBreak();
  }

  void _onTakeBreakRequest() {
    _openBreakScreen();
  }

  /// Anchors the hourly cycle at now: the first break reminder buzzes one
  /// interval after this press.
  Future<void> _startWork() async {
    if (_startingWork) return;
    setState(() => _startingWork = true);
    try {
      // Starting work is an explicit "I want reminders" — it overrides pause.
      if (await widget.settings.isPaused()) {
        await widget.settings.setPaused(false);
      }
      await widget.notifications
          .restartCycle(widget.settings, DateTime.now());
      await _refreshNextBreak();
      if (!mounted) return;
      final next = _nextBreakAt;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(next == null
            ? 'Work started.'
            : 'Work started — break reminder at ${formatClock(next)}.'),
      ));
    } finally {
      if (mounted) setState(() => _startingWork = false);
    }
  }

  /// The next chain occurrence that is still in the future, for display.
  Future<void> _refreshNextBreak() async {
    DateTime? next;
    if (!await widget.settings.isPaused()) {
      final anchor = await widget.settings.lastAnchor();
      if (anchor != null) {
        final schedule = await widget.settings.schedule();
        final now = DateTime.now();
        for (final t in schedule.nextOccurrences(anchor)) {
          if (t.isAfter(now)) {
            next = t;
            break;
          }
        }
      }
    }
    if (!mounted) return;
    if (next != _nextBreakAt) setState(() => _nextBreakAt = next);
  }

  Future<void> _openBreakScreen() async {
    if (_breakScreenOpen || !mounted) return;
    _breakScreenOpen = true;
    setState(() => _breakInProgress = false);
    try {
      // Stop a buzzing reminder and silence the chain for the duration of
      // the break; End break reschedules it.
      await widget.notifications.cancelAllReminders();
    } catch (e, st) {
      debugPrint('break_reminder: failed to cancel reminders: $e\n$st');
    }
    if (!mounted) {
      _breakScreenOpen = false;
      return;
    }
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
    await _refreshNextBreak();
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
    await _refreshNextBreak();
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
              if (!mounted) return;
              setState(() => _refreshTick++);
              await _refreshNextBreak();
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
                onPressed: _startingWork ? null : _startWork,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 24),
                label: const Text(
                  'Start work',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _nextBreakAt != null
                    ? 'Next break at ${formatClock(_nextBreakAt!)}'
                    : 'Press Start work to begin the hourly break cycle.',
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.inkSecondary),
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
          color: AppColors.accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.45)),
        ),
        child: const Row(
          children: [
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
