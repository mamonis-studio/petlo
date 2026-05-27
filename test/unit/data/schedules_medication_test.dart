// ============================================================================
// petlo - Schedules medication (build 47b) Tests
// ============================================================================
//
// build 47b (Scope B1/B2/B4) のテスト。
//   1. schedules.times / weekdaysBits カラムが ALTER TABLE で追加された後も
//      既存 schedule (= category != medication) は壊れないこと
//   2. SchedulesRepository.create で category=medication + times/weekdays を
//      渡すと正しく保存されること
//   3. category=medication 以外で渡した times/weekdays は無視されること
//   4. update の clearMedicationFields=true で null に戻ること
//   5. update の clearMedicationFields=false で部分更新が効くこと
//
// 注: drift の onCreate は最新スキーマで全テーブルを作るため、v6→v7 の
// migration コードパス自体は migration_test (別ファイル / DB 実機検証) で
// カバーする。本ファイルは「カラムが存在する前提での読み書き」を担保する。
//
// ============================================================================

@Tags(<String>['needs_codegen'])
library;

import 'package:drift/drift.dart' show QueryRow, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/data/repositories/schedules_repository.dart';

void main() {
  group('SchedulesRepository (build 47b medication)', () {
    late AppDatabase db;
    late SchedulesRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = SchedulesRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('non-medication schedule has null times / weekdaysBits', () async {
      final int id = await repo.create(
        groupId: 'personal',
        title: 'Vaccination',
        category: ScheduleCategory.vaccination,
        scheduledAtMsec: DateTime.now().millisecondsSinceEpoch,
      );
      final ScheduleEntity? s = await repo.getById(id);
      expect(s, isNotNull);
      expect(s!.times, isNull);
      expect(s.weekdaysBits, isNull);
    });

    test('medication schedule persists times[] + weekdays bitset', () async {
      final int id = await repo.create(
        groupId: 'personal',
        title: 'Antibiotics',
        category: ScheduleCategory.medication,
        scheduledAtMsec: DateTime.now().millisecondsSinceEpoch,
        times: <String>['08:00', '20:00'],
        weekdays: <int>{1, 3, 5}, // 月水金 → 0b0101010 = 42
      );
      final ScheduleEntity? s = await repo.getById(id);
      expect(s, isNotNull);
      expect(s!.times, '["08:00","20:00"]');
      expect(s.weekdaysBits, 42);
    });

    test('medication schedule with empty weekdays stores null (= daily)',
        () async {
      final int id = await repo.create(
        groupId: 'personal',
        title: 'Vitamin',
        category: ScheduleCategory.medication,
        scheduledAtMsec: DateTime.now().millisecondsSinceEpoch,
        times: <String>['09:00'],
        weekdays: <int>{},
      );
      final ScheduleEntity? s = await repo.getById(id);
      expect(s!.weekdaysBits, isNull,
          reason: 'empty weekdays should be persisted as null');
    });

    test('times/weekdays passed on non-medication category are ignored',
        () async {
      final int id = await repo.create(
        groupId: 'personal',
        title: 'Grooming',
        category: ScheduleCategory.grooming,
        scheduledAtMsec: DateTime.now().millisecondsSinceEpoch,
        times: <String>['10:00'],
        weekdays: <int>{2},
      );
      final ScheduleEntity? s = await repo.getById(id);
      expect(s!.times, isNull);
      expect(s.weekdaysBits, isNull);
    });

    test('update with clearMedicationFields=true wipes both columns',
        () async {
      final int id = await repo.create(
        groupId: 'personal',
        title: 'Antibiotics',
        category: ScheduleCategory.medication,
        scheduledAtMsec: DateTime.now().millisecondsSinceEpoch,
        times: <String>['08:00'],
        weekdays: <int>{1},
      );
      await repo.update(
        scheduleId: id,
        category: ScheduleCategory.custom,
        clearMedicationFields: true,
      );
      final ScheduleEntity? s = await repo.getById(id);
      expect(s!.category, ScheduleCategory.custom);
      expect(s.times, isNull);
      expect(s.weekdaysBits, isNull);
    });

    test('update without clear preserves untouched medication fields',
        () async {
      final int id = await repo.create(
        groupId: 'personal',
        title: 'Antibiotics',
        category: ScheduleCategory.medication,
        scheduledAtMsec: DateTime.now().millisecondsSinceEpoch,
        times: <String>['08:00'],
        weekdays: <int>{2},
      );
      // title だけ書き換え。times/weekdays は指定しない → そのまま
      await repo.update(scheduleId: id, title: 'Antibiotics v2');
      final ScheduleEntity? s = await repo.getById(id);
      expect(s!.title, 'Antibiotics v2');
      expect(s.times, '["08:00"]');
      expect(s.weekdaysBits, 4); // 0b0000100 = 4 (wd=2)
    });
  });

  group('migrateMedicationRemindersToSchedules (build 47b Scope B2)', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      // build 49 (Scope C1) で medication_reminders テーブルは drift schema
      // から削除されたため、onCreate (= v8 current schema) では作られない。
      // v7→v8 アップグレードパスの helper を検証するために、v7 時点の
      // medication_reminders テーブルを手動で組み立てる (アップグレード時に
      // 必ず存在していた構造をそのまま再現)。
      await db.customStatement(
        'CREATE TABLE medication_reminders ('
        'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        'remote_id TEXT, '
        "group_id TEXT NOT NULL DEFAULT 'personal', "
        'pet_id INTEGER NOT NULL, '
        'medicine_name TEXT NOT NULL, '
        'dosage TEXT, '
        'times TEXT, '
        'weekdays_bits INTEGER, '
        'enabled INTEGER NOT NULL DEFAULT 1, '
        'start_date INTEGER, '
        'end_date INTEGER, '
        'notes TEXT, '
        'created_by TEXT, '
        "sync_status TEXT NOT NULL DEFAULT 'synced', "
        'deleted_at INTEGER, '
        'created_at INTEGER NOT NULL, '
        'updated_at INTEGER NOT NULL, '
        'last_modified_at_client INTEGER'
        ')',
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('copies enabled medication_reminder → schedule with times', () async {
      final int t = DateTime.now().millisecondsSinceEpoch;
      // 投入: meds_reminders 1 件 (enabled, 月水金朝晩)
      await db.customStatement(
        'INSERT INTO medication_reminders '
        '(pet_id, group_id, medicine_name, dosage, times, weekdays_bits, '
        'enabled, notes, sync_status, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          1, 'personal', 'Antibiotics', '5mg',
          '["08:00","20:00"]', 42, 1, 'after meals', 'synced', t, t,
        ],
      );

      await db.migrateMedicationRemindersToSchedules();

      final List<QueryRow> rows = await db.customSelect(
        "SELECT title, times, weekdays_bits, recurrence, notes, category "
        "FROM schedules WHERE category = 'medication'",
      ).get();
      expect(rows.length, 1);
      final QueryRow s = rows.first;
      expect(s.read<String>('title'), 'Antibiotics');
      expect(s.read<String?>('times'), '["08:00","20:00"]');
      expect(s.read<int?>('weekdays_bits'), 42);
      expect(s.read<String>('recurrence'), 'daily');
      final String notes = s.read<String>('notes');
      expect(notes.contains('after meals'), isTrue);
      expect(notes.contains('5mg'), isTrue,
          reason: 'dosage should be appended to notes');
    });

    test('disabled medication_reminder loses times (becomes date-marker)',
        () async {
      final int t = DateTime.now().millisecondsSinceEpoch;
      await db.customStatement(
        'INSERT INTO medication_reminders '
        '(pet_id, group_id, medicine_name, times, weekdays_bits, enabled, '
        'sync_status, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          1, 'personal', 'OldMed', '["09:00"]', 0, 0, 'synced', t, t,
        ],
      );

      await db.migrateMedicationRemindersToSchedules();

      final List<QueryRow> rows = await db.customSelect(
        "SELECT times, recurrence FROM schedules WHERE category = 'medication'",
      ).get();
      expect(rows.length, 1);
      expect(rows.first.read<String?>('times'), isNull,
          reason: 'disabled reminder migrates without notification times');
      expect(rows.first.read<String>('recurrence'), 'none');
    });

    test('idempotent: second call does not duplicate', () async {
      final int t = DateTime.now().millisecondsSinceEpoch;
      await db.customStatement(
        'INSERT INTO medication_reminders '
        '(pet_id, group_id, medicine_name, times, weekdays_bits, enabled, '
        'sync_status, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          1, 'personal', 'OnceOnly', '["08:00"]', 0, 1, 'synced', t, t,
        ],
      );

      await db.migrateMedicationRemindersToSchedules();
      await db.migrateMedicationRemindersToSchedules();

      final List<QueryRow> rows = await db.customSelect(
        "SELECT COUNT(*) AS c FROM schedules WHERE category = 'medication'",
      ).get();
      expect(rows.first.read<int>('c'), 1,
          reason: 'second run should be a no-op (idempotent)');
    });

    test('preserves deleted_at on migrated row', () async {
      final int t = DateTime.now().millisecondsSinceEpoch;
      const int legacyDeletedAt = 99999;
      await db.customStatement(
        'INSERT INTO medication_reminders '
        '(pet_id, group_id, medicine_name, times, weekdays_bits, enabled, '
        'sync_status, deleted_at, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          1, 'personal', 'Tombstone', '["07:00"]', 0, 1, 'synced',
          legacyDeletedAt, t, t,
        ],
      );

      await db.migrateMedicationRemindersToSchedules();

      final List<QueryRow> rows = await db.customSelect(
        "SELECT deleted_at FROM schedules WHERE title = 'Tombstone'",
      ).get();
      expect(rows.first.read<int>('deleted_at'), legacyDeletedAt);
    });
  });

  group('SchedulesRepository.getAllForRescheduling (build 47b Scope B3)', () {
    late AppDatabase db;
    late SchedulesRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = SchedulesRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('returns medication schedules with times', () async {
      final int future =
          DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch;
      await repo.create(
        groupId: 'personal',
        title: 'Med',
        category: ScheduleCategory.medication,
        scheduledAtMsec: future,
        times: <String>['08:00'],
      );
      final List<ScheduleEntity> list = await repo.getAllForRescheduling();
      expect(list.length, 1);
    });

    test('skips deleted schedules', () async {
      final int id = await repo.create(
        groupId: 'personal',
        title: 'Med',
        category: ScheduleCategory.medication,
        scheduledAtMsec: DateTime.now().millisecondsSinceEpoch,
        times: <String>['08:00'],
      );
      await repo.softDelete(id);
      final List<ScheduleEntity> list = await repo.getAllForRescheduling();
      expect(list, isEmpty);
    });

    test('returns future schedules with notificationTiming != none', () async {
      final int future =
          DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch;
      await repo.create(
        groupId: 'personal',
        title: 'Vacc',
        category: ScheduleCategory.vaccination,
        scheduledAtMsec: future,
        notificationTiming: ScheduleNotificationTiming.day_before,
      );
      final List<ScheduleEntity> list = await repo.getAllForRescheduling();
      expect(list.length, 1);
    });

    test('excludes past schedules with notificationTiming != none', () async {
      final int past =
          DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch;
      await repo.create(
        groupId: 'personal',
        title: 'OldVacc',
        category: ScheduleCategory.vaccination,
        scheduledAtMsec: past,
        notificationTiming: ScheduleNotificationTiming.day_before,
      );
      final List<ScheduleEntity> list = await repo.getAllForRescheduling();
      // past schedule without times[] should be excluded
      expect(list, isEmpty);
    });

    test('orders by scheduledAt ascending', () async {
      final int t1 =
          DateTime.now().add(const Duration(days: 10)).millisecondsSinceEpoch;
      final int t2 =
          DateTime.now().add(const Duration(days: 2)).millisecondsSinceEpoch;
      await repo.create(
        groupId: 'personal',
        title: 'Later',
        category: ScheduleCategory.medication,
        scheduledAtMsec: t1,
        times: <String>['08:00'],
      );
      await repo.create(
        groupId: 'personal',
        title: 'Earlier',
        category: ScheduleCategory.medication,
        scheduledAtMsec: t2,
        times: <String>['08:00'],
      );
      final List<ScheduleEntity> list = await repo.getAllForRescheduling();
      expect(list.first.title, 'Earlier');
      expect(list.last.title, 'Later');
    });
  });
}

// Suppress unused import for QueryRow / Variable when this file is consumed
// from the runner under tighter lints.
// ignore_for_file: unused_import
void _unused() {
  Variable<int>(0);
  // QueryRow is exposed as a return type elsewhere — kept for visibility.
}
