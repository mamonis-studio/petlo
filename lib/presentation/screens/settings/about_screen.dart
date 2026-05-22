// ============================================================================
// petlo - About Screen
// ============================================================================
//
// petloについて。
//
// レイアウト:
//   - エディトリアルヒーロー: "petlo."
//   - コンセプト文 + バージョン
//   - Privacy policy / Terms of use リンク
//   - Support 連絡先
//   - mamonis.studio SNS フッター (X / Instagram / TikTok)
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/section_label.dart';
import 'developer_settings_screen.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const AboutScreen(),
      ),
    );
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    try {
      final Uri uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).settings_snackbar_link_open_failed),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to open url: $url', error: e, stackTrace: st);
    }
  }

  Future<void> _openMail(BuildContext context, String email) async {
    try {
      final Uri uri = Uri(scheme: 'mailto', path: email);
      if (!await launchUrl(uri)) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(email),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to open mail', error: e, stackTrace: st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          AppLocalizations.of(context).appbar_about,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            letterSpacing: 10 * 0.2,
            color: colors.fg,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.fg),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SectionLabel(
                l10n.settings_about_eyebrow,
                size: EyebrowSize.large,
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
              ),
              // build 23: § ABOUT 統一後も、ブランドロゴ的に petlo. 64pt は残す
              Text(
                'petlo.',
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontStyle: FontStyle.italic,
                  fontSize: 64,
                  letterSpacing: -64 * 0.04,
                  height: 0.95,
                  color: colors.fg,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(context).about_app_description,
                style: typo.bodyLarge
                    .copyWith(color: colors.fg, height: 1.7),
              ),
              const SizedBox(height: 28),

              // バージョン
              _MetaRow(
                  label: 'VERSION', value: AppConstants.appVersion),
              _MetaRow(
                  label: 'BUNDLE', value: AppConstants.bundleId),
              const SizedBox(height: 32),

              // Legal
              SectionLabel(AppLocalizations.of(context).section_legal),
              const SizedBox(height: 8),
              _LinkRow(
                title: 'Privacy policy',
                onTap: () =>
                    _openUrl(context, AppConstants.privacyPolicyUrl),
              ),
              _LinkRow(
                title: 'Terms of use',
                onTap: () => _openUrl(context, AppConstants.termsOfUseUrl),
              ),
              const SizedBox(height: 32),

              // Support
              SectionLabel(AppLocalizations.of(context).section_support),
              const SizedBox(height: 8),
              _LinkRow(
                title: 'Contact form',
                onTap: () => _openUrl(context, AppConstants.supportUrl),
              ),
              _LinkRow(
                title: AppConstants.contactEmail,
                onTap: () =>
                    _openMail(context, AppConstants.contactEmail),
              ),
              const SizedBox(height: 32),

              // mamonis.studio
              const SectionLabel('mamonis.studio'),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context).about_studio_description,
                style: typo.bodyMedium
                    .copyWith(color: colors.fgMuted, height: 1.6),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  _SocialPill(
                    label: 'X',
                    onTap: () => _openUrl(context, AppConstants.xUrl),
                  ),
                  const SizedBox(width: 8),
                  _SocialPill(
                    label: 'INSTAGRAM',
                    onTap: () =>
                        _openUrl(context, AppConstants.instagramUrl),
                  ),
                  const SizedBox(width: 8),
                  _SocialPill(
                    label: 'TIKTOK',
                    onTap: () =>
                        _openUrl(context, AppConstants.tiktokUrl),
                  ),
                ],
              ),
              const SizedBox(height: 40),

              // Footer (長押しで開発者メニュー)
              GestureDetector(
                onLongPress: () =>
                    DeveloperSettingsScreen.push(context),
                child: Text(
                  '© ${DateTime.now().year} mamonis.studio',
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 10,
                    letterSpacing: 10 * 0.15,
                    color: colors.fgFaint,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// _MetaRow - 値表示行
// ============================================================================
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 9,
                letterSpacing: 9 * 0.2,
                color: colors.fgMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 11,
                letterSpacing: 11 * 0.05,
                color: colors.fg,
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// _LinkRow - 外部リンク行
// ============================================================================
class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
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
              child: Text(
                title,
                style: typo.bodyLarge.copyWith(color: colors.fg),
              ),
            ),
            Icon(Icons.north_east, size: 14, color: colors.fgMuted),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// _SocialPill - SNSアイコンの代わりのテキストピル(絵文字なし方針)
// ============================================================================
class _SocialPill extends StatelessWidget {
  const _SocialPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: colors.fg, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            letterSpacing: 10 * 0.18,
            color: colors.fg,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
