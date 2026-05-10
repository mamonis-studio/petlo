// ============================================================================
// petlo - Group Members Repository
// ============================================================================
//
// グループメンバー(自分以外)のローカルキャッシュ管理。
//
// rev5.3 F-29: メンバー一覧 / F-29a 権限変更 / F-29b 除名
//
// 設計:
//   - サーバーから定期 sync で取得した結果をキャッシュ
//   - 表示用 Stream + 個別取得 Future
//   - upsert は groupRemoteId + userId 複合 一意性保証
//
// ============================================================================

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_enums.dart';
import 'base_repository.dart';

class GroupMembersRepository extends BaseRepository {
  GroupMembersRepository(super.db);

  // ============================================================================
  // Read
  // ============================================================================

  /// 指定グループの全メンバー(自分以外)を表示順で
  Stream<List<GroupMemberEntity>> watchMembersForGroup(
      String groupRemoteId) {
    final query = db.select(db.groupMembers)
      ..where((GroupMembers t) =>
          t.groupRemoteId.equals(groupRemoteId))
      ..orderBy(<OrderClauseGenerator<GroupMembers>>[
        // Owner → Editor → Viewer の順
        (GroupMembers t) => OrderingTerm(expression: t.permission),
        (GroupMembers t) => OrderingTerm(expression: t.joinedAt),
      ]);
    return query.watch();
  }

  /// 単一メンバー取得
  Future<GroupMemberEntity?> getMember({
    required String groupRemoteId,
    required String userId,
  }) {
    return (db.select(db.groupMembers)
          ..where((GroupMembers t) =>
              t.groupRemoteId.equals(groupRemoteId) &
              t.userId.equals(userId))
          ..limit(1))
        .getSingleOrNull();
  }

  /// 指定グループのメンバー数(自分含めて欲しい場合は +1 する)
  Future<int> countMembersForGroup(String groupRemoteId) async {
    final Expression<int> cnt = db.groupMembers.id.count();
    final query = db.selectOnly(db.groupMembers)
      ..addColumns(<Expression<Object>>[cnt])
      ..where(db.groupMembers.groupRemoteId.equals(groupRemoteId));
    final res = await query.getSingle();
    return res.read(cnt) ?? 0;
  }

  // ============================================================================
  // Write — Local cache update (sync後に呼ばれる)
  // ============================================================================

  /// サーバーから受け取ったメンバー情報を upsert
  Future<void> upsertMember({
    required String groupRemoteId,
    required String userId,
    required String displayName,
    String? avatarLabel,
    required MemberPermission permission,
    required int joinedAt,
    int? lastActiveAt,
  }) async {
    final int t = now();
    final GroupMemberEntity? existing = await getMember(
      groupRemoteId: groupRemoteId,
      userId: userId,
    );

    if (existing == null) {
      await db.into(db.groupMembers).insert(
            GroupMembersCompanion.insert(
              groupRemoteId: groupRemoteId,
              userId: userId,
              displayName: displayName,
              avatarLabel: Value(avatarLabel),
              permission: permission,
              joinedAt: joinedAt,
              lastActiveAt: Value(lastActiveAt),
              updatedAt: t,
            ),
          );
    } else {
      await (db.update(db.groupMembers)
            ..where((GroupMembers tbl) => tbl.id.equals(existing.id)))
          .write(GroupMembersCompanion(
        displayName: Value(displayName),
        avatarLabel: Value(avatarLabel),
        permission: Value(permission),
        lastActiveAt: Value(lastActiveAt),
        updatedAt: Value(t),
      ));
    }
  }

  /// メンバーを除名 (ローカル削除のみ、サーバー側削除は GroupApiService)
  Future<void> removeMemberLocally({
    required String groupRemoteId,
    required String userId,
  }) async {
    await (db.delete(db.groupMembers)
          ..where((GroupMembers t) =>
              t.groupRemoteId.equals(groupRemoteId) &
              t.userId.equals(userId)))
        .go();
  }

  /// グループ全体のメンバーをローカルから削除 (グループ退出時)
  Future<void> deleteAllForGroup(String groupRemoteId) async {
    await (db.delete(db.groupMembers)
          ..where((GroupMembers t) =>
              t.groupRemoteId.equals(groupRemoteId)))
        .go();
  }
}
