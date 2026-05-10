// ============================================================================
// petlo - Medication Reminders Providers
// ============================================================================
//
// 投薬リマインダーの Repository と、よく使う Stream Provider 群。
//
// rev3 F-13
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/medication_reminders_repository.dart';
import 'database_provider.dart';
import 'scope_providers.dart';

// ============================================================================
// Repository
// ============================================================================
final Provider<MedicationRemindersRepository>
    medicationRemindersRepositoryProvider =
    Provider<MedicationRemindersRepository>(
  (Ref ref) => MedicationRemindersRepository(ref.watch(appDatabaseProvider)),
);

// ============================================================================
// Streams
// ============================================================================

/// 現在ペットの全リマインダー(編集画面用)
final StreamProvider<List<MedicationReminderEntity>>
    currentPetRemindersProvider =
    StreamProvider<List<MedicationReminderEntity>>(
  (Ref ref) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<List<MedicationReminderEntity>>.value(
          <MedicationReminderEntity>[]);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) {
      return Stream<List<MedicationReminderEntity>>.value(
          <MedicationReminderEntity>[]);
    }
    return ref
        .watch(medicationRemindersRepositoryProvider)
        .watchForPet(petId);
  },
);

/// 現在ペットの「有効な」リマインダー(通知スケジュール用)
final StreamProvider<List<MedicationReminderEntity>>
    currentPetEnabledRemindersProvider =
    StreamProvider<List<MedicationReminderEntity>>(
  (Ref ref) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<List<MedicationReminderEntity>>.value(
          <MedicationReminderEntity>[]);
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) {
      return Stream<List<MedicationReminderEntity>>.value(
          <MedicationReminderEntity>[]);
    }
    return ref
        .watch(medicationRemindersRepositoryProvider)
        .watchEnabledForPet(petId);
  },
);

/// 現在グループの有効リマインダー (Plansタブ統合用)
final StreamProvider<List<MedicationReminderEntity>>
    currentGroupEnabledRemindersProvider =
    StreamProvider<List<MedicationReminderEntity>>(
  (Ref ref) {
    final String groupId = ref.watch(currentGroupIdProvider);
    return ref
        .watch(medicationRemindersRepositoryProvider)
        .watchEnabledForGroup(groupId);
  },
);

/// 現在グループのアクティブリマインダー件数(無料制限の判定用、Future)
final FutureProvider<int> currentGroupReminderCountProvider =
    FutureProvider<int>(
  (Ref ref) async {
    final String groupId = ref.watch(currentGroupIdProvider);
    return ref
        .watch(medicationRemindersRepositoryProvider)
        .countActiveForGroup(groupId);
  },
);
