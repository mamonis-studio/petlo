// ============================================================================
// petlo - Medication Reminder Form Controller
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../../data/local/app_database.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/medication_reminders_providers.dart';
import '../../providers/notification_scheduler_provider.dart';
import '../../providers/scope_providers.dart';
import 'medication_reminder_form_state.dart';

enum MedicationReminderSaveOutcome {
  success,
  validationFailed,
  freeLimitReached,
  dbError,
}

/// 無料プランで作成可能なリマインダー数(rev3 F-13)
const int kFreeReminderLimit = 1;

final NotifierProviderFamily<
    MedicationReminderFormController,
    MedicationReminderFormState,
    int?> medicationReminderFormControllerProvider =
    NotifierProviderFamily<MedicationReminderFormController,
        MedicationReminderFormState, int?>(
  MedicationReminderFormController.new,
);

class MedicationReminderFormController
    extends FamilyNotifier<MedicationReminderFormState, int?> {
  @override
  MedicationReminderFormState build(int? editingReminderId) {
    if (editingReminderId == null) {
      final String? petIdStr = ref.read(currentPetIdProvider);
      final int? petId = (petIdStr == null || petIdStr == kAllPetsId)
          ? null
          : int.tryParse(petIdStr);
      // 新規作成時のデフォルトで 09:00 を1つ入れておく
      return MedicationReminderFormState(
        petId: petId,
        times: const <String>['09:00'],
      );
    }
    Future<void>.microtask(() => _loadExisting(editingReminderId));
    return const MedicationReminderFormState();
  }

  Future<void> _loadExisting(int reminderId) async {
    try {
      final repo = ref.read(medicationRemindersRepositoryProvider);
      final MedicationReminderEntity? r = await repo.getById(reminderId);
      if (r == null) return;
      state = MedicationReminderFormState.fromExisting(
        reminderId: r.id,
        petId: r.petId,
        medicineName: r.medicineName,
        dosage: r.dosage,
        times: r.times,
        weekdays: r.weekdaysBits,
        notes: r.notes,
        startDateMsec: r.startDate,
        endDateMsec: r.endDate,
        enabled: r.enabled,
      );
    } catch (e, st) {
      PetloLogger.instance.w('Failed to load reminder for editing',
          error: e, stackTrace: st);
    }
  }

  // ==========================================================================
  // フィールド更新
  // ==========================================================================
  void updateMedicineName(String v) =>
      state = state.copyWith(medicineName: v);
  void updateDosage(String v) => state = state.copyWith(dosage: v);
  void updateNotes(String v) => state = state.copyWith(notes: v);
  void updateEnabled(bool v) => state = state.copyWith(enabled: v);
  void updateStartDate(DateTime? v) =>
      state = state.copyWith(startDate: v);
  void updateEndDate(DateTime? v) => state = state.copyWith(endDate: v);

  /// 時刻を1つ追加(重複は無視、ソート)
  void addTime(String hhmm) {
    if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(hhmm)) return;
    if (state.times.contains(hhmm)) return;
    final List<String> next = List<String>.from(state.times)..add(hhmm);
    next.sort();
    state = state.copyWith(times: next);
  }

  void removeTime(String hhmm) {
    final List<String> next = List<String>.from(state.times)..remove(hhmm);
    state = state.copyWith(times: next);
  }

  /// 曜日のトグル(0=日, 1=月,...,6=土)
  void toggleWeekday(int weekday) {
    final Set<int> next = Set<int>.from(state.weekdays);
    if (next.contains(weekday)) {
      next.remove(weekday);
    } else {
      next.add(weekday);
    }
    state = state.copyWith(weekdays: next);
  }

  /// 「毎日」モードに戻す
  void setEveryday() {
    state = state.copyWith(weekdays: <int>{});
  }

  // ==========================================================================
  // Save
  // ==========================================================================
  Future<MedicationReminderSaveOutcome> save(
    AppLocalizations l10n, {
    bool isProUser = false,
  }) async {
    final validated = state.validate(l10n);
    if (validated.errors.hasAny) {
      state = validated;
      return MedicationReminderSaveOutcome.validationFailed;
    }

    state = validated.copyWith(isSubmitting: true);

    try {
      final repo = ref.read(medicationRemindersRepositoryProvider);
      final String groupId = ref.read(currentGroupIdProvider);

      // 新規作成時の無料プラン上限チェック
      if (!state.isEditing && !isProUser) {
        final int currentCount =
            await repo.countActiveForGroup(groupId);
        if (currentCount >= kFreeReminderLimit) {
          state = state.copyWith(isSubmitting: false);
          return MedicationReminderSaveOutcome.freeLimitReached;
        }
      }

      if (state.isEditing) {
        await repo.update(
          reminderId: state.editingReminderId!,
          medicineName: state.medicineName,
          dosage: state.dosage,
          clearDosage: state.dosage.trim().isEmpty,
          times: state.times,
          weekdays: state.weekdays,
          notes: state.notes,
          clearNotes: state.notes.trim().isEmpty,
          startDateMsec: state.startDate?.toUtc().millisecondsSinceEpoch,
          clearStartDate: state.startDate == null,
          endDateMsec: state.endDate?.toUtc().millisecondsSinceEpoch,
          clearEndDate: state.endDate == null,
          enabled: state.enabled,
        );
        // 通知再構築
        await ref
            .read(notificationSchedulerProvider)
            .syncReminder(state.editingReminderId!);
      } else {
        if (state.petId == null) {
          state = state.copyWith(isSubmitting: false);
          return MedicationReminderSaveOutcome.dbError;
        }
        final int newId = await repo.create(
          groupId: groupId,
          petId: state.petId!,
          medicineName: state.medicineName,
          dosage: state.dosage,
          times: state.times,
          weekdays: state.weekdays,
          notes: state.notes,
          startDateMsec: state.startDate?.toUtc().millisecondsSinceEpoch,
          endDateMsec: state.endDate?.toUtc().millisecondsSinceEpoch,
          enabled: state.enabled,
        );
        // 通知スケジュール
        await ref
            .read(notificationSchedulerProvider)
            .syncReminder(newId);
      }

      state = state.copyWith(isSubmitting: false);
      return MedicationReminderSaveOutcome.success;
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to save reminder', error: e, stackTrace: st);
      state = state.copyWith(isSubmitting: false);
      return MedicationReminderSaveOutcome.dbError;
    }
  }

  /// 削除(scheduler の通知も一緒にキャンセル)
  Future<bool> delete() async {
    if (!state.isEditing) return false;
    try {
      final repo = ref.read(medicationRemindersRepositoryProvider);
      final scheduler = ref.read(notificationSchedulerProvider);
      // 通知を先に消す(DB削除後に scheduler 呼ぶと getById null になる)
      await scheduler.cancelReminder(state.editingReminderId!);
      return await repo.softDelete(state.editingReminderId!);
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to delete reminder', error: e, stackTrace: st);
      return false;
    }
  }
}
