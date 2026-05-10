// ============================================================================
// petlo - Visit Form State
// ============================================================================

import 'package:flutter/foundation.dart';

import '../../widgets/forms/multi_photo_picker.dart';

@immutable
class VisitFormErrors {
  const VisitFormErrors({
    this.reason,
    this.visitedAt,
    this.costJpy,
  });

  final String? reason;
  final String? visitedAt;
  final String? costJpy;

  bool get hasAny => reason != null || visitedAt != null || costJpy != null;
}

@immutable
class VisitFormState {
  const VisitFormState({
    this.editingVisitId,
    this.petId,
    this.visitedAt,
    this.clinicName = '',
    this.vetName = '',
    this.reason = '',
    this.diagnosis = '',
    this.treatment = '',
    this.costJpy,
    this.photoSlots = const <PhotoSlot>[],
    this.notes = '',
    this.isSubmitting = false,
    this.errors = const VisitFormErrors(),
  });

  final int? editingVisitId;
  final int? petId;
  final DateTime? visitedAt;
  final String clinicName;
  final String vetName;
  final String reason;
  final String diagnosis;
  final String treatment;
  final int? costJpy;
  final List<PhotoSlot> photoSlots;
  final String notes;
  final bool isSubmitting;
  final VisitFormErrors errors;

  bool get isEditing => editingVisitId != null;

  VisitFormState validate() {
    final errs = VisitFormErrors(
      reason: reason.trim().isEmpty ? '主訴を入力してください' : null,
      visitedAt: visitedAt == null
          ? '通院日を選んでください'
          : (visitedAt!.isAfter(
                  DateTime.now().add(const Duration(days: 1)))
              ? '未来の日付は記録できません'
              : null),
      costJpy: costJpy != null && costJpy! < 0
          ? '0円以上で入力してください'
          : (costJpy != null && costJpy! > 99999999
              ? '金額が大きすぎます'
              : null),
    );
    return copyWith(errors: errs);
  }

  static VisitFormState fromExisting({
    required int visitId,
    required int petId,
    required DateTime visitedAt,
    String? clinicName,
    String? vetName,
    required String reason,
    String? diagnosis,
    String? treatment,
    int? costJpy,
    List<String>? savedPhotoPaths,
    String? notes,
  }) {
    return VisitFormState(
      editingVisitId: visitId,
      petId: petId,
      visitedAt: visitedAt,
      clinicName: clinicName ?? '',
      vetName: vetName ?? '',
      reason: reason,
      diagnosis: diagnosis ?? '',
      treatment: treatment ?? '',
      costJpy: costJpy,
      photoSlots: (savedPhotoPaths ?? <String>[])
          .map((String p) => PhotoSlot(savedRelativePath: p))
          .toList(),
      notes: notes ?? '',
    );
  }

  VisitFormState copyWith({
    Object? editingVisitId = _sentinel,
    Object? petId = _sentinel,
    Object? visitedAt = _sentinel,
    String? clinicName,
    String? vetName,
    String? reason,
    String? diagnosis,
    String? treatment,
    Object? costJpy = _sentinel,
    List<PhotoSlot>? photoSlots,
    String? notes,
    bool? isSubmitting,
    VisitFormErrors? errors,
  }) {
    return VisitFormState(
      editingVisitId: editingVisitId == _sentinel
          ? this.editingVisitId
          : editingVisitId as int?,
      petId: petId == _sentinel ? this.petId : petId as int?,
      visitedAt:
          visitedAt == _sentinel ? this.visitedAt : visitedAt as DateTime?,
      clinicName: clinicName ?? this.clinicName,
      vetName: vetName ?? this.vetName,
      reason: reason ?? this.reason,
      diagnosis: diagnosis ?? this.diagnosis,
      treatment: treatment ?? this.treatment,
      costJpy: costJpy == _sentinel ? this.costJpy : costJpy as int?,
      photoSlots: photoSlots ?? this.photoSlots,
      notes: notes ?? this.notes,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errors: errors ?? this.errors,
    );
  }

  static const Object _sentinel = Object();
}
