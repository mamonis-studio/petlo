// ============================================================================
// petlo - Calendar Provider
// ============================================================================
//
// 指定月の各日付ごとの記録件数を集計して返す Provider。
//
// rev5.2: カレンダーUI (table_calendar) で dot indicator 表示用。
//
// 設計:
//   - YearMonth (immutable) を family parameter
//   - 9種の Repository.watchInRange() / watchForPet() を購読
//   - 結果を Map<DateTime(local 0時), DaySummary> で返す
//   - 1記録の追加で即時 UI 更新される
//
// ============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/models/day_summary.dart';
import 'diaries_providers.dart';
import 'meals_providers.dart';
import 'pees_providers.dart';
import 'pets_providers.dart';
import 'poops_providers.dart';
import 'scope_providers.dart';
import 'temperatures_providers.dart';
import 'vaccinations_providers.dart';
import 'visits_providers.dart';
import 'vomits_providers.dart';
import 'weights_providers.dart';

/// 年月のペア。family parameter として使う。
@immutable
class YearMonth {
  const YearMonth(this.year, this.month);

  final int year;
  final int month;

  YearMonth get prev =>
      month == 1 ? YearMonth(year - 1, 12) : YearMonth(year, month - 1);
  YearMonth get next =>
      month == 12 ? YearMonth(year + 1, 1) : YearMonth(year, month + 1);

  static YearMonth ofNow() {
    final DateTime n = DateTime.now();
    return YearMonth(n.year, n.month);
  }

  /// この月の0時(ローカル時刻ベース)からのUTC msec範囲
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
      other is YearMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => '$year-${month.toString().padLeft(2, '0')}';
}

/// msec → ローカル0時のDateTime(Map のキー用)
DateTime _localDayKey(int msec) {
  final DateTime t = DateTime.fromMillisecondsSinceEpoch(msec);
  return DateTime(t.year, t.month, t.day);
}

// ============================================================================
// Provider — birthdays
// ============================================================================

/// 指定月の中で誕生日に該当するペット名を日付ごとに集めた Map。
/// (現在グループのペット全員の birthday を読み取り、month が一致する日付を抽出)
final ProviderFamily<Map<DateTime, List<String>>, YearMonth>
    petBirthdaysInMonthProvider =
    ProviderFamily<Map<DateTime, List<String>>, YearMonth>(
  (Ref ref, YearMonth ym) {
    final AsyncValue<List<PetEntity>> petsAsync =
        ref.watch(currentGroupPetsProvider);
    final List<PetEntity> pets = petsAsync.maybeWhen(
      data: (List<PetEntity> l) => l,
      orElse: () => <PetEntity>[],
    );
    final Map<DateTime, List<String>> map = <DateTime, List<String>>{};
    for (final PetEntity p in pets) {
      final int? bd = p.birthday;
      if (bd == null) continue;
      final DateTime date = DateTime.fromMillisecondsSinceEpoch(bd);
      if (date.month != ym.month) continue;
      final DateTime key = DateTime(ym.year, ym.month, date.day);
      (map[key] ??= <String>[]).add(p.name);
    }
    return map;
  },
);

// ============================================================================
// Provider
// ============================================================================

/// 指定月の DaySummary Map を返す。
final StreamProviderFamily<Map<DateTime, DaySummary>, YearMonth>
    calendarMonthProvider =
    StreamProviderFamily<Map<DateTime, DaySummary>, YearMonth>(
  (Ref ref, YearMonth ym) {
    final String? petIdStr = ref.watch(currentPetIdProvider);
    if (petIdStr == null || petIdStr == kAllPetsId) {
      return Stream<Map<DateTime, DaySummary>>.value(
          <DateTime, DaySummary>{});
    }
    final int? petId = int.tryParse(petIdStr);
    if (petId == null) {
      return Stream<Map<DateTime, DaySummary>>.value(
          <DateTime, DaySummary>{});
    }

    final ({int from, int to}) range = ym.rangeUtcMsec;

    // 9種のRepoから月内ストリーム
    final Stream<List<MealEntity>> meals = ref
        .watch(mealsRepositoryProvider)
        .watchMealsInRange(
            petId: petId, fromMsec: range.from, toMsec: range.to);
    final Stream<List<PoopEntity>> poops = ref
        .watch(poopsRepositoryProvider)
        .watchInRange(petId: petId, fromMsec: range.from, toMsec: range.to);
    // pees/vomits は Repo に watchInRange が無いので watchForPet で全件→月フィルタ
    final Stream<List<PeeEntity>> pees =
        ref.watch(peesRepositoryProvider).watchForPet(petId);
    final Stream<List<VomitEntity>> vomits =
        ref.watch(vomitsRepositoryProvider).watchForPet(petId);
    final Stream<List<WeightEntity>> weights = ref
        .watch(weightsRepositoryProvider)
        .watchInRange(petId: petId, fromMsec: range.from, toMsec: range.to);
    final Stream<List<TemperatureEntity>> temps = ref
        .watch(temperaturesRepositoryProvider)
        .watchInRange(petId: petId, fromMsec: range.from, toMsec: range.to);
    final Stream<List<VisitEntity>> visits = ref
        .watch(visitsRepositoryProvider)
        .watchInRange(petId: petId, fromMsec: range.from, toMsec: range.to);
    // vaccinations は administeredAt 月フィルタ
    final Stream<List<VaccinationEntity>> vaccinations =
        ref.watch(vaccinationsRepositoryProvider).watchForPet(petId);
    final Stream<List<DiaryEntity>> diaries = ref
        .watch(diariesRepositoryProvider)
        .watchInRange(petId: petId, fromMsec: range.from, toMsec: range.to);

    return _combineLatest9(
      meals,
      poops,
      pees,
      vomits,
      weights,
      temps,
      visits,
      vaccinations,
      diaries,
      (List<MealEntity> m,
          List<PoopEntity> po,
          List<PeeEntity> pe,
          List<VomitEntity> vo,
          List<WeightEntity> w,
          List<TemperatureEntity> te,
          List<VisitEntity> vi,
          List<VaccinationEntity> va,
          List<DiaryEntity> di) {
        final Map<DateTime, _MutableSummary> map =
            <DateTime, _MutableSummary>{};

        for (final MealEntity e in m) {
          (map[_localDayKey(e.eatenAt)] ??= _MutableSummary()).meals++;
        }
        for (final PoopEntity e in po) {
          (map[_localDayKey(e.pooedAt)] ??= _MutableSummary()).poops++;
        }
        for (final PeeEntity e in pe) {
          if (e.peedAt < range.from || e.peedAt >= range.to) continue;
          (map[_localDayKey(e.peedAt)] ??= _MutableSummary()).pees++;
        }
        for (final VomitEntity e in vo) {
          if (e.vomitedAt < range.from || e.vomitedAt >= range.to) continue;
          (map[_localDayKey(e.vomitedAt)] ??= _MutableSummary()).vomits++;
        }
        for (final WeightEntity e in w) {
          (map[_localDayKey(e.measuredAt)] ??= _MutableSummary()).weights++;
        }
        for (final TemperatureEntity e in te) {
          (map[_localDayKey(e.measuredAt)] ??= _MutableSummary())
              .temperatures++;
        }
        for (final VisitEntity e in vi) {
          (map[_localDayKey(e.visitedAt)] ??= _MutableSummary()).visits++;
        }
        for (final VaccinationEntity e in va) {
          if (e.administeredAt < range.from ||
              e.administeredAt >= range.to) {
            continue;
          }
          (map[_localDayKey(e.administeredAt)] ??= _MutableSummary())
              .vaccinations++;
        }
        for (final DiaryEntity e in di) {
          (map[_localDayKey(e.eventAt)] ??= _MutableSummary()).diaries++;
        }

        return <DateTime, DaySummary>{
          for (final entry in map.entries)
            entry.key: entry.value.toImmutable(),
        };
      },
    );
  },
);

// ============================================================================
// 内部: 集計途中のmutable版
// ============================================================================
class _MutableSummary {
  int meals = 0;
  int poops = 0;
  int pees = 0;
  int vomits = 0;
  int weights = 0;
  int temperatures = 0;
  int visits = 0;
  int vaccinations = 0;
  int diaries = 0;

  DaySummary toImmutable() => DaySummary(
        meals: meals,
        poops: poops,
        pees: pees,
        vomits: vomits,
        weights: weights,
        temperatures: temperatures,
        visits: visits,
        vaccinations: vaccinations,
        diaries: diaries,
      );
}

// ============================================================================
// 9引数 combineLatest の自前実装
//
// すべてのストリームから少なくとも1値が来てから初めて出力する。
// その後はどれかが新しい値を出したらcombinerを呼んで結果を出力。
// ============================================================================
Stream<R> _combineLatest9<A, B, C, D, E, F, G, H, I, R>(
  Stream<A> a,
  Stream<B> b,
  Stream<C> c,
  Stream<D> d,
  Stream<E> e,
  Stream<F> f,
  Stream<G> g,
  Stream<H> h,
  Stream<I> i,
  R Function(A, B, C, D, E, F, G, H, I) combiner,
) {
  final StreamController<R> controller = StreamController<R>();
  final List<Object?> values = List<Object?>.filled(9, null);
  final List<bool> seen = List<bool>.filled(9, false);
  int activeCount = 9;

  void emit() {
    if (seen.every((v) => v)) {
      try {
        controller.add(combiner(
          values[0] as A,
          values[1] as B,
          values[2] as C,
          values[3] as D,
          values[4] as E,
          values[5] as F,
          values[6] as G,
          values[7] as H,
          values[8] as I,
        ));
      } catch (err, st) {
        controller.addError(err, st);
      }
    }
  }

  StreamSubscription<T> subscribe<T>(Stream<T> stream, int idx) {
    return stream.listen(
      (T v) {
        values[idx] = v;
        seen[idx] = true;
        emit();
      },
      onError: controller.addError,
      onDone: () {
        activeCount--;
        if (activeCount == 0 && !controller.isClosed) {
          controller.close();
        }
      },
    );
  }

  final List<StreamSubscription<dynamic>> subs = <StreamSubscription<dynamic>>[
    subscribe(a, 0),
    subscribe(b, 1),
    subscribe(c, 2),
    subscribe(d, 3),
    subscribe(e, 4),
    subscribe(f, 5),
    subscribe(g, 6),
    subscribe(h, 7),
    subscribe(i, 8),
  ];

  controller.onCancel = () async {
    for (final StreamSubscription<dynamic> s in subs) {
      await s.cancel();
    }
  };

  return controller.stream;
}
