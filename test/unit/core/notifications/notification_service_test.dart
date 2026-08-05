// ============================================================================
// petlo - Notification Service Tests
// ============================================================================
//
// プラットフォーム呼び出しは Mockできないので、ここでは
// Pure Dart で計算可能な ID 採番ロジックのみテストする。
//
// ============================================================================

import 'package:flutter/services.dart';
import 'package:petlo/core/utils/logger.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/core/notifications/notification_service.dart';

void main() {
  group('NotificationService.idForVaccination (build 73: 幅 4)', () {
    test('vaccination 1 slot 0 → 1_000_004', () {
      expect(NotificationService.idForVaccination(1, 0), 1000004);
      expect(NotificationService.idForVaccination(1, 1), 1000005);
    });

    test('★隣接する vaccinationId で ID が衝突しない', () {
      // 旧採番 (1000000 + id) は幅 1 しか無いのに 2 slot 使っていたため、
      // v3 の当日 (1000004) と v4 の3日前 (1000004) が必ず衝突し、
      // N 件登録しても distinct な ID は N+1 個にしかならなかった。
      final Set<int> ids = <int>{};
      for (int id = 1; id <= 10; id++) {
        ids.add(NotificationService.idForVaccination(id, 0));
        ids.add(NotificationService.idForVaccination(id, 1));
      }
      expect(ids, hasLength(20), reason: '10 件 × 2 slot = 20 個が全て別 ID');
    });

    test('★1 件分の cancelRange が隣の ID を巻き込まない', () {
      // cancelRange(baseId, kVaccinationSlotSpan) が消す範囲
      final int base3 = NotificationService.idForVaccination(3, 0);
      final Set<int> cleared = <int>{
        for (int i = 0; i < 4; i++) base3 + i,
      };
      // 隣接する v2 / v4 が使う ID
      for (final int slot in <int>[0, 1]) {
        expect(cleared.contains(NotificationService.idForVaccination(2, slot)),
            isFalse,
            reason: 'v3 の掃除が v2 の通知を消してはいけない');
        expect(cleared.contains(NotificationService.idForVaccination(4, slot)),
            isFalse,
            reason: 'v3 の掃除が v4 の通知を消してはいけない');
      }
    });

    test('確保した幅 4 を超えて次の ID に食い込まない', () {
      expect(
        NotificationService.idForVaccination(1, 3),
        lessThan(NotificationService.idForVaccination(2, 0)),
      );
    });

    test('medication レンジ (10M) の手前に収まる — 境界の明示', () {
      // 1_000_000 + id * 4 < 10_000_000  ⇔  id < 2_250_000
      expect(NotificationService.idForVaccination(2249999, 3),
          lessThan(10000000));
      expect(NotificationService.idForVaccination(1000, 3),
          lessThan(10000000));
    });
  });

  group('NotificationService.idForMedicationReminder', () {
    test('reminder 1, slot 0 → 10_000_032', () {
      expect(
          NotificationService.idForMedicationReminder(1, 0), 10000032);
    });

    test('reminder 1, slot 31 → 10_000_063', () {
      expect(
          NotificationService.idForMedicationReminder(1, 31), 10000063);
    });

    test('reminder 100, slot 0 → 10_003_200', () {
      expect(
          NotificationService.idForMedicationReminder(100, 0), 10003200);
    });

    test('different reminders get distinct ID ranges (no overlap)', () {
      // reminder 1 の slot 31 と reminder 2 の slot 0 が重ならないこと
      final int r1Last =
          NotificationService.idForMedicationReminder(1, 31);
      final int r2First =
          NotificationService.idForMedicationReminder(2, 0);
      expect(r1Last, lessThan(r2First));
    });

    test('vaccination range and medication range never overlap', () {
      // vaccinationの上限近く vs medicationの下限近く
      final int vaxMax = NotificationService.idForVaccination(2249999, 3);
      final int medMin = NotificationService.idForMedicationReminder(0, 0);
      expect(vaxMax, lessThan(medMin));
    });
  });

  // ==========================================================================
  // build 72: 予防コース
  // ==========================================================================

  group('NotificationService prevention ID ranges (build 72)', () {
    test('dose 1, slot 0 → 400_000_004', () {
      expect(NotificationService.idForPreventionDose(1, 0), 400000004);
    });

    test('course 1, slot 0 → 500_000_004', () {
      expect(NotificationService.idForPreventionCourse(1, 0), 500000004);
    });

    test('隣接する dose の slot 範囲が重ならない', () {
      expect(
        NotificationService.idForPreventionDose(1, 3),
        lessThan(NotificationService.idForPreventionDose(2, 0)),
      );
      expect(
        NotificationService.idForPreventionCourse(1, 3),
        lessThan(NotificationService.idForPreventionCourse(2, 0)),
      );
    });

    test('schedule レンジと予防レンジが重ならない', () {
      // schedule は 100M + id*32、上限想定 ~200M
      final int scheduleMax = NotificationService.idForSchedule(3124999, 6, 7);
      final int preventionMin = NotificationService.idForPreventionDose(0, 0);
      expect(scheduleMax, lessThan(preventionMin));
    });

    test('dose レンジと course レンジが現実的な範囲で重ならない', () {
      // doseId 24_999_999 までは course レンジ (500M) に届かない
      expect(
        NotificationService.idForPreventionDose(24999999, 3),
        lessThan(NotificationService.idForPreventionCourse(0, 0)),
      );
    });

    test('Android の int32 上限に収まる', () {
      // 現実的な最大 courseId (10万件) でも int32 に余裕で収まる
      expect(
        NotificationService.idForPreventionCourse(100000, 3),
        lessThan(2147483647),
      );
    });
  });


  // ==========================================================================
  // build 73: schedule ID の衝突修正
  // ==========================================================================

  group('NotificationService.idForSchedule (build 73: 幅 64)', () {
    test('★(時刻 × 曜日) の全組み合わせで ID が衝突しない', () {
      // 旧採番は通し番号 slot を渡し、scheduleDailyAt が内部で + wd して
      // いたため実 ID が base+slotIdx+wd になり、
      // (時刻0,曜日1) と (時刻1,曜日0) が同じ ID に潰れていた。
      final Set<int> ids = <int>{};
      for (int timeIndex = 0; timeIndex < 7; timeIndex++) {
        for (int wd = 0; wd < 7; wd++) {
          ids.add(NotificationService.idForSchedule(1, timeIndex, wd));
        }
        // 毎日 (weekdaySlot 7)
        ids.add(NotificationService.idForSchedule(1, timeIndex, 7));
      }
      expect(ids, hasLength(7 * 8), reason: '7 時刻 × 8 = 56 個が全て別 ID');
    });

    test('one-shot が繰り返しの ID と衝突しない', () {
      final Set<int> repeating = <int>{
        for (int ti = 0; ti < 7; ti++)
          for (int wd = 0; wd < 8; wd++)
            NotificationService.idForSchedule(1, ti, wd),
      };
      expect(repeating.contains(NotificationService.idForScheduleOneShot(1)),
          isFalse);
    });

    test('隣接する scheduleId の幅が重ならない', () {
      expect(
        NotificationService.idForScheduleOneShot(1),
        lessThan(NotificationService.idForSchedule(2, 0, 0)),
      );
      expect(
        NotificationService.idForSchedule(1, 7, 7),
        lessThan(NotificationService.idForSchedule(2, 0, 0)),
      );
    });

    test('prevention dose レンジ (400M) の手前に収まる — 境界の明示', () {
      // 100,000,000 + id * 64 < 400,000,000  ⇔  id < 4,687,500
      expect(NotificationService.idForSchedule(4687499, 7, 7),
          lessThan(400000000));
    });

    test('ワクチンレンジと重ならない', () {
      expect(
        NotificationService.idForVaccination(2249999, 3),
        lessThan(NotificationService.idForSchedule(0, 0, 0)),
      );
    });
  });

  _pendingFallbackTests();
}

// ============================================================================
// build 73: pending() の異物耐性
// ============================================================================
//
// プラグインの Dart 側マッピングは p['id'] を non-nullable int へ暗黙キャスト
// する。iOS 側は userInfo[NOTIFICATION_ID] から id を読むため、このプラグイン
// 以外が登録した pending request (FCM 由来など) は id が null になり、
// **1 件の異物でリスト全体が例外** になっていた。
//
// pending() は例外時に生チャンネルへフォールバックし、壊れた要素だけを
// 捨てて残りを返す。ここではそのフォールバック経路を直接検証する。
//
void _pendingFallbackTests() {
  const MethodChannel channel =
      MethodChannel('dexterous.com/flutter/local_notifications');

  group('pending() のフォールバック (build 73)', () {
    final List<MethodCall> calls = <MethodCall>[];

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      // pending() は初期化ガードで PetloLogger に触れる
      await PetloLogger.initialize();
    });

    setUp(() {
      calls.clear();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    void mockPending(List<Map<Object?, Object?>> items) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        calls.add(call);
        if (call.method == 'pendingNotificationRequests') return items;
        return null;
      });
    }

    test('id が null の異物が混ざっても、残りは読める', () async {
      mockPending(<Map<Object?, Object?>>[
        <Object?, Object?>{'id': 400000004, 'title': 'prevention', 'body': 'b'},
        // 他プラグイン由来: id を持たない
        <Object?, Object?>{'title': 'foreign', 'body': 'from FCM'},
        <Object?, Object?>{'id': 1000001, 'title': 'vaccination', 'body': 'b'},
      ]);

      final List<PendingNotificationRequest> got =
          await NotificationService.instance.pending();

      expect(got.map((PendingNotificationRequest r) => r.id).toList(),
          <int>[400000004, 1000001],
          reason: '異物 1 件で全滅してはいけない');
    });

    test('全件が正常なら全件返る', () async {
      mockPending(<Map<Object?, Object?>>[
        <Object?, Object?>{'id': 1, 'title': 'a', 'body': 'b'},
        <Object?, Object?>{'id': 2, 'title': 'c', 'body': 'd'},
      ]);
      final List<PendingNotificationRequest> got =
          await NotificationService.instance.pending();
      expect(got, hasLength(2));
    });

    test('空なら空が返る (失敗と区別できる状態)', () async {
      mockPending(<Map<Object?, Object?>>[]);
      final List<PendingNotificationRequest> got =
          await NotificationService.instance.pending();
      expect(got, isEmpty);
    });
  });
}
