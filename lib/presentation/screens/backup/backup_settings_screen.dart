// ============================================================================
// petlo - Backup Settings Screen
// ============================================================================
//
// バックアップ設定画面。
//
// レイアウト:
//   - eyebrow + ヒーロー
//   - 状態カード (ON / OFF / setupInProgress / error の4状態を反映)
//   - 「今すぐバックアップ」ボタン (state=on のみ)
//   - 「バックアップを有効化」 (state=off の時、プラットフォーム別)
//   - 「バックアップを停止」 (state=on の時)
//   - 注意書き(暗号化、復元方法等)
//
// rev3 + rev5.5 F-79
// v1.0: クラウド連携はプレースホルダ、UI と永続化のみ動作
//
// ============================================================================

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backup/backup_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/section_label.dart';
import '../../providers/backup_settings_provider.dart';

class BackupSettingsScreen extends ConsumerWidget {
  const BackupSettingsScreen({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const BackupSettingsScreen(),
      ),
    );
  }

  BackupProvider get _platformProvider {
    return Platform.isIOS
        ? BackupProvider.iCloud
        : BackupProvider.googleDrive;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final BackupSettings settings = ref.watch(backupSettingsProvider);
    final BackupSettingsNotifier notifier =
        ref.read(backupSettingsProvider.notifier);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          AppLocalizations.of(context).appbar_backup,
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
                l10n.backup_eyebrow,
                size: EyebrowSize.large,
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
              ),
              Text(
                _heroDescription(settings, _platformProvider, l10n),
                style: typo.bodyMedium.copyWith(
                  color: colors.fgMuted,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 28),

              // ===== 状態カード =====
              _StatusCard(settings: settings, colors: colors, typo: typo),
              const SizedBox(height: 24),

              // ===== アクションボタン =====
              if (settings.state == BackupState.off)
                _PrimaryAction(
                  label:
                      'Enable backup with ${_platformProvider.displayLabel(l10n)}',
                  enabled: true,
                  onTap: () => _onEnable(
                      context, notifier, _platformProvider),
                  colors: colors,
                ),

              if (settings.state == BackupState.setupInProgress)
                _PrimaryAction(
                  label: 'Setting up...',
                  enabled: false,
                  onTap: () {},
                  colors: colors,
                ),

              if (settings.state == BackupState.on) ...<Widget>[
                _PrimaryAction(
                  label: 'Back up now',
                  enabled: true,
                  onTap: () => _onBackupNow(context, notifier),
                  colors: colors,
                ),
                const SizedBox(height: 10),
                _SecondaryAction(
                  label: 'Stop backup',
                  onTap: () => _onDisable(context, notifier),
                  colors: colors,
                ),
              ],

              if (settings.state == BackupState.error) ...<Widget>[
                _PrimaryAction(
                  label: 'Try again',
                  enabled: true,
                  onTap: () => _onBackupNow(context, notifier),
                  colors: colors,
                ),
                const SizedBox(height: 10),
                _SecondaryAction(
                  label: 'Stop backup',
                  onTap: () => _onDisable(context, notifier),
                  colors: colors,
                ),
              ],

              const SizedBox(height: 32),

              // ===== 詳細情報 =====
              SectionLabel(AppLocalizations.of(context).common_details),
              const SizedBox(height: 8),
              _DetailRow(
                label: 'PROVIDER',
                value: settings.provider.displayLabel(l10n),
                colors: colors,
              ),
              if (settings.lastSuccessAt != null)
                _DetailRow(
                  label: 'LAST BACKUP',
                  value: formatDateTime(
                    settings.lastSuccessAt!,
                    Localizations.localeOf(context).toLanguageTag(),
                  ),
                  colors: colors,
                ),
              if (settings.lastErrorMessage != null)
                _DetailRow(
                  label: 'LAST ERROR',
                  value: settings.lastErrorMessage!,
                  colors: colors,
                  isWarning: true,
                ),
              const SizedBox(height: 32),

              // ===== 注意書き =====
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.line, width: 1),
                ),
                child: Text(
                  AppLocalizations.of(context).backup_settings_disclaimer,
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 10,
                    letterSpacing: 10 * 0.1,
                    height: 1.6,
                    color: colors.fgMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // Helpers
  // ==========================================================================

  String _heroDescription(
      BackupSettings s, BackupProvider provider, AppLocalizations l10n) {
    switch (s.state) {
      case BackupState.on:
        return l10n.backup_status_on_message(provider.displayLabel(l10n));
      case BackupState.setupInProgress:
        return l10n.backup_status_setup_in_progress;
      case BackupState.error:
        return l10n.backup_status_error_message;
      case BackupState.off:
        return l10n.backup_status_off_message;
    }
  }

  // ==========================================================================
  // Actions
  // ==========================================================================

  Future<void> _onEnable(
    BuildContext context,
    BackupSettingsNotifier notifier,
    BackupProvider provider,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool ok = await notifier.enableBackup(provider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? l10n.backup_enable_success_snackbar
            : l10n.backup_enable_failed_snackbar),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _onDisable(
    BuildContext context,
    BackupSettingsNotifier notifier,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.backup_disable_dialog_title),
        content: Text(l10n.backup_disable_dialog_body),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.backup_disable_dialog_action),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await notifier.disableBackup();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
              content: Text(AppLocalizations.of(context).backup_snackbar_disabled),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _onBackupNow(
    BuildContext context,
    BackupSettingsNotifier notifier,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool ok = await notifier.backupNow();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? l10n.backup_now_success_snackbar
            : l10n.backup_now_failed_snackbar),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ============================================================================
// _StatusCard - 状態表示カード
// ============================================================================
class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.settings,
    required this.colors,
    required this.typo,
  });

  final BackupSettings settings;
  final AppColors colors;
  final AppTypography typo;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ({String label, Color color, String body}) status = switch (
        settings.state) {
      BackupState.on => (
          label: 'ACTIVE',
          color: colors.fg,
          body: settings.daysSinceLastSuccess == null
              ? l10n.backup_banner_setup_in_progress
              : settings.daysSinceLastSuccess == 0
                  ? l10n.backup_banner_today
                  : l10n.backup_banner_days_ago(
                      settings.daysSinceLastSuccess!),
        ),
      BackupState.off => (
          label: 'INACTIVE',
          color: colors.fgMuted,
          body: l10n.backup_banner_off,
        ),
      BackupState.setupInProgress => (
          label: 'SETTING UP',
          color: colors.fg,
          body: l10n.backup_banner_connecting,
        ),
      BackupState.error => (
          label: 'ERROR',
          color: colors.accentDanger,
          body: settings.lastErrorMessage ?? l10n.backup_banner_failed,
        ),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: settings.state == BackupState.on ? colors.fg : colors.bg,
        border: Border.all(color: status.color, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            status.label,
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 10,
              letterSpacing: 10 * 0.2,
              color: settings.state == BackupState.on
                  ? colors.bg
                  : status.color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            status.body,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 22,
              color: settings.state == BackupState.on
                  ? colors.bg
                  : colors.fg,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// _PrimaryAction / _SecondaryAction
// ============================================================================
class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.label,
    required this.enabled,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? colors.fg : colors.bgSoft,
          border: Border.all(
              color: enabled ? colors.fg : colors.line, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 12,
            letterSpacing: 12 * 0.15,
            color: enabled ? colors.bg : colors.fgFaint,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
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
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: colors.line, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 11,
            letterSpacing: 11 * 0.15,
            color: colors.fgMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// _DetailRow - 詳細情報の1行
// ============================================================================
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.colors,
    this.isWarning = false,
  });

  final String label;
  final String value;
  final AppColors colors;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 100,
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
                fontFamily: 'Manrope',
                fontSize: 13,
                color: isWarning ? colors.accentDanger : colors.fg,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
