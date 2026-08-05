// ============================================================================
// petlo - v9 → v10 Migration Test (build 72)
// ============================================================================
//
// §13 #1: v9 のデータが入った DB に v10 を被せても、既存のペット・記録が
//         無傷であること。新テーブルが空で作成されること。
//
// v9 の DB は「v10 スキーマから prevention 2 テーブルを DROP し、
// user_version を 9 に戻したもの」として再現する。
// v10 が純粋な追加のみ (§0 の非破壊制約) であることが前提なので、
// この再現が成立すること自体が制約の検証にもなっている。
//
// ============================================================================

@Tags(<String>['needs_codegen'])
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/local/app_database.dart';

void main() {
  group('migration v9 → v10', () {
    late Directory tmp;
    late File dbFile;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('petlo_v10_test');
      dbFile = File('${tmp.path}/petlo.sqlite');
    });

    tearDown(() async {
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    });

    test('既存データが無傷のまま予防テーブルが追加される', () async {
      // ---- 1. v9 相当の DB を用意し、ユーザーデータを入れる ----
      AppDatabase db = AppDatabase.forTesting(NativeDatabase(dbFile));
      final int t = DateTime.now().toUtc().millisecondsSinceEpoch;

      await db.customStatement(
        'INSERT INTO pets (name, type, group_id, sync_status, '
        'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        <Object?>['ぽち', 'dog', 'personal', 'synced', t, t],
      );
      await db.customStatement(
        'INSERT INTO medications (pet_id, group_id, medicine_name, '
        'administered_at, sync_status, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        <Object?>[1, 'personal', '既存の薬', t, 'synced', t, t],
      );

      // 予防テーブルを落として v9 の姿に戻す
      await db.customStatement('DROP TABLE prevention_doses');
      await db.customStatement('DROP TABLE prevention_courses');
      await db.customStatement('PRAGMA user_version = 9');
      await db.close();

      // ---- 2. v10 のアプリで開き直す (onUpgrade 9→10 が走る) ----
      db = AppDatabase.forTesting(NativeDatabase(dbFile));

      final List<QueryRow> version =
          await db.customSelect('PRAGMA user_version').get();
      expect(version.first.read<int>('user_version'), 10);

      // ---- 3. 既存データが無傷 ----
      final List<QueryRow> pets =
          await db.customSelect('SELECT name FROM pets').get();
      expect(pets, hasLength(1));
      expect(pets.first.read<String>('name'), 'ぽち');

      final List<QueryRow> meds = await db
          .customSelect('SELECT medicine_name FROM medications')
          .get();
      expect(meds, hasLength(1));
      expect(meds.first.read<String>('medicine_name'), '既存の薬');

      // ---- 4. 予防テーブルが空で作成されている ----
      final List<QueryRow> tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name LIKE 'prevention_%'",
          )
          .get();
      expect(
        tables.map((QueryRow r) => r.read<String>('name')).toList()..sort(),
        <String>['prevention_courses', 'prevention_doses'],
      );

      expect(await db.select(db.preventionCourses).get(), isEmpty);
      expect(await db.select(db.preventionDoses).get(), isEmpty);

      await db.close();
    });
  });
}
