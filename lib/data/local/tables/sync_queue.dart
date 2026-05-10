// ============================================================================
// petlo - Sync Queue Table
// ============================================================================
//
// 同期待ちレコードのキュー。
//
// オフライン時の編集 → ローカルDBに反映 → sync_queueに積む
// → オンライン復帰時 → 順次pushしてsynced
//
// rev5.5: 同期間隔120秒 ± 30秒ジッター
// 失敗時はリトライ、3回失敗で警告フラグ。
//
// ============================================================================

import 'package:drift/drift.dart';

import '../database_converters.dart';
import '../database_enums.dart';

@DataClassName('SyncQueueItemEntity')
class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 操作種別
  TextColumn get operation =>
      text().map(const AppEnumConverter(SyncOperation.values))();

  /// 対象テーブル名 (例: "pets", "meals", "poops")
  /// drift の `Table.tableName` getter と衝突するため `targetTable` という名前にしている。
  /// DB 上のカラム名は `target_table`。
  TextColumn get targetTable => text()();

  /// ローカルレコードID
  IntColumn get recordId => integer()();

  /// 送信ペイロード (JSON文字列)
  TextColumn get payload => text()();

  /// 試行回数
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// 最終エラーメッセージ
  TextColumn get lastError => text().nullable()();

  /// キューに積まれた日時 (UTC msec)
  IntColumn get queuedAt => integer()();

  /// 最終試行日時 (UTC msec)
  IntColumn get lastAttemptAt => integer().nullable()();
}
