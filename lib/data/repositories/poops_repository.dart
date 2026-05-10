// ============================================================================
// petlo - Poops Repository
// ============================================================================
//
// うんち記録のCRUD。
// rev3 F-02: ブリストル5段階形状 + 5色 + 量(3段階)
// rev5: AI画像診断と連動可能(aiDiagnosisId)
//
// ============================================================================

import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_enums.dart';
import 'base_repository.dart';

class PoopsRepository extends BaseRepository {
  PoopsRepository(super.db);

  // ============================================================================
  // Read
  // ============================================================================

  Stream<List<PoopEntity>> watchForPet(int petId, {int? limit}) {
    final query = db.select(db.poops)
      ..where((Poops t) => t.petId.equals(petId) & t.deletedAt.isNull())
      ..orderBy(<OrderClauseGenerator<Poops>>[
        (Poops t) => OrderingTerm(
              expression: t.pooedAt,
              mode: OrderingMode.desc,
            ),
      ]);
    if (limit != null) query.limit(limit);
    return query.watch();
  }

  Stream<List<PoopEntity>> watchInRange({
    required int petId,
    required int fromMsec,
    required int toMsec,
  }) {
    return (db.select(db.poops)
          ..where((Poops t) =>
              t.petId.equals(petId) &
              t.deletedAt.isNull() &
              t.pooedAt.isBetweenValues(fromMsec, toMsec))
          ..orderBy(<OrderClauseGenerator<Poops>>[
            (Poops t) => OrderingTerm(expression: t.pooedAt),
          ]))
        .watch();
  }

  Future<PoopEntity?> getById(int id) {
    return (db.select(db.poops)
          ..where((Poops t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
  }

  // ============================================================================
  // Write
  // ============================================================================

  Future<int> create({
    required String groupId,
    required int petId,
    required PoopForm form,
    required PoopColor color,
    required RecordAmount amount,
    required int pooedAtMsec,
    String? notes,
    String? photoPath,
    int? aiDiagnosisId,
    String? createdBy,
  }) async {
    final meta = buildCreateMetadata(groupId: groupId);

    final int newId = await db.into(db.poops).insert(
          PoopsCompanion.insert(
            groupId: Value(groupId),
            petId: petId,
            form: form,
            color: color,
            amount: amount,
            pooedAt: pooedAtMsec,
            notes: Value(notes?.trim().isEmpty == true ? null : notes?.trim()),
            photoPath: Value(photoPath),
            aiDiagnosisId: Value(aiDiagnosisId),
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
      targetTable: 'poops',
      recordId: newId,
      payloadJson: jsonEncode(<String, dynamic>{
        'petId': petId,
        'form': form.name,
        'color': color.name,
        'amount': amount.name,
        'pooedAt': pooedAtMsec,
      }),
    );
    return newId;
  }

  Future<bool> update({
    required int poopId,
    PoopForm? form,
    PoopColor? color,
    RecordAmount? amount,
    int? pooedAtMsec,
    String? notes,
    String? photoPath,
    bool clearPhoto = false,
  }) async {
    final PoopEntity? existing = await getById(poopId);
    if (existing == null) throw StateError('Poop not found: id=$poopId');

    final meta = buildUpdateMetadata(groupId: existing.groupId);

    final companion = PoopsCompanion(
      form: form == null ? const Value.absent() : Value(form),
      color: color == null ? const Value.absent() : Value(color),
      amount: amount == null ? const Value.absent() : Value(amount),
      pooedAt: pooedAtMsec == null ? const Value.absent() : Value(pooedAtMsec),
      notes: notes == null
          ? const Value.absent()
          : Value(notes.trim().isEmpty ? null : notes.trim()),
      photoPath: clearPhoto
          ? const Value(null)
          : (photoPath == null ? const Value.absent() : Value(photoPath)),
      syncStatus: Value(meta.updatedSyncStatus),
      updatedAt: Value(meta.updatedAt),
      lastModifiedAtClient: Value(meta.lastModifiedAtClient),
    );

    final int affected = await (db.update(db.poops)
          ..where((Poops t) => t.id.equals(poopId)))
        .write(companion);

    if (affected > 0) {
      await enqueueSyncIfShared(
        groupId: existing.groupId,
        operation: SyncOperation.update,
        targetTable: 'poops',
        recordId: poopId,
        payloadJson: jsonEncode(<String, dynamic>{}),
      );
    }
    return affected > 0;
  }

  Future<bool> softDelete(int poopId) async {
    final PoopEntity? existing = await getById(poopId);
    if (existing == null) return false;

    final meta = buildDeleteMetadata(groupId: existing.groupId);
    final int affected = await (db.update(db.poops)
          ..where((Poops t) => t.id.equals(poopId)))
        .write(PoopsCompanion(
      deletedAt: Value(meta.deletedAt),
      syncStatus: Value(meta.updatedSyncStatus),
      updatedAt: Value(meta.updatedAt),
      lastModifiedAtClient: Value(meta.lastModifiedAtClient),
    ));

    if (affected > 0) {
      await enqueueSyncIfShared(
        groupId: existing.groupId,
        operation: SyncOperation.delete,
        targetTable: 'poops',
        recordId: poopId,
        payloadJson: jsonEncode(<String, dynamic>{}),
      );
    }
    return affected > 0;
  }
}
