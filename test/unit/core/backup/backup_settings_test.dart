// ============================================================================
// petlo - BackupSettings Tests (build 62)
// ============================================================================
//
// クラウド連携プレースホルダ撤廃に伴い、BackupState / BackupProvider は廃止。
// 新モデルは「最終エクスポート時刻」+「リマインダー抑止時刻」のみ。
//
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/core/backup/backup_settings.dart';

void main() {
  group('BackupSettings.initial', () {
    test('lastExportAt is null', () {
      expect(BackupSettings.initial.lastExportAt, isNull);
    });

    test('remindLaterAt is null', () {
      expect(BackupSettings.initial.remindLaterAt, isNull);
    });

    test('isRemindLaterActive is false', () {
      expect(BackupSettings.initial.isRemindLaterActive, isFalse);
    });

    test('daysSinceLastExport is null', () {
      expect(BackupSettings.initial.daysSinceLastExport, isNull);
    });
  });

  group('isRemindLaterActive (30 day window)', () {
    test('null → not active', () {
      expect(BackupSettings.initial.isRemindLaterActive, isFalse);
    });

    test('1 day ago → active', () {
      final BackupSettings s = BackupSettings.initial.copyWith(
        remindLaterAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(s.isRemindLaterActive, isTrue);
    });

    test('29 days ago → still active', () {
      final BackupSettings s = BackupSettings.initial.copyWith(
        remindLaterAt: DateTime.now().subtract(const Duration(days: 29)),
      );
      expect(s.isRemindLaterActive, isTrue);
    });

    test('31 days ago → no longer active', () {
      final BackupSettings s = BackupSettings.initial.copyWith(
        remindLaterAt: DateTime.now().subtract(const Duration(days: 31)),
      );
      expect(s.isRemindLaterActive, isFalse);
    });
  });

  group('daysSinceLastExport', () {
    test('null lastExportAt → null', () {
      expect(BackupSettings.initial.daysSinceLastExport, isNull);
    });

    test('now → 0', () {
      final BackupSettings s = BackupSettings.initial.copyWith(
        lastExportAt: DateTime.now(),
      );
      expect(s.daysSinceLastExport, 0);
    });

    test('3 days ago → ~3', () {
      final BackupSettings s = BackupSettings.initial.copyWith(
        lastExportAt:
            DateTime.now().subtract(const Duration(days: 3, hours: 1)),
      );
      expect(s.daysSinceLastExport, inInclusiveRange(2, 3));
    });
  });

  group('toMap / fromMap round-trip', () {
    test('initial state', () {
      final BackupSettings restored =
          BackupSettings.fromMap(BackupSettings.initial.toMap());
      expect(restored.lastExportAt, isNull);
      expect(restored.remindLaterAt, isNull);
    });

    test('both fields populated', () {
      final BackupSettings original = BackupSettings(
        lastExportAt: DateTime.utc(2026, 5, 1, 12, 0),
        remindLaterAt: DateTime.utc(2026, 4, 15),
      );
      final BackupSettings restored =
          BackupSettings.fromMap(original.toMap());
      expect(restored.lastExportAt, DateTime.utc(2026, 5, 1, 12, 0));
      expect(restored.remindLaterAt, DateTime.utc(2026, 4, 15));
    });

    test('invalid date strings parse to null (no crash)', () {
      final BackupSettings restored =
          BackupSettings.fromMap(<String, String?>{
        'lastExportAt': 'not-a-date',
        'remindLaterAt': 'also-bad',
      });
      expect(restored.lastExportAt, isNull);
      expect(restored.remindLaterAt, isNull);
    });
  });

  group('copyWith (sentinel pattern)', () {
    test('explicit null clears lastExportAt', () {
      final BackupSettings s = BackupSettings.initial.copyWith(
        lastExportAt: DateTime.utc(2026, 1, 1),
      );
      final BackupSettings s2 = s.copyWith(lastExportAt: null);
      expect(s2.lastExportAt, isNull);
    });

    test('omitted parameter preserves existing value', () {
      final BackupSettings s = BackupSettings.initial.copyWith(
        lastExportAt: DateTime.utc(2026, 1, 1),
        remindLaterAt: DateTime.utc(2026, 2, 1),
      );
      final BackupSettings s2 =
          s.copyWith(remindLaterAt: DateTime.utc(2026, 3, 1));
      expect(s2.lastExportAt, DateTime.utc(2026, 1, 1));
      expect(s2.remindLaterAt, DateTime.utc(2026, 3, 1));
    });
  });
}
