// ============================================================================
// petlo - Prevention Repositories Tests (build 72)
// ============================================================================
//
// 重点は §13 の回帰項目:
//   #9  コース期間の短縮で、範囲外になった **投与済み** dose が消えないこと
//   #10 投与記録の取り消しで medications の該当行が論理削除されること
//
// ============================================================================

@Tags(<String>['needs_codegen'])
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/data/local/database_enums.dart';
import 'package:petlo/core/utils/logger.dart';
import 'package:petlo/data/repositories/pets_repository.dart';
import 'package:petlo/data/repositories/prevention_courses_repository.dart';
import 'package:petlo/data/repositories/prevention_doses_repository.dart';

void main() {
  group('PreventionCoursesRepository', () {
    late AppDatabase db;
    late PreventionCoursesRepository courses;
    late PreventionDosesRepository doses;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      courses = PreventionCoursesRepository(db);
      doses = PreventionDosesRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> createKantoCourse({
      int startMonth = 5,
      int endMonth = 12,
      int dayOfMonth = 10,
      PreventionForm form = PreventionForm.chewable,
      String groupId = 'personal',
    }) {
      return courses.create(
        groupId: groupId,
        petId: 1,
        kind: PreventionKind.filaria,
        year: 2026,
        startMonth: startMonth,
        endMonth: endMonth,
        dayOfMonth: dayOfMonth,
        medicineName: 'ネクスガードスペクトラ',
        region: PreventionRegion.kanto,
        form: form,
      );
    }

    group('plannedMonths', () {
      test('同年内は startMonth..endMonth を並べる', () {
        final List<PreventionPlannedMonth> p =
            PreventionCoursesRepository.plannedMonths(
          year: 2026,
          startMonth: 5,
          endMonth: 12,
          form: PreventionForm.chewable,
        );
        expect(p.length, 8);
        expect(p.first, (year: 2026, month: 5));
        expect(p.last, (year: 2026, month: 12));
      });

      test('endMonth < startMonth は越年する', () {
        final List<PreventionPlannedMonth> p =
            PreventionCoursesRepository.plannedMonths(
          year: 2026,
          startMonth: 11,
          endMonth: 3,
          form: PreventionForm.chewable,
        );
        expect(p.length, 5);
        expect(p.first, (year: 2026, month: 11));
        expect(p[2], (year: 2027, month: 1));
        expect(p.last, (year: 2027, month: 3));
      });

      test('injection は 1 件のみ', () {
        final List<PreventionPlannedMonth> p =
            PreventionCoursesRepository.plannedMonths(
          year: 2026,
          startMonth: 5,
          endMonth: 12,
          form: PreventionForm.injection,
        );
        expect(p.length, 1);
        expect(p.single, (year: 2026, month: 5));
      });
    });

    group('clampDay', () {
      test('存在しない日は月末に丸める', () {
        expect(PreventionCoursesRepository.clampDay(2026, 2, 31), 28);
        expect(PreventionCoursesRepository.clampDay(2024, 2, 31), 29);
        expect(PreventionCoursesRepository.clampDay(2026, 4, 31), 30);
        expect(PreventionCoursesRepository.clampDay(2026, 5, 10), 10);
      });
    });

    group('create', () {
      test('シーズン分の dose を materialize し最終回に isFinal が立つ', () async {
        final int courseId = await createKantoCourse();
        final List<PreventionDoseEntity> list =
            await doses.getForCourse(courseId);

        expect(list.length, 8);
        expect(list.first.seq, 1);
        expect(list.last.seq, 8);
        expect(list.where((PreventionDoseEntity d) => d.isFinal).length, 1);
        expect(list.last.isFinal, isTrue);

        final DateTime first =
            DateTime.fromMillisecondsSinceEpoch(list.first.scheduledDate);
        expect(first.year, 2026);
        expect(first.month, 5);
        expect(first.day, 10);
        // cascade 用の冗長 petId が course と一致していること
        expect(list.every((PreventionDoseEntity d) => d.petId == 1), isTrue);
      });

      test('投与日が月末を超える場合は各月の末日に丸まる', () async {
        final int courseId =
            await createKantoCourse(startMonth: 1, endMonth: 3, dayOfMonth: 31);
        final List<PreventionDoseEntity> list =
            await doses.getForCourse(courseId);
        final List<int> days = list
            .map((PreventionDoseEntity d) =>
                DateTime.fromMillisecondsSinceEpoch(d.scheduledDate).day)
            .toList();
        expect(days, <int>[31, 28, 31]);
      });

      test('personal スコープでは sync_queue に積まない', () async {
        await createKantoCourse();
        final List<SyncQueueItemEntity> q = await db.select(db.syncQueue).get();
        expect(q, isEmpty);
      });

      test('共有スコープでは course / doses が sync_queue に積まれる', () async {
        await createKantoCourse(groupId: 'g-1');
        final List<SyncQueueItemEntity> q = await db.select(db.syncQueue).get();
        expect(
          q.where((SyncQueueItemEntity e) =>
              e.targetTable == 'prevention_courses'),
          hasLength(1),
        );
        expect(
          q.where(
              (SyncQueueItemEntity e) => e.targetTable == 'prevention_doses'),
          hasLength(8),
        );
      });
    });

    group('再 materialize (§13 #9)', () {
      test('期間短縮で範囲外になった投与済み dose は消えない', () async {
        final int courseId = await createKantoCourse(); // 5..12月 = 8 回
        List<PreventionDoseEntity> list = await doses.getForCourse(courseId);

        // 11月・12月分を投与済みにする
        final PreventionDoseEntity nov =
            list.firstWhere((PreventionDoseEntity d) => d.seq == 7);
        final PreventionDoseEntity dec =
            list.firstWhere((PreventionDoseEntity d) => d.seq == 8);
        await doses.recordAdministration(
          doseId: nov.id,
          administeredAtMsec: DateTime(2026, 11, 10).millisecondsSinceEpoch,
        );
        await doses.recordAdministration(
          doseId: dec.id,
          administeredAtMsec: DateTime(2026, 12, 10).millisecondsSinceEpoch,
        );

        // 終了月を 10 月へ短縮
        await courses.update(courseId: courseId, endMonth: 10);

        list = await doses.getForCourse(courseId);
        // 5..10月の 6 件 + 実績が残る 11月・12月の 2 件
        expect(list.length, 8);

        final PreventionDoseEntity? novAfter = await doses.getById(nov.id);
        final PreventionDoseEntity? decAfter = await doses.getById(dec.id);
        expect(novAfter, isNotNull);
        expect(novAfter!.deletedAt, isNull, reason: '投与済み dose は消えてはならない');
        expect(novAfter.administeredAt, isNotNull);
        expect(decAfter!.deletedAt, isNull);
        expect(decAfter.administeredAt, isNotNull);

        // 実績は seq を末尾へ退避し、isFinal は降ろされている
        expect(novAfter.seq, greaterThan(6));
        expect(novAfter.isFinal, isFalse);
        expect(decAfter.isFinal, isFalse);

        // 現行範囲の最終回 (10月) に isFinal が移っている
        final PreventionCourseEntity? course = await courses.getById(courseId);
        final List<PreventionDoseEntity> inRange = list
            .where((PreventionDoseEntity d) =>
                !PreventionCoursesRepository.isOrphanDose(course!, d))
            .toList();
        expect(inRange.length, 6);
        expect(
          inRange.where((PreventionDoseEntity d) => d.isFinal).single.seq,
          6,
        );

        // 範囲外の実績は orphan として判定できる
        expect(
          PreventionCoursesRepository.isOrphanDose(course!, novAfter),
          isTrue,
        );
      });

      test('期間短縮で範囲外になった未投与 dose は論理削除される', () async {
        final int courseId = await createKantoCourse();
        await courses.update(courseId: courseId, endMonth: 10);

        final List<PreventionDoseEntity> alive =
            await doses.getForCourse(courseId);
        expect(alive.length, 6);

        final List<PreventionDoseEntity> all =
            await db.select(db.preventionDoses).get();
        expect(
          all.where((PreventionDoseEntity d) => d.deletedAt != null).length,
          2,
        );
      });

      test('スキップ済み dose も範囲外で消えない', () async {
        final int courseId = await createKantoCourse();
        final List<PreventionDoseEntity> list =
            await doses.getForCourse(courseId);
        final PreventionDoseEntity dec =
            list.firstWhere((PreventionDoseEntity d) => d.seq == 8);
        await doses.setSkipped(dec.id, true);

        await courses.update(courseId: courseId, endMonth: 10);

        final PreventionDoseEntity? after = await doses.getById(dec.id);
        expect(after!.deletedAt, isNull);
        expect(after.skipped, isTrue);
      });

      test('期間を再度広げても行が増殖せず論理削除済みが復活する', () async {
        final int courseId = await createKantoCourse();
        await courses.update(courseId: courseId, endMonth: 10);
        await courses.update(courseId: courseId, endMonth: 12);

        final List<PreventionDoseEntity> alive =
            await doses.getForCourse(courseId);
        expect(alive.length, 8);
        final List<PreventionDoseEntity> all =
            await db.select(db.preventionDoses).get();
        expect(all.length, 8, reason: '行が増殖してはならない');
        expect(alive.last.isFinal, isTrue);
      });

      test('投与日の変更で scheduledDate が更新され実績は保持される', () async {
        final int courseId = await createKantoCourse();
        final List<PreventionDoseEntity> list =
            await doses.getForCourse(courseId);
        final PreventionDoseEntity may = list.first;
        await doses.recordAdministration(
          doseId: may.id,
          administeredAtMsec: DateTime(2026, 5, 14).millisecondsSinceEpoch,
        );

        await courses.update(courseId: courseId, dayOfMonth: 20);

        final PreventionDoseEntity? after = await doses.getById(may.id);
        expect(
          DateTime.fromMillisecondsSinceEpoch(after!.scheduledDate).day,
          20,
        );
        expect(
          DateTime.fromMillisecondsSinceEpoch(after.administeredAt!).day,
          14,
          reason: '実際に投与した日はコース設定変更で動かない',
        );
      });
    });

    group('softDelete', () {
      test('コース削除で dose も論理削除される', () async {
        final int courseId = await createKantoCourse();
        expect(await courses.softDelete(courseId), isTrue);

        expect(await doses.getForCourse(courseId), isEmpty);
        final PreventionCourseEntity? c = await courses.getById(courseId);
        expect(c!.deletedAt, isNotNull);
      });
    });

    group('countActive (無料枠カウント)', () {
      test('created_at 昇順で並び、削除済みは数えない', () async {
        final int first = await createKantoCourse();
        await createKantoCourse(startMonth: 4, endMonth: 11);
        expect(await courses.countActive(), 2);

        await courses.softDelete(first);
        expect(await courses.countActive(), 1);
      });
    });
  });

  group('PreventionDosesRepository', () {
    late AppDatabase db;
    late PreventionCoursesRepository courses;
    late PreventionDosesRepository doses;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      courses = PreventionCoursesRepository(db);
      doses = PreventionDosesRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> newCourse({String groupId = 'personal'}) {
      return courses.create(
        groupId: groupId,
        petId: 7,
        kind: PreventionKind.filaria,
        year: 2026,
        startMonth: 5,
        endMonth: 12,
        dayOfMonth: 10,
        medicineName: 'ネクスガードスペクトラ',
        dosage: '1錠',
      );
    }

    test('投与記録で medications に 1 行 INSERT される', () async {
      final int courseId = await newCourse();
      final PreventionDoseEntity dose =
          (await doses.getForCourse(courseId)).first;

      final int at = DateTime(2026, 5, 10, 9).millisecondsSinceEpoch;
      expect(
        await doses.recordAdministration(doseId: dose.id, administeredAtMsec: at),
        isTrue,
      );

      final List<MedicationEntity> meds =
          await db.select(db.medications).get();
      expect(meds, hasLength(1));
      expect(meds.single.petId, 7);
      expect(meds.single.medicineName, 'ネクスガードスペクトラ');
      expect(meds.single.dosage, '1錠');
      expect(meds.single.administeredAt, at);
      expect(meds.single.reminderId, isNull,
          reason: 'reminderId は schedules 系の参照なので必ず null');

      final PreventionDoseEntity? after = await doses.getById(dose.id);
      expect(after!.administeredAt, at);
      expect(after.medicationId, meds.single.id);
    });

    test('薬剤名が無いコースでは fallback 名を使う', () async {
      final int courseId = await courses.create(
        groupId: 'personal',
        petId: 7,
        kind: PreventionKind.filaria,
        year: 2026,
        startMonth: 5,
        endMonth: 6,
        dayOfMonth: 1,
      );
      final PreventionDoseEntity dose =
          (await doses.getForCourse(courseId)).first;
      await doses.recordAdministration(
        doseId: dose.id,
        administeredAtMsec: DateTime(2026, 5).millisecondsSinceEpoch,
        medicineNameFallback: 'フィラリア予防',
      );
      final List<MedicationEntity> meds =
          await db.select(db.medications).get();
      expect(meds.single.medicineName, 'フィラリア予防');
    });

    test('取り消しで medications 行が論理削除される (§13 #10)', () async {
      final int courseId = await newCourse();
      final PreventionDoseEntity dose =
          (await doses.getForCourse(courseId)).first;
      await doses.recordAdministration(
        doseId: dose.id,
        administeredAtMsec: DateTime(2026, 5, 10).millisecondsSinceEpoch,
      );

      expect(await doses.undoAdministration(dose.id), isTrue);

      final List<MedicationEntity> meds =
          await db.select(db.medications).get();
      expect(meds.single.deletedAt, isNotNull);

      final PreventionDoseEntity? after = await doses.getById(dose.id);
      expect(after!.administeredAt, isNull);
      expect(after.medicationId, isNull);
    });

    test('投与済みの回をスキップすると記録が取り消される', () async {
      final int courseId = await newCourse();
      final PreventionDoseEntity dose =
          (await doses.getForCourse(courseId)).first;
      await doses.recordAdministration(
        doseId: dose.id,
        administeredAtMsec: DateTime(2026, 5, 10).millisecondsSinceEpoch,
      );

      expect(await doses.setSkipped(dose.id, true), isTrue);

      final PreventionDoseEntity? after = await doses.getById(dose.id);
      expect(after!.skipped, isTrue);
      expect(after.administeredAt, isNull);
      final List<MedicationEntity> meds =
          await db.select(db.medications).get();
      expect(meds.single.deletedAt, isNotNull);
    });

    test('共有スコープでは medications / doses の op が積まれる (§13 #11)', () async {
      final int courseId = await newCourse(groupId: 'g-1');
      final PreventionDoseEntity dose =
          (await doses.getForCourse(courseId)).first;
      await doses.recordAdministration(
        doseId: dose.id,
        administeredAtMsec: DateTime(2026, 5, 10).millisecondsSinceEpoch,
      );

      final List<SyncQueueItemEntity> q = await db.select(db.syncQueue).get();
      expect(
        q.where((SyncQueueItemEntity e) =>
            e.targetTable == 'medications' &&
            e.operation == SyncOperation.insert),
        hasLength(1),
      );
      expect(
        q.where((SyncQueueItemEntity e) => e.targetTable == 'prevention_doses'),
        isNotEmpty,
      );
    });

    group('§6.3 BaseRepository 経由の検証 (v2 P3)', () {
      test('#1 INSERT は buildCreateMetadata 相当のメタで埋まる', () async {
        final int courseId = await newCourse();
        final PreventionDoseEntity dose =
            (await doses.getForCourse(courseId)).first;
        final int before = DateTime.now().toUtc().millisecondsSinceEpoch;
        await doses.recordAdministration(
          doseId: dose.id,
          administeredAtMsec: DateTime(2026, 5, 10).millisecondsSinceEpoch,
        );
        final int after = DateTime.now().toUtc().millisecondsSinceEpoch;

        final MedicationEntity m = (await db.select(db.medications).get()).single;
        expect(m.createdAt, inInclusiveRange(before, after));
        expect(m.updatedAt, inInclusiveRange(before, after));
        expect(m.lastModifiedAtClient, inInclusiveRange(before, after));
        expect(m.deletedAt, isNull);
        // personal スコープは同期不要なので initialSyncStatus = synced
        expect(m.syncStatus, SyncStatus.synced);
      });

      test('#1 共有スコープの INSERT は pending で入る', () async {
        final int courseId = await newCourse(groupId: 'g-1');
        final PreventionDoseEntity dose =
            (await doses.getForCourse(courseId)).first;
        await doses.recordAdministration(
          doseId: dose.id,
          administeredAtMsec: DateTime(2026, 5, 10).millisecondsSinceEpoch,
        );
        final MedicationEntity m = (await db.select(db.medications).get()).single;
        expect(m.syncStatus, SyncStatus.pending);
      });

      test('#3 取消の論理削除は buildDeleteMetadata 相当のメタで埋まる', () async {
        final int courseId = await newCourse();
        final PreventionDoseEntity dose =
            (await doses.getForCourse(courseId)).first;
        await doses.recordAdministration(
          doseId: dose.id,
          administeredAtMsec: DateTime(2026, 5, 10).millisecondsSinceEpoch,
        );
        final int before = DateTime.now().toUtc().millisecondsSinceEpoch;
        await doses.undoAdministration(dose.id);
        final int after = DateTime.now().toUtc().millisecondsSinceEpoch;

        final MedicationEntity m = (await db.select(db.medications).get()).single;
        expect(m.deletedAt, isNotNull);
        expect(m.deletedAt, inInclusiveRange(before, after));
        // buildDeleteMetadata は deletedAt と updatedAt を同一時刻で埋める
        expect(m.updatedAt, m.deletedAt);
        expect(m.lastModifiedAtClient, m.deletedAt);
      });

      test('#6 groupId はコースを引き継ぐ (personal 決め打ちでない)', () async {
        final int courseId = await newCourse(groupId: 'g-42');
        final PreventionDoseEntity dose =
            (await doses.getForCourse(courseId)).first;
        await doses.recordAdministration(
          doseId: dose.id,
          administeredAtMsec: DateTime(2026, 5, 10).millisecondsSinceEpoch,
        );
        final MedicationEntity m = (await db.select(db.medications).get()).single;
        expect(m.groupId, 'g-42');
      });
    });

    group('statusOf', () {
      PreventionDoseEntity make({
        int? administeredAt,
        bool skipped = false,
        required DateTime scheduled,
      }) {
        return PreventionDoseEntity(
          id: 1,
          groupId: 'personal',
          courseId: 1,
          petId: 1,
          seq: 1,
          scheduledDate: scheduled.millisecondsSinceEpoch,
          administeredAt: administeredAt,
          skipped: skipped,
          isFinal: false,
          syncStatus: SyncStatus.synced,
          createdAt: 0,
          updatedAt: 0,
        );
      }

      final int today = DateTime(2026, 8, 10, 15).millisecondsSinceEpoch;

      test('投与済み / スキップが最優先', () {
        expect(
          PreventionDosesRepository.statusOf(
            make(scheduled: DateTime(2026, 8, 10), administeredAt: 1),
            nowMsec: today,
          ),
          PreventionDoseStatus.administered,
        );
        expect(
          PreventionDosesRepository.statusOf(
            make(scheduled: DateTime(2026, 8, 10), skipped: true),
            nowMsec: today,
          ),
          PreventionDoseStatus.skipped,
        );
      });

      test('今日 / 過去 / 未来を判定する', () {
        expect(
          PreventionDosesRepository.statusOf(
            make(scheduled: DateTime(2026, 8, 10)),
            nowMsec: today,
          ),
          PreventionDoseStatus.due,
        );
        expect(
          PreventionDosesRepository.statusOf(
            make(scheduled: DateTime(2026, 7, 10)),
            nowMsec: today,
          ),
          PreventionDoseStatus.overdue,
        );
        expect(
          PreventionDosesRepository.statusOf(
            make(scheduled: DateTime(2026, 9, 10)),
            nowMsec: today,
          ),
          PreventionDoseStatus.upcoming,
        );
      });
    });
  });

  _petCascadeTests();
  _yearChangeTests();
  _createdAtAuditTests();
  _fallbackExclusionTests();
}

// ============================================================================
// §13 #5 / #6: ペット削除・お別れとの連動
// ============================================================================

void _petCascadeTests() {
  group('PetsRepository cascade (§13 #5 / #6)', () {
    late AppDatabase db;
    late PetsRepository pets;
    late PreventionCoursesRepository courses;
    late PreventionDosesRepository doses;

    // createPet の診断ログが PetloLogger.instance を触るため先に初期化する。
    setUpAll(() async {
      await PetloLogger.initialize();
    });

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      pets = PetsRepository(db);
      courses = PreventionCoursesRepository(db);
      doses = PreventionDosesRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<({int petId, int courseId})> seed() async {
      final int petId = await pets.createPet(
        groupId: 'personal',
        name: 'ぽち',
        type: PetType.dog,
      );
      final int courseId = await courses.create(
        groupId: 'personal',
        petId: petId,
        kind: PreventionKind.filaria,
        year: 2026,
        startMonth: 5,
        endMonth: 12,
        dayOfMonth: 10,
      );
      return (petId: petId, courseId: courseId);
    }

    test('#5 ペット論理削除で予防コースと dose も論理削除される', () async {
      final ({int petId, int courseId}) s = await seed();
      expect(await doses.getForCourse(s.courseId), hasLength(8));

      expect(await pets.softDeletePet(s.petId), isTrue);

      final PreventionCourseEntity? course = await courses.getById(s.courseId);
      expect(course!.deletedAt, isNotNull);
      expect(await doses.getForCourse(s.courseId), isEmpty);
    });

    test('#6 お別れ (markAsParted) では予防データは消えない', () async {
      final ({int petId, int courseId}) s = await seed();

      expect(
        await pets.markAsParted(
          petId: s.petId,
          partedAtMsec: DateTime.now()
              .subtract(const Duration(days: 1))
              .millisecondsSinceEpoch,
        ),
        isTrue,
      );

      final PreventionCourseEntity? course = await courses.getById(s.courseId);
      expect(course!.deletedAt, isNull, reason: '記録は宝物。消してはならない');
      expect(await doses.getForCourse(s.courseId), hasLength(8));
    });
  });
}

// ============================================================================
// §13 #17: 実績 0 件コースの年変更 (v2 P4)
// ============================================================================

void _yearChangeTests() {
  group('年の変更 (§8.4 / §13 #17)', () {
    late AppDatabase db;
    late PreventionCoursesRepository courses;
    late PreventionDosesRepository doses;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      courses = PreventionCoursesRepository(db);
      doses = PreventionDosesRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> newCourse({int year = 2026}) {
      return courses.create(
        groupId: 'personal',
        petId: 1,
        kind: PreventionKind.filaria,
        year: year,
        startMonth: 5,
        endMonth: 12,
        dayOfMonth: 10,
      );
    }

    test('#17 実績 0 件なら全 dose が単純 UPDATE され行が増えない', () async {
      final int courseId = await newCourse();
      final List<PreventionDoseEntity> before =
          await doses.getForCourse(courseId);
      expect(before, hasLength(8));
      final Set<int> beforeIds =
          before.map((PreventionDoseEntity d) => d.id).toSet();

      await courses.update(courseId: courseId, year: 2025);

      final List<PreventionDoseEntity> after =
          await doses.getForCourse(courseId);
      expect(after, hasLength(8));
      expect(
        after.map((PreventionDoseEntity d) => d.id).toSet(),
        beforeIds,
        reason: '同じ行が UPDATE されるだけ。INSERT / 論理削除は起きない',
      );

      // 全 dose の年が 2025 に移り、月と seq は保たれる
      for (final PreventionDoseEntity d in after) {
        expect(
          DateTime.fromMillisecondsSinceEpoch(d.scheduledDate).year,
          2025,
        );
      }
      expect(
        after.map((PreventionDoseEntity d) => d.seq).toList(),
        <int>[1, 2, 3, 4, 5, 6, 7, 8],
      );

      // 行が増殖していない (論理削除された行も無い)
      final List<PreventionDoseEntity> all =
          await db.select(db.preventionDoses).get();
      expect(all, hasLength(8));
    });

    test('#17 年変更後に「コース外の記録」が発生しない', () async {
      final int courseId = await newCourse();
      await courses.update(courseId: courseId, year: 2025);

      final PreventionCourseEntity course = (await courses.getById(courseId))!;
      final List<PreventionDoseEntity> after =
          await doses.getForCourse(courseId);
      for (final PreventionDoseEntity d in after) {
        expect(
          PreventionCoursesRepository.isOrphanDose(course, d),
          isFalse,
          reason: '実績 0 件なので §4.3 ケース (c) は発生しない',
        );
      }
    });

    test('実績があるコースで年を変えると実績は退避されて残る (ロックの根拠)', () async {
      // UI ではロックして到達させないが、データ層の挙動を明示しておく。
      final int courseId = await newCourse();
      final PreventionDoseEntity may =
          (await doses.getForCourse(courseId)).first;
      await doses.recordAdministration(
        doseId: may.id,
        administeredAtMsec: DateTime(2026, 5, 10).millisecondsSinceEpoch,
      );

      await courses.update(courseId: courseId, year: 2025);

      final PreventionDoseEntity? after = await doses.getById(may.id);
      expect(after!.deletedAt, isNull, reason: '実績は消えない');
      expect(after.administeredAt, isNotNull);

      final PreventionCourseEntity course = (await courses.getById(courseId))!;
      expect(
        PreventionCoursesRepository.isOrphanDose(course, after),
        isTrue,
        reason: 'コース外の記録に退避される。だから UI では年をロックする',
      );
    });
  });
}

// ============================================================================
// createdAt 監査 (build 73)
// ============================================================================
//
// なぜ重要か: §7.1 の無料枠判定は created_at 昇順の先着 1 件。
// UPDATE で createdAt が動くと「コース A を編集したら無料枠が B に移る」
// というペイウォール回避経路になる。悪意なしで踏める。
//
void _createdAtAuditTests() {
  group('createdAt 監査 (build 73)', () {
    late AppDatabase db;
    late PreventionCoursesRepository courses;
    late PreventionDosesRepository doses;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      courses = PreventionCoursesRepository(db);
      doses = PreventionDosesRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> newCourse({
      String groupId = 'personal',
      int endMonth = 12,
      int petId = 1,
    }) {
      return courses.create(
        groupId: groupId,
        petId: petId,
        kind: PreventionKind.filaria,
        year: 2026,
        startMonth: 5,
        endMonth: endMonth,
        dayOfMonth: 10,
        medicineName: 'ネクスガードスペクトラ',
      );
    }

    test('prevention_courses の INSERT は createdAt に実 INSERT 時刻が入る', () async {
      final int before = DateTime.now().toUtc().millisecondsSinceEpoch;
      final int id = await newCourse();
      final int after = DateTime.now().toUtc().millisecondsSinceEpoch;

      final PreventionCourseEntity c = (await courses.getById(id))!;
      expect(c.createdAt, inInclusiveRange(before, after));
      expect(c.updatedAt, inInclusiveRange(before, after));
      expect(c.lastModifiedAtClient, inInclusiveRange(before, after));
    });

    test('prevention_doses の INSERT は createdAt に実 INSERT 時刻が入る', () async {
      final int before = DateTime.now().toUtc().millisecondsSinceEpoch;
      final int id = await newCourse();
      final int after = DateTime.now().toUtc().millisecondsSinceEpoch;

      for (final PreventionDoseEntity d in await doses.getForCourse(id)) {
        expect(d.createdAt, inInclusiveRange(before, after));
        expect(d.updatedAt, inInclusiveRange(before, after));
      }
    });

    test('★コースの UPDATE は createdAt を書き換えない (無料枠の順序を守る)', () async {
      final int id = await newCourse();
      final int original = (await courses.getById(id))!.createdAt;

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await courses.update(courseId: id, endMonth: 10, medicineName: '別の薬');

      final PreventionCourseEntity after = (await courses.getById(id))!;
      expect(after.createdAt, original, reason: 'createdAt は不変でなければならない');
      expect(after.updatedAt, greaterThan(original));
    });

    test('★編集しても無料枠の先着順が入れ替わらない', () async {
      final int first = await newCourse();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final int second = await newCourse(petId: 2);

      List<PreventionCourseEntity> ordered =
          await courses.getAllActiveByCreation();
      expect(ordered.first.id, first);

      // 先に作ったコースを何度も編集する
      for (int i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await courses.update(courseId: first, dayOfMonth: 10 + i);
      }

      ordered = await courses.getAllActiveByCreation();
      expect(
        ordered.first.id,
        first,
        reason: '編集で無料枠が 2 件目に移ってはならない (ペイウォール回避経路)',
      );
      expect(ordered.last.id, second);
    });

    test('再 materialize は既存 dose の createdAt を書き換えない', () async {
      final int id = await newCourse();
      final Map<int, int> before = <int, int>{
        for (final PreventionDoseEntity d in await doses.getForCourse(id))
          d.id: d.createdAt,
      };

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await courses.update(courseId: id, dayOfMonth: 20);

      for (final PreventionDoseEntity d in await doses.getForCourse(id)) {
        expect(d.createdAt, before[d.id],
            reason: 'dose の生成時刻も UPDATE で動いてはならない');
        expect(d.updatedAt, greaterThan(d.createdAt));
      }
    });

    test('materialize の INSERT は create メタ、UPDATE は update メタを使う', () async {
      // 期間を広げると新しい月だけ INSERT される
      final int id = await newCourse(endMonth: 10);
      final List<PreventionDoseEntity> firstBatch = await doses.getForCourse(id);
      final Set<int> firstIds =
          firstBatch.map((PreventionDoseEntity d) => d.id).toSet();

      await Future<void>.delayed(const Duration(milliseconds: 5));
      final int mark = DateTime.now().toUtc().millisecondsSinceEpoch;
      await courses.update(courseId: id, endMonth: 12);

      for (final PreventionDoseEntity d in await doses.getForCourse(id)) {
        if (firstIds.contains(d.id)) {
          expect(d.createdAt, lessThan(mark), reason: '既存行の createdAt は不変');
        } else {
          expect(d.createdAt, greaterThanOrEqualTo(mark),
              reason: '新規行の createdAt は INSERT 時刻');
        }
      }
    });

    test('medications の createdAt は実 INSERT 時刻 (§6.3 #1 の回帰)', () async {
      final int id = await newCourse();
      final PreventionDoseEntity dose = (await doses.getForCourse(id)).first;

      final int before = DateTime.now().toUtc().millisecondsSinceEpoch;
      await doses.recordAdministration(
        doseId: dose.id,
        // 投与日は過去。createdAt と混同していないことを確かめる
        administeredAtMsec: DateTime(2026, 5, 10).millisecondsSinceEpoch,
      );
      final int after = DateTime.now().toUtc().millisecondsSinceEpoch;

      final MedicationEntity m = (await db.select(db.medications).get()).single;
      expect(m.createdAt, inInclusiveRange(before, after));
      expect(
        m.createdAt,
        isNot(m.administeredAt),
        reason: 'createdAt は行の生成時刻であって投与日時ではない',
      );
    });

    test('投与の取り消しは medications の createdAt を書き換えない', () async {
      final int id = await newCourse();
      final PreventionDoseEntity dose = (await doses.getForCourse(id)).first;
      await doses.recordAdministration(
        doseId: dose.id,
        administeredAtMsec: DateTime(2026, 5, 10).millisecondsSinceEpoch,
      );
      final int original =
          (await db.select(db.medications).get()).single.createdAt;

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await doses.undoAdministration(dose.id);

      final MedicationEntity m = (await db.select(db.medications).get()).single;
      expect(m.createdAt, original);
      expect(m.deletedAt, greaterThan(original));
    });
  });
}

// ============================================================================
// materialize フォールバックの除外条件 (build 73)
// ============================================================================

void _fallbackExclusionTests() {
  group('materialize フォールバックの除外条件', () {
    late AppDatabase db;
    late PreventionCoursesRepository courses;
    late PreventionDosesRepository doses;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      courses = PreventionCoursesRepository(db);
      doses = PreventionDosesRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> newCourse({int year = 2026}) {
      return courses.create(
        groupId: 'personal',
        petId: 1,
        kind: PreventionKind.filaria,
        year: year,
        startMonth: 5,
        endMonth: 12,
        dayOfMonth: 10,
      );
    }

    test('★メモ付きの未投与 dose はフォールバックで流用されない', () async {
      final int id = await newCourse();
      final List<PreventionDoseEntity> before = await doses.getForCourse(id);
      // 7 月分 (seq=3) にメモを書く
      final PreventionDoseEntity july =
          before.firstWhere((PreventionDoseEntity d) => d.seq == 3);
      await doses.updateNotes(july.id, '動物病院で受け取る予定');

      final int julyScheduled = july.scheduledDate;

      // 年をずらす → キー一致ゼロ。フォールバックが走る。
      await courses.update(courseId: id, year: 2025);

      final PreventionDoseEntity? after = await doses.getById(july.id);
      expect(after, isNotNull);
      expect(after!.notes, '動物病院で受け取る予定');
      expect(
        after.scheduledDate,
        julyScheduled,
        reason: 'メモを置いた行の予定日が黙って別の月へ動いてはならない',
      );
      expect(
        DateTime.fromMillisecondsSinceEpoch(after.scheduledDate).year,
        2026,
        reason: 'コース外の記録として元の年に残る',
      );

      // コース外として扱われる
      final PreventionCourseEntity course = (await courses.getById(id))!;
      expect(PreventionCoursesRepository.isOrphanDose(course, after), isTrue);
    });

    test('メモがある分だけ新しい行が INSERT される', () async {
      final int id = await newCourse();
      final PreventionDoseEntity july =
          (await doses.getForCourse(id)).firstWhere(
        (PreventionDoseEntity d) => d.seq == 3,
      );
      await doses.updateNotes(july.id, 'メモ');

      await courses.update(courseId: id, year: 2025);

      final List<PreventionDoseEntity> alive = await doses.getForCourse(id);
      // 2025 年の 8 枠 + メモ付きで退避した 1 件
      expect(alive, hasLength(9));
      final List<PreventionDoseEntity> inRange = alive.where(
        (PreventionDoseEntity d) =>
            DateTime.fromMillisecondsSinceEpoch(d.scheduledDate).year == 2025,
      ).toList();
      expect(inRange, hasLength(8));
    });

    test('空白のみのメモは流用を妨げない', () async {
      final int id = await newCourse();
      final PreventionDoseEntity july =
          (await doses.getForCourse(id)).firstWhere(
        (PreventionDoseEntity d) => d.seq == 3,
      );
      // updateNotes は空白を null に正規化する
      await doses.updateNotes(july.id, '   ');

      await courses.update(courseId: id, year: 2025);

      final List<PreventionDoseEntity> alive = await doses.getForCourse(id);
      expect(alive, hasLength(8), reason: '空メモは「空の行」なので流用してよい');
    });

    test('メモなし・未投与の dose はこれまで通り流用される', () async {
      final int id = await newCourse();
      final Set<int> before = (await doses.getForCourse(id))
          .map((PreventionDoseEntity d) => d.id)
          .toSet();

      await courses.update(courseId: id, year: 2025);

      final Set<int> after = (await doses.getForCourse(id))
          .map((PreventionDoseEntity d) => d.id)
          .toSet();
      expect(after, before, reason: '空の行は行 ID を保ったまま UPDATE される');
    });
  });
}
