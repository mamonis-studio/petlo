// ============================================================================
// petlo - Backup Settings Provider
// ============================================================================
//
// build 62 でクラウド連携プレースホルダを撤去し、ローカル ZIP エクスポートの
// 状態管理に縮退。Notifier はエクスポート時刻の記録と「あとで」抑止のみを
// 扱う。
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backup/backup_settings.dart';
import '../../core/preferences/user_preferences.dart';

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

  /// エクスポート成功時に呼ぶ。最終エクスポート時刻を更新し、リマインダーの
  /// 抑止状態は意図して残さない(エクスポートしたなら抑止は不要)。
  Future<void> markExported({DateTime? at}) async {
    final BackupSettings next = state.copyWith(
      lastExportAt: at ?? DateTime.now(),
      remindLaterAt: null,
    );
    state = next;
    await UserPreferences.instance.setBackupSettings(next);
  }

  /// 「あとで」— 30 日間バナーを抑止する F-79 セマンティクス互換。
  Future<void> remindLater() async {
    final BackupSettings next =
        state.copyWith(remindLaterAt: DateTime.now());
    state = next;
    await UserPreferences.instance.setBackupSettings(next);
  }

  /// build 68: クラウドバックアップ成功時に呼ぶ。lastCloudBackupAt と
  /// cloudBackupByteSize を更新する。
  Future<void> markCloudBackupCompleted({
    DateTime? at,
    required int byteSize,
  }) async {
    final BackupSettings next = state.copyWith(
      lastCloudBackupAt: at ?? DateTime.now(),
      cloudBackupByteSize: byteSize,
    );
    state = next;
    await UserPreferences.instance.setBackupSettings(next);
  }

  /// build 68: 自動クラウドバックアップを有効/無効に切替。
  Future<void> setCloudBackupAutoEnabled(bool enabled) async {
    final BackupSettings next =
        state.copyWith(cloudBackupAutoEnabled: enabled);
    state = next;
    await UserPreferences.instance.setBackupSettings(next);
  }
}
