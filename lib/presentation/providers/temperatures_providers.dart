// ============================================================================
// petlo - Temperatures Providers
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/temperatures_repository.dart';
import 'database_provider.dart';
import 'scope_providers.dart';

final Provider<TemperaturesRepository> temperaturesRepositoryProvider =
    Provider<TemperaturesRepository>(
  (Ref ref) {
    final AppDatabase db = ref.watch(appDatabaseProvider);
    return TemperaturesRepository(db);
  },
);

final StreamProvider<TemperatureEntity?> currentPetLatestTemperatureProvider =
    StreamProvider<TemperatureEntity?>(
  (Ref ref) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<TemperatureEntity?>.value(null);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) return Stream<TemperatureEntity?>.value(null);
    final TemperaturesRepository repo =
        ref.watch(temperaturesRepositoryProvider);
    return repo.watchLatest(petId);
  },
);

final StreamProvider<List<TemperatureEntity>>
    currentPetTemperatureHistoryProvider =
    StreamProvider<List<TemperatureEntity>>(
  (Ref ref) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<List<TemperatureEntity>>.value(<TemperatureEntity>[]);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) {
      return Stream<List<TemperatureEntity>>.value(<TemperatureEntity>[]);
    }
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int from = DateTime.now()
        .subtract(const Duration(days: 90))
        .millisecondsSinceEpoch;
    final TemperaturesRepository repo =
        ref.watch(temperaturesRepositoryProvider);
    return repo.watchInRange(petId: petId, fromMsec: from, toMsec: now);
  },
);
