// ============================================================================
// petlo - PetScopesRepository (multi-scope pet sharing, Phase G1)
// ============================================================================
//
// `pet_scopes` テーブルに対する read/write の最小集合。build 43 では
// **schema 拡張のみ**で UI 経路は変えないため、既存 `movePetToGroup` の挙動と
// 並走する形でこの repository が pet_scopes 行を管理する。
//
// build 43 (Phase G1) 時点の責務:
//   - pet ごとの scope 一覧 watch / get
//   - 新規共有 (addPetScope) / 共有解除 (removePetScope) / 権限更新
//   - primary scope 探索 (`findPrimaryScope`)
//
// Phase G2 以降で `currentGroupPetsProvider` 等がこの repository 経由に
// 移行し、`movePetToGroup` も Phase G4 で `sharePet` API に置換される予定。
//
// build 44 (Phase G2) 更新: shared scope への書き込みは `sync_queue` に
// entityType='pet_scope' op を積むようにした。Backend (Phase G3) が受信
// 対応するまでは reject 'invalid_operation' を食らって queue から落ちる
// 想定だが、ローカル状態は正常に保たれる。
//
// ============================================================================

import 'package:drift/drift.dart';

import '../../core/utils/logger.dart';
import '../local/app_database.dart';
import '../local/database_enums.dart';
import 'base_repository.dart';

class PetScopesRepository extends BaseRepository {
  PetScopesRepository(super.db);

  // ============================================================================
  // Read
  // ============================================================================

  /// 指定ペットの生存 scope 一覧を stream。
  /// 共有時刻 (sharedAt) の昇順 ─ primary が最初に共有されてるとは限らないが、
  /// 通常 primary が最古になる。
  Stream<List<PetScopeEntity>> watchPetScopes(int petId) {
    return (db.select(db.petScopes)
          ..where(($PetScopesTable t) =>
              t.petId.equals(petId) & t.deletedAt.isNull())
          ..orderBy(<OrderClauseGenerator<$PetScopesTable>>[
            ($PetScopesTable t) => OrderingTerm(expression: t.sharedAt),
          ]))
        .watch();
  }

  /// One-shot 取得版。
  Future<List<PetScopeEntity>> getPetScopes(int petId) {
    return (db.select(db.petScopes)
          ..where(($PetScopesTable t) =>
              t.petId.equals(petId) & t.deletedAt.isNull())
          ..orderBy(<OrderClauseGenerator<$PetScopesTable>>[
            ($PetScopesTable t) => OrderingTerm(expression: t.sharedAt),
          ]))
        .get();
  }

  /// ペットの primary scope を返す。未設定や論理削除済みのみなら null。
  Future<PetScopeEntity?> findPrimaryScope(int petId) {
    return (db.select(db.petScopes)
          ..where(($PetScopesTable t) =>
              t.petId.equals(petId) &
              t.isPrimary.equals(true) &
              t.deletedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
  }

  /// 指定 (pet, group) の生存 scope を返す。
  Future<PetScopeEntity?> findScope({
    required int petId,
    required String groupId,
  }) {
    return (db.select(db.petScopes)
          ..where(($PetScopesTable t) =>
              t.petId.equals(petId) &
              t.groupId.equals(groupId) &
              t.deletedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
  }

  // ============================================================================
  // Write
  // ============================================================================

  /// 新規共有。同じ (pet, group) が既に生存している場合は何もせず既存行を返す。
  /// 論理削除済みの行があれば deletedAt を NULL に戻して再活性化する。
  ///
  /// `isPrimary=true` を指定した場合、同 pet の他 scope は **呼び出し側で
  /// false に落とす責任を負う** (本 repository は呼び出し側のトランザクション
  /// 構造に介入しない)。
  Future<int> addPetScope({
    required int petId,
    required String groupId,
    required MemberPermission permission,
    bool isPrimary = false,
    String? sharedByUserId,
    int? sharedAtMsec,
  }) async {
    final int t = now();
    final PetScopeEntity? existing =
        await findScope(petId: petId, groupId: groupId);
    if (existing != null) {
      // 既に生存中 → 何もしない。冪等。
      return existing.id;
    }
    // ソフト削除されている行があれば再活性化
    final PetScopeEntity? soft = await (db.select(db.petScopes)
          ..where(($PetScopesTable t) =>
              t.petId.equals(petId) &
              t.groupId.equals(groupId) &
              t.deletedAt.isNotNull())
          ..limit(1))
        .getSingleOrNull();
    final int scopeId;
    if (soft != null) {
      await (db.update(db.petScopes)
            ..where(($PetScopesTable t) => t.id.equals(soft.id)))
          .write(PetScopesCompanion(
        permission: Value(permission),
        isPrimary: Value(isPrimary),
        sharedAt: Value(sharedAtMsec ?? t),
        sharedByUserId: Value(sharedByUserId),
        deletedAt: const Value(null),
        updatedAt: Value(t),
        lastModifiedAtClient: Value(t),
        syncStatus: const Value(SyncStatus.pending),
      ));
      scopeId = soft.id;
    } else {
      scopeId = await db.into(db.petScopes).insert(PetScopesCompanion.insert(
            petId: petId,
            groupId: groupId,
            permission: permission,
            isPrimary: Value(isPrimary),
            sharedAt: sharedAtMsec ?? t,
            sharedByUserId: Value(sharedByUserId),
            syncStatus: const Value(SyncStatus.pending),
            createdAt: t,
            updatedAt: t,
            lastModifiedAtClient: Value(t),
          ));
    }
    // build 44 (Phase G2): shared scope への書き込みは sync_queue に積む。
    // personal は同期不要なので enqueueSyncIfShared 側でスキップされる。
    await enqueueSyncIfShared(
      groupId: groupId,
      operation: SyncOperation.update,
      targetTable: 'pet_scopes',
      recordId: scopeId,
      payloadJson: '{}',
      clientTimestamp: t,
    );

    // build 53a (診断): pet_scopes の最新状態を log。
    final List<PetScopeEntity> all = await getPetScopes(petId);
    PetloLogger.instance.i(
      '[addPetScope diag] petId=$petId groupId=$groupId '
      'scopeId=$scopeId isPrimary=$isPrimary perm=${permission.name} '
      'scopes_for_pet=${all.length} '
      'groups=${all.map((PetScopeEntity s) => '${s.groupId}(primary=${s.isPrimary})').toList()}',
    );

    return scopeId;
  }

  /// 共有解除 (論理削除)。primary scope の解除は本 repository では禁止せず、
  /// 呼び出し側のフローで判断する (例: 別 scope を新しい primary に昇格してから
  /// 旧 primary を解除、など)。
  Future<bool> removePetScope({
    required int petId,
    required String groupId,
  }) async {
    final PetScopeEntity? existing =
        await findScope(petId: petId, groupId: groupId);
    if (existing == null) return false;
    final int t = now();
    final int rows = await (db.update(db.petScopes)
          ..where(($PetScopesTable t) => t.id.equals(existing.id)))
        .write(PetScopesCompanion(
      deletedAt: Value(t),
      updatedAt: Value(t),
      lastModifiedAtClient: Value(t),
      syncStatus: const Value(SyncStatus.pending),
    ));
    if (rows > 0) {
      await enqueueSyncIfShared(
        groupId: groupId,
        operation: SyncOperation.delete,
        targetTable: 'pet_scopes',
        recordId: existing.id,
        payloadJson: '{}',
        clientTimestamp: t,
      );
    }
    return rows > 0;
  }

  /// per-pet 権限を変更 (Decision Log #4: per-pet は group 権限を上書き)。
  Future<bool> updatePetScopePermission({
    required int petId,
    required String groupId,
    required MemberPermission permission,
  }) async {
    final PetScopeEntity? existing =
        await findScope(petId: petId, groupId: groupId);
    if (existing == null) return false;
    final int t = now();
    final int rows = await (db.update(db.petScopes)
          ..where(($PetScopesTable t) => t.id.equals(existing.id)))
        .write(PetScopesCompanion(
      permission: Value(permission),
      updatedAt: Value(t),
      lastModifiedAtClient: Value(t),
      syncStatus: const Value(SyncStatus.pending),
    ));
    if (rows > 0) {
      await enqueueSyncIfShared(
        groupId: groupId,
        operation: SyncOperation.update,
        targetTable: 'pet_scopes',
        recordId: existing.id,
        payloadJson: '{}',
        clientTimestamp: t,
      );
    }
    return rows > 0;
  }
}
