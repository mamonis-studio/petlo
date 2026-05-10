// ============================================================================
// petlo - Invite Codes Repository
// ============================================================================
//
// 招待コードのローカルキャッシュ管理。
//
// rev5.3 F-25: 6桁招待コード発行 / F-26: 招待コードで参加
//
// 設計:
//   - サーバー側で発行された情報を保存(コード本体はサーバーが生成)
//   - クライアントは active な未使用コードを表示する
//   - 期限切れ判定は expiresAt と現在時刻で算出
//
// ============================================================================

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_enums.dart';
import 'base_repository.dart';

class InviteCodesRepository extends BaseRepository {
  InviteCodesRepository(super.db);

  // ============================================================================
  // Read
  // ============================================================================

  /// 指定グループの active な招待コード(複数可、新しい順)
  Stream<List<InviteCodeEntity>> watchActiveCodesForGroup(
      String groupRemoteId) {
    final int nowMsec = DateTime.now().millisecondsSinceEpoch;
    final query = db.select(db.inviteCodes)
      ..where(($InviteCodesTable t) =>
          t.groupRemoteId.equals(groupRemoteId) &
          t.status.equalsValue(InviteCodeStatus.active) &
          t.expiresAt.isBiggerThanValue(nowMsec))
      ..orderBy(<OrderClauseGenerator<InviteCodes>>[
        (InviteCodes t) =>
            OrderingTerm(expression: t.issuedAt, mode: OrderingMode.desc),
      ]);
    return query.watch();
  }

  /// 全コード履歴(失効済み含む、新しい順 50件)
  Stream<List<InviteCodeEntity>> watchAllForGroup(String groupRemoteId) {
    final query = db.select(db.inviteCodes)
      ..where((InviteCodes t) =>
          t.groupRemoteId.equals(groupRemoteId))
      ..orderBy(<OrderClauseGenerator<InviteCodes>>[
        (InviteCodes t) =>
            OrderingTerm(expression: t.issuedAt, mode: OrderingMode.desc),
      ])
      ..limit(50);
    return query.watch();
  }

  /// コード本体で検索(参加時に使用)
  Future<InviteCodeEntity?> getByCode(String code) {
    return (db.select(db.inviteCodes)
          ..where((InviteCodes t) => t.code.equals(code))
          ..limit(1))
        .getSingleOrNull();
  }

  // ============================================================================
  // Write — Local cache update
  // ============================================================================

  /// サーバーが発行した招待コードをローカルに保存
  Future<int> insertCode({
    required String code,
    required String groupRemoteId,
    required MemberPermission grantedPermission,
    required int issuedAt,
    required int expiresAt,
  }) async {
    return db.into(db.inviteCodes).insert(
          InviteCodesCompanion.insert(
            code: code,
            groupRemoteId: groupRemoteId,
            grantedPermission: grantedPermission,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
          ),
        );
  }

  /// コードのステータス更新 (used/expired/cancelled に遷移)
  Future<void> updateStatus({
    required String code,
    required InviteCodeStatus status,
    int? usedAt,
    String? usedByUserId,
  }) async {
    await (db.update(db.inviteCodes)
          ..where((InviteCodes t) => t.code.equals(code)))
        .write(InviteCodesCompanion(
      status: Value(status),
      usedAt: Value(usedAt),
      usedByUserId: Value(usedByUserId),
    ));
  }

  /// 期限切れコードを一括 expired に更新(起動時等)
  Future<int> markExpiredCodes() async {
    final int nowMsec = DateTime.now().millisecondsSinceEpoch;
    return (db.update(db.inviteCodes)
          ..where(($InviteCodesTable t) =>
              t.status.equalsValue(InviteCodeStatus.active) &
              t.expiresAt.isSmallerOrEqualValue(nowMsec)))
        .write(const InviteCodesCompanion(
      status: Value(InviteCodeStatus.expired),
    ));
  }

  /// グループの全招待コードを削除 (グループ退出時)
  Future<void> deleteAllForGroup(String groupRemoteId) async {
    await (db.delete(db.inviteCodes)
          ..where((InviteCodes t) =>
              t.groupRemoteId.equals(groupRemoteId)))
        .go();
  }
}
