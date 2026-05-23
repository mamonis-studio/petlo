// ============================================================================
// petlo - Visits Repository
// ============================================================================
//
// 通院記録のCRUD。
// rev3: 主訴、診断、治療、費用、写真複数枚を記録。
// rev5: 無料プラン上限10件 (定数 freeMaxVisits)。
//
// 設計:
//   - 写真は List<String> の相対パスで保存(複数枚対応)
//   - 費用は円単位の int (国際対応は将来)
//   - 主訴・診断・治療は自由記述、enum化はしない(柔軟性優先)
//
// ============================================================================

import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_enums.dart';
import '../storage/photo_storage.dart';
import 'base_repository.dart';

class VisitsRepository extends BaseRepository {
  VisitsRepository(super.db);

  // ============================================================================
  // Read
  // ============================================================================

  Stream<List<VisitEntity>> watchForPet(int petId, {int? limit}) {
    final query = db.select(db.visits)
      ..where((Visits t) => t.petId.equals(petId) & t.deletedAt.isNull())
      ..orderBy(<OrderClauseGenerator<Visits>>[
        (Visits t) => OrderingTerm(
              expression: t.visitedAt,
              mode: OrderingMode.desc,
            ),
      ]);
    if (limit != null) query.limit(limit);
    return query.watch();
  }

  Stream<List<VisitEntity>> watchInRange({
    required int petId,
    required int fromMsec,
    required int toMsec,
  }) {
    return (db.select(db.visits)
          ..where((Visits t) =>
              t.petId.equals(petId) &
              t.deletedAt.isNull() &
              t.visitedAt.isBetweenValues(fromMsec, toMsec))
          ..orderBy(<OrderClauseGenerator<Visits>>[
            (Visits t) => OrderingTerm(expression: t.visitedAt),
          ]))
        .watch();
  }

  Future<VisitEntity?> getById(int id) {
    return (db.select(db.visits)
          ..where((Visits t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
  }

  /// 全グループでの記録総数(無料プラン上限チェック用)
  /// rev5: freeMaxVisits = 10
  Future<int> countAllVisits(String groupId) async {
    final result = await (db.selectOnly(db.visits)
          ..addColumns(<Expression<int>>[db.visits.id.count()])
          ..where(db.visits.groupId.equals(groupId) &
              db.visits.deletedAt.isNull()))
        .getSingle();
    return result.read(db.visits.id.count()) ?? 0;
  }

  // ============================================================================
  // Write
  // ============================================================================

  Future<int> create({
    required String groupId,
    required int petId,
    required int visitedAtMsec,
    required String reason,
    String? clinicName,
    String? vetName,
    String? diagnosis,
    String? treatment,
    int? costJpy,
    List<String>? photoPaths,
    String? notes,
    String? createdBy,
  }) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('reason cannot be empty');
    }
    if (costJpy != null && costJpy < 0) {
      throw ArgumentError('costJpy cannot be negative');
    }
    assertRelativePhotoPaths(photoPaths);
    final meta = buildCreateMetadata(groupId: groupId);

    final int newId = await db.into(db.visits).insert(
          VisitsCompanion.insert(
            groupId: Value(groupId),
            petId: petId,
            visitedAt: visitedAtMsec,
            clinicName: Value(_emptyToNull(clinicName)),
            vetName: Value(_emptyToNull(vetName)),
            reason: reason.trim(),
            diagnosis: Value(_emptyToNull(diagnosis)),
            treatment: Value(_emptyToNull(treatment)),
            costJpy: Value(costJpy),
            photoPaths: Value(photoPaths),
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
      targetTable: 'visits',
      recordId: newId,
      payloadJson: jsonEncode(<String, dynamic>{
        'petId': petId,
        'visitedAt': visitedAtMsec,
        'reason': reason,
      }),
    );
    return newId;
  }

  Future<bool> update({
    required int visitId,
    int? visitedAtMsec,
    String? clinicName,
    String? vetName,
    String? reason,
    String? diagnosis,
    String? treatment,
    int? costJpy,
    bool clearCost = false,
    List<String>? photoPaths,
    bool clearPhotos = false,
    String? notes,
  }) async {
    assertRelativePhotoPaths(photoPaths);
    final VisitEntity? existing = await getById(visitId);
    if (existing == null) throw StateError('Visit not found: id=$visitId');

    if (reason != null && reason.trim().isEmpty) {
      throw ArgumentError('reason cannot be empty');
    }
    if (costJpy != null && costJpy < 0) {
      throw ArgumentError('costJpy cannot be negative');
    }

    final meta = buildUpdateMetadata(groupId: existing.groupId);

    final companion = VisitsCompanion(
      visitedAt:
          visitedAtMsec == null ? const Value.absent() : Value(visitedAtMsec),
      clinicName: clinicName == null
          ? const Value.absent()
          : Value(_emptyToNull(clinicName)),
      vetName: vetName == null
          ? const Value.absent()
          : Value(_emptyToNull(vetName)),
      reason: reason == null ? const Value.absent() : Value(reason.trim()),
      diagnosis: diagnosis == null
          ? const Value.absent()
          : Value(_emptyToNull(diagnosis)),
      treatment: treatment == null
          ? const Value.absent()
          : Value(_emptyToNull(treatment)),
      costJpy: clearCost
          ? const Value(null)
          : (costJpy == null ? const Value.absent() : Value(costJpy)),
      photoPaths: clearPhotos
          ? const Value(null)
          : (photoPaths == null
              ? const Value.absent()
              : Value(photoPaths)),
      notes: notes == null
          ? const Value.absent()
          : Value(_emptyToNull(notes)),
      syncStatus: Value(meta.updatedSyncStatus),
      updatedAt: Value(meta.updatedAt),
      lastModifiedAtClient: Value(meta.lastModifiedAtClient),
    );

    final int affected = await (db.update(db.visits)
          ..where((Visits t) => t.id.equals(visitId)))
        .write(companion);

    if (affected > 0) {
      await enqueueSyncIfShared(
        groupId: existing.groupId,
        operation: SyncOperation.update,
        targetTable: 'visits',
        recordId: visitId,
        payloadJson: jsonEncode(<String, dynamic>{}),
      );
    }
    return affected > 0;
  }

  Future<bool> softDelete(int visitId) async {
    final VisitEntity? existing = await getById(visitId);
    if (existing == null) return false;

    final meta = buildDeleteMetadata(groupId: existing.groupId);
    final int affected = await (db.update(db.visits)
          ..where((Visits t) => t.id.equals(visitId)))
        .write(VisitsCompanion(
      deletedAt: Value(meta.deletedAt),
      syncStatus: Value(meta.updatedSyncStatus),
      updatedAt: Value(meta.updatedAt),
      lastModifiedAtClient: Value(meta.lastModifiedAtClient),
    ));

    if (affected > 0) {
      await enqueueSyncIfShared(
        groupId: existing.groupId,
        operation: SyncOperation.delete,
        targetTable: 'visits',
        recordId: visitId,
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
