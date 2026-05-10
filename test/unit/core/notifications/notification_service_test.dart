// ============================================================================
// petlo - Notification Service Tests
// ============================================================================
//
// プラットフォーム呼び出しは Mockできないので、ここでは
// Pure Dart で計算可能な ID 採番ロジックのみテストする。
//
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/core/notifications/notification_service.dart';

void main() {
  group('NotificationService.idForVaccination', () {
    test('vaccination 1 → 1_000_001', () {
      expect(NotificationService.idForVaccination(1), 1000001);
    });

    test('vaccination 100 → 1_000_100', () {
      expect(NotificationService.idForVaccination(100), 1000100);
    });

    test('range stays under 10M (medication range)', () {
      // どのワクチンID でも 10M 未満に収まることを保証
      // (実用上、ペット1匹あたり数十件程度なので余裕)
      expect(NotificationService.idForVaccination(1000), lessThan(10000000));
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
      final int vaxMax = NotificationService.idForVaccination(8999999);
      final int medMin = NotificationService.idForMedicationReminder(0, 0);
      expect(vaxMax, lessThan(medMin));
    });
  });
}
