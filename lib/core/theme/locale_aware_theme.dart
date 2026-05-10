// ============================================================================
// petlo - Locale-aware Theme Helpers
// ============================================================================
//
// rev5.3で確定: 中国語(zh)ロケール時は Noto Serif/Sans SC を主フォントとして
// 使う(Frauncesは中国語グリフを持たないため)。
//
// 通常の `fontFamilyFallback` だけでは「最初の字はFraunces、次の字は中国語フォント」
// と混在してしまうため、**中国語ロケールの場合は明示的にプライマリーを切替**する。
//
// 仕組み:
//   1. AppTypography は通常 Fraunces プライマリ + NotoSerifSC fallback で構築
//   2. 中国語ロケール時のみ、本ヘルパーが TextStyle を全部書き換えて
//      NotoSerifSC をプライマリにする
//
// 使用箇所: MaterialApp の builder で Theme をラップする想定
//
// ============================================================================

import 'package:flutter/material.dart';

import 'app_typography.dart';

abstract final class LocaleAwareTheme {
  LocaleAwareTheme._();

  /// 中国語ロケール時はAppTypographyを書き換えて返す。
  /// それ以外はそのまま。
  static AppTypography adaptForLocale(AppTypography base, Locale? locale) {
    if (locale == null || locale.languageCode != 'zh') {
      return base;
    }
    // 中国語: セリフ系はNotoSerifSC, サンセリフ系はNotoSansSCを主に
    return base.copyWith(
      heroName: _swapFamily(base.heroName, 'NotoSerifSC'),
      pageTitle: _swapFamily(base.pageTitle, 'NotoSerifSC'),
      numericLarge: _swapFamily(base.numericLarge, 'NotoSerifSC'),
      numericMedium: _swapFamily(base.numericMedium, 'NotoSerifSC'),
      aiResponseBody: _swapFamily(base.aiResponseBody, 'NotoSerifSC'),
      bodyLarge: _swapFamily(base.bodyLarge, 'NotoSansSC'),
      bodyMedium: _swapFamily(base.bodyMedium, 'NotoSansSC'),
      bodySmall: _swapFamily(base.bodySmall, 'NotoSansSC'),
      button: _swapFamily(base.button, 'NotoSansSC'),
      sectionTitle: _swapFamily(base.sectionTitle, 'NotoSansSC'),
      eyebrow: _swapFamily(base.eyebrow, 'NotoSansSC'),
      metaSmall: _swapFamily(base.metaSmall, 'NotoSansSC'),
    );
  }

  /// MaterialApp の builder で使うラッパー。
  /// Theme を取得し、ロケールに応じて AppTypography 拡張を差し替えて再構築する。
  static Widget applyLocaleAdaptation({
    required BuildContext context,
    required Widget child,
  }) {
    final ThemeData theme = Theme.of(context);
    final Locale locale = Localizations.localeOf(context);

    final AppTypography? base = theme.extension<AppTypography>();
    if (base == null) {
      // テーマにAppTypographyが入っていない場合はそのまま
      return child;
    }

    final AppTypography adapted = adaptForLocale(base, locale);
    if (identical(adapted, base)) {
      // 中国語以外: 何もせず返す
      return child;
    }

    final List<ThemeExtension<dynamic>> updatedExtensions =
        theme.extensions.values.map((ThemeExtension<dynamic> ext) {
      if (ext is AppTypography) {
        return adapted;
      }
      return ext;
    }).toList();

    final ThemeData updated = theme.copyWith(extensions: updatedExtensions);

    return Theme(data: updated, child: child);
  }

  static TextStyle _swapFamily(TextStyle base, String newPrimary) {
    return base.copyWith(
      fontFamily: newPrimary,
      // fallbackは元のまま (Fraunces / Manrope / JetBrainsMono を含む)
      // 中国語に無いラテン文字は元のフォントが描画する
      fontFamilyFallback: <String>[
        if (base.fontFamily != null) base.fontFamily!,
        ...?base.fontFamilyFallback,
      ].where((String f) => f != newPrimary).toList(),
      // fontVariations は維持
    );
  }
}
