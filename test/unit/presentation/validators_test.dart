// ============================================================================
// petlo - Validators Tests
// ============================================================================
// build 61: API 変更追従。Validators は AppLocalizations を第1引数で受ける
// 設計に変わったため、test では `await AppLocalizations.delegate.load(Locale('ja'))`
// で実 l10n インスタンスを生成して渡す。
// ============================================================================

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/l10n/generated/app_localizations.dart';
import 'package:petlo/presentation/widgets/forms/validators.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    l10n = await AppLocalizations.delegate.load(const Locale('ja'));
  });

  group('Validators.required', () {
    test('null is invalid',
        () => expect(Validators.required(l10n)(null), isNotNull));
    test('empty string is invalid',
        () => expect(Validators.required(l10n)(''), isNotNull));
    test('whitespace only is invalid',
        () => expect(Validators.required(l10n)('   '), isNotNull));
    test('non-empty is valid',
        () => expect(Validators.required(l10n)('abc'), isNull));
    test('custom message', () {
      final Validator vm = Validators.required(l10n, message: 'カスタム');
      expect(vm(''), 'カスタム');
    });
  });

  group('Validators.minLength', () {
    test('null is invalid',
        () => expect(Validators.minLength(l10n, 3)(null), isNotNull));
    test('shorter is invalid',
        () => expect(Validators.minLength(l10n, 3)('ab'), isNotNull));
    test('exactly min is valid',
        () => expect(Validators.minLength(l10n, 3)('abc'), isNull));
    test('longer is valid',
        () => expect(Validators.minLength(l10n, 3)('abcd'), isNull));
  });

  group('Validators.maxLength', () {
    test('null is OK (use required separately)',
        () => expect(Validators.maxLength(l10n, 5)(null), isNull));
    test('shorter is valid',
        () => expect(Validators.maxLength(l10n, 5)('abc'), isNull));
    test('exactly max is valid',
        () => expect(Validators.maxLength(l10n, 5)('abcde'), isNull));
    test('longer is invalid',
        () => expect(Validators.maxLength(l10n, 5)('abcdef'), isNotNull));
  });

  group('Validators.numericOrEmpty', () {
    test('null is OK',
        () => expect(Validators.numericOrEmpty(l10n)(null), isNull));
    test('empty is OK',
        () => expect(Validators.numericOrEmpty(l10n)(''), isNull));
    test('integer is valid',
        () => expect(Validators.numericOrEmpty(l10n)('123'), isNull));
    test('decimal is valid',
        () => expect(Validators.numericOrEmpty(l10n)('1.5'), isNull));
    test('negative is valid',
        () => expect(Validators.numericOrEmpty(l10n)('-42'), isNull));
    test('letters invalid',
        () => expect(Validators.numericOrEmpty(l10n)('abc'), isNotNull));
    test('mixed invalid',
        () => expect(Validators.numericOrEmpty(l10n)('1a'), isNotNull));
  });

  group('Validators.integerOrEmpty', () {
    test('integer is valid',
        () => expect(Validators.integerOrEmpty(l10n)('100'), isNull));
    test('decimal is invalid',
        () => expect(Validators.integerOrEmpty(l10n)('1.5'), isNotNull));
  });

  group('Validators.numberRange', () {
    Validator v() => Validators.numberRange(l10n, min: 0, max: 100);
    test('within range is valid', () => expect(v()('50'), isNull));
    test('lower bound included', () => expect(v()('0'), isNull));
    test('upper bound included', () => expect(v()('100'), isNull));
    test('below min is invalid', () => expect(v()('-1'), isNotNull));
    test('above max is invalid', () => expect(v()('101'), isNotNull));
    test('null is OK (optional)', () => expect(v()(null), isNull));
    test('empty is OK', () => expect(v()(''), isNull));
    test('non-numeric is invalid', () => expect(v()('abc'), isNotNull));
  });

  group('Validators.phoneNumberOrEmpty', () {
    Validator v() => Validators.phoneNumberOrEmpty(l10n);
    test('empty is OK', () => expect(v()(''), isNull));
    test('domestic format is valid',
        () => expect(v()('090-1234-5678'), isNull));
    test('international format is valid',
        () => expect(v()('+81 90 1234 5678'), isNull));
    test('parens format is valid', () => expect(v()('(03) 1234 5678'), isNull));
    test('letters invalid', () => expect(v()('abc-def'), isNotNull));
    test('too short invalid', () => expect(v()('12345'), isNotNull));
  });

  group('Validators.compose', () {
    Validator v() => Validators.compose(<Validator>[
          Validators.required(l10n, message: 'A'),
          Validators.minLength(l10n, 3, message: 'B'),
        ]);
    test('first failure short-circuits', () => expect(v()(''), 'A'));
    test('second failure used after first passes', () => expect(v()('ab'), 'B'));
    test('all pass', () => expect(v()('abcd'), isNull));
  });
}
