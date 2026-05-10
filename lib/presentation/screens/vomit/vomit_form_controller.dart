// ============================================================================
// petlo - Vomit Form Controller
// ============================================================================

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../providers/database_provider.dart';
import '../../providers/photo_storage_provider.dart';
import '../../providers/scope_providers.dart';
import '../../providers/vomits_providers.dart';
import 'vomit_form_state.dart';

enum VomitFormSaveOutcome { success, validationFailed, dbError }

final NotifierProviderFamily<VomitFormController, VomitFormState, int?>
    vomitFormControllerProvider =
    NotifierProviderFamily<VomitFormController, VomitFormState, int?>(
  VomitFormController.new,
);

class VomitFormController extends FamilyNotifier<VomitFormState, int?> {
  @override
  VomitFormState build(int? editingVomitId) {
    if (editingVomitId == null) {
      final String? petIdStr = ref.read(currentPetIdProvider);
      final int? petId = (petIdStr == null || petIdStr == kAllPetsId)
          ? null
          : int.tryParse(petIdStr);
      return VomitFormState(petId: petId, vomitedAt: DateTime.now());
    }
    Future<void>.microtask(() => _loadExisting(editingVomitId));
    return const VomitFormState();
  }

  Future<void> _loadExisting(int vomitId) async {
    try {
      final repo = ref.read(vomitsRepositoryProvider);
      final VomitEntity? v = await repo.getById(vomitId);
      if (v == null) return;
      state = VomitFormState.fromExisting(
        vomitId: v.id,
        petId: v.petId,
        color: v.color,
        colorOtherText: v.colorOtherText,
        amount: v.amount,
        count: v.count,
        containsFood: v.containsFood,
        suspectIngestion: v.suspectIngestion,
        vomitedAt: DateTime.fromMillisecondsSinceEpoch(v.vomitedAt),
        notes: v.notes,
        savedPhotoRelativePath: v.photoPath,
      );
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to load vomit for editing', error: e, stackTrace: st);
    }
  }

  void updateColor(VomitColor? v) {
    // 「other」以外を選んだら自由記述はクリア
    if (v != VomitColor.other) {
      state = state.copyWith(color: v, colorOtherText: '');
    } else {
      state = state.copyWith(color: v);
    }
  }

  void updateColorOtherText(String v) =>
      state = state.copyWith(colorOtherText: v);
  void updateAmount(RecordAmount? v) => state = state.copyWith(amount: v);
  void updateCount(int v) => state = state.copyWith(count: v);
  void updateContainsFood(bool v) => state = state.copyWith(containsFood: v);
  void updateSuspectIngestion(bool v) =>
      state = state.copyWith(suspectIngestion: v);
  void updateVomitedAt(DateTime? v) => state = state.copyWith(vomitedAt: v);
  void updateNotes(String v) => state = state.copyWith(notes: v);
  void updatePhotoFile(File? v) => state = state.copyWith(photoFile: v);

  Future<VomitFormSaveOutcome> save() async {
    final validated = state.validate();
    if (validated.errors.hasAny) {
      state = validated;
      return VomitFormSaveOutcome.validationFailed;
    }
    state = validated.copyWith(isSubmitting: true);

    try {
      final repo = ref.read(vomitsRepositoryProvider);
      final photoStorage = ref.read(photoStorageProvider);
      final String groupId = ref.read(currentGroupIdProvider);
      final int t = state.vomitedAt!.toUtc().millisecondsSinceEpoch;

      final String? colorOtherText = state.color == VomitColor.other
          ? state.colorOtherText.trim()
          : null;

      int vomitId;
      if (state.isEditing) {
        await repo.update(
          vomitId: state.editingVomitId!,
          color: state.color,
          colorOtherText: colorOtherText,
          clearColorOtherText: state.color != VomitColor.other,
          amount: state.amount,
          count: state.count,
          containsFood: state.containsFood,
          suspectIngestion: state.suspectIngestion,
          vomitedAtMsec: t,
          notes: state.notes,
        );
        vomitId = state.editingVomitId!;
      } else {
        vomitId = await repo.create(
          groupId: groupId,
          petId: state.petId!,
          color: state.color!,
          colorOtherText: colorOtherText,
          amount: state.amount!,
          count: state.count,
          containsFood: state.containsFood,
          suspectIngestion: state.suspectIngestion,
          vomitedAtMsec: t,
          notes: state.notes.trim().isEmpty ? null : state.notes.trim(),
        );
      }

      // 写真
      if (state.photoFile != null) {
        try {
          final String relPath = await photoStorage.saveVomitPhoto(
            vomitId: vomitId,
            source: state.photoFile!,
          );
          await repo.update(vomitId: vomitId, photoPath: relPath);
        } catch (e, st) {
          PetloLogger.instance
              .w('Failed to save vomit photo', error: e, stackTrace: st);
        }
      }

      state = state.copyWith(isSubmitting: false);
      return VomitFormSaveOutcome.success;
    } catch (e, st) {
      PetloLogger.instance.w('Failed to save vomit', error: e, stackTrace: st);
      state = state.copyWith(isSubmitting: false);
      return VomitFormSaveOutcome.dbError;
    }
  }
}
