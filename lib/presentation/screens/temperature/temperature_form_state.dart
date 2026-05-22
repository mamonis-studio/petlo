// ============================================================================
// petlo - Temperature Form State
// ============================================================================

import 'package:flutter/foundation.dart';

import '../../../data/local/database_enums.dart';
import '../../../l10n/generated/app_localizations.dart';

@immutable
class TemperatureFormErrors {
  const TemperatureFormErrors({this.tempCelsiusX10, this.measuredAt});

  final String? tempCelsiusX10;
  final String? measuredAt;

  bool get hasAny => tempCelsiusX10 != null || measuredAt != null;
}

@immutable
class TemperatureFormState {
  const TemperatureFormState({
    this.editingTempId,
    this.petId,
    this.petType,
    this.tempCelsiusX10,
    this.unit = TemperatureUnit.celsius,
    this.measuredAt,
    this.notes = '',
    this.isSubmitting = false,
    this.errors = const TemperatureFormErrors(),
  });

  final int? editingTempId;
  final int? petId;

  /// 現在のペット種別 (正常範囲ヒント表示用)
  final PetType? petType;

  final int? tempCelsiusX10; // 摂氏×10
  final TemperatureUnit unit;
  final DateTime? measuredAt;
  final String notes;
  final bool isSubmitting;
  final TemperatureFormErrors errors;

  bool get isEditing => editingTempId != null;

  TemperatureFormState validate(AppLocalizations l10n) {
    final errs = TemperatureFormErrors(
      tempCelsiusX10: tempCelsiusX10 == null
          ? l10n.temperature_validation_required
          : (tempCelsiusX10! < 300 || tempCelsiusX10! > 450
              ? l10n.temperature_validation_range
              : null),
      measuredAt: measuredAt == null
          ? l10n.record_validation_time_required
          : (measuredAt!.isAfter(
                  DateTime.now().add(const Duration(minutes: 5)))
              ? l10n.record_validation_future_time
              : null),
    );
    return copyWith(errors: errs);
  }

  static TemperatureFormState fromExisting({
    required int tempId,
    required int petId,
    PetType? petType,
    required int tempCelsiusX10,
    required DateTime measuredAt,
    String? notes,
    TemperatureUnit unit = TemperatureUnit.celsius,
  }) {
    return TemperatureFormState(
      editingTempId: tempId,
      petId: petId,
      petType: petType,
      tempCelsiusX10: tempCelsiusX10,
      unit: unit,
      measuredAt: measuredAt,
      notes: notes ?? '',
    );
  }

  TemperatureFormState copyWith({
    Object? editingTempId = _sentinel,
    Object? petId = _sentinel,
    Object? petType = _sentinel,
    Object? tempCelsiusX10 = _sentinel,
    TemperatureUnit? unit,
    Object? measuredAt = _sentinel,
    String? notes,
    bool? isSubmitting,
    TemperatureFormErrors? errors,
  }) {
    return TemperatureFormState(
      editingTempId: editingTempId == _sentinel
          ? this.editingTempId
          : editingTempId as int?,
      petId: petId == _sentinel ? this.petId : petId as int?,
      petType: petType == _sentinel ? this.petType : petType as PetType?,
      tempCelsiusX10: tempCelsiusX10 == _sentinel
          ? this.tempCelsiusX10
          : tempCelsiusX10 as int?,
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
