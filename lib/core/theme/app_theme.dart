// ============================================================================
// petlo - Theme (Full version)
// ============================================================================
//
// Light/Dark両対応のThemeDataを構築する。
//
// 設計方針:
//   - Material 3 ベース (useMaterial3: true)
//   - エディトリアル振り (角丸ゼロ、影なし、罫線多用)
//   - すべてのデザイントークンは extensions で配信
//
// 使い方:
//   - 配色:     AppColors.of(context).fg
//   - 文字:     AppTypography.of(context).heroName
//   - 余白:     AppDimensions.paddingPage
//   - アニメ:   AppDurations.petSwitch
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_dimensions.dart';
import 'app_typography.dart';

abstract final class AppTheme {
  AppTheme._();

  // ============================================================================
  // Light Theme
  // ============================================================================
  static ThemeData light() {
    const AppColors colors = AppColors.light;
    final AppTypography typo = AppTypography.light(
      fg: colors.fg,
      fgMuted: colors.fgMuted,
    );

    return _buildTheme(
      brightness: Brightness.light,
      colors: colors,
      typo: typo,
    );
  }

  // ============================================================================
  // Dark Theme
  // ============================================================================
  static ThemeData dark() {
    const AppColors colors = AppColors.dark;
    final AppTypography typo = AppTypography.dark(
      fg: colors.fg,
      fgMuted: colors.fgMuted,
    );

    return _buildTheme(
      brightness: Brightness.dark,
      colors: colors,
      typo: typo,
    );
  }

  // ============================================================================
  // Internal builder (共通処理)
  // ============================================================================
  static ThemeData _buildTheme({
    required Brightness brightness,
    required AppColors colors,
    required AppTypography typo,
  }) {
    final ColorScheme colorScheme = ColorScheme(
      brightness: brightness,
      // Material 3 のColorScheme。
      // petloの基本配色を Material のスロットにマッピング。
      // 多くの画面で直接 AppColors を参照するので、ここはフォールバック用途。
      primary: colors.fg,
      onPrimary: colors.bg,
      secondary: colors.fgMuted,
      onSecondary: colors.bg,
      error: colors.accentDanger,
      onError: colors.bg,
      surface: colors.bg,
      onSurface: colors.fg,
      surfaceContainerHighest: colors.bgSoft,
      outline: colors.line,
      outlineVariant: colors.line,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.bg,

      // === Typography ===
      // Material標準のTextThemeにもマッピングしておく(他ライブラリが使う可能性)
      textTheme: TextTheme(
        displayLarge: typo.heroName,
        displayMedium: typo.pageTitle,
        displaySmall: typo.pageTitle,
        headlineMedium: typo.pageTitle,
        titleLarge: typo.numericMedium,
        titleMedium: typo.bodyLarge,
        bodyLarge: typo.bodyLarge,
        bodyMedium: typo.bodyMedium,
        bodySmall: typo.bodySmall,
        labelLarge: typo.button,
        labelMedium: typo.eyebrow,
        labelSmall: typo.metaSmall,
      ),

      // === Component themes ===

      // AppBar (基本使わない、Scaffoldを直接組む方針)
      appBarTheme: AppBarTheme(
        backgroundColor: colors.bg,
        foregroundColor: colors.fg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        systemOverlayStyle: brightness == Brightness.light
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
        titleTextStyle: typo.bodyLarge,
      ),

      // Scaffold (SnackBar)
      snackBarTheme: const SnackBarThemeData(
        // SnackBarは別途 widget で作る、デフォルトテーマは控えめに
        elevation: 0,
      ),

      // Buttons - すべて角丸ゼロ、影なし
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.fg,
          foregroundColor: colors.bg,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
          textStyle: typo.button,
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingPage,
            vertical: AppDimensions.paddingCompact,
          ),
          minimumSize: const Size(0, AppDimensions.minTapTarget),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.fg,
          side: BorderSide(color: colors.fg, width: AppDimensions.strokeLine),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
          textStyle: typo.button,
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingPage,
            vertical: AppDimensions.paddingCompact,
          ),
          minimumSize: const Size(0, AppDimensions.minTapTarget),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.fg,
          textStyle: typo.bodyMedium,
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingTight,
            vertical: AppDimensions.paddingTight,
          ),
          minimumSize: const Size(0, AppDimensions.minTapTarget),
        ),
      ),

      // Inputs
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.paddingCompact,
          vertical: AppDimensions.paddingCompact,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: colors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: colors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: colors.fg),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: colors.accentDanger),
        ),
        hintStyle: typo.bodyMedium.copyWith(color: colors.fgMuted),
        labelStyle: typo.eyebrow,
      ),

      // Dividers
      dividerTheme: DividerThemeData(
        color: colors.line,
        thickness: AppDimensions.strokeLine,
        space: 0,
      ),

      // Switches (お別れ通知ON/OFFなどで使用)
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return colors.bg;
          }
          return colors.bg;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return colors.accentSoft;
          }
          return colors.fgMuted;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      // Card (基本使わない、Containerを直接使う)
      cardTheme: CardThemeData(
        color: colors.bg,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: colors.line),
        ),
      ),

      // Bottom sheets (グループ切替モーダル等で使用)
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.bg,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.zero,
          ),
        ),
        modalBackgroundColor: colors.bg,
      ),

      // Dialogs
      dialogTheme: DialogThemeData(
        backgroundColor: colors.bg,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
        ),
        titleTextStyle: typo.pageTitle.copyWith(fontSize: 24),
        contentTextStyle: typo.bodyMedium,
      ),

      // === Splash & ripple ===
      // Material風のリップルは雑誌風UIに合わない、控えめに
      splashFactory: NoSplash.splashFactory,
      highlightColor: colors.bgSoft,

      // === Page transitions ===
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),

      // === Extensions (petlo独自) ===
      extensions: <ThemeExtension<dynamic>>[
        colors,
        typo,
      ],
    );
  }
}
