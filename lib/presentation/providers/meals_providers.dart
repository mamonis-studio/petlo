// ============================================================================
// petlo - Meals Providers
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/meals_repository.dart';
import 'database_provider.dart';
import 'scope_providers.dart';

final Provider<MealsRepository> mealsRepositoryProvider =
    Provider<MealsRepository>(
  (Ref ref) {
    final AppDatabase db = ref.watch(appDatabaseProvider);
    return MealsRepository(db);
  },
);

/// 現在ペットの食事記録 Stream (新しい順)
/// 単一ペット選択中の時のみ動作、All mode/未選択時は空リスト。
final StreamProvider<List<MealEntity>> currentPetMealsProvider =
    StreamProvider<List<MealEntity>>(
  (Ref ref) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<List<MealEntity>>.value(<MealEntity>[]);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) {
      return Stream<List<MealEntity>>.value(<MealEntity>[]);
    }
    final MealsRepository repo = ref.watch(mealsRepositoryProvider);
    return repo.watchMealsForPet(petId);
  },
);

/// ホーム画面用の最新N件
final StreamProvider<List<MealEntity>> recentMealsForHomeProvider =
    StreamProvider<List<MealEntity>>(
  (Ref ref) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<List<MealEntity>>.value(<MealEntity>[]);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) {
      return Stream<List<MealEntity>>.value(<MealEntity>[]);
    }
    final MealsRepository repo = ref.watch(mealsRepositoryProvider);
    return repo.watchMealsForPet(petId, limit: 5);
  },
);
