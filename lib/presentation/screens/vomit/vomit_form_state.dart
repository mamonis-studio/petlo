// ============================================================================
// petlo - Vomit Form State (rev5.5)
// ============================================================================

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../data/local/database_enums.dart';

@immutable
class VomitFormErrors {
  const VomitFormErrors({
    this.color,
    this.colorOtherText,
    this.amount,
    this.count,
    this.vomitedAt,
  });

  final String? color;
  final String? colorOtherText;
  final String? amount;
  final String? count;
  final String? vomitedAt;

  bool get hasAny =>
      color != null ||
      colorOtherText != null ||
      amount != null ||
      count != null ||
      vomitedAt != null;
}

@immutable
class VomitFormState {
  const VomitFormState({
    this.editingVomitId,
    this.petId,
    this.color,
    this.colorOtherText = '',
    this.amount,
    this.count = 1,
    this.containsFood = false,
    this.suspectIngestion = false,
    this.vomitedAt,
    this.notes = '',
    this.photoFile,
    this.savedPhotoRelativePath,
    this.isSubmitting = false,
    this.errors = const VomitFormErrors(),
  });

  final int? editingVomitId;
  final int? petId;
  final VomitColor? color;
  final String colorOtherText;
  final RecordAmount? amount;
  final int count;
  final bool containsFood;
  final bool suspectIngestion;
  final DateTime? vomitedAt;
  final String notes;
  final File? photoFile;
  final String? savedPhotoRelativePath;
  final bool isSubmitting;
  final VomitFormErrors errors;

  bool get isEditing => editingVomitId != null;

  VomitFormState validate() {
    final errs = VomitFormErrors(
      color: color == null ? '色を選んでください' : null,
      colorOtherText: color == VomitColor.other && colorOtherText.trim().isEmpty
          ? '色の説明を入力してください'
          : null,
      amount: amount == null ? '量を選んでください' : null,
      count: count < 1 || count > 10 ? '回数は1〜10で指定してください' : null,
      vomitedAt: vomitedAt == null
          ? '時刻を選んでください'
          : (vomitedAt!.isAfter(DateTime.now().add(const Duration(minutes: 5)))
              ? '未来の時刻は記録できません'
              : null),
    );
    return copyWith(errors: errs);
  }

  static VomitFormState fromExisting({
    required int vomitId,
    required int petId,
    required VomitColor color,
    String? colorOtherText,
    required RecordAmount amount,
    required int count,
    required bool containsFood,
    required bool suspectIngestion,
    required DateTime vomitedAt,
    String? notes,
    String? savedPhotoRelativePath,
  }) {
    return VomitFormState(
      editingVomitId: vomitId,
      petId: petId,
      color: color,
      colorOtherText: colorOtherText ?? '',
      amount: amount,
      count: count,
      containsFood: containsFood,
      suspectIngestion: suspectIngestion,
      vomitedAt: vomitedAt,
      notes: notes ?? '',
      savedPhotoRelativePath: savedPhotoRelativePath,
    );
  }

  VomitFormState copyWith({
    Object? editingVomitId = _sentinel,
    Object? petId = _sentinel,
    Object? color = _sentinel,
    String? colorOtherText,
    Object? amount = _sentinel,
    int? count,
    bool? containsFood,
    bool? suspectIngestion,
    Object? vomitedAt = _sentinel,
    String? notes,
    Object? photoFile = _sentinel,
    Object? savedPhotoRelativePath = _sentinel,
    bool? isSubmitting,
    VomitFormErrors? errors,
  }) {
    return VomitFormState(
      editingVomitId: editingVomitId == _sentinel
          ? this.editingVomitId
          : editingVomitId as int?,
      petId: petId == _sentinel ? this.petId : petId as int?,
      color: color == _sentinel ? this.color : color as VomitColor?,
      colorOtherText: colorOtherText ?? this.colorOtherText,
      amount: amount == _sentinel ? this.amount : amount as RecordAmount?,
      count: count ?? this.count,
      containsFood: containsFood ?? this.containsFood,
      suspectIngestion: suspectIngestion ?? this.suspectIngestion,
      vomitedAt: vomitedAt == _sentinel ? this.vomitedAt : vomitedAt as DateTime?,
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
