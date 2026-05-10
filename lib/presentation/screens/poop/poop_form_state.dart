// ============================================================================
// petlo - Poop Form State
// ============================================================================

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../data/local/database_enums.dart';

@immutable
class PoopFormErrors {
  const PoopFormErrors({
    this.form,
    this.color,
    this.amount,
    this.pooedAt,
  });

  final String? form;
  final String? color;
  final String? amount;
  final String? pooedAt;

  bool get hasAny =>
      form != null || color != null || amount != null || pooedAt != null;
}

@immutable
class PoopFormState {
  const PoopFormState({
    this.editingPoopId,
    this.petId,
    this.form,
    this.color,
    this.amount,
    this.pooedAt,
    this.notes = '',
    this.photoFile,
    this.savedPhotoRelativePath,
    this.isSubmitting = false,
    this.errors = const PoopFormErrors(),
  });

  final int? editingPoopId;
  final int? petId;
  final PoopForm? form;
  final PoopColor? color;
  final RecordAmount? amount;
  final DateTime? pooedAt;
  final String notes;
  final File? photoFile;
  final String? savedPhotoRelativePath;
  final bool isSubmitting;
  final PoopFormErrors errors;

  bool get isEditing => editingPoopId != null;

  PoopFormState validate() {
    final PoopFormErrors errs = PoopFormErrors(
      form: form == null ? '形状を選んでください' : null,
      color: color == null ? '色を選んでください' : null,
      amount: amount == null ? '量を選んでください' : null,
      pooedAt: pooedAt == null
          ? '時刻を選んでください'
          : (pooedAt!.isAfter(DateTime.now().add(const Duration(minutes: 5)))
              ? '未来の時刻は記録できません'
              : null),
    );
    return copyWith(errors: errs);
  }

  static PoopFormState fromExisting({
    required int poopId,
    required int petId,
    required PoopForm form,
    required PoopColor color,
    required RecordAmount amount,
    required DateTime pooedAt,
    String? notes,
    String? savedPhotoRelativePath,
  }) {
    return PoopFormState(
      editingPoopId: poopId,
      petId: petId,
      form: form,
      color: color,
      amount: amount,
      pooedAt: pooedAt,
      notes: notes ?? '',
      savedPhotoRelativePath: savedPhotoRelativePath,
    );
  }

  PoopFormState copyWith({
    Object? editingPoopId = _sentinel,
    Object? petId = _sentinel,
    Object? form = _sentinel,
    Object? color = _sentinel,
    Object? amount = _sentinel,
    Object? pooedAt = _sentinel,
    String? notes,
    Object? photoFile = _sentinel,
    Object? savedPhotoRelativePath = _sentinel,
    bool? isSubmitting,
    PoopFormErrors? errors,
  }) {
    return PoopFormState(
      editingPoopId: editingPoopId == _sentinel
          ? this.editingPoopId
          : editingPoopId as int?,
      petId: petId == _sentinel ? this.petId : petId as int?,
      form: form == _sentinel ? this.form : form as PoopForm?,
      color: color == _sentinel ? this.color : color as PoopColor?,
      amount: amount == _sentinel ? this.amount : amount as RecordAmount?,
      pooedAt: pooedAt == _sentinel ? this.pooedAt : pooedAt as DateTime?,
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
