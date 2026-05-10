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

class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    this.padding = const EdgeInsets.fromLTRB(
      AppDimensions.paddingPage,
      28,
      AppDimensions.paddingPage,
      16,
    ),
    super.key,
  });

  final String text;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

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
              fontSize: 14,
              color: colors.fgMuted,
            ),
          ),
          const SizedBox(width: AppDimensions.gapMedium),
          // ラベル本文
          Text(
            text.toUpperCase(),
            style: typo.sectionTitle,
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
