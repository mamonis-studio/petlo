// ============================================================================
// petlo - PreventionSlotPlanner Tests (build 73 / v2 §5.4)
// ============================================================================
//
// §5.4「配分の検算」の 3 ケースと、§13 の v2 追加項目 #13 / #14 / #15 を固定する。
//
// 配分ロジックは純粋関数なのでプラットフォーム呼び出しなしで検算できる。
//
// ============================================================================

@Tags(<String>['needs_codegen'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/core/prevention/prevention_notification_scheduler.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/data/local/database_enums.dart';
import 'package:petlo/data/repositories/prevention_courses_repository.dart';

void main() {
  // 「今」を 2026-01-15 に固定する。2026 年シーズンは丸ごと未来になる。
  final DateTime now = DateTime(2026, 1, 15, 10);

  // §5.4 のラダー自体を検算するテストなので、バジェットは明示的に固定する。
  // AppConstants.enablePrevention (キルスイッチ) の値に左右されないため。
  // フラグと実バジェットの整合は prevention_kill_switch_test.dart が見る。
  const int budget = 12;
  const int testReserve = 4;

  PreventionCourseEntity course({
    required int id,
    int petId = 1,
    PreventionKind kind = PreventionKind.filaria,
    int year = 2026,
    int startMonth = 5,
    int endMonth = 12,
    int dayOfMonth = 10,
    String notifyTime = '09:00',
    int? testedAt,
    bool testReminderEnabled = true,
    bool notificationEnabled = true,
    PreventionForm form = PreventionForm.chewable,
  }) {
    return PreventionCourseEntity(
      id: id,
      groupId: 'personal',
      petId: petId,
      kind: kind,
      year: year,
      startMonth: startMonth,
      endMonth: endMonth,
      dayOfMonth: dayOfMonth,
      notifyTime: notifyTime,
      form: form,
      region: PreventionRegion.kanto,
      testedAt: testedAt,
      testReminderEnabled: testReminderEnabled,
      notificationEnabled: notificationEnabled,
      syncStatus: SyncStatus.synced,
      createdAt: 0,
      updatedAt: 0,
    );
  }

  /// コースの計画月から dose 群を組み立てる (materialize と同じ規則)。
  List<PreventionDoseEntity> dosesFor(
    PreventionCourseEntity c, {
    int idBase = 0,
    int administeredCount = 0,
  }) {
    final List<PreventionPlannedMonth> months =
        PreventionCoursesRepository.plannedMonthsOf(c);
    return <PreventionDoseEntity>[
      for (int i = 0; i < months.length; i++)
        PreventionDoseEntity(
          id: idBase + i + 1,
          groupId: 'personal',
          courseId: c.id,
          petId: c.petId,
          seq: i + 1,
          scheduledDate: PreventionCoursesRepository.scheduledDateFor(
            months[i].year,
            months[i].month,
            c.dayOfMonth,
          ),
          administeredAt: i < administeredCount ? 1 : null,
          skipped: false,
          isFinal: i == months.length - 1,
          syncStatus: SyncStatus.synced,
          createdAt: 0,
          updatedAt: 0,
        ),
    ];
  }

  List<PreventionNotificationSlot> planFor(
    List<PreventionCoursePlanInput> inputs, {
    required bool isPro,
  }) {
    return PreventionSlotPlanner.plan(
      inputs: inputs,
      now: now,
      isPro: isPro,
      budget: budget,
      testReserve: testReserve,
    );
  }

  int countOf(
    List<PreventionNotificationSlot> slots,
    Set<PreventionSlotKind> kinds,
  ) {
    return slots
        .where((PreventionNotificationSlot s) => kinds.contains(s.kind))
        .length;
  }

  const Set<PreventionSlotKind> testTier = <PreventionSlotKind>{
    PreventionSlotKind.testReminder30,
    PreventionSlotKind.testReminder7,
  };

  group('§5.4 配分の検算', () {
    test('無料・1 コース (未検査) → 検査 2 + dose 8 = 10 slot', () {
      final PreventionCourseEntity c = course(id: 1);
      final List<PreventionNotificationSlot> slots = planFor(
        <PreventionCoursePlanInput>[(course: c, doses: dosesFor(c))],
        isPro: false,
      );

      expect(countOf(slots, testTier), 2);
      expect(
        countOf(slots, <PreventionSlotKind>{PreventionSlotKind.doseDue}),
        8,
        reason: 'シーズン全 8 回が予約される。アプリを開かなくても切れない',
      );
      expect(slots.length, 10);
      expect(slots.length, lessThanOrEqualTo(budget));
      // 無料プランに Pro 限定 slot は積まれない
      expect(
        countOf(slots, <PreventionSlotKind>{
          PreventionSlotKind.doseFollowUp,
          PreventionSlotKind.doseFinal,
          PreventionSlotKind.nextSeason,
        }),
        0,
      );
    });

    test('無料・1 コース (検査済み) → dose 8 = 8 slot', () {
      final PreventionCourseEntity c = course(
        id: 1,
        testedAt: DateTime(2026, 4, 28).millisecondsSinceEpoch,
      );
      final List<PreventionNotificationSlot> slots = planFor(
        <PreventionCoursePlanInput>[(course: c, doses: dosesFor(c))],
        isPro: false,
      );

      expect(countOf(slots, testTier), 0);
      expect(
        countOf(slots, <PreventionSlotKind>{PreventionSlotKind.doseDue}),
        8,
      );
      expect(slots.length, 8);
    });

    test('Pro・2 ペット × 2 種 = 4 コース → 検査 4 + dose 8 = 12 slot', () {
      final List<PreventionCoursePlanInput> inputs =
          <PreventionCoursePlanInput>[];
      int idBase = 0;
      for (int pet = 1; pet <= 2; pet++) {
        for (final PreventionKind k in <PreventionKind>[
          PreventionKind.filaria,
          PreventionKind.flea_tick,
        ]) {
          final PreventionCourseEntity c = course(
            id: inputs.length + 1,
            petId: pet,
            kind: k,
          );
          inputs.add((course: c, doses: dosesFor(c, idBase: idBase)));
          idBase += 100;
        }
      }

      final List<PreventionNotificationSlot> slots =
          planFor(inputs, isPro: true);

      // ノミダニ単独は検査対象外なので、検査候補はフィラリア 2 コース × 2 = 4
      expect(countOf(slots, testTier), 4);
      expect(
        countOf(slots, <PreventionSlotKind>{PreventionSlotKind.doseDue}),
        8,
      );
      expect(slots.length, budget);
    });
  });

  group('§13 v2 追加項目', () {
    test('#13 無料・1 コース・未検査でシーズン全回が予約される', () {
      final PreventionCourseEntity c = course(id: 1);
      final List<PreventionNotificationSlot> slots = planFor(
        <PreventionCoursePlanInput>[(course: c, doses: dosesFor(c))],
        isPro: false,
      );
      final List<PreventionNotificationSlot> due = slots
          .where((PreventionNotificationSlot s) =>
              s.kind == PreventionSlotKind.doseDue)
          .toList();
      expect(due, hasLength(8));
      // 5 月から 12 月まで途切れなく並ぶ
      expect(
        due.map((PreventionNotificationSlot s) => s.fireAt.month).toList(),
        <int>[5, 6, 7, 8, 9, 10, 11, 12],
      );
    });

    test('#14 Pro・4 コースでも検査リマインドが dose に押し出されない', () {
      // dose を大量に積める状況 (通年 12 回 × 4 コース) を作る
      final List<PreventionCoursePlanInput> inputs =
          <PreventionCoursePlanInput>[];
      int idBase = 0;
      for (int i = 1; i <= 4; i++) {
        final PreventionCourseEntity c = course(
          id: i,
          petId: i,
          startMonth: 2,
          endMonth: 12, // 11 回
        );
        inputs.add((course: c, doses: dosesFor(c, idBase: idBase)));
        idBase += 100;
      }

      final List<PreventionNotificationSlot> slots =
          planFor(inputs, isPro: true);

      expect(
        countOf(slots, testTier),
        testReserve,
        reason: '検査リマインドは予約枠 4 を必ず確保する',
      );
      expect(slots.length, budget);

      // 予約が効かなければ dose が 12 slot 全部を奪っていたはず
      expect(
        countOf(slots, <PreventionSlotKind>{PreventionSlotKind.doseDue}),
        budget - testReserve,
      );
    });

    test('#15 過去年のコースには通知が 1 件もスケジュールされない', () {
      // 2026-01-15 時点で 2024 年シーズンは全て過去
      final PreventionCourseEntity c = course(id: 1, year: 2024);
      final List<PreventionNotificationSlot> slots = planFor(
        <PreventionCoursePlanInput>[(course: c, doses: dosesFor(c))],
        isPro: true,
      );
      expect(slots, isEmpty, reason: '遡り入力が通知バジェットを消費してはならない');
    });
  });

  group('その他の配分ルール', () {
    test('投与済み・スキップ済みの dose は積まない', () {
      final PreventionCourseEntity c = course(id: 1);
      final List<PreventionDoseEntity> doses =
          dosesFor(c, administeredCount: 3);
      final List<PreventionNotificationSlot> slots = planFor(
        <PreventionCoursePlanInput>[(course: c, doses: doses)],
        isPro: false,
      );
      expect(
        countOf(slots, <PreventionSlotKind>{PreventionSlotKind.doseDue}),
        5,
      );
    });

    test('notificationEnabled=false のコースは一切積まない', () {
      final PreventionCourseEntity c =
          course(id: 1, notificationEnabled: false);
      final List<PreventionNotificationSlot> slots = planFor(
        <PreventionCoursePlanInput>[(course: c, doses: dosesFor(c))],
        isPro: true,
      );
      expect(slots, isEmpty);
    });

    test('Tier 1 が 1 slot なら残り 11 が下位ティアへ流れる (§5.4 の例)', () {
      // シーズン開始 2026-02-10。now=2026-01-15 なので 30 日前 (01-11) は
      // 既に過去で落ち、7 日前 (02-03) だけが Tier 1 に残る。
      final PreventionCourseEntity c =
          course(id: 1, startMonth: 2, endMonth: 12);
      final List<PreventionNotificationSlot> slots = planFor(
        <PreventionCoursePlanInput>[(course: c, doses: dosesFor(c))],
        isPro: false,
      );
      expect(countOf(slots, testTier), 1);
      expect(
        countOf(slots, <PreventionSlotKind>{PreventionSlotKind.doseDue}),
        11,
        reason: '予約は min(所要数, 4)。余りは Tier 2 に回る',
      );
      expect(slots.length, budget);
    });

    test('過去日の通知は積まない (30 日前が過ぎていれば 7 日前だけ残る)', () {
      final PreventionCourseEntity c =
          course(id: 1, startMonth: 2, endMonth: 3);
      final List<PreventionNotificationSlot> slots = planFor(
        <PreventionCoursePlanInput>[(course: c, doses: dosesFor(c))],
        isPro: false,
      );
      expect(
        slots
            .where((PreventionNotificationSlot s) =>
                s.kind == PreventionSlotKind.testReminder30)
            .toList(),
        isEmpty,
      );
      expect(
        slots
            .where((PreventionNotificationSlot s) =>
                s.kind == PreventionSlotKind.testReminder7)
            .toList(),
        hasLength(1),
      );
      // 全ての通知が now より未来
      for (final PreventionNotificationSlot s in slots) {
        expect(s.fireAt.isAfter(now), isTrue);
      }
    });

    test('Pro 限定 slot は Tier 2 を満たした後にだけ入る', () {
      // dose が少ないコースなら Tier 3/4/5 まで届く
      final PreventionCourseEntity c = course(
        id: 1,
        startMonth: 5,
        endMonth: 6, // 2 回
        testedAt: 1, // 検査済みなので Tier 1 なし
      );
      final List<PreventionNotificationSlot> slots = planFor(
        <PreventionCoursePlanInput>[(course: c, doses: dosesFor(c))],
        isPro: true,
      );
      expect(
        countOf(slots, <PreventionSlotKind>{PreventionSlotKind.doseDue}),
        2,
      );
      expect(
        countOf(slots, <PreventionSlotKind>{PreventionSlotKind.doseFinal}),
        1,
      );
      expect(
        countOf(slots, <PreventionSlotKind>{PreventionSlotKind.doseFollowUp}),
        2,
      );
      expect(
        countOf(slots, <PreventionSlotKind>{PreventionSlotKind.nextSeason}),
        1,
      );
      expect(slots.length, 6);
    });

    test('バジェットを超えて積むことはない', () {
      final List<PreventionCoursePlanInput> inputs =
          <PreventionCoursePlanInput>[];
      int idBase = 0;
      for (int i = 1; i <= 8; i++) {
        final PreventionCourseEntity c =
            course(id: i, petId: i, startMonth: 1, endMonth: 12);
        inputs.add((course: c, doses: dosesFor(c, idBase: idBase)));
        idBase += 100;
      }
      final List<PreventionNotificationSlot> slots =
          planFor(inputs, isPro: true);
      expect(slots.length, budget);
    });

    test('notifyTime が発火時刻に反映される', () {
      final PreventionCourseEntity c = course(id: 1, notifyTime: '20:30');
      final List<PreventionNotificationSlot> slots = planFor(
        <PreventionCoursePlanInput>[(course: c, doses: dosesFor(c))],
        isPro: false,
      );
      final PreventionNotificationSlot first = slots.firstWhere(
        (PreventionNotificationSlot s) => s.kind == PreventionSlotKind.doseDue,
      );
      expect(first.fireAt.hour, 20);
      expect(first.fireAt.minute, 30);
    });

    test('通知 ID レンジが dose / course で分かれている', () {
      final PreventionCourseEntity c = course(id: 1);
      final List<PreventionNotificationSlot> slots = planFor(
        <PreventionCoursePlanInput>[(course: c, doses: dosesFor(c))],
        isPro: false,
      );
      for (final PreventionNotificationSlot s in slots) {
        if (testTier.contains(s.kind)) {
          expect(s.doseId, isNull);
          expect(s.notificationSlot, anyOf(0, 1));
        } else {
          expect(s.doseId, isNotNull);
        }
      }
    });
  });
}
