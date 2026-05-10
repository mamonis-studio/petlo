// ============================================================================
// petlo - Responsive Layout
// ============================================================================
//
// rev3 で確定した iPad 2カラムレイアウト対応。
//
// ブレークポイント:
//   - < 600px: iPhone (1カラム、ペットセレクター水平スクロール)
//   - 600-900px: iPad縦/横 (2カラム: 左にメニュー、右に詳細)
//   - >= 900px: iPad横ワイド (2カラム余白拡大)
//
// 使い方:
// ```dart
// ResponsiveLayout(
//   mobile: HomeScreenMobile(),
//   tablet: HomeScreenTablet(),
// )
// ```
//
// ============================================================================

import 'package:flutter/material.dart';

import '../theme/app_dimensions.dart';

enum DeviceFormFactor {
  /// 600px未満。iPhone通常サイズ、Androidスマホ
  mobile,

  /// 600-900px。iPad縦、Androidタブレット標準
  tablet,

  /// 900px以上。iPad横、大型タブレット
  tabletLarge,
}

extension DeviceFormFactorExtension on BuildContext {
  /// 現在のデバイス形態を判定
  DeviceFormFactor get formFactor {
    final double width = MediaQuery.sizeOf(this).width;
    if (width < AppDimensions.breakpointTablet) {
      return DeviceFormFactor.mobile;
    } else if (width < AppDimensions.breakpointTabletLarge) {
      return DeviceFormFactor.tablet;
    }
    return DeviceFormFactor.tabletLarge;
  }

  /// モバイル(スマホ)かどうか
  bool get isMobile => formFactor == DeviceFormFactor.mobile;

  /// タブレット(iPad/Androidタブ)かどうか
  bool get isTablet => formFactor != DeviceFormFactor.mobile;

  /// タブレットでも横向きの大画面か
  bool get isTabletLarge => formFactor == DeviceFormFactor.tabletLarge;
}

/// 画面ごとに mobile / tablet レイアウトを切り替えるWidget。
///
/// tablet が省略された場合、mobile レイアウトが両方で使われる。
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    required this.mobile,
    this.tablet,
    this.tabletLarge,
    super.key,
  });

  /// 必須。スマホ用レイアウト。
  final Widget mobile;

  /// 省略可能。タブレット用レイアウト。
  /// 指定しなければ mobile が使われる。
  final Widget? tablet;

  /// 省略可能。タブレット横用レイアウト。
  /// 指定しなければ tablet → mobile の順でフォールバック。
  final Widget? tabletLarge;

  @override
  Widget build(BuildContext context) {
    return switch (context.formFactor) {
      DeviceFormFactor.mobile => mobile,
      DeviceFormFactor.tablet => tablet ?? mobile,
      DeviceFormFactor.tabletLarge => tabletLarge ?? tablet ?? mobile,
    };
  }
}
