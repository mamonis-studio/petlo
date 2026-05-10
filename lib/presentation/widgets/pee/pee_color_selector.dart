// ============================================================================
// petlo - PeeColorSelector
// ============================================================================
//
// rev3 F-03: おしっこの6色セレクター。
//
// 6色 (PeeColor enum):
//   pale_yellow  薄い黄色 (薄すぎ→水分過多/腎臓注意)
//   yellow       黄色 (正常)
//   dark_yellow  濃い黄色 (脱水気味)
//   amber        濃褐色 (脱水・要注意)
//   red          赤・血尿 (至急)
//   cloudy       濁り (要注意)
//
// 6個は1行に収まりにくいので、2行 × 3列で表示。
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../data/local/database_enums.dart';

class PeeColorSelector extends StatelessWidget {
  const PeeColorSelector({
    required this.value,
    required this.onChanged,
    this.label,
    this.required = false,
    this.errorText,
    super.key,
  });

  final PeeColor? value;
  final ValueChanged<PeeColor> onChanged;
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
        // 2行×3列のグリッド
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 0,
          crossAxisSpacing: 0,
          childAspectRatio: 2.0,
          children: <Widget>[
            for (final PeeColor c in PeeColor.values)
              _PeeColorOption(
                color: c,
                isSelected: value == c,
                onTap: () => onChanged(c),
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

class _PeeColorOption extends StatelessWidget {
  const _PeeColorOption({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final PeeColor color;
  final bool isSelected;
  final VoidCallback onTap;

  String _label(AppLocalizations l10n) {
    switch (color) {
      case PeeColor.pale_yellow:
        return l10n.pee_color_pale;
      case PeeColor.yellow:
        return l10n.pee_color_yellow;
      case PeeColor.dark_yellow:
        return l10n.pee_color_dark;
      case PeeColor.amber:
        return l10n.pee_color_amber;
      case PeeColor.red:
        return l10n.pee_color_red;
      case PeeColor.cloudy:
        return l10n.pee_color_cloudy;
    }
  }

  Color _swatchColor() {
    switch (color) {
      case PeeColor.pale_yellow:
        return const Color(0xFFFAF1B8);
      case PeeColor.yellow:
        return const Color(0xFFE5C547);
      case PeeColor.dark_yellow:
        return const Color(0xFFB89A2E);
      case PeeColor.amber:
        return const Color(0xFF8B5A1F);
      case PeeColor.red:
        return const Color(0xFF9B2A2A);
      case PeeColor.cloudy:
        return const Color(0xFFE8E5DC);
    }
  }

  _Urgency get _urgency {
    switch (color) {
      case PeeColor.yellow:
        return _Urgency.normal;
      case PeeColor.pale_yellow:
      case PeeColor.dark_yellow:
      case PeeColor.cloudy:
        return _Urgency.caution;
      case PeeColor.amber:
      case PeeColor.red:
        return _Urgency.urgent;
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
        return '$name, URGENT — see a vet soon';
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
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? colors.fg : colors.bg,
            border: Border.all(color: colors.fg, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 22,
                height: 22,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Container(
                      width: 16,
                      height: 16,
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
                        right: 2,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: colors.accentDanger,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? colors.bg : colors.fg,
                              width: 0.8,
                            ),
                          ),
                        ),
                      )
                    else if (_urgency == _Urgency.caution)
                      Positioned(
                        top: 0,
                        right: 2,
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: colors.accentWarn,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _label(l10n),
                  style: typo.bodySmall.copyWith(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? colors.bg : colors.fg,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Urgency { normal, caution, urgent }
