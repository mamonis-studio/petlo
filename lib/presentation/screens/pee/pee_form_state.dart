// ============================================================================
// petlo - Pee Form State
// ============================================================================

import 'package:flutter/foundation.dart';

import '../../../data/local/database_enums.dart';

@immutable
class PeeFormErrors {
  const PeeFormErrors({this.color, this.amount, this.count, this.peedAt});

  final String? color;
  final String? amount;
  final String? count;
  final String? peedAt;

  bool get hasAny =>
      color != null || amount != null || count != null || peedAt != null;
}

@immutable
class PeeFormState {
  const PeeFormState({
    this.editingPeeId,
    this.petId,
    this.color,
    this.amount,
    this.count = 1,
    this.peedAt,
    this.notes = '',
    this.isSubmitting = false,
    this.errors = const PeeFormErrors(),
  });

  final int? editingPeeId;
  final int? petId;
  final PeeColor? color;
  final RecordAmount? amount;
  final int count;
  final DateTime? peedAt;
  final String notes;
  final bool isSubmitting;
  final PeeFormErrors errors;

  bool get isEditing => editingPeeId != null;

  PeeFormState validate() {
    final errs = PeeFormErrors(
      color: color == null ? '色を選んでください' : null,
      amount: amount == null ? '量を選んでください' : null,
      count: count < 1 || count > 10 ? '回数は1〜10で指定してください' : null,
      peedAt: peedAt == null
          ? '時刻を選んでください'
          : (peedAt!.isAfter(DateTime.now().add(const Duration(minutes: 5)))
              ? '未来の時刻は記録できません'
              : null),
    );
    return copyWith(errors: errs);
  }

  static PeeFormState fromExisting({
    required int peeId,
    required int petId,
    required PeeColor color,
    required RecordAmount amount,
    required int count,
    required DateTime peedAt,
    String? notes,
  }) {
    return PeeFormState(
      editingPeeId: peeId,
      petId: petId,
      color: color,
      amount: amount,
      count: count,
      peedAt: peedAt,
      notes: notes ?? '',
    );
  }

  PeeFormState copyWith({
    Object? editingPeeId = _sentinel,
    Object? petId = _sentinel,
    Object? color = _sentinel,
    Object? amount = _sentinel,
    int? count,
    Object? peedAt = _sentinel,
    String? notes,
    bool? isSubmitting,
    PeeFormErrors? errors,
  }) {
    return PeeFormState(
      editingPeeId: editingPeeId == _sentinel
          ? this.editingPeeId
          : editingPeeId as int?,
      petId: petId == _sentinel ? this.petId : petId as int?,
      color: color == _sentinel ? this.color : color as PeeColor?,
      amount: amount == _sentinel ? this.amount : amount as RecordAmount?,
      count: count ?? this.count,
      peedAt: peedAt == _sentinel ? this.peedAt : peedAt as DateTime?,
      notes: notes ?? this.notes,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errors: errors ?? this.errors,
    );
  }

  static const Object _sentinel = Object();
}
