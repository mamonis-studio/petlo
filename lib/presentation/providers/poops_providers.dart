// ============================================================================
// petlo - Poops Providers
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/poops_repository.dart';
import 'database_provider.dart';
import 'scope_providers.dart';

final Provider<PoopsRepository> poopsRepositoryProvider =
    Provider<PoopsRepository>(
  (Ref ref) {
    final AppDatabase db = ref.watch(appDatabaseProvider);
    return PoopsRepository(db);
  },
);

/// 現在ペットの最新N件 (ホーム表示用)
final StreamProvider<List<PoopEntity>> recentPoopsForHomeProvider =
    StreamProvider<List<PoopEntity>>(
  (Ref ref) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<List<PoopEntity>>.value(<PoopEntity>[]);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) {
      return Stream<List<PoopEntity>>.value(<PoopEntity>[]);
    }
    final PoopsRepository repo = ref.watch(poopsRepositoryProvider);
    return repo.watchForPet(petId, limit: 5);
  },
);
