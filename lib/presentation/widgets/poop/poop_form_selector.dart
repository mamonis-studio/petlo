// ============================================================================
// petlo - PoopFormSelector
// ============================================================================
//
// rev3 F-02: ブリストル5段階形状セレクター。
//
// 5段階 (PoopForm enum):
//   hard    硬い小球
//   lumpy   ゴツゴツ
//   normal  正常 ← 推奨表示
//   soft    やや軟らかい
//   watery  水様
//
// デザイン:
//   横並び5択。各セルは絵文字ではなく Custom 図像で形状を抽象表現。
//   選択中: 黒塗り反転、ラベル太字。
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../data/local/database_enums.dart';

class PoopFormSelector extends StatelessWidget {
  const PoopFormSelector({
    required this.value,
    required this.onChanged,
    this.label,
    this.required = false,
    this.errorText,
    super.key,
  });

  final PoopForm? value;
  final ValueChanged<PoopForm> onChanged;
  final String? label;
  final bool required;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool hasError = errorText != null && errorText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            EyebrowText(label ?? l10n.record_field_form),
            if (required) ...<Widget>[
              const SizedBox(width: 4),
              Text('*',
                  style: TextStyle(
                    color: colors.accentDanger,
                    fontFamily: 'JetBrainsMono',
                    fontSize: 10,
                  )),
            ],
          ],
        ),
        const SizedBox(height: AppDimensions.gapMedium),
        Row(
          children: <Widget>[
            for (final PoopForm f in PoopForm.values)
              Expanded(
                child: _PoopFormOption(
                  form: f,
                  isSelected: value == f,
                  onTap: () => onChanged(f),
                ),
              ),
          ],
        ),
        if (hasError) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: typo.bodySmall.copyWith(color: colors.accentDanger),
          ),
        ],
      ],
    );
  }
}

class _PoopFormOption extends StatelessWidget {
  const _PoopFormOption({
    required this.form,
    required this.isSelected,
    required this.onTap,
  });

  final PoopForm form;
  final bool isSelected;
  final VoidCallback onTap;

  String _label(AppLocalizations l10n) {
    switch (form) {
      case PoopForm.hard:
        return l10n.poop_form_hard;
      case PoopForm.lumpy:
        return l10n.poop_form_lumpy;
      case PoopForm.normal:
        return l10n.poop_form_normal;
      case PoopForm.soft:
        return l10n.poop_form_soft;
      case PoopForm.watery:
        return l10n.poop_form_watery;
    }
  }

  String _semanticLabel(AppLocalizations l10n) {
    final int idx = PoopForm.values.indexOf(form) + 1;
    return '${_label(l10n)}, $idx of 5';
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Semantics(
      label: _semanticLabel(l10n),
      selected: isSelected,
      button: true,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: colors.bgSoft,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? colors.fg : colors.bg,
            border: Border.all(color: colors.fg, width: 1),
          ),
          child: Column(
            children: <Widget>[
              SizedBox(
                width: 28,
                height: 28,
                child: CustomPaint(
                  painter: _PoopFormPainter(
                    form: form,
                    color: isSelected ? colors.bg : colors.fg,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _label(l10n),
                style: typo.bodySmall.copyWith(
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? colors.bg : colors.fg,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// うんち形状を抽象的に描画 (絵文字なし)
class _PoopFormPainter extends CustomPainter {
  _PoopFormPainter({required this.form, required this.color});

  final PoopForm form;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    final Paint fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final double cx = size.width / 2;
    final double cy = size.height / 2;

    switch (form) {
      case PoopForm.hard:
        // 小さな点3つ
        canvas.drawCircle(Offset(cx - 6, cy), 2.5, fill);
        canvas.drawCircle(Offset(cx + 1, cy - 2), 2.5, fill);
        canvas.drawCircle(Offset(cx + 6, cy + 2), 2.5, fill);

      case PoopForm.lumpy:
        // 連結したゴツゴツ
        canvas.drawCircle(Offset(cx - 5, cy), 3.5, fill);
        canvas.drawCircle(Offset(cx + 1, cy - 1), 3.5, fill);
        canvas.drawCircle(Offset(cx + 7, cy + 2), 3.0, fill);

      case PoopForm.normal:
        // 滑らかな楕円(理想形)
        canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, cy), width: 18, height: 9),
          fill,
        );

      case PoopForm.soft:
        // やや崩れた波線形状
        final Path p = Path()
          ..moveTo(cx - 9, cy)
          ..quadraticBezierTo(cx - 5, cy - 5, cx, cy)
          ..quadraticBezierTo(cx + 5, cy + 5, cx + 9, cy);
        canvas.drawPath(p, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(cx - 9, cy + 4)
            ..quadraticBezierTo(cx - 5, cy + 9, cx, cy + 4)
            ..quadraticBezierTo(cx + 5, cy - 1, cx + 9, cy + 4),
          stroke,
        );

      case PoopForm.watery:
        // 水滴3つ(液状を表現)
        for (int i = -1; i <= 1; i++) {
          final Path drop = Path()
            ..moveTo(cx + i * 8, cy - 6)
            ..quadraticBezierTo(
                cx + i * 8 - 3, cy + 2, cx + i * 8, cy + 5)
            ..quadraticBezierTo(
                cx + i * 8 + 3, cy + 2, cx + i * 8, cy - 6);
          canvas.drawPath(drop, fill);
        }
    }
  }

  @override
  bool shouldRepaint(covariant _PoopFormPainter old) =>
      old.form != form || old.color != color;
}
