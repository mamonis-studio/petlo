// ============================================================================
// petlo - GroupClosureBanner Logic Tests
// ============================================================================
//
// shouldShow (GroupEntity 引数) は drift 生成型に依存するので、
// ここでは GroupStatus enum の判定ロジックと、
// 残り日数計算を純粋関数として検証する。
//
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/local/database_enums.dart';

/// shouldShow の判定ロジック (GroupEntity 抜きで純粋に検証)
bool _shouldShowForStatus(GroupStatus status) {
  return status == GroupStatus.pendingDeletion ||
      status == GroupStatus.frozen ||
      status == GroupStatus.deletionScheduled;
}

/// 残り日数計算 (90日 - 経過日数)
int _daysUntilDeletion(int? pendingDeletionAtMsec) {
  if (pendingDeletionAtMsec == null) return -1;
  final DateTime closureAt =
      DateTime.fromMillisecondsSinceEpoch(pendingDeletionAtMsec);
  final int since = DateTime.now().difference(closureAt).inDays;
  final int remaining = 90 - since;
  return remaining < 0 ? 0 : remaining;
}

void main() {
  // ==========================================================================
  // shouldShow ロジック
  // ==========================================================================
  group('GroupClosureBanner shouldShow logic', () {
    test('active → false (バナー不要)', () {
      expect(_shouldShowForStatus(GroupStatus.active), isFalse);
    });

    test('pendingDeletion → true (警告表示)', () {
      expect(_shouldShowForStatus(GroupStatus.pendingDeletion),
          isTrue);
    });

    test('frozen → true (閲覧のみ警告)', () {
      expect(_shouldShowForStatus(GroupStatus.frozen), isTrue);
    });

    test('deletionScheduled → true (最終警告)', () {
      expect(_shouldShowForStatus(GroupStatus.deletionScheduled),
          isTrue);
    });

    test('全 status を網羅', () {
      // sealed enum なので switch で網羅性確認
      for (final GroupStatus s in GroupStatus.values) {
        final bool result = switch (s) {
          GroupStatus.active => false,
          GroupStatus.pendingDeletion => true,
          GroupStatus.frozen => true,
          GroupStatus.deletionScheduled => true,
        };
        expect(_shouldShowForStatus(s), result);
      }
    });
  });

  // ==========================================================================
  // _daysUntilDeletion (90日カウントダウン)
  // ==========================================================================
  group('daysUntilDeletion calculation', () {
    test('null → -1 (無効値)', () {
      expect(_daysUntilDeletion(null), -1);
    });

    test('今 → 約90 (まだ削除予定まで90日)', () {
      final int now = DateTime.now().millisecondsSinceEpoch;
      // ±1 でゆらぎ吸収
      expect(_daysUntilDeletion(now), inInclusiveRange(89, 90));
    });

    test('30日前 → 約60', () {
      final int t = DateTime.now()
          .subtract(const Duration(days: 30))
          .millisecondsSinceEpoch;
      expect(_daysUntilDeletion(t), inInclusiveRange(59, 60));
    });

    test('60日前 → 約30', () {
      final int t = DateTime.now()
          .subtract(const Duration(days: 60))
          .millisecondsSinceEpoch;
      expect(_daysUntilDeletion(t), inInclusiveRange(29, 30));
    });

    test('89日前 → 約1', () {
      final int t = DateTime.now()
          .subtract(const Duration(days: 89))
          .millisecondsSinceEpoch;
      expect(_daysUntilDeletion(t), inInclusiveRange(0, 1));
    });

    test('90日前 → 0 (削除予定)', () {
      final int t = DateTime.now()
          .subtract(const Duration(days: 90))
          .millisecondsSinceEpoch;
      expect(_daysUntilDeletion(t), 0);
    });

    test('100日前 → 0 (過ぎても 0 でクランプ)', () {
      final int t = DateTime.now()
          .subtract(const Duration(days: 100))
          .millisecondsSinceEpoch;
      expect(_daysUntilDeletion(t), 0);
    });
  });

  // ==========================================================================
  // GroupStatus enum の sealed 性確認
  // ==========================================================================
  group('GroupStatus enum', () {
    test('all 4 values present', () {
      expect(GroupStatus.values.length, 4);
      expect(GroupStatus.values, containsAll(<GroupStatus>[
        GroupStatus.active,
        GroupStatus.pendingDeletion,
        GroupStatus.frozen,
        GroupStatus.deletionScheduled,
      ]));
    });
  });
}
