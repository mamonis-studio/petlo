// ============================================================================
// petlo - Medication Reminder Form State
// ============================================================================

import 'package:flutter/foundation.dart';

@immutable
class MedicationReminderFormErrors {
  const MedicationReminderFormErrors({
    this.medicineName,
    this.times,
    this.weekdays,
    this.dateRange,
  });

  final String? medicineName;
  final String? times;
  final String? weekdays;
  final String? dateRange;

  bool get hasAny =>
      medicineName != null ||
      times != null ||
      weekdays != null ||
      dateRange != null;
}

@immutable
class MedicationReminderFormState {
  const MedicationReminderFormState({
    this.editingReminderId,
    this.petId,
    this.medicineName = '',
    this.dosage = '',
    this.times = const <String>[],
    this.weekdays = const <int>{}, // 空 = 毎日
    this.notes = '',
    this.startDate,
    this.endDate,
    this.enabled = true,
    this.isSubmitting = false,
    this.errors = const MedicationReminderFormErrors(),
  });

  final int? editingReminderId;
  final int? petId;
  final String medicineName;
  final String dosage;
  final List<String> times;

  /// 0=日曜, 1=月曜, ..., 6=土曜。空 Set は「毎日」を意味する
  final Set<int> weekdays;
  final String notes;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool enabled;
  final bool isSubmitting;
  final MedicationReminderFormErrors errors;

  bool get isEditing => editingReminderId != null;

  /// 「毎日」表示用ヘルパー
  bool get isEveryday => weekdays.isEmpty;

  MedicationReminderFormState validate() {
    String? medicineNameErr;
    if (medicineName.trim().isEmpty) {
      medicineNameErr = '薬の名前を入力してください';
    } else if (medicineName.trim().length > 50) {
      medicineNameErr = '50文字以内で入力してください';
    }

    String? timesErr;
    if (times.isEmpty) {
      timesErr = '少なくとも1つ時刻を追加してください';
    } else {
      for (final String t in times) {
        if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(t)) {
          timesErr = '時刻形式が不正です: $t';
          break;
        }
      }
    }

    String? dateRangeErr;
    if (startDate != null && endDate != null) {
      if (endDate!.isBefore(startDate!)) {
        dateRangeErr = '終了日は開始日より後にしてください';
      }
    }

    return copyWith(
      errors: MedicationReminderFormErrors(
        medicineName: medicineNameErr,
        times: timesErr,
        dateRange: dateRangeErr,
      ),
    );
  }

  static MedicationReminderFormState fromExisting({
    required int reminderId,
    required int petId,
    required String medicineName,
    String? dosage,
    required List<String> times,
    required Set<int> weekdays,
    String? notes,
    int? startDateMsec,
    int? endDateMsec,
    required bool enabled,
  }) {
    return MedicationReminderFormState(
      editingReminderId: reminderId,
      petId: petId,
      medicineName: medicineName,
      dosage: dosage ?? '',
      times: List<String>.from(times),
      weekdays: Set<int>.from(weekdays),
      notes: notes ?? '',
      startDate: startDateMsec == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(startDateMsec),
      endDate: endDateMsec == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(endDateMsec),
      enabled: enabled,
    );
  }

  MedicationReminderFormState copyWith({
    Object? editingReminderId = _sentinel,
    Object? petId = _sentinel,
    String? medicineName,
    String? dosage,
    List<String>? times,
    Set<int>? weekdays,
    String? notes,
    Object? startDate = _sentinel,
    Object? endDate = _sentinel,
    bool? enabled,
    bool? isSubmitting,
    MedicationReminderFormErrors? errors,
  }) {
    return MedicationReminderFormState(
      editingReminderId: editingReminderId == _sentinel
          ? this.editingReminderId
          : editingReminderId as int?,
      petId: petId == _sentinel ? this.petId : petId as int?,
      medicineName: medicineName ?? this.medicineName,
      dosage: dosage ?? this.dosage,
      times: times ?? this.times,
      weekdays: weekdays ?? this.weekdays,
      notes: notes ?? this.notes,
      startDate:
          startDate == _sentinel ? this.startDate : startDate as DateTime?,
      endDate: endDate == _sentinel ? this.endDate : endDate as DateTime?,
      enabled: enabled ?? this.enabled,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errors: errors ?? this.errors,
    );
  }

  static const Object _sentinel = Object();
}
