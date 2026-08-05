// ============================================================================
// petlo - 編集フォームの controller 反映テスト (build 73)
// ============================================================================
//
// 不具合: アプリ再起動後の初回だけ、編集画面の入力欄が空になる。
//
// 原因は _syncControllers の判定が `s.isEditing`
// (= State の editingXxxId != null) を見ていたこと。
// 編集モードでも **ロード前の初期 State では false** になるため
// 「新規作成」と誤判定して _initialSynced を立ててしまい、
// 後からデータが届いても controller へ反映されなかった。
//
// Notifier は autoDispose ではないのでプロセス内で生存する。
// 2 回目以降は最初から埋まった State が来るため正常に見え、
// アプリ再起動で再発する — という再現条件と一致する。
//
// ここでは **controller の中身を直接読む**。画面に文字が見えるかではなく、
// TextEditingController.text に値が入っているかを見ないと検出できない。
//
// ============================================================================

@Tags(<String>['needs_codegen'])
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:petlo/core/preferences/user_preferences.dart';
import 'package:petlo/core/utils/logger.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/data/local/database_enums.dart';
import 'package:petlo/data/repositories/diaries_repository.dart';
import 'package:petlo/data/repositories/prevention_courses_repository.dart';
import 'package:petlo/data/repositories/vaccinations_repository.dart';
import 'package:petlo/data/repositories/visits_repository.dart';
import 'package:petlo/presentation/providers/database_provider.dart';
import 'package:petlo/presentation/screens/diary/diary_record_screen.dart';
import 'package:petlo/presentation/screens/prevention/prevention_course_form_screen.dart';
import 'package:petlo/presentation/screens/vaccination/vaccination_record_screen.dart';
import 'package:petlo/presentation/screens/visit/visit_record_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/test_app.dart';

const String kMarker = 'テスト333';

void main() {
  late AppDatabase db;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await PetloLogger.initialize();
    await UserPreferences.instance.initialize();
    initializeDateFormatting();
  });

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final int t = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.customStatement(
      'INSERT INTO pets (name, type, group_id, sync_status, created_at, '
      'updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      <Object?>['ぽち', 'dog', 'personal', 'synced', t, t],
    );
    await db.customStatement(
      'INSERT INTO pet_scopes (pet_id, group_id, permission, is_primary, '
      'shared_at, sync_status, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[1, 'personal', 'owner', 1, t, 'synced', t, t],
    );
  });

  tearDown(() async {
    await db.close();
  });

  /// 画面を開いて controller の中身を返す。
  /// **同一プロセスで初めて開く** = Notifier が新規作成される状況を再現する。
  Future<List<String>> openAndReadControllers(
    WidgetTester tester,
    Widget screen,
  ) async {
    await tester.pumpWidget(wrapWithApp(
      locale: const Locale('ja'),
      overrides: <Override>[appDatabaseProvider.overrideWithValue(db)],
      child: screen,
    ));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final List<String> texts = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((TextField f) => f.controller?.text ?? '')
        .toList();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    return texts;
  }

  testWidgets('★ワクチン: 初回でも controller に値が入る',
      (WidgetTester tester) async {
    final int id = await VaccinationsRepository(db).create(
      groupId: 'personal',
      petId: 1,
      kind: kMarker,
      administeredAtMsec: DateTime(2026, 8, 4).millisecondsSinceEpoch,
      nextDueAtMsec: DateTime(2026, 8, 21).millisecondsSinceEpoch,
      clinicName: kMarker,
      notes: kMarker,
    );

    final List<String> texts = await openAndReadControllers(
        tester, VaccinationRecordScreen(editingVaccinationId: id));

    expect(texts.where((String s) => s == kMarker).length, 3,
        reason: '種類・病院名・メモの 3 欄すべてに入るべき: $texts');
  });

  testWidgets('★通院: 初回でも controller に値が入る',
      (WidgetTester tester) async {
    final int id = await VisitsRepository(db).create(
      groupId: 'personal',
      petId: 1,
      visitedAtMsec: DateTime(2026, 8, 4).millisecondsSinceEpoch,
      reason: kMarker,
      clinicName: kMarker,
      vetName: kMarker,
      notes: kMarker,
    );

    final List<String> texts = await openAndReadControllers(
        tester, VisitRecordScreen(editingVisitId: id));

    expect(texts.where((String s) => s == kMarker).length,
        greaterThanOrEqualTo(4),
        reason: '理由・病院・獣医・メモが入るべき: $texts');
  });

  testWidgets('★日記: 初回でも controller に値が入る',
      (WidgetTester tester) async {
    final int id = await DiariesRepository(db).create(
      groupId: 'personal',
      petId: 1,
      eventAtMsec: DateTime(2026, 8, 4).millisecondsSinceEpoch,
      title: kMarker,
      body: kMarker,
    );

    final List<String> texts = await openAndReadControllers(
        tester, DiaryRecordScreen(editingDiaryId: id));

    expect(texts.where((String s) => s == kMarker).length, greaterThanOrEqualTo(2),
        reason: 'タイトル・本文が入るべき: $texts');
  });

  testWidgets('★予防コース: 初回でも controller に値が入る',
      (WidgetTester tester) async {
    final int id = await PreventionCoursesRepository(db).create(
      groupId: 'personal',
      petId: 1,
      kind: PreventionKind.filaria,
      year: 2026,
      startMonth: 5,
      endMonth: 12,
      dayOfMonth: 10,
      medicineName: kMarker,
      dosage: kMarker,
    );

    final List<String> texts = await openAndReadControllers(
        tester, PreventionCourseFormScreen(editingCourseId: id));

    expect(texts.where((String s) => s == kMarker).length, 2,
        reason: '薬剤名・用量が入るべき: $texts');
  });

  testWidgets('新規作成モードでは空のまま (誤検出しないこと)',
      (WidgetTester tester) async {
    final List<String> texts =
        await openAndReadControllers(tester, const VaccinationRecordScreen());
    expect(texts.every((String s) => s.isEmpty), isTrue,
        reason: '新規作成で値が入ってはいけない: $texts');
  });
}
