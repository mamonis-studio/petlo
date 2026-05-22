// ============================================================================
// petlo - Poop Form Controller
// ============================================================================

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/database_provider.dart';
import '../../providers/photo_storage_provider.dart';
import '../../providers/poops_providers.dart';
import '../../providers/scope_providers.dart';
import 'poop_form_state.dart';

enum PoopFormSaveOutcome { success, validationFailed, dbError }

final NotifierProviderFamily<PoopFormController, PoopFormState, int?>
    poopFormControllerProvider =
    NotifierProviderFamily<PoopFormController, PoopFormState, int?>(
  PoopFormController.new,
);

class PoopFormController extends FamilyNotifier<PoopFormState, int?> {
  @override
  PoopFormState build(int? editingPoopId) {
    if (editingPoopId == null) {
      final String? petIdStr = ref.read(currentPetIdProvider);
      final int? petId =
          (petIdStr == null || petIdStr == kAllPetsId) ? null : int.tryParse(petIdStr);
      return PoopFormState(
        petId: petId,
        pooedAt: DateTime.now(),
      );
    }
    Future<void>.microtask(() => _loadExisting(editingPoopId));
    return const PoopFormState();
  }

  Future<void> _loadExisting(int poopId) async {
    try {
      final repo = ref.read(poopsRepositoryProvider);
      final PoopEntity? p = await repo.getById(poopId);
      if (p == null) return;
      state = PoopFormState.fromExisting(
        poopId: p.id,
        petId: p.petId,
        form: p.form,
        color: p.color,
        amount: p.amount,
        pooedAt: DateTime.fromMillisecondsSinceEpoch(p.pooedAt),
        notes: p.notes,
        savedPhotoRelativePath: p.photoPath,
      );
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to load poop for editing', error: e, stackTrace: st);
    }
  }

  // フィールド更新
  void updateForm(PoopForm? v) => state = state.copyWith(form: v);
  void updateColor(PoopColor? v) => state = state.copyWith(color: v);
  void updateAmount(RecordAmount? v) => state = state.copyWith(amount: v);
  void updatePooedAt(DateTime? v) => state = state.copyWith(pooedAt: v);
  void updateNotes(String v) => state = state.copyWith(notes: v);
  void updatePhotoFile(File? v) => state = state.copyWith(photoFile: v);

  // Save
  Future<PoopFormSaveOutcome> save(AppLocalizations l10n) async {
    final PoopFormState validated = state.validate(l10n);
    if (validated.errors.hasAny) {
      state = validated;
      return PoopFormSaveOutcome.validationFailed;
    }
    state = validated.copyWith(isSubmitting: true);

    try {
      final repo = ref.read(poopsRepositoryProvider);
      final photoStorage = ref.read(photoStorageProvider);
      final String groupId = ref.read(currentGroupIdProvider);
      final int t = state.pooedAt!.toUtc().millisecondsSinceEpoch;

      int poopId;
      if (state.isEditing) {
        await repo.update(
          poopId: state.editingPoopId!,
          form: state.form,
          color: state.color,
          amount: state.amount,
          pooedAtMsec: t,
          notes: state.notes,
        );
        poopId = state.editingPoopId!;
      } else {
        poopId = await repo.create(
          groupId: groupId,
          petId: state.petId!,
          form: state.form!,
          color: state.color!,
          amount: state.amount!,
          pooedAtMsec: t,
          notes: state.notes.trim().isEmpty ? null : state.notes.trim(),
        );
      }

      // 写真
      if (state.photoFile != null) {
        try {
          final String relPath = await photoStorage.savePoopPhoto(
            poopId: poopId,
            source: state.photoFile!,
          );
          await repo.update(poopId: poopId, photoPath: relPath);
        } catch (e, st) {
          PetloLogger.instance
              .w('Failed to save poop photo', error: e, stackTrace: st);
        }
      }

      state = state.copyWith(isSubmitting: false);
      return PoopFormSaveOutcome.success;
    } catch (e, st) {
      PetloLogger.instance.w('Failed to save poop', error: e, stackTrace: st);
      state = state.copyWith(isSubmitting: false);
      return PoopFormSaveOutcome.dbError;
    }
  }
}
