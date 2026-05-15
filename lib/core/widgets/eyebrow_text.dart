// ============================================================================
// petlo - EyebrowText
// ============================================================================
//
// "TODAY, MAY 4" や "SECTION II · LIFE" のような小さな見出し用テキスト。
// JetBrainsMono、tracked、uppercase。
//
// build 16: small / medium / large の 3 サイズに展開。
//   small  = 10pt  既存サイズ。サブ要素 / 補助ラベル。
//   medium = 12pt  サブセクション §。
//   large  = 14pt  各トップタブの先頭 § (Editorial-style)。
//
// モックの `<div class="eyebrow">` 相当。
//
// ============================================================================

import 'package:flutter/material.dart';

import '../theme/app_typography.dart';

enum EyebrowSize {
  small,
  medium,
  large,
}

class EyebrowText extends StatelessWidget {
  const EyebrowText(
    this.text, {
    this.size = EyebrowSize.small,
    this.color,
    this.textAlign = TextAlign.start,
    super.key,
  });

  final String text;
  final EyebrowSize size;

  /// 色を上書きしたい場合(警告色等)。
  /// 省略時は AppTypography.eyebrow の色 (fgMuted) が使われる。
  final Color? color;

  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final TextStyle base = AppTypography.of(context).eyebrow;
    final double fontSize = switch (size) {
      EyebrowSize.small => 10,
      EyebrowSize.medium => 12,
      EyebrowSize.large => 14,
    };
    final TextStyle style = base.copyWith(
      fontSize: fontSize,
      letterSpacing: fontSize * 0.2,
      color: color,
    );

    // uppercase化はFlutterで自動できないので明示変換
    return Text(
      text.toUpperCase(),
      style: style,
      textAlign: textAlign,
    );
  }
}
