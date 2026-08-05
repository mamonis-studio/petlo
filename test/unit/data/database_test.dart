// ============================================================================
// petlo - Database Smoke Test
// ============================================================================
//
// driftテーブル定義の最低限の動作確認。
// このテストは `flutter pub run build_runner build` 実行後に動く。
//
// テスト対象:
//   - DBがインメモリで作れる
//   - 全28テーブルが存在する
//   - 主要テーブルへの insert/select が動く
//   - enum converter が正しく動作する
//   - マイグレーションがv1で初期化される
//
// このテストはClaude Codeが build_runner を走らせて生成された
// app_database.g.dart があってはじめて通る。
//
// ============================================================================

@Tags(<String>['needs_codegen'])
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/data/local/database_converters.dart';
import 'package:petlo/data/local/database_enums.dart';

void main() {
  group('AppDatabase - schema', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('schemaVersion matches AppDatabaseMigrations.currentVersion', () {
      // build 49 (C1) で v8 (medication_reminders DROP)。
      // build 57: Decision D 純粋実装で v9 (Personal scope backfill)。
      // build 72: 予防コースで v10 (prevention_courses / prevention_doses 追加)。
      expect(db.schemaVersion, 10);
    });

    test('database initializes without errors', () async {
      // 単純なクエリで初期化を確認
      await db.customSelect('SELECT 1').get();
    });

    test('all expected tables exist (build 49: 27 after medication_reminders DROP + pet_scopes)', () async {
      final List<QueryRow> result = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'",
      ).get();

      final List<String> tables = result
          .map((QueryRow row) => row.read<String>('name'))
          .toList()
        ..sort();

      // 27 テーブル + pet_scopes (build 43) で 28 + drift 内部の schema_versions
      expect(tables.length >= 27, isTrue, reason: 'Expected at least 27 tables, got ${tables.length}: $tables');

      // 主要テーブルの存在確認
      const List<String> expected = <String>[
        'pets',
        'meals',
        'foods',
        'poops',
        'pees',
        'vomits',
        'weights',
        'temperatures',
        'diaries',
        'visits',
        'medications',
        'vaccinations',
        'bcs_checks',
        'expiration_items',
        'streak_statuses',
        'groups',
        'group_members',
        'invite_codes',
        'pending_transfers',
        'cancel_feedback',
        'ai_chat_messages',
        'ai_sessions',
        'ai_image_diagnoses',
        'weekly_summaries',
        'sync_queue',
        'upload_queue',
        'account_deletion_queue',
        // build 72: 予防コース
        'prevention_courses',
        'prevention_doses',
      ];

      for (final String name in expected) {
        expect(tables, contains(name), reason: 'Missing table: $name');
      }
    });
  });

  group('Type Converters', () {
    test('AppEnumConverter round-trips', () {
      const converter = AppEnumConverter(PetType.values);
      expect(converter.toSql(PetType.dog), 'dog');
      expect(converter.fromSql('dog'), PetType.dog);
      expect(converter.fromSql('cat'), PetType.cat);
    });

    test('AppEnumConverter throws on unknown value', () {
      const converter = AppEnumConverter(PetType.values);
      expect(
        () => converter.fromSql('unknown_animal'),
        throwsA(isA<FormatException>()),
      );
    });

    test('StringListConverter round-trips', () {
      const converter = StringListConverter();
      const List<String> input = <String>['アレルギー1', 'allergy2'];
      final String json = converter.toSql(input);
      final List<String> output = converter.fromSql(json);
      expect(output, input);
    });

    test('StringListConverter handles empty list', () {
      const converter = StringListConverter();
      expect(converter.fromSql(''), <String>[]);
      expect(converter.fromSql('[]'), <String>[]);
    });

    test('WeekdaysBitsetConverter round-trips', () {
      const converter = WeekdaysBitsetConverter();
      const Set<int> mwf = <int>{1, 3, 5}; // 月水金
      final int bits = converter.toSql(mwf);
      expect(converter.fromSql(bits), mwf);
    });

    test('WeekdaysBitsetConverter rejects invalid weekday', () {
      const converter = WeekdaysBitsetConverter();
      expect(() => converter.toSql(<int>{7}), throwsArgumentError);
      expect(() => converter.toSql(<int>{-1}), throwsArgumentError);
    });

    test('TimeOfDayListConverter validates HH:mm format', () {
      const converter = TimeOfDayListConverter();
      // 正常
      expect(converter.toSql(<String>['07:00', '21:30']), isNotEmpty);
      // 桁数 NG: 1 桁時 → ArgumentError
      expect(() => converter.toSql(<String>['7:00']), throwsArgumentError);
      // build 61: production の RegExp `^\d{2}:\d{2}$` は形式 (2桁:2桁) のみ
      // 検査するため、25:00 や 99:99 のような「形式は合うが範囲外」は
      // throw しない (バリデーションは形式のみ、コメントの意図通り)。
      expect(converter.toSql(<String>['25:00']), isNotEmpty);
    });
  });

  group('VomitColor enum (rev5.5)', () {
    test('main 4 colors are recognized', () {
      expect(VomitColor.clear.isMain, isTrue);
      expect(VomitColor.yellow.isMain, isTrue);
      expect(VomitColor.brown.isMain, isTrue);
      expect(VomitColor.food.isMain, isTrue);
    });

    test('detail 5 colors are not main', () {
      expect(VomitColor.white_foam.isMain, isFalse);
      expect(VomitColor.red.isMain, isFalse);
      expect(VomitColor.green.isMain, isFalse);
      expect(VomitColor.black.isMain, isFalse);
      expect(VomitColor.other.isMain, isFalse);
    });

    test('urgent colors are flagged', () {
      expect(VomitColor.red.urgency, VomitUrgency.urgent);
      expect(VomitColor.black.urgency, VomitUrgency.urgent);
    });

    test('caution colors are flagged', () {
      expect(VomitColor.yellow.urgency, VomitUrgency.caution);
      expect(VomitColor.green.urgency, VomitUrgency.caution);
      expect(VomitColor.white_foam.urgency, VomitUrgency.caution);
    });
  });
}
