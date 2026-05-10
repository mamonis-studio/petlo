// ============================================================================
// petlo - Vomits Providers
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/vomits_repository.dart';
import 'database_provider.dart';
import 'scope_providers.dart';

final Provider<VomitsRepository> vomitsRepositoryProvider =
    Provider<VomitsRepository>(
  (Ref ref) {
    final AppDatabase db = ref.watch(appDatabaseProvider);
    return VomitsRepository(db);
  },
);

final StreamProvider<List<VomitEntity>> recentVomitsForHomeProvider =
    StreamProvider<List<VomitEntity>>(
  (Ref ref) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<List<VomitEntity>>.value(<VomitEntity>[]);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) return Stream<List<VomitEntity>>.value(<VomitEntity>[]);
    final VomitsRepository repo = ref.watch(vomitsRepositoryProvider);
    return repo.watchForPet(petId, limit: 5);
  },
);
