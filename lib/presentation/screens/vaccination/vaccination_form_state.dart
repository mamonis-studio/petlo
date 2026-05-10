// ============================================================================
// petlo - Vaccination Form State
// ============================================================================

import 'dart:io';

import 'package:flutter/foundation.dart';

@immutable
class VaccinationFormErrors {
  const VaccinationFormErrors({
    this.kind,
    this.administeredAt,
    this.nextDueAt,
  });

  final String? kind;
  final String? administeredAt;
  final String? nextDueAt;

  bool get hasAny =>
      kind != null || administeredAt != null || nextDueAt != null;
}

@immutable
class VaccinationFormState {
  const VaccinationFormState({
    this.editingVaccinationId,
    this.petId,
    this.kind = '',
    this.administeredAt,
    this.nextDueAt,
    this.clinicName = '',
    this.notes = '',
    this.photoFile,
    this.savedPhotoRelativePath,
    this.isSubmitting = false,
    this.errors = const VaccinationFormErrors(),
  });

  final int? editingVaccinationId;
  final int? petId;
  final String kind;
  final DateTime? administeredAt;
  final DateTime? nextDueAt;
  final String clinicName;
  final String notes;
  final File? photoFile;
  final String? savedPhotoRelativePath;
  final bool isSubmitting;
  final VaccinationFormErrors errors;

  bool get isEditing => editingVaccinationId != null;

  VaccinationFormState validate() {
    final errs = VaccinationFormErrors(
      kind: kind.trim().isEmpty ? 'ワクチン種別を入力してください' : null,
      administeredAt: administeredAt == null
          ? '接種日を選んでください'
          : (administeredAt!.isAfter(
                  DateTime.now().add(const Duration(days: 1)))
              ? '未来の日付は記録できません'
              : null),
      nextDueAt: (nextDueAt != null && administeredAt != null &&
              !nextDueAt!.isAfter(administeredAt!))
          ? '次回予定日は接種日より後にしてください'
          : null,
    );
    return copyWith(errors: errs);
  }

  static VaccinationFormState fromExisting({
    required int vaccinationId,
    required int petId,
    required String kind,
    required DateTime administeredAt,
    DateTime? nextDueAt,
    String? clinicName,
    String? notes,
    String? savedPhotoRelativePath,
  }) {
    return VaccinationFormState(
      editingVaccinationId: vaccinationId,
      petId: petId,
      kind: kind,
      administeredAt: administeredAt,
      nextDueAt: nextDueAt,
      clinicName: clinicName ?? '',
      notes: notes ?? '',
      savedPhotoRelativePath: savedPhotoRelativePath,
    );
  }

  VaccinationFormState copyWith({
    Object? editingVaccinationId = _sentinel,
    Object? petId = _sentinel,
    String? kind,
    Object? administeredAt = _sentinel,
    Object? nextDueAt = _sentinel,
    String? clinicName,
    String? notes,
    Object? photoFile = _sentinel,
    Object? savedPhotoRelativePath = _sentinel,
    bool? isSubmitting,
    VaccinationFormErrors? errors,
  }) {
    return VaccinationFormState(
      editingVaccinationId: editingVaccinationId == _sentinel
          ? this.editingVaccinationId
          : editingVaccinationId as int?,
      petId: petId == _sentinel ? this.petId : petId as int?,
      kind: kind ?? this.kind,
      administeredAt: administeredAt == _sentinel
          ? this.administeredAt
          : administeredAt as DateTime?,
      nextDueAt:
          nextDueAt == _sentinel ? this.nextDueAt : nextDueAt as DateTime?,
      clinicName: clinicName ?? this.clinicName,
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
