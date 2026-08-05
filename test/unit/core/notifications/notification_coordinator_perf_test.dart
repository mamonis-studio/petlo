// ============================================================================
// petlo - NotificationCoordinator 所要時間の実測 (build 73)
// ============================================================================
//
// 個別 sync を廃止し「変更のたびに全体を再割り当てする」方式に変えた。
// ワクチン 50 件の状態で 1 件編集したときの所要時間を測る。
// 体感で引っかかるようなら debounce を検討する。
//
// 注: ここで測るのはロジック部分 (DB 読み + 配分 + チャンネル呼び出し)。
// 実機のプラットフォーム処理は含まないので下限値として読む。
//
// ============================================================================

@Tags(<String>['needs_codegen'])
library;

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
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

void main() {
  test('ワクチン50件の状態で1件編集 → 再割り当ての所要時間', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await PetloLogger.initialize();
    initializeDateFormatting();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await UserPreferences.instance.initialize();

    const MethodChannel ch =
        MethodChannel('dexterous.com/flutter/local_notifications');
    final Map<int, String> sched = <int, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, (MethodCall c) async {
      switch (c.method) {
        case 'zonedSchedule':
        case 'schedule':
          sched[(c.arguments as Map<Object?, Object?>)['id']! as int] = '';
          return null;
        case 'cancel':
          final Object? a = c.arguments;
          sched.remove(a is int ? a : (a! as Map<Object?, Object?>)['id']);
          return null;
        case 'pendingNotificationRequests':
          return sched.keys
              .map((int e) => <Object?, Object?>{
                    'id': e,
                    'title': '',
                    'body': '',
                    'payload': null,
                  })
              .toList();
        case 'initialize':
          return true;
        case 'getNotificationAppLaunchDetails':
          return <Object?, Object?>{'notificationLaunchedApp': false};
        default:
          return null;
      }
    });

    final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
    final VaccinationsRepository vac = VaccinationsRepository(db);
    final DateTime now = DateTime.now();
    for (int i = 0; i < 50; i++) {
      await vac.create(
        groupId: 'personal',
        petId: 1,
        kind: 'k$i',
        administeredAtMsec: now.millisecondsSinceEpoch,
        nextDueAtMsec:
            now.add(Duration(days: 20 + i * 3)).millisecondsSinceEpoch,
      );
    }

    final NotificationCoordinator coord = NotificationCoordinator(
      service: NotificationService.instance,
      schedulesRepo: SchedulesRepository(db),
      vaccinationsRepo: vac,
      preventionCoursesRepo: PreventionCoursesRepository(db),
      preventionDosesRepo: PreventionDosesRepository(db),
      petsRepo: PetsRepository(db),
    );

    // 初回 (全件登録)
    final Stopwatch first = Stopwatch()..start();
    await coord.rescheduleAll(isPro: true);
    first.stop();

    // 1 件編集 → 再割り当て (差分キャンセルが効く経路)
    final List<VaccinationEntity> all = await db.select(db.vaccinations).get();
    await vac.update(
      vaccinationId: all.first.id,
      nextDueAtMsec:
          now.add(const Duration(days: 400)).millisecondsSinceEpoch,
    );
    final Stopwatch edit = Stopwatch()..start();
    await coord.rescheduleAll(isPro: true);
    edit.stop();

    // ignore: avoid_print
    print('PERF first=${first.elapsedMilliseconds}ms '
        'edit=${edit.elapsedMilliseconds}ms scheduled=${sched.length}');

    expect(sched.length, lessThanOrEqualTo(NotificationBudget.total));
    // 回帰検知用の緩いガード。実機はこれより遅いが桁が変われば気付ける。
    expect(edit.elapsedMilliseconds, lessThan(3000));

    await db.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, null);
  });
}
