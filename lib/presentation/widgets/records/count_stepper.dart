// ============================================================================
// petlo - CountStepper
// ============================================================================
//
// 回数を +/- で増減する共通部品。
// 用途: おしっこ回数、嘔吐回数 (1日にまとめて記録するケース)
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';

class CountStepper extends StatelessWidget {
  const CountStepper({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 10,
    this.unitText,
    super.key,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final String? unitText;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    final bool canDec = value > min;
    final bool canInc = value < max;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        EyebrowText(label),
        const SizedBox(height: AppDimensions.gapSmall),
        Row(
          children: <Widget>[
            _StepButton(
              icon: Icons.remove,
              enabled: canDec,
              onTap: () => onChanged(value - 1),
            ),
            const SizedBox(width: AppDimensions.gapMedium),
            Container(
              width: 64,
              alignment: Alignment.center,
              child: Text(
                '$value${unitText ?? ""}',
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontStyle: FontStyle.italic,
                  fontSize: 28,
                  height: 1.0,
                  color: colors.fg,
                  fontFeatures: <FontFeature>[
                    const FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppDimensions.gapMedium),
            _StepButton(
              icon: Icons.add,
              enabled: canInc,
              onTap: () => onChanged(value + 1),
            ),
            const SizedBox(width: AppDimensions.gapLarge),
            Text(
              '$min – $max',
              style: typo.metaSmall,
            ),
          ],
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Semantics(
      button: true,
      enabled: enabled,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(
              color: enabled ? colors.fg : colors.fgFaint,
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: enabled ? colors.fg : colors.fgFaint,
          ),
        ),
      ),
    );
  }
}
