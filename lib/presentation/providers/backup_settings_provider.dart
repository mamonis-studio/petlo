// ============================================================================
// petlo - Backup Settings Provider
// ============================================================================
//
// バックアップ設定のリアクティブ管理 + F-79 警告バナー表示判定。
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backup/backup_settings.dart';
import '../../core/preferences/user_preferences.dart';
import '../../core/utils/logger.dart';
import 'database_provider.dart';

// ============================================================================
// Settings (Notifier)
// ============================================================================
final NotifierProvider<BackupSettingsNotifier, BackupSettings>
    backupSettingsProvider =
    NotifierProvider<BackupSettingsNotifier, BackupSettings>(
  BackupSettingsNotifier.new,
);

class BackupSettingsNotifier extends Notifier<BackupSettings> {
  @override
  BackupSettings build() {
    return UserPreferences.instance.backupSettings;
  }

  Future<void> updateSettings(BackupSettings next) async {
    state = next;
    await UserPreferences.instance.setBackupSettings(next);
  }

  /// バックアップを有効化(プラットフォーム別の認証フローはこの中で行う想定)
  /// v1.0 ではプレースホルダ実装、UI 確認用
  Future<bool> enableBackup(BackupProvider provider) async {
    state = state.copyWith(
      state: BackupState.setupInProgress,
      provider: provider,
    );
    await UserPreferences.instance.setBackupSettings(state);

    // TODO(backup): 実際のクラウド連携実装は v1.1
    //   - iOS: NSUbiquitousKeyValueStore + iCloud Drive API
    //   - Android: Google Drive REST API + OAuth
    //   - 共通: Cloudflare R2 経由(暗号化バックアップ)
    // v1.0 はプレースホルダで擬似的に成功させる(UI 動作確認用)
    await Future<void>.delayed(const Duration(milliseconds: 800));

    final BackupSettings next = BackupSettings(
      state: BackupState.on,
      provider: provider,
      lastSuccessAt: DateTime.now(),
      remindLaterAt: null, // 有効化したら警告バナーは消す
    );
    state = next;
    await UserPreferences.instance.setBackupSettings(next);
    return true;
  }

  /// バックアップを無効化
  Future<void> disableBackup() async {
    final BackupSettings next = BackupSettings.off.copyWith(
      remindLaterAt: state.remindLaterAt, // 抑止状態は維持
    );
    state = next;
    await UserPreferences.instance.setBackupSettings(next);
  }

  /// "Remind me later" — 30日間警告バナーを抑止
  Future<void> remindLater() async {
    final BackupSettings next =
        state.copyWith(remindLaterAt: DateTime.now());
    state = next;
    await UserPreferences.instance.setBackupSettings(next);
  }

  /// 手動で「今すぐバックアップ」
  /// v1.0 ではプレースホルダ
  Future<bool> backupNow() async {
    if (state.state != BackupState.on) return false;

    // TODO(backup): 実装時はクラウドに sqlite ダンプ + 暗号化を upload
    try {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final BackupSettings next = state.copyWith(
        lastSuccessAt: DateTime.now(),
        lastErrorMessage: null,
      );
      state = next;
      await UserPreferences.instance.setBackupSettings(next);
      return true;
    } catch (e) {
      PetloLogger.instance.d('backupNow failed: $e');
      final BackupSettings next = state.copyWith(
        state: BackupState.error,
        lastErrorMessage: e.toString(),
      );
      state = next;
      await UserPreferences.instance.setBackupSettings(next);
      return false;
    }
  }
}

// ============================================================================
// 派生 Provider: 警告バナー表示判定 (F-79)
// ============================================================================

/// 全記録の総数(meals + poops + pees + vomits + visits + diaries 等)
/// F-79 の閾値判定 (>=100件) 用に簡易集計
final FutureProvider<int> totalRecordCountProvider =
    FutureProvider<int>(
  (Ref ref) async {
    try {
      final db = ref.watch(appDatabaseProvider);
      // 各テーブルから簡易 count
      Future<int> _count(Future<int> Function() future) async {
        try {
          return await future();
        } catch (_) {
          return 0;
        }
      }

      final List<int> counts = await Future.wait<int>(<Future<int>>[
        db.select(db.meals).get().then((l) => l.length),
        db.select(db.poops).get().then((l) => l.length),
        db.select(db.pees).get().then((l) => l.length),
        db.select(db.vomits).get().then((l) => l.length),
        db.select(db.visits).get().then((l) => l.length),
        db.select(db.diaries).get().then((l) => l.length),
        db.select(db.weights).get().then((l) => l.length),
      ]);
      return counts.fold<int>(0, (int a, int b) => a + b);
    } catch (e) {
      PetloLogger.instance.d('totalRecordCount failed: $e');
      return 0;
    }
  },
);

/// 通院記録の数 (F-79 の閾値の片方: visits >= 5)
final FutureProvider<int> visitsCountProvider = FutureProvider<int>(
  (Ref ref) async {
    try {
      final db = ref.watch(appDatabaseProvider);
      return (await db.select(db.visits).get()).length;
    } catch (_) {
      return 0;
    }
  },
);

/// F-79: バックアップ警告バナーを表示するか判定
///
/// 条件 (rev5.5):
///   1. 自動バックアップが OFF
///   2. ローカル記録 ≥ 100件 OR 通院記録 ≥ 5件
///   3. 過去30日以内に "Remind me later" していない
///
final Provider<bool> shouldShowBackupBannerProvider = Provider<bool>(
  (Ref ref) {
    final BackupSettings settings = ref.watch(backupSettingsProvider);
    if (settings.isOn) return false;
    if (settings.isRemindLaterActive) return false;

    final AsyncValue<int> total = ref.watch(totalRecordCountProvider);
    final AsyncValue<int> visits = ref.watch(visitsCountProvider);

    final int t = total.maybeWhen(data: (v) => v, orElse: () => 0);
    final int v = visits.maybeWhen(data: (v) => v, orElse: () => 0);

    return t >= 100 || v >= 5;
  },
);
