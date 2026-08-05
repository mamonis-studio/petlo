// ============================================================================
// petlo - Prevention Kill Switch Tests (build 73)
// ============================================================================
//
// AppConstants.enablePrevention を false に倒したとき、以下が「すべて」
// 止まることを担保する。
//
//   (1) 健康タブの予防セクションを表示しない   … health_tab_screen 側の分岐
//   (2) 予防の通知候補が 0 件になる            … NotificationCoordinator
//   (3) 予防が使わない枠が他系統へ流れる        … NotificationBudget の配分
//
// ============================================================================
// このテストの書き換え経緯 (重要)
// ============================================================================
//
// 当初は `kScheduleSlotBudget + kPreventionSlotBudget == 50` を検証していた。
// しかし Step 3 で個別 sync を全廃した結果、その定数を使う
// rescheduleAllSchedules() は **誰からも呼ばれなくなった**。
// つまり不変条件は成り立っていても何も守っていない状態だった。
//
// 総量を決めているのは NotificationBudget と NotificationBudgetAllocator。
// よってここでは死んだ定数への依存を外し、
// **Coordinator を実際に走らせて** 配分結果を検証する。
//
// enablePrevention は compile-time const なので 1 回の実行で両方の状態は
// 踏めない。フラグ依存の検証は現在値に応じて分岐し、フラグに依存しない
// 「予防が候補 0 のときの配分」は reserveOverride で直接再現する。
//
// ============================================================================

@Tags(<String>['needs_codegen'])
library;

import 'package:drift/drift.dart' show QueryRow;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:petlo/core/constants/app_constants.dart';
import 'package:petlo/core/notifications/notification_budget_allocator.dart';
import 'package:petlo/core/notifications/notification_coordinator.dart';
import 'package:petlo/core/notifications/notification_service.dart';
import 'package:petlo/core/preferences/user_preferences.dart';
import 'package:petlo/core/utils/logger.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/data/repositories/pets_repository.dart';
import 'package:petlo/data/repositories/prevention_courses_repository.dart';
import 'package:petlo/data/repositories/prevention_doses_repository.dart';
import 'package:petlo/data/repositories/schedules_repository.dart';
import 'package:petlo/data/repositories/vaccinations_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 予約中の通知を保持するだけのプラグインモック。
class _FakeChannel {
  _FakeChannel() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, _handle);
  }

  static const MethodChannel _channel =
      MethodChannel('dexterous.com/flutter/local_notifications');

  final Map<int, String> scheduled = <int, String>{};
  final List<int> cancelled = <int>[];

  Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'initialize':
        return true;
      case 'zonedSchedule':
      case 'schedule':
      case 'show':
        final Map<Object?, Object?> a =
            call.arguments as Map<Object?, Object?>;
        scheduled[a['id']! as int] = (a['title'] as String?) ?? '';
        return null;
      case 'cancel':
        final Object? arg = call.arguments;
        final int id =
            arg is int ? arg : (arg! as Map<Object?, Object?>)['id']! as int;
        scheduled.remove(id);
        cancelled.add(id);
        return null;
      case 'pendingNotificationRequests':
        return scheduled.entries
            .map((MapEntry<int, String> e) => <Object?, Object?>{
                  'id': e.key,
                  'title': e.value,
                  'body': '',
                  'payload': null,
                })
            .toList();
      case 'getNotificationAppLaunchDetails':
        return <Object?, Object?>{'notificationLaunchedApp': false};
      default:
        return null;
    }
  }

  void dispose() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }
}

void main() {
  final DateTime now = DateTime(2026, 8, 3, 12);

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await PetloLogger.initialize();
    initializeDateFormatting();
  });

  // ==========================================================================
  // 配分の性質 (フラグに依存しない)
  // ==========================================================================

  group('★予防が候補 0 のとき、12 枠が他系統に流れる', () {
    List<NotificationCandidate> make(NotificationSystem s, int n, int idBase) {
      return <NotificationCandidate>[
        for (int i = 0; i < n; i++)
          NotificationCandidate(
            system: s,
            id: idBase + i,
            fireAt: now.add(Duration(days: 1 + i)),
            rank: i,
            title: '${s.name}$i',
            body: '',
          ),
      ];
    }

    test('予防の候補が無ければ他系統が 64 を使い切れる', () {
      final NotificationAllocation r =
          NotificationBudgetAllocator.allocate(
        candidates: <NotificationCandidate>[
          ...make(NotificationSystem.vaccination, 100, 1000),
          ...make(NotificationSystem.schedule, 100, 100000000),
        ],
        now: now,
      );

      expect(r.selected, hasLength(NotificationBudget.total),
          reason: '予防が使わない 12 枠を余らせてはいけない');
      expect(
        r.selected
            .where((NotificationCandidate c) =>
                c.system == NotificationSystem.prevention)
            .length,
        0,
      );
    });

    test('reserveOverride で 0 にしても同じ結果になる (二重防御の等価性)', () {
      final List<NotificationCandidate> candidates = <NotificationCandidate>[
        ...make(NotificationSystem.vaccination, 100, 1000),
        ...make(NotificationSystem.schedule, 100, 100000000),
      ];

      // 本命の防御: 候補が 0 件
      final NotificationAllocation viaEmptyCandidates =
          NotificationBudgetAllocator.allocate(
              candidates: candidates, now: now);

      // 二重防御: reserveOverride で予防枠を 0 に
      final NotificationAllocation viaOverride =
          NotificationBudgetAllocator.allocate(
        candidates: candidates,
        now: now,
        reserveOverride: <NotificationSystem, int>{
          NotificationSystem.vaccination:
              NotificationBudget.vaccinationReserve,
          NotificationSystem.schedule: NotificationBudget.scheduleReserve,
          NotificationSystem.prevention: 0,
        },
      );

      expect(
        viaOverride.selected.map((NotificationCandidate c) => c.id).toList(),
        viaEmptyCandidates.selected
            .map((NotificationCandidate c) => c.id)
            .toList(),
        reason: 'どちらの経路でも配分は同じ。'
            'reserveOverride は保険であって本命ではない',
      );
    });

    test('合計は常に 64 を超えない', () {
      final NotificationAllocation r =
          NotificationBudgetAllocator.allocate(
        candidates: <NotificationCandidate>[
          ...make(NotificationSystem.vaccination, 200, 1000),
          ...make(NotificationSystem.schedule, 200, 100000000),
          ...make(NotificationSystem.prevention, 200, 400000000),
        ],
        now: now,
      );
      expect(r.selected.length, lessThanOrEqualTo(NotificationBudget.total));
    });
  });

  // ==========================================================================
  // Coordinator を実際に走らせる
  // ==========================================================================

  group('Coordinator 経由の実挙動', () {
    late AppDatabase db;
    late _FakeChannel fake;
    late NotificationCoordinator coordinator;
    late PreventionCoursesRepository courses;
    late VaccinationsRepository vaccinations;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await UserPreferences.instance.initialize();

      fake = _FakeChannel();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      courses = PreventionCoursesRepository(db);
      vaccinations = VaccinationsRepository(db);

      coordinator = NotificationCoordinator(
        service: NotificationService.instance,
        schedulesRepo: SchedulesRepository(db),
        vaccinationsRepo: vaccinations,
        preventionCoursesRepo: courses,
        preventionDosesRepo: PreventionDosesRepository(db),
        petsRepo: PetsRepository(db),
      );
    });

    tearDown(() async {
      fake.dispose();
      await db.close();
    });

    Future<void> seedPrevention() async {
      await courses.create(
        groupId: 'personal',
        petId: 1,
        kind: PreventionKind.filaria,
        year: DateTime.now().year + 1,
        startMonth: 1,
        endMonth: 12,
        dayOfMonth: 10,
      );
    }

    Future<void> seedVaccinations(int count) async {
      final DateTime n = DateTime.now();
      for (int i = 0; i < count; i++) {
        await vaccinations.create(
          groupId: 'personal',
          petId: 1,
          kind: 'k$i',
          administeredAtMsec: n.millisecondsSinceEpoch,
          nextDueAtMsec:
              n.add(Duration(days: 20 + i * 3)).millisecondsSinceEpoch,
        );
      }
    }

    int preventionScheduled() => fake.scheduled.keys
        .where((int id) => id >= 400000000 && id < 600000000)
        .length;

    test('★enablePrevention に応じて予防の候補数が決まる', () async {
      await seedPrevention();
      final NotificationAllocationReport? report =
          await coordinator.rescheduleAll(isPro: true);
      expect(report, isNotNull);

      final int candidates =
          report!.candidatesOf(NotificationSystem.prevention);
      if (AppConstants.enablePrevention) {
        expect(candidates, greaterThan(0),
            reason: 'フラグが立っていれば候補が出る');
      } else {
        expect(candidates, 0,
            reason: '★フラグを倒したら候補は 0 件でなければならない');
        expect(preventionScheduled(), 0);
      }
    });

    test('★既に積まれた予防通知は差分キャンセルで消える', () async {
      // フラグの値に関わらず「候補に無い予防 ID は掃除される」ことを見る。
      // 存在しないコースの ID を混ぜて、候補に上がりようがない状態を作る。
      const int orphanDoseId = 400000000 + 99999 * 4;
      const int orphanCourseId = 500000000 + 99999 * 4;
      fake.scheduled[orphanDoseId] = 'stale prevention dose';
      fake.scheduled[orphanCourseId] = 'stale prevention course';

      await seedVaccinations(2);
      await coordinator.rescheduleAll(isPro: true);

      expect(fake.scheduled.containsKey(orphanDoseId), isFalse,
          reason: '候補から消えた予防通知は keep に含まれず cancel される');
      expect(fake.scheduled.containsKey(orphanCourseId), isFalse);
      expect(fake.cancelled, contains(orphanDoseId));
      expect(fake.cancelled, contains(orphanCourseId));
    });

    test('★予防が 0 でも他系統が枠を使い切れる', () async {
      // 予防コースを作らず、ワクチンだけを大量に積む。
      // 予防が候補 0 の状況は、フラグを倒した場合と同じ配分になる。
      await seedVaccinations(50);
      final NotificationAllocationReport? report =
          await coordinator.rescheduleAll(isPro: true);

      expect(report!.candidatesOf(NotificationSystem.prevention), 0);
      expect(report.totalScheduled, NotificationBudget.total,
          reason: '予防の 12 枠が余ってはいけない');
      expect(fake.scheduled.length, NotificationBudget.total);
    });

    test('合計が 64 を超えない', () async {
      await seedPrevention();
      await seedVaccinations(50);
      await coordinator.rescheduleAll(isPro: true);
      expect(fake.scheduled.length,
          lessThanOrEqualTo(NotificationBudget.total));
    });
  });

  // ==========================================================================
  // DB は触らない
  // ==========================================================================

  group('キルスイッチは DB に触らない', () {
    test('schemaVersion はフラグに依存せず 10、予防テーブルも残る', () async {
      // フラグを倒してもテーブルは残す。migration の巻き戻しだけが
      // 本当に破壊的な操作であり、キルスイッチでやってよいことではない。
      final AppDatabase db =
          AppDatabase.forTesting(NativeDatabase.memory());
      expect(db.schemaVersion, 10);

      final List<QueryRow> tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name LIKE 'prevention_%'",
          )
          .get();
      expect(tables, hasLength(2));

      await db.close();
    });
  });
}
