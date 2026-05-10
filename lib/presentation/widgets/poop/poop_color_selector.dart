// ============================================================================
// petlo - PoopColorSelector
// ============================================================================
//
// rev3 F-02: うんちの5色セレクター。
//
// 5色 (PoopColor enum):
//   brown   茶 (正常)
//   black   黒 (至急)
//   red     赤 (至急)
//   yellow  黄 (注意)
//   pale    薄い (注意)
//
// rev5 アクセシビリティ: 色だけに頼らず、ラベル文字 + 緊急度マーク併記。
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../data/local/database_enums.dart';

class PoopColorSelector extends StatelessWidget {
  const PoopColorSelector({
    required this.value,
    required this.onChanged,
    this.label,
    this.required = false,
    this.errorText,
    super.key,
  });

  final PoopColor? value;
  final ValueChanged<PoopColor> onChanged;
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
            EyebrowText(label ?? l10n.record_field_color),
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
            for (final PoopColor c in PoopColor.values)
              Expanded(
                child: _ColorOption(
                  color: c,
                  isSelected: value == c,
                  onTap: () => onChanged(c),
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

class _ColorOption extends StatelessWidget {
  const _ColorOption({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final PoopColor color;
  final bool isSelected;
  final VoidCallback onTap;

  String _label(AppLocalizations l10n) {
    switch (color) {
      case PoopColor.brown:
        return l10n.poop_color_brown;
      case PoopColor.black:
        return l10n.poop_color_black;
      case PoopColor.red:
        return l10n.poop_color_red;
      case PoopColor.yellow:
        return l10n.poop_color_yellow;
      case PoopColor.pale:
        return l10n.poop_color_pale;
    }
  }

  /// 緊急度: black/red は至急、yellow/pale は注意、brown は正常
  _Urgency get _urgency {
    switch (color) {
      case PoopColor.brown:
        return _Urgency.normal;
      case PoopColor.black:
      case PoopColor.red:
        return _Urgency.urgent;
      case PoopColor.yellow:
      case PoopColor.pale:
        return _Urgency.caution;
    }
  }

  Color _swatchColor() {
    // 図像の色は実際の見た目に近いが、petloのトーンに合わせて落ち着いた色味で
    switch (color) {
      case PoopColor.brown:
        return const Color(0xFF6B4423);
      case PoopColor.black:
        return const Color(0xFF1A1A1A);
      case PoopColor.red:
        return const Color(0xFF9B2A2A);
      case PoopColor.yellow:
        return const Color(0xFFB89A2E);
      case PoopColor.pale:
        return const Color(0xFFD9CFB8);
    }
  }

  String _semanticLabel(AppLocalizations l10n) {
    final String name = _label(l10n);
    switch (_urgency) {
      case _Urgency.normal:
        return '$name, normal';
      case _Urgency.caution:
        return '$name, caution';
      case _Urgency.urgent:
        return '$name, URGENT — consider seeing a vet';
    }
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
              // 色サンプル(円)+ 緊急マーク重ね
              SizedBox(
                width: 28,
                height: 22,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _swatchColor(),
                        border: Border.all(
                          color: isSelected ? colors.bg : colors.fgMuted,
                          width: 1,
                        ),
                      ),
                    ),
                    if (_urgency == _Urgency.urgent)
                      Positioned(
                        top: 0,
                        right: 4,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: colors.accentDanger,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? colors.bg : colors.fg,
                              width: 1,
                            ),
                          ),
                        ),
                      )
                    else if (_urgency == _Urgency.caution)
                      Positioned(
                        top: 0,
                        right: 4,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: colors.accentWarn,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
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

enum _Urgency { normal, caution, urgent }
