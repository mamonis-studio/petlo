// ============================================================================
// petlo - Backup Banner (F-79)
// ============================================================================
//
// バックアップOFF + 記録100件以上 + 30日以内未抑止 で表示する警告バナー。
//
// rev5.5 §4.14: エディトリアル風冷静なトーン、煽らない。
//
// Layout:
// ┌─────────────────────────────┐
// │ BACKUP                       │
// │                              │
// │ Your records are safer       │
// │ in the cloud.                │
// │                              │
// │ 100件以上記録されています。      │
// │ 端末を紛失すると失われます。      │
// │                              │
// │ [Set up auto backup]         │
// │ [Remind me later]            │
// └─────────────────────────────┘
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../providers/backup_settings_provider.dart';
import '../../screens/backup/backup_settings_screen.dart';

/// More タブ等で挿入される警告バナー。
/// 表示条件は `shouldShowBackupBannerProvider` が true の時のみ。
class BackupBanner extends ConsumerWidget {
  const BackupBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool shouldShow = ref.watch(shouldShowBackupBannerProvider);
    if (!shouldShow) return const SizedBox.shrink();

    final AppColors colors = AppColors.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border.all(color: colors.fg, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ヘッダー
          Text(
            'BACKUP',
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 9,
              letterSpacing: 9 * 0.2,
              color: colors.fgMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),

          // メイン Fraunces italic
          Text(
            'Your records are safer\nin the cloud.',
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 24,
              letterSpacing: -24 * 0.03,
              height: 1.15,
              color: colors.fg,
            ),
          ),
          const SizedBox(height: 12),

          // サブコピー
          Text(
            '100件以上の記録があります。\n端末を紛失すると失われてしまうので、\n自動バックアップを有効にしましょう。',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 13,
              color: colors.fgMuted,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),

          // CTA
          _CtaButton(
            label: 'SET UP AUTO BACKUP',
            isPrimary: true,
            onTap: () => BackupSettingsScreen.push(context),
            colors: colors,
          ),
          const SizedBox(height: 8),
          _CtaButton(
            label: 'REMIND ME LATER',
            isPrimary: false,
            onTap: () =>
                ref.read(backupSettingsProvider.notifier).remindLater(),
            colors: colors,
          ),
        ],
      ),
    );
  }
}

class _CtaButton extends StatelessWidget {
  const _CtaButton({
    required this.label,
    required this.isPrimary,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final bool isPrimary;
  final VoidCallback onTap;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isPrimary ? colors.fg : colors.bg,
          border: Border.all(
            color: isPrimary ? colors.fg : colors.line,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            letterSpacing: 10 * 0.18,
            color: isPrimary ? colors.bg : colors.fgMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
