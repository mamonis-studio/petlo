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
  static const int currentVersion = 5;

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
