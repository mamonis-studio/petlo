// ============================================================================
// petlo - Weights Providers
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/weights_repository.dart';
import 'database_provider.dart';
import 'scope_providers.dart';

final Provider<WeightsRepository> weightsRepositoryProvider =
    Provider<WeightsRepository>(
  (Ref ref) {
    final AppDatabase db = ref.watch(appDatabaseProvider);
    return WeightsRepository(db);
  },
);

/// 現在ペットの最新体重 (ホーム画面の上部に表示する想定)
final StreamProvider<WeightEntity?> currentPetLatestWeightProvider =
    StreamProvider<WeightEntity?>(
  (Ref ref) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<WeightEntity?>.value(null);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) return Stream<WeightEntity?>.value(null);
    final WeightsRepository repo = ref.watch(weightsRepositoryProvider);
    return repo.watchLatest(petId);
  },
);

/// 現在ペットの履歴 (グラフ用、デフォルト直近30日)
final StreamProvider<List<WeightEntity>> currentPetWeightHistoryProvider =
    StreamProvider<List<WeightEntity>>(
  (Ref ref) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<List<WeightEntity>>.value(<WeightEntity>[]);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) {
      return Stream<List<WeightEntity>>.value(<WeightEntity>[]);
    }
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int from = DateTime.now()
        .subtract(const Duration(days: 90))
        .millisecondsSinceEpoch;
    final WeightsRepository repo = ref.watch(weightsRepositoryProvider);
    return repo.watchInRange(petId: petId, fromMsec: from, toMsec: now);
  },
);
