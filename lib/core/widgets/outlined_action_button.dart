// ============================================================================
// petlo - OutlinedActionButton
// ============================================================================
//
// 線画スタイルのセカンダリーボタン。
// 黒い枠 + 内側はbg色、ホバーで反転(bgとfgが入れ替わる)。
//
// モックの `.share-btn` `.memorial-cta` 相当。
//
// ============================================================================

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_typography.dart';

class OutlinedActionButton extends StatefulWidget {
  const OutlinedActionButton({
    required this.label,
    required this.onPressed,
    this.subLabel,
    this.expand = true,
    this.semanticHint,
    super.key,
  });

  final String label;

  /// オプションでラベル下に小さなサブテキスト (例: "PRO · OPTIONAL")
  final String? subLabel;

  final VoidCallback? onPressed;
  final bool expand;
  final String? semanticHint;

  @override
  State<OutlinedActionButton> createState() => _OutlinedActionButtonState();
}

class _OutlinedActionButtonState extends State<OutlinedActionButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final bool isEnabled = widget.onPressed != null;

    final Color bgColor = _isPressed ? colors.fg : colors.bg;
    final Color fgColor = _isPressed ? colors.bg : colors.fg;

    final Widget button = Semantics(
      button: true,
      enabled: isEnabled,
      label: widget.label,
      hint: widget.semanticHint,
      child: Material(
        color: bgColor,
        child: InkWell(
          onTap: widget.onPressed,
          onHighlightChanged: (bool pressed) {
            setState(() => _isPressed = pressed);
          },
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(
              vertical: AppDimensions.paddingRow,
              horizontal: AppDimensions.paddingPage,
            ),
            constraints: const BoxConstraints(
              minHeight: AppDimensions.minTapTarget,
            ),
            decoration: BoxDecoration(
              border: Border.all(
                color: isEnabled ? colors.fg : colors.fgFaint,
                width: AppDimensions.strokeLine,
              ),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  widget.label,
                  style: typo.button.copyWith(color: fgColor),
                  textAlign: TextAlign.center,
                ),
                if (widget.subLabel != null) ...<Widget>[
                  const SizedBox(height: AppDimensions.gapTight),
                  Text(
                    widget.subLabel!,
                    style: typo.metaSmall.copyWith(color: fgColor.withValues(alpha: 0.6)),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.expand) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}
