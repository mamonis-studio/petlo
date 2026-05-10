// ============================================================================
// petlo - Calendar Tests
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/models/day_summary.dart';
import 'package:petlo/presentation/providers/calendar_provider.dart';

void main() {
  // ==========================================================================
  // DaySummary
  // ==========================================================================
  group('DaySummary', () {
    test('empty has total 0 and hasAny=false', () {
      const DaySummary s = DaySummary();
      expect(s.total, 0);
      expect(s.hasAny, isFalse);
      expect(s.hasHealth, isFalse);
      expect(s.hasUrgent, isFalse);
      expect(s.hasDaily, isFalse);
      expect(s.hasMemory, isFalse);
    });

    test('total sums all categories', () {
      const DaySummary s = DaySummary(
        meals: 3,
        poops: 1,
        pees: 2,
        vomits: 0,
        weights: 1,
        temperatures: 1,
        visits: 0,
        vaccinations: 1,
        diaries: 1,
      );
      expect(s.total, 10);
    });

    test('hasUrgent triggers on vomits or visits', () {
      expect(const DaySummary(vomits: 1).hasUrgent, isTrue);
      expect(const DaySummary(visits: 1).hasUrgent, isTrue);
      expect(const DaySummary(meals: 100).hasUrgent, isFalse);
    });

    test('hasHealth triggers on weight/temp/visit/vaccination', () {
      expect(const DaySummary(weights: 1).hasHealth, isTrue);
      expect(const DaySummary(temperatures: 1).hasHealth, isTrue);
      expect(const DaySummary(visits: 1).hasHealth, isTrue);
      expect(const DaySummary(vaccinations: 1).hasHealth, isTrue);
      expect(const DaySummary(meals: 1, diaries: 1).hasHealth, isFalse);
    });

    test('hasDaily triggers on meal/poop/pee', () {
      expect(const DaySummary(meals: 1).hasDaily, isTrue);
      expect(const DaySummary(poops: 1).hasDaily, isTrue);
      expect(const DaySummary(pees: 1).hasDaily, isTrue);
      expect(const DaySummary(vomits: 1).hasDaily, isFalse);
    });

    test('hasMemory triggers only on diaries', () {
      expect(const DaySummary(diaries: 1).hasMemory, isTrue);
      expect(const DaySummary(meals: 100).hasMemory, isFalse);
    });
  });

  // ==========================================================================
  // YearMonth
  // ==========================================================================
  group('YearMonth', () {
    test('prev rolls over year correctly', () {
      const YearMonth jan = YearMonth(2025, 1);
      expect(jan.prev, const YearMonth(2024, 12));
    });

    test('next rolls over year correctly', () {
      const YearMonth dec = YearMonth(2025, 12);
      expect(dec.next, const YearMonth(2026, 1));
    });

    test('ofNow returns current year/month', () {
      final DateTime now = DateTime.now();
      final YearMonth ym = YearMonth.ofNow();
      expect(ym.year, now.year);
      expect(ym.month, now.month);
    });

    test('rangeUtcMsec covers exactly the month', () {
      const YearMonth may = YearMonth(2025, 5);
      final ({int from, int to}) r = may.rangeUtcMsec;
      final DateTime fromDt = DateTime.fromMillisecondsSinceEpoch(r.from);
      final DateTime toDt = DateTime.fromMillisecondsSinceEpoch(r.to);
      // toUtc().millisecondsSinceEpoch から戻すとUTCで2025-05-01 00:00:00相当
      // ローカルタイムゾーンに変換されて表示されるが、関係としては
      // from + 31日 = to (Mayは31日)
      final Duration diff = toDt.difference(fromDt);
      expect(diff.inDays, 31);
    });

    test('equality / hashCode for use as family key', () {
      const YearMonth a = YearMonth(2025, 5);
      const YearMonth b = YearMonth(2025, 5);
      const YearMonth c = YearMonth(2025, 6);
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('toString format', () {
      expect(const YearMonth(2025, 5).toString(), '2025-05');
      expect(const YearMonth(2025, 12).toString(), '2025-12');
    });
  });
}
