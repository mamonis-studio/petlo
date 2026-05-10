// ============================================================================
// petlo - Typography Tokens
// ============================================================================
//
// rev5.5仕様§10で確定したフォント体系。
//
// 3つのフォントファミリー:
//   - Fraunces       — 見出し、装飾、感情を込めたいテキスト(セリフ、可変軸)
//   - Manrope        — 本文、ボタン(サンセリフ、読みやすい)
//   - JetBrains Mono — eyebrow、メタ情報、コード(等幅)
//
// 中国語ロケール時は Noto Serif/Sans SC にフォールバック。
//
// ============================================================================

import 'package:flutter/material.dart';

/// petlo のすべてのテキストスタイル。
///
/// 使用時は `AppTypography.of(context).heroName` のようにアクセス。
/// テキストの「役割」で命名している (display1, h1のような汎用名は使わない)。
@immutable
class AppTypography extends ThemeExtension<AppTypography> {
  const AppTypography({
    required this.heroName,
    required this.pageTitle,
    required this.sectionTitle,
    required this.bodyLarge,
    required this.bodyMedium,
    required this.bodySmall,
    required this.eyebrow,
    required this.metaSmall,
    required this.button,
    required this.numericLarge,
    required this.numericMedium,
    required this.aiResponseBody,
  });

  /// ホーム画面の超大セリフ italic。"Taro" のようなペット名表示。
  /// Fraunces 64px italic, opsz 144, SOFT 100, WONK 1
  final TextStyle heroName;

  /// 各画面のページタイトル。"A diary, day by day."
  /// Fraunces 44-48px italic
  final TextStyle pageTitle;

  /// セクション見出し小。"Quick · Log" など。
  /// JetBrains Mono 10px, letterSpacing 0.2em, uppercase
  final TextStyle sectionTitle;

  /// 本文大 (16px Manrope)。
  final TextStyle bodyLarge;

  /// 標準本文 (14px Manrope)。
  final TextStyle bodyMedium;

  /// 補助本文 (12-13px Manrope)。
  final TextStyle bodySmall;

  /// "TODAY, MAY 4" のようなeyebrow。
  /// JetBrains Mono 10px, letterSpacing 0.2em, uppercase
  final TextStyle eyebrow;

  /// "VOL. 04 · ISSUE 128" のような最小メタ情報。
  /// JetBrains Mono 9px, letterSpacing 0.15em
  final TextStyle metaSmall;

  /// ボタンラベル。
  /// Manrope 13px bold, letterSpacing 0.2em, uppercase
  final TextStyle button;

  /// 大数値表示。"6.2 kg" の "6.2" 部分。
  /// Fraunces 96px light, opsz 144
  final TextStyle numericLarge;

  /// 中数値。"32 days" の "32" 部分。
  /// Fraunces 20px semibold
  final TextStyle numericMedium;

  /// AI応答本文。普通の本文より大きく、雑誌コラム風。
  /// Fraunces 18px regular, opsz 24, SOFT 50
  final TextStyle aiResponseBody;

  // ===== Locale-aware fontFamilyFallback =====
  // 中国語ロケール時のフォールバックフォント

  /// セリフ系 (Fraunces) のフォールバック。
  static const List<String> _serifFallback = <String>['NotoSerifSC'];

  /// サンセリフ系 (Manrope) のフォールバック。
  static const List<String> _sansFallback = <String>['NotoSansSC'];

  /// JetBrains Mono のフォールバック。等幅は中国語に適切な代替が少ない、
  /// NotoSansSCを併用 (CJK文字部分のみフォールバック)
  static const List<String> _monoFallback = <String>['NotoSansSC'];

  // ===== Light テーマ用 =====

  static AppTypography light({required Color fg, required Color fgMuted}) {
    return AppTypography(
      heroName: TextStyle(
        fontFamily: 'Fraunces',
        fontFamilyFallback: _serifFallback,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w400,
        fontSize: 48,
        letterSpacing: -48 * 0.04, // -0.04em
        height: 0.95,
        color: fg,
        fontVariations: const <FontVariation>[
          FontVariation('opsz', 144),
          FontVariation('SOFT', 100),
          FontVariation('WONK', 1),
        ],
      ),
      pageTitle: TextStyle(
        fontFamily: 'Fraunces',
        fontFamilyFallback: _serifFallback,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w400,
        fontSize: 44,
        letterSpacing: -44 * 0.04,
        height: 0.95,
        color: fg,
        fontVariations: const <FontVariation>[
          FontVariation('opsz', 144),
          FontVariation('SOFT', 100),
          FontVariation('WONK', 1),
        ],
      ),
      sectionTitle: TextStyle(
        fontFamily: 'JetBrainsMono',
        fontFamilyFallback: _monoFallback,
        fontWeight: FontWeight.w500,
        fontSize: 10,
        letterSpacing: 10 * 0.2, // 0.2em
        color: fgMuted,
      ),
      bodyLarge: TextStyle(
        fontFamily: 'Manrope',
        fontFamilyFallback: _sansFallback,
        fontWeight: FontWeight.w400,
        fontSize: 16,
        height: 1.5,
        color: fg,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'Manrope',
        fontFamilyFallback: _sansFallback,
        fontWeight: FontWeight.w400,
        fontSize: 14,
        height: 1.4,
        color: fg,
      ),
      bodySmall: TextStyle(
        fontFamily: 'Manrope',
        fontFamilyFallback: _sansFallback,
        fontWeight: FontWeight.w400,
        fontSize: 13,
        height: 1.4,
        color: fgMuted,
      ),
      eyebrow: TextStyle(
        fontFamily: 'JetBrainsMono',
        fontFamilyFallback: _monoFallback,
        fontWeight: FontWeight.w500,
        fontSize: 10,
        letterSpacing: 10 * 0.2,
        color: fgMuted,
      ),
      metaSmall: TextStyle(
        fontFamily: 'JetBrainsMono',
        fontFamilyFallback: _monoFallback,
        fontWeight: FontWeight.w500,
        fontSize: 9,
        letterSpacing: 9 * 0.15,
        color: fgMuted,
      ),
      button: TextStyle(
        fontFamily: 'Manrope',
        fontFamilyFallback: _sansFallback,
        fontWeight: FontWeight.w700,
        fontSize: 13,
        letterSpacing: 13 * 0.2,
        color: fg,
      ),
      numericLarge: TextStyle(
        fontFamily: 'Fraunces',
        fontFamilyFallback: _serifFallback,
        fontWeight: FontWeight.w300,
        fontSize: 96,
        letterSpacing: -96 * 0.05,
        height: 0.85,
        color: fg,
        fontVariations: const <FontVariation>[
          FontVariation('opsz', 144),
        ],
      ),
      numericMedium: TextStyle(
        fontFamily: 'Fraunces',
        fontFamilyFallback: _serifFallback,
        fontWeight: FontWeight.w600,
        fontSize: 20,
        letterSpacing: -20 * 0.02,
        color: fg,
      ),
      aiResponseBody: TextStyle(
        fontFamily: 'Fraunces',
        fontFamilyFallback: _serifFallback,
        fontWeight: FontWeight.w400,
        fontSize: 18,
        height: 1.45,
        letterSpacing: -18 * 0.01,
        color: fg,
        fontVariations: const <FontVariation>[
          FontVariation('opsz', 24),
          FontVariation('SOFT', 50),
        ],
      ),
    );
  }

  // ===== Dark テーマ用 =====
  // 構造はlightと同じ、色だけfg/fgMutedで変える
  static AppTypography dark({required Color fg, required Color fgMuted}) {
    return AppTypography.light(fg: fg, fgMuted: fgMuted);
  }

  static AppTypography of(BuildContext context) {
    final AppTypography? typo = Theme.of(context).extension<AppTypography>();
    if (typo == null) {
      throw FlutterError(
        'AppTypography extension not found in current Theme.',
      );
    }
    return typo;
  }

  // ===== ThemeExtension implementation =====

  @override
  AppTypography copyWith({
    TextStyle? heroName,
    TextStyle? pageTitle,
    TextStyle? sectionTitle,
    TextStyle? bodyLarge,
    TextStyle? bodyMedium,
    TextStyle? bodySmall,
    TextStyle? eyebrow,
    TextStyle? metaSmall,
    TextStyle? button,
    TextStyle? numericLarge,
    TextStyle? numericMedium,
    TextStyle? aiResponseBody,
  }) {
    return AppTypography(
      heroName: heroName ?? this.heroName,
      pageTitle: pageTitle ?? this.pageTitle,
      sectionTitle: sectionTitle ?? this.sectionTitle,
      bodyLarge: bodyLarge ?? this.bodyLarge,
      bodyMedium: bodyMedium ?? this.bodyMedium,
      bodySmall: bodySmall ?? this.bodySmall,
      eyebrow: eyebrow ?? this.eyebrow,
      metaSmall: metaSmall ?? this.metaSmall,
      button: button ?? this.button,
      numericLarge: numericLarge ?? this.numericLarge,
      numericMedium: numericMedium ?? this.numericMedium,
      aiResponseBody: aiResponseBody ?? this.aiResponseBody,
    );
  }

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) {
      return this;
    }
    return AppTypography(
      heroName: TextStyle.lerp(heroName, other.heroName, t)!,
      pageTitle: TextStyle.lerp(pageTitle, other.pageTitle, t)!,
      sectionTitle: TextStyle.lerp(sectionTitle, other.sectionTitle, t)!,
      bodyLarge: TextStyle.lerp(bodyLarge, other.bodyLarge, t)!,
      bodyMedium: TextStyle.lerp(bodyMedium, other.bodyMedium, t)!,
      bodySmall: TextStyle.lerp(bodySmall, other.bodySmall, t)!,
      eyebrow: TextStyle.lerp(eyebrow, other.eyebrow, t)!,
      metaSmall: TextStyle.lerp(metaSmall, other.metaSmall, t)!,
      button: TextStyle.lerp(button, other.button, t)!,
      numericLarge: TextStyle.lerp(numericLarge, other.numericLarge, t)!,
      numericMedium: TextStyle.lerp(numericMedium, other.numericMedium, t)!,
      aiResponseBody: TextStyle.lerp(aiResponseBody, other.aiResponseBody, t)!,
    );
  }
}
