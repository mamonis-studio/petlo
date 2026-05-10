// ============================================================================
// petlo - EditorialDivider
// ============================================================================
//
// 雑誌風の罫線。Material標準のDividerより細く、上下マージンなし。
//
// 種類:
//   - EditorialDivider() — 横一本線(全幅)
//   - EditorialDivider.vertical() — 縦線
//
// ============================================================================

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

class EditorialDivider extends StatelessWidget {
  const EditorialDivider({
    this.color,
    this.thickness = AppDimensions.strokeLine,
    this.indent = 0,
    this.endIndent = 0,
    super.key,
  }) : _vertical = false;

  /// 縦線版
  const EditorialDivider.vertical({
    this.color,
    this.thickness = AppDimensions.strokeLine,
    this.indent = 0,
    this.endIndent = 0,
    super.key,
  }) : _vertical = true;

  final Color? color;
  final double thickness;
  final double indent;
  final double endIndent;
  final bool _vertical;

  @override
  Widget build(BuildContext context) {
    final Color resolvedColor = color ?? AppColors.of(context).line;

    if (_vertical) {
      return Container(
        width: thickness,
        margin: EdgeInsets.only(top: indent, bottom: endIndent),
        color: resolvedColor,
      );
    }

    return Container(
      height: thickness,
      margin: EdgeInsets.only(left: indent, right: endIndent),
      color: resolvedColor,
    );
  }
}
