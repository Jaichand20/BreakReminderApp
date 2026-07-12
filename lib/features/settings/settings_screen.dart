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
  static const List<String> _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  bool _loading = true;
  bool _paused = false;
  int _intervalMinutes = SettingsRepository.defaultIntervalMinutes;
  Set<int> _activeDays = SettingsRepository.defaultActiveDays.toSet();
  int _startMinutes = SettingsRepository.defaultStartMinutes;
  int _endMinutes = SettingsRepository.defaultEndMinutes;
  String? _testStatus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final paused = await widget.settings.isPaused();
    final interval = await widget.settings.intervalMinutes();
    final days = await widget.settings.activeDays();
    final start = await widget.settings.startMinutes();
    final end = await widget.settings.endMinutes();
    if (!mounted) return;
    setState(() {
      _paused = paused;
      _intervalMinutes = interval;
      _activeDays = days;
      _startMinutes = start;
      _endMinutes = end;
      _loading = false;
    });
  }

  Future<void> _applySchedule() async {
    if (_paused) {
      await widget.notifications.cancelChain();
    } else {
      await widget.notifications
          .rescheduleChain(await widget.settings.schedule(), DateTime.now());
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
    await _applySchedule();
  }

  Future<void> _toggleDay(int day) async {
    final next = Set<int>.from(_activeDays);
    if (!next.remove(day)) next.add(day);
    setState(() => _activeDays = next);
    await widget.settings.setActiveDays(next);
    await _applySchedule();
  }

  String _formatMinutes(int minutes) {
    final hour24 = minutes ~/ 60;
    final minute = minutes % 60;
    final period = hour24 < 12 ? 'AM' : 'PM';
    var hour12 = hour24 % 12;
    if (hour12 == 0) hour12 = 12;
    return '$hour12:${minute.toString().padLeft(2, '0')} $period';
  }

  Future<void> _pickTime({required bool isStart}) async {
    final current = isStart ? _startMinutes : _endMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null || !mounted) return;
    final minutes = picked.hour * 60 + picked.minute;

    final start = isStart ? minutes : _startMinutes;
    final end = isStart ? _endMinutes : minutes;
    if (end <= start) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start time must be before end time')),
      );
      return;
    }

    if (isStart) {
      setState(() => _startMinutes = minutes);
      await widget.settings.setStartMinutes(minutes);
    } else {
      setState(() => _endMinutes = minutes);
      await widget.settings.setEndMinutes(minutes);
    }
    await _applySchedule();
  }

  Future<void> _sendTest() async {
    await widget.notifications.sendTestReminder();
    setState(() =>
        _testStatus = 'Test reminder sent — check your notification shade.');
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
                        activeColor: AppColors.accent,
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
                  ],
                ),
                const SizedBox(height: 14),
                _SettingsCard(
                  children: [
                    const Text('Active days',
                        style: TextStyle(
                            fontSize: 14.5, color: AppColors.inkPrimary)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (var day = 1; day <= 7; day++)
                          _DayChip(
                            label: _dayLabels[day - 1],
                            selected: _activeDays.contains(day),
                            onTap: () => _toggleDay(day),
                          ),
                      ],
                    ),
                    if (_activeDays.isEmpty) ...[
                      const SizedBox(height: 10),
                      const Text(
                        "No days selected — reminders won't fire.",
                        style: TextStyle(
                            fontSize: 12.5, color: AppColors.inkMuted),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                _SettingsCard(
                  children: [
                    const Text('Active hours',
                        style: TextStyle(
                            fontSize: 14.5, color: AppColors.inkPrimary)),
                    const SizedBox(height: 8),
                    _TimeRow(
                      label: 'Start',
                      valueLabel: _formatMinutes(_startMinutes),
                      onTap: () => _pickTime(isStart: true),
                    ),
                    const Divider(height: 20, color: AppColors.border),
                    _TimeRow(
                      label: 'End',
                      valueLabel: _formatMinutes(_endMinutes),
                      onTap: () => _pickTime(isStart: false),
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
                    'Xiaomi, Huawei, Samsung, OnePlus) need Break Reminder '
                    'excluded from battery optimization: Settings → Apps → '
                    'Break Reminder → Battery → Unrestricted.',
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
              width: 64,
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

class _DayChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DayChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surface2,
          shape: BoxShape.circle,
          border: selected ? null : Border.all(color: AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.inkSecondary,
          ),
        ),
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  final String label;
  final String valueLabel;
  final VoidCallback onTap;

  const _TimeRow({
    required this.label,
    required this.valueLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 14.5, color: AppColors.inkSecondary)),
            Row(
              children: [
                Text(valueLabel,
                    style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkPrimary)),
                const SizedBox(width: 6),
                const Icon(Icons.edit_outlined,
                    size: 16, color: AppColors.inkMuted),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
