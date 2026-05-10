// ============================================================================
// petlo - CreateGroupState Tests
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/presentation/screens/groups/create_group_controller.dart';

void main() {
  // ==========================================================================
  // defaults
  // ==========================================================================
  group('CreateGroupState defaults', () {
    test('name is empty', () {
      const s = CreateGroupState();
      expect(s.name, '');
    });

    test('not submitting initially', () {
      const s = CreateGroupState();
      expect(s.isSubmitting, isFalse);
    });

    test('no errors initially', () {
      const s = CreateGroupState();
      expect(s.errorMessage, isNull);
      expect(s.nameError, isNull);
    });
  });

  // ==========================================================================
  // copyWith
  // ==========================================================================
  group('CreateGroupState.copyWith', () {
    test('name can be updated', () {
      const s = CreateGroupState();
      final s2 = s.copyWith(name: '山田家');
      expect(s2.name, '山田家');
    });

    test('errorMessage=null can be set explicitly', () {
      const s = CreateGroupState(errorMessage: 'old');
      final s2 = s.copyWith(errorMessage: null);
      expect(s2.errorMessage, isNull);
    });

    test('errorMessage omitted preserves existing', () {
      const s = CreateGroupState(errorMessage: 'kept');
      final s2 = s.copyWith(isSubmitting: true);
      expect(s2.errorMessage, 'kept');
    });

    test('isSubmitting toggle', () {
      const s = CreateGroupState();
      final s2 = s.copyWith(isSubmitting: true);
      final s3 = s2.copyWith(isSubmitting: false);
      expect(s2.isSubmitting, isTrue);
      expect(s3.isSubmitting, isFalse);
    });

    test('nameError sentinel preserves value', () {
      const s = CreateGroupState(nameError: 'kept');
      final s2 = s.copyWith(name: 'new name');
      expect(s2.nameError, 'kept'); // copyWith で省略 → 維持
    });
  });

  // ==========================================================================
  // CreateGroupOutcome enum
  // ==========================================================================
  group('CreateGroupOutcome', () {
    test('all values are unique', () {
      final Set<CreateGroupOutcome> set =
          CreateGroupOutcome.values.toSet();
      expect(set.length, CreateGroupOutcome.values.length);
    });

    test('expected values present', () {
      expect(CreateGroupOutcome.values, containsAll(<CreateGroupOutcome>[
        CreateGroupOutcome.success,
        CreateGroupOutcome.validationFailed,
        CreateGroupOutcome.proRequired,
        CreateGroupOutcome.limitReached,
        CreateGroupOutcome.network,
        CreateGroupOutcome.serverError,
        CreateGroupOutcome.unknown,
      ]));
    });
  });
}
