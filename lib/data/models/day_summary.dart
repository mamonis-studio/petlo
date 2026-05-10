// ============================================================================
// petlo - Day Summary
// ============================================================================
//
// カレンダー表示用、1日分の記録カウント。
//
// 各記録種別ごとの件数を保持し、合計や「何かある日」判定に使う。
// rev5.2: カレンダーUIで dot indicator として可視化。
//
// ============================================================================

import 'package:flutter/foundation.dart';

@immutable
class DaySummary {
  const DaySummary({
    this.meals = 0,
    this.poops = 0,
    this.pees = 0,
    this.vomits = 0,
    this.weights = 0,
    this.temperatures = 0,
    this.visits = 0,
    this.vaccinations = 0,
    this.diaries = 0,
  });

  final int meals;
  final int poops;
  final int pees;
  final int vomits;
  final int weights;
  final int temperatures;
  final int visits;
  final int vaccinations;
  final int diaries;

  /// 全記録の合計件数
  int get total =>
      meals + poops + pees + vomits + weights + temperatures + visits +
      vaccinations + diaries;

  /// その日に何かしらの記録があるか
  bool get hasAny => total > 0;

  /// 健康記録カテゴリ(体重/体温/通院/ワクチン)
  bool get hasHealth =>
      weights > 0 || temperatures > 0 || visits > 0 || vaccinations > 0;

  /// 緊急性のある記録があるか(嘔吐 or 通院)
  bool get hasUrgent => vomits > 0 || visits > 0;

  /// 日常記録カテゴリ(食事/排泄)
  bool get hasDaily =>
      meals > 0 || poops > 0 || pees > 0;

  /// 思い出系(日記)
  bool get hasMemory => diaries > 0;

  static const DaySummary empty = DaySummary();
}
