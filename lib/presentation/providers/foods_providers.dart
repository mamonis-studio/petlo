// ============================================================================
// petlo - Foods Providers
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/foods_repository.dart';
import 'database_provider.dart';

final Provider<FoodsRepository> foodsRepositoryProvider =
    Provider<FoodsRepository>(
  (Ref ref) {
    final AppDatabase db = ref.watch(appDatabaseProvider);
    return FoodsRepository(db);
  },
);

/// 直近3銘柄 (rev3 F-01: 食事記録画面の素早い再選択用)
final StreamProvider<List<FoodEntity>> recentFoodsProvider =
    StreamProvider<List<FoodEntity>>(
  (Ref ref) {
    final FoodsRepository repo = ref.watch(foodsRepositoryProvider);
    return repo.watchRecentFoods(limit: 3);
  },
);

/// 全銘柄(管理画面・検索基盤)
final StreamProvider<List<FoodEntity>> allFoodsProvider =
    StreamProvider<List<FoodEntity>>(
  (Ref ref) {
    final FoodsRepository repo = ref.watch(foodsRepositoryProvider);
    return repo.watchAllFoods();
  },
);
