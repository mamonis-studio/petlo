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

    final double labelSize = switch (size) {
      EyebrowSize.small => 10,
      EyebrowSize.medium => 12,
      EyebrowSize.large => 14,
    };
    // § マーク自体も labelSize に合わせて少し大きく
    final double markSize = labelSize + 4;

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
              letterSpacing: labelSize * 0.2,
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
