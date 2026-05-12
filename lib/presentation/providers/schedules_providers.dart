// ============================================================================
// petlo - Schedules Providers (build 5; rev build 10: recurrence expansion)
// ============================================================================
//
// Schedule の Repository / 派生 Provider 群。
//
// build 10: 月別取得 schedulesInMonthProvider に recurrence 展開を実装。
// 元の scheduledAt と異なる年・月の表示でも、recurrence が yearly/monthly/
// weekly/daily の場合は仮想インスタンスを生成して返す。
//
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_enums.dart';
import '../../data/repositories/schedules_repository.dart';
import 'database_provider.dart';
import 'scope_providers.dart';

// ============================================================================
// Repository
// ============================================================================

final Provider<SchedulesRepository> schedulesRepositoryProvider =
    Provider<SchedulesRepository>(
  (Ref ref) {
    final AppDatabase db = ref.watch(appDatabaseProvider);
    return SchedulesRepository(db);
  },
);

// ============================================================================
// 現在グループの全 schedule (date asc)
// ============================================================================

final StreamProvider<List<ScheduleEntity>> currentGroupSchedulesProvider =
    StreamProvider<List<ScheduleEntity>>(
  (Ref ref) {
    final String groupId = ref.watch(currentGroupIdProvider);
    final SchedulesRepository repo = ref.watch(schedulesRepositoryProvider);
    return repo.watchForGroup(groupId);
  },
);

// ============================================================================
// 指定月の schedule
// ============================================================================

class YearMonthForSchedules {
  const YearMonthForSchedules(this.year, this.month);
  final int year;
  final int month;

  ({int from, int to}) get rangeUtcMsec {
    final DateTime first = DateTime(year, month, 1);
    final DateTime nextMonth = DateTime(year, month + 1, 1);
    return (
      from: first.toUtc().millisecondsSinceEpoch,
      to: nextMonth.toUtc().millisecondsSinceEpoch,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is YearMonthForSchedules &&
          other.year == year &&
          other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

final StreamProviderFamily<List<ScheduleEntity>, YearMonthForSchedules>
    schedulesInMonthProvider =
    StreamProviderFamily<List<ScheduleEntity>, YearMonthForSchedules>(
  (Ref ref, YearMonthForSchedules ym) {
    final String groupId = ref.watch(currentGroupIdProvider);
    final SchedulesRepository repo = ref.watch(schedulesRepositoryProvider);
    // recurrence 展開のため、グループの全 schedule を取得してから
    // Dart 側でその月に該当するインスタンスをフィルタ・展開する。
    return repo.watchForGroup(groupId).map(
          (List<ScheduleEntity> all) => _expandSchedulesForMonth(all, ym),
        );
  },
);

/// 指定月に該当する schedule インスタンスを返す。
/// recurrence が none 以外の場合、scheduledAt を当月にシフトした
/// 仮想インスタンスを生成する。
@visibleForTesting
List<ScheduleEntity> expandSchedulesForMonth(
  List<ScheduleEntity> all,
  YearMonthForSchedules ym,
) =>
    _expandSchedulesForMonth(all, ym);

List<ScheduleEntity> _expandSchedulesForMonth(
  List<ScheduleEntity> all,
  YearMonthForSchedules ym,
) {
  final ({int from, int to}) range = ym.rangeUtcMsec;
  final DateTime monthStart = DateTime(ym.year, ym.month, 1);
  final DateTime monthEndExclusive = DateTime(ym.year, ym.month + 1, 1);
  final List<ScheduleEntity> result = <ScheduleEntity>[];

  for (final ScheduleEntity s in all) {
    final DateTime original =
        DateTime.fromMillisecondsSinceEpoch(s.scheduledAt);
    switch (s.recurrence) {
      case ScheduleRecurrence.none:
        if (s.scheduledAt >= range.from && s.scheduledAt < range.to) {
          result.add(s);
        }
      case ScheduleRecurrence.yearly:
        // 元の月日を当月の年に当てはめる
        final DateTime candidate = _safeDay(
          ym.year,
          original.month,
          original.day,
          original.hour,
          original.minute,
        );
        if (candidate.month == ym.month &&
            !candidate.isBefore(monthStart) &&
            candidate.isBefore(monthEndExclusive)) {
          result.add(s.copyWith(scheduledAt: candidate.millisecondsSinceEpoch));
        }
      case ScheduleRecurrence.monthly:
        // 元の日を当月に当てはめる
        final DateTime candidate = _safeDay(
          ym.year,
          ym.month,
          original.day,
          original.hour,
          original.minute,
        );
        if (candidate.month == ym.month) {
          result.add(s.copyWith(scheduledAt: candidate.millisecondsSinceEpoch));
        }
      case ScheduleRecurrence.weekly:
        // 同曜日を当月内すべて生成
        DateTime cursor = DateTime(ym.year, ym.month, 1,
            original.hour, original.minute);
        // 最初の同曜日まで進める
        while (cursor.weekday != original.weekday) {
          cursor = cursor.add(const Duration(days: 1));
        }
        while (cursor.isBefore(monthEndExclusive)) {
          if (!cursor.isBefore(monthStart)) {
            result.add(
                s.copyWith(scheduledAt: cursor.millisecondsSinceEpoch));
          }
          cursor = cursor.add(const Duration(days: 7));
        }
      case ScheduleRecurrence.daily:
        // 当月のすべての日を生成
        DateTime cursor = DateTime(ym.year, ym.month, 1,
            original.hour, original.minute);
        while (cursor.isBefore(monthEndExclusive)) {
          result.add(
              s.copyWith(scheduledAt: cursor.millisecondsSinceEpoch));
          cursor = cursor.add(const Duration(days: 1));
        }
    }
  }

  result.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  return result;
}

/// 月末日越え(例: 1月31日 → 2月にスライドさせると31日がない)で
/// DateTime が翌月の頭に繰り上がるのを防ぐ。
/// invalid な日付の場合は当月の末日に丸める。
DateTime _safeDay(int year, int month, int day, int hour, int minute) {
  final DateTime probe = DateTime(year, month, day, hour, minute);
  if (probe.month == month) return probe;
  // 当月の末日 (= 翌月1日の前日)
  final DateTime lastDay =
      DateTime(year, month + 1, 1).subtract(const Duration(days: 1));
  return DateTime(lastDay.year, lastDay.month, lastDay.day, hour, minute);
}
