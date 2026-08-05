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

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show PendingNotificationRequest;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/backup/backup_settings.dart';
import '../../../core/billing/pro_status.dart';
import '../../../core/notifications/notification_budget_allocator.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/preferences/user_preferences.dart';
import '../../../core/utils/startup_trace.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/section_label.dart';
import '../../providers/backup_settings_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/onboarding_completed_provider.dart';
import '../../providers/pro_status_provider.dart';

class DeveloperSettingsScreen extends ConsumerWidget {
  const DeveloperSettingsScreen({super.key});

  static Future<void> push(BuildContext context) {
    // build 61: 多重防御。trigger 側でも Release ガードしているが、
    // 万一 push 関数が他経路から呼ばれてもここで弾く。App Store 審査対策。
    if (kReleaseMode) return Future<void>.value();
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
              SectionLabel(
                l10n.settings_developer_eyebrow,
                size: EyebrowSize.large,
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
              ),
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

              _ActionRow(
                title: 'Sync now',
                note: '家族共有スコープを即時 push + pull します。',
                onTap: () => _onSyncNow(context),
                colors: colors,
                typo: typo,
              ),

              _ActionRow(
                title: 'データリセット (全消去)',
                note: 'Keychain + ローカル DB を全消去し、新規ユーザーとして再登録します。'
                    '\nアカウント認証が壊れたときの最終手段。実行後はアプリを再起動してください。',
                onTap: () => _onFactoryReset(context, ref),
                colors: colors,
                typo: typo,
                isDestructive: true,
              ),

              const SizedBox(height: 24),
              _ForceProToggle(colors: colors, typo: typo),

              // build 73: 起動シーケンスの所要時間
              const SizedBox(height: 32),
              _StartupTraceBlock(colors: colors, typo: typo),

              // build 73: §13 #4 (iOS 64 slot 上限) を見る唯一の手段。
              const SizedBox(height: 32),
              const _PendingNotificationsSection(),
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

  Future<void> _onSyncNow(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Syncing...'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 1),
      ),
    );
    await SyncService.instance.syncAll();
    if (!context.mounted) return;
    final DateTime? at = SyncService.instance.lastSyncAt;
    messenger.showSnackBar(
      SnackBar(
        content: Text(at == null
            ? 'Sync finished (no active groups?)'
            : 'Sync finished at ${at.toLocal()}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _onFactoryReset(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('データリセット'),
        content: const Text(
          '全データを消去し、新規ユーザーとして再登録します。\n\n'
          '・ペット、記録、写真、AI 会話\n'
          '・ログイン情報 (Keychain)\n'
          '\nこの操作は取り消せません。実行後はアプリを再起動してください。',
        ),
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

    // drift DB をクローズ + sqlite ファイル削除
    try {
      await ref.read(appDatabaseProvider).close();
    } catch (_) {}
    try {
      final Directory dir = await getApplicationDocumentsDirectory();
      final File dbFile = File(p.join(dir.path, 'petlo.sqlite'));
      if (dbFile.existsSync()) {
        await dbFile.delete();
      }
    } catch (_) {}

    // Keychain クリア + 新しい deviceId で anonymous 再登録
    await AuthService.instance.forceReset();

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('リセット完了'),
        content: const Text(
          'データを全消去しました。\n手動でアプリを終了して再起動してください。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
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

// ============================================================================
// _PendingNotificationsSection (build 73)
// ============================================================================
//
// NotificationService.pending() を ID レンジで仕分けて表示する。
// §13 #4「iOS で合計 64 未満」を確認する唯一の手段。
//
//   1,000,000〜    ワクチン
// 100,000,000〜    schedule (投薬)
// 400,000,000〜    予防 dose
// 500,000,000〜    予防 course
//
// _kScheduleSlotBudget を 50 → 38 に下げた影響 (#2 / #3) も、
// ワクチン・投薬の件数がここで 0 になっていないかで判定する。
//
class _PendingNotificationsSection extends StatefulWidget {
  const _PendingNotificationsSection();

  @override
  State<_PendingNotificationsSection> createState() =>
      _PendingNotificationsSectionState();
}

/// ID レンジの区分。境界は NotificationService の採番ヘルパーと対応する。
enum _NotificationBucket {
  vaccination('VACCINATION', 1000000, 10000000),
  medicationLegacy('MEDICATION (legacy)', 10000000, 100000000),
  schedule('SCHEDULE', 100000000, 400000000),
  preventionDose('PREVENTION DOSE', 400000000, 500000000),
  preventionCourse('PREVENTION COURSE', 500000000, 600000000),
  other('OTHER', 0, 0);

  const _NotificationBucket(this.label, this.from, this.toExclusive);

  final String label;
  final int from;
  final int toExclusive;

  static _NotificationBucket of(int id) {
    for (final _NotificationBucket b in values) {
      if (b == other) continue;
      if (id >= b.from && id < b.toExclusive) return b;
    }
    return other;
  }
}

class _PendingNotificationsSectionState
    extends State<_PendingNotificationsSection> {
  List<PendingNotificationRequest>? _pending;

  /// 通知権限の許可状態。null = 未取得
  bool? _permitted;

  bool _loading = false;

  Future<void> _load() async {
    setState(() => _loading = true);
    // 「0 件」と「未許可」を区別できるよう権限状態も一緒に取る。
    final bool permitted = await NotificationService.instance.hasPermissions();
    final List<PendingNotificationRequest> list =
        await NotificationService.instance.pending();
    if (!mounted) return;
    setState(() {
      _permitted = permitted;
      _pending = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final List<PendingNotificationRequest>? pending = _pending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionLabel('PENDING NOTIFICATIONS'),
        const SizedBox(height: 8),
        Text(
          'iOS の同時予約上限は 64。合計がこれを超えると、'
          '古いものから黙って捨てられます。',
          style: typo.bodySmall.copyWith(color: colors.fgMuted, height: 1.6),
        ),
        const SizedBox(height: 12),

        _ActionRow(
          title: _loading ? '読み込み中…' : 'Reload pending()',
          note: '現在予約されているローカル通知を ID レンジ別に集計します',
          onTap: () {
            if (!_loading) unawaited(_load());
          },
          colors: colors,
          typo: typo,
        ),

        if (pending != null) ...<Widget>[
          const SizedBox(height: 16),

          // ===== 権限状態 =====
          // 0 件のとき、それが「予約が無い」のか「そもそも通知が
          // 許可されていない」のかを読み分けるための行。
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(
                color: _permitted == true ? colors.line : colors.accentWarn,
              ),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'NOTIFICATION PERMISSION',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 9,
                      letterSpacing: 9 * 0.2,
                      color: colors.fgMuted,
                    ),
                  ),
                ),
                Text(
                  _permitted == null
                      ? '—'
                      : (_permitted! ? 'GRANTED' : 'NOT GRANTED'),
                  style: typo.bodyMedium.copyWith(
                    color:
                        _permitted == true ? colors.fg : colors.accentWarn,
                  ),
                ),
              ],
            ),
          ),
          // ===== 旧 ID 掃除の実行結果 (build 73) =====
          // 「未実行」「実行して 0 件」「実行して N 件」を区別する。
          // ログは debug でしか出ず、debug は端末によって起動できないため、
          // 結果そのものを永続化して読む。
          const SizedBox(height: 8),
          _MigrationRow(
            label: 'LEGACY SCHEDULE ID CLEANUP',
            done: UserPreferences.instance.scheduleIdMigratedV2,
            count: UserPreferences.instance.scheduleIdMigratedCount,
            colors: colors,
            typo: typo,
          ),
          const SizedBox(height: 8),
          Builder(
            builder: (BuildContext context) {
              final bool done =
                  UserPreferences.instance.vaccinationIdMigratedV2;
              final int? count =
                  UserPreferences.instance.vaccinationIdMigratedCount;
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.line),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'LEGACY VACCINATION ID CLEANUP',
                        style: TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 9,
                          letterSpacing: 9 * 0.2,
                          color: colors.fgMuted,
                        ),
                      ),
                    ),
                    Text(
                      done
                          ? 'cleared ${count ?? '?'}'
                          : 'not run yet',
                      style: typo.bodyMedium.copyWith(
                        color: done ? colors.fg : colors.accentWarn,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          if (_permitted == false) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '未許可のため、予約しても iOS 側に登録されない可能性があります。'
              '下の 0 件はその結果かもしれません。',
              style: typo.bodySmall
                  .copyWith(color: colors.accentWarn, height: 1.6),
            ),
          ],
          const SizedBox(height: 16),

          // ===== 直近の割り当てレポート (build 73) =====
          // 「積みたかった数 / 積めた数 / 溢れた数」を系統別に出す。
          // pending() の実測と突き合わせるための基準値になる。
          _AllocationReportBlock(colors: colors, typo: typo),
          const SizedBox(height: 16),

          // ===== 合計 =====
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(
                color: pending.length >= 64
                    ? colors.accentDanger
                    : colors.fg,
                width: pending.length >= 64 ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'TOTAL',
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 9,
                    letterSpacing: 9 * 0.2,
                    color: colors.fgMuted,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${pending.length} / 64',
                  style: TextStyle(
                    fontFamily: 'Fraunces',
                    fontStyle: FontStyle.italic,
                    fontSize: 32,
                    height: 1.0,
                    color: pending.length >= 64
                        ? colors.accentDanger
                        : colors.fg,
                  ),
                ),
                if (pending.length >= 64) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    '上限に達しています。リリースしないでください。',
                    style: typo.bodySmall
                        .copyWith(color: colors.accentDanger),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ===== レンジ別 =====
          for (final _NotificationBucket b in _NotificationBucket.values)
            _BucketRow(
              bucket: b,
              items: pending
                  .where((PendingNotificationRequest r) =>
                      _NotificationBucket.of(r.id) == b)
                  .toList(),
              colors: colors,
              typo: typo,
            ),
        ],
      ],
    );
  }
}

class _BucketRow extends StatelessWidget {
  const _BucketRow({
    required this.bucket,
    required this.items,
    required this.colors,
    required this.typo,
  });

  final _NotificationBucket bucket;
  final List<PendingNotificationRequest> items;
  final AppColors colors;
  final AppTypography typo;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && bucket == _NotificationBucket.other) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  bucket.label,
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 10,
                    letterSpacing: 10 * 0.15,
                    color: items.isEmpty ? colors.fgFaint : colors.fg,
                  ),
                ),
              ),
              Text(
                '${items.length}',
                style: typo.bodyMedium.copyWith(
                  color: items.isEmpty ? colors.fgFaint : colors.fg,
                ),
              ),
            ],
          ),
          // 個別の ID とタイトル (多いときは先頭のみ)
          for (final PendingNotificationRequest r in items.take(8))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '· ${r.id}  ${r.title ?? ''}',
                style: typo.metaSmall.copyWith(color: colors.fgMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (items.length > 8)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '· … 他 ${items.length - 8} 件',
                style: typo.metaSmall.copyWith(color: colors.fgFaint),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// _MigrationRow (build 73)
// ============================================================================
//
// 「未実行」「実行して 0 件」「実行して N 件」を区別して表示する。
// ログは debug ビルドでしか出ず、debug は端末によっては JIT で起動できない。
// 可観測性はログではなく永続化した結果で担保する。
//
class _MigrationRow extends StatelessWidget {
  const _MigrationRow({
    required this.label,
    required this.done,
    required this.count,
    required this.colors,
    required this.typo,
  });

  final String label;
  final bool done;
  final int? count;
  final AppColors colors;
  final AppTypography typo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: colors.line)),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 9,
                letterSpacing: 9 * 0.2,
                color: colors.fgMuted,
              ),
            ),
          ),
          Text(
            done ? 'cleared ${count ?? '?'}' : 'not run yet',
            style: typo.bodyMedium.copyWith(
              color: done ? colors.fg : colors.accentWarn,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// _AllocationReportBlock (build 73)
// ============================================================================
//
// NotificationCoordinator が最後に行った割り当ての結果。
// 「何を積みたかったか」と「何が溢れたか」を系統別に出す。
// 下の pending() の実測と突き合わせて使う。
//
class _AllocationReportBlock extends StatelessWidget {
  const _AllocationReportBlock({required this.colors, required this.typo});

  final AppColors colors;
  final AppTypography typo;

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? raw =
        UserPreferences.instance.notificationAllocationReport;
    final NotificationAllocationReport? report =
        raw == null ? null : NotificationAllocationReport.fromJson(raw);

    if (report == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: colors.line)),
        child: Text(
          'ALLOCATION REPORT: not run yet',
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 9,
            letterSpacing: 9 * 0.2,
            color: colors.accentWarn,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border.all(color: colors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'ALLOCATION (scheduled / wanted)',
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 9,
              letterSpacing: 9 * 0.2,
              color: colors.fgMuted,
            ),
          ),
          const SizedBox(height: 8),
          for (final NotificationSystem s in NotificationSystem.values)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      s.name.toUpperCase(),
                      style: typo.metaSmall.copyWith(color: colors.fgMuted),
                    ),
                  ),
                  Text(
                    '${report.scheduledOf(s)} / ${report.candidatesOf(s)}',
                    style: typo.bodyMedium,
                  ),
                  if (report.droppedOf(s) > 0) ...<Widget>[
                    const SizedBox(width: 8),
                    Text(
                      '-${report.droppedOf(s)}',
                      style: typo.metaSmall
                          .copyWith(color: colors.accentDanger),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: Text('TOTAL',
                    style: typo.metaSmall.copyWith(color: colors.fg)),
              ),
              Text(
                '${report.totalScheduled} / ${NotificationBudget.total}',
                style: typo.bodyMedium,
              ),
            ],
          ),
          if (report.totalDropped > 0) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '溢れた ${report.totalDropped} 件は積まれていません。'
              'iOS の切り捨てではなく、こちらが意図的に落としたぶんです。',
              style: typo.bodySmall
                  .copyWith(color: colors.fgMuted, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// _StartupTraceBlock (build 73)
// ============================================================================
//
// main() から初回フレーム描画までの各処理の所要時間。
// ログは debug でしか出ず、この端末では debug が JIT で起動できないため、
// 永続化した計測結果をここに出す。
//
class _StartupTraceBlock extends StatelessWidget {
  const _StartupTraceBlock({required this.colors, required this.typo});

  final AppColors colors;
  final AppTypography typo;

  @override
  Widget build(BuildContext context) {
    final StartupTraceReport? report = StartupTrace.read();
    if (report == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: colors.line)),
        child: Text(
          'STARTUP TRACE: not recorded yet',
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 9,
            letterSpacing: 9 * 0.2,
            color: colors.accentWarn,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border.all(color: colors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'STARTUP TRACE (slowest first)',
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 9,
              letterSpacing: 9 * 0.2,
              color: colors.fgMuted,
            ),
          ),
          const SizedBox(height: 12),
          for (final MapEntry<String, int> e in report.slowestFirst)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      e.key,
                      style: typo.metaSmall.copyWith(color: colors.fgMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${e.value} ms',
                    style: typo.bodyMedium.copyWith(
                      // 100ms 以上は目立たせる
                      color: e.value >= 100 ? colors.accentDanger : colors.fg,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: Text('FIRST FRAME',
                    style: typo.metaSmall.copyWith(color: colors.fg)),
              ),
              Text(
                report.firstFrameMs == null
                    ? '—'
                    : '${report.firstFrameMs} ms',
                style: typo.bodyMedium,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
