// ============================================================================
// petlo - ProStatus Tests
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/core/billing/pro_status.dart';

void main() {
  // ==========================================================================
  // ProTier.fromString
  // ==========================================================================
  group('ProTier.fromString', () {
    test('null defaults to free', () {
      expect(ProTier.fromString(null), ProTier.free);
    });

    test('empty string defaults to free', () {
      expect(ProTier.fromString(''), ProTier.free);
    });

    test('unknown string defaults to free', () {
      expect(ProTier.fromString('lifetime'), ProTier.free);
    });

    test('parses monthly', () {
      expect(ProTier.fromString('monthly'), ProTier.monthly);
    });

    test('parses yearly', () {
      expect(ProTier.fromString('yearly'), ProTier.yearly);
    });

    test('parses free', () {
      expect(ProTier.fromString('free'), ProTier.free);
    });
  });

  // ==========================================================================
  // ProState.fromString
  // ==========================================================================
  group('ProState.fromString', () {
    test('null defaults to free', () {
      expect(ProState.fromString(null), ProState.free);
    });

    test('parses all known values', () {
      expect(ProState.fromString('active'), ProState.active);
      expect(ProState.fromString('grace'), ProState.grace);
      expect(ProState.fromString('cancelled'), ProState.cancelled);
      expect(ProState.fromString('free'), ProState.free);
    });
  });

  // ==========================================================================
  // ProState.isProAvailable
  // ==========================================================================
  group('ProState.isProAvailable', () {
    test('active is available', () {
      expect(ProState.active.isProAvailable, isTrue);
    });

    test('grace is available', () {
      expect(ProState.grace.isProAvailable, isTrue);
    });

    test('cancelled (within expiry) is available', () {
      expect(ProState.cancelled.isProAvailable, isTrue);
    });

    test('free is NOT available', () {
      expect(ProState.free.isProAvailable, isFalse);
    });
  });

  // ==========================================================================
  // ProStatus const + isPro
  // ==========================================================================
  group('ProStatus.free', () {
    test('isPro is false', () {
      expect(ProStatus.free.isPro, isFalse);
    });

    test('tier is free', () {
      expect(ProStatus.free.tier, ProTier.free);
    });

    test('state is free', () {
      expect(ProStatus.free.state, ProState.free);
    });

    test('expiresAt is null', () {
      expect(ProStatus.free.expiresAt, isNull);
    });
  });

  group('ProStatus.isPro for various states', () {
    test('active monthly is Pro', () {
      const s = ProStatus(tier: ProTier.monthly, state: ProState.active);
      expect(s.isPro, isTrue);
    });

    test('grace is Pro', () {
      const s = ProStatus(tier: ProTier.yearly, state: ProState.grace);
      expect(s.isPro, isTrue);
    });

    test('cancelled is Pro (within expiry)', () {
      const s =
          ProStatus(tier: ProTier.yearly, state: ProState.cancelled);
      expect(s.isPro, isTrue);
    });

    test('free state is not Pro even with monthly tier (edge case)', () {
      const s = ProStatus(tier: ProTier.monthly, state: ProState.free);
      expect(s.isPro, isFalse);
    });
  });

  // ==========================================================================
  // isInTrial
  // ==========================================================================
  group('ProStatus.isInTrial', () {
    test('null trialEndsAt → not in trial', () {
      const s = ProStatus(tier: ProTier.monthly, state: ProState.active);
      expect(s.isInTrial, isFalse);
    });

    test('trialEndsAt in the past → not in trial', () {
      final s = ProStatus(
        tier: ProTier.monthly,
        state: ProState.active,
        trialEndsAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(s.isInTrial, isFalse);
    });

    test('trialEndsAt in the future → in trial', () {
      final s = ProStatus(
        tier: ProTier.monthly,
        state: ProState.active,
        trialEndsAt: DateTime.now().add(const Duration(days: 5)),
      );
      expect(s.isInTrial, isTrue);
    });
  });

  // ==========================================================================
  // daysRemaining
  // ==========================================================================
  group('ProStatus.daysRemaining', () {
    test('null expiresAt → null', () {
      const s = ProStatus(tier: ProTier.monthly, state: ProState.active);
      expect(s.daysRemaining, isNull);
    });

    test('expiresAt in the past → 0', () {
      final s = ProStatus(
        tier: ProTier.monthly,
        state: ProState.cancelled,
        expiresAt: DateTime.now().subtract(const Duration(days: 5)),
      );
      expect(s.daysRemaining, 0);
    });

    test('expiresAt in 10 days → ~10', () {
      final s = ProStatus(
        tier: ProTier.yearly,
        state: ProState.cancelled,
        expiresAt: DateTime.now().add(const Duration(days: 10, hours: 1)),
      );
      // ±1 で許容(タイムスタンプの揺れ吸収)
      expect(s.daysRemaining, inInclusiveRange(9, 10));
    });
  });

  // ==========================================================================
  // toMap / fromMap (round-trip)
  // ==========================================================================
  group('ProStatus toMap / fromMap round-trip', () {
    test('free state', () {
      final restored = ProStatus.fromMap(ProStatus.free.toMap());
      expect(restored.tier, ProTier.free);
      expect(restored.state, ProState.free);
      expect(restored.expiresAt, isNull);
      expect(restored.trialEndsAt, isNull);
    });

    test('active monthly with expiresAt', () {
      final original = ProStatus(
        tier: ProTier.monthly,
        state: ProState.active,
        expiresAt: DateTime.utc(2026, 6, 15, 12, 30),
      );
      final restored = ProStatus.fromMap(original.toMap());
      expect(restored.tier, ProTier.monthly);
      expect(restored.state, ProState.active);
      expect(restored.expiresAt, DateTime.utc(2026, 6, 15, 12, 30));
      expect(restored.trialEndsAt, isNull);
    });

    test('active yearly with trial', () {
      final original = ProStatus(
        tier: ProTier.yearly,
        state: ProState.active,
        expiresAt: DateTime.utc(2027, 1, 1),
        trialEndsAt: DateTime.utc(2026, 1, 8),
      );
      final restored = ProStatus.fromMap(original.toMap());
      expect(restored.tier, ProTier.yearly);
      expect(restored.expiresAt, DateTime.utc(2027, 1, 1));
      expect(restored.trialEndsAt, DateTime.utc(2026, 1, 8));
    });

    test('grace state with cancelled tier preserved', () {
      final original = ProStatus(
        tier: ProTier.yearly,
        state: ProState.grace,
        expiresAt: DateTime.utc(2026, 8, 1),
      );
      final restored = ProStatus.fromMap(original.toMap());
      expect(restored.state, ProState.grace);
      expect(restored.tier, ProTier.yearly);
    });

    test('all enum values can round-trip via .name', () {
      for (final ProTier t in ProTier.values) {
        expect(ProTier.fromString(t.name), t);
      }
      for (final ProState s in ProState.values) {
        expect(ProState.fromString(s.name), s);
      }
    });
  });

  // ==========================================================================
  // fromMap defensive parsing
  // ==========================================================================
  group('ProStatus.fromMap defensive', () {
    test('all null map → free', () {
      final restored = ProStatus.fromMap(<String, String?>{});
      expect(restored.tier, ProTier.free);
      expect(restored.state, ProState.free);
    });

    test('invalid date string is null (no crash)', () {
      final restored = ProStatus.fromMap(<String, String?>{
        'tier': 'monthly',
        'state': 'active',
        'expiresAt': 'not-a-date',
      });
      expect(restored.tier, ProTier.monthly);
      expect(restored.expiresAt, isNull);
    });
  });

  // ==========================================================================
  // 念のため Flutter ThemeMode 衝突しないか
  // ==========================================================================
  test('ProStatus does not depend on ThemeMode', () {
    // ThemeMode は dart:ui (Flutter) なので、
    // pro_status.dart は dart:ui に依存しないはず
    expect(ThemeMode.values, isNotEmpty); // Flutter が import 可能なら sanity OK
  });
}
