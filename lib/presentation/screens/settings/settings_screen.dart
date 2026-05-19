// ============================================================================
// petlo - Settings Screen (build 13 rev)
// ============================================================================
//
// 全タブ AppBar 右上の歯車から push される統合設定画面。
// build 13 で「その他」タブを廃止し、その中身をすべてここに集約。
//
// セクション構成:
//   - Pro バナー (無料時のみ)
//   - アカウント (ゲスト + バックアップ)
//   - 機能 (家族共有 / 投薬リマインダー)
//   - アプリ (テーマ / 言語 / 通知 / サブスク)
//   - サポート (お問い合わせ)
//   - 法的 (利用規約 / プライバシー)
//   - アプリについて (バージョン — 5タップで開発者設定)
//   - mamonis.studio (SNS + サイト)
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/billing/pro_status.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/section_label.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/display_name_provider.dart';
import '../../providers/pro_status_provider.dart';
import '../groups/groups_list_screen.dart';
import '../medication_reminder/medication_reminders_list_screen.dart';
import '../paywall/paywall_screen.dart';
import 'developer_settings_screen.dart';
import 'display_name_screen.dart';
import 'theme_settings_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _versionTapCount = 0;

  void _onVersionTap() {
    setState(() => _versionTapCount++);
    if (_versionTapCount >= 5) {
      _versionTapCount = 0;
      DeveloperSettingsScreen.push(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isPro = ref.watch(isProProvider);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        foregroundColor: colors.fg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          l10n.settings_app_bar_title.toUpperCase(),
          style: typo.metaSmall.copyWith(letterSpacing: 10 * 0.2),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // バナー類
              // build 31: BackupBanner はバックアップ未設定時に「設定推奨」を
              // 出すバナーだが、v1.0 ではクラウド連携が擬似実装なので非表示。
              // (BackupSettingsScreen / BackupBanner のコード自体は残存。v1.1 で復帰)
              if (!isPro)
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 16, 28, 8),
                  child: _ProCtaBanner(colors: colors, typo: typo),
                ),
              const SizedBox(height: 16),

              // ===== アカウント =====
              _SectionHeader(label: l10n.other_section_account),
              _Row(
                title: l10n.other_account_guest_title,
                subtitle: l10n.other_account_guest_subtitle,
              ),
              // build 18: 家族共有メンバー表示名
              _Row(
                title: '表示名',
                subtitle: ref.watch(displayNameProvider) ?? '未設定',
                onTap: () => DisplayNameScreen.push(context),
              ),
              // build 31: バックアップ行を v1.0 では非表示 (擬似実装のため)。
              // v1.1 でクラウド連携実装後に復帰させる。

              // ===== 機能 =====
              _SectionHeader(label: l10n.more_section_family),
              _Row(
                title: l10n.more_item_groups,
                onTap: () => GroupsListScreen.push(context),
              ),
              _Row(
                title: l10n.more_item_medication_reminders,
                onTap: () => MedicationRemindersListScreen.push(context),
              ),

              // ===== アプリ =====
              _SectionHeader(label: l10n.settings_section_app),
              _Row(
                title: l10n.settings_item_theme,
                onTap: () => ThemeSettingsScreen.push(context),
              ),
              _Row(
                title: l10n.settings_item_language,
                subtitle: l10n.settings_item_language_subtitle,
                trailing: l10n.settings_item_open_ios_settings,
                onTap: () => _openOsSettings(context),
              ),
              _Row(
                title: l10n.settings_item_notifications,
                subtitle: const _NotificationStatus(),
                onTap: () async {
                  final bool granted = await NotificationService.instance
                      .requestPermissions();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(granted
                          ? l10n.notifications_enabled
                          : l10n.notifications_disabled_open_settings),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              _Row(
                title: l10n.settings_item_subscription,
                subtitle: const _SubscriptionStatus(),
                onTap: () => PaywallScreen.push(context),
              ),

              // ===== サポート =====
              _SectionHeader(label: l10n.settings_section_support),
              _Row(
                title: l10n.settings_item_contact,
                subtitle: AppConstants.contactEmail,
                onTap: () => _launchMail(context),
              ),

              // ===== 法的 =====
              _SectionHeader(label: l10n.settings_section_legal),
              _Row(
                title: l10n.settings_item_terms,
                onTap: () => _openUrl(context, AppConstants.termsOfUseUrl),
              ),
              _Row(
                title: l10n.settings_item_privacy,
                onTap: () => _openUrl(context, AppConstants.privacyPolicyUrl),
              ),

              // ===== アプリについて =====
              _SectionHeader(label: l10n.settings_section_about),
              _Row(
                title: l10n.settings_item_version,
                subtitle:
                    '${AppConstants.appVersion} (build ${AppConstants.appBuildNumber})',
                onTap: _onVersionTap,
              ),

              // ===== mamonis.studio =====
              _SectionHeader(label: l10n.other_section_studio),
              _Row(
                title: l10n.other_studio_x,
                onTap: () => _openUrl(context, AppConstants.xUrl),
              ),
              _Row(
                title: l10n.other_studio_instagram,
                onTap: () => _openUrl(context, AppConstants.instagramUrl),
              ),
              _Row(
                title: l10n.other_studio_tiktok,
                onTap: () => _openUrl(context, AppConstants.tiktokUrl),
              ),
              _Row(
                title: l10n.other_studio_website,
                subtitle: 'petlo.mamonis.studio',
                onTap: () => _openUrl(context, AppConstants.websiteUrl),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    try {
      final Uri uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e, st) {
      PetloLogger.instance.w('open url failed', error: e, stackTrace: st);
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

  Future<void> _openOsSettings(BuildContext context) async {
    try {
      final Uri uri = Uri.parse('app-settings:');
      final bool ok =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (e, st) {
      PetloLogger.instance
          .w('open app-settings failed', error: e, stackTrace: st);
    }
    if (!context.mounted) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.settings_language_helper),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ============================================================================
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: SectionLabel(
        label,
        padding: const EdgeInsets.fromLTRB(0, 24, 0, 12),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  final String title;
  final Object? subtitle; // String or Widget
  final VoidCallback? onTap;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    final Widget? subtitleWidget = switch (subtitle) {
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
        padding: const EdgeInsets.fromLTRB(28, 14, 28, 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.line)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: typo.bodyLarge.copyWith(
                      color: onTap != null ? colors.fg : colors.fgMuted,
                    ),
                  ),
                  if (subtitleWidget != null) ...<Widget>[
                    const SizedBox(height: 2),
                    subtitleWidget,
                  ],
                ],
              ),
            ),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: 12),
              Text(
                trailing!,
                style: typo.bodySmall.copyWith(
                  color: colors.fgMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotificationStatus extends StatefulWidget {
  const _NotificationStatus();

  @override
  State<_NotificationStatus> createState() => _NotificationStatusState();
}

class _NotificationStatusState extends State<_NotificationStatus> {
  bool? _granted;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final bool g = await NotificationService.instance.hasPermissions();
    if (mounted) setState(() => _granted = g);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String label = switch (_granted) {
      true => l10n.notifications_enabled,
      false => l10n.notifications_disabled_open_settings,
      null => '...',
    };
    return Text(
      label,
      style: typo.bodySmall.copyWith(
        color: _granted == false ? colors.accentWarn : colors.fgMuted,
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
    final bool isPro = ref.watch(isProProvider);
    final String label = switch (status.state) {
      ProState.active => isPro ? 'Pro' : 'Free',
      ProState.grace => 'Pro · 猶予期間',
      ProState.cancelled => 'Pro · 解約済み',
      ProState.free => isPro ? 'Pro (Force)' : 'Free',
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
                fontSize: 28,
                letterSpacing: -28 * 0.04,
                height: 1.0,
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
