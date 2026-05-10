// ============================================================================
// petlo - Medication Reminders Repository Tests
// ============================================================================

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/data/repositories/medication_reminders_repository.dart';

void main() {
  late AppDatabase db;
  late MedicationRemindersRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = MedicationRemindersRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('MedicationRemindersRepository validation', () {
    test('rejects empty medicineName', () async {
      expect(
        () => repo.create(
          groupId: 'personal',
          petId: 1,
          medicineName: '',
          times: <String>['09:00'],
          weekdays: <int>{},
        ),
        throwsArgumentError,
      );
    }, tags: <String>['needs_codegen']);

    test('rejects whitespace-only medicineName', () async {
      expect(
        () => repo.create(
          groupId: 'personal',
          petId: 1,
          medicineName: '   ',
          times: <String>['09:00'],
          weekdays: <int>{},
        ),
        throwsArgumentError,
      );
    }, tags: <String>['needs_codegen']);

    test('rejects empty times list', () async {
      expect(
        () => repo.create(
          groupId: 'personal',
          petId: 1,
          medicineName: 'TestMed',
          times: <String>[],
          weekdays: <int>{},
        ),
        throwsArgumentError,
      );
    }, tags: <String>['needs_codegen']);

    test('rejects malformed time string', () async {
      expect(
        () => repo.create(
          groupId: 'personal',
          petId: 1,
          medicineName: 'TestMed',
          times: <String>['9:00'], // 1桁
          weekdays: <int>{},
        ),
        throwsArgumentError,
      );
    }, tags: <String>['needs_codegen']);

    test('rejects out-of-range weekday', () async {
      expect(
        () => repo.create(
          groupId: 'personal',
          petId: 1,
          medicineName: 'TestMed',
          times: <String>['09:00'],
          weekdays: <int>{7}, // 6 まで
        ),
        throwsArgumentError,
      );
    }, tags: <String>['needs_codegen']);
  });

  group('MedicationRemindersRepository CRUD', () {
    test('create + getById', () async {
      final int id = await repo.create(
        groupId: 'personal',
        petId: 1,
        medicineName: 'フィラリア',
        times: <String>['09:00', '21:00'],
        weekdays: <int>{1, 3, 5},
        dosage: '1錠',
      );
      final r = await repo.getById(id);
      expect(r, isNotNull);
      expect(r!.medicineName, 'フィラリア');
      expect(r.times, <String>['09:00', '21:00']);
      expect(r.weekdaysBits, <int>{1, 3, 5});
      expect(r.dosage, '1錠');
      expect(r.enabled, isTrue);
    }, tags: <String>['needs_codegen']);

    test('setEnabled toggles flag', () async {
      final int id = await repo.create(
        groupId: 'personal',
        petId: 1,
        medicineName: 'TestMed',
        times: <String>['09:00'],
        weekdays: <int>{},
      );
      await repo.setEnabled(id, false);
      final r1 = await repo.getById(id);
      expect(r1!.enabled, isFalse);
      await repo.setEnabled(id, true);
      final r2 = await repo.getById(id);
      expect(r2!.enabled, isTrue);
    }, tags: <String>['needs_codegen']);

    test('countActiveForGroup excludes deleted', () async {
      await repo.create(
        groupId: 'personal',
        petId: 1,
        medicineName: 'A',
        times: <String>['09:00'],
        weekdays: <int>{},
      );
      final int id2 = await repo.create(
        groupId: 'personal',
        petId: 1,
        medicineName: 'B',
        times: <String>['10:00'],
        weekdays: <int>{},
      );
      expect(await repo.countActiveForGroup('personal'), 2);
      await repo.softDelete(id2);
      expect(await repo.countActiveForGroup('personal'), 1);
    }, tags: <String>['needs_codegen']);

    test('getAllEnabled excludes disabled and deleted', () async {
      final int a = await repo.create(
        groupId: 'personal',
        petId: 1,
        medicineName: 'A',
        times: <String>['09:00'],
        weekdays: <int>{},
      );
      final int b = await repo.create(
        groupId: 'personal',
        petId: 1,
        medicineName: 'B',
        times: <String>['10:00'],
        weekdays: <int>{},
      );
      final int c = await repo.create(
        groupId: 'personal',
        petId: 1,
        medicineName: 'C',
        times: <String>['11:00'],
        weekdays: <int>{},
      );
      await repo.setEnabled(b, false);
      await repo.softDelete(c);

      final enabled = await repo.getAllEnabled();
      expect(enabled.length, 1);
      expect(enabled.first.id, a);
    }, tags: <String>['needs_codegen']);
  });
}
