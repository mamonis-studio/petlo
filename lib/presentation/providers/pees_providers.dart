// ============================================================================
// petlo - Pees Providers
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/pees_repository.dart';
import 'database_provider.dart';
import 'scope_providers.dart';

final Provider<PeesRepository> peesRepositoryProvider =
    Provider<PeesRepository>(
  (Ref ref) {
    final AppDatabase db = ref.watch(appDatabaseProvider);
    return PeesRepository(db);
  },
);

final StreamProvider<List<PeeEntity>> recentPeesForHomeProvider =
    StreamProvider<List<PeeEntity>>(
  (Ref ref) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<List<PeeEntity>>.value(<PeeEntity>[]);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) return Stream<List<PeeEntity>>.value(<PeeEntity>[]);
    final PeesRepository repo = ref.watch(peesRepositoryProvider);
    return repo.watchForPet(petId, limit: 5);
  },
);
