// ============================================================================
// petlo - Backup Settings Model
// ============================================================================
//
// build 62 でクラウド連携プレースホルダを廃止し、ローカル ZIP エクスポートへ
// 移行。
// build 68 で R2 への「個人クラウドバックアップ」を追加 — モデルに
// lastCloudBackupAt / cloudBackupByteSize / cloudBackupAutoEnabled を追加し、
// SharedPreferences に永続化する。
//
// ============================================================================

import 'package:flutter/foundation.dart';

@immutable
class BackupSettings {
  const BackupSettings({
    this.lastExportAt,
    this.remindLaterAt,
    this.lastCloudBackupAt,
    this.cloudBackupByteSize,
    this.cloudBackupAutoEnabled = true,
  });

  /// 最後に手動エクスポートが成功した日時 (なければ未エクスポート)。
  final DateTime? lastExportAt;

  /// 「あとで」リマインダー抑止日時 (なければ抑止していない)。
  /// 30 日間バナーを抑止する F-79 のセマンティクス互換。
  final DateTime? remindLaterAt;

  /// build 68: 最後にクラウド (R2) バックアップが成功した日時 (なければ未送信)。
  final DateTime? lastCloudBackupAt;

  /// build 68: 最後にクラウドへ送った ZIP のバイト数 (なければ未送信)。
  final int? cloudBackupByteSize;

  /// build 68: 自動クラウドバックアップを許可するか。デフォルト true。
  /// false にした場合、BackupScheduler は ライフサイクル resumed 経由の
  /// 自動アップロードを skip する (手動ボタンは引き続き使える)。
  final bool cloudBackupAutoEnabled;

  /// まだ何もしていない初期値。
  static const BackupSettings initial = BackupSettings();

  /// 抑止中(過去 30 日以内に「あとで」をタップした) か。
  bool get isRemindLaterActive {
    if (remindLaterAt == null) return false;
    return DateTime.now().difference(remindLaterAt!).inDays < 30;
  }

  /// 最後のエクスポートからの経過日数 (null は未エクスポート)。
  int? get daysSinceLastExport {
    if (lastExportAt == null) return null;
    return DateTime.now().difference(lastExportAt!).inDays;
  }

  /// 最後のクラウドバックアップからの経過時間 (build 68、自動トリガ用)。
  Duration? get sinceLastCloudBackup {
    if (lastCloudBackupAt == null) return null;
    return DateTime.now().difference(lastCloudBackupAt!);
  }

  Map<String, String?> toMap() {
    return <String, String?>{
      'lastExportAt': lastExportAt?.toIso8601String(),
      'remindLaterAt': remindLaterAt?.toIso8601String(),
      'lastCloudBackupAt': lastCloudBackupAt?.toIso8601String(),
      'cloudBackupByteSize': cloudBackupByteSize?.toString(),
      'cloudBackupAutoEnabled': cloudBackupAutoEnabled ? '1' : '0',
    };
  }

  static BackupSettings fromMap(Map<String, String?> map) {
    return BackupSettings(
      lastExportAt: map['lastExportAt'] == null
          ? null
          : DateTime.tryParse(map['lastExportAt']!),
      remindLaterAt: map['remindLaterAt'] == null
          ? null
          : DateTime.tryParse(map['remindLaterAt']!),
      lastCloudBackupAt: map['lastCloudBackupAt'] == null
          ? null
          : DateTime.tryParse(map['lastCloudBackupAt']!),
      cloudBackupByteSize: map['cloudBackupByteSize'] == null
          ? null
          : int.tryParse(map['cloudBackupByteSize']!),
      // キー欠落時は build 68 デフォルトに揃える (= true)。
      cloudBackupAutoEnabled: map['cloudBackupAutoEnabled'] != '0',
    );
  }

  BackupSettings copyWith({
    Object? lastExportAt = _sentinel,
    Object? remindLaterAt = _sentinel,
    Object? lastCloudBackupAt = _sentinel,
    Object? cloudBackupByteSize = _sentinel,
    bool? cloudBackupAutoEnabled,
  }) {
    return BackupSettings(
      lastExportAt: lastExportAt == _sentinel
          ? this.lastExportAt
          : lastExportAt as DateTime?,
      remindLaterAt: remindLaterAt == _sentinel
          ? this.remindLaterAt
          : remindLaterAt as DateTime?,
      lastCloudBackupAt: lastCloudBackupAt == _sentinel
          ? this.lastCloudBackupAt
          : lastCloudBackupAt as DateTime?,
      cloudBackupByteSize: cloudBackupByteSize == _sentinel
          ? this.cloudBackupByteSize
          : cloudBackupByteSize as int?,
      cloudBackupAutoEnabled:
          cloudBackupAutoEnabled ?? this.cloudBackupAutoEnabled,
    );
  }

  static const Object _sentinel = Object();
}
