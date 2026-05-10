// ============================================================================
// petlo - Chart Range
// ============================================================================
//
// 推移グラフの期間切替用 enum。
//
// rev3 F-06/F-07: 体重・体温グラフ
// rev5: 無料は3ヶ月まで、Pro は全期間
//
// ============================================================================

import 'package:flutter/foundation.dart';

enum ChartRange {
  /// 直近1ヶ月
  month1,

  /// 直近3ヶ月(無料プランの上限)
  month3,

  /// 直近6ヶ月(Pro)
  month6,

  /// 直近1年(Pro)
  year1,

  /// 全期間(Pro)
  all;

  /// 表示ラベル
  String get label {
    switch (this) {
      case ChartRange.month1:
        return '1M';
      case ChartRange.month3:
        return '3M';
      case ChartRange.month6:
        return '6M';
      case ChartRange.year1:
        return '1Y';
      case ChartRange.all:
        return 'ALL';
    }
  }

  /// 無料プランで使える期間か
  bool get isFreeAllowed {
    switch (this) {
      case ChartRange.month1:
      case ChartRange.month3:
        return true;
      case ChartRange.month6:
      case ChartRange.year1:
      case ChartRange.all:
        return false;
    }
  }

  /// 期間の開始日(現在から遡って)。
  /// all の場合は null(全データ)
  DateTime? fromDate() {
    final DateTime now = DateTime.now();
    switch (this) {
      case ChartRange.month1:
        return DateTime(now.year, now.month - 1, now.day);
      case ChartRange.month3:
        return DateTime(now.year, now.month - 3, now.day);
      case ChartRange.month6:
        return DateTime(now.year, now.month - 6, now.day);
      case ChartRange.year1:
        return DateTime(now.year - 1, now.month, now.day);
      case ChartRange.all:
        return null;
    }
  }
}

/// 集計済みのチャートデータポイント
@immutable
class ChartPoint {
  const ChartPoint({required this.timestamp, required this.value});

  /// X軸: msec UTC
  final int timestamp;

  /// Y軸の値
  final double value;
}
