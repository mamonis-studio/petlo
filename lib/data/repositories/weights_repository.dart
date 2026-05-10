// ============================================================================
// petlo - Weights Repository
// ============================================================================
//
// 体重記録のCRUD。
//
// 設計:
//   - 値は **グラム単位の int** で保存(kg/lb は UI 側で変換)
//   - measuredAt 時刻ベースで時系列管理
//   - 無料プラン: 履歴3ヶ月のみ表示 (rev5)
//   - Pro: 全履歴 + グラフ
//
// rev5 連動:
//   - bcs_checks テーブルとは独立 (体重から自動推定するロジックは別Repo)
//   - 理想体重(pet.idealWeightMin/MaxG)との比較は UI 側で
//
// ============================================================================

import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_enums.dart';
import 'base_repository.dart';

class WeightsRepository extends BaseRepository {
  WeightsRepository(super.db);

  // ============================================================================
  // Read
  // ============================================================================

  /// ペットの全履歴(新しい順)
  Stream<List<WeightEntity>> watchForPet(int petId, {int? limit}) {
    final query = db.select(db.weights)
      ..where((Weights t) => t.petId.equals(petId) & t.deletedAt.isNull())
      ..orderBy(<OrderClauseGenerator<Weights>>[
        (Weights t) => OrderingTerm(
              expression: t.measuredAt,
              mode: OrderingMode.desc,
            ),
      ]);
    if (limit != null) query.limit(limit);
    return query.watch();
  }

  /// 期間内の体重 (グラフ用、古い順)
  Stream<List<WeightEntity>> watchInRange({
    required int petId,
    required int fromMsec,
    required int toMsec,
  }) {
    return (db.select(db.weights)
          ..where((Weights t) =>
              t.petId.equals(petId) &
              t.deletedAt.isNull() &
              t.measuredAt.isBetweenValues(fromMsec, toMsec))
          ..orderBy(<OrderClauseGenerator<Weights>>[
            (Weights t) => OrderingTerm(expression: t.measuredAt),
          ]))
        .watch();
  }

  /// 最新の体重1件 (ホーム画面の「現在体重」表示用)
  Stream<WeightEntity?> watchLatest(int petId) {
    return (db.select(db.weights)
          ..where(
              (Weights t) => t.petId.equals(petId) & t.deletedAt.isNull())
          ..orderBy(<OrderClauseGenerator<Weights>>[
            (Weights t) => OrderingTerm(
                  expression: t.measuredAt,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(1))
        .watchSingleOrNull();
  }

  Future<WeightEntity?> getById(int id) {
    return (db.select(db.weights)
          ..where((Weights t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
  }

  // ============================================================================
  // Write
  // ============================================================================

  Future<int> create({
    required String groupId,
    required int petId,
    required int weightG,
    required int measuredAtMsec,
    String? notes,
    String? createdBy,
  }) async {
    if (weightG <= 0) {
      throw ArgumentError('weightG must be > 0, got $weightG');
    }
    if (weightG > 200000) {
      // 200kg超は明らかに誤入力 (世界最大の犬でも100kg程度)
      throw ArgumentError('weightG too large: $weightG');
    }
    final meta = buildCreateMetadata(groupId: groupId);

    final int newId = await db.into(db.weights).insert(
          WeightsCompanion.insert(
            groupId: Value(groupId),
            petId: petId,
            weightG: weightG,
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
      targetTable: 'weights',
      recordId: newId,
      payloadJson: jsonEncode(<String, dynamic>{
        'petId': petId,
        'weightG': weightG,
        'measuredAt': measuredAtMsec,
      }),
    );
    return newId;
  }

  Future<bool> update({
    required int weightId,
    int? weightG,
    int? measuredAtMsec,
    String? notes,
  }) async {
    final WeightEntity? existing = await getById(weightId);
    if (existing == null) throw StateError('Weight not found: id=$weightId');

    if (weightG != null && (weightG <= 0 || weightG > 200000)) {
      throw ArgumentError('Invalid weightG: $weightG');
    }

    final meta = buildUpdateMetadata(groupId: existing.groupId);
    final int affected = await (db.update(db.weights)
          ..where((Weights t) => t.id.equals(weightId)))
        .write(WeightsCompanion(
      weightG: weightG == null ? const Value.absent() : Value(weightG),
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
        targetTable: 'weights',
        recordId: weightId,
        payloadJson: jsonEncode(<String, dynamic>{}),
      );
    }
    return affected > 0;
  }

  Future<bool> softDelete(int weightId) async {
    final WeightEntity? existing = await getById(weightId);
    if (existing == null) return false;

    final meta = buildDeleteMetadata(groupId: existing.groupId);
    final int affected = await (db.update(db.weights)
          ..where((Weights t) => t.id.equals(weightId)))
        .write(WeightsCompanion(
      deletedAt: Value(meta.deletedAt),
      syncStatus: Value(meta.updatedSyncStatus),
      updatedAt: Value(meta.updatedAt),
      lastModifiedAtClient: Value(meta.lastModifiedAtClient),
    ));

    if (affected > 0) {
      await enqueueSyncIfShared(
        groupId: existing.groupId,
        operation: SyncOperation.delete,
        targetTable: 'weights',
        recordId: weightId,
        payloadJson: jsonEncode(<String, dynamic>{}),
      );
    }
    return affected > 0;
  }
}
