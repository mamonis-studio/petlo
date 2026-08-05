// ============================================================================
// petlo - SectionLabel
// ============================================================================
//
// "§ Quick · Log" のような § マーク + 罫線付きの見出し。
// モックの `.section-label` クラス相当。
//
// 構造:
//   [§] [Quick · Log] ━━━━━━━━━━━
//
// ============================================================================

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_typography.dart';
import 'eyebrow_text.dart';

class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    this.size = EyebrowSize.small,
    this.padding = const EdgeInsets.fromLTRB(
      AppDimensions.paddingPage,
      28,
      AppDimensions.paddingPage,
      16,
    ),
    super.key,
  });

  final String text;

  /// build 16: 各タブのトップ § を large、サブセクション § を medium、
  /// それ以外を small (既存) に揃えるための size 切替。
  final EyebrowSize size;

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    // build 17: large=22pt+w700 / medium=13pt / small=10pt
    final double labelSize = switch (size) {
      EyebrowSize.small => 10,
      EyebrowSize.medium => 13,
      EyebrowSize.large => 22,
    };
    final FontWeight labelWeight = switch (size) {
      EyebrowSize.large => FontWeight.w700,
      _ => FontWeight.w500,
    };
    // tracking は large でやや締める (caps が大きいと 0.2em だと開きすぎる)
    final double trackingFactor = switch (size) {
      EyebrowSize.large => 0.12,
      _ => 0.2,
    };
    // § マーク自体も labelSize に合わせて拡縮
    final double markSize = switch (size) {
      EyebrowSize.large => 28,
      EyebrowSize.medium => 17,
      EyebrowSize.small => 14,
    };

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // § マーク (Fraunces italic)
          Text(
            '§',
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: markSize,
              color: colors.fgMuted,
            ),
          ),
          const SizedBox(width: AppDimensions.gapMedium),
          // ラベル本文
          //
          // build 73: Flexible で包む。以前は素の Text だったため、
          // Dynamic Type を上げた端末 + 長い訳語で Row からはみ出し、
          // 見えない部分が黙って切り落とされていた
          // (デバッグビルドでは黄黒の縞が出る)。
          // 通常サイズでは幅に収まるので、見た目は従来どおり変わらない。
          Flexible(
            child: Text(
              text.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: typo.sectionTitle.copyWith(
                fontSize: labelSize,
                fontWeight: labelWeight,
                letterSpacing: labelSize * trackingFactor,
              ),
            ),
          ),
          const SizedBox(width: AppDimensions.gapMedium),
          // 右側の罫線(伸縮)
          //
          // build 73: ラベルが 2 行に折り返したとき、Row の既定
          // (crossAxisAlignment: center) では罫線が 2 行分の中央に来て
          // しまい、2 行目が線の下にはみ出して見えた。
          // 最終行のベースライン側に寄せる。1 行のときは中央と同じ位置に
          // なるので、既存の見た目は変わらない。
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: AppDimensions.strokeLine,
                color: colors.line,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
