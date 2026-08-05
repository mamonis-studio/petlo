// ============================================================================
// petlo - Prevention Month Grid
// ============================================================================
//
// 予防コースのシーズンを月マスで並べる (§8.2)。
//
//    5月 ✓   6月 ✓   7月 ✓   8月 ●
//    9月 ○  10月 ○  11月 ○  12月 ○ ←最終回
//
// 状態表示は **色だけに依存しない**。必ず記号を併記する:
//   投与済み        ✓ + 塗りつぶし
//   今日が予定日    ● + 太枠
//   予定日超過・未投与 ! + 太枠 (既存の urgent 表現に揃える)
//   未来            ○ + 細枠
//   スキップ        – + グレー
//
// 絵文字は使わない。記号はいずれもテキストグリフ。
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/prevention/prevention_labels.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../../data/repositories/prevention_doses_repository.dart';
import '../../../l10n/generated/app_localizations.dart';

class PreventionMonthGrid extends StatelessWidget {
  const PreventionMonthGrid({
    required this.doses,
    required this.onDoseTapped,
    super.key,
  });

  final List<PreventionDoseEntity> doses;
  final ValueChanged<PreventionDoseEntity> onDoseTapped;

  @override
  Widget build(BuildContext context) {
    if (doses.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: AppDimensions.gapSmall,
      runSpacing: AppDimensions.gapSmall,
      children: <Widget>[
        for (final PreventionDoseEntity d in doses)
          _MonthCell(dose: d, onTap: () => onDoseTapped(d)),
      ],
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({required this.dose, required this.onTap});

  final PreventionDoseEntity dose;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String localeTag = Localizations.localeOf(context).toLanguageTag();

    final PreventionDoseStatus status =
        PreventionDosesRepository.statusOf(dose);
    final DateTime scheduled =
        DateTime.fromMillisecondsSinceEpoch(dose.scheduledDate);
    final _CellStyle style = _styleFor(status, colors);

    return Semantics(
      button: true,
      label: '${PreventionLabels.monthLabel(scheduled.month, localeTag)} '
          '${PreventionLabels.doseStatus(status, l10n)}',
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 72,
          padding: const EdgeInsets.symmetric(
            vertical: AppDimensions.paddingTight,
            horizontal: AppDimensions.gapSmall,
          ),
          decoration: BoxDecoration(
            color: style.fill,
            border: Border.all(color: style.border, width: style.borderWidth),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    _monthText(scheduled.month, localeTag, l10n),
                    style: typo.metaSmall.copyWith(color: style.foreground),
                  ),
                  Text(
                    style.symbol,
                    style: typo.metaSmall.copyWith(
                      color: style.foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (dose.isFinal) ...<Widget>[
                const SizedBox(height: AppDimensions.gapTight),
                Text(
                  l10n.prevention_final_badge,
                  style: typo.metaSmall.copyWith(
                    color: style.foreground,
                    fontSize: 8,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// ja / zh は "5月"、en は "May"。
  String _monthText(int month, String localeTag, AppLocalizations l10n) {
    return l10n.prevention_dose_sheet_title(
      PreventionLabels.monthLabel(month, localeTag),
    );
  }
}

class _CellStyle {
  const _CellStyle({
    required this.symbol,
    required this.foreground,
    required this.border,
    required this.borderWidth,
    this.fill,
  });

  final String symbol;
  final Color foreground;
  final Color border;
  final double borderWidth;
  final Color? fill;
}

_CellStyle _styleFor(PreventionDoseStatus status, AppColors colors) {
  switch (status) {
    case PreventionDoseStatus.administered:
      return _CellStyle(
        symbol: '✓',
        foreground: colors.bg,
        border: colors.fg,
        borderWidth: AppDimensions.strokeLine,
        fill: colors.fg,
      );
    case PreventionDoseStatus.due:
      return _CellStyle(
        symbol: '●',
        foreground: colors.fg,
        border: colors.fg,
        borderWidth: AppDimensions.strokeAccent,
      );
    case PreventionDoseStatus.overdue:
      return _CellStyle(
        symbol: '!',
        foreground: colors.accentDanger,
        border: colors.accentDanger,
        borderWidth: AppDimensions.strokeAccent,
      );
    case PreventionDoseStatus.skipped:
      return _CellStyle(
        symbol: '–',
        foreground: colors.fgFaint,
        border: colors.line,
        borderWidth: AppDimensions.strokeLine,
      );
    case PreventionDoseStatus.upcoming:
      return _CellStyle(
        symbol: '○',
        foreground: colors.fgMuted,
        border: colors.line,
        borderWidth: AppDimensions.strokeLine,
      );
  }
}
