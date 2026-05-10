// ============================================================================
// petlo - Foods Repository
// ============================================================================
//
// 食事銘柄マスタ (foods テーブル) の管理。
//
// 設計:
//   - foods は完全にローカル(共有しない、各ユーザー個別)
//   - useCount + lastUsedAt で「直近3銘柄」「人気3銘柄」を取得
//   - 直近3銘柄UI (rev3 F-01) → 食事記録画面で素早く再選択
//
// ============================================================================

import 'package:drift/drift.dart';

import '../local/app_database.dart';

class FoodsRepository {
  FoodsRepository(this.db);

  final AppDatabase db;

  int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  // ============================================================================
  // Read
  // ============================================================================

  /// 直近使用順の上位N件 (デフォルト3)
  /// 食事記録画面の「直近3銘柄」ボタン用
  Stream<List<FoodEntity>> watchRecentFoods({int limit = 3}) {
    return (db.select(db.foods)
          ..orderBy(<OrderClauseGenerator<Foods>>[
            (Foods t) => OrderingTerm(
                  expression: t.lastUsedAt,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(limit))
        .watch();
  }

  /// 全件取得 (検索や管理画面用)
  Stream<List<FoodEntity>> watchAllFoods() {
    return (db.select(db.foods)
          ..orderBy(<OrderClauseGenerator<Foods>>[
            (Foods t) => OrderingTerm(
                  expression: t.lastUsedAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .watch();
  }

  /// 名前で曖昧検索 (LIKE %query%)
  Future<List<FoodEntity>> searchByName(String query) async {
    if (query.trim().isEmpty) return <FoodEntity>[];
    return (db.select(db.foods)
          ..where((Foods t) => t.name.like('%${query.trim()}%'))
          ..orderBy(<OrderClauseGenerator<Foods>>[
            (Foods t) => OrderingTerm(
                  expression: t.useCount,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(20))
        .get();
  }

  Future<FoodEntity?> getById(int id) {
    return (db.select(db.foods)
          ..where((Foods t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
  }

  /// 同名銘柄が既に存在するか (重複登録防止)
  Future<FoodEntity?> findByExactName(String name) {
    return (db.select(db.foods)
          ..where((Foods t) => t.name.equals(name.trim()))
          ..limit(1))
        .getSingleOrNull();
  }

  // ============================================================================
  // Write
  // ============================================================================

  /// 銘柄を新規作成、または既存の同名銘柄を返す。
  /// 食事記録時に「初めての銘柄」を自動登録する用途。
  Future<int> upsertByName({
    required String name,
    String? brand,
    int? defaultAmountG,
  }) async {
    final FoodEntity? existing = await findByExactName(name);
    if (existing != null) {
      // 既存: useCount増 + lastUsedAt更新
      await touchUsage(existing.id);
      return existing.id;
    }

    // 新規
    final int t = _now();
    return db.into(db.foods).insert(
          FoodsCompanion.insert(
            name: name.trim(),
            brand: Value(brand),
            defaultAmountG: Value(defaultAmountG),
            lastUsedAt: t,
            useCount: const Value(1),
            createdAt: t,
          ),
        );
  }

  /// 既存銘柄の使用情報を更新 (記録時に呼ばれる)
  Future<void> touchUsage(int foodId) async {
    final FoodEntity? food = await getById(foodId);
    if (food == null) return;

    await (db.update(db.foods)..where((Foods t) => t.id.equals(foodId)))
        .write(FoodsCompanion(
      lastUsedAt: Value(_now()),
      useCount: Value(food.useCount + 1),
    ));
  }

  /// 銘柄削除 (使用中の食事記録があってもOK、過去記録は文字列のまま残る想定)
  Future<bool> deleteFood(int foodId) async {
    final int affected = await (db.delete(db.foods)
          ..where((Foods t) => t.id.equals(foodId)))
        .go();
    return affected > 0;
  }
}
