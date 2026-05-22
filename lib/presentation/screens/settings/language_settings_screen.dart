// ============================================================================
// petlo - Language Settings Screen
// ============================================================================
//
// 言語設定画面。
//
// rev3 方針:
//   - iOS は per-app language 設定が標準なので、in-app での切替UI は持たない
//     (Bundle swizzling は再起動問題が出るため棄却)
//   - 代わりに「OS設定アプリで切り替え可能」という案内 + Settings へのリンク
//   - 対応言語: 日本語 / English / 简体中文
//
// ============================================================================

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/section_label.dart';

class LanguageSettingsScreen extends StatelessWidget {
  const LanguageSettingsScreen({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const LanguageSettingsScreen(),
      ),
    );
  }

  Future<void> _openOsSettings(BuildContext context) async {
    try {
      // iOS: app-specific settings
      // Android: app info screen
      final Uri uri = Platform.isIOS
          ? Uri.parse('app-settings:')
          : Uri.parse('package:com.example.petlo'); // 後方互換用、url_launcher 内部でhandleされる

      if (Platform.isIOS) {
        await launchUrl(uri);
      } else {
        // Android は url_launcher で `app-settings:` 系が動かないため、
        // 一般的な Settings アプリへのintentに代替
        // (実機テストで permission_handler の openAppSettings() を後で接続)
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).settings_snackbar_change_in_os),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to open OS settings', error: e, stackTrace: st);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).settings_snackbar_open_settings_failed),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
          AppLocalizations.of(context).appbar_language,
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
                l10n.settings_language_eyebrow,
                size: EyebrowSize.large,
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
              ),
              Text(
                l10n.settings_language_body,
                style: typo.bodyMedium
                    .copyWith(color: colors.fgMuted, height: 1.7),
              ),
              const SizedBox(height: 32),

              SectionLabel(AppLocalizations.of(context).section_available_languages),
              const SizedBox(height: 8),
              _LangRow(name: '日本語', code: 'JA'),
              _LangRow(name: 'English', code: 'EN'),
              _LangRow(name: '简体中文', code: 'ZH'),
              const SizedBox(height: 32),

              if (Platform.isIOS)
                InkWell(
                  onTap: () => _openOsSettings(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: colors.fg,
                      border: Border.all(color: colors.fg),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'OPEN iOS SETTINGS',
                      style: TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 10,
                        letterSpacing: 10 * 0.18,
                        color: colors.bg,
                        fontWeight: FontWeight.w700,
                      ),
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

class _LangRow extends StatelessWidget {
  const _LangRow({required this.name, required this.code});

  final String name;
  final String code;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              name,
              style: typo.bodyLarge.copyWith(color: colors.fg),
            ),
          ),
          Text(
            code,
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 11,
              letterSpacing: 11 * 0.18,
              color: colors.fgMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
