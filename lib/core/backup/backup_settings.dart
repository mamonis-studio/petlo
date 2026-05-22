// ============================================================================
// petlo - Backup Settings Model
// ============================================================================
//
// 自動バックアップの設定状態。
//
// rev3 + rev5.5 F-79: バックアップOFF + 記録100件以上で警告バナー
//
// 状態遷移:
//   - off → setupInProgress → on (ユーザーが有効化)
//   - on → off (ユーザーが無効化)
//   - on → error (バックアップ失敗時、通知 + 設定画面で要対応)
//
// プロバイダ:
//   - iOS: iCloud Drive
//   - Android: Google Drive
//   - 将来: Cloudflare R2 経由(プラットフォーム共通の暗号化バックアップ)
//
// v1.0: 設定永続化 + UI のみ実装、実際のクラウド連携は v1.1 で本実装
//
// ============================================================================

import 'package:flutter/foundation.dart';

import '../../l10n/generated/app_localizations.dart';

/// バックアップの状態
enum BackupState {
  /// 無効
  off,

  /// 有効
  on,

  /// 設定中(認証フロー中等)
  setupInProgress,

  /// エラー(直近のバックアップ失敗)
  error;

  String get name {
    switch (this) {
      case BackupState.off:
        return 'off';
      case BackupState.on:
        return 'on';
      case BackupState.setupInProgress:
        return 'setup';
      case BackupState.error:
        return 'error';
    }
  }

  static BackupState fromString(String? s) {
    switch (s) {
      case 'on':
        return BackupState.on;
      case 'setup':
        return BackupState.setupInProgress;
      case 'error':
        return BackupState.error;
      case 'off':
      default:
        return BackupState.off;
    }
  }
}

/// バックアップのプロバイダ
enum BackupProvider {
  none,
  iCloud,
  googleDrive,
  cloudflareR2; // 将来

  String get name {
    switch (this) {
      case BackupProvider.none:
        return 'none';
      case BackupProvider.iCloud:
        return 'iCloud';
      case BackupProvider.googleDrive:
        return 'googleDrive';
      case BackupProvider.cloudflareR2:
        return 'cloudflareR2';
    }
  }

  /// build 39: l10n を受け取り、`none` ケースだけ翻訳。固有名詞ストア名はそのまま。
  String displayLabel(AppLocalizations l10n) {
    switch (this) {
      case BackupProvider.none:
        return l10n.backup_provider_unset;
      case BackupProvider.iCloud:
        return 'iCloud Drive';
      case BackupProvider.googleDrive:
        return 'Google Drive';
      case BackupProvider.cloudflareR2:
        return 'petlo Cloud';
    }
  }

  static BackupProvider fromString(String? s) {
    switch (s) {
      case 'iCloud':
        return BackupProvider.iCloud;
      case 'googleDrive':
        return BackupProvider.googleDrive;
      case 'cloudflareR2':
        return BackupProvider.cloudflareR2;
      case 'none':
      default:
        return BackupProvider.none;
    }
  }
}

@immutable
class BackupSettings {
  const BackupSettings({
    required this.state,
    required this.provider,
    this.lastSuccessAt,
    this.lastErrorMessage,
    this.remindLaterAt,
  });

  final BackupState state;
  final BackupProvider provider;

  /// 最後にバックアップが成功した日時 (UI 表示用)
  final DateTime? lastSuccessAt;

  /// 最後のエラーメッセージ (state=error の時)
  final String? lastErrorMessage;

  /// "Remind me later" を押した日時 (F-79 の30日カウンター用)
  final DateTime? remindLaterAt;

  /// 完全に OFF 状態の初期値
  static const BackupSettings off = BackupSettings(
    state: BackupState.off,
    provider: BackupProvider.none,
  );

  /// バックアップが有効か
  bool get isOn => state == BackupState.on;

  /// 警告バナーを「Remind me later」で抑止中か
  bool get isRemindLaterActive {
    if (remindLaterAt == null) return false;
    final Duration since = DateTime.now().difference(remindLaterAt!);
    return since.inDays < 30;
  }

  /// 最後の成功からの経過日数 (null は未バックアップ)
  int? get daysSinceLastSuccess {
    if (lastSuccessAt == null) return null;
    return DateTime.now().difference(lastSuccessAt!).inDays;
  }

  Map<String, String?> toMap() {
    return <String, String?>{
      'state': state.name,
      'provider': provider.name,
      'lastSuccessAt': lastSuccessAt?.toIso8601String(),
      'lastErrorMessage': lastErrorMessage,
      'remindLaterAt': remindLaterAt?.toIso8601String(),
    };
  }

  static BackupSettings fromMap(Map<String, String?> map) {
    return BackupSettings(
      state: BackupState.fromString(map['state']),
      provider: BackupProvider.fromString(map['provider']),
      lastSuccessAt: map['lastSuccessAt'] == null
          ? null
          : DateTime.tryParse(map['lastSuccessAt']!),
      lastErrorMessage: map['lastErrorMessage'],
      remindLaterAt: map['remindLaterAt'] == null
          ? null
          : DateTime.tryParse(map['remindLaterAt']!),
    );
  }

  BackupSettings copyWith({
    BackupState? state,
    BackupProvider? provider,
    Object? lastSuccessAt = _sentinel,
    Object? lastErrorMessage = _sentinel,
    Object? remindLaterAt = _sentinel,
  }) {
    return BackupSettings(
      state: state ?? this.state,
      provider: provider ?? this.provider,
      lastSuccessAt: lastSuccessAt == _sentinel
          ? this.lastSuccessAt
          : lastSuccessAt as DateTime?,
      lastErrorMessage: lastErrorMessage == _sentinel
          ? this.lastErrorMessage
          : lastErrorMessage as String?,
      remindLaterAt: remindLaterAt == _sentinel
          ? this.remindLaterAt
          : remindLaterAt as DateTime?,
    );
  }

  static const Object _sentinel = Object();
}
