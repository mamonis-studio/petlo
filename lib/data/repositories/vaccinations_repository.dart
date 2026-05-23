// ============================================================================
// petlo - Vaccinations Repository
// ============================================================================
//
// ワクチン記録のCRUD。
// rev3 F-08: 種別 + 接種日 + 次回予定 + 病院 + 証明書写真。
// 次回予定がある記録は将来リマインダーになる。
//
// ============================================================================

import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_enums.dart';
import '../storage/photo_storage.dart';
import 'base_repository.dart';

class VaccinationsRepository extends BaseRepository {
  VaccinationsRepository(super.db);

  // ============================================================================
  // Read
  // ============================================================================

  /// ペットのワクチン記録 (新しい接種日順)
  Stream<List<VaccinationEntity>> watchForPet(int petId, {int? limit}) {
    final query = db.select(db.vaccinations)
      ..where((Vaccinations t) =>
          t.petId.equals(petId) & t.deletedAt.isNull())
      ..orderBy(<OrderClauseGenerator<Vaccinations>>[
        (Vaccinations t) => OrderingTerm(
              expression: t.administeredAt,
              mode: OrderingMode.desc,
            ),
      ]);
    if (limit != null) query.limit(limit);
    return query.watch();
  }

  /// 「次回接種が近づいているもの」を抽出。
  /// fromMsec(現在) より未来 かつ toMsec(現在+30日 等) より過去のものを取得。
  Stream<List<VaccinationEntity>> watchUpcomingDue({
    required int petId,
    required int fromMsec,
    required int toMsec,
  }) {
    return (db.select(db.vaccinations)
          ..where((Vaccinations t) =>
              t.petId.equals(petId) &
              t.deletedAt.isNull() &
              t.nextDueAt.isNotNull() &
              t.nextDueAt.isBetweenValues(fromMsec, toMsec))
          ..orderBy(<OrderClauseGenerator<Vaccinations>>[
            (Vaccinations t) => OrderingTerm(expression: t.nextDueAt),
          ]))
        .watch();
  }

  /// 期限切れ(nextDueAt が現在より過去)のワクチン
  Stream<List<VaccinationEntity>> watchOverdue(int petId) {
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    return (db.select(db.vaccinations)
          ..where((Vaccinations t) =>
              t.petId.equals(petId) &
              t.deletedAt.isNull() &
              t.nextDueAt.isNotNull() &
              t.nextDueAt.isSmallerThanValue(now))
          ..orderBy(<OrderClauseGenerator<Vaccinations>>[
            (Vaccinations t) => OrderingTerm(
                  expression: t.nextDueAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .watch();
  }

  Future<VaccinationEntity?> getById(int id) {
    return (db.select(db.vaccinations)
          ..where((Vaccinations t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
  }

  /// 全 nextDueAt > now な未来期限のワクチン(起動時の通知再構築用、Future)
  Future<List<VaccinationEntity>> getAllUpcomingDueAlerts() {
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    return (db.select(db.vaccinations)
          ..where((Vaccinations t) =>
              t.deletedAt.isNull() &
              t.nextDueAt.isNotNull() &
              t.nextDueAt.isBiggerThanValue(now)))
        .get();
  }

  // ============================================================================
  // Write
  // ============================================================================

  Future<int> create({
    required String groupId,
    required int petId,
    required String kind,
    required int administeredAtMsec,
    int? nextDueAtMsec,
    String? clinicName,
    String? photoPath,
    String? notes,
    String? createdBy,
  }) async {
    if (kind.trim().isEmpty) {
      throw ArgumentError('kind cannot be empty');
    }
    if (nextDueAtMsec != null && nextDueAtMsec <= administeredAtMsec) {
      throw ArgumentError(
        'nextDueAtMsec must be after administeredAtMsec',
      );
    }
    assertRelativePhotoPath(photoPath);
    final meta = buildCreateMetadata(groupId: groupId);

    final int newId = await db.into(db.vaccinations).insert(
          VaccinationsCompanion.insert(
            groupId: Value(groupId),
            petId: petId,
            kind: kind.trim(),
            administeredAt: administeredAtMsec,
            nextDueAt: Value(nextDueAtMsec),
            clinicName: Value(_emptyToNull(clinicName)),
            photoPath: Value(photoPath),
            notes: Value(_emptyToNull(notes)),
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
      targetTable: 'vaccinations',
      recordId: newId,
      payloadJson: jsonEncode(<String, dynamic>{
        'petId': petId,
        'kind': kind,
        'administeredAt': administeredAtMsec,
        'nextDueAt': nextDueAtMsec,
      }),
    );
    return newId;
  }

  Future<bool> update({
    required int vaccinationId,
    String? kind,
    int? administeredAtMsec,
    int? nextDueAtMsec,
    bool clearNextDue = false,
    String? clinicName,
    String? photoPath,
    bool clearPhoto = false,
    String? notes,
  }) async {
    assertRelativePhotoPath(photoPath);
    final VaccinationEntity? existing = await getById(vaccinationId);
    if (existing == null) {
      throw StateError('Vaccination not found: id=$vaccinationId');
    }

    if (kind != null && kind.trim().isEmpty) {
      throw ArgumentError('kind cannot be empty');
    }
    if (nextDueAtMsec != null && administeredAtMsec != null) {
      if (nextDueAtMsec <= administeredAtMsec) {
        throw ArgumentError(
          'nextDueAtMsec must be after administeredAtMsec',
        );
      }
    }

    final meta = buildUpdateMetadata(groupId: existing.groupId);

    final companion = VaccinationsCompanion(
      kind: kind == null ? const Value.absent() : Value(kind.trim()),
      administeredAt: administeredAtMsec == null
          ? const Value.absent()
          : Value(administeredAtMsec),
      nextDueAt: clearNextDue
          ? const Value(null)
          : (nextDueAtMsec == null
              ? const Value.absent()
              : Value(nextDueAtMsec)),
      clinicName: clinicName == null
          ? const Value.absent()
          : Value(_emptyToNull(clinicName)),
      photoPath: clearPhoto
          ? const Value(null)
          : (photoPath == null ? const Value.absent() : Value(photoPath)),
      notes: notes == null
          ? const Value.absent()
          : Value(_emptyToNull(notes)),
      syncStatus: Value(meta.updatedSyncStatus),
      updatedAt: Value(meta.updatedAt),
      lastModifiedAtClient: Value(meta.lastModifiedAtClient),
    );

    final int affected = await (db.update(db.vaccinations)
          ..where((Vaccinations t) => t.id.equals(vaccinationId)))
        .write(companion);

    if (affected > 0) {
      await enqueueSyncIfShared(
        groupId: existing.groupId,
        operation: SyncOperation.update,
        targetTable: 'vaccinations',
        recordId: vaccinationId,
        payloadJson: jsonEncode(<String, dynamic>{}),
      );
    }
    return affected > 0;
  }

  Future<bool> softDelete(int vaccinationId) async {
    final VaccinationEntity? existing = await getById(vaccinationId);
    if (existing == null) return false;

    final meta = buildDeleteMetadata(groupId: existing.groupId);
    final int affected = await (db.update(db.vaccinations)
          ..where((Vaccinations t) => t.id.equals(vaccinationId)))
        .write(VaccinationsCompanion(
      deletedAt: Value(meta.deletedAt),
      syncStatus: Value(meta.updatedSyncStatus),
      updatedAt: Value(meta.updatedAt),
      lastModifiedAtClient: Value(meta.lastModifiedAtClient),
    ));

    if (affected > 0) {
      await enqueueSyncIfShared(
        groupId: existing.groupId,
        operation: SyncOperation.delete,
        targetTable: 'vaccinations',
        recordId: vaccinationId,
        payloadJson: jsonEncode(<String, dynamic>{}),
      );
    }
    return affected > 0;
  }

  static String? _emptyToNull(String? s) {
    if (s == null) return null;
    final String trimmed = s.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
