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

import '../local/app_database.dart';
import '../local/database_enums.dart';
import 'base_repository.dart';

class PetsRepository extends BaseRepository {
  PetsRepository(super.db);

  // ============================================================================
  // Read
  // ============================================================================

  /// 指定スコープ内の生存ペット一覧 (お別れ済み除く、削除済み除く)。
  /// sortOrderの昇順。
  Stream<List<PetEntity>> watchActivePetsInScope(String groupId) {
    return (db.select(db.pets)
          ..where((Pets t) =>
              t.groupId.equals(groupId) &
              t.deletedAt.isNull() &
              t.partedAt.isNull())
          ..orderBy(<OrderClauseGenerator<Pets>>[
            (Pets t) => OrderingTerm(expression: t.sortOrder),
            (Pets t) => OrderingTerm(expression: t.id),
          ]))
        .watch();
  }

  /// 指定スコープ内のお別れ済みペット (メモリアル)。
  Stream<List<PetEntity>> watchPartedPetsInScope(String groupId) {
    return (db.select(db.pets)
          ..where((Pets t) =>
              t.groupId.equals(groupId) &
              t.deletedAt.isNull() &
              t.partedAt.isNotNull())
          ..orderBy(<OrderClauseGenerator<Pets>>[
            (Pets t) => OrderingTerm(
                  expression: t.partedAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .watch();
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

  /// 指定グループの中で同名ペットが既に存在するか (rev5.5 同名警告用)
  Future<bool> hasPetWithName({
    required String groupId,
    required String name,
    int? excludePetId,
  }) async {
    final query = db.select(db.pets)
      ..where((Pets t) =>
          t.groupId.equals(groupId) &
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
    required PetSex sex,
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

    final meta = buildCreateMetadata(groupId: groupId);
    final int nextSortOrder = await _getNextSortOrder(groupId);

    final int newId = await db.into(db.pets).insert(
          PetsCompanion.insert(
            groupId: Value(groupId),
            name: name.trim(),
            type: type,
            breed: Value(breed),
            sex: sex,
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

    await enqueueSyncIfShared(
      groupId: groupId,
      operation: SyncOperation.insert,
      targetTable: 'pets',
      recordId: newId,
      payloadJson: jsonEncode(<String, dynamic>{
        'name': name,
        'type': type.name,
        'breed': breed,
        'sex': sex.name,
        // 写真は別途upload_queueで処理
      }),
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

  /// ペットを論理削除 (deletedAtセット)。
  /// 30日後にCronで物理削除される想定。
  Future<bool> softDeletePet(int petId) async {
    final PetEntity? pet = await getPet(petId);
    if (pet == null) return false;

    final meta = buildDeleteMetadata(groupId: pet.groupId);

    final int affected =
        await (db.update(db.pets)..where((Pets t) => t.id.equals(petId)))
            .write(PetsCompanion(
      deletedAt: Value(meta.deletedAt),
      syncStatus: Value(meta.updatedSyncStatus),
      updatedAt: Value(meta.updatedAt),
      lastModifiedAtClient: Value(meta.lastModifiedAtClient),
    ));

    if (affected > 0) {
      await enqueueSyncIfShared(
        groupId: pet.groupId,
        operation: SyncOperation.delete,
        targetTable: 'pets',
        recordId: petId,
        payloadJson: jsonEncode(<String, dynamic>{}),
      );
    }
    return affected > 0;
  }
}
