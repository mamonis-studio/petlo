// ============================================================================
// petlo - AI Chat Repository
// ============================================================================
//
// AI相談チャット用 Repository。メッセージ + セッション両方を扱う。
//
// rev3 F-18: AI相談チャット
// rev5.5: 500文字制限はAiServiceで先にバリデート
//
// 設計:
//   - メッセージは chronological(古い順)で取得 → ChatScreen で素直に並べる
//   - セッション継続条件: 同じペットID + 30分以内の活動
//   - サーバー側 ID (remoteId/sessionId) は AiService が払い出してから insert
//
// ============================================================================

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_enums.dart';
import '../storage/photo_storage.dart';
import 'base_repository.dart';

class AiChatRepository extends BaseRepository {
  AiChatRepository(super.db);

  // ==========================================================================
  // Sessions
  // ==========================================================================

  /// 現在ペットの最新セッション (30分以内なら継続)
  Future<AiSessionEntity?> getActiveSessionForPet(int petId) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int thirtyMinAgo = now - 30 * 60 * 1000;

    final query = db.select(db.aiSessions)
      ..where((AiSessions t) =>
          t.petId.equals(petId) &
          t.lastActiveAt.isBiggerOrEqualValue(thirtyMinAgo))
      ..orderBy(<OrderClauseGenerator<AiSessions>>[
        (AiSessions t) =>
            OrderingTerm(expression: t.lastActiveAt, mode: OrderingMode.desc),
      ])
      ..limit(1);
    return query.getSingleOrNull();
  }

  /// 新しいセッション作成 (サーバー側で発行された UUID 必須)
  Future<int> createSession({
    required String remoteId,
    required int petId,
    required String groupId,
  }) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    return db.into(db.aiSessions).insert(
          AiSessionsCompanion.insert(
            remoteId: remoteId,
            petId: petId,
            groupId: Value(groupId),
            startedAt: now,
            lastActiveAt: now,
            createdAt: now,
          ),
        );
  }

  /// セッションの活動時刻を更新 (継続中なので now に)
  Future<void> touchSession(String remoteId) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    await (db.update(db.aiSessions)
          ..where((AiSessions t) => t.remoteId.equals(remoteId)))
        .write(AiSessionsCompanion(lastActiveAt: Value(now)));
  }

  // ==========================================================================
  // Messages
  // ==========================================================================

  /// セッションのメッセージ一覧 (古い順)
  Stream<List<AiChatMessageEntity>> watchMessagesForSession(String sessionId) {
    final query = db.select(db.aiChatMessages)
      ..where(
          (AiChatMessages t) => t.sessionId.equals(sessionId))
      ..orderBy(<OrderClauseGenerator<AiChatMessages>>[
        (AiChatMessages t) =>
            OrderingTerm(expression: t.sentAt, mode: OrderingMode.asc),
      ]);
    return query.watch();
  }

  /// 現在ペットの全メッセージ (履歴一覧画面用、新しい順)
  Stream<List<AiChatMessageEntity>> watchMessagesForPet(
    int petId, {
    int limit = 50,
  }) {
    final query = db.select(db.aiChatMessages)
      ..where((AiChatMessages t) => t.petId.equals(petId))
      ..orderBy(<OrderClauseGenerator<AiChatMessages>>[
        (AiChatMessages t) =>
            OrderingTerm(expression: t.sentAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return query.watch();
  }

  /// 月内メッセージ数 (Pro 月100回制限の判定用、user role のみカウント)
  Future<int> countUserMessagesInMonth({
    required String groupId,
    required int year,
    required int month,
  }) async {
    final DateTime first = DateTime(year, month, 1);
    final DateTime nextMonth = DateTime(year, month + 1, 1);
    final int from = first.toUtc().millisecondsSinceEpoch;
    final int to = nextMonth.toUtc().millisecondsSinceEpoch;

    final Expression<int> cnt = db.aiChatMessages.id.count();
    final query = db.selectOnly(db.aiChatMessages)
      ..addColumns(<Expression<Object>>[cnt])
      ..where(db.aiChatMessages.role.equalsValue(AiMessageRole.user) &
          db.aiChatMessages.sentAt.isBetweenValues(from, to));
    final res = await query.getSingle();
    return res.read(cnt) ?? 0;
  }

  /// メッセージ追加
  Future<int> addMessage({
    required String sessionId,
    required int petId,
    required AiMessageRole role,
    required String content,
    String? remoteId,
    SyncStatus syncStatus = SyncStatus.synced,
    String? imagePath,
  }) async {
    assertRelativePhotoPath(imagePath);
    final int now = DateTime.now().millisecondsSinceEpoch;
    return db.into(db.aiChatMessages).insert(
          AiChatMessagesCompanion.insert(
            remoteId: Value(remoteId),
            sessionId: sessionId,
            petId: petId,
            role: role,
            content: content,
            sentAt: now,
            syncStatus: Value(syncStatus),
            imagePath: Value(imagePath),
            createdAt: now,
          ),
        );
  }

  /// レーティング更新 (👍/👎)
  Future<bool> setRating({
    required int messageId,
    required AiFeedback rating,
  }) async {
    final int rows = await (db.update(db.aiChatMessages)
          ..where((AiChatMessages t) => t.id.equals(messageId)))
        .write(AiChatMessagesCompanion(rating: Value(rating)));
    return rows > 0;
  }

  /// メッセージ単体取得
  Future<AiChatMessageEntity?> getMessageById(int id) {
    return (db.select(db.aiChatMessages)
          ..where((AiChatMessages t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
  }
}
