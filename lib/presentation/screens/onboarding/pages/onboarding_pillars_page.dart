// ============================================================================
// petlo - Onboarding Pillars Page
// ============================================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/eyebrow_text.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../l10n/generated/app_localizations.dart';

class OnboardingPillarsPage extends StatelessWidget {
  const OnboardingPillarsPage({required this.onNext, super.key});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionLabel(
            l10n.onboarding_pillars_eyebrow,
            size: EyebrowSize.large,
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
          ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _PillarRow(
                  number: '01',
                  title: '体系的記録',
                  note: 'ごはん・うんち・体重などを毎日記録',
                ),
                _PillarRow(
                  number: '02',
                  title: 'AI相談',
                  note: 'うちの子の様子や写真をAIに相談',
                ),
                _PillarRow(
                  number: '03',
                  title: '家族共有',
                  note: '最大3グループ × 5人で一緒に見守る',
                ),
                _PillarRow(
                  number: '04',
                  title: 'お別れの後も',
                  note: '月命日通知や思い出として残す',
                ),
                _PillarRow(
                  number: '05',
                  title: '長期で見える',
                  note: '体重・体温の推移、通院記録、日記',
                  isLast: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _PrimaryCta(
            label: l10n.common_continue,
            onTap: onNext,
            colors: colors,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// _PillarRow
// ============================================================================
class _PillarRow extends StatelessWidget {
  const _PillarRow({
    required this.number,
    required this.title,
    required this.note,
    this.isLast = false,
  });

  final String number;
  final String title;
  final String note;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(bottom: BorderSide(color: colors.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 32,
              child: Text(
                number,
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 10,
                  letterSpacing: 10 * 0.18,
                  color: colors.fgMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontStyle: FontStyle.italic,
                      fontSize: 18,
                      letterSpacing: -18 * 0.03,
                      height: 1.2,
                      color: colors.fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    note,
                    style: typo.bodySmall.copyWith(
                      color: colors.fgMuted,
                      height: 1.4,
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryCta extends StatelessWidget {
  const _PrimaryCta({
    required this.label,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final VoidCallback onTap;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.fg,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            color: colors.bg,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
