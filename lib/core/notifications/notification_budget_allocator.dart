// ============================================================================
// petlo - Notification Budget Allocator
// ============================================================================
//
// iOS は同時に保持できるローカル通知を 64 件に制限する。上限を超えると
// **古いものから黙って捨てられる**。build 72 までは 3 系統
// (ワクチン / schedule / 予防) がそれぞれ自分のバジェットしか見ておらず、
// 合計を見ている者が居なかった。ワクチンに至っては上限が無かった。
//
// 実測 (Phase C): ワクチンが 48/64 を占領し、schedule が押し出された。
//
// ここは **3 系統の合計を見る唯一の場所**。純粋関数なのでプラットフォームに
// 触れず、配分だけをテストできる。
//
// ============================================================================
// 配分方式 — 最低保証枠 + 余りは時間軸で融通
// ============================================================================
//
//   Tier 1  各系統に最低保証枠を確保する (rank 昇順)
//             vaccination 16 / schedule 16 / prevention 12   小計 44
//
//   Tier 2  残り 20 を系統問わず fireAt 昇順で先着
//             Tier 1 を使い切らなかった系統の余りもこの枠に合流する
//
// 合計 64 を絶対に超えない。
//
// 系統内の優先順位 (rank) は各 planner が決める:
//   - vaccination / schedule … 直近順 (3 か月先より明日を優先)
//   - prevention             … 優先度ラダー (v2 §5.4)。
//                               検査リマインドを先頭 4 件に置くことで、
//                               どこで打ち切られても予約枠が保たれる
//
// ============================================================================

import 'package:flutter/foundation.dart';

/// 通知を出す系統。バジェットはこの単位で最低保証する。
enum NotificationSystem { vaccination, schedule, prevention }

/// 実行方法。Allocator は配分だけを見るが、Executor が必要とする。
enum NotificationKind {
  /// 単発 (scheduleOneTime)
  oneTime,

  /// 毎日 / 毎週の繰り返し (scheduleDailyAt)
  dailyRepeat,
}

/// 積みたい通知 1 件。プラットフォームには触れない純粋なデータ。
@immutable
class NotificationCandidate {
  const NotificationCandidate({
    required this.system,
    required this.id,
    required this.fireAt,
    required this.rank,
    required this.title,
    required this.body,
    this.kind = NotificationKind.oneTime,
    this.channelId,
    this.channelName,
    this.hour,
    this.minute,
    this.weekday,
  });

  final NotificationSystem system;

  /// 採番済みの最終 ID
  final int id;

  /// 次回発火時刻。Tier 2 の並べ替えキー。
  final DateTime fireAt;

  /// 系統内の優先順位 (0 が最優先)。Tier 1 の並べ替えキー。
  final int rank;

  final String title;
  final String body;
  final NotificationKind kind;
  final String? channelId;
  final String? channelName;

  /// dailyRepeat のとき使う
  final int? hour;
  final int? minute;

  /// dailyRepeat のとき使う。null = 毎日
  final int? weekday;

  @override
  String toString() =>
      'NotificationCandidate(${system.name}, id=$id, rank=$rank, at=$fireAt)';
}

// ============================================================================
// バジェット定数 — 調整はここ 1 箇所
// ============================================================================

/// iOS の同時予約上限と、系統ごとの最低保証枠。
///
/// 数字は Phase C の実測からの仮置き。多頭飼いを想定した再調整は
/// **ここだけ**触れば済むようにしてある。
abstract final class NotificationBudget {
  NotificationBudget._();

  /// iOS の同時予約上限。これを超えると古いものから黙って捨てられる。
  static const int total = 64;

  static const int vaccinationReserve = 16;
  static const int scheduleReserve = 16;
  static const int preventionReserve = 12;

  /// 最低保証の合計
  static const int reservedTotal =
      vaccinationReserve + scheduleReserve + preventionReserve;

  /// 系統問わず先着で埋める枠。Tier 1 の余りもここに合流する。
  static const int shared = total - reservedTotal;

  /// 系統ごとの最低保証枠
  static int reserveFor(NotificationSystem system) {
    switch (system) {
      case NotificationSystem.vaccination:
        return vaccinationReserve;
      case NotificationSystem.schedule:
        return scheduleReserve;
      case NotificationSystem.prevention:
        return preventionReserve;
    }
  }
}

// ============================================================================
// 配分結果
// ============================================================================

/// 何を積み、何が溢れたか。ログと開発者設定の両方に出す。
///
/// ログは debug ビルドでしか出ない (DevelopmentFilter) 一方、debug は端末に
/// よっては JIT で起動できない。可観測性はこのレポートの永続化で担保する。
@immutable
class NotificationAllocationReport {
  const NotificationAllocationReport({
    required this.candidates,
    required this.scheduled,
  });

  /// 系統ごとの「積みたかった数」(過去日を除いた後)
  final Map<NotificationSystem, int> candidates;

  /// 系統ごとの「積めた数」
  final Map<NotificationSystem, int> scheduled;

  int candidatesOf(NotificationSystem s) => candidates[s] ?? 0;
  int scheduledOf(NotificationSystem s) => scheduled[s] ?? 0;

  /// 系統ごとの「溢れた数」
  int droppedOf(NotificationSystem s) => candidatesOf(s) - scheduledOf(s);

  int get totalCandidates =>
      candidates.values.fold(0, (int a, int b) => a + b);
  int get totalScheduled => scheduled.values.fold(0, (int a, int b) => a + b);
  int get totalDropped => totalCandidates - totalScheduled;

  /// 1 行サマリ。ログと画面の両方で使う。
  String get summary {
    final StringBuffer sb = StringBuffer();
    for (final NotificationSystem s in NotificationSystem.values) {
      sb.write('${s.name}=${scheduledOf(s)}/${candidatesOf(s)} ');
    }
    sb.write('total=$totalScheduled/${NotificationBudget.total}');
    if (totalDropped > 0) sb.write(' dropped=$totalDropped');
    return sb.toString();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'candidates': <String, int>{
          for (final NotificationSystem s in NotificationSystem.values)
            s.name: candidatesOf(s),
        },
        'scheduled': <String, int>{
          for (final NotificationSystem s in NotificationSystem.values)
            s.name: scheduledOf(s),
        },
      };

  static NotificationAllocationReport? fromJson(Map<String, dynamic> json) {
    try {
      final Map<String, dynamic> c =
          (json['candidates'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final Map<String, dynamic> s =
          (json['scheduled'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      return NotificationAllocationReport(
        candidates: <NotificationSystem, int>{
          for (final NotificationSystem sys in NotificationSystem.values)
            sys: (c[sys.name] as int?) ?? 0,
        },
        scheduled: <NotificationSystem, int>{
          for (final NotificationSystem sys in NotificationSystem.values)
            sys: (s[sys.name] as int?) ?? 0,
        },
      );
    } catch (_) {
      return null;
    }
  }
}

/// 配分の出力
@immutable
class NotificationAllocation {
  const NotificationAllocation({
    required this.selected,
    required this.report,
  });

  /// 実際に積む通知。合計は必ず [NotificationBudget.total] 以下。
  final List<NotificationCandidate> selected;

  final NotificationAllocationReport report;
}

// ============================================================================
// Allocator
// ============================================================================

abstract final class NotificationBudgetAllocator {
  NotificationBudgetAllocator._();

  /// 全系統の候補から、実際に積むものを決める。
  ///
  /// [now] より前に発火する候補は積まない (既存ルール)。
  ///
  /// [reserveOverride] を渡すと系統ごとの最低保証を差し替えられる。
  /// キルスイッチで予防を止めた場合など、枠を 0 にして他系統へ流すために使う。
  static NotificationAllocation allocate({
    required List<NotificationCandidate> candidates,
    required DateTime now,
    int total = NotificationBudget.total,
    Map<NotificationSystem, int>? reserveOverride,
  }) {
    int reserveOf(NotificationSystem s) =>
        reserveOverride?[s] ?? NotificationBudget.reserveFor(s);

    // ---- 過去日を落とす ----
    final List<NotificationCandidate> alive = candidates
        .where((NotificationCandidate c) => c.fireAt.isAfter(now))
        .toList();

    // ---- 系統ごとに rank 昇順で並べる ----
    final Map<NotificationSystem, List<NotificationCandidate>> bySystem =
        <NotificationSystem, List<NotificationCandidate>>{
      for (final NotificationSystem s in NotificationSystem.values)
        s: <NotificationCandidate>[],
    };
    for (final NotificationCandidate c in alive) {
      bySystem[c.system]!.add(c);
    }
    for (final List<NotificationCandidate> list in bySystem.values) {
      list.sort((NotificationCandidate a, NotificationCandidate b) {
        final int r = a.rank.compareTo(b.rank);
        if (r != 0) return r;
        final int f = a.fireAt.compareTo(b.fireAt);
        return f != 0 ? f : a.id.compareTo(b.id);
      });
    }

    // ---- Tier 1: 最低保証 ----
    final List<NotificationCandidate> selected = <NotificationCandidate>[];
    final Map<NotificationSystem, List<NotificationCandidate>> leftovers =
        <NotificationSystem, List<NotificationCandidate>>{};
    int reservedUsed = 0;

    for (final NotificationSystem s in NotificationSystem.values) {
      final List<NotificationCandidate> list = bySystem[s]!;
      final int take = _min3(reserveOf(s), list.length, total - reservedUsed);
      selected.addAll(list.take(take));
      leftovers[s] = list.skip(take).toList();
      reservedUsed += take;
    }

    // ---- Tier 2: 余った保証枠 + 共有枠を、系統問わず fireAt 昇順で ----
    // 「使い切らなかった系統の余り」もここに合流する。
    final int pool = total - reservedUsed;
    if (pool > 0) {
      final List<NotificationCandidate> rest = <NotificationCandidate>[
        for (final List<NotificationCandidate> l in leftovers.values) ...l,
      ]..sort((NotificationCandidate a, NotificationCandidate b) {
          final int f = a.fireAt.compareTo(b.fireAt);
          if (f != 0) return f;
          final int r = a.rank.compareTo(b.rank);
          return r != 0 ? r : a.id.compareTo(b.id);
        });
      selected.addAll(rest.take(pool));
    }

    return NotificationAllocation(
      selected: selected,
      report: NotificationAllocationReport(
        candidates: <NotificationSystem, int>{
          for (final NotificationSystem s in NotificationSystem.values)
            s: bySystem[s]!.length,
        },
        scheduled: <NotificationSystem, int>{
          for (final NotificationSystem s in NotificationSystem.values)
            s: selected
                .where((NotificationCandidate c) => c.system == s)
                .length,
        },
      ),
    );
  }

  static int _min3(int a, int b, int c) {
    final int m = a < b ? a : b;
    return m < c ? m : c;
  }
}
