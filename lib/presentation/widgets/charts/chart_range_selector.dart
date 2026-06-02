// ============================================================================
// petlo - ChartRangeSelector
// ============================================================================
//
// 期間切替トグル(1M / 3M / 6M / 1Y / ALL)。
//
// rev5: 無料は3Mまで、それ以上は ProロックUI(灰色 + 鍵アイコン)。
// (現状は実際のロックは効かせず、視覚的なヒントのみ)
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/chart_range.dart';
import '../../screens/paywall/paywall_screen.dart';

class ChartRangeSelector extends StatelessWidget {
  const ChartRangeSelector({
    required this.current,
    required this.onChanged,
    this.isProUser = false,
    super.key,
  });

  final ChartRange current;
  final ValueChanged<ChartRange> onChanged;
  final bool isProUser;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    return Row(
      children: <Widget>[
        for (final ChartRange r in ChartRange.values)
          Expanded(
            child: _RangeButton(
              range: r,
              isSelected: current == r,
              isLocked: !isProUser && !r.isFreeAllowed,
              onTap: () {
                if (!isProUser && !r.isFreeAllowed) {
                  // build 71: ロックされた期間タップ → SnackBar + 「Proを見る」
                  // アクションで Paywall に誘導。
                  final AppLocalizations l10n =
                      AppLocalizations.of(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n.chart_range_pro_only),
                      behavior: SnackBarBehavior.floating,
                      action: SnackBarAction(
                        label: l10n.chart_range_pro_only_action,
                        onPressed: () => PaywallScreen.push(context),
                      ),
                    ),
                  );
                  return;
                }
                onChanged(r);
              },
              colors: colors,
            ),
          ),
      ],
    );
  }
}

class _RangeButton extends StatelessWidget {
  const _RangeButton({
    required this.range,
    required this.isSelected,
    required this.isLocked,
    required this.onTap,
    required this.colors,
  });

  final ChartRange range;
  final bool isSelected;
  final bool isLocked;
  final VoidCallback onTap;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final Color bg =
        isSelected ? colors.fg : colors.bg;
    final Color fg = isSelected
        ? colors.bg
        : (isLocked ? colors.fgFaint : colors.fg);

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${range.label}${isLocked ? ", Pro only" : ""}',
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: colors.fg, width: 1),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (isLocked) ...<Widget>[
                Icon(Icons.lock_outline, size: 11, color: fg),
                const SizedBox(width: 3),
              ],
              Text(
                range.label,
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 10,
                  letterSpacing: 10 * 0.18,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
