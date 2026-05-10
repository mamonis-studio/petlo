// ============================================================================
// petlo - SegmentedSelector
// ============================================================================
//
// 2〜4択の択一セレクター。
// 例: 犬/猫、男/女/不明、5段階のブリストルスケール
//
// デザイン:
//   - 横並びの矩形セグメント
//   - 角丸ゼロ、罫線で区切る
//   - 選択中: 黒塗り、文字白
//   - 非選択: bg、文字fg、外枠 line
//
// ジェネリックで型安全 (T extends enum 等)
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';

class SegmentedSelector<T> extends StatelessWidget {
  const SegmentedSelector({
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.required = false,
    this.errorText,
    this.optionLabel,
    super.key,
  });

  final String label;

  /// 選択肢のリスト
  final List<T> options;

  /// 現在の選択値
  final T? value;

  /// 値変更時のコールバック
  final ValueChanged<T> onChanged;

  /// "*" を表示するか
  final bool required;

  final String? errorText;

  /// 各値の表示ラベルを返す関数 (省略時は toString())
  final String Function(T)? optionLabel;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final bool hasError = errorText != null && errorText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Label
        Row(
          children: <Widget>[
            EyebrowText(label),
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

        // Segments
        // 隣接セグメントの罫線重ねは、最初のセグメント以外の left border を
        // 抑制することで実現(右隣の right border が境界線として共有される)。
        // 以前は外側 Container に負 margin (-1) を入れていたが、Flutter の
        // Container.margin.isNonNegative assert に違反するため、設計的に正しい
        // shared-border 構造へ変更した。
        Row(
          children: <Widget>[
            for (int i = 0; i < options.length; i++)
              Expanded(
                child: _Segment<T>(
                  label: optionLabel?.call(options[i]) ?? options[i].toString(),
                  isSelected: value == options[i],
                  showLeftBorder: i == 0,
                  onTap: () => onChanged(options[i]),
                ),
              ),
          ],
        ),

        // Error text
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

class _Segment<T> extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.showLeftBorder = true,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  /// `false` のとき left border を `BorderSide.none` にすることで、
  /// 左隣のセグメントの right border と境界線を共有する。
  /// (selected セグメントは塗りつぶしのため left border の有無は視覚に出ない)
  final bool showLeftBorder;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    final BorderSide side = BorderSide(color: colors.fg, width: 1);

    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: colors.bgSoft,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? colors.fg : colors.bg,
            border: Border(
              top: side,
              right: side,
              bottom: side,
              left: showLeftBorder ? side : BorderSide.none,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: typo.bodyMedium.copyWith(
              color: isSelected ? colors.bg : colors.fg,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
