// ============================================================================
// petlo - Pet Form State
// ============================================================================
//
// PetFormScreen の状態を保持するDTO。
//
// 設計:
//   - イミュータブル(copyWithで更新)
//   - DB の PetEntity とは別物 (フォーム内では "未入力" を null で表す等、
//     画面固有の意味を持たせる)
//   - validate() で全フィールドのバリデーション結果を返す
//
// ============================================================================

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../data/local/database_enums.dart';
import '../../widgets/forms/validators.dart';

/// フォームのバリデーション結果を集約。
@immutable
class PetFormErrors {
  const PetFormErrors({
    this.name,
    this.type,
    this.breed,
    this.sex,
    this.idealWeightMinG,
    this.idealWeightMaxG,
    this.primaryVetPhone,
    this.emergencyVetPhone,
  });

  final String? name;
  final String? type;
  final String? breed;
  final String? sex;
  final String? idealWeightMinG;
  final String? idealWeightMaxG;
  final String? primaryVetPhone;
  final String? emergencyVetPhone;

  /// エラーが1つでもあるか
  bool get hasAny =>
      name != null ||
      type != null ||
      breed != null ||
      sex != null ||
      idealWeightMinG != null ||
      idealWeightMaxG != null ||
      primaryVetPhone != null ||
      emergencyVetPhone != null;
}

/// PetForm のメイン状態
@immutable
class PetFormState {
  const PetFormState({
    this.editingPetId,
    this.name = '',
    this.type,
    this.breed = '',
    this.sex,
    this.neutered = false,
    this.birthday,
    this.idealWeightMinG,
    this.idealWeightMaxG,
    this.photoFile,
    this.savedPhotoRelativePath,
    this.chronicConditions = const <String>[],
    this.allergies = const <String>[],
    this.primaryVetName = '',
    this.primaryVetPhone = '',
    this.primaryVetAddress = '',
    this.emergencyVetName = '',
    this.emergencyVetPhone = '',
    this.emergencyVetAddress = '',
    this.isSubmitting = false,
    this.errors = const PetFormErrors(),
  });

  /// 編集モードの場合の対象ペットID(null なら新規作成)
  final int? editingPetId;

  // ===== 基本情報 =====
  final String name;
  final PetType? type;
  final String breed;
  final PetSex? sex;
  final bool neutered;
  final DateTime? birthday;

  // ===== 体重 =====
  /// 入力時はグラム整数(UI側でkg/lb変換)
  final int? idealWeightMinG;
  final int? idealWeightMaxG;

  // ===== 写真 =====
  /// 新規選択直後の一時ファイル(まだ未保存)
  final File? photoFile;

  /// 既存ペット編集時の保存済み相対パス
  final String? savedPhotoRelativePath;

  // ===== 健康情報 =====
  final List<String> chronicConditions;
  final List<String> allergies;

  // ===== 連絡先 =====
  final String primaryVetName;
  final String primaryVetPhone;
  final String primaryVetAddress;
  final String emergencyVetName;
  final String emergencyVetPhone;
  final String emergencyVetAddress;

  // ===== UI状態 =====
  final bool isSubmitting;
  final PetFormErrors errors;

  /// 編集モードか
  bool get isEditing => editingPetId != null;

  /// バリデーション。エラーは新しい PetFormState を返して伝える。
  PetFormState validate() {
    final PetFormErrors errs = PetFormErrors(
      name: Validators.compose(<Validator>[
        Validators.required(message: '名前を入力してください'),
        Validators.minLength(1),
        Validators.maxLength(50),
      ])(name),
      type: type == null ? '犬か猫を選んでください' : null,
      // build 6 で任意化 (DB nullable)、build 12 でバリデーションも撤去
      breed: null,
      // build 22: 性別も任意化 (DB nullable)、未選択でも保存可能
      sex: null,
      idealWeightMinG: idealWeightMinG != null &&
              idealWeightMaxG != null &&
              idealWeightMinG! > idealWeightMaxG!
          ? '下限は上限以下にしてください'
          : null,
      idealWeightMaxG: idealWeightMaxG != null &&
              idealWeightMinG != null &&
              idealWeightMaxG! < idealWeightMinG!
          ? '上限は下限以上にしてください'
          : null,
      primaryVetPhone: Validators.phoneNumberOrEmpty()(primaryVetPhone),
      emergencyVetPhone: Validators.phoneNumberOrEmpty()(emergencyVetPhone),
    );
    return copyWith(errors: errs);
  }

  /// 既存ペット情報からPetFormStateを復元 (編集時に使う)
  static PetFormState fromExistingValues({
    required int petId,
    required String name,
    required PetType type,
    required String breed,
    PetSex? sex,
    required bool neutered,
    DateTime? birthday,
    int? idealWeightMinG,
    int? idealWeightMaxG,
    String? savedPhotoRelativePath,
    List<String>? chronicConditions,
    List<String>? allergies,
    String? primaryVetName,
    String? primaryVetPhone,
    String? primaryVetAddress,
    String? emergencyVetName,
    String? emergencyVetPhone,
    String? emergencyVetAddress,
  }) {
    return PetFormState(
      editingPetId: petId,
      name: name,
      type: type,
      breed: breed,
      sex: sex,
      neutered: neutered,
      birthday: birthday,
      idealWeightMinG: idealWeightMinG,
      idealWeightMaxG: idealWeightMaxG,
      savedPhotoRelativePath: savedPhotoRelativePath,
      chronicConditions: chronicConditions ?? const <String>[],
      allergies: allergies ?? const <String>[],
      primaryVetName: primaryVetName ?? '',
      primaryVetPhone: primaryVetPhone ?? '',
      primaryVetAddress: primaryVetAddress ?? '',
      emergencyVetName: emergencyVetName ?? '',
      emergencyVetPhone: emergencyVetPhone ?? '',
      emergencyVetAddress: emergencyVetAddress ?? '',
    );
  }

  PetFormState copyWith({
    Object? editingPetId = _sentinel,
    String? name,
    Object? type = _sentinel,
    String? breed,
    Object? sex = _sentinel,
    bool? neutered,
    Object? birthday = _sentinel,
    Object? idealWeightMinG = _sentinel,
    Object? idealWeightMaxG = _sentinel,
    Object? photoFile = _sentinel,
    Object? savedPhotoRelativePath = _sentinel,
    List<String>? chronicConditions,
    List<String>? allergies,
    String? primaryVetName,
    String? primaryVetPhone,
    String? primaryVetAddress,
    String? emergencyVetName,
    String? emergencyVetPhone,
    String? emergencyVetAddress,
    bool? isSubmitting,
    PetFormErrors? errors,
  }) {
    return PetFormState(
      editingPetId: editingPetId == _sentinel
          ? this.editingPetId
          : editingPetId as int?,
      name: name ?? this.name,
      type: type == _sentinel ? this.type : type as PetType?,
      breed: breed ?? this.breed,
      sex: sex == _sentinel ? this.sex : sex as PetSex?,
      neutered: neutered ?? this.neutered,
      birthday: birthday == _sentinel ? this.birthday : birthday as DateTime?,
      idealWeightMinG: idealWeightMinG == _sentinel
          ? this.idealWeightMinG
          : idealWeightMinG as int?,
      idealWeightMaxG: idealWeightMaxG == _sentinel
          ? this.idealWeightMaxG
          : idealWeightMaxG as int?,
      photoFile: photoFile == _sentinel ? this.photoFile : photoFile as File?,
      savedPhotoRelativePath: savedPhotoRelativePath == _sentinel
          ? this.savedPhotoRelativePath
          : savedPhotoRelativePath as String?,
      chronicConditions: chronicConditions ?? this.chronicConditions,
      allergies: allergies ?? this.allergies,
      primaryVetName: primaryVetName ?? this.primaryVetName,
      primaryVetPhone: primaryVetPhone ?? this.primaryVetPhone,
      primaryVetAddress: primaryVetAddress ?? this.primaryVetAddress,
      emergencyVetName: emergencyVetName ?? this.emergencyVetName,
      emergencyVetPhone: emergencyVetPhone ?? this.emergencyVetPhone,
      emergencyVetAddress: emergencyVetAddress ?? this.emergencyVetAddress,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errors: errors ?? this.errors,
    );
  }

  /// nullとunsetを区別するためのセンチネル
  static const Object _sentinel = Object();
}
