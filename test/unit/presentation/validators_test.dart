// ============================================================================
// petlo - Validators Tests
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/presentation/widgets/forms/validators.dart';

void main() {
  group('Validators.required', () {
    final Validator v = Validators.required();

    test('null is invalid', () => expect(v(null), isNotNull));
    test('empty string is invalid', () => expect(v(''), isNotNull));
    test('whitespace only is invalid', () => expect(v('   '), isNotNull));
    test('non-empty is valid', () => expect(v('abc'), isNull));
    test('custom message', () {
      final Validator vm = Validators.required(message: 'カスタム');
      expect(vm(''), 'カスタム');
    });
  });

  group('Validators.minLength', () {
    final Validator v = Validators.minLength(3);

    test('null is invalid', () => expect(v(null), isNotNull));
    test('shorter is invalid', () => expect(v('ab'), isNotNull));
    test('exactly min is valid', () => expect(v('abc'), isNull));
    test('longer is valid', () => expect(v('abcd'), isNull));
  });

  group('Validators.maxLength', () {
    final Validator v = Validators.maxLength(5);

    test('null is OK (use required separately)', () => expect(v(null), isNull));
    test('shorter is valid', () => expect(v('abc'), isNull));
    test('exactly max is valid', () => expect(v('abcde'), isNull));
    test('longer is invalid', () => expect(v('abcdef'), isNotNull));
  });

  group('Validators.numericOrEmpty', () {
    final Validator v = Validators.numericOrEmpty();

    test('null is OK', () => expect(v(null), isNull));
    test('empty is OK', () => expect(v(''), isNull));
    test('integer is valid', () => expect(v('123'), isNull));
    test('decimal is valid', () => expect(v('1.5'), isNull));
    test('negative is valid', () => expect(v('-42'), isNull));
    test('letters invalid', () => expect(v('abc'), isNotNull));
    test('mixed invalid', () => expect(v('1a'), isNotNull));
  });

  group('Validators.integerOrEmpty', () {
    final Validator v = Validators.integerOrEmpty();

    test('integer is valid', () => expect(v('100'), isNull));
    test('decimal is invalid', () => expect(v('1.5'), isNotNull));
  });

  group('Validators.numberRange', () {
    final Validator v = Validators.numberRange(min: 0, max: 100);

    test('within range is valid', () => expect(v('50'), isNull));
    test('lower bound included', () => expect(v('0'), isNull));
    test('upper bound included', () => expect(v('100'), isNull));
    test('below min is invalid', () => expect(v('-1'), isNotNull));
    test('above max is invalid', () => expect(v('101'), isNotNull));
    test('null is OK (optional)', () => expect(v(null), isNull));
    test('empty is OK', () => expect(v(''), isNull));
    test('non-numeric is invalid', () => expect(v('abc'), isNotNull));
  });

  group('Validators.phoneNumberOrEmpty', () {
    final Validator v = Validators.phoneNumberOrEmpty();

    test('empty is OK', () => expect(v(''), isNull));
    test('domestic format is valid', () => expect(v('090-1234-5678'), isNull));
    test('international format is valid', () => expect(v('+81 90 1234 5678'), isNull));
    test('parens format is valid', () => expect(v('(03) 1234 5678'), isNull));
    test('letters invalid', () => expect(v('abc-def'), isNotNull));
    test('too short invalid', () => expect(v('12345'), isNotNull));
  });

  group('Validators.compose', () {
    final Validator v = Validators.compose(<Validator>[
      Validators.required(message: 'A'),
      Validators.minLength(3, message: 'B'),
    ]);

    test('first failure short-circuits', () => expect(v(''), 'A'));
    test('second failure used after first passes', () => expect(v('ab'), 'B'));
    test('all pass', () => expect(v('abcd'), isNull));
  });
}
