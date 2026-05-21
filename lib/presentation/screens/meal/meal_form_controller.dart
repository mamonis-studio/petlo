// ============================================================================
// petlo - Meal Form Controller
// ============================================================================
//
// MealRecordScreen のロジック。
//
// 責務:
//   1. State の保持と更新
//   2. 既存記録のロード (編集時)
//   3. Save 時の処理:
//      - バリデーション
//      - 銘柄処理 (foodId か freeText を upsert で foodId に統一)
//      - DB書込み
//      - 写真保存
//   4. ペット選択 → petIdを取得して引数で受け取る
//
// ============================================================================

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/database_provider.dart';
import '../../providers/foods_providers.dart';
import '../../providers/meals_providers.dart';
import '../../providers/photo_storage_provider.dart';
import '../../providers/scope_providers.dart';
import 'meal_form_state.dart';

enum MealFormSaveOutcome {
  success,
  validationFailed,
  dbError,
}

/// 食事記録Controller。
/// editingMealId が null なら新規、あれば編集モード。
final NotifierProviderFamily<MealFormController, MealFormState, int?>
    mealFormControllerProvider =
    NotifierProviderFamily<MealFormController, MealFormState, int?>(
  MealFormController.new,
);

class MealFormController extends FamilyNotifier<MealFormState, int?> {
  @override
  MealFormState build(int? editingMealId) {
    if (editingMealId == null) {
      // 新規モード: 現在ペット + 現在時刻で初期化
      final String? petIdStr = ref.read(currentPetIdProvider);
      final int? petId =
          (petIdStr == null || petIdStr == kAllPetsId) ? null : int.tryParse(petIdStr);
      return MealFormState(
        petId: petId,
        eatenAt: DateTime.now(),
      );
    }
    // 編集モード
    Future<void>.microtask(() => _loadExisting(editingMealId));
    return const MealFormState();
  }

  Future<void> _loadExisting(int mealId) async {
    try {
      final repo = ref.read(mealsRepositoryProvider);
      final MealEntity? m = await repo.getById(mealId);
      if (m == null) {
        PetloLogger.instance.w('Meal not found for editing: $mealId');
        return;
      }
      state = MealFormState.fromExisting(
        mealId: m.id,
        petId: m.petId,
        foodId: m.foodId,
        foodNameFreeText: m.foodNameFreeText,
        amountG: m.amountG,
        appetite: m.appetite,
        eatenAt: DateTime.fromMillisecondsSinceEpoch(m.eatenAt),
        notes: m.notes,
        savedPhotoRelativePath: m.photoPath,
      );
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to load meal for editing', error: e, stackTrace: st);
    }
  }

  // ============================================================================
  // フィールド更新
  // ============================================================================

  /// 直近銘柄チップから選択
  void selectExistingFood(FoodEntity food) {
    state = state.copyWith(
      foodId: food.id,
      foodNameFreeText: food.name, // 表示用にも入れておく
      // デフォルト量があり、まだ未入力なら自動で入れる
      amountG: state.amountG ?? food.defaultAmountG,
    );
  }

  /// フリー入力で銘柄名を変更
  /// (foodId は null に戻す = マスタ未確定状態)
  void updateFoodNameFreeText(String value) {
    state = state.copyWith(
      foodId: null, // フリー入力中は foodId を消す
      foodNameFreeText: value,
    );
  }

  void updateAmountG(int? value) {
    state = state.copyWith(amountG: value);
  }

  void updateAppetite(MealAppetite? value) {
    state = state.copyWith(appetite: value);
  }

  void updateEatenAt(DateTime? value) {
    state = state.copyWith(eatenAt: value);
  }

  void updateNotes(String value) {
    state = state.copyWith(notes: value);
  }

  void updatePhotoFile(File? value) {
    state = state.copyWith(photoFile: value);
  }

  // ============================================================================
  // Save
  // ============================================================================

  Future<MealFormSaveOutcome> save(AppLocalizations l10n) async {
    // 1. バリデーション
    final MealFormState validated = state.validate(l10n);
    if (validated.errors.hasAny) {
      state = validated;
      return MealFormSaveOutcome.validationFailed;
    }
    state = validated.copyWith(isSubmitting: true);

    try {
      final mealsRepo = ref.read(mealsRepositoryProvider);
      final foodsRepo = ref.read(foodsRepositoryProvider);
      final photoStorage = ref.read(photoStorageProvider);
      final String groupId = ref.read(currentGroupIdProvider);

      // 2. 銘柄処理: フリー入力なら foodsマスタにupsert → foodId に統一
      int? finalFoodId = state.foodId;
      String? finalFreeText;

      if (finalFoodId == null && state.foodNameFreeText.trim().isNotEmpty) {
        // フリー入力 → マスタにupsert
        finalFoodId = await foodsRepo.upsertByName(
          name: state.foodNameFreeText.trim(),
          defaultAmountG: state.amountG,
        );
      } else if (finalFoodId != null) {
        // 既存銘柄選択時 → useCount 増加
        await foodsRepo.touchUsage(finalFoodId);
      } else {
        finalFreeText = state.foodNameFreeText.trim().isEmpty
            ? null
            : state.foodNameFreeText.trim();
      }

      // 3. DB書込み
      final int eatenAtMsec = state.eatenAt!.toUtc().millisecondsSinceEpoch;

      int mealId;
      if (state.isEditing) {
        await mealsRepo.updateMeal(
          mealId: state.editingMealId!,
          foodId: finalFoodId,
          clearFoodId: finalFoodId == null,
          foodNameFreeText: finalFreeText,
          amountG: state.amountG,
          clearAmountG: state.amountG == null,
          appetite: state.appetite,
          eatenAtMsec: eatenAtMsec,
          notes: state.notes,
        );
        mealId = state.editingMealId!;
      } else {
        mealId = await mealsRepo.createMeal(
          groupId: groupId,
          petId: state.petId!,
          foodId: finalFoodId,
          foodNameFreeText: finalFreeText,
          amountG: state.amountG,
          appetite: state.appetite!,
          eatenAtMsec: eatenAtMsec,
          notes: state.notes.trim().isEmpty ? null : state.notes.trim(),
        );
      }

      // 4. 写真保存
      if (state.photoFile != null) {
        try {
          final String relPath = await photoStorage.saveMealPhoto(
            mealId: mealId,
            source: state.photoFile!,
          );
          await mealsRepo.updateMeal(mealId: mealId, photoPath: relPath);
        } catch (e, st) {
          PetloLogger.instance
              .w('Failed to save meal photo', error: e, stackTrace: st);
          // 写真失敗してもレコード自体は成功扱い
        }
      }

      state = state.copyWith(isSubmitting: false);
      return MealFormSaveOutcome.success;
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to save meal', error: e, stackTrace: st);
      state = state.copyWith(isSubmitting: false);
      return MealFormSaveOutcome.dbError;
    }
  }
}
