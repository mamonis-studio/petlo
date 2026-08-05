// ============================================================================
// petlo - Database Migrations
// ============================================================================
//
// driftスキーマバージョンとマイグレーション処理を集約 (rev5.4 F-73)。
//
// ルール:
//   - schemaVersion を1から開始
//   - 破壊的変更は禁止 (ユーザーデータ消失 = 致命的)
//   - カラム追加: ALTER TABLE ADD COLUMN ...
//   - 段階的マイグレーション: 1→2→3 を順に実行
//
// 使い方: AppDatabase.migration を MigrationStrategy として使う
//
// ============================================================================

import 'package:drift/drift.dart';

abstract final class AppDatabaseMigrations {
  AppDatabaseMigrations._();

  /// 現在のスキーマバージョン
  /// v2: schedules テーブル追加 (build 5)
  /// v3: ai_chat_messages.image_path カラム追加 (build 15)
  /// v4: sync_queue 拡張 (op_id / group_id / client_timestamp) (build 19)
  /// v5: pets.sex を nullable 化 (build 22)
  /// v6: pet_scopes テーブル追加 + 既存 pets を 1:1 backfill (build 43, Phase G1)
  /// v7: schedules.times / weekdays_bits カラム追加 + medication_reminders
  ///     から schedules への 1:1 データ移行 (build 47b, Scope B1/B2)
  /// v8: medication_reminders テーブル DROP (build 49, Scope C1)
  /// v9: Decision D 純粋実装 (build 57)。
  ///     全ペットに Personal scope を必ず常在させる。
  ///     - 既存 pets で Personal scope が無いものに backfill
  ///     - 既存 non-Personal primary scope は is_primary=0 へ降格
  ///       (1 ペット 1 primary 不変条件を維持、Personal を canonical primary に)
  ///     schema 変更なし、データ追加・更新のみ。
  /// v10: 予防コース機能 (build 72)。
  ///      prevention_courses / prevention_doses を新規作成。
  ///      既存テーブル・既存データへの変更は一切なし。純粋な追加のみ。
  static const int currentVersion = 10;

  /// 新規インストール時の onCreate
  static Future<void> onCreate(Migrator m) async {
    await m.createAll();
  }

  /// バージョン間マイグレーション。
  /// テーブル参照が必要な処理は AppDatabase 側の closure で対応するため
  /// ここではバージョン分岐の枠だけ持つ。
  /// (build 5: schedules テーブル追加は AppDatabase の migration getter 内で実施)
  static Future<void> onUpgrade(
    Migrator m,
    int from,
    int to,
  ) async {
    // ノーオペ。バージョン別の処理は AppDatabase.migration で実行。
  }
}
