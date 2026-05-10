// ============================================================================
// petlo - Theme Tests
// ============================================================================
//
// AppTheme/AppColors/AppTypographyの動作確認。
// デザイントークンの一貫性を保証する。
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/core/theme/app_colors.dart';
import 'package:petlo/core/theme/app_dimensions.dart';
import 'package:petlo/core/theme/app_durations.dart';
import 'package:petlo/core/theme/app_theme.dart';
import 'package:petlo/core/theme/app_typography.dart';

void main() {
  group('AppTheme', () {
    test('light() returns Material 3 ThemeData with light brightness', () {
      final ThemeData theme = AppTheme.light();
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
    });

    test('dark() returns Material 3 ThemeData with dark brightness', () {
      final ThemeData theme = AppTheme.dark();
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, const Color(0xFF0A0A0A));
    });

    test('light() exposes AppColors extension', () {
      final ThemeData theme = AppTheme.light();
      final AppColors? colors = theme.extension<AppColors>();
      expect(colors, isNotNull);
      expect(colors!.fg, const Color(0xFF0A0A0A));
    });

    test('dark() exposes AppColors extension with dark values', () {
      final ThemeData theme = AppTheme.dark();
      final AppColors? colors = theme.extension<AppColors>();
      expect(colors, isNotNull);
      expect(colors!.fg, const Color(0xFFF5F2EC));
    });

    test('both themes expose AppTypography extension', () {
      final ThemeData light = AppTheme.light();
      final ThemeData dark = AppTheme.dark();
      expect(light.extension<AppTypography>(), isNotNull);
      expect(dark.extension<AppTypography>(), isNotNull);
    });
  });

  group('AppColors', () {
    test('lerp returns valid color set when t=0.5', () {
      const AppColors light = AppColors.light;
      const AppColors dark = AppColors.dark;
      final AppColors lerped = light.lerp(dark, 0.5) as AppColors;
      expect(lerped.fg, isNot(light.fg));
      expect(lerped.fg, isNot(dark.fg));
    });

    test('lerp with same instance returns the same colors', () {
      const AppColors light = AppColors.light;
      final AppColors lerped = light.lerp(light, 0.5) as AppColors;
      expect(lerped.fg, light.fg);
      expect(lerped.bg, light.bg);
    });

    test('copyWith preserves untouched fields', () {
      const AppColors light = AppColors.light;
      final AppColors copy = light.copyWith(fg: const Color(0xFF123456));
      expect(copy.fg, const Color(0xFF123456));
      expect(copy.bg, light.bg);
      expect(copy.line, light.line);
    });

    testWidgets('AppColors.of(context) retrieves colors from theme',
        (WidgetTester tester) async {
      late AppColors fetched;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (BuildContext context) {
              fetched = AppColors.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(fetched.fg, AppColors.light.fg);
    });
  });

  group('AppTypography', () {
    test('light() heroName uses Fraunces italic', () {
      final AppTypography typo = AppTypography.light(
        fg: const Color(0xFF000000),
        fgMuted: const Color(0xFF666666),
      );
      expect(typo.heroName.fontFamily, 'Fraunces');
      expect(typo.heroName.fontStyle, FontStyle.italic);
      expect(typo.heroName.fontSize, 64);
    });

    test('light() sectionTitle uses JetBrainsMono', () {
      final AppTypography typo = AppTypography.light(
        fg: const Color(0xFF000000),
        fgMuted: const Color(0xFF666666),
      );
      expect(typo.sectionTitle.fontFamily, 'JetBrainsMono');
      expect(typo.sectionTitle.fontSize, 10);
    });

    test('all styles include NotoSerifSC or NotoSansSC fallback', () {
      final AppTypography typo = AppTypography.light(
        fg: const Color(0xFF000000),
        fgMuted: const Color(0xFF666666),
      );
      // フラウンス系
      expect(typo.heroName.fontFamilyFallback, contains('NotoSerifSC'));
      expect(typo.numericLarge.fontFamilyFallback, contains('NotoSerifSC'));
      // サンセリフ系
      expect(typo.bodyMedium.fontFamilyFallback, contains('NotoSansSC'));
      // モノ系
      expect(typo.eyebrow.fontFamilyFallback, contains('NotoSansSC'));
    });

    test('lerp produces intermediate styles', () {
      final AppTypography light = AppTypography.light(
        fg: const Color(0xFF000000),
        fgMuted: const Color(0xFF666666),
      );
      final AppTypography dark = AppTypography.dark(
        fg: const Color(0xFFFFFFFF),
        fgMuted: const Color(0xFF888888),
      );
      final AppTypography lerped = light.lerp(dark, 0.5) as AppTypography;
      expect(lerped.heroName, isNotNull);
    });
  });

  group('AppDimensions', () {
    test('iPad breakpoint is 600', () {
      expect(AppDimensions.breakpointTablet, 600);
    });

    test('topBarTotalHeight is sum of brandBar + groupSelector + petSelector',
        () {
      expect(
        AppDimensions.topBarTotalHeight,
        AppDimensions.brandBarHeight +
            AppDimensions.groupSelectorHeight +
            AppDimensions.petSelectorHeight,
      );
    });

    test('icon stroke width is 1.4 (rev5.3)', () {
      expect(AppDimensions.strokeIcon, 1.4);
    });
  });

  group('AppDurations', () {
    test('petSwitch is 300ms (rev5.1)', () {
      expect(AppDurations.petSwitch.inMilliseconds, 300);
    });

    test('groupSwitch is 400ms (rev5.3 — heavier than pet switch)', () {
      expect(AppDurations.groupSwitch.inMilliseconds, 400);
    });

    test('aiThinkingDot is 400ms (rev5.5)', () {
      expect(AppDurations.aiThinkingDot.inMilliseconds, 400);
    });

    test('snackBar is 3 seconds (rev5.4 Undo)', () {
      expect(AppDurations.snackBar.inSeconds, 3);
    });
  });
}
