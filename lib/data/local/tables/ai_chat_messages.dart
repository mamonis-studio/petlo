// ============================================================================
// petlo - AI Chat Messages Table
// ============================================================================
//
// AI相談チャットの会話履歴 (rev5.1: F-18)。
//
// rev5.5仕様:
//   - pet_id NOT NULL (ペットコンテキスト混入防止のため必ず特定)
//   - content 500文字制限 (プロンプトインジェクション対策、クライアント側でも検証)
//   - role enum で user/assistant/system を区別
//   - rating で👍/👎評価
//
// ============================================================================

import 'package:drift/drift.dart';

import '../database_converters.dart';
import '../database_enums.dart';

@DataClassName('AiChatMessageEntity')
class AiChatMessages extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// サーバー側ID (UUID、rev5.3: フィードバック検証用にmessage_id必要)
  TextColumn get remoteId => text().nullable()();

  /// セッションID (ai_sessions.remoteId へのFK)
  TextColumn get sessionId => text()();

  /// ペットID (rev5.5: NOT NULL)
  IntColumn get petId => integer()();

  /// メッセージの送信者
  TextColumn get role =>
      text().map(const AppEnumConverter(AiMessageRole.values))();

  /// 本文 (rev5.5: 500文字制限はクライアント側で検証)
  TextColumn get content => text()();

  /// 送信日時 (UTC msec)
  IntColumn get sentAt => integer()();

  /// フィードバック評価
  TextColumn get rating => text()
      .map(const AppEnumConverter(AiFeedback.values))
      .withDefault(const Constant('none'))();

  /// 同期状態 (送信中、送信成功などのトラッキング)
  TextColumn get syncStatus => text()
      .map(const AppEnumConverter(SyncStatus.values))
      .withDefault(const Constant('synced'))();

  IntColumn get createdAt => integer()();
}
