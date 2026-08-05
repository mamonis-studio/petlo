// ============================================================================
// petlo - Prevention Progress Bar
// ============================================================================
//
// 予防コースの進捗 (投与済み / 全回数) を 1 本のバーで示す。
//
// 色だけに依存しない (既存の色覚配慮方針)。バーの塗り分けに加えて
// "3 / 8 回" のテキストを必ず併記する。
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../l10n/generated/app_localizations.dart';

class PreventionProgressBar extends StatelessWidget {
  const PreventionProgressBar({
    required this.done,
    required this.total,
    this.trailing,
    super.key,
  });

  /// 投与済みの回数
  final int done;

  /// シーズン全体の回数
  final int total;

  /// 右端に添える補足 (次回予定日など)
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool complete = total > 0 && done >= total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                complete
                    ? l10n.prevention_season_complete
                    : l10n.prevention_progress_label(done, total),
                style: typo.metaSmall.copyWith(color: colors.fg),
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: typo.metaSmall.copyWith(color: colors.fgMuted),
              ),
          ],
        ),
        const SizedBox(height: AppDimensions.gapSmall),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double ratio =
                total <= 0 ? 0 : (done / total).clamp(0.0, 1.0);
            return Stack(
              children: <Widget>[
                Container(
                  height: 4,
                  width: constraints.maxWidth,
                  color: colors.line,
                ),
                Container(
                  height: 4,
                  width: constraints.maxWidth * ratio,
                  color: colors.fg,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
