// ============================================================================
// petlo - Startup Trace
// ============================================================================
//
// 起動シーケンスの各処理にかかった時間を記録する (build 73)。
//
// なぜログではなく永続化なのか:
//   PetloLogger は DevelopmentFilter を使うので **debug ビルドでしか出ない**。
//   一方この端末では debug が JIT の制約で起動できず、実機の計測は profile /
//   release でしか行えない。そこで結果を UserPreferences に書き、
//   開発者設定から読む (旧 ID 移行カウンタや通知の割り当てレポートと同じ方式)。
//
// 使い方:
//   await StartupTrace.measure('initializeDateFormatting', () async { ... });
//   ...
//   await StartupTrace.markFirstFrame();   // 初回フレーム描画後
//
// ============================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../preferences/user_preferences.dart';

abstract final class StartupTrace {
  StartupTrace._();

  static final Stopwatch _sinceMain = Stopwatch();
  static final Map<String, int> _durations = <String, int>{};
  static int? _firstFrameMs;

  /// main() の先頭で呼ぶ。
  static void begin() {
    _sinceMain
      ..reset()
      ..start();
    _durations.clear();
    _firstFrameMs = null;
  }

  /// [body] の所要時間を [label] として記録する。
  /// 例外は握り潰さない。計測のために挙動を変えないため。
  static Future<T> measure<T>(String label, Future<T> Function() body) async {
    final Stopwatch sw = Stopwatch()..start();
    try {
      return await body();
    } finally {
      sw.stop();
      _durations[label] = sw.elapsedMilliseconds;
    }
  }

  /// 同期処理版
  static T measureSync<T>(String label, T Function() body) {
    final Stopwatch sw = Stopwatch()..start();
    try {
      return body();
    } finally {
      sw.stop();
      _durations[label] = sw.elapsedMilliseconds;
    }
  }

  /// 初回フレーム描画時点の経過時間を記録して永続化する。
  static Future<void> markFirstFrame() async {
    _firstFrameMs = _sinceMain.elapsedMilliseconds;
    await _persist();
  }

  /// runApp より後に走る処理 (通知の再割り当てなど) を追記する。
  static Future<void> addAfterFirstFrame(String label, int millis) async {
    _durations[label] = millis;
    await _persist();
  }

  static Future<void> _persist() async {
    try {
      await UserPreferences.instance.setStartupTrace(<String, dynamic>{
        'firstFrameMs': _firstFrameMs,
        'totalMs': _sinceMain.elapsedMilliseconds,
        'steps': Map<String, int>.of(_durations),
      });
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('StartupTrace persist failed: $e');
      }
    }
  }

  /// 保存済みの計測結果を読む (開発者設定用)。
  static StartupTraceReport? read() {
    final Map<String, dynamic>? raw =
        UserPreferences.instance.startupTrace;
    if (raw == null) return null;
    return StartupTraceReport.fromJson(raw);
  }
}

/// 永続化された計測結果
@immutable
class StartupTraceReport {
  const StartupTraceReport({
    required this.steps,
    required this.firstFrameMs,
    required this.totalMs,
  });

  /// ラベル → 所要ミリ秒。記録順を保つ
  final Map<String, int> steps;

  /// main() から初回フレーム描画までの経過ミリ秒
  final int? firstFrameMs;

  /// 最後に永続化した時点の経過ミリ秒
  final int totalMs;

  /// 遅い順に並べ替えたもの
  List<MapEntry<String, int>> get slowestFirst {
    final List<MapEntry<String, int>> list = steps.entries.toList()
      ..sort((MapEntry<String, int> a, MapEntry<String, int> b) =>
          b.value.compareTo(a.value));
    return list;
  }

  static StartupTraceReport? fromJson(Map<String, dynamic> json) {
    try {
      final Map<String, dynamic> raw =
          (json['steps'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      return StartupTraceReport(
        steps: <String, int>{
          for (final MapEntry<String, dynamic> e in raw.entries)
            e.key: (e.value as num).toInt(),
        },
        firstFrameMs: (json['firstFrameMs'] as num?)?.toInt(),
        totalMs: (json['totalMs'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode(<String, dynamic>{
        'steps': steps,
        'firstFrameMs': firstFrameMs,
        'totalMs': totalMs,
      });
}
