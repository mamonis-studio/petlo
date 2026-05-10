// ============================================================================
// petlo - Weight Form State
// ============================================================================

import 'package:flutter/foundation.dart';

import '../../../data/local/database_enums.dart';

@immutable
class WeightFormErrors {
  const WeightFormErrors({this.weightG, this.measuredAt});

  final String? weightG;
  final String? measuredAt;

  bool get hasAny => weightG != null || measuredAt != null;
}

@immutable
class WeightFormState {
  const WeightFormState({
    this.editingWeightId,
    this.petId,
    this.weightG,
    this.unit = WeightUnit.kg,
    this.measuredAt,
    this.notes = '',
    this.isSubmitting = false,
    this.errors = const WeightFormErrors(),
  });

  final int? editingWeightId;
  final int? petId;
  final int? weightG; // 内部表現はグラム
  final WeightUnit unit; // UI表示単位のみ
  final DateTime? measuredAt;
  final String notes;
  final bool isSubmitting;
  final WeightFormErrors errors;

  bool get isEditing => editingWeightId != null;

  WeightFormState validate() {
    final errs = WeightFormErrors(
      weightG: weightG == null
          ? '体重を入力してください'
          : (weightG! <= 0
              ? '0より大きい値を入力してください'
              : (weightG! > 200000 ? '200kg以下で入力してください' : null)),
      measuredAt: measuredAt == null
          ? '時刻を選んでください'
          : (measuredAt!.isAfter(
                  DateTime.now().add(const Duration(minutes: 5)))
              ? '未来の時刻は記録できません'
              : null),
    );
    return copyWith(errors: errs);
  }

  static WeightFormState fromExisting({
    required int weightId,
    required int petId,
    required int weightG,
    required DateTime measuredAt,
    String? notes,
    WeightUnit unit = WeightUnit.kg,
  }) {
    return WeightFormState(
      editingWeightId: weightId,
      petId: petId,
      weightG: weightG,
      unit: unit,
      measuredAt: measuredAt,
      notes: notes ?? '',
    );
  }

  WeightFormState copyWith({
    Object? editingWeightId = _sentinel,
    Object? petId = _sentinel,
    Object? weightG = _sentinel,
    WeightUnit? unit,
    Object? measuredAt = _sentinel,
    String? notes,
    bool? isSubmitting,
    WeightFormErrors? errors,
  }) {
    return WeightFormState(
      editingWeightId: editingWeightId == _sentinel
          ? this.editingWeightId
          : editingWeightId as int?,
      petId: petId == _sentinel ? this.petId : petId as int?,
      weightG: weightG == _sentinel ? this.weightG : weightG as int?,
      unit: unit ?? this.unit,
      measuredAt:
          measuredAt == _sentinel ? this.measuredAt : measuredAt as DateTime?,
      notes: notes ?? this.notes,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errors: errors ?? this.errors,
    );
  }

  static const Object _sentinel = Object();
}
