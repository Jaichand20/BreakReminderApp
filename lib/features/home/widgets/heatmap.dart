import 'package:flutter/material.dart';

import '../../../core/db/squat_repository.dart';
import '../../../theme.dart';

const _monthAbbr = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _p2(int n) => n.toString().padLeft(2, '0');
String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_p2(d.month)}-${_p2(d.day)}';
bool _isLeapYear(int y) => (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;

int _levelFor(int value) {
  if (value == 0) return 0;
  final level = (value / 25).ceil();
  return level > 4 ? 4 : level;
}

class HeatmapCard extends StatefulWidget {
  final SquatRepository repository;

  const HeatmapCard({super.key, required this.repository});

  @override
  State<HeatmapCard> createState() => _HeatmapCardState();
}

class _HeatmapCardState extends State<HeatmapCard> {
  late int _year;
  DateTime? _selectedDay;
  int? _selectedValue;

  @override
  void initState() {
    super.initState();
    _year = DateTime.now().year;
  }

  void _changeYear(int delta) {
    final next = _year + delta;
    if (next > DateTime.now().year) return;
    setState(() {
      _year = next;
      _selectedDay = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final totals = widget.repository.yearDailyTotals(_year);
    final streak = widget.repository.currentStreak();
    final best = widget.repository.bestDay();
    final yearTotal = totals.values.fold<int>(0, (a, b) => a + b);
    final dayCount = _isLeapYear(_year) ? 366 : 365;
    final columns = (dayCount / 7).ceil();

    // cell[col][row] -> DateTime for that day, or null if out of range.
    final grid = List.generate(columns, (_) => List<DateTime?>.filled(7, null));
    final monthLabels = <String>[];
    var lastMonth = -1;
    for (var i = 0; i < dayCount; i++) {
      // Constructor arithmetic (not Duration) so DST days can't skip/repeat.
      final d = DateTime(_year, 1, 1 + i);
      final col = i ~/ 7;
      final row = d.weekday - 1; // Monday=0 .. Sunday=6
      grid[col][row] = d;
      if (d.month != lastMonth) {
        lastMonth = d.month;
        monthLabels.add(_monthAbbr[d.month - 1]);
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Year in squats',
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkPrimary)),
              Row(
                children: [
                  _YearNavButton(
                      icon: Icons.chevron_left,
                      onTap: () => _changeYear(-1)),
                  const SizedBox(width: 8),
                  Text('$_year',
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.inkSecondary)),
                  const SizedBox(width: 8),
                  _YearNavButton(
                      icon: Icons.chevron_right,
                      onTap: _year >= DateTime.now().year
                          ? null
                          : () => _changeYear(1)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: monthLabels
                      .map((m) => SizedBox(
                            width: 56,
                            child: Text(m,
                                style: const TextStyle(
                                    fontSize: 10.5,
                                    color: AppColors.inkMuted)),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 4),
                Row(
                  children: List.generate(columns, (col) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: Column(
                        children: List.generate(7, (row) {
                          final day = grid[col][row];
                          if (day == null) {
                            return const SizedBox(width: 11, height: 11);
                          }
                          final value = totals[_isoDate(day)] ?? 0;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _selectedDay = day;
                                _selectedValue = value;
                              }),
                              child: Container(
                                width: 11,
                                height: 11,
                                decoration: BoxDecoration(
                                  color: AppColors
                                      .heatLevels[_levelFor(value)],
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 16,
            child: Text(
              _selectedDay == null
                  ? ' '
                  : '${_monthAbbr[_selectedDay!.month - 1]} ${_selectedDay!.day} · $_selectedValue squats',
              style:
                  const TextStyle(fontSize: 11.5, color: AppColors.inkSecondary),
            ),
          ),
          Row(
            children: [
              const Text('Less',
                  style:
                      TextStyle(fontSize: 11, color: AppColors.inkMuted)),
              const SizedBox(width: 6),
              ...AppColors.heatLevels.map((c) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  )),
              const SizedBox(width: 2),
              const Text('More',
                  style:
                      TextStyle(fontSize: 11, color: AppColors.inkMuted)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                  child: _Callout(
                      label: 'Current streak',
                      value: streak == 1 ? '1 day' : '$streak days')),
              const SizedBox(width: 10),
              Expanded(
                  child: _Callout(
                      label: 'Best day',
                      value: best == null ? 'None yet' : '${best.count} squats')),
              const SizedBox(width: 10),
              Expanded(
                  child: _Callout(
                      label: 'Year total', value: '$yearTotal squats')),
            ],
          ),
        ],
      ),
    );
  }
}

class _YearNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _YearNavButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon,
            size: 14,
            color: enabled ? AppColors.inkSecondary : AppColors.inkMuted),
      ),
    );
  }
}

class _Callout extends StatelessWidget {
  final String label;
  final String value;

  const _Callout({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.inkSecondary)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkPrimary)),
        ],
      ),
    );
  }
}
