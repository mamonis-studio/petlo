// ============================================================================
// petlo - MedicationReminderFormState Tests
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/presentation/screens/medication_reminder/medication_reminder_form_state.dart';

void main() {
  // ==========================================================================
  // validate
  // ==========================================================================
  group('MedicationReminderFormState validate', () {
    test('rejects empty medicineName', () {
      const MedicationReminderFormState s = MedicationReminderFormState(
        medicineName: '',
        times: <String>['09:00'],
      );
      expect(s.validate().errors.medicineName, isNotNull);
    });

    test('rejects whitespace-only medicineName', () {
      const MedicationReminderFormState s = MedicationReminderFormState(
        medicineName: '   ',
        times: <String>['09:00'],
      );
      expect(s.validate().errors.medicineName, isNotNull);
    });

    test('rejects medicineName over 50 chars', () {
      final s = MedicationReminderFormState(
        medicineName: 'a' * 51,
        times: const <String>['09:00'],
      );
      expect(s.validate().errors.medicineName, isNotNull);
    });

    test('rejects empty times', () {
      const MedicationReminderFormState s = MedicationReminderFormState(
        medicineName: 'フィラリア錠',
        times: <String>[],
      );
      expect(s.validate().errors.times, isNotNull);
    });

    test('rejects malformed time format', () {
      const MedicationReminderFormState s = MedicationReminderFormState(
        medicineName: 'フィラリア錠',
        times: <String>['9:00'], // hh が1桁
      );
      expect(s.validate().errors.times, isNotNull);
    });

    test('rejects endDate before startDate', () {
      final s = MedicationReminderFormState(
        medicineName: 'フィラリア錠',
        times: const <String>['09:00'],
        startDate: DateTime(2025, 6, 1),
        endDate: DateTime(2025, 5, 1),
      );
      expect(s.validate().errors.dateRange, isNotNull);
    });

    test('valid with empty weekdays (= every day)', () {
      const MedicationReminderFormState s = MedicationReminderFormState(
        medicineName: 'フィラリア錠',
        times: <String>['09:00'],
        weekdays: <int>{}, // 空 = 毎日
      );
      expect(s.validate().errors.hasAny, isFalse);
      expect(s.isEveryday, isTrue);
    });

    test('valid with specific weekdays', () {
      const MedicationReminderFormState s = MedicationReminderFormState(
        medicineName: 'フィラリア錠',
        times: <String>['08:00', '20:00'],
        weekdays: <int>{1, 3, 5}, // 月水金
      );
      expect(s.validate().errors.hasAny, isFalse);
      expect(s.isEveryday, isFalse);
    });

    test('valid with same start/end date', () {
      final s = MedicationReminderFormState(
        medicineName: 'フィラリア錠',
        times: const <String>['09:00'],
        startDate: DateTime(2025, 6, 1),
        endDate: DateTime(2025, 6, 1),
      );
      expect(s.validate().errors.dateRange, isNull);
    });
  });

  // ==========================================================================
  // copyWith with sentinel
  // ==========================================================================
  group('MedicationReminderFormState copyWith', () {
    test('startDate=null can be set explicitly', () {
      final s = MedicationReminderFormState(
        medicineName: 'フィラリア',
        times: const <String>['09:00'],
        startDate: DateTime(2025, 6, 1),
      );
      final s2 = s.copyWith(startDate: null);
      expect(s2.startDate, isNull);
    });

    test('startDate omitted preserves existing', () {
      final s = MedicationReminderFormState(
        medicineName: 'フィラリア',
        times: const <String>['09:00'],
        startDate: DateTime(2025, 6, 1),
      );
      final s2 = s.copyWith(medicineName: 'インスリン');
      expect(s2.startDate, isNotNull);
      expect(s2.startDate!.year, 2025);
      expect(s2.medicineName, 'インスリン');
    });
  });

  // ==========================================================================
  // fromExisting
  // ==========================================================================
  group('MedicationReminderFormState fromExisting', () {
    test('reconstructs full state', () {
      final s = MedicationReminderFormState.fromExisting(
        reminderId: 7,
        petId: 1,
        medicineName: 'フィラリア',
        dosage: '1錠',
        times: <String>['08:00'],
        weekdays: <int>{1, 3, 5},
        notes: '空腹時',
        startDateMsec:
            DateTime(2025, 6, 1).millisecondsSinceEpoch,
        endDateMsec: null,
        enabled: true,
      );
      expect(s.editingReminderId, 7);
      expect(s.medicineName, 'フィラリア');
      expect(s.times.length, 1);
      expect(s.weekdays.length, 3);
      expect(s.startDate, isNotNull);
      expect(s.endDate, isNull);
      expect(s.enabled, isTrue);
      expect(s.isEditing, isTrue);
    });

    test('handles null dosage and notes', () {
      final s = MedicationReminderFormState.fromExisting(
        reminderId: 1,
        petId: 1,
        medicineName: 'A',
        dosage: null,
        times: <String>['09:00'],
        weekdays: <int>{},
        notes: null,
        enabled: false,
      );
      expect(s.dosage, '');
      expect(s.notes, '');
    });
  });
}
