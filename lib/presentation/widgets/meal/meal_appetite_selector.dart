// ============================================================================
// petlo - MealAppetiteSelector
// ============================================================================
//
// rev3 F-01: 食いつき5段階セレクター。
//
// 5段階 (MealAppetite enum):
//   ate_all     完食 (全部食べた)
//   ate_well    よく食べた (8割以上)
//   ate_normal  普通 (半分くらい)
//   left_some   残した (少し)
//   refused     ほぼ食べず
//
// デザイン (絵文字を使わずSVG的に表現):
//   - 5つのドット円が並ぶ
//   - 完食: 5つすべて塗り
//   - よく食べ: 4つ塗り
//   - 普通: 3つ塗り
//   - 残した: 2つ塗り
//   - ほぼ食べず: 1つ塗り
//
//   選択中はドットが大きく+黒、ラベルが太字に。
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../data/local/database_enums.dart';

class MealAppetiteSelector extends StatelessWidget {
  const MealAppetiteSelector({
    required this.value,
    required this.onChanged,
    this.label,
    this.required = false,
    this.errorText,
    super.key,
  });

  final MealAppetite? value;
  final ValueChanged<MealAppetite> onChanged;
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
            EyebrowText(label ?? l10n.record_field_appetite),
            if (required) ...<Widget>[
              const SizedBox(width: 4),
              Text(
                '*',
                style: TextStyle(
                  color: colors.accentDanger,
                  fontFamily: 'JetBrainsMono',
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppDimensions.gapMedium),

        Row(
          children: <Widget>[
            for (final MealAppetite a in MealAppetite.values)
              Expanded(
                child: _AppetiteOption(
                  appetite: a,
                  isSelected: value == a,
                  onTap: () => onChanged(a),
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

class _AppetiteOption extends StatelessWidget {
  const _AppetiteOption({
    required this.appetite,
    required this.isSelected,
    required this.onTap,
  });

  final MealAppetite appetite;
  final bool isSelected;
  final VoidCallback onTap;

  /// このappetiteで塗るドット数 (1〜5)
  int get _filledDots {
    switch (appetite) {
      case MealAppetite.ate_all:
        return 5;
      case MealAppetite.ate_well:
        return 4;
      case MealAppetite.ate_normal:
        return 3;
      case MealAppetite.left_some:
        return 2;
      case MealAppetite.refused:
        return 1;
    }
  }

  /// 表示ラベル
  String _label(AppLocalizations l10n) {
    switch (appetite) {
      case MealAppetite.ate_all:
        return l10n.meal_appetite_excellent;
      case MealAppetite.ate_well:
        return l10n.meal_appetite_good;
      case MealAppetite.ate_normal:
        return l10n.meal_appetite_normal;
      case MealAppetite.left_some:
        return l10n.meal_appetite_poor;
      case MealAppetite.refused:
        return l10n.meal_appetite_none;
    }
  }

  /// セマンティクス用説明
  String _semanticLabel(AppLocalizations l10n) {
    final String name = _label(l10n);
    final int n = _filledDots;
    return '$name, $n of 5';
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
              // 5つのドット
              SizedBox(
                height: 14,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    for (int i = 0; i < 5; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: _Dot(
                          filled: i < _filledDots,
                          inverted: isSelected,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // ラベル
              Text(
                _label(l10n),
                style: typo.bodySmall.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
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

class _Dot extends StatelessWidget {
  const _Dot({required this.filled, required this.inverted});

  final bool filled;

  /// 親が選択中(黒背景)の時、ドットの色を反転する
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Color foreground = inverted ? colors.bg : colors.fg;

    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? foreground : Colors.transparent,
        border: filled ? null : Border.all(color: foreground, width: 1),
      ),
    );
  }
}
