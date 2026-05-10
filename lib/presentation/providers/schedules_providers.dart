// ============================================================================
// petlo - Schedules Providers (build 5)
// ============================================================================
//
// Schedule の Repository / 派生 Provider 群。
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
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
    final ({int from, int to}) range = ym.rangeUtcMsec;
    return repo.watchInRange(
      groupId: groupId,
      fromMsec: range.from,
      toMsec: range.to,
    );
  },
);
