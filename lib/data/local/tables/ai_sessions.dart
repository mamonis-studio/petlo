// ============================================================================
// petlo - AI Sessions Table
// ============================================================================
//
// AIセッション (rev5.1: F-22 AIセッション内文脈保持)。
//
// 仕様:
//   - 直近5往復、30分間文脈保持
//   - サーバーKVに会話履歴、ローカルにはメタ情報のみ
//   - rev5.5: pet_id NOT NULL
//
// セッション継続条件:
//   - 同じペットID
//   - 30分以内の活動
//
// ============================================================================

import 'package:drift/drift.dart';

@DataClassName('AiSessionEntity')
class AiSessions extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// サーバー側セッションID (UUID)
  TextColumn get remoteId => text().unique()();

  /// 所属スコープ
  TextColumn get groupId => text().withDefault(const Constant('personal'))();

  /// ペットID (rev5.5: NOT NULL)
  IntColumn get petId => integer()();

  /// セッション開始日時 (UTC msec)
  IntColumn get startedAt => integer()();

  /// 最終アクティブ日時 (UTC msec、30分超えで自動終了)
  IntColumn get lastActiveAt => integer()();

  /// メッセージ数
  IntColumn get messageCount => integer().withDefault(const Constant(0))();

  /// セッションタイトル (最初のメッセージから自動生成)
  TextColumn get title => text().nullable()();

  IntColumn get createdAt => integer()();
}
