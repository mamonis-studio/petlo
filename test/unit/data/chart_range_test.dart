// ============================================================================
// petlo - Chart Range Tests
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/models/chart_range.dart';

void main() {
  // ==========================================================================
  // ChartRange labels
  // ==========================================================================
  group('ChartRange.label', () {
    test('all 5 ranges have short labels', () {
      expect(ChartRange.month1.label, '1M');
      expect(ChartRange.month3.label, '3M');
      expect(ChartRange.month6.label, '6M');
      expect(ChartRange.year1.label, '1Y');
      expect(ChartRange.all.label, 'ALL');
    });
  });

  // ==========================================================================
  // ChartRange.isFreeAllowed
  // ==========================================================================
  group('ChartRange.isFreeAllowed', () {
    test('1M and 3M are free, others are Pro-only', () {
      expect(ChartRange.month1.isFreeAllowed, isTrue);
      expect(ChartRange.month3.isFreeAllowed, isTrue);
      expect(ChartRange.month6.isFreeAllowed, isFalse);
      expect(ChartRange.year1.isFreeAllowed, isFalse);
      expect(ChartRange.all.isFreeAllowed, isFalse);
    });
  });

  // ==========================================================================
  // ChartRange.fromDate
  // ==========================================================================
  group('ChartRange.fromDate', () {
    test('all returns null', () {
      expect(ChartRange.all.fromDate(), isNull);
    });

    test('month1 returns date roughly 1 month ago', () {
      final DateTime? from = ChartRange.month1.fromDate();
      expect(from, isNotNull);
      final Duration diff = DateTime.now().difference(from!);
      // 28-32日範囲 (月の長さ依存)
      expect(diff.inDays, greaterThanOrEqualTo(27));
      expect(diff.inDays, lessThanOrEqualTo(32));
    });

    test('month3 returns date roughly 3 months ago', () {
      final DateTime? from = ChartRange.month3.fromDate();
      expect(from, isNotNull);
      final Duration diff = DateTime.now().difference(from!);
      // 87-94日範囲
      expect(diff.inDays, greaterThanOrEqualTo(85));
      expect(diff.inDays, lessThanOrEqualTo(95));
    });

    test('year1 returns date roughly 365 days ago', () {
      final DateTime? from = ChartRange.year1.fromDate();
      expect(from, isNotNull);
      final Duration diff = DateTime.now().difference(from!);
      // 364-366日範囲
      expect(diff.inDays, greaterThanOrEqualTo(364));
      expect(diff.inDays, lessThanOrEqualTo(367));
    });
  });

  // ==========================================================================
  // ChartPoint
  // ==========================================================================
  group('ChartPoint', () {
    test('immutable construction', () {
      const ChartPoint p = ChartPoint(timestamp: 1234567890, value: 5.2);
      expect(p.timestamp, 1234567890);
      expect(p.value, 5.2);
    });
  });
}
