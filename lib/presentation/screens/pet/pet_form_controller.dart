// ============================================================================
// petlo - Pet Form Controller
// ============================================================================
//
// PetFormScreen のロジックを集約。
//
// 責務:
//   1. 状態(PetFormState)の保持と更新
//   2. 既存ペット情報のロード(編集時)
//   3. Save 時のバリデーション → 同名警告 → DB書き込み → 写真保存
//   4. currentPetId の自動切替(新規作成時)
//
// UI(PetFormScreen)はこのControllerの state を watch し、
// アクション(updateName 等)を呼ぶだけ。
//
// ============================================================================

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/database_provider.dart';
import '../../providers/pet_selection_controller.dart';
import '../../providers/pets_providers.dart';
import '../../providers/photo_storage_provider.dart';
import '../../providers/schedules_providers.dart';
import '../../providers/scope_providers.dart';
import 'pet_form_state.dart';

/// 結果型: save() の戻り値
enum PetFormSaveOutcome {
  /// 保存成功 (新規/編集 共通)
  success,

  /// バリデーションエラーで保存しなかった
  validationFailed,

  /// 同名ペットが存在する → UIで警告ダイアログ表示が必要
  duplicateNameNeedsConfirmation,

  /// DBエラー
  dbError,
}

/// 同名警告にユーザーが「続行」と答えた後に呼ばれる確認後saveの戻り値
enum PetFormFinalSaveOutcome {
  success,
  dbError,
}

/// PetFormController用のProviderファミリー。
/// 編集時は petId を渡す、新規時は null を渡す。
final NotifierProviderFamily<PetFormController, PetFormState, int?>
    petFormControllerProvider =
    NotifierProviderFamily<PetFormController, PetFormState, int?>(
  PetFormController.new,
);

class PetFormController extends FamilyNotifier<PetFormState, int?> {
  @override
  PetFormState build(int? editingPetId) {
    if (editingPetId == null) {
      return const PetFormState();
    }
    // 編集モード: 既存ペット情報をロード(非同期)
    Future<void>.microtask(() => _loadExistingPet(editingPetId));
    return PetFormState(editingPetId: editingPetId);
  }

  Future<void> _loadExistingPet(int petId) async {
    try {
      final repo = ref.read(petsRepositoryProvider);
      final PetEntity? pet = await repo.getPet(petId);
      if (pet == null) {
        PetloLogger.instance.w('Pet not found for editing: $petId');
        return;
      }
      state = PetFormState.fromExistingValues(
        petId: pet.id,
        name: pet.name,
        type: pet.type,
        breed: pet.breed ?? '',
        sex: pet.sex,
        neutered: pet.neutered,
        birthday: pet.birthday == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(pet.birthday!),
        idealWeightMinG: pet.idealWeightMinG,
        idealWeightMaxG: pet.idealWeightMaxG,
        savedPhotoRelativePath: pet.photoPath,
        chronicConditions: pet.chronicConditions,
        allergies: pet.allergies,
        primaryVetName: pet.primaryVetName,
        primaryVetPhone: pet.primaryVetPhone,
        primaryVetAddress: pet.primaryVetAddress,
        emergencyVetName: pet.emergencyVetName,
        emergencyVetPhone: pet.emergencyVetPhone,
        emergencyVetAddress: pet.emergencyVetAddress,
      );
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to load pet for editing', error: e, stackTrace: st);
    }
  }

  // ============================================================================
  // フィールド更新アクション
  // ============================================================================

  void updateName(String value) {
    state = state.copyWith(name: value);
  }

  void updateType(PetType? value) {
    state = state.copyWith(type: value);
  }

  void updateBreed(String value) {
    state = state.copyWith(breed: value);
  }

  void updateSex(PetSex? value) {
    state = state.copyWith(sex: value);
  }

  void updateNeutered(bool value) {
    state = state.copyWith(neutered: value);
  }

  void updateBirthday(DateTime? value) {
    state = state.copyWith(birthday: value);
  }

  void updateIdealWeightMinG(int? value) {
    state = state.copyWith(idealWeightMinG: value);
  }

  void updateIdealWeightMaxG(int? value) {
    state = state.copyWith(idealWeightMaxG: value);
  }

  void updatePhotoFile(File? file) {
    state = state.copyWith(photoFile: file);
  }

  void updateChronicConditions(List<String> value) {
    state = state.copyWith(chronicConditions: value);
  }

  void updateAllergies(List<String> value) {
    state = state.copyWith(allergies: value);
  }

  void updatePrimaryVet({String? name, String? phone, String? address}) {
    state = state.copyWith(
      primaryVetName: name ?? state.primaryVetName,
      primaryVetPhone: phone ?? state.primaryVetPhone,
      primaryVetAddress: address ?? state.primaryVetAddress,
    );
  }

  void updateEmergencyVet({String? name, String? phone, String? address}) {
    state = state.copyWith(
      emergencyVetName: name ?? state.emergencyVetName,
      emergencyVetPhone: phone ?? state.emergencyVetPhone,
      emergencyVetAddress: address ?? state.emergencyVetAddress,
    );
  }

  // ============================================================================
  // Save
  // ============================================================================

  /// 1段階目: バリデーション + 同名チェック。
  /// 同名警告が必要な場合は `duplicateNameNeedsConfirmation` を返し、
  /// UIはダイアログ表示 → confirmAndSave() を呼ぶ。
  Future<PetFormSaveOutcome> save(AppLocalizations l10n) async {
    final PetFormState validated = state.validate(l10n);
    if (validated.errors.hasAny) {
      state = validated;
      return PetFormSaveOutcome.validationFailed;
    }
    state = validated;

    // 同名チェック (rev5.5 §4.17)
    final String groupId = ref.read(currentGroupIdProvider);
    final repo = ref.read(petsRepositoryProvider);
    final bool duplicate = await repo.hasPetWithName(
      groupId: groupId,
      name: state.name.trim(),
      excludePetId: state.editingPetId,
    );

    if (duplicate) {
      return PetFormSaveOutcome.duplicateNameNeedsConfirmation;
    }

    return _doSave(l10n);
  }

  /// 2段階目: 同名警告ダイアログでユーザーが「続行」を選んだ後の確認後save。
  Future<PetFormFinalSaveOutcome> confirmAndSave(AppLocalizations l10n) async {
    final PetFormSaveOutcome result = await _doSave(l10n);
    return result == PetFormSaveOutcome.success
        ? PetFormFinalSaveOutcome.success
        : PetFormFinalSaveOutcome.dbError;
  }

  Future<PetFormSaveOutcome> _doSave(AppLocalizations l10n) async {
    state = state.copyWith(isSubmitting: true);

    try {
      final repo = ref.read(petsRepositoryProvider);
      final photoStorage = ref.read(photoStorageProvider);
      final String groupId = ref.read(currentGroupIdProvider);

      final int birthdayMsec =
          state.birthday?.toUtc().millisecondsSinceEpoch ?? 0;

      int petId;
      if (state.isEditing) {
        // === 更新 ===
        await repo.updatePet(
          petId: state.editingPetId!,
          name: state.name.trim(),
          breed: state.breed.trim(),
          sex: state.sex,
          neutered: state.neutered,
          birthday: state.birthday == null ? null : birthdayMsec,
          idealWeightMinG: state.idealWeightMinG,
          idealWeightMaxG: state.idealWeightMaxG,
          chronicConditions: state.chronicConditions,
          allergies: state.allergies,
          primaryVetName: state.primaryVetName.trim(),
          primaryVetPhone: state.primaryVetPhone.trim(),
          primaryVetAddress: state.primaryVetAddress.trim(),
          emergencyVetName: state.emergencyVetName.trim(),
          emergencyVetPhone: state.emergencyVetPhone.trim(),
          emergencyVetAddress: state.emergencyVetAddress.trim(),
        );
        petId = state.editingPetId!;
      } else {
        // === 新規 ===
        petId = await repo.createPet(
          groupId: groupId,
          name: state.name.trim(),
          type: state.type!, // バリデーション通ってる前提
          breed: state.breed.trim(),
          sex: state.sex,
          neutered: state.neutered,
          birthday: state.birthday == null ? null : birthdayMsec,
          idealWeightMinG: state.idealWeightMinG,
          idealWeightMaxG: state.idealWeightMaxG,
          chronicConditions: state.chronicConditions,
          allergies: state.allergies,
          primaryVetName: state.primaryVetName.trim().isEmpty
              ? null
              : state.primaryVetName.trim(),
          primaryVetPhone: state.primaryVetPhone.trim().isEmpty
              ? null
              : state.primaryVetPhone.trim(),
          primaryVetAddress: state.primaryVetAddress.trim().isEmpty
              ? null
              : state.primaryVetAddress.trim(),
          emergencyVetName: state.emergencyVetName.trim().isEmpty
              ? null
              : state.emergencyVetName.trim(),
          emergencyVetPhone: state.emergencyVetPhone.trim().isEmpty
              ? null
              : state.emergencyVetPhone.trim(),
          emergencyVetAddress: state.emergencyVetAddress.trim().isEmpty
              ? null
              : state.emergencyVetAddress.trim(),
        );
      }

      // === 誕生日 schedule 自動同期 (build 5) ===
      try {
        await ref.read(schedulesRepositoryProvider).upsertBirthdaySchedule(
              groupId: groupId,
              petId: petId,
              petName: state.name.trim(),
              birthdayMsec: state.birthday == null ? null : birthdayMsec,
              birthdaySuffix: l10n.onboarding_pet_birthday_suffix,
            );
      } catch (e, st) {
        PetloLogger.instance
            .w('upsert birthday schedule failed', error: e, stackTrace: st);
      }

      // === 写真保存 ===
      if (state.photoFile != null) {
        try {
          final String relPath = await photoStorage.savePetProfilePhoto(
            petId: petId,
            source: state.photoFile!,
          );
          // photoPath を更新
          await repo.updatePet(
            petId: petId,
            photoPath: relPath,
          );
        } catch (e, st) {
          PetloLogger.instance
              .w('Failed to save pet photo', error: e, stackTrace: st);
          // 写真保存失敗してもペット登録自体は成功扱い
        }
      }

      // === currentPetId 自動切替 (新規作成時のみ) ===
      if (!state.isEditing) {
        await ref.read(petSelectionControllerProvider.notifier).selectPet(petId);
      }

      state = state.copyWith(isSubmitting: false);
      return PetFormSaveOutcome.success;
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to save pet', error: e, stackTrace: st);
      state = state.copyWith(isSubmitting: false);
      return PetFormSaveOutcome.dbError;
    }
  }
}

