// ============================================================================
// petlo - Vaccination Notification ID Migration Tests (build 73)
// ============================================================================
//
// 旧採番 `1000000 + vaccinationId` は幅 1 しか無いのに 2 slot 使っていたため、
// 隣接 ID のワクチン同士が必ず衝突していた。新採番は `+ id * 4 + slot`。
//
// 旧採番で積まれた通知は新採番と重ならない保証が無いので、起動時に一度だけ
// 旧レンジ (1,000,000 〜 10,000,000) を全掃除してから積み直す。
//
// ここで見るのは:
//   - 掃除が旧レンジだけを消し、他系統を巻き込まないこと
//   - 掃除が 1 回だけ走ること (フラグ)
//   - 10 件のワクチンで 20 slot 積まれること
//
// ============================================================================

@Tags(<String>['needs_codegen'])
library;

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/core/notifications/notification_scheduler.dart';
import 'package:petlo/core/notifications/notification_service.dart';
import 'package:petlo/core/preferences/user_preferences.dart';
import 'package:petlo/core/utils/logger.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/data/repositories/schedules_repository.dart';
import 'package:petlo/data/repositories/vaccinations_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 通知の登録・キャンセルを記録するだけの差し替え可能な NotificationService。
///
/// NotificationService はシングルトンで final メソッドしか無いため、
/// ここでは「プラグインのメソッドチャンネルをモックする」方式を採る。
/// 実サービスを通すので、ID 採番とキャンセル範囲の実挙動を検証できる。
class _FakeChannel {
  _FakeChannel() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, _handle);
  }

  static const MethodChannel _channel =
      MethodChannel('dexterous.com/flutter/local_notifications');

  /// 現在「予約中」の通知 id → タイトル
  final Map<int, String> scheduled = <int, String>{};

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
        // プラグインは platform によって int / Map のどちらでも送ってくる
        final Object? arg = call.arguments;
        if (arg is int) {
          scheduled.remove(arg);
        } else if (arg is Map) {
          scheduled.remove(arg['id'] as int);
        }
        return null;
      case 'cancelAll':
        scheduled.clear();
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
  late NotificationScheduler scheduler;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await PetloLogger.initialize();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await UserPreferences.instance.initialize();
    // 各テストで未移行状態から始める
    await UserPreferences.instance.setVaccinationIdMigratedV2(false);

    fake = _FakeChannel();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    scheduler = NotificationScheduler(
      service: NotificationService.instance,
      schedulesRepo: SchedulesRepository(db),
      vaccinationsRepo: VaccinationsRepository(db),
    );
  });

  tearDown(() async {
    fake.dispose();
    await db.close();
  });

  /// nextDueAt を未来に散らしたワクチンを [count] 件作る。
  Future<void> seedVaccinations(int count) async {
    final VaccinationsRepository repo = VaccinationsRepository(db);
    final DateTime now = DateTime.now();
    for (int i = 0; i < count; i++) {
      await repo.create(
        groupId: 'personal',
        petId: 1,
        kind: 'kind$i',
        administeredAtMsec: now.millisecondsSinceEpoch,
        // 3日前通知も当日通知も未来になるよう十分先に散らす
        nextDueAtMsec: now.add(Duration(days: 20 + i * 5)).millisecondsSinceEpoch,
      );
    }
  }

  group('新採番でのスケジューリング', () {
    test('★10 件のワクチンで 20 slot 積まれる', () async {
      await seedVaccinations(10);

      await scheduler.rescheduleAllVaccinationAlerts();

      final List<int> vaccinationIds = fake.scheduled.keys
          .where((int id) =>
              id >= kVaccinationIdRangeStart && id < kVaccinationIdRangeEnd)
          .toList();
      expect(vaccinationIds, hasLength(20),
          reason: '1 件につき 3日前 + 当日 の 2 slot。旧採番では 11 個しか出なかった');
    });

    test('★1 件削除しても隣のワクチンの通知が消えない', () async {
      await seedVaccinations(3);
      await scheduler.rescheduleAllVaccinationAlerts();
      expect(fake.scheduled, hasLength(6));

      // 真ん中 (id=2) の通知だけを掃除する
      await scheduler.cancelVaccinationDueAlert(2);

      for (final int slot in <int>[0, 1]) {
        expect(
          fake.scheduled.containsKey(
              NotificationService.idForVaccination(1, slot)),
          isTrue,
          reason: 'v1 の通知が巻き込まれてはいけない',
        );
        expect(
          fake.scheduled.containsKey(
              NotificationService.idForVaccination(3, slot)),
          isTrue,
          reason: 'v3 の通知が巻き込まれてはいけない',
        );
        expect(
          fake.scheduled.containsKey(
              NotificationService.idForVaccination(2, slot)),
          isFalse,
          reason: 'v2 自身は消える',
        );
      }
      expect(fake.scheduled, hasLength(4));
    });

    test('syncVaccinationDueAlert が積んだ slot 数を返す', () async {
      await seedVaccinations(1);
      final int used = await scheduler.syncVaccinationDueAlert(1);
      expect(used, 2, reason: 'ログ粒度を slot 単位にするための戻り値');
    });
  });

  group('旧レンジの掃除 (移行)', () {
    /// 旧採番 `1000000 + id` で積まれた残骸を模擬する
    void seedLegacyPending() {
      for (int id = 1; id <= 5; id++) {
        fake.scheduled[1000000 + id] = 'legacy vaccination $id';
      }
    }

    test('旧レンジの通知が全て消える', () async {
      seedLegacyPending();
      expect(fake.scheduled, hasLength(5));

      await scheduler.migrateLegacyVaccinationNotificationIds();

      expect(fake.scheduled, isEmpty);
    });

    test('他系統の通知を巻き込まない', () async {
      seedLegacyPending();
      // schedule (100M) / prevention dose (400M) / prevention course (500M)
      fake.scheduled[NotificationService.idForSchedule(1, 0, 0)] = 'schedule';
      fake.scheduled[NotificationService.idForPreventionDose(1, 0)] = 'dose';
      fake.scheduled[NotificationService.idForPreventionCourse(1, 0)] =
          'course';

      await scheduler.migrateLegacyVaccinationNotificationIds();

      expect(fake.scheduled.keys.toSet(), <int>{
        NotificationService.idForSchedule(1, 0, 0),
        NotificationService.idForPreventionDose(1, 0),
        NotificationService.idForPreventionCourse(1, 0),
      });
    });

    test('★掃除は 1 回だけ走る', () async {
      seedLegacyPending();
      await scheduler.migrateLegacyVaccinationNotificationIds();
      expect(UserPreferences.instance.vaccinationIdMigratedV2, isTrue);

      // 2 回目: 旧レンジに何か積まれていても触らない
      fake.scheduled[1000042] = 'should survive';
      await scheduler.migrateLegacyVaccinationNotificationIds();

      expect(fake.scheduled.containsKey(1000042), isTrue,
          reason: '毎起動で走らせない。フラグで抑止する');
    });

    test('移行済みフラグが立っていれば最初から何もしない', () async {
      await UserPreferences.instance.setVaccinationIdMigratedV2(true);
      seedLegacyPending();

      await scheduler.migrateLegacyVaccinationNotificationIds();

      expect(fake.scheduled, hasLength(5));
    });

    test('掃除 → 積み直しで新採番に入れ替わる', () async {
      seedLegacyPending();
      await seedVaccinations(3);

      await scheduler.migrateLegacyVaccinationNotificationIds();
      await scheduler.rescheduleAllVaccinationAlerts();

      // 旧採番の残骸 (1000001..1000005) は消えている。
      // v1 slot0 = 1000004 は新採番として再登場するので、
      // 「旧採番でしか出ない ID」で判定する。
      expect(fake.scheduled.containsKey(1000001), isFalse);
      expect(fake.scheduled.containsKey(1000002), isFalse);
      expect(fake.scheduled.containsKey(1000003), isFalse);
      // 新採番で 3 件 × 2 slot
      expect(fake.scheduled, hasLength(6));
      for (int id = 1; id <= 3; id++) {
        for (final int slot in <int>[0, 1]) {
          expect(
            fake.scheduled
                .containsKey(NotificationService.idForVaccination(id, slot)),
            isTrue,
          );
        }
      }
    });
  });
}
