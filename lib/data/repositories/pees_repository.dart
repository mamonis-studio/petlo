// ============================================================================
// petlo - Pees Repository
// ============================================================================
//
// おしっこ記録のCRUD。
// rev3 F-03: 6色 + 量(3段階) + 回数(count、複数回まとめ可)
//
// ============================================================================

import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_enums.dart';
import 'base_repository.dart';

class PeesRepository extends BaseRepository {
  PeesRepository(super.db);

  // ============================================================================
  // Read
  // ============================================================================

  Stream<List<PeeEntity>> watchForPet(int petId, {int? limit}) {
    final query = db.select(db.pees)
      ..where((Pees t) => t.petId.equals(petId) & t.deletedAt.isNull())
      ..orderBy(<OrderClauseGenerator<Pees>>[
        (Pees t) => OrderingTerm(
              expression: t.peedAt,
              mode: OrderingMode.desc,
            ),
      ]);
    if (limit != null) query.limit(limit);
    return query.watch();
  }

  Future<PeeEntity?> getById(int id) {
    return (db.select(db.pees)
          ..where((Pees t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
  }

  // ============================================================================
  // Write
  // ============================================================================

  Future<int> create({
    required String groupId,
    required int petId,
    required PeeColor color,
    required RecordAmount amount,
    required int count,
    required int peedAtMsec,
    String? notes,
    String? createdBy,
  }) async {
    if (count < 1) {
      throw ArgumentError('count must be >= 1, got $count');
    }
    final meta = buildCreateMetadata(groupId: groupId);

    final int newId = await db.into(db.pees).insert(
          PeesCompanion.insert(
            groupId: Value(groupId),
            petId: petId,
            color: color,
            amount: amount,
            count: Value(count),
            peedAt: peedAtMsec,
            notes: Value(notes?.trim().isEmpty == true ? null : notes?.trim()),
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
      targetTable: 'pees',
      recordId: newId,
      payloadJson: jsonEncode(<String, dynamic>{
        'petId': petId,
        'color': color.name,
        'amount': amount.name,
        'count': count,
        'peedAt': peedAtMsec,
      }),
    );
    return newId;
  }

  Future<bool> update({
    required int peeId,
    PeeColor? color,
    RecordAmount? amount,
    int? count,
    int? peedAtMsec,
    String? notes,
  }) async {
    final PeeEntity? existing = await getById(peeId);
    if (existing == null) throw StateError('Pee not found: id=$peeId');

    if (count != null && count < 1) {
      throw ArgumentError('count must be >= 1');
    }

    final meta = buildUpdateMetadata(groupId: existing.groupId);

    final int affected = await (db.update(db.pees)
          ..where((Pees t) => t.id.equals(peeId)))
        .write(PeesCompanion(
      color: color == null ? const Value.absent() : Value(color),
      amount: amount == null ? const Value.absent() : Value(amount),
      count: count == null ? const Value.absent() : Value(count),
      peedAt: peedAtMsec == null ? const Value.absent() : Value(peedAtMsec),
      notes: notes == null
          ? const Value.absent()
          : Value(notes.trim().isEmpty ? null : notes.trim()),
      syncStatus: Value(meta.updatedSyncStatus),
      updatedAt: Value(meta.updatedAt),
      lastModifiedAtClient: Value(meta.lastModifiedAtClient),
    ));

    if (affected > 0) {
      await enqueueSyncIfShared(
        groupId: existing.groupId,
        operation: SyncOperation.update,
        targetTable: 'pees',
        recordId: peeId,
        payloadJson: jsonEncode(<String, dynamic>{}),
      );
    }
    return affected > 0;
  }

  Future<bool> softDelete(int peeId) async {
    final PeeEntity? existing = await getById(peeId);
    if (existing == null) return false;

    final meta = buildDeleteMetadata(groupId: existing.groupId);
    final int affected = await (db.update(db.pees)
          ..where((Pees t) => t.id.equals(peeId)))
        .write(PeesCompanion(
      deletedAt: Value(meta.deletedAt),
      syncStatus: Value(meta.updatedSyncStatus),
      updatedAt: Value(meta.updatedAt),
      lastModifiedAtClient: Value(meta.lastModifiedAtClient),
    ));

    if (affected > 0) {
      await enqueueSyncIfShared(
        groupId: existing.groupId,
        operation: SyncOperation.delete,
        targetTable: 'pees',
        recordId: peeId,
        payloadJson: jsonEncode(<String, dynamic>{}),
      );
    }
    return affected > 0;
  }
}
