// ============================================================================
// petlo - Visits Providers
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/visits_repository.dart';
import 'database_provider.dart';
import 'scope_providers.dart';

final Provider<VisitsRepository> visitsRepositoryProvider =
    Provider<VisitsRepository>(
  (Ref ref) {
    final AppDatabase db = ref.watch(appDatabaseProvider);
    return VisitsRepository(db);
  },
);

/// 現在ペットの全通院記録 (新しい順)
final StreamProvider<List<VisitEntity>> currentPetVisitsProvider =
    StreamProvider<List<VisitEntity>>(
  (Ref ref) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<List<VisitEntity>>.value(<VisitEntity>[]);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) {
      return Stream<List<VisitEntity>>.value(<VisitEntity>[]);
    }
    final VisitsRepository repo = ref.watch(visitsRepositoryProvider);
    return repo.watchForPet(petId);
  },
);

/// ホーム表示用の最新N件
final StreamProvider<List<VisitEntity>> recentVisitsForHomeProvider =
    StreamProvider<List<VisitEntity>>(
  (Ref ref) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<List<VisitEntity>>.value(<VisitEntity>[]);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) {
      return Stream<List<VisitEntity>>.value(<VisitEntity>[]);
    }
    final VisitsRepository repo = ref.watch(visitsRepositoryProvider);
    return repo.watchForPet(petId, limit: 3);
  },
);
