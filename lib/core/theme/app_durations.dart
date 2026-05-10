// ============================================================================
// petlo - Animation Duration Tokens
// ============================================================================
//
// アニメーション時間を一箇所に集約。
// 一貫した「リズム感」を全画面で実現する。
//
// petloの基本リズム:
//   - 即時反応: 150ms
//   - 通常切替: 300ms
//   - 重い切替(ペット): 300ms
//   - もっと重い切替(グループ): 400ms
//   - 強調系の登場: 400ms
//
// すべてのCurveは Curves.easeOutCubic を基本にする (上品で速すぎない)。
// 急すぎず、もたつかない。
//
// ============================================================================

import 'package:flutter/material.dart';

abstract final class AppDurations {
  AppDurations._();

  // ===== 基本durations =====
  static const Duration instant = Duration(milliseconds: 150);
  static const Duration short = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 300);
  static const Duration long = Duration(milliseconds: 400);
  static const Duration extraLong = Duration(milliseconds: 600);

  // ===== 用途別 =====

  /// ペット切替時のクロスフェード (rev5.1で300ms確定)
  static const Duration petSwitch = Duration(milliseconds: 300);

  /// グループ切替時のクロスフェード (rev5.3で400ms確定、心理的に「重い」)
  static const Duration groupSwitch = Duration(milliseconds: 400);

  /// AIメッセージのフェードイン
  static const Duration aiMessageFadeIn = Duration(milliseconds: 300);

  /// AI thinking dotのアニメーション間隔 (rev5.5)
  static const Duration aiThinkingDot = Duration(milliseconds: 400);

  /// AI thinking dotの1サイクル全体 (3つのドット × 400 + 余白)
  static const Duration aiThinkingCycle = Duration(milliseconds: 1600);

  /// Snackbar 表示時間 (rev5.4 Undo)
  static const Duration snackBar = Duration(seconds: 3);

  /// Snackbar フェード時間
  static const Duration snackBarFade = Duration(milliseconds: 200);

  /// モーダル開閉
  static const Duration modal = Duration(milliseconds: 350);

  /// ボタンタップ視覚フィードバック
  static const Duration tapFeedback = Duration(milliseconds: 100);

  /// 画面ロード時のフェードイン (1要素ずつずらす)
  static const Duration screenLoadStaggerStep = Duration(milliseconds: 40);

  /// AIタイムアウト
  static const Duration aiTimeout = Duration(seconds: 30);

  // ===== 推奨Curve =====

  /// 標準の上品なeasing。多くの画面遷移で使用。
  static const Curve standardCurve = Curves.easeOutCubic;

  /// やや弾力ある (オンボーディングのスワイプ用など)
  static const Curve emphasizedCurve = Curves.easeOutQuint;

  /// 等速 (ローディング系)
  static const Curve linearCurve = Curves.linear;
}
