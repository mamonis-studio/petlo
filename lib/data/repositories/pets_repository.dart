// ============================================================================
// petlo - Pets Repository
// ============================================================================
//
// ペット情報のCRUDを担当。
// このRepositoryは他のRepositoryのリファレンス実装。
//
// 設計:
//   - すべてのreadはStreamで提供 (driftの.watch())、UIは自動更新
//   - writeはFuture<int> (新規作成) / Future<bool> (更新成否) を返す
//   - sortOrder はローカル個人設定 (rev5.5)、同期しない
//   - groupIdスコープでフィルタ (Personal / Shared)
//
// ============================================================================

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/utils/logger.dart';
import '../local/app_database.dart';
import '../local/database_enums.dart';
import '../storage/photo_storage.dart';
import 'base_repository.dart';

class PetsRepository extends BaseRepository {
  PetsRepository(super.db);

  // ============================================================================
  // Read
  // ============================================================================

  /// 指定スコープ内の生存ペット一覧 (お別れ済み除く、削除済み除く)。
  /// sortOrderの昇順。
  ///
  /// build 44 (Phase G2): 旧 `pets.group_id == ?` フィルタを廃止し
  /// `pet_scopes` 経由の JOIN に切替。subscriber 視点 (= 他人のペットが
  /// このグループに共有されている) でも該当ペットが返るようになる。
  /// Single-scope な既存データは `_backfillPetScopesFromPets` で 1:1 行が
  /// 存在するため挙動は同一。
  Stream<List<PetEntity>> watchActivePetsInScope(String groupId) {
    return _selectPetsInScope(
      groupId: groupId,
      includeParted: false,
      partedOnly: false,
    ).watch();
  }

  /// 指定スコープ内のお別れ済みペット (メモリアル)。
  Stream<List<PetEntity>> watchPartedPetsInScope(String groupId) {
    return _selectPetsInScope(
      groupId: groupId,
      includeParted: true,
      partedOnly: true,
    ).watch();
  }

  /// pets を pet_scopes 経由で抽出する共通ヘルパ。
  /// drift の subquery API (`isInQuery`) を使い、`pets.id IN
  /// (SELECT pet_id FROM pet_scopes WHERE group_id=? AND deleted_at IS NULL)`
  /// 相当のクエリを構築する。
  Selectable<PetEntity> _selectPetsInScope({
    required String groupId,
    required bool includeParted,
    required bool partedOnly,
  }) {
    final JoinedSelectStatement<PetScopes, PetScopeEntity> scopeIdsQuery =
        db.selectOnly(db.petScopes)
          ..addColumns(<Expression<Object>>[db.petScopes.petId])
          ..where(db.petScopes.groupId.equals(groupId) &
              db.petScopes.deletedAt.isNull());
    final SimpleSelectStatement<Pets, PetEntity> q = db.select(db.pets)
      ..where((Pets t) =>
          t.id.isInQuery(scopeIdsQuery) &
          t.deletedAt.isNull() &
          (partedOnly ? t.partedAt.isNotNull() : t.partedAt.isNull()));
    if (partedOnly) {
      q.orderBy(<OrderClauseGenerator<Pets>>[
        (Pets t) => OrderingTerm(
              expression: t.partedAt,
              mode: OrderingMode.desc,
            ),
      ]);
    } else {
      q.orderBy(<OrderClauseGenerator<Pets>>[
        (Pets t) => OrderingTerm(expression: t.sortOrder),
        (Pets t) => OrderingTerm(expression: t.id),
      ]);
    }
    return q;
  }

  /// 単一ペット取得 (Stream)
  Stream<PetEntity?> watchPet(int petId) {
    return (db.select(db.pets)
          ..where((Pets t) => t.id.equals(petId))
          ..limit(1))
        .watchSingleOrNull();
  }

  /// 単一ペット取得 (Future、initial表示用)
  Future<PetEntity?> getPet(int petId) {
    return (db.select(db.pets)
          ..where((Pets t) => t.id.equals(petId))
          ..limit(1))
        .getSingleOrNull();
  }

  /// 指定グループの中で同名ペットが既に存在するか (rev5.5 同名警告用)。
  ///
  /// build 44 (Phase G2): 共有された他人のペットも判定対象に含めるため
  /// pet_scopes 経由でスコープを解決する。
  Future<bool> hasPetWithName({
    required String groupId,
    required String name,
    int? excludePetId,
  }) async {
    final JoinedSelectStatement<PetScopes, PetScopeEntity> scopeIdsQuery =
        db.selectOnly(db.petScopes)
          ..addColumns(<Expression<Object>>[db.petScopes.petId])
          ..where(db.petScopes.groupId.equals(groupId) &
              db.petScopes.deletedAt.isNull());
    final query = db.select(db.pets)
      ..where((Pets t) =>
          t.id.isInQuery(scopeIdsQuery) &
          t.name.equals(name) &
          t.deletedAt.isNull());
    if (excludePetId != null) {
      query.where((Pets t) => t.id.equals(excludePetId).not());
    }
    final List<PetEntity> matches = await query.get();
    return matches.isNotEmpty;
  }

  // ============================================================================
  // Write — Create
  // ============================================================================

  /// 新規ペット登録。
  /// sortOrder はスコープ内の最大値 + 1 を自動設定。
  /// 戻り値は新規ペットのid。
  Future<int> createPet({
    required String groupId,
    required String name,
    required PetType type,
    String? breed,
    PetSex? sex,
    bool neutered = false,
    int? birthday,
    int? idealWeightMinG,
    int? idealWeightMaxG,
    String? photoPath,
    List<String>? chronicConditions,
    List<String>? allergies,
    String? primaryVetName,
    String? primaryVetPhone,
    String? primaryVetAddress,
    String? emergencyVetName,
    String? emergencyVetPhone,
    String? emergencyVetAddress,
    String? createdBy,
  }) async {
    // 名前の最低限バリデーション
    if (name.trim().isEmpty || name.length > 50) {
      throw ArgumentError('Pet name must be 1-50 characters');
    }
    // build 40: 絶対パス紛れ込みの debug-only 防御
    assertRelativePhotoPath(photoPath);

    final meta = buildCreateMetadata(groupId: groupId);
    final int nextSortOrder = await _getNextSortOrder(groupId);

    final int newId = await db.into(db.pets).insert(
          PetsCompanion.insert(
            groupId: Value(groupId),
            name: name.trim(),
            type: type,
            breed: Value(breed),
            sex: Value(sex),
            neutered: Value(neutered),
            birthday: Value(birthday),
            idealWeightMinG: Value(idealWeightMinG),
            idealWeightMaxG: Value(idealWeightMaxG),
            photoPath: Value(photoPath),
            chronicConditions: Value(chronicConditions),
            allergies: Value(allergies),
            primaryVetName: Value(primaryVetName),
            primaryVetPhone: Value(primaryVetPhone),
            primaryVetAddress: Value(primaryVetAddress),
            emergencyVetName: Value(emergencyVetName),
            emergencyVetPhone: Value(emergencyVetPhone),
            emergencyVetAddress: Value(emergencyVetAddress),
            sortOrder: Value(nextSortOrder),
            createdBy: Value(createdBy),
            syncStatus: Value(meta.initialSyncStatus),
            createdAt: meta.createdAt,
            updatedAt: meta.updatedAt,
            lastModifiedAtClient: Value(meta.lastModifiedAtClient),
          ),
        );

    // build 44 (Phase G2): 新規ペットには primary pet_scope を自動作成する。
    // pet_scopes 経由の JOIN 読み取り (watchActivePetsInScope) で新規ペットが
    // 即座に可視化されるための必須ステップ。Phase G1 の backfill と完全に
    // 同じ形 (permission=owner, isPrimary=true) で挿入する。
    final int scopeId = await db.into(db.petScopes).insert(
          PetScopesCompanion.insert(
            petId: newId,
            groupId: groupId,
            permission: MemberPermission.owner,
            isPrimary: const Value(true),
            sharedAt: meta.createdAt,
            sharedByUserId: Value(createdBy),
            syncStatus: Value(meta.initialSyncStatus),
            createdAt: meta.createdAt,
            updatedAt: meta.updatedAt,
            lastModifiedAtClient: Value(meta.lastModifiedAtClient),
          ),
        );

    await enqueueSyncIfShared(
      groupId: groupId,
      operation: SyncOperation.insert,
      targetTable: 'pets',
      recordId: newId,
      payloadJson: jsonEncode(<String, dynamic>{
        'name': name,
        'type': type.name,
        'breed': breed,
        'sex': sex?.name,
        // 写真は別途upload_queueで処理
      }),
    );

    // build 53a (構造的欠陥 #1 修正): 旧実装は pets だけ sync_queue に積み、
    // 自動生成した primary pet_scope 行は積んでいなかった。結果、shared スコープで
    // 新規ペットを作成しても server 側で pet_scopes 行が無いため、他端末から
    // 見えない + 自分の端末でも sync の副作用で消える挙動を疑っていた。
    // Personal は同期しないので enqueueSyncIfShared が no-op。
    await enqueueSyncIfShared(
      groupId: groupId,
      operation: SyncOperation.update,
      targetTable: 'pet_scopes',
      recordId: scopeId,
      payloadJson: '{}',
    );

    // build 53a: 診断ログ (構造的欠陥の検証用、build 53b で d レベルに下げる)
    final int scopesCount = await (db.selectOnly(db.petScopes)
          ..addColumns(<Expression<Object>>[db.petScopes.id])
          ..where(db.petScopes.petId.equals(newId) &
              db.petScopes.deletedAt.isNull()))
        .get()
        .then((List<TypedResult> rows) => rows.length);
    PetloLogger.instance.i(
      '[createPet diag] petId=$newId groupId=$groupId '
      'scopeId=$scopeId pet_scopes_for_pet=$scopesCount '
      'is_shared=${isSharedScope(groupId)}',
    );

    return newId;
  }

  Future<int> _getNextSortOrder(String groupId) async {
    // drift 2.28 では selectOnly + addColumns が Expression<Object> non-null を要求するため、
    // nullable 列の MAX 取得は customSelect で書く方が素直。
    final QueryRow? row = await db.customSelect(
      'SELECT MAX(sort_order) AS max_order FROM pets '
      'WHERE group_id = ?1 AND deleted_at IS NULL',
      variables: <Variable<Object>>[Variable<String>(groupId)],
      readsFrom: <ResultSetImplementation<dynamic, dynamic>>{db.pets},
    ).getSingleOrNull();
    final int? maxOrder = row?.readNullable<int>('max_order');
    return (maxOrder ?? -1) + 1;
  }

  // ============================================================================
  // Write — Update
  // ============================================================================

  /// ペット情報更新。指定したフィールドのみ更新する。
  Future<bool> updatePet({
    required int petId,
    String? name,
    String? breed,
    PetSex? sex,
    bool? neutered,
    int? birthday,
    int? idealWeightMinG,
    int? idealWeightMaxG,
    String? photoPath,
    List<String>? chronicConditions,
    List<String>? allergies,
    String? primaryVetName,
    String? primaryVetPhone,
    String? primaryVetAddress,
    String? emergencyVetName,
    String? emergencyVetPhone,
    String? emergencyVetAddress,
  }) async {
    assertRelativePhotoPath(photoPath);
    final PetEntity? pet = await getPet(petId);
    if (pet == null) {
      throw StateError('Pet not found: id=$petId');
    }

    final meta = buildUpdateMetadata(groupId: pet.groupId);

    final PetsCompanion companion = PetsCompanion(
      name: name == null ? const Value.absent() : Value(name.trim()),
      breed: breed == null ? const Value.absent() : Value(breed),
      sex: sex == null ? const Value.absent() : Value(sex),
      neutered: neutered == null ? const Value.absent() : Value(neutered),
      birthday: birthday == null ? const Value.absent() : Value(birthday),
      idealWeightMinG:
          idealWeightMinG == null ? const Value.absent() : Value(idealWeightMinG),
      idealWeightMaxG:
          idealWeightMaxG == null ? const Value.absent() : Value(idealWeightMaxG),
      photoPath: photoPath == null ? const Value.absent() : Value(photoPath),
      chronicConditions: chronicConditions == null
          ? const Value.absent()
          : Value(chronicConditions),
      allergies: allergies == null ? const Value.absent() : Value(allergies),
      primaryVetName:
          primaryVetName == null ? const Value.absent() : Value(primaryVetName),
      primaryVetPhone:
          primaryVetPhone == null ? const Value.absent() : Value(primaryVetPhone),
      primaryVetAddress: primaryVetAddress == null
          ? const Value.absent()
          : Value(primaryVetAddress),
      emergencyVetName: emergencyVetName == null
          ? const Value.absent()
          : Value(emergencyVetName),
      emergencyVetPhone: emergencyVetPhone == null
          ? const Value.absent()
          : Value(emergencyVetPhone),
      emergencyVetAddress: emergencyVetAddress == null
          ? const Value.absent()
          : Value(emergencyVetAddress),
      syncStatus: Value(meta.updatedSyncStatus),
      updatedAt: Value(meta.updatedAt),
      lastModifiedAtClient: Value(meta.lastModifiedAtClient),
    );

    final int affected =
        await (db.update(db.pets)..where((Pets t) => t.id.equals(petId)))
            .write(companion);

    if (affected > 0) {
      await enqueueSyncIfShared(
        groupId: pet.groupId,
        operation: SyncOperation.update,
        targetTable: 'pets',
        recordId: petId,
        payloadJson: jsonEncode(<String, dynamic>{}),
      );
    }

    return affected > 0;
  }

  /// 並び順だけ更新 (rev5.5: ローカル個人設定、サーバー同期しない)
  Future<void> updateSortOrder(int petId, int newSortOrder) async {
    await (db.update(db.pets)..where((Pets t) => t.id.equals(petId)))
        .write(PetsCompanion(
      sortOrder: Value(newSortOrder),
      // 注: updatedAt や syncStatusは触らない (sortOrderは同期対象外)
    ));
  }

  /// お別れ日設定 (メモリアルモード切替)。
  /// rev5.4: 今日以前の日付のみ許可、未来日はエラー。
  Future<bool> markAsParted({
    required int petId,
    required int partedAtMsec,
    MemorialNotifyFrequency notify = MemorialNotifyFrequency.monthly,
  }) async {
    if (partedAtMsec > now()) {
      throw ArgumentError('お別れ日は今日以前の日付のみ指定できます');
    }
    final PetEntity? pet = await getPet(petId);
    if (pet == null) return false;

    final meta = buildUpdateMetadata(groupId: pet.groupId);

    final int affected =
        await (db.update(db.pets)..where((Pets t) => t.id.equals(petId)))
            .write(PetsCompanion(
      partedAt: Value(partedAtMsec),
      memorialNotify: Value(notify),
      syncStatus: Value(meta.updatedSyncStatus),
      updatedAt: Value(meta.updatedAt),
      lastModifiedAtClient: Value(meta.lastModifiedAtClient),
    ));

    if (affected > 0) {
      await enqueueSyncIfShared(
        groupId: pet.groupId,
        operation: SyncOperation.update,
        targetTable: 'pets',
        recordId: petId,
        payloadJson: jsonEncode(<String, dynamic>{
          'partedAt': partedAtMsec,
          'memorialNotify': notify.name,
        }),
      );
    }
    return affected > 0;
  }

  // ============================================================================
  // Write — Delete (論理削除)
  // ============================================================================
  //
  // build 49 (C3): @Deprecated だった `movePetToGroup` (build 20-48) を物理
  // 削除した。multi-scope モデルでは [PetScopesRepository.addPetScope]/
  // [removePetScope] が公式 API。UI caller は build 46 (Phase G4b) で
  // 全置換済み。
  // ============================================================================

  /// ペットを論理削除 (deletedAtセット)。
  /// 30日後にCronで物理削除される想定。
  ///
  /// build 47 (Scope A2): pet 単体だけでなく紐づく子レコード
  /// (meals/poops/pees/vomits/weights/temperatures/bcs_checks/diaries/
  /// visits/vaccinations/medications/medication_reminders/expiration_items)
  /// も同じトランザクションで論理削除する。子レコードが孤児として残ると
  /// クエリで弾けず容量も食うため。お別れ (markAsParted) は記録を
  /// 宝物として残す哲学なので子は触らない。
  ///
  /// 既に deleted_at が立っている子レコードはスキップ
  /// (同じタイミングを上書きしない、sync_queue も二重に積まない)。
  Future<bool> softDeletePet(int petId) async {
    final PetEntity? pet = await getPet(petId);
    if (pet == null) return false;
    if (pet.deletedAt != null) return false;

    final meta = buildDeleteMetadata(groupId: pet.groupId);

    // build 49 (C1): medication_reminders は v8 で DROP 済みなので外す。
    // 投薬の枠は schedules (category=medication) に統合されたが、schedules は
    // 「複数ペット共通の予定」を許す構造なので pet 単独削除では消さない
    // (例: 旅行プラン schedule に複数ペットが related され、1 匹だけ削除
    // するケースを正しく扱うため、schedule の cascade は schedules 側の
    // relatedPetIds 編集経路で扱う)。
    const List<String> petBoundTables = <String>[
      'meals', 'poops', 'pees', 'vomits',
      'weights', 'temperatures', 'bcs_checks',
      'diaries', 'visits', 'vaccinations',
      'medications', 'expiration_items',
    ];

    final List<({String table, int id})> affectedChildren =
        <({String table, int id})>[];
    int petAffected = 0;

    await db.transaction(() async {
      // 子レコード: まだ生存しているものだけ id を拾って一括 UPDATE
      for (final String table in petBoundTables) {
        final List<QueryRow> ids = await db.customSelect(
          'SELECT id FROM $table WHERE pet_id = ? AND deleted_at IS NULL',
          variables: <Variable<Object>>[Variable<int>(petId)],
        ).get();
        for (final QueryRow row in ids) {
          affectedChildren.add((table: table, id: row.read<int>('id')));
        }
        await db.customStatement(
          'UPDATE $table SET deleted_at = ?, sync_status = ?, '
          'updated_at = ?, last_modified_at_client = ? '
          'WHERE pet_id = ? AND deleted_at IS NULL',
          <Object?>[
            meta.deletedAt,
            meta.updatedSyncStatus.name,
            meta.updatedAt,
            meta.lastModifiedAtClient,
            petId,
          ],
        );
      }

      // ペット本体
      petAffected =
          await (db.update(db.pets)..where((Pets t) => t.id.equals(petId)))
              .write(PetsCompanion(
        deletedAt: Value(meta.deletedAt),
        syncStatus: Value(meta.updatedSyncStatus),
        updatedAt: Value(meta.updatedAt),
        lastModifiedAtClient: Value(meta.lastModifiedAtClient),
      ));
    });

    if (petAffected == 0) return false;

    // drift watchers を発火 (StreamProvider 再評価)
    db.notifyUpdates(<TableUpdate>{
      const TableUpdate('pets'),
      for (final String t in petBoundTables) TableUpdate(t),
    });

    // sync_queue: pet + 影響を受けた子レコードそれぞれに delete op を積む。
    // personal スコープでは enqueueSyncIfShared が no-op。
    await enqueueSyncIfShared(
      groupId: pet.groupId,
      operation: SyncOperation.delete,
      targetTable: 'pets',
      recordId: petId,
      payloadJson: jsonEncode(<String, dynamic>{}),
    );
    for (final ({String table, int id}) r in affectedChildren) {
      await enqueueSyncIfShared(
        groupId: pet.groupId,
        operation: SyncOperation.delete,
        targetTable: r.table,
        recordId: r.id,
        payloadJson: '{}',
      );
    }
    return true;
  }
}
