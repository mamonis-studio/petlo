// ============================================================================
// petlo - JoinByCodeState Tests
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/presentation/screens/groups/join_by_code_controller.dart';

void main() {
  // ==========================================================================
  // canSubmit
  // ==========================================================================
  group('JoinByCodeState.canSubmit', () {
    test('default state is not submittable', () {
      const s = JoinByCodeState();
      expect(s.canSubmit, isFalse);
    });

    test('only code (no name) is not submittable', () {
      const s = JoinByCodeState(code: '123456');
      expect(s.canSubmit, isFalse);
    });

    test('only name (no code) is not submittable', () {
      const s = JoinByCodeState(displayName: '太郎');
      expect(s.canSubmit, isFalse);
    });

    test('5-digit code is not submittable', () {
      const s = JoinByCodeState(code: '12345', displayName: '太郎');
      expect(s.canSubmit, isFalse);
    });

    test('7-digit code is not submittable', () {
      const s = JoinByCodeState(code: '1234567', displayName: '太郎');
      expect(s.canSubmit, isFalse);
    });

    test('non-numeric code is not submittable', () {
      const s = JoinByCodeState(code: '12345A', displayName: '太郎');
      expect(s.canSubmit, isFalse);
    });

    test('exactly 6 digits + name = submittable', () {
      const s = JoinByCodeState(code: '123456', displayName: '太郎');
      expect(s.canSubmit, isTrue);
    });

    test('whitespace-only name is not submittable', () {
      const s = JoinByCodeState(code: '123456', displayName: '   ');
      expect(s.canSubmit, isFalse);
    });

    test('isSubmitting=true is not submittable', () {
      const s = JoinByCodeState(
        code: '123456',
        displayName: '太郎',
        isSubmitting: true,
      );
      expect(s.canSubmit, isFalse);
    });
  });

  // ==========================================================================
  // copyWith
  // ==========================================================================
  group('JoinByCodeState.copyWith', () {
    test('errorMessage=null can be set explicitly', () {
      const s = JoinByCodeState(errorMessage: 'previous error');
      final s2 = s.copyWith(errorMessage: null);
      expect(s2.errorMessage, isNull);
    });

    test('errorMessage omitted preserves existing', () {
      const s = JoinByCodeState(errorMessage: 'preserved');
      final s2 = s.copyWith(isSubmitting: true);
      expect(s2.errorMessage, 'preserved');
      expect(s2.isSubmitting, isTrue);
    });

    test('codeError can be set then cleared', () {
      const s = JoinByCodeState();
      final s2 = s.copyWith(codeError: '不正なコードです');
      final s3 = s2.copyWith(codeError: null);
      expect(s2.codeError, '不正なコードです');
      expect(s3.codeError, isNull);
    });

    test('code update preserves other fields', () {
      const s =
          JoinByCodeState(displayName: '太郎', isSubmitting: false);
      final s2 = s.copyWith(code: '999999');
      expect(s2.code, '999999');
      expect(s2.displayName, '太郎');
    });
  });

  // ==========================================================================
  // JoinResult
  // ==========================================================================
  group('JoinResult', () {
    test('basic construction', () {
      const r = JoinResult(
        groupRemoteId: 'abc-123',
        groupName: 'お父さん家族',
        memberDisplayNames: <String>['お父さん', '太郎', '花子'],
      );
      expect(r.groupRemoteId, 'abc-123');
      expect(r.groupName, 'お父さん家族');
      expect(r.memberDisplayNames.length, 3);
    });
  });

  // ==========================================================================
  // JoinByCodeOutcome enum
  // ==========================================================================
  group('JoinByCodeOutcome', () {
    test('all values are unique', () {
      final Set<JoinByCodeOutcome> set =
          JoinByCodeOutcome.values.toSet();
      expect(set.length, JoinByCodeOutcome.values.length);
    });

    test('expected values present', () {
      expect(JoinByCodeOutcome.values, containsAll(<JoinByCodeOutcome>[
        JoinByCodeOutcome.success,
        JoinByCodeOutcome.invalid,
        JoinByCodeOutcome.alreadyUsed,
        JoinByCodeOutcome.full,
        JoinByCodeOutcome.alreadyMember,
        JoinByCodeOutcome.limitReached,
      ]));
    });
  });
}
