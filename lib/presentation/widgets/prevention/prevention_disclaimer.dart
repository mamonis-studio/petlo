// ============================================================================
// petlo - Prevention Disclaimer
// ============================================================================
//
// 医療免責の表示 (§9)。**常設・折りたたみ不可**。
//
// petlo は記録・リマインダーアプリであり、獣医療の指示を行うものではない。
// この表示は省略できない。App Store 審査でも指摘されうる箇所。
//
// 使い分け:
//   period  … コース作成の地域選択直下 / コース詳細の最下部
//   test    … コース作成の検査セクション直下
//   general … 設定 > このアプリについて
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../l10n/generated/app_localizations.dart';

enum PreventionDisclaimerKind { period, test, general }

class PreventionDisclaimer extends StatelessWidget {
  const PreventionDisclaimer(this.kind, {super.key});

  final PreventionDisclaimerKind kind;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    final String text = switch (kind) {
      PreventionDisclaimerKind.period => l10n.prevention_disclaimer_period,
      PreventionDisclaimerKind.test => l10n.prevention_disclaimer_test,
      PreventionDisclaimerKind.general => l10n.prevention_disclaimer_general,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimensions.paddingCompact),
      decoration: BoxDecoration(
        color: colors.bgSoft,
        border: Border(
          left: BorderSide(color: colors.line, width: AppDimensions.strokeAccent),
        ),
      ),
      child: Text(
        text,
        style: typo.bodySmall.copyWith(color: colors.fgMuted, height: 1.6),
      ),
    );
  }
}
