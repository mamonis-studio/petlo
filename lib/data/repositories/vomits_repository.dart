// ============================================================================
// petlo - Vomits Repository
// ============================================================================
//
// 嘔吐記録のCRUD。
//
// rev5.5 §F-04: **2階層色** (メイン4色 + 詳細5色)
//   メイン: clear / yellow / brown / food
//   詳細 (「Other」経由): white_foam / red / green / black / other
//
// 加えて:
//   - count: 1日にまとめて記録(回数)
//   - amount: 3段階
//   - containsFood: 食べたものが混じっているか(boolean)
//   - suspectIngestion: 異物誤飲の疑い(boolean)
//   - colorOtherText: VomitColor.other 選択時の自由記述
//
// ============================================================================

import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_enums.dart';
import 'base_repository.dart';

class VomitsRepository extends BaseRepository {
  VomitsRepository(super.db);

  // ============================================================================
  // Read
  // ============================================================================

  Stream<List<VomitEntity>> watchForPet(int petId, {int? limit}) {
    final query = db.select(db.vomits)
      ..where((Vomits t) => t.petId.equals(petId) & t.deletedAt.isNull())
      ..orderBy(<OrderClauseGenerator<Vomits>>[
        (Vomits t) => OrderingTerm(
              expression: t.vomitedAt,
              mode: OrderingMode.desc,
            ),
      ]);
    if (limit != null) query.limit(limit);
    return query.watch();
  }

  Future<VomitEntity?> getById(int id) {
    return (db.select(db.vomits)
          ..where((Vomits t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
  }

  // ============================================================================
  // Write
  // ============================================================================

  Future<int> create({
    required String groupId,
    required int petId,
    required VomitColor color,
    String? colorOtherText,
    required RecordAmount amount,
    required int count,
    required bool containsFood,
    required bool suspectIngestion,
    required int vomitedAtMsec,
    String? notes,
    String? photoPath,
    String? createdBy,
  }) async {
    if (count < 1) {
      throw ArgumentError('count must be >= 1, got $count');
    }
    if (color == VomitColor.other &&
        (colorOtherText == null || colorOtherText.trim().isEmpty)) {
      throw ArgumentError('colorOtherText required when color is "other"');
    }

    final meta = buildCreateMetadata(groupId: groupId);

    final int newId = await db.into(db.vomits).insert(
          VomitsCompanion.insert(
            groupId: Value(groupId),
            petId: petId,
            color: color,
            colorOtherText: Value(colorOtherText?.trim()),
            amount: amount,
            count: Value(count),
            containsFood: Value(containsFood),
            suspectIngestion: Value(suspectIngestion),
            vomitedAt: vomitedAtMsec,
            notes: Value(notes?.trim().isEmpty == true ? null : notes?.trim()),
            photoPath: Value(photoPath),
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
      targetTable: 'vomits',
      recordId: newId,
      payloadJson: jsonEncode(<String, dynamic>{
        'petId': petId,
        'color': color.name,
        'colorOtherText': colorOtherText,
        'amount': amount.name,
        'count': count,
        'containsFood': containsFood,
        'suspectIngestion': suspectIngestion,
        'vomitedAt': vomitedAtMsec,
      }),
    );
    return newId;
  }

  Future<bool> update({
    required int vomitId,
    VomitColor? color,
    String? colorOtherText,
    bool clearColorOtherText = false,
    RecordAmount? amount,
    int? count,
    bool? containsFood,
    bool? suspectIngestion,
    int? vomitedAtMsec,
    String? notes,
    String? photoPath,
    bool clearPhoto = false,
  }) async {
    final VomitEntity? existing = await getById(vomitId);
    if (existing == null) throw StateError('Vomit not found: id=$vomitId');

    if (count != null && count < 1) {
      throw ArgumentError('count must be >= 1');
    }

    final meta = buildUpdateMetadata(groupId: existing.groupId);

    final companion = VomitsCompanion(
      color: color == null ? const Value.absent() : Value(color),
      colorOtherText: clearColorOtherText
          ? const Value(null)
          : (colorOtherText == null
              ? const Value.absent()
              : Value(colorOtherText.trim().isEmpty ? null : colorOtherText.trim())),
      amount: amount == null ? const Value.absent() : Value(amount),
      count: count == null ? const Value.absent() : Value(count),
      containsFood: containsFood == null
          ? const Value.absent()
          : Value(containsFood),
      suspectIngestion: suspectIngestion == null
          ? const Value.absent()
          : Value(suspectIngestion),
      vomitedAt: vomitedAtMsec == null
          ? const Value.absent()
          : Value(vomitedAtMsec),
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

    final int affected = await (db.update(db.vomits)
          ..where((Vomits t) => t.id.equals(vomitId)))
        .write(companion);

    if (affected > 0) {
      await enqueueSyncIfShared(
        groupId: existing.groupId,
        operation: SyncOperation.update,
        targetTable: 'vomits',
        recordId: vomitId,
        payloadJson: jsonEncode(<String, dynamic>{}),
      );
    }
    return affected > 0;
  }

  Future<bool> softDelete(int vomitId) async {
    final VomitEntity? existing = await getById(vomitId);
    if (existing == null) return false;

    final meta = buildDeleteMetadata(groupId: existing.groupId);
    final int affected = await (db.update(db.vomits)
          ..where((Vomits t) => t.id.equals(vomitId)))
        .write(VomitsCompanion(
      deletedAt: Value(meta.deletedAt),
      syncStatus: Value(meta.updatedSyncStatus),
      updatedAt: Value(meta.updatedAt),
      lastModifiedAtClient: Value(meta.lastModifiedAtClient),
    ));

    if (affected > 0) {
      await enqueueSyncIfShared(
        groupId: existing.groupId,
        operation: SyncOperation.delete,
        targetTable: 'vomits',
        recordId: vomitId,
        payloadJson: jsonEncode(<String, dynamic>{}),
      );
    }
    return affected > 0;
  }
}
