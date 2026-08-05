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
        //
        // build 73: crossAxisAlignment を stretch にする。
        //
        // 既定の center だと、長いラベルの子だけ 2 行に折り返して背が高くなり、
        // 他のセグメントは元の高さのまま **中央に浮く**。
        // 結果として隣り合う矩形の上下の罫線が繋がらず、
        // 「一続きのセグメントコントロール」という見た目が崩れる。
        // (実測: 高さが [50, 70, 50] になる)
        //
        // stretch にすると全セグメントが最も高い子に揃うので、
        // 箱は縦に伸びるが破綻はしない。伸びる量は _Segment 側の
        // maxLines で頭打ちにしてある。
        //
        // ja のラベルは短いので通常は 1 行に収まり、見た目は変わらない。
        //
        // IntrinsicHeight が要るのは、Column の中の Row は高さが非拘束だから。
        // stretch だけ付けると子に無限の高さ制約が渡って
        // `BoxConstraints forces an infinite height` で落ちる。
        // IntrinsicHeight が「最も背の高い子」を測って Row の高さを確定させる。
        // 選択肢は 2〜5 個なので測り直しのコストは問題にならない。
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < options.length; i++)
                Expanded(
                  child: _Segment<T>(
                    label:
                        optionLabel?.call(options[i]) ?? options[i].toString(),
                    isSelected: value == options[i],
                    showLeftBorder: i == 0,
                    onTap: () => onChanged(options[i]),
                  ),
                ),
            ],
          ),
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
            // build 73: 伸びしろに上限を設ける。
            //
            // Row + Expanded は全選択肢を必ず 1 行に詰めるので、
            // セグメント 1 個あたりの幅は「親の幅 ÷ 選択肢数」で決まる。
            // 長い訳語や Dynamic Type の拡大で、ここに収まらない量の
            // テキストが来たときに際限なく縦へ伸びるのを防ぐ。
            //
            // 既定の clip ではなく ellipsis にするのは、切り詰められたことが
            // ユーザーに見えるようにするため。clip だと「…」も出ずに黙って
            // 切り落とされ、切れたこと自体が伝わらない。
            //
            // 3 行以上必要になるほど長いラベルを 1 行に並べる設計自体が
            // 無理なので、その場合は SegmentedSelector ではなく
            // ChoiceChips を使うこと (下の doc コメント参照)。
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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
