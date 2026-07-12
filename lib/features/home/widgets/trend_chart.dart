import 'package:flutter/material.dart';

import '../../../core/db/break_repository.dart';
import '../../../theme.dart';
import '../format.dart';

enum TrendMode { week, month, year }

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _monthAbbr = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _p2(int n) => n.toString().padLeft(2, '0');
String _p4(int n) => n.toString().padLeft(4, '0');
String _isoDate(DateTime d) => '${_p4(d.year)}-${_p2(d.month)}-${_p2(d.day)}';

/// Ported 1:1 from the original app's `_compute_trend`; values are now
/// minutes of break time instead of squat counts.
TrendResult computeTrend(BreakRepository repo, TrendMode mode, int offset) {
  final today = DateTime.now();

  if (mode == TrendMode.week) {
    final end = today.subtract(Duration(days: 7 * offset));
    final start = end.subtract(const Duration(days: 6));
    final dates =
        List.generate(7, (i) => _isoDate(start.add(Duration(days: i))));
    final label =
        '${_monthAbbr[start.month - 1]} ${start.day} – ${_monthAbbr[end.month - 1]} ${end.day}';
    final totals = repo.dailyMinutes(
        dates.first, _isoDate(end.add(const Duration(days: 1))));
    final values = dates.map((d) => totals[d] ?? 0).toList();
    return TrendResult(label: label, dates: dates, values: values);
  }

  if (mode == TrendMode.month) {
    final totalMonths = today.year * 12 + (today.month - 1) - offset;
    final m0 = totalMonths % 12;
    final y = (totalMonths - m0) ~/ 12;
    final m = m0 + 1;
    final daysInMonth = DateTime(y, m + 1, 0).day;
    final dates =
        List.generate(daysInMonth, (i) => '${_p4(y)}-${_p2(m)}-${_p2(i + 1)}');
    final label = '${_monthNames[m - 1]} $y';
    final nextMonthStart = _isoDate(
        DateTime(y, m, daysInMonth).add(const Duration(days: 1)));
    final totals = repo.dailyMinutes(dates.first, nextMonthStart);
    final values = dates.map((d) => totals[d] ?? 0).toList();
    return TrendResult(label: label, dates: dates, values: values);
  }

  final y = today.year - offset;
  final dates = List.generate(12, (i) => '${_p4(y)}-${_p2(i + 1)}');
  final values = repo.monthlyMinutes(y);
  return TrendResult(label: '$y', dates: dates, values: values);
}

class TrendChart extends StatefulWidget {
  final BreakRepository repository;

  const TrendChart({super.key, required this.repository});

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  TrendMode _mode = TrendMode.month;
  int _offset = 0;
  int? _selectedIndex;
  late TrendResult _data;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _data = computeTrend(widget.repository, _mode, _offset);
    _selectedIndex = null;
  }

  void _setMode(TrendMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _offset = 0;
      _reload();
    });
  }

  void _step(int delta) {
    final next = _offset + delta;
    if (next < 0) return;
    setState(() {
      _offset = next;
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCurrent = _offset == 0;
    final today = DateTime.now();
    int? highlightIndex;
    if (isCurrent) {
      if (_mode == TrendMode.year) {
        highlightIndex = today.month - 1;
      } else {
        highlightIndex = _data.values.length - 1;
      }
    }

    final selected = _selectedIndex;
    String? caption;
    if (selected != null) {
      final v = formatMinutes(_data.values[selected]);
      if (_mode == TrendMode.year) {
        caption = '${_monthNames[selected]} · $v';
      } else {
        final d = DateTime.parse(_data.dates[selected]);
        final isToday = isCurrent && selected == _data.values.length - 1;
        caption =
            '${isToday ? "Today" : "${_monthAbbr[d.month - 1]} ${d.day}"} · $v';
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
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
              const Text('Trend',
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkPrimary)),
              _ModeSegment(mode: _mode, onChanged: _setMode),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _NavButton(
                  icon: Icons.chevron_left, onTap: () => _step(1)),
              const SizedBox(width: 8),
              Text(_data.label,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.inkSecondary)),
              const SizedBox(width: 8),
              _NavButton(
                  icon: Icons.chevron_right,
                  onTap: isCurrent ? null : () => _step(-1)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 180,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onTapDown: (details) {
                    final index = _indexForTap(
                        details.localPosition.dx, constraints.maxWidth);
                    setState(() => _selectedIndex = index);
                  },
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, 180),
                    painter: _TrendPainter(
                      values: _data.values,
                      mode: _mode,
                      highlightIndex: highlightIndex,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 16,
            child: Text(
              caption ?? ' ',
              style: const TextStyle(
                  fontSize: 11.5, color: AppColors.inkSecondary),
            ),
          ),
        ],
      ),
    );
  }

  int _indexForTap(double dx, double width) {
    const padL = 8.0, padR = 8.0;
    final n = _data.values.length;
    if (_mode == TrendMode.year) {
      final slot = (width - padL - padR) / n;
      return ((dx - padL) / slot).floor().clamp(0, n - 1);
    }
    final xStep = (width - padL - padR) / ((n - 1 == 0) ? 1 : (n - 1));
    return (((dx - padL) / xStep).round()).clamp(0, n - 1);
  }
}

class _ModeSegment extends StatelessWidget {
  final TrendMode mode;
  final ValueChanged<TrendMode> onChanged;

  const _ModeSegment({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, TrendMode m) {
      final active = m == mode;
      return GestureDetector(
        onTap: () => onChanged(m),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: active ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : AppColors.inkSecondary,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          seg('Week', TrendMode.week),
          seg('Month', TrendMode.month),
          seg('Year', TrendMode.year),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _NavButton({required this.icon, required this.onTap});

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
            color:
                enabled ? AppColors.inkSecondary : AppColors.inkMuted),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<int> values;
  final TrendMode mode;
  final int? highlightIndex;

  _TrendPainter({
    required this.values,
    required this.mode,
    required this.highlightIndex,
  });

  static const padL = 8.0, padR = 8.0, padT = 18.0, padB = 20.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final n = values.length;
    final highestValue =
        values.isEmpty ? 0 : values.reduce((a, b) => a > b ? a : b);
    final maxVal = highestValue < 10 ? 10 : highestValue;

    final gridPaint = Paint()
      ..color = AppColors.gridLine
      ..strokeWidth = 1;
    for (var g = 0; g <= 3; g++) {
      final y = padT + (g / 3) * (h - padT - padB);
      canvas.drawLine(Offset(padL, y), Offset(w - padR, y), gridPaint);
    }

    if (n == 0) return;

    if (mode == TrendMode.year) {
      final slot = (w - padL - padR) / n;
      final barW = slot * 0.55;
      for (var i = 0; i < n; i++) {
        final v = values[i];
        final bh = (v / maxVal) * (h - padT - padB);
        final bx = padL + i * slot + (slot - barW) / 2;
        final by = h - padB - bh;
        final isHighlight = i == highlightIndex;
        final paint = Paint()
          ..color = isHighlight
              ? AppColors.accentLight
              : Colors.white.withOpacity(0.18);
        if (isHighlight) {
          final shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.accentLight, AppColors.accent],
          ).createShader(Rect.fromLTWH(bx, by, barW, bh < 2 ? 2 : bh));
          paint.shader = shader;
        }
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(bx, by, barW, bh < 2 ? 2 : bh),
          const Radius.circular(4),
        );
        canvas.drawRRect(rect, paint);
      }
      return;
    }

    final xStep = (w - padL - padR) / ((n - 1 == 0) ? 1 : (n - 1));
    double xFor(int i) => padL + i * xStep;
    double yFor(int v) => h - padB - (v / maxVal) * (h - padT - padB);

    final path = Path()..moveTo(xFor(0), yFor(values[0]));
    for (var i = 1; i < n; i++) {
      path.lineTo(xFor(i), yFor(values[i]));
    }

    final areaPath = Path.from(path)
      ..lineTo(xFor(n - 1), h - padB)
      ..lineTo(xFor(0), h - padB)
      ..close();
    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.accent.withOpacity(0.35),
          AppColors.accent.withOpacity(0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(areaPath, areaPaint);

    final linePaint = Paint()
      ..color = AppColors.accentLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    for (var i = 0; i < n; i++) {
      final cx = xFor(i), cy = yFor(values[i]);
      final isLast = i == highlightIndex;
      canvas.drawCircle(
        Offset(cx, cy),
        isLast ? 4.5 : 2.4,
        Paint()
          ..color = (isLast ? AppColors.accentLight : AppColors.inkSecondary)
              .withOpacity(isLast ? 1 : 0.55),
      );
    }

    if (highlightIndex != null) {
      final v = values[highlightIndex!];
      final tp = TextPainter(
        text: TextSpan(
          text: formatMinutes(v),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.inkPrimary,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = xFor(n - 1) - tp.width;
      final y = yFor(values[n - 1]) - 12 - tp.height;
      tp.paint(canvas, Offset(x, y));
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.mode != mode ||
        oldDelegate.highlightIndex != highlightIndex;
  }
}
