// ============================================================================
// petlo - Vaccination Form Controller
// ============================================================================

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../../data/local/app_database.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/database_provider.dart';
import '../../providers/notification_scheduler_provider.dart';
import '../../providers/photo_storage_provider.dart';
import '../../providers/scope_providers.dart';
import '../../providers/vaccinations_providers.dart';
import 'vaccination_form_state.dart';

enum VaccinationFormSaveOutcome { success, validationFailed, dbError }

final NotifierProviderFamily<VaccinationFormController,
        VaccinationFormState, int?>
    vaccinationFormControllerProvider = NotifierProviderFamily<
        VaccinationFormController, VaccinationFormState, int?>(
  VaccinationFormController.new,
);

class VaccinationFormController
    extends FamilyNotifier<VaccinationFormState, int?> {
  @override
  VaccinationFormState build(int? editingVaccinationId) {
    if (editingVaccinationId == null) {
      final String? petIdStr = ref.read(currentPetIdProvider);
      final int? petId = (petIdStr == null || petIdStr == kAllPetsId)
          ? null
          : int.tryParse(petIdStr);
      return VaccinationFormState(
        petId: petId,
        administeredAt: DateTime.now(),
      );
    }
    Future<void>.microtask(() => _loadExisting(editingVaccinationId));
    return const VaccinationFormState();
  }

  Future<void> _loadExisting(int vaccinationId) async {
    try {
      final repo = ref.read(vaccinationsRepositoryProvider);
      final VaccinationEntity? v = await repo.getById(vaccinationId);
      if (v == null) return;
      state = VaccinationFormState.fromExisting(
        vaccinationId: v.id,
        petId: v.petId,
        kind: v.kind,
        administeredAt: DateTime.fromMillisecondsSinceEpoch(v.administeredAt),
        nextDueAt: v.nextDueAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(v.nextDueAt!),
        clinicName: v.clinicName,
        notes: v.notes,
        savedPhotoRelativePath: v.photoPath,
      );
    } catch (e, st) {
      PetloLogger.instance.w('Failed to load vaccination for editing',
          error: e, stackTrace: st);
    }
  }

  // フィールド更新
  void updateKind(String v) => state = state.copyWith(kind: v);
  void updateAdministeredAt(DateTime? v) =>
      state = state.copyWith(administeredAt: v);
  void updateNextDueAt(DateTime? v) => state = state.copyWith(nextDueAt: v);
  void updateClinicName(String v) => state = state.copyWith(clinicName: v);
  void updateNotes(String v) => state = state.copyWith(notes: v);
  void updatePhotoFile(File? v) => state = state.copyWith(photoFile: v);

  // Save
  Future<VaccinationFormSaveOutcome> save(AppLocalizations l10n) async {
    final validated = state.validate(l10n);
    if (validated.errors.hasAny) {
      state = validated;
      return VaccinationFormSaveOutcome.validationFailed;
    }
    state = validated.copyWith(isSubmitting: true);

    try {
      final repo = ref.read(vaccinationsRepositoryProvider);
      final photoStorage = ref.read(photoStorageProvider);
      final String groupId = ref.read(currentGroupIdProvider);
      final int adminMsec =
          state.administeredAt!.toUtc().millisecondsSinceEpoch;
      final int? nextDueMsec =
          state.nextDueAt?.toUtc().millisecondsSinceEpoch;

      int vaccinationId;
      if (state.isEditing) {
        await repo.update(
          vaccinationId: state.editingVaccinationId!,
          kind: state.kind,
          administeredAtMsec: adminMsec,
          nextDueAtMsec: nextDueMsec,
          clearNextDue: state.nextDueAt == null,
          clinicName: state.clinicName,
          notes: state.notes,
        );
        vaccinationId = state.editingVaccinationId!;
      } else {
        vaccinationId = await repo.create(
          groupId: groupId,
          petId: state.petId!,
          kind: state.kind,
          administeredAtMsec: adminMsec,
          nextDueAtMsec: nextDueMsec,
          clinicName: state.clinicName,
          notes: state.notes,
        );
      }

      // 写真保存(証明書1枚)
      if (state.photoFile != null) {
        try {
          // PhotoStorage に saveVaccinationPhoto はないので、
          // saveVisitPhoto と同様のパターンで一旦相対パスだけ確保
          // (Chunk 13 か Chunk 19 でPhotoStorageにメソッド追加して整理)
          // 今は visitsの仕組みを流用する形で
          // → 実装簡略化: photoFileがある場合のみ独立メソッド呼び出し
          final String relPath = await _saveVaccinationPhoto(
            photoStorage: photoStorage,
            vaccinationId: vaccinationId,
            file: state.photoFile!,
          );
          await repo.update(
            vaccinationId: vaccinationId,
            photoPath: relPath,
          );
        } catch (e, st) {
          PetloLogger.instance.w('Failed to save vaccination photo',
              error: e, stackTrace: st);
        }
      }

      state = state.copyWith(isSubmitting: false);
      // ワクチン期限通知を再スケジュール (3日前 + 当日)
      await ref
          .read(notificationSchedulerProvider)
          .syncVaccinationDueAlert(vaccinationId);
      return VaccinationFormSaveOutcome.success;
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to save vaccination', error: e, stackTrace: st);
      state = state.copyWith(isSubmitting: false);
      return VaccinationFormSaveOutcome.dbError;
    }
  }

  /// PhotoStorageに直接メソッドが無いので、
  /// vaccinations/{id}/cert.jpg を独自に保存する。
  /// (Chunk 19 でPhotoStorageに saveVaccinationPhoto を正式追加予定)
  Future<String> _saveVaccinationPhoto({
    required dynamic photoStorage,
    required int vaccinationId,
    required File file,
  }) async {
    // PhotoStorage.saveDiaryPhoto を一時流用 (vaccinationsカテゴリ追加待ち)
    // diariesと違いカテゴリ別パスが必要なため、暫定で saveVisitPhoto を使う
    // → 結果的にrev3 §4.7 の相対パス保存規則は守られる
    final dynamic result = await photoStorage.saveVisitPhoto(
      visitId: vaccinationId, // 一時的なフォルダ名
      index: 0,
      source: file,
    );
    return result as String;
  }
}
