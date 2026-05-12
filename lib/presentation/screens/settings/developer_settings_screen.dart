// ============================================================================
// petlo - Developer Settings Screen
// ============================================================================
//
// デバッグ用の隠しメニュー。
// リリース前に kReleaseMode で gating して非表示化する想定だが、
// v1.0 では「困ったときの再表示」として残しておく(問い合わせ対応が楽)。
//
// 提供:
//   - オンボーディングを再表示
//   - Pro 状態をリセット (v1.0 のサーバー検証未実装期に開発で使う)
//   - 警告バナー(F-79)を再表示 (Remind me later をリセット)
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backup/backup_settings.dart';
import '../../../core/billing/pro_status.dart';
import '../../../core/preferences/user_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/section_label.dart';
import '../../providers/backup_settings_provider.dart';
import '../../providers/onboarding_completed_provider.dart';
import '../../providers/pro_status_provider.dart';

class DeveloperSettingsScreen extends ConsumerWidget {
  const DeveloperSettingsScreen({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const DeveloperSettingsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          AppLocalizations.of(context).appbar_developer,
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
              EyebrowText(l10n.settings_developer_eyebrow),
              const SizedBox(height: 8),
              Text(
                'Developer.',
                style: typo.heroName.copyWith(height: 0.95),
              ),
              const SizedBox(height: 16),
              Text(
                '困った時のリセット用メニュー。\n通常は使う必要ありません。',
                style: typo.bodyMedium
                    .copyWith(color: colors.fgMuted, height: 1.7),
              ),
              const SizedBox(height: 32),

              SectionLabel(AppLocalizations.of(context).section_reset_state),
              const SizedBox(height: 8),

              _ActionRow(
                title: 'Replay onboarding',
                note: 'チュートリアルを次回起動時に再表示します',
                onTap: () => _onReplayOnboarding(context, ref),
                colors: colors,
                typo: typo,
              ),

              _ActionRow(
                title: 'Clear backup reminder',
                note: '"Remind me later" の30日抑止を解除します',
                onTap: () => _onClearBackupReminder(context, ref),
                colors: colors,
                typo: typo,
              ),

              _ActionRow(
                title: 'Reset Pro status',
                note: 'Pro 契約状態を無料に戻します(レシート再検証で復元されます)',
                onTap: () => _onResetProStatus(context, ref),
                colors: colors,
                typo: typo,
                isDestructive: true,
              ),

              const SizedBox(height: 24),
              _ForceProToggle(colors: colors, typo: typo),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onReplayOnboarding(
      BuildContext context, WidgetRef ref) async {
    await ref.read(onboardingCompletedProvider.notifier).reset();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).developer_snackbar_onboarding_reset),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _onClearBackupReminder(
      BuildContext context, WidgetRef ref) async {
    final BackupSettings current =
        ref.read(backupSettingsProvider);
    final BackupSettings cleared =
        current.copyWith(remindLaterAt: null);
    await ref
        .read(backupSettingsProvider.notifier)
        .updateSettings(cleared);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).developer_snackbar_backup_reminder_cleared),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _onResetProStatus(
      BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Pro 状態をリセット'),
        content: const Text(
            'Pro 契約状態をローカルで無料にします。\n実際の契約は変更されません。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('リセット'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await UserPreferences.instance.setProStatus(ProStatus.free);
    // 反映のため Provider を invalidate
    ref.invalidate(proStatusProvider);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).developer_snackbar_pro_reset),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ============================================================================
// _ForceProToggle (build 11) - Pro 状態強制 ON で課金フローをテスト
// ============================================================================
class _ForceProToggle extends ConsumerWidget {
  const _ForceProToggle({required this.colors, required this.typo});

  final AppColors colors;
  final AppTypography typo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool enabled = ref.watch(forceProProvider);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.line),
          bottom: BorderSide(color: colors.line),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Force Pro (テスト用)',
                  style: typo.bodyLarge.copyWith(color: colors.fg),
                ),
                const SizedBox(height: 2),
                Text(
                  'ON で課金状態に関わらず Pro 機能を有効化します。'
                  '\n本番リリース前に必ず OFF に戻してください。',
                  style: typo.bodySmall
                      .copyWith(color: colors.fgMuted, height: 1.5),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            onChanged: (bool v) async {
              await ref.read(forceProProvider.notifier).setEnabled(v);
            },
            activeThumbColor: colors.bg,
            activeTrackColor: colors.fg,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// _ActionRow
// ============================================================================
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.title,
    required this.note,
    required this.onTap,
    required this.colors,
    required this.typo,
    this.isDestructive = false,
  });

  final String title;
  final String note;
  final VoidCallback onTap;
  final AppColors colors;
  final AppTypography typo;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final Color titleColor =
        isDestructive ? colors.accentDanger : colors.fg;
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
                    style:
                        typo.bodyLarge.copyWith(color: titleColor),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    note,
                    style: typo.bodySmall
                        .copyWith(color: colors.fgMuted, height: 1.5),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: colors.fgMuted),
          ],
        ),
      ),
    );
  }
}
