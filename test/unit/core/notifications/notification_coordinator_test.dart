// ============================================================================
// petlo - NotificationCoordinator Tests (build 73)
// ============================================================================
//
// 3 系統をまとめて 64 枠に収める経路の統合テスト。
// プラグインのメソッドチャンネルをモックし、実サービスを通すので
// ID 採番・差分キャンセル・登録件数の実挙動を検証できる。
//
// 特に見るのは:
//   - 総量が 64 を超えないこと
//   - ワクチンが他系統を押し潰さないこと (Phase C の再現防止)
//   - 差分キャンセル: 残る通知は一瞬も消えないこと (落ちたときの窓を潰す)
//   - 再割り当ての途中で落ちても、次回起動で回復すること
//
// ============================================================================

@Tags(<String>['needs_codegen'])
library;

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

  /// 登録・キャンセルの履歴 (差分キャンセルの検証に使う)
  final List<String> ops = <String>[];

  Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'initialize':
        return true;
      case 'zonedSchedule':
      case 'schedule':
      case 'show':
        final Map<Object?, Object?> a =
            call.arguments as Map<Object?, Object?>;
        final int id = a['id']! as int;
        scheduled[id] = (a['title'] as String?) ?? '';
        ops.add('add:$id');
        return null;
      case 'cancel':
        final Object? arg = call.arguments;
        final int id = arg is int ? arg : (arg! as Map)['id'] as int;
        scheduled.remove(id);
        ops.add('cancel:$id');
        return null;
      case 'cancelAll':
        scheduled.clear();
        ops.add('cancelAll');
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
  late AppDatabase db;
  late _FakeChannel fake;
  late NotificationCoordinator coordinator;
  late VaccinationsRepository vaccinations;
  late PreventionCoursesRepository courses;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await PetloLogger.initialize();
    // 通知の文言組み立てが DateFormat を使う。アプリ側は main() で
    // 初期化しているので、テストでも同じ前提を揃える。
    initializeDateFormatting();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await UserPreferences.instance.initialize();

    fake = _FakeChannel();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    vaccinations = VaccinationsRepository(db);
    courses = PreventionCoursesRepository(db);

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

  Future<void> seedVaccinations(int count) async {
    final DateTime now = DateTime.now();
    for (int i = 0; i < count; i++) {
      await vaccinations.create(
        groupId: 'personal',
        petId: 1,
        kind: 'kind$i',
        administeredAtMsec: now.millisecondsSinceEpoch,
        nextDueAtMsec:
            now.add(Duration(days: 20 + i * 3)).millisecondsSinceEpoch,
      );
    }
  }

  Future<void> seedPreventionCourses(int count) async {
    for (int i = 0; i < count; i++) {
      await courses.create(
        groupId: 'personal',
        petId: i + 1,
        kind: PreventionKind.filaria,
        year: DateTime.now().year + 1,
        startMonth: 1,
        endMonth: 12,
        dayOfMonth: 10,
      );
    }
  }

  int countInRange(int start, int endExclusive) => fake.scheduled.keys
      .where((int id) => id >= start && id < endExclusive)
      .length;

  // 関数本体の中では getter を宣言できないのでローカル関数にする
  int vaccinationCount() => countInRange(1000000, 10000000);
  int preventionCount() => countInRange(400000000, 600000000);

  group('総量ガード', () {
    test('★ワクチン50件でも合計 64 を超えない', () async {
      await seedVaccinations(50);

      final NotificationAllocationReport? report =
          await coordinator.rescheduleAll(isPro: true);

      expect(report, isNotNull);
      expect(fake.scheduled.length, lessThanOrEqualTo(NotificationBudget.total));
      expect(report!.totalScheduled, fake.scheduled.length);
    });

    test('★ワクチンが予防の最低保証を押し潰さない', () async {
      await seedVaccinations(50);
      await seedPreventionCourses(4);

      await coordinator.rescheduleAll(isPro: true);

      expect(fake.scheduled.length,
          lessThanOrEqualTo(NotificationBudget.total));

      if (AppConstants.enablePrevention) {
        expect(
          preventionCount(),
          greaterThanOrEqualTo(NotificationBudget.preventionReserve),
          reason: 'Phase C ではワクチンが 75% を占領して他系統を潰していた',
        );
        // ワクチンは残り全部を取ってよいが、他系統の最低保証は侵せない。
        // Phase C では保証が無かったため予防・schedule が押し出された。
        expect(
          vaccinationCount(),
          lessThanOrEqualTo(
              NotificationBudget.total - NotificationBudget.preventionReserve),
          reason: '予防の最低保証を食い潰してはいけない',
        );
      } else {
        // キルスイッチが倒れていれば予防は 0。最低保証の検証は成立しない。
        // 「12 枠が他系統へ流れる」ことは prevention_kill_switch_test が見る。
        expect(preventionCount(), 0);
        expect(fake.scheduled.length, NotificationBudget.total,
            reason: '予防が使わない枠を余らせてはいけない');
      }
    });

    test('候補が少なければ全部積まれる', () async {
      await seedVaccinations(3);
      final NotificationAllocationReport? report =
          await coordinator.rescheduleAll(isPro: true);
      expect(report!.totalDropped, 0);
      expect(vaccinationCount(), 6, reason: '3 件 × 2 slot');
    });
  });

  group('★差分キャンセル (落ちたときの窓を潰す)', () {
    test('残る通知は cancel されない', () async {
      await seedVaccinations(3);
      await coordinator.rescheduleAll(isPro: true);
      final Set<int> first = fake.scheduled.keys.toSet();

      fake.ops.clear();
      // 同じ状態でもう一度走らせる
      await coordinator.rescheduleAll(isPro: true);

      final List<String> cancels =
          fake.ops.where((String o) => o.startsWith('cancel:')).toList();
      expect(cancels, isEmpty,
          reason: '割り当てが変わらないなら 1 件も cancel してはいけない');
      expect(fake.scheduled.keys.toSet(), first);
    });

    test('割り当てから外れたものだけ cancel される', () async {
      await seedVaccinations(3);
      await coordinator.rescheduleAll(isPro: true);
      final Set<int> before = fake.scheduled.keys.toSet();

      // 1 件消すと、その 2 slot だけが対象になる
      final List<VaccinationEntity> all =
          await db.select(db.vaccinations).get();
      await vaccinations.softDelete(all.first.id);

      fake.ops.clear();
      await coordinator.rescheduleAll(isPro: true);

      final Set<int> cancelled = fake.ops
          .where((String o) => o.startsWith('cancel:'))
          .map((String o) => int.parse(o.split(':')[1]))
          .toSet();
      expect(cancelled, hasLength(2));
      expect(
        cancelled,
        <int>{
          NotificationService.idForVaccination(all.first.id, 0),
          NotificationService.idForVaccination(all.first.id, 1),
        },
      );
      expect(fake.scheduled.keys.toSet(),
          before.difference(cancelled));
    });

    test('自分のレンジ外は触らない', () async {
      // 他プラグイン由来の通知を模擬
      fake.scheduled[999] = 'foreign';
      fake.scheduled[700000000] = 'foreign too';

      await seedVaccinations(2);
      await coordinator.rescheduleAll(isPro: true);

      expect(fake.scheduled.containsKey(999), isTrue);
      expect(fake.scheduled.containsKey(700000000), isTrue);
    });
  });

  group('★落ちたときの回復経路', () {
    test('通知が全消しされた状態から起動しても復元される', () async {
      await seedVaccinations(5);
      await coordinator.rescheduleAll(isPro: true);
      final Set<int> healthy = fake.scheduled.keys.toSet();
      expect(healthy, isNotEmpty);

      // cancel 後 schedule 前に落ちた状況を模擬する
      fake.scheduled.clear();

      // 起動時の再割り当て
      await coordinator.rescheduleAll(isPro: true);

      expect(fake.scheduled.keys.toSet(), healthy,
          reason: 'DB が真実なので、次回起動で必ず同じ状態に収束する');
    });

    test('中途半端に残った状態からでも収束する', () async {
      await seedVaccinations(5);
      await coordinator.rescheduleAll(isPro: true);
      final Set<int> healthy = fake.scheduled.keys.toSet();

      // 半分だけ消えた状態
      final List<int> half = healthy.take(healthy.length ~/ 2).toList();
      for (final int id in half) {
        fake.scheduled.remove(id);
      }

      await coordinator.rescheduleAll(isPro: true);
      expect(fake.scheduled.keys.toSet(), healthy);
    });
  });

  group('レポートの永続化', () {
    test('割り当て結果が UserPreferences に残る', () async {
      await seedVaccinations(50);
      await coordinator.rescheduleAll(isPro: true);

      final Map<String, dynamic>? raw =
          UserPreferences.instance.notificationAllocationReport;
      expect(raw, isNotNull);

      final NotificationAllocationReport? report =
          NotificationAllocationReport.fromJson(raw!);
      expect(report, isNotNull);
      expect(report!.totalScheduled, fake.scheduled.length);
      expect(report.droppedOf(NotificationSystem.vaccination),
          greaterThan(0));
    });
  });

  group('多重実行の抑止', () {
    test('走行中の再入は skip される', () async {
      await seedVaccinations(10);
      final List<Future<NotificationAllocationReport?>> futures =
          <Future<NotificationAllocationReport?>>[
        coordinator.rescheduleAll(isPro: true),
        coordinator.rescheduleAll(isPro: true),
      ];
      final List<NotificationAllocationReport?> results =
          await Future.wait(futures);
      // 2 本目は null (skip)
      expect(results.where((NotificationAllocationReport? r) => r == null),
          hasLength(1));
    });
  });
}
