// ============================================================================
// petlo - Temperature Form Controller
// ============================================================================
//
// 体温フォームのロジック。
//
// 特徴:
//   - 起動時にペット情報も取得 → state.petType に反映 (正常範囲ヒント用)
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/database_provider.dart';
import '../../providers/pets_providers.dart';
import '../../providers/scope_providers.dart';
import '../../providers/temperatures_providers.dart';
import 'temperature_form_state.dart';

enum TemperatureFormSaveOutcome { success, validationFailed, dbError }

final NotifierProviderFamily<TemperatureFormController, TemperatureFormState,
        int?>
    temperatureFormControllerProvider =
    NotifierProviderFamily<TemperatureFormController, TemperatureFormState,
        int?>(
  TemperatureFormController.new,
);

class TemperatureFormController
    extends FamilyNotifier<TemperatureFormState, int?> {
  @override
  TemperatureFormState build(int? editingTempId) {
    if (editingTempId == null) {
      final String? petIdStr = ref.read(currentPetIdProvider);
      final int? petId = (petIdStr == null || petIdStr == kAllPetsId)
          ? null
          : int.tryParse(petIdStr);

      // ペット種別を非同期で取得して state に反映
      Future<void>.microtask(() => _loadPetType(petId));

      return TemperatureFormState(
        petId: petId,
        measuredAt: DateTime.now(),
      );
    }
    Future<void>.microtask(() => _loadExisting(editingTempId));
    return const TemperatureFormState();
  }

  Future<void> _loadExisting(int tempId) async {
    try {
      final repo = ref.read(temperaturesRepositoryProvider);
      final TemperatureEntity? t = await repo.getById(tempId);
      if (t == null) return;

      // ペット種別取得
      PetType? petType;
      try {
        final petsRepo = ref.read(petsRepositoryProvider);
        final PetEntity? pet = await petsRepo.getPet(t.petId);
        petType = pet?.type;
      } catch (e) {
        // 取得失敗してもFormは動かす
      }

      state = TemperatureFormState.fromExisting(
        tempId: t.id,
        petId: t.petId,
        petType: petType,
        tempCelsiusX10: t.tempCelsiusX10,
        measuredAt: DateTime.fromMillisecondsSinceEpoch(t.measuredAt),
        notes: t.notes,
      );
    } catch (e, st) {
      PetloLogger.instance.w('Failed to load temperature for editing',
          error: e, stackTrace: st);
    }
  }

  Future<void> _loadPetType(int? petId) async {
    if (petId == null) return;
    try {
      final petsRepo = ref.read(petsRepositoryProvider);
      final PetEntity? pet = await petsRepo.getPet(petId);
      if (pet != null) {
        state = state.copyWith(petType: pet.type);
      }
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to load pet type', error: e, stackTrace: st);
    }
  }

  // フィールド更新
  void updateTempCelsiusX10(int? v) =>
      state = state.copyWith(tempCelsiusX10: v);
  void updateUnit(TemperatureUnit v) => state = state.copyWith(unit: v);
  void updateMeasuredAt(DateTime? v) =>
      state = state.copyWith(measuredAt: v);
  void updateNotes(String v) => state = state.copyWith(notes: v);

  // Save
  Future<TemperatureFormSaveOutcome> save(AppLocalizations l10n) async {
    final validated = state.validate(l10n);
    if (validated.errors.hasAny) {
      state = validated;
      return TemperatureFormSaveOutcome.validationFailed;
    }
    state = validated.copyWith(isSubmitting: true);

    try {
      final repo = ref.read(temperaturesRepositoryProvider);
      final String groupId = ref.read(currentGroupIdProvider);
      final int t = state.measuredAt!.toUtc().millisecondsSinceEpoch;

      if (state.isEditing) {
        await repo.update(
          tempId: state.editingTempId!,
          tempCelsiusX10: state.tempCelsiusX10,
          measuredAtMsec: t,
          notes: state.notes,
        );
      } else {
        await repo.create(
          groupId: groupId,
          petId: state.petId!,
          tempCelsiusX10: state.tempCelsiusX10!,
          measuredAtMsec: t,
          notes: state.notes.trim().isEmpty ? null : state.notes.trim(),
        );
      }

      state = state.copyWith(isSubmitting: false);
      return TemperatureFormSaveOutcome.success;
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to save temperature', error: e, stackTrace: st);
      state = state.copyWith(isSubmitting: false);
      return TemperatureFormSaveOutcome.dbError;
    }
  }
}
