// ============================================================================
// petlo - Weight Form Controller
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/database_provider.dart';
import '../../providers/scope_providers.dart';
import '../../providers/weights_providers.dart';
import 'weight_form_state.dart';

enum WeightFormSaveOutcome { success, validationFailed, dbError }

final NotifierProviderFamily<WeightFormController, WeightFormState, int?>
    weightFormControllerProvider =
    NotifierProviderFamily<WeightFormController, WeightFormState, int?>(
  WeightFormController.new,
);

class WeightFormController extends FamilyNotifier<WeightFormState, int?> {
  @override
  WeightFormState build(int? editingWeightId) {
    if (editingWeightId == null) {
      final String? petIdStr = ref.read(currentPetIdProvider);
      final int? petId = (petIdStr == null || petIdStr == kAllPetsId)
          ? null
          : int.tryParse(petIdStr);
      return WeightFormState(
        petId: petId,
        measuredAt: DateTime.now(),
      );
    }
    Future<void>.microtask(() => _loadExisting(editingWeightId));
    return const WeightFormState();
  }

  Future<void> _loadExisting(int weightId) async {
    try {
      final repo = ref.read(weightsRepositoryProvider);
      final WeightEntity? w = await repo.getById(weightId);
      if (w == null) return;
      state = WeightFormState.fromExisting(
        weightId: w.id,
        petId: w.petId,
        weightG: w.weightG,
        measuredAt: DateTime.fromMillisecondsSinceEpoch(w.measuredAt),
        notes: w.notes,
      );
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to load weight for editing', error: e, stackTrace: st);
    }
  }

  // フィールド更新
  void updateWeightG(int? v) => state = state.copyWith(weightG: v);
  void updateUnit(WeightUnit v) => state = state.copyWith(unit: v);
  void updateMeasuredAt(DateTime? v) => state = state.copyWith(measuredAt: v);
  void updateNotes(String v) => state = state.copyWith(notes: v);

  // Save
  Future<WeightFormSaveOutcome> save(AppLocalizations l10n) async {
    final validated = state.validate(l10n);
    if (validated.errors.hasAny) {
      state = validated;
      return WeightFormSaveOutcome.validationFailed;
    }
    state = validated.copyWith(isSubmitting: true);

    try {
      final repo = ref.read(weightsRepositoryProvider);
      final String groupId = ref.read(currentGroupIdProvider);
      final int t = state.measuredAt!.toUtc().millisecondsSinceEpoch;

      if (state.isEditing) {
        await repo.update(
          weightId: state.editingWeightId!,
          weightG: state.weightG,
          measuredAtMsec: t,
          notes: state.notes,
        );
      } else {
        await repo.create(
          groupId: groupId,
          petId: state.petId!,
          weightG: state.weightG!,
          measuredAtMsec: t,
          notes: state.notes.trim().isEmpty ? null : state.notes.trim(),
        );
      }

      state = state.copyWith(isSubmitting: false);
      return WeightFormSaveOutcome.success;
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to save weight', error: e, stackTrace: st);
      state = state.copyWith(isSubmitting: false);
      return WeightFormSaveOutcome.dbError;
    }
  }
}
