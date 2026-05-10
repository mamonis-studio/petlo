// ============================================================================
// petlo - BackupSettings Tests
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/core/backup/backup_settings.dart';

void main() {
  // ==========================================================================
  // BackupState.fromString
  // ==========================================================================
  group('BackupState.fromString', () {
    test('null defaults to off', () {
      expect(BackupState.fromString(null), BackupState.off);
    });

    test('empty string defaults to off', () {
      expect(BackupState.fromString(''), BackupState.off);
    });

    test('unknown string defaults to off', () {
      expect(BackupState.fromString('paused'), BackupState.off);
    });

    test('parses all known values', () {
      expect(BackupState.fromString('on'), BackupState.on);
      expect(BackupState.fromString('off'), BackupState.off);
      expect(BackupState.fromString('setup'), BackupState.setupInProgress);
      expect(BackupState.fromString('error'), BackupState.error);
    });

    test('round-trip via .name', () {
      for (final BackupState s in BackupState.values) {
        expect(BackupState.fromString(s.name), s);
      }
    });
  });

  // ==========================================================================
  // BackupProvider.fromString
  // ==========================================================================
  group('BackupProvider.fromString', () {
    test('null defaults to none', () {
      expect(BackupProvider.fromString(null), BackupProvider.none);
    });

    test('parses all known values', () {
      expect(BackupProvider.fromString('iCloud'), BackupProvider.iCloud);
      expect(BackupProvider.fromString('googleDrive'),
          BackupProvider.googleDrive);
      expect(BackupProvider.fromString('cloudflareR2'),
          BackupProvider.cloudflareR2);
      expect(BackupProvider.fromString('none'), BackupProvider.none);
    });

    test('round-trip via .name', () {
      for (final BackupProvider p in BackupProvider.values) {
        expect(BackupProvider.fromString(p.name), p);
      }
    });

    test('displayLabel covers all values', () {
      for (final BackupProvider p in BackupProvider.values) {
        expect(p.displayLabel, isNotEmpty);
      }
    });
  });

  // ==========================================================================
  // BackupSettings.off (const)
  // ==========================================================================
  group('BackupSettings.off', () {
    test('state is off', () {
      expect(BackupSettings.off.state, BackupState.off);
    });

    test('provider is none', () {
      expect(BackupSettings.off.provider, BackupProvider.none);
    });

    test('isOn is false', () {
      expect(BackupSettings.off.isOn, isFalse);
    });

    test('lastSuccessAt is null', () {
      expect(BackupSettings.off.lastSuccessAt, isNull);
    });

    test('isRemindLaterActive is false', () {
      expect(BackupSettings.off.isRemindLaterActive, isFalse);
    });
  });

  // ==========================================================================
  // isOn
  // ==========================================================================
  group('BackupSettings.isOn', () {
    test('on state → true', () {
      const s = BackupSettings(
        state: BackupState.on,
        provider: BackupProvider.iCloud,
      );
      expect(s.isOn, isTrue);
    });

    test('off state → false', () {
      expect(BackupSettings.off.isOn, isFalse);
    });

    test('setupInProgress state → false', () {
      const s = BackupSettings(
        state: BackupState.setupInProgress,
        provider: BackupProvider.iCloud,
      );
      expect(s.isOn, isFalse);
    });

    test('error state → false', () {
      const s = BackupSettings(
        state: BackupState.error,
        provider: BackupProvider.iCloud,
      );
      expect(s.isOn, isFalse);
    });
  });

  // ==========================================================================
  // isRemindLaterActive (30日カウントダウン)
  // ==========================================================================
  group('BackupSettings.isRemindLaterActive', () {
    test('null remindLaterAt → not active', () {
      const s = BackupSettings.off;
      expect(s.isRemindLaterActive, isFalse);
    });

    test('1日前 → active', () {
      final s = BackupSettings.off.copyWith(
        remindLaterAt:
            DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(s.isRemindLaterActive, isTrue);
    });

    test('29日前 → active (境界内)', () {
      final s = BackupSettings.off.copyWith(
        remindLaterAt:
            DateTime.now().subtract(const Duration(days: 29)),
      );
      expect(s.isRemindLaterActive, isTrue);
    });

    test('30日前 → not active (境界外)', () {
      final s = BackupSettings.off.copyWith(
        remindLaterAt:
            DateTime.now().subtract(const Duration(days: 31)),
      );
      expect(s.isRemindLaterActive, isFalse);
    });

    test('未来日付 → active', () {
      final s = BackupSettings.off.copyWith(
        remindLaterAt: DateTime.now().add(const Duration(days: 5)),
      );
      // 未来日付でも diff は負になる → inDays が 0 以下 → < 30 → active
      expect(s.isRemindLaterActive, isTrue);
    });
  });

  // ==========================================================================
  // daysSinceLastSuccess
  // ==========================================================================
  group('BackupSettings.daysSinceLastSuccess', () {
    test('null lastSuccessAt → null', () {
      const s = BackupSettings.off;
      expect(s.daysSinceLastSuccess, isNull);
    });

    test('今 → 0', () {
      final s = BackupSettings.off.copyWith(
        lastSuccessAt: DateTime.now(),
      );
      expect(s.daysSinceLastSuccess, 0);
    });

    test('3日前 → 約3', () {
      final s = BackupSettings.off.copyWith(
        lastSuccessAt:
            DateTime.now().subtract(const Duration(days: 3, hours: 1)),
      );
      expect(s.daysSinceLastSuccess, inInclusiveRange(2, 3));
    });
  });

  // ==========================================================================
  // toMap / fromMap (round-trip)
  // ==========================================================================
  group('BackupSettings round-trip', () {
    test('off state', () {
      final restored =
          BackupSettings.fromMap(BackupSettings.off.toMap());
      expect(restored.state, BackupState.off);
      expect(restored.provider, BackupProvider.none);
      expect(restored.lastSuccessAt, isNull);
      expect(restored.lastErrorMessage, isNull);
      expect(restored.remindLaterAt, isNull);
    });

    test('full active state', () {
      final original = BackupSettings(
        state: BackupState.on,
        provider: BackupProvider.iCloud,
        lastSuccessAt: DateTime.utc(2026, 5, 1, 12, 0),
        remindLaterAt: DateTime.utc(2026, 4, 15),
      );
      final restored = BackupSettings.fromMap(original.toMap());
      expect(restored.state, BackupState.on);
      expect(restored.provider, BackupProvider.iCloud);
      expect(restored.lastSuccessAt, DateTime.utc(2026, 5, 1, 12, 0));
      expect(restored.remindLaterAt, DateTime.utc(2026, 4, 15));
    });

    test('error state with message', () {
      final original = BackupSettings(
        state: BackupState.error,
        provider: BackupProvider.googleDrive,
        lastErrorMessage: 'Network unreachable',
        lastSuccessAt: DateTime.utc(2026, 4, 28),
      );
      final restored = BackupSettings.fromMap(original.toMap());
      expect(restored.state, BackupState.error);
      expect(restored.lastErrorMessage, 'Network unreachable');
      expect(restored.lastSuccessAt, DateTime.utc(2026, 4, 28));
    });
  });

  // ==========================================================================
  // fromMap defensive parsing
  // ==========================================================================
  group('BackupSettings.fromMap defensive', () {
    test('all null map → off', () {
      final restored = BackupSettings.fromMap(<String, String?>{});
      expect(restored.state, BackupState.off);
      expect(restored.provider, BackupProvider.none);
    });

    test('invalid date strings are null (no crash)', () {
      final restored = BackupSettings.fromMap(<String, String?>{
        'state': 'on',
        'provider': 'iCloud',
        'lastSuccessAt': 'not-a-date',
        'remindLaterAt': 'also-bad',
      });
      expect(restored.state, BackupState.on);
      expect(restored.lastSuccessAt, isNull);
      expect(restored.remindLaterAt, isNull);
    });
  });

  // ==========================================================================
  // copyWith with sentinel
  // ==========================================================================
  group('BackupSettings.copyWith', () {
    test('lastSuccessAt=null can be set explicitly', () {
      final s = BackupSettings.off.copyWith(
        lastSuccessAt: DateTime.utc(2026, 1, 1),
      );
      final s2 = s.copyWith(lastSuccessAt: null);
      expect(s2.lastSuccessAt, isNull);
    });

    test('lastSuccessAt omitted preserves existing', () {
      final s = BackupSettings.off.copyWith(
        lastSuccessAt: DateTime.utc(2026, 1, 1),
      );
      final s2 = s.copyWith(state: BackupState.on);
      expect(s2.lastSuccessAt, DateTime.utc(2026, 1, 1));
      expect(s2.state, BackupState.on);
    });

    test('multiple fields update at once', () {
      final s = BackupSettings.off.copyWith(
        state: BackupState.on,
        provider: BackupProvider.googleDrive,
        lastSuccessAt: DateTime.utc(2026, 5, 5),
      );
      expect(s.state, BackupState.on);
      expect(s.provider, BackupProvider.googleDrive);
      expect(s.lastSuccessAt, DateTime.utc(2026, 5, 5));
    });
  });
}
