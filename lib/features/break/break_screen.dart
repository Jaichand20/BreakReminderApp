import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/db/break_repository.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/settings/settings_repository.dart';
import '../../theme.dart';

class BreakScreen extends StatefulWidget {
  final BreakRepository repository;
  final NotificationService notifications;
  final SettingsRepository settings;

  const BreakScreen({
    super.key,
    required this.repository,
    required this.notifications,
    required this.settings,
  });

  @override
  State<BreakScreen> createState() => _BreakScreenState();
}

class _BreakScreenState extends State<BreakScreen> {
  DateTime? _start;
  Timer? _ticker;
  bool _ending = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    var start = await widget.settings.activeBreakStart();
    if (start == null) {
      start = DateTime.now();
      await widget.settings.setActiveBreakStart(start);
    }
    if (!mounted) return;
    setState(() => _start = start);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatElapsed(Duration elapsed) {
    final totalSeconds = elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$mm:$ss';
    return '$mm:$ss';
  }

  Future<void> _endBreak() async {
    final start = _start;
    if (start == null || _ending) return;
    setState(() => _ending = true);

    final end = DateTime.now();
    widget.repository.logBreak(start, end);
    await widget.settings.setActiveBreakStart(null);
    if (!await widget.settings.isPaused()) {
      // Re-anchor the cycle: the next reminder lands one interval after the
      // break ended.
      await widget.notifications
          .rescheduleChain(await widget.settings.schedule(), end);
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final start = _start;
    return Scaffold(
      appBar: AppBar(title: const Text('Break')),
      body: start == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent))
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _formatElapsed(DateTime.now().difference(start)),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 64,
                            fontWeight: FontWeight.w700,
                            color: AppColors.inkPrimary,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Break in progress — it keeps running if you '
                          'leave this screen.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13, color: AppColors.inkSecondary),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _ending ? null : _endBreak,
                    child: const Text('End break',
                        style: TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
    );
  }
}
