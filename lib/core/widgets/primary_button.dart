// ============================================================================
// petlo - PrimaryButton
// ============================================================================
//
// 黒塗りの主要アクションボタン。
// 角丸ゼロ、影なし、tracked uppercase ラベル。
//
// モックの `.save-btn` `.generate-btn` 相当。
//
// ============================================================================

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_typography.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.expand = true,
    this.semanticHint,
    super.key,
  });

  final String label;

  /// nullの場合はdisabled状態(半透明)
  final VoidCallback? onPressed;

  /// trueなら横幅いっぱい、falseなら内容に合わせる
  final bool expand;

  /// VoiceOver用ヒント
  final String? semanticHint;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final bool isEnabled = onPressed != null;

    final Widget button = Semantics(
      button: true,
      enabled: isEnabled,
      label: label,
      hint: semanticHint,
      child: Material(
        color: isEnabled ? colors.fg : colors.fgFaint,
        child: InkWell(
          onTap: onPressed,
          highlightColor: Colors.white.withValues(alpha: 0.1),
          splashColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(
              vertical: AppDimensions.paddingRow,
              horizontal: AppDimensions.paddingPage,
            ),
            constraints: const BoxConstraints(
              minHeight: AppDimensions.minTapTarget,
            ),
            alignment: Alignment.center,
            child: Text(
              label.toUpperCase(),
              style: typo.button.copyWith(color: colors.bg),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );

    if (expand) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}
