// ============================================================================
// petlo - Accessibility Extensions
// ============================================================================
//
// アクセシビリティ周辺のヘルパー。
// VoiceOver / TalkBack 対応を全画面で楽にする。
//
// rev5 仕様で確定:
//   - VoiceOver / TalkBack 対応
//   - Dynamic Type 対応
//   - 4.5:1 コントラスト比保証
//   - 色覚異常配慮(色 + 文字ラベル併記)
//
// ============================================================================

import 'package:flutter/material.dart';

extension TextScalerExtension on BuildContext {
  /// 現在のtextScaleFactorを取得 (Dynamic Type対応)
  double get textScaleFactor =>
      MediaQuery.textScalerOf(this).scale(1).clamp(0.85, 2.0);

  /// 巨大文字モードかどうかの判定 (1.5以上を「巨大」とみなす)
  bool get isLargeText => textScaleFactor >= 1.5;
}

extension MediaQueryExtension on BuildContext {
  /// セーフエリアを除いた画面幅
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// セーフエリアを除いた画面高さ
  double get screenHeight => MediaQuery.sizeOf(this).height;

  /// ステータスバー高さ
  double get statusBarHeight => MediaQuery.paddingOf(this).top;

  /// ホームインジケーター/ナビゲーションバー高さ
  double get bottomInset => MediaQuery.paddingOf(this).bottom;
}

/// 装飾的な要素(線画ドット等)をスクリーンリーダーから隠すためのラッパー
class DecorativeElement extends StatelessWidget {
  const DecorativeElement({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(child: child);
  }
}

/// セマンティックグループ化ヘルパー。
/// カレンダーや複雑なレイアウトを1つのSemanticsノードに集約する場合に使う。
///
/// 例:
/// ```dart
/// SemanticGroup(
///   label: 'May 2026, 8 plans this month',
///   child: CalendarGrid(...),
/// )
/// ```
class SemanticGroup extends StatelessWidget {
  const SemanticGroup({
    required this.label,
    required this.child,
    this.hint,
    this.button = false,
    super.key,
  });

  final String label;
  final String? hint;
  final bool button;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        label: label,
        hint: hint,
        button: button,
        excludeSemantics: true,
        child: child,
      ),
    );
  }
}
