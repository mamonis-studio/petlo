// ============================================================================
// petlo - Onboarding Welcome Page
// ============================================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/eyebrow_text.dart';
import '../../../../l10n/generated/app_localizations.dart';

class OnboardingWelcomePage extends StatelessWidget {
  const OnboardingWelcomePage({required this.onNext, super.key});

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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              EyebrowText(l10n.onboarding_welcome_eyebrow),
              const SizedBox(height: 8),
              // ヒーロー: petlo. (英字維持)
              Text('petlo.', style: typo.heroName),
              const SizedBox(height: 24),
              // 各行を FittedBox(scaleDown) で包み、狭幅端末でも 1 行に収める
              // (line1/line2 はロケールごとに l10n から取得、行数を変えない)
              _HeroLine(text: l10n.onboarding_welcome_hero_line1, colors: colors),
              _HeroLine(text: l10n.onboarding_welcome_hero_line2, colors: colors),
              const SizedBox(height: 16),
              Text(
                l10n.onboarding_welcome_body,
                style: typo.bodyMedium.copyWith(
                  color: colors.fgMuted,
                  height: 1.5,
                ),
              ),
            ],
          ),
          _PrimaryCta(
            label: l10n.onboarding_welcome_cta,
            onTap: onNext,
            colors: colors,
          ),
        ],
      ),
    );
  }
}

class _HeroLine extends StatelessWidget {
  const _HeroLine({required this.text, required this.colors});

  final String text;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FittedBox(
        alignment: Alignment.centerLeft,
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(
            fontFamily: 'Fraunces',
            fontStyle: FontStyle.italic,
            fontSize: 22,
            letterSpacing: -22 * 0.03,
            height: 1.3,
            color: colors.fg,
          ),
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
