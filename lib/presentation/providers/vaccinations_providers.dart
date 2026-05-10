// ============================================================================
// petlo - Vaccinations Providers
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/vaccinations_repository.dart';
import 'database_provider.dart';
import 'scope_providers.dart';

final Provider<VaccinationsRepository> vaccinationsRepositoryProvider =
    Provider<VaccinationsRepository>(
  (Ref ref) {
    final AppDatabase db = ref.watch(appDatabaseProvider);
    return VaccinationsRepository(db);
  },
);

/// 現在ペットの全ワクチン記録
final StreamProvider<List<VaccinationEntity>>
    currentPetVaccinationsProvider =
    StreamProvider<List<VaccinationEntity>>(
  (Ref ref) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<List<VaccinationEntity>>.value(<VaccinationEntity>[]);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) {
      return Stream<List<VaccinationEntity>>.value(<VaccinationEntity>[]);
    }
    final VaccinationsRepository repo =
        ref.watch(vaccinationsRepositoryProvider);
    return repo.watchForPet(petId);
  },
);

/// 30日以内に次回接種予定のワクチン (リマインダー用)
final StreamProvider<List<VaccinationEntity>>
    upcomingVaccinationsProvider =
    StreamProvider<List<VaccinationEntity>>(
  (Ref ref) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<List<VaccinationEntity>>.value(<VaccinationEntity>[]);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) {
      return Stream<List<VaccinationEntity>>.value(<VaccinationEntity>[]);
    }
    final VaccinationsRepository repo =
        ref.watch(vaccinationsRepositoryProvider);
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final int in30days =
        now + const Duration(days: 30).inMilliseconds;
    return repo.watchUpcomingDue(
      petId: petId,
      fromMsec: now,
      toMsec: in30days,
    );
  },
);

/// 期限切れワクチン
final StreamProvider<List<VaccinationEntity>>
    overdueVaccinationsProvider =
    StreamProvider<List<VaccinationEntity>>(
  (Ref ref) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<List<VaccinationEntity>>.value(<VaccinationEntity>[]);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) {
      return Stream<List<VaccinationEntity>>.value(<VaccinationEntity>[]);
    }
    final VaccinationsRepository repo =
        ref.watch(vaccinationsRepositoryProvider);
    return repo.watchOverdue(petId);
  },
);
