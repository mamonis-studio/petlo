// ============================================================================
// petlo - EyebrowText
// ============================================================================
//
// "TODAY, MAY 4" や "SECTION II · LIFE" のような小さな見出し用テキスト。
// JetBrainsMono、tracked、uppercase。
//
// モックの `<div class="eyebrow">` 相当。
//
// ============================================================================

import 'package:flutter/material.dart';

import '../theme/app_typography.dart';

class EyebrowText extends StatelessWidget {
  const EyebrowText(
    this.text, {
    this.color,
    this.textAlign = TextAlign.start,
    super.key,
  });

  final String text;

  /// 色を上書きしたい場合(警告色等)。
  /// 省略時は AppTypography.eyebrow の色 (fgMuted) が使われる。
  final Color? color;

  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final TextStyle base = AppTypography.of(context).eyebrow;
    final TextStyle style = color != null ? base.copyWith(color: color) : base;

    // uppercase化はFlutterで自動できないので明示変換
    return Text(
      text.toUpperCase(),
      style: style,
      textAlign: textAlign,
    );
  }
}
