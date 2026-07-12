import 'package:flutter/material.dart';

import '../../core/notifications/notification_service.dart';
import '../../core/settings/settings_repository.dart';
import '../../theme.dart';

class SettingsScreen extends StatefulWidget {
  final NotificationService notifications;
  final SettingsRepository settings;

  const SettingsScreen({
    super.key,
    required this.notifications,
    required this.settings,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  bool _paused = false;
  int _intervalMinutes = SettingsRepository.defaultIntervalMinutes;
  int _squatsPerReminder = SettingsRepository.defaultSquatsPerReminder;
  String? _testStatus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final paused = await widget.settings.isPaused();
    final interval = await widget.settings.intervalMinutes();
    final squats = await widget.settings.squatsPerReminder();
    if (!mounted) return;
    setState(() {
      _paused = paused;
      _intervalMinutes = interval;
      _squatsPerReminder = squats;
      _loading = false;
    });
  }

  Future<void> _applySchedule() async {
    try {
      if (_paused) {
        await widget.notifications.cancelReminders();
      } else {
        await widget.notifications.scheduleReminders(
          intervalMinutes: _intervalMinutes,
          squatsPerReminder: _squatsPerReminder,
        );
      }
    } catch (e) {
      // Settings are already persisted; main() re-applies the schedule on
      // next launch, so a transient plugin failure here is recoverable.
      debugPrint('squat_reminder: applying reminder schedule failed: $e');
    }
  }

  Future<void> _togglePaused(bool value) async {
    setState(() => _paused = value);
    await widget.settings.setPaused(value);
    await _applySchedule();
  }

  Future<void> _changeInterval(int delta) async {
    final next = (_intervalMinutes + delta).clamp(5, 24 * 60);
    setState(() => _intervalMinutes = next);
    await widget.settings.setIntervalMinutes(next);
    if (!_paused) await _applySchedule();
  }

  Future<void> _changeSquats(int delta) async {
    final next = (_squatsPerReminder + delta).clamp(1, 100);
    setState(() => _squatsPerReminder = next);
    await widget.settings.setSquatsPerReminder(next);
    if (!_paused) await _applySchedule();
  }

  Future<void> _sendTest() async {
    String status;
    try {
      await widget.notifications.sendTestReminder(_squatsPerReminder);
      status = 'Test reminder sent — check your notification shade.';
    } catch (e) {
      status = 'Could not send the test reminder — check that notifications '
          'are allowed for Squat Reminder.';
      debugPrint('squat_reminder: test reminder failed: $e');
    }
    if (!mounted) return;
    setState(() => _testStatus = status);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SettingsCard(
                  children: [
                    _Row(
                      label: _paused ? 'Reminders paused' : 'Reminders active',
                      trailing: Switch(
                        value: !_paused,
                        activeThumbColor: AppColors.accent,
                        onChanged: (v) => _togglePaused(!v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SettingsCard(
                  children: [
                    _StepperRow(
                      label: 'Reminder interval',
                      valueLabel: '$_intervalMinutes min',
                      onDecrement: () => _changeInterval(-5),
                      onIncrement: () => _changeInterval(5),
                    ),
                    const Divider(height: 24, color: AppColors.border),
                    _StepperRow(
                      label: 'Squats per reminder',
                      valueLabel: '$_squatsPerReminder',
                      onDecrement: () => _changeSquats(-5),
                      onIncrement: () => _changeSquats(5),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SettingsCard(
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _sendTest,
                      child: const Text('Send test reminder now'),
                    ),
                    if (_testStatus != null) ...[
                      const SizedBox(height: 10),
                      Text(_testStatus!,
                          style: const TextStyle(
                              fontSize: 12.5, color: AppColors.inkSecondary)),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'For the most reliable delivery, some phones (especially '
                    'Xiaomi, Huawei, Samsung, OnePlus) need Squat Reminder '
                    'excluded from battery optimization: Settings → Apps → '
                    'Squat Reminder → Battery → Unrestricted.',
                    style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final Widget trailing;

  const _Row({required this.label, required this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 14.5, color: AppColors.inkPrimary)),
        trailing,
      ],
    );
  }
}

class _StepperRow extends StatelessWidget {
  final String label;
  final String valueLabel;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _StepperRow({
    required this.label,
    required this.valueLabel,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 14.5, color: AppColors.inkPrimary)),
        Row(
          children: [
            _StepButton(icon: Icons.remove, onTap: onDecrement),
            SizedBox(
              width: 56,
              child: Text(valueLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkPrimary)),
            ),
            _StepButton(icon: Icons.add, onTap: onIncrement),
          ],
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _StepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: AppColors.inkSecondary),
      ),
    );
  }
}
