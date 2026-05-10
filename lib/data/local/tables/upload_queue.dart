// ============================================================================
// petlo - Upload Queue Table
// ============================================================================
//
// 写真・AI画像診断画像のアップロードキュー (rev5.4)。
//
// rev5.4仕様:
//   - upload_queue がpending状態の写真は自動バックアップに含める
//     (R2未アップロード時の保険、機種変時のデータ消失防止)
//   - kind: photo (通常写真) / ai_image_diagnosis (AI診断用画像)
//
// ============================================================================

import 'package:drift/drift.dart';

import '../database_converters.dart';
import '../database_enums.dart';

@DataClassName('UploadQueueItemEntity')
class UploadQueue extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// アップロード種別
  TextColumn get kind =>
      text().map(const AppEnumConverter(UploadKind.values))();

  /// ローカル画像パス (相対)
  TextColumn get localPath => text()();

  /// R2の予定キー (アップロード成功後にレコードのr2_keyに反映)
  TextColumn get r2Key => text()();

  /// 関連レコードのテーブル名 (例: "meals", "poops")
  TextColumn get relatedTableName => text()();

  /// 関連レコードのローカルID
  IntColumn get relatedRecordId => integer()();

  /// 試行回数
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// 最終エラー
  TextColumn get lastError => text().nullable()();

  /// キューに積まれた日時 (UTC msec)
  IntColumn get queuedAt => integer()();

  /// 最終試行日時 (UTC msec)
  IntColumn get lastAttemptAt => integer().nullable()();
}
