// ============================================================================
// petlo - Groups Repository
// ============================================================================
//
// グループ情報のCRUD + 権限管理。
//
// 設計:
//   - すべてのグループ(自分が参加してるもの)を取得
//   - グループ切替時に myPermission を取得して currentRoleProvider に反映
//   - rev5.4: lastActiveAt をオーナーアクティブ判定に使う
//   - rev5.5: status による段階的freeze (active/pendingDeletion/frozen/deletionScheduled)
//
// このRepositoryはサーバーAPIから定期的にpullしたデータをローカルにキャッシュする想定。
// CRUD のwrite系は Phase 4(共有実装)で本格的に使われる。
//
// ============================================================================

import 'package:drift/drift.dart';

import '../../core/constants/app_constants.dart';
import '../local/app_database.dart';
import '../local/database_enums.dart';
import 'base_repository.dart';

class GroupsRepository extends BaseRepository {
  GroupsRepository(super.db);

  // ============================================================================
  // Read
  // ============================================================================

  /// 自分が参加している全グループ (Personal は除く、active のみ)。
  /// 権限・状態すべて含む。
  Stream<List<GroupEntity>> watchMyActiveGroups() {
    return (db.select(db.groups)
          ..where(($GroupsTable t) =>
              t.status.equalsValue(GroupStatus.active) |
              t.status.equalsValue(GroupStatus.pendingDeletion))
          ..orderBy(<OrderClauseGenerator<Groups>>[
            (Groups t) => OrderingTerm(
                  expression: t.lastActiveAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .watch();
  }

  /// 単一グループの取得 (remoteId基準)。
  Stream<GroupEntity?> watchGroupByRemoteId(String remoteId) {
    return (db.select(db.groups)
          ..where((Groups t) => t.remoteId.equals(remoteId))
          ..limit(1))
        .watchSingleOrNull();
  }

  Future<GroupEntity?> getGroupByRemoteId(String remoteId) {
    return (db.select(db.groups)
          ..where((Groups t) => t.remoteId.equals(remoteId))
          ..limit(1))
        .getSingleOrNull();
  }

  /// 自分が作成可能なグループ枠の残り数 (rev5.5: 最大3、build 71 で定数化)。
  Future<int> remainingGroupSlots() async {
    final int maxGroups = AppConstants.maxGroupsPerUser;
    final List<GroupEntity> groups = await db.select(db.groups).get();
    return (maxGroups - groups.length).clamp(0, maxGroups);
  }

  /// 現在 pending_deletion 状態のグループ一覧 (Pro解約警告バナー用)。
  Stream<List<GroupEntity>> watchPendingDeletionGroups() {
    return (db.select(db.groups)
          ..where(($GroupsTable t) =>
              t.status.equalsValue(GroupStatus.pendingDeletion)))
        .watch();
  }

  // ============================================================================
  // Write — Local cache update (sync後に呼ばれる)
  // ============================================================================

  /// サーバーから取得したグループ情報をローカルにキャッシュ。
  /// 既存があれば更新、なければinsert。
  Future<void> upsertGroupFromServer({
    required String remoteId,
    required String name,
    required String ownerUserId,
    required MemberPermission myPermission,
    required GroupStatus status,
    int? pendingDeletionAt,
    required int joinedAt,
    int? lastActiveAt,
  }) async {
    final int t = now();
    final GroupEntity? existing = await getGroupByRemoteId(remoteId);

    if (existing == null) {
      await db.into(db.groups).insert(
            GroupsCompanion.insert(
              remoteId: remoteId,
              name: name,
              ownerUserId: ownerUserId,
              myPermission: myPermission,
              status: Value(status),
              pendingDeletionAt: Value(pendingDeletionAt),
              joinedAt: joinedAt,
              lastActiveAt: lastActiveAt ?? t,
              createdAt: t,
              updatedAt: t,
            ),
          );
    } else {
      await (db.update(db.groups)
            ..where((Groups tbl) => tbl.id.equals(existing.id)))
          .write(GroupsCompanion(
        name: Value(name),
        ownerUserId: Value(ownerUserId),
        myPermission: Value(myPermission),
        status: Value(status),
        pendingDeletionAt: Value(pendingDeletionAt),
        lastActiveAt: Value(lastActiveAt ?? t),
        updatedAt: Value(t),
      ));
    }
  }

  /// グループから退出: ローカル削除のみ。
  /// 関連する写真・ペットレコードの掃除は別途呼び出し側で行う。
  /// (rev5.5 §4.16 グループ退出時のローカル写真完全削除)
  Future<void> leaveGroupLocally(String remoteId) async {
    await (db.delete(db.groups)
          ..where((Groups t) => t.remoteId.equals(remoteId)))
        .go();
  }

  /// グループ参加直後の自分の lastActiveAt を更新。
  /// オーナー30日不在検知に使われる(rev5.4)。
  Future<void> touchLastActive(String remoteId) async {
    await (db.update(db.groups)
          ..where((Groups t) => t.remoteId.equals(remoteId)))
        .write(GroupsCompanion(
      lastActiveAt: Value(now()),
    ));
  }
}
