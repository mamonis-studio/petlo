// ============================================================================
// petlo - More Tab Screen
// ============================================================================
//
// 「その他」ハブ画面。build 4 で再構成。
// ホームに既存の Diary / Gallery セクションは削除。
// アカウント・設定・サポート・アプリについて・mamonis.studio の構成。
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/billing/pro_status.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/section_label.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/ai_service_provider.dart';
import '../../providers/pro_status_provider.dart';
import '../../providers/scope_providers.dart';
import '../../widgets/backup/backup_banner.dart';
import '../../widgets/petlo_scaffold.dart';
import '../ai_chat/ai_chat_screen.dart';
import '../backup/backup_settings_screen.dart';
import '../groups/groups_list_screen.dart';
import '../medication_reminder/medication_reminders_list_screen.dart';
import '../paywall/paywall_screen.dart';
import '../settings/settings_screen.dart';

class MoreTabScreen extends ConsumerWidget {
  const MoreTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTypography typo = AppTypography.of(context);
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? currentPetId = ref.watch(currentPetIdProvider);
    final bool hasPet = currentPetId != null && currentPetId != kAllPetsId;
    final bool canUseAi = ref.watch(canUseAiProvider);
    final bool isPro = ref.watch(isProProvider);

    final double bottomInset = MediaQuery.of(context).padding.bottom;
    return PetloScaffold(
      showTabBar: false,
      showPetSelector: false,
      showGroupSelector: false,
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          28,
          28,
          28,
          28 + bottomInset + kBottomNavigationBarHeight,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 12),
            EyebrowText(l10n.more_eyebrow),
            const SizedBox(height: 12),
            Text(
              'More.',
              style: typo.heroName.copyWith(height: 0.95),
            ),
            const SizedBox(height: 24),

            const BackupBanner(),

            // ===== Pro CTA バナー (無料時のみ) =====
            if (!isPro) ...<Widget>[
              const SizedBox(height: 16),
              _ProCtaBanner(colors: colors, typo: typo),
              const SizedBox(height: 24),
            ],

            // ===== アカウント =====
            _Row(
              title: l10n.other_account_guest_title,
              subtitle: l10n.other_account_guest_subtitle,
              onTap: null,
            ),
            _Row(
              title: l10n.more_item_backup,
              subtitle: l10n.more_trailing_open,
              onTap: () => BackupSettingsScreen.push(context),
            ),

            // ===== AI =====
            if (hasPet)
              _Row(
                title: l10n.more_item_pet_consult,
                subtitle: canUseAi ? null : l10n.ai_chat_offline,
                onTap: canUseAi ? () => AiChatScreen.push(context) : null,
              ),

            // ===== 家族 =====
            _Row(
              title: l10n.more_item_groups,
              onTap: () => GroupsListScreen.push(context),
            ),

            // ===== リマインダー =====
            _Row(
              title: l10n.more_item_medication_reminders,
              onTap: () => MedicationRemindersListScreen.push(context),
            ),

            // ===== 設定 =====
            _Row(
              title: l10n.other_item_settings,
              onTap: () => SettingsScreen.push(context),
            ),
            _Row(
              title: l10n.more_item_subscription,
              subtitle: const _SubscriptionStatus(),
              onTap: () => PaywallScreen.push(context),
            ),

            // ===== サポート =====
            _Row(
              title: l10n.other_item_contact,
              subtitle: AppConstants.contactEmail,
              onTap: () => _launchMail(context),
            ),

            // ===== アプリについて =====
            _Row(
              title: l10n.more_item_terms,
              onTap: () =>
                  _openExternalUrl(context, AppConstants.termsOfUseUrl),
            ),
            _Row(
              title: l10n.more_item_privacy,
              onTap: () =>
                  _openExternalUrl(context, AppConstants.privacyPolicyUrl),
            ),
            _Row(
              title: l10n.settings_item_version,
              subtitle:
                  '${AppConstants.appVersion} (build ${AppConstants.appBuildNumber})',
              onTap: null,
            ),

            // ===== mamonis.studio =====
            _Row(
              title: l10n.other_studio_x,
              onTap: () => _openExternalUrl(context, AppConstants.xUrl),
            ),
            _Row(
              title: l10n.other_studio_instagram,
              onTap: () =>
                  _openExternalUrl(context, AppConstants.instagramUrl),
            ),
            _Row(
              title: l10n.other_studio_tiktok,
              onTap: () =>
                  _openExternalUrl(context, AppConstants.tiktokUrl),
            ),
            _Row(
              title: l10n.other_studio_website,
              subtitle: 'petlo.mamonis.studio',
              onTap: () =>
                  _openExternalUrl(context, AppConstants.websiteUrl),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final String title;
  final Object? subtitle; // String or Widget
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    final Widget? sub = switch (subtitle) {
      final String s => Text(
          s,
          style: typo.bodySmall.copyWith(color: colors.fgMuted),
        ),
      final Widget w => w,
      _ => null,
    };

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.line)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: typo.bodyLarge.copyWith(
                color: onTap != null ? colors.fg : colors.fgMuted,
              ),
            ),
            if (sub != null) ...<Widget>[
              const SizedBox(height: 2),
              sub,
            ],
          ],
        ),
      ),
    );
  }
}

class _SubscriptionStatus extends ConsumerWidget {
  const _SubscriptionStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final ProStatus status = ref.watch(proStatusProvider);
    final String label = switch (status.state) {
      ProState.active => 'Pro',
      ProState.grace => 'Pro · 猶予期間',
      ProState.cancelled => 'Pro · 解約済み',
      ProState.free => 'Free',
    };
    return Text(
      label,
      style: typo.bodySmall.copyWith(color: colors.fgMuted),
    );
  }
}

// ============================================================================
class _ProCtaBanner extends StatelessWidget {
  const _ProCtaBanner({required this.colors, required this.typo});

  final AppColors colors;
  final AppTypography typo;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: () => PaywallScreen.push(context),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: colors.fg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'petlo Pro',
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 11,
                color: colors.bg.withValues(alpha: 0.6),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.more_pro_cta_hero,
              style: TextStyle(
                fontFamily: 'Fraunces',
                fontStyle: FontStyle.italic,
                fontSize: 32,
                letterSpacing: -32 * 0.04,
                height: 0.95,
                color: colors.bg,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.more_pro_cta_body,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 13,
                color: colors.bg.withValues(alpha: 0.85),
                height: 1.6,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: colors.bg, width: 1),
              ),
              child: Text(
                '${l10n.more_pro_view_plans}  →',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  color: colors.bg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openExternalUrl(BuildContext context, String url) async {
  try {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!context.mounted) return;
      final AppLocalizations l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.more_link_open_failed),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  } catch (e, st) {
    PetloLogger.instance
        .w('Failed to open external url: $url', error: e, stackTrace: st);
  }
}

Future<void> _launchMail(BuildContext context) async {
  final Uri uri = Uri(
    scheme: 'mailto',
    path: AppConstants.contactEmail,
    queryParameters: <String, String>{
      'subject':
          'petlo ${AppConstants.appVersion}+${AppConstants.appBuildNumber}',
    },
  );
  try {
    await launchUrl(uri);
  } catch (e, st) {
    PetloLogger.instance.w('mailto failed', error: e, stackTrace: st);
  }
}
