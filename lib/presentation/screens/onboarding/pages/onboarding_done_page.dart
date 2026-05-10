// ============================================================================
// petlo - Onboarding Done Page
// ============================================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/eyebrow_text.dart';
import '../../../../l10n/generated/app_localizations.dart';

class OnboardingDonePage extends StatelessWidget {
  const OnboardingDonePage({required this.onFinish, super.key});

  final VoidCallback onFinish;

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
              EyebrowText(l10n.onboarding_done_eyebrow),
              const SizedBox(height: 8),
              // ヒーロー (英字維持)
              Text('All\nset.', style: typo.heroName),
              const SizedBox(height: 24),
              Text(
                l10n.onboarding_done_body,
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontStyle: FontStyle.italic,
                  fontSize: 20,
                  letterSpacing: -20 * 0.03,
                  height: 1.4,
                  color: colors.fg,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.onboarding_done_helper,
                style: typo.bodyMedium
                    .copyWith(color: colors.fgMuted, height: 1.5),
              ),
            ],
          ),
          _PrimaryCta(
            label: l10n.onboarding_done_cta,
            onTap: onFinish,
            colors: colors,
          ),
        ],
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
