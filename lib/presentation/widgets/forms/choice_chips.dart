// ============================================================================
// petlo - ChoiceChips
// ============================================================================
//
// Wrap ベースの択一セレクタ。
//
// SegmentedSelector との使い分け:
//
//   SegmentedSelector — 全選択肢を必ず 1 行に等幅で並べる。
//     一続きの矩形として見せたい 2〜3 択向け (犬/猫、オス/メス/不明)。
//     ラベルが短いことが前提。長いと 1 個あたりの幅が足りなくなり、
//     縦に伸びるか省略される。
//
//   ChoiceChips (これ) — 入らなければ次の行へ送る。
//     ラベルの長さが読めない、あるいは翻訳で伸びる可能性がある選択肢向け。
//     予防コースの「ノミ・マダニ予防」/「Flea & tick prevention」が実例。
//
// 迷ったらこちらを使う。SegmentedSelector は「1 行に収まると分かっている」
// ときだけの選択肢。
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';

// 共有の SegmentedSelector は Row + Expanded で全選択肢を必ず 1 行に詰める。
// 「ノミ・マダニ予防」「Flea & tick prevention」のような長いラベルが入ると
// その子だけ 2 行に折り返して箱が縦に膨らみ、左右の要素へ食い込む。
//
// ここでは地域チップと同じ Wrap 方式に統一する:
//   - 1 行に詰め込まず、入らなければ次の行へ送る
//   - 各チップのラベルは 1 行固定 (maxLines: 1 / softWrap: false)。
//     これで全チップの高さが揃う。通常の文字サイズではチップ幅がテキスト幅に
//     追従するので切り詰めも起きない
//   - 選択中は塗りつぶし + 文字反転、未選択は枠線のみ。見た目は現行を維持
//
// 安全網 (build 73):
//   Wrap は「入らないチップを次の行へ送る」ことはできるが、チップ 1 個が
//   親の幅を超えた場合は送り先が無い。Dynamic Type を大きくした端末で
//   長い訳語 ("Flea & tick prevention" 等) を出すと現実に起こりうる。
//   そこで
//     - 各チップに親の利用可能幅を上限として与える
//     - あふれたら ellipsis で丸める (既定の clip だと「…」も出ずに
//       黙って切り落とされ、ユーザーは切れたことに気づけない)
//   通常サイズでは上限に当たらないので、従来どおり省略は発生しない。
//
class ChoiceChips<T> extends StatelessWidget {
  const ChoiceChips({
    required this.label,
    required this.options,
    required this.value,
    required this.optionLabel,
    required this.onChanged,
    this.required = false,
    this.errorText,
    super.key,
  });

  final String label;
  final List<T> options;
  final T? value;
  final String Function(T) optionLabel;
  final ValueChanged<T> onChanged;
  final bool required;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final bool hasError = errorText != null && errorText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
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
        // 親の利用可能幅を測り、各チップの上限として渡す。
        // これが無いと、チップ 1 個が幅を超えたときに Wrap が逃がせない。
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double maxChipWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : double.infinity;
            return Wrap(
              spacing: AppDimensions.gapSmall,
              runSpacing: AppDimensions.gapSmall,
              children: <Widget>[
                for (final T o in options)
                  _ChoiceChip(
                    label: optionLabel(o),
                    isSelected: o == value,
                    maxWidth: maxChipWidth,
                    onTap: () => onChanged(o),
                  ),
              ],
            );
          },
        ),
        if (hasError) ...<Widget>[
          const SizedBox(height: AppDimensions.gapTight),
          Text(
            errorText!,
            style: typo.bodySmall.copyWith(color: colors.accentDanger),
          ),
        ],
      ],
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.isSelected,
    required this.maxWidth,
    required this.onTap,
  });

  final String label;
  final bool isSelected;

  /// 親の利用可能幅。チップはこれを超えて広がらない。
  final double maxWidth;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    return Semantics(
      button: true,
      selected: isSelected,
      // 見た目が省略されても読み上げは全文にする
      label: label,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.paddingCompact,
              vertical: AppDimensions.paddingTight,
            ),
            decoration: BoxDecoration(
              color: isSelected ? colors.fg : null,
              border: Border.all(
                color: isSelected ? colors.fg : colors.line,
                width: AppDimensions.strokeLine,
              ),
            ),
            child: Text(
              label,
              // 1 行固定。折り返させないことで全チップの高さが揃う。
              // 通常サイズではチップ幅がテキストに追従するため省略されない。
              maxLines: 1,
              softWrap: false,
              // 最後の安全網。既定の clip だと「…」も出ずに黙って
              // 切り落とされ、切れたこと自体が伝わらない。
              overflow: TextOverflow.ellipsis,
              style: typo.bodySmall.copyWith(
                color: isSelected ? colors.bg : colors.fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

