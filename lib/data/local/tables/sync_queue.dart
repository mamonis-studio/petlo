// ============================================================================
// petlo - Sync Queue Table
// ============================================================================
//
// 同期待ちレコードのキュー。
//
// オフライン時の編集 → ローカル DB に反映 → sync_queue に積む
// → オンライン復帰時 → 順次 push して accepted を削除。
//
// rev5.5: 同期間隔120秒 ± 30秒ジッター
// 失敗時はリトライ、3回失敗で警告フラグ。
//
// build 19: 同期エンジン phase 2 のため次のカラムを追加。
//   - opId          冪等性キー (クライアント生成 UUID)
//   - groupId       backend 経路特定用 (enqueue 時の値で固定)
//   - clientTimestamp LWW 比較用 (entity の lastModifiedAtClient/now())
//
// payload カラムは互換性のため残しているが、push 時には
// (targetTable, recordId) でローカル行を再読み込みして送る方針なので
// 中身は使われない。
//
// ============================================================================

import 'package:drift/drift.dart';

import '../database_converters.dart';
import '../database_enums.dart';

@DataClassName('SyncQueueItemEntity')
class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 冪等性キー (UUID v4)。retry 時にも同じ値を送ることで多重適用を防ぐ。
  TextColumn get opId => text()();

  /// 操作種別
  TextColumn get operation =>
      text().map(const AppEnumConverter(SyncOperation.values))();

  /// 対象テーブル名 (例: "pets", "meals", "poops")
  /// drift の `Table.tableName` getter と衝突するため `targetTable` という名前にしている。
  /// DB 上のカラム名は `target_table`。
  TextColumn get targetTable => text()();

  /// ローカルレコードID
  IntColumn get recordId => integer()();

  /// 所属グループ (enqueue 時に確定、entity が後で別グループに移動しても
  /// この op はもとのグループへ送る)。
  TextColumn get groupId => text()();

  /// LWW 比較用クライアント時刻 (UTC msec)。
  IntColumn get clientTimestamp => integer()();

  /// 送信ペイロード (互換、build 19 以降は未使用)
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
