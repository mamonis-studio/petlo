// ============================================================================
// petlo - Tap Target
// ============================================================================
//
// アクセシビリティ要件: タップ可能要素の最小サイズは 48x48dp。
// 視覚的には小さく見せたい場合でも、タップ判定領域は 48dp 確保する。
//
// 使い方:
// ```dart
// TapTarget(
//   onTap: () { ... },
//   child: SizedBox(
//     width: 24,
//     height: 24,
//     child: SomeIcon(),  // 視覚的には24x24でも、タップ範囲は48x48
//   ),
// )
// ```
//
// ============================================================================

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

class TapTarget extends StatelessWidget {
  const TapTarget({
    required this.child,
    required this.onTap,
    this.semanticLabel,
    this.minSize = AppDimensions.minTapTarget,
    this.enableHaptic = true,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final double minSize;
  final bool enableHaptic;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    return Semantics(
      label: semanticLabel,
      button: true,
      enabled: onTap != null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  if (enableHaptic) {
                    Feedback.forTap(context);
                  }
                  onTap!();
                },
          highlightColor: colors.bgSoft,
          splashColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: minSize,
              minHeight: minSize,
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
