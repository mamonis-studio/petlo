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
          Text(
            text.toUpperCase(),
            style: typo.sectionTitle.copyWith(
              fontSize: labelSize,
              fontWeight: labelWeight,
              letterSpacing: labelSize * trackingFactor,
            ),
          ),
          const SizedBox(width: AppDimensions.gapMedium),
          // 右側の罫線(伸縮)
          Expanded(
            child: Container(
              height: AppDimensions.strokeLine,
              color: colors.line,
            ),
          ),
        ],
      ),
    );
  }
}
