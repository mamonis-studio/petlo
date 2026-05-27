// ============================================================================
// petlo - Pee Form Controller
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/pees_providers.dart';
import '../../providers/scope_providers.dart';
import 'pee_form_state.dart';

enum PeeFormSaveOutcome { success, validationFailed, dbError }

final NotifierProviderFamily<PeeFormController, PeeFormState, int?>
    peeFormControllerProvider =
    NotifierProviderFamily<PeeFormController, PeeFormState, int?>(
  PeeFormController.new,
);

class PeeFormController extends FamilyNotifier<PeeFormState, int?> {
  @override
  PeeFormState build(int? editingPeeId) {
    if (editingPeeId == null) {
      final String? petIdStr = ref.read(currentPetIdProvider);
      final int? petId = (petIdStr == null || petIdStr == kAllPetsId)
          ? null
          : int.tryParse(petIdStr);
      return PeeFormState(petId: petId, peedAt: DateTime.now());
    }
    Future<void>.microtask(() => _loadExisting(editingPeeId));
    return const PeeFormState();
  }

  Future<void> _loadExisting(int peeId) async {
    try {
      final repo = ref.read(peesRepositoryProvider);
      final PeeEntity? p = await repo.getById(peeId);
      if (p == null) return;
      state = PeeFormState.fromExisting(
        peeId: p.id,
        petId: p.petId,
        color: p.color,
        amount: p.amount,
        count: p.count,
        peedAt: DateTime.fromMillisecondsSinceEpoch(p.peedAt),
        notes: p.notes,
      );
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to load pee for editing', error: e, stackTrace: st);
    }
  }

  void updateColor(PeeColor? v) => state = state.copyWith(color: v);
  void updateAmount(RecordAmount? v) => state = state.copyWith(amount: v);
  void updateCount(int v) => state = state.copyWith(count: v);
  void updatePeedAt(DateTime? v) => state = state.copyWith(peedAt: v);
  void updateNotes(String v) => state = state.copyWith(notes: v);

  Future<PeeFormSaveOutcome> save(AppLocalizations l10n) async {
    final validated = state.validate(l10n);
    if (validated.errors.hasAny) {
      state = validated;
      return PeeFormSaveOutcome.validationFailed;
    }
    state = validated.copyWith(isSubmitting: true);

    try {
      final repo = ref.read(peesRepositoryProvider);
      final String groupId = ref.read(currentGroupIdProvider);
      final int t = state.peedAt!.toUtc().millisecondsSinceEpoch;

      if (state.isEditing) {
        await repo.update(
          peeId: state.editingPeeId!,
          color: state.color,
          amount: state.amount,
          count: state.count,
          peedAtMsec: t,
          notes: state.notes,
        );
      } else {
        await repo.create(
          groupId: groupId,
          petId: state.petId!,
          color: state.color!,
          amount: state.amount!,
          count: state.count,
          peedAtMsec: t,
          notes: state.notes.trim().isEmpty ? null : state.notes.trim(),
        );
      }

      state = state.copyWith(isSubmitting: false);
      return PeeFormSaveOutcome.success;
    } catch (e, st) {
      PetloLogger.instance.w('Failed to save pee', error: e, stackTrace: st);
      state = state.copyWith(isSubmitting: false);
      return PeeFormSaveOutcome.dbError;
    }
  }
}
