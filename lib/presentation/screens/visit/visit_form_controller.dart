// ============================================================================
// petlo - Visit Form Controller
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../../data/local/app_database.dart';
import '../../providers/database_provider.dart';
import '../../providers/photo_storage_provider.dart';
import '../../providers/scope_providers.dart';
import '../../providers/visits_providers.dart';
import '../../widgets/forms/multi_photo_picker.dart';
import 'visit_form_state.dart';

enum VisitFormSaveOutcome { success, validationFailed, dbError }

final NotifierProviderFamily<VisitFormController, VisitFormState, int?>
    visitFormControllerProvider =
    NotifierProviderFamily<VisitFormController, VisitFormState, int?>(
  VisitFormController.new,
);

class VisitFormController extends FamilyNotifier<VisitFormState, int?> {
  @override
  VisitFormState build(int? editingVisitId) {
    if (editingVisitId == null) {
      final String? petIdStr = ref.read(currentPetIdProvider);
      final int? petId = (petIdStr == null || petIdStr == kAllPetsId)
          ? null
          : int.tryParse(petIdStr);
      return VisitFormState(
        petId: petId,
        visitedAt: DateTime.now(),
      );
    }
    Future<void>.microtask(() => _loadExisting(editingVisitId));
    return const VisitFormState();
  }

  Future<void> _loadExisting(int visitId) async {
    try {
      final repo = ref.read(visitsRepositoryProvider);
      final VisitEntity? v = await repo.getById(visitId);
      if (v == null) return;
      state = VisitFormState.fromExisting(
        visitId: v.id,
        petId: v.petId,
        visitedAt: DateTime.fromMillisecondsSinceEpoch(v.visitedAt),
        clinicName: v.clinicName,
        vetName: v.vetName,
        reason: v.reason,
        diagnosis: v.diagnosis,
        treatment: v.treatment,
        costJpy: v.costJpy,
        savedPhotoPaths: v.photoPaths,
        notes: v.notes,
      );
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to load visit for editing', error: e, stackTrace: st);
    }
  }

  // フィールド更新
  void updateVisitedAt(DateTime? v) => state = state.copyWith(visitedAt: v);
  void updateClinicName(String v) => state = state.copyWith(clinicName: v);
  void updateVetName(String v) => state = state.copyWith(vetName: v);
  void updateReason(String v) => state = state.copyWith(reason: v);
  void updateDiagnosis(String v) => state = state.copyWith(diagnosis: v);
  void updateTreatment(String v) => state = state.copyWith(treatment: v);
  void updateCostJpy(int? v) => state = state.copyWith(costJpy: v);
  void updateNotes(String v) => state = state.copyWith(notes: v);
  void updatePhotoSlots(List<PhotoSlot> slots) =>
      state = state.copyWith(photoSlots: slots);

  // Save
  Future<VisitFormSaveOutcome> save() async {
    final validated = state.validate();
    if (validated.errors.hasAny) {
      state = validated;
      return VisitFormSaveOutcome.validationFailed;
    }
    state = validated.copyWith(isSubmitting: true);

    try {
      final repo = ref.read(visitsRepositoryProvider);
      final photoStorage = ref.read(photoStorageProvider);
      final String groupId = ref.read(currentGroupIdProvider);
      final int t = state.visitedAt!.toUtc().millisecondsSinceEpoch;

      // 既存写真の相対パスを抜き出し(残ってるもの)
      final List<String> keptPaths = state.photoSlots
          .where((s) => s.isExisting)
          .map((s) => s.savedRelativePath!)
          .toList();

      int visitId;
      if (state.isEditing) {
        await repo.update(
          visitId: state.editingVisitId!,
          visitedAtMsec: t,
          clinicName: state.clinicName,
          vetName: state.vetName,
          reason: state.reason,
          diagnosis: state.diagnosis,
          treatment: state.treatment,
          costJpy: state.costJpy,
          clearCost: state.costJpy == null,
          photoPaths: keptPaths.isEmpty ? null : keptPaths,
          clearPhotos: keptPaths.isEmpty,
          notes: state.notes,
        );
        visitId = state.editingVisitId!;
      } else {
        visitId = await repo.create(
          groupId: groupId,
          petId: state.petId!,
          visitedAtMsec: t,
          clinicName: state.clinicName,
          vetName: state.vetName,
          reason: state.reason,
          diagnosis: state.diagnosis,
          treatment: state.treatment,
          costJpy: state.costJpy,
          photoPaths: keptPaths.isEmpty ? null : keptPaths,
          notes: state.notes,
        );
      }

      // 新規写真ファイルを順次保存
      final List<String> finalPaths = <String>[...keptPaths];
      int idx = keptPaths.length;
      for (final PhotoSlot slot in state.photoSlots) {
        if (slot.isNew) {
          try {
            final String relPath = await photoStorage.saveVisitPhoto(
              visitId: visitId,
              index: idx,
              source: slot.file!,
            );
            finalPaths.add(relPath);
            idx++;
          } catch (e, st) {
            PetloLogger.instance.w('Failed to save visit photo[$idx]',
                error: e, stackTrace: st);
          }
        }
      }
      // 写真パスを反映 (新規ファイルがあった場合のみupdate)
      if (finalPaths.length != keptPaths.length) {
        await repo.update(
          visitId: visitId,
          photoPaths: finalPaths.isEmpty ? null : finalPaths,
          clearPhotos: finalPaths.isEmpty,
        );
      }

      state = state.copyWith(isSubmitting: false);
      return VisitFormSaveOutcome.success;
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to save visit', error: e, stackTrace: st);
      state = state.copyWith(isSubmitting: false);
      return VisitFormSaveOutcome.dbError;
    }
  }
}
