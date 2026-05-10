// ============================================================================
// petlo - Calendar Header
// ============================================================================
//
// table_calendar の標準ヘッダーは Material風で petlo らしくないので、
// 自前のエディトリアルヘッダーを使う。
//
// 構成:
//   < (前月) | YYYY MONTH (Fraunces) | (次月) >
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/generated/app_localizations.dart';

class CalendarHeader extends StatelessWidget {
  const CalendarHeader({
    required this.focusedMonth,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    super.key,
  });

  final DateTime focusedMonth;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  bool get _isCurrentMonth {
    final DateTime now = DateTime.now();
    return now.year == focusedMonth.year &&
        now.month == focusedMonth.month;
  }

  String _monthLabel(BuildContext context) {
    final String locale = Localizations.localeOf(context).languageCode;
    if (locale == 'ja' || locale == 'zh') {
      return '${focusedMonth.month}月';
    }
    return DateFormat.MMMM(locale).format(focusedMonth);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 年(JetBrainsMono)
          Row(
            children: <Widget>[
              Text(
                '${focusedMonth.year}',
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 10,
                  letterSpacing: 10 * 0.18,
                  color: colors.fgMuted,
                ),
              ),
              const Spacer(),
              if (!_isCurrentMonth)
                InkWell(
                  onTap: onToday,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.fgMuted, width: 1),
                    ),
                    child: Text(
                      l10n.record_today_label,
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.fg,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // 月名 + 矢印
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Text(
                  _monthLabel(context),
                  style: TextStyle(
                    fontFamily: 'Fraunces',
                    fontStyle: FontStyle.italic,
                    fontSize: 36,
                    height: 1.0,
                    letterSpacing: -36 * 0.04,
                    color: colors.fg,
                  ),
                ),
              ),
              _ArrowButton(
                semanticLabel: 'Previous month',
                onTap: onPrev,
                child: _Arrow(direction: AxisDirection.left, color: colors.fg),
              ),
              const SizedBox(width: 4),
              _ArrowButton(
                semanticLabel: 'Next month',
                onTap: onNext,
                child: _Arrow(direction: AxisDirection.right, color: colors.fg),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.semanticLabel,
    required this.onTap,
    required this.child,
  });

  final String semanticLabel;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: colors.fg, width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.direction, required this.color});

  final AxisDirection direction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: CustomPaint(
        painter: _ArrowPainter(direction: direction, color: color),
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter({required this.direction, required this.color});

  final AxisDirection direction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final double w = size.width;
    final double h = size.height;
    final Path p = Path();

    if (direction == AxisDirection.left) {
      p
        ..moveTo(w * 0.65, h * 0.2)
        ..lineTo(w * 0.35, h * 0.5)
        ..lineTo(w * 0.65, h * 0.8);
    } else {
      p
        ..moveTo(w * 0.35, h * 0.2)
        ..lineTo(w * 0.65, h * 0.5)
        ..lineTo(w * 0.35, h * 0.8);
    }
    canvas.drawPath(p, stroke);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter old) =>
      old.direction != direction || old.color != color;
}
