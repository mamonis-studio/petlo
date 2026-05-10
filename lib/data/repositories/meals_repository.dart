// ============================================================================
// petlo - Meals Repository
// ============================================================================
//
// 食事記録のCRUD。
//
// 設計:
//   - PetsRepository と同じパターン (BaseRepository 継承、Personal/Shared対応)
//   - foodId と foodNameFreeText の二択 (マスタ参照 or フリー入力)
//   - 写真は別途 PhotoStorage で保存、photoPath は相対パス
//
// ============================================================================

import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_enums.dart';
import 'base_repository.dart';

class MealsRepository extends BaseRepository {
  MealsRepository(super.db);

  // ============================================================================
  // Read
  // ============================================================================

  /// 他リポジトリと API 名を揃えるためのエイリアス。
  /// `watchMealsForPet` 既存呼び出しはそのまま温存している。
  Stream<List<MealEntity>> watchForPet(int petId, {int? limit}) =>
      watchMealsForPet(petId, limit: limit);

  /// 指定ペットの食事記録 (新しい順、論理削除済み除く)
  Stream<List<MealEntity>> watchMealsForPet(int petId, {int? limit}) {
    final query = db.select(db.meals)
      ..where((Meals t) =>
          t.petId.equals(petId) & t.deletedAt.isNull())
      ..orderBy(<OrderClauseGenerator<Meals>>[
        (Meals t) => OrderingTerm(
              expression: t.eatenAt,
              mode: OrderingMode.desc,
            ),
      ]);
    if (limit != null) query.limit(limit);
    return query.watch();
  }

  /// 期間内の食事記録 (グラフや週次集計用)
  Stream<List<MealEntity>> watchMealsInRange({
    required int petId,
    required int fromMsec,
    required int toMsec,
  }) {
    return (db.select(db.meals)
          ..where((Meals t) =>
              t.petId.equals(petId) &
              t.deletedAt.isNull() &
              t.eatenAt.isBetweenValues(fromMsec, toMsec))
          ..orderBy(<OrderClauseGenerator<Meals>>[
            (Meals t) => OrderingTerm(expression: t.eatenAt),
          ]))
        .watch();
  }

  Future<MealEntity?> getById(int id) {
    return (db.select(db.meals)
          ..where((Meals t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
  }

  /// 当月の記録件数 (無料プラン上限チェック用、rev5)
  Future<int> countMealsThisMonth(String groupId) async {
    final DateTime now = DateTime.now();
    final DateTime monthStart = DateTime(now.year, now.month);
    final int from = monthStart.toUtc().millisecondsSinceEpoch;

    final result = await (db.selectOnly(db.meals)
          ..addColumns(<Expression<int>>[db.meals.id.count()])
          ..where(db.meals.groupId.equals(groupId) &
              db.meals.deletedAt.isNull() &
              db.meals.createdAt.isBiggerOrEqualValue(from)))
        .getSingle();
    return result.read(db.meals.id.count()) ?? 0;
  }

  // ============================================================================
  // Write — Create
  // ============================================================================

  Future<int> createMeal({
    required String groupId,
    required int petId,
    int? foodId,
    String? foodNameFreeText,
    int? amountG,
    required MealAppetite appetite,
    required int eatenAtMsec,
    String? notes,
    String? photoPath,
    String? createdBy,
  }) async {
    if (foodId == null &&
        (foodNameFreeText == null || foodNameFreeText.trim().isEmpty)) {
      throw ArgumentError('foodId または foodNameFreeText のどちらかが必要');
    }

    final meta = buildCreateMetadata(groupId: groupId);

    final int newId = await db.into(db.meals).insert(
          MealsCompanion.insert(
            groupId: Value(groupId),
            petId: petId,
            foodId: Value(foodId),
            foodNameFreeText: Value(foodNameFreeText?.trim()),
            amountG: Value(amountG),
            appetite: appetite,
            eatenAt: eatenAtMsec,
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
      targetTable: 'meals',
      recordId: newId,
      payloadJson: jsonEncode(<String, dynamic>{
        'petId': petId,
        'foodId': foodId,
        'foodNameFreeText': foodNameFreeText,
        'amountG': amountG,
        'appetite': appetite.name,
        'eatenAt': eatenAtMsec,
      }),
    );

    return newId;
  }

  // ============================================================================
  // Write — Update
  // ============================================================================

  Future<bool> updateMeal({
    required int mealId,
    int? foodId,
    bool clearFoodId = false,
    String? foodNameFreeText,
    int? amountG,
    bool clearAmountG = false,
    MealAppetite? appetite,
    int? eatenAtMsec,
    String? notes,
    String? photoPath,
    bool clearPhoto = false,
  }) async {
    final MealEntity? existing = await getById(mealId);
    if (existing == null) {
      throw StateError('Meal not found: id=$mealId');
    }

    final meta = buildUpdateMetadata(groupId: existing.groupId);

    final companion = MealsCompanion(
      foodId: clearFoodId ? const Value(null) : (foodId == null ? const Value.absent() : Value(foodId)),
      foodNameFreeText: foodNameFreeText == null
          ? const Value.absent()
          : Value(foodNameFreeText.trim().isEmpty ? null : foodNameFreeText.trim()),
      amountG: clearAmountG ? const Value(null) : (amountG == null ? const Value.absent() : Value(amountG)),
      appetite: appetite == null ? const Value.absent() : Value(appetite),
      eatenAt: eatenAtMsec == null ? const Value.absent() : Value(eatenAtMsec),
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

    final int affected = await (db.update(db.meals)
          ..where((Meals t) => t.id.equals(mealId)))
        .write(companion);

    if (affected > 0) {
      await enqueueSyncIfShared(
        groupId: existing.groupId,
        operation: SyncOperation.update,
        targetTable: 'meals',
        recordId: mealId,
        payloadJson: jsonEncode(<String, dynamic>{}),
      );
    }
    return affected > 0;
  }

  // ============================================================================
  // Write — Delete (論理削除)
  // ============================================================================

  Future<bool> softDelete(int mealId) async {
    final MealEntity? existing = await getById(mealId);
    if (existing == null) return false;

    final meta = buildDeleteMetadata(groupId: existing.groupId);

    final int affected = await (db.update(db.meals)
          ..where((Meals t) => t.id.equals(mealId)))
        .write(MealsCompanion(
      deletedAt: Value(meta.deletedAt),
      syncStatus: Value(meta.updatedSyncStatus),
      updatedAt: Value(meta.updatedAt),
      lastModifiedAtClient: Value(meta.lastModifiedAtClient),
    ));

    if (affected > 0) {
      await enqueueSyncIfShared(
        groupId: existing.groupId,
        operation: SyncOperation.delete,
        targetTable: 'meals',
        recordId: mealId,
        payloadJson: jsonEncode(<String, dynamic>{}),
      );
    }
    return affected > 0;
  }
}
