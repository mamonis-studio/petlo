// ============================================================================
// petlo - UserPreferences (AppThemeMode) Tests
// ============================================================================
//
// SharedPreferences 自体は Flutter テストに直接依存するので、
// Pure Dart で検証可能な enum シリアライズロジックのみテストする。
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/core/preferences/user_preferences.dart';

void main() {
  group('AppThemeMode.fromString', () {
    test('null defaults to system', () {
      expect(AppThemeMode.fromString(null), AppThemeMode.system);
    });

    test('empty string defaults to system', () {
      expect(AppThemeMode.fromString(''), AppThemeMode.system);
    });

    test('unknown string defaults to system', () {
      expect(AppThemeMode.fromString('cosmic'), AppThemeMode.system);
    });

    test('parses light', () {
      expect(AppThemeMode.fromString('light'), AppThemeMode.light);
    });

    test('parses dark', () {
      expect(AppThemeMode.fromString('dark'), AppThemeMode.dark);
    });

    test('parses system', () {
      expect(AppThemeMode.fromString('system'), AppThemeMode.system);
    });
  });

  group('AppThemeMode round-trip via .name', () {
    test('all values can be re-parsed from .name', () {
      for (final AppThemeMode mode in AppThemeMode.values) {
        final String serialized = mode.name;
        final AppThemeMode restored = AppThemeMode.fromString(serialized);
        expect(restored, mode);
      }
    });
  });

  group('AppThemeMode.toFlutter', () {
    test('light maps correctly', () {
      expect(AppThemeMode.light.toFlutter(), ThemeMode.light);
    });

    test('dark maps correctly', () {
      expect(AppThemeMode.dark.toFlutter(), ThemeMode.dark);
    });

    test('system maps correctly', () {
      expect(AppThemeMode.system.toFlutter(), ThemeMode.system);
    });

    test('all values produce a valid Flutter ThemeMode', () {
      for (final AppThemeMode mode in AppThemeMode.values) {
        final ThemeMode flutter = mode.toFlutter();
        expect(<ThemeMode>{
          ThemeMode.light,
          ThemeMode.dark,
          ThemeMode.system,
        }.contains(flutter), isTrue);
      }
    });
  });
}
