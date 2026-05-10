// ============================================================================
// petlo - Account Deletion Queue Table
// ============================================================================
//
// アカウント削除リクエストのキュー (rev3で確定)。
//
// 設計:
//   - リクエスト時: 即座にAI画像診断のR2画像を削除 (rev5.4 GDPR配慮)
//   - 30日間は復元可能 (誤操作対策)
//   - 30日後にCron Triggerで物理削除
//   - ローカルDBの全データもキャンセル可能期間中はそのまま保持
//
// ============================================================================

import 'package:drift/drift.dart';

@DataClassName('AccountDeletionQueueEntity')
class AccountDeletionQueue extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// ユーザーID
  TextColumn get userId => text()();

  /// 削除リクエスト日時 (UTC msec)
  IntColumn get requestedAt => integer()();

  /// 物理削除予定日時 (UTC msec、requestedAt + 30日)
  IntColumn get scheduledForDeletionAt => integer()();

  /// キャンセル済み (誤操作で復元した場合)
  BoolColumn get cancelled => boolean().withDefault(const Constant(false))();

  /// キャンセル日時 (UTC msec)
  IntColumn get cancelledAt => integer().nullable()();

  /// AI画像診断R2画像の即時削除完了済み (rev5.4)
  BoolColumn get r2ImagesPurged => boolean().withDefault(const Constant(false))();
}
