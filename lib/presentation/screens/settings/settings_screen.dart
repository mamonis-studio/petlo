// ============================================================================
// petlo - Settings Screen
// ============================================================================
//
// アプリの設定画面。歯車アイコンから遷移する。
// 「その他」タブの § 設定 行からも到達。
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/section_label.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/pro_status_provider.dart';
import '../backup/backup_settings_screen.dart';
import '../paywall/paywall_screen.dart';
import 'developer_settings_screen.dart';
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
    final WidgetRef ref = this.ref;
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

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
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              EyebrowText(l10n.settings_eyebrow),
              const SizedBox(height: 8),
              Text(
                l10n.settings_hero,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontStyle: FontStyle.italic,
                  fontSize: 44,
                  letterSpacing: -44 * 0.04,
                  height: 1.0,
                  color: colors.fg,
                ),
              ),
              const SizedBox(height: 32),

              // ===== § App =====
              SectionLabel(l10n.settings_section_app),
              const SizedBox(height: 8),
              _Row(
                title: l10n.settings_item_theme,
                onTap: () => ThemeSettingsScreen.push(context),
              ),
              _Row(
                title: l10n.settings_item_language,
                subtitle: l10n.settings_item_language_subtitle,
                onTap: () => _openOsSettings(context),
                trailing: l10n.settings_item_open_ios_settings,
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
              _Row(
                title: l10n.settings_item_backup,
                onTap: () => BackupSettingsScreen.push(context),
              ),
              const SizedBox(height: 32),

              // ===== § Support =====
              SectionLabel(l10n.settings_section_support),
              const SizedBox(height: 8),
              _Row(
                title: l10n.settings_item_contact,
                subtitle: AppConstants.contactEmail,
                onTap: () => _launchMail(context),
              ),
              const SizedBox(height: 32),

              // ===== § Legal =====
              SectionLabel(l10n.settings_section_legal),
              const SizedBox(height: 8),
              _Row(
                title: l10n.settings_item_terms,
                onTap: () =>
                    _openUrl(context, AppConstants.termsOfUseUrl),
              ),
              _Row(
                title: l10n.settings_item_privacy,
                onTap: () =>
                    _openUrl(context, AppConstants.privacyPolicyUrl),
              ),
              const SizedBox(height: 32),

              // ===== § About =====
              SectionLabel(l10n.settings_section_about),
              const SizedBox(height: 8),
              _Row(
                title: l10n.settings_item_version,
                subtitle:
                    '${AppConstants.appVersion} (build ${AppConstants.appBuildNumber})',
                onTap: _onVersionTap,
              ),
              const SizedBox(height: 48),
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
        'subject': 'petlo ${AppConstants.appVersion}+${AppConstants.appBuildNumber}',
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
      // iOS: app-settings: scheme は url_launcher で開ける
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
        padding: const EdgeInsets.symmetric(vertical: 14),
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
    final bool isPro = ref.watch(isProProvider);
    return Text(
      isPro ? 'Pro' : 'Free',
      style: typo.bodySmall.copyWith(color: colors.fgMuted),
    );
  }
}
