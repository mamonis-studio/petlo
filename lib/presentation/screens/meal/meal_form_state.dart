// ============================================================================
// petlo - Meal Form State
// ============================================================================
//
// MealRecordScreen の状態DTO。
//
// 設計:
//   - イミュータブル(copyWithで更新)
//   - foodId / foodNameFreeText の二択を明確に表現
//   - validate() で全フィールドのバリデーション結果を返す
//
// ============================================================================

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../data/local/database_enums.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../widgets/forms/validators.dart';

/// バリデーション結果
@immutable
class MealFormErrors {
  const MealFormErrors({
    this.foodName,
    this.amountG,
    this.appetite,
    this.eatenAt,
  });

  final String? foodName;
  final String? amountG;
  final String? appetite;
  final String? eatenAt;

  bool get hasAny =>
      foodName != null ||
      amountG != null ||
      appetite != null ||
      eatenAt != null;
}

/// MealForm メイン状態
@immutable
class MealFormState {
  const MealFormState({
    this.editingMealId,
    this.petId,
    this.foodId,
    this.foodNameFreeText = '',
    this.amountG,
    this.appetite,
    this.eatenAt,
    this.notes = '',
    this.photoFile,
    this.savedPhotoRelativePath,
    this.isSubmitting = false,
    this.errors = const MealFormErrors(),
  });

  /// 編集モード時の食事記録ID(nullなら新規)
  final int? editingMealId;

  /// 対象ペットID(必須、画面起動時にセット)
  final int? petId;

  // ===== Food (foodId or freeText の二択) =====
  /// マスタ参照ID(直近3銘柄から選んだ場合)
  final int? foodId;

  /// フリー入力(マスタなしの新規銘柄)
  final String foodNameFreeText;

  // ===== Meal info =====
  final int? amountG;
  final MealAppetite? appetite;
  final DateTime? eatenAt;
  final String notes;

  // ===== Photo =====
  final File? photoFile;
  final String? savedPhotoRelativePath;

  // ===== UI状態 =====
  final bool isSubmitting;
  final MealFormErrors errors;

  bool get isEditing => editingMealId != null;

  /// 「銘柄が指定されているか」 — foodId または freeText どちらかあればOK
  bool get hasFoodSelected =>
      foodId != null || foodNameFreeText.trim().isNotEmpty;

  /// バリデーション
  MealFormState validate(AppLocalizations l10n) {
    final MealFormErrors errs = MealFormErrors(
      foodName: !hasFoodSelected ? l10n.meal_validation_food_required : null,
      amountG: amountG != null && amountG! < 0
          ? l10n.meal_validation_amount_non_negative
          : (amountG != null && amountG! > 10000
              ? l10n.meal_validation_amount_max
              : null),
      appetite: appetite == null ? l10n.meal_validation_appetite_required : null,
      eatenAt: eatenAt == null
          ? l10n.meal_validation_time_required
          : (eatenAt!.isAfter(DateTime.now().add(const Duration(minutes: 5)))
              ? l10n.record_validation_future_time
              : null),
    );
    return copyWith(errors: errs);
  }

  /// 既存食事記録から復元 (編集モード)
  static MealFormState fromExisting({
    required int mealId,
    required int petId,
    int? foodId,
    String? foodNameFreeText,
    int? amountG,
    required MealAppetite appetite,
    required DateTime eatenAt,
    String? notes,
    String? savedPhotoRelativePath,
  }) {
    return MealFormState(
      editingMealId: mealId,
      petId: petId,
      foodId: foodId,
      foodNameFreeText: foodNameFreeText ?? '',
      amountG: amountG,
      appetite: appetite,
      eatenAt: eatenAt,
      notes: notes ?? '',
      savedPhotoRelativePath: savedPhotoRelativePath,
    );
  }

  MealFormState copyWith({
    Object? editingMealId = _sentinel,
    Object? petId = _sentinel,
    Object? foodId = _sentinel,
    String? foodNameFreeText,
    Object? amountG = _sentinel,
    Object? appetite = _sentinel,
    Object? eatenAt = _sentinel,
    String? notes,
    Object? photoFile = _sentinel,
    Object? savedPhotoRelativePath = _sentinel,
    bool? isSubmitting,
    MealFormErrors? errors,
  }) {
    return MealFormState(
      editingMealId: editingMealId == _sentinel
          ? this.editingMealId
          : editingMealId as int?,
      petId: petId == _sentinel ? this.petId : petId as int?,
      foodId: foodId == _sentinel ? this.foodId : foodId as int?,
      foodNameFreeText: foodNameFreeText ?? this.foodNameFreeText,
      amountG: amountG == _sentinel ? this.amountG : amountG as int?,
      appetite: appetite == _sentinel
          ? this.appetite
          : appetite as MealAppetite?,
      eatenAt:
          eatenAt == _sentinel ? this.eatenAt : eatenAt as DateTime?,
      notes: notes ?? this.notes,
      photoFile: photoFile == _sentinel ? this.photoFile : photoFile as File?,
      savedPhotoRelativePath: savedPhotoRelativePath == _sentinel
          ? this.savedPhotoRelativePath
          : savedPhotoRelativePath as String?,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errors: errors ?? this.errors,
    );
  }

  static const Object _sentinel = Object();
}
