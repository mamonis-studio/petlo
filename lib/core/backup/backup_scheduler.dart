// ============================================================================
// petlo - Backup Scheduler (build 68)
// ============================================================================
//
// アプリのライフサイクル `resumed` で `maybeRunCloudBackup` が呼ばれ、
// 「自動バックアップが許可」「Pro」「Apple 連携済」「オンライン」「前回から
// 24h 以上」の全条件が揃った時だけ fire-and-forget でクラウドへ送る。
//
// 失敗は warn ログだけ。UI を一切ブロックしない (snackbar も出さない)。
// 多重起動防止のためモジュール private な `_running` フラグを使う。
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/providers/auth_provider.dart';
import '../../presentation/providers/backup_settings_provider.dart';
import '../../presentation/providers/connectivity_provider.dart';
import '../../presentation/providers/database_provider.dart';
import '../../presentation/providers/pro_status_provider.dart';
import '../auth/auth_service.dart';
import '../utils/logger.dart';
import 'backup_archive_service.dart';
import 'backup_settings.dart';

class BackupScheduler {
  BackupScheduler._();

  /// 24 時間。ARB / Pref キーには直接埋めずに定数として置く。
  static const Duration _minInterval = Duration(hours: 24);

  /// 多重起動防止用フラグ。Future が解決するまで他の呼び出しを skip。
  static bool _running = false;

  /// 必要条件を全て満たすときだけクラウドへバックアップを送る。
  /// ライフサイクル `resumed` で呼ばれる前提。fire-and-forget で呼び出し側は
  /// 戻り値を待たない。失敗は静かに log warning。
  static Future<void> maybeRunCloudBackup(WidgetRef ref) async {
    if (_running) return;

    // === ゲート確認 ===
    final BackupSettings settings = ref.read(backupSettingsProvider);
    if (!settings.cloudBackupAutoEnabled) return;

    final bool isPro = ref.read(isProProvider);
    if (!isPro) return;

    final AuthStatus authStatus = ref.read(authStatusProvider);
    if (authStatus != AuthStatus.appleLinked) return;

    final bool isOnline = ref.read(isOnlineSnapshotProvider);
    if (!isOnline) return;

    final Duration? since = settings.sinceLastCloudBackup;
    if (since != null && since < _minInterval) return;

    // === 実行 ===
    _running = true;
    try {
      PetloLogger.instance.i(
        'auto cloud backup: starting '
        '(sinceLast=${since?.inHours ?? -1}h)',
      );
      final BackupArchiveService service =
          BackupArchiveService(ref.read(appDatabaseProvider));
      final BackupCloudUploadResult result = await service.uploadToCloud();
      await ref.read(backupSettingsProvider.notifier).markCloudBackupCompleted(
            at: result.completedAt,
            byteSize: result.byteSize,
          );
      PetloLogger.instance.i(
        'auto cloud backup: succeeded (${result.byteSize} bytes)',
      );
    } catch (e, st) {
      // ネットワーク / R2 エラー等。UI には出さず、次の resumed に再試行を委ねる。
      PetloLogger.instance.w(
        'auto cloud backup failed',
        error: e,
        stackTrace: st,
      );
    } finally {
      _running = false;
    }
  }
}
