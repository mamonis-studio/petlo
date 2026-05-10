// ============================================================================
// petlo - Temperatures Repository
// ============================================================================
//
// 体温記録のCRUD。
//
// 設計:
//   - 値は **小数1桁の摂氏 × 10 の int** で保存(0.1℃精度)
//     例: 38.5°C → 385
//   - 華氏は UI 側で変換
//   - 無料: 履歴3ヶ月のみ (rev5)
//   - Pro: 全履歴 + グラフ + 異常値警告
//
// 体温の正常範囲:
//   - 犬: 37.5 - 39.0°C
//   - 猫: 38.0 - 39.5°C
//   - 上下逸脱は要注意 (UI側で警告色)
//
// ============================================================================

import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_enums.dart';
import 'base_repository.dart';

class TemperaturesRepository extends BaseRepository {
  TemperaturesRepository(super.db);

  // ============================================================================
  // Read
  // ============================================================================

  Stream<List<TemperatureEntity>> watchForPet(int petId, {int? limit}) {
    final query = db.select(db.temperatures)
      ..where((Temperatures t) =>
          t.petId.equals(petId) & t.deletedAt.isNull())
      ..orderBy(<OrderClauseGenerator<Temperatures>>[
        (Temperatures t) => OrderingTerm(
              expression: t.measuredAt,
              mode: OrderingMode.desc,
            ),
      ]);
    if (limit != null) query.limit(limit);
    return query.watch();
  }

  Stream<List<TemperatureEntity>> watchInRange({
    required int petId,
    required int fromMsec,
    required int toMsec,
  }) {
    return (db.select(db.temperatures)
          ..where((Temperatures t) =>
              t.petId.equals(petId) &
              t.deletedAt.isNull() &
              t.measuredAt.isBetweenValues(fromMsec, toMsec))
          ..orderBy(<OrderClauseGenerator<Temperatures>>[
            (Temperatures t) => OrderingTerm(expression: t.measuredAt),
          ]))
        .watch();
  }

  Stream<TemperatureEntity?> watchLatest(int petId) {
    return (db.select(db.temperatures)
          ..where((Temperatures t) =>
              t.petId.equals(petId) & t.deletedAt.isNull())
          ..orderBy(<OrderClauseGenerator<Temperatures>>[
            (Temperatures t) => OrderingTerm(
                  expression: t.measuredAt,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(1))
        .watchSingleOrNull();
  }

  Future<TemperatureEntity?> getById(int id) {
    return (db.select(db.temperatures)
          ..where((Temperatures t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
  }

  // ============================================================================
  // Write
  // ============================================================================

  Future<int> create({
    required String groupId,
    required int petId,
    required int tempCelsiusX10, // 摂氏×10 (例: 38.5°C → 385)
    required int measuredAtMsec,
    String? notes,
    String? createdBy,
  }) async {
    // 妥当性チェック: 30.0°C(=300)未満 or 45.0°C(=450)超は明らかに誤入力
    if (tempCelsiusX10 < 300 || tempCelsiusX10 > 450) {
      throw ArgumentError('Invalid tempCelsiusX10: $tempCelsiusX10');
    }
    final meta = buildCreateMetadata(groupId: groupId);

    final int newId = await db.into(db.temperatures).insert(
          TemperaturesCompanion.insert(
            groupId: Value(groupId),
            petId: petId,
            tempCelsiusX10: tempCelsiusX10,
            measuredAt: measuredAtMsec,
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
      targetTable: 'temperatures',
      recordId: newId,
      payloadJson: jsonEncode(<String, dynamic>{
        'petId': petId,
        'tempCelsiusX10': tempCelsiusX10,
        'measuredAt': measuredAtMsec,
      }),
    );
    return newId;
  }

  Future<bool> update({
    required int tempId,
    int? tempCelsiusX10,
    int? measuredAtMsec,
    String? notes,
  }) async {
    final TemperatureEntity? existing = await getById(tempId);
    if (existing == null) {
      throw StateError('Temperature not found: id=$tempId');
    }

    if (tempCelsiusX10 != null &&
        (tempCelsiusX10 < 300 || tempCelsiusX10 > 450)) {
      throw ArgumentError('Invalid tempCelsiusX10: $tempCelsiusX10');
    }

    final meta = buildUpdateMetadata(groupId: existing.groupId);
    final int affected = await (db.update(db.temperatures)
          ..where((Temperatures t) => t.id.equals(tempId)))
        .write(TemperaturesCompanion(
      tempCelsiusX10: tempCelsiusX10 == null
          ? const Value.absent()
          : Value(tempCelsiusX10),
      measuredAt: measuredAtMsec == null
          ? const Value.absent()
          : Value(measuredAtMsec),
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
        targetTable: 'temperatures',
        recordId: tempId,
        payloadJson: jsonEncode(<String, dynamic>{}),
      );
    }
    return affected > 0;
  }

  Future<bool> softDelete(int tempId) async {
    final TemperatureEntity? existing = await getById(tempId);
    if (existing == null) return false;

    final meta = buildDeleteMetadata(groupId: existing.groupId);
    final int affected = await (db.update(db.temperatures)
          ..where((Temperatures t) => t.id.equals(tempId)))
        .write(TemperaturesCompanion(
      deletedAt: Value(meta.deletedAt),
      syncStatus: Value(meta.updatedSyncStatus),
      updatedAt: Value(meta.updatedAt),
      lastModifiedAtClient: Value(meta.lastModifiedAtClient),
    ));

    if (affected > 0) {
      await enqueueSyncIfShared(
        groupId: existing.groupId,
        operation: SyncOperation.delete,
        targetTable: 'temperatures',
        recordId: tempId,
        payloadJson: jsonEncode(<String, dynamic>{}),
      );
    }
    return affected > 0;
  }
}
