// ============================================================================
// petlo - EyebrowText
// ============================================================================
//
// "TODAY, MAY 4" や "SECTION II · LIFE" のような小さな見出し用テキスト。
// JetBrainsMono、tracked、uppercase。
//
// build 16: small / medium / large の 3 サイズに展開。
//   small  = 10pt  既存サイズ。サブ要素 / 補助ラベル。
//   medium = 13pt  サブセクション §。
//   large  = 22pt  各トップタブの先頭 § (Editorial title 相当、w700)。
// build 17: large を 14→22pt に引き上げ「タイトル」として機能させる。
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
      EyebrowSize.medium => 13,
      EyebrowSize.large => 22,
    };
    final FontWeight weight = switch (size) {
      EyebrowSize.large => FontWeight.w700,
      _ => FontWeight.w500,
    };
    // large 時は tracking をやや締める (大型 caps は 0.2em だと開きすぎる)
    final double trackingFactor = switch (size) {
      EyebrowSize.large => 0.12,
      _ => 0.2,
    };
    final TextStyle style = base.copyWith(
      fontSize: fontSize,
      fontWeight: weight,
      letterSpacing: fontSize * trackingFactor,
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
