// ============================================================================
// petlo - Day Detail Sheet
// ============================================================================
//
// カレンダーで日付タップ時に出るモーダル。
// その日の全記録を時系列で並べて、タップで該当の編集画面に遷移。
//
// rev5.2: カレンダー → 日付タップ → 詳細
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/diaries_providers.dart';
import '../../providers/meals_providers.dart';
import '../../providers/pees_providers.dart';
import '../../providers/poops_providers.dart';
import '../../providers/schedules_providers.dart';
import '../../providers/scope_providers.dart';
import '../../providers/temperatures_providers.dart';
import '../../providers/vaccinations_providers.dart';
import '../../providers/visits_providers.dart';
import '../../providers/vomits_providers.dart';
import '../../providers/weights_providers.dart';
import '../../screens/schedule/schedule_record_screen.dart';
import '../../screens/diary/diary_record_screen.dart';
import '../../screens/meal/meal_record_screen.dart';
import '../../screens/pee/pee_record_screen.dart';
import '../../screens/poop/poop_record_screen.dart';
import '../../screens/temperature/temperature_record_screen.dart';
import '../../screens/vaccination/vaccination_record_screen.dart';
import '../../screens/visit/visit_record_screen.dart';
import '../../screens/vomit/vomit_record_screen.dart';
import '../../screens/weight/weight_record_screen.dart';

class DayDetailSheet extends ConsumerWidget {
  const DayDetailSheet({required this.day, super.key});

  final DateTime day;

  static Future<void> show(BuildContext context, DateTime day) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext c) => DayDetailSheet(day: day),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    // 当日の schedule を抽出
    final YearMonthForSchedules ym =
        YearMonthForSchedules(day.year, day.month);
    final AsyncValue<List<ScheduleEntity>> schedulesAsync =
        ref.watch(schedulesInMonthProvider(ym));
    final List<ScheduleEntity> daySchedules =
        schedulesAsync.maybeWhen(
      data: (List<ScheduleEntity> all) => all.where((ScheduleEntity s) {
        final DateTime t =
            DateTime.fromMillisecondsSinceEpoch(s.scheduledAt);
        return t.year == day.year && t.month == day.month && t.day == day.day;
      }).toList()
        ..sort((ScheduleEntity a, ScheduleEntity b) =>
            a.scheduledAt.compareTo(b.scheduledAt)),
      orElse: () => <ScheduleEntity>[],
    );

    final List<_DayItem> items = _collectItemsForDay(ref, day);
    items.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext context, ScrollController scroll) {
        return Container(
          decoration: BoxDecoration(
            color: colors.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
            border: Border(top: BorderSide(color: colors.fg, width: 1)),
          ),
          child: Column(
            children: <Widget>[
              // ハンドル
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                width: 40,
                height: 3,
                color: colors.fgFaint,
              ),

              // ヘッダー
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            _formatDateLabel(day, l10n),
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colors.fgMuted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatHeroDate(day),
                            style: TextStyle(
                              fontFamily: 'Fraunces',
                              fontStyle: FontStyle.italic,
                              fontSize: 28,
                              height: 1.0,
                              letterSpacing: -28 * 0.03,
                              color: colors.fg,
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: colors.fg, width: 1),
                        ),
                        child: Icon(Icons.close, size: 18, color: colors.fg),
                      ),
                    ),
                  ],
                ),
              ),

              Container(height: 1, color: colors.line),

              // 当日の予定セクション
              if (daySchedules.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  decoration: BoxDecoration(
                    color: colors.bgSoft,
                    border: Border(
                      bottom: BorderSide(color: colors.line),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.schedule_day_section_existing,
                        style: typo.metaSmall.copyWith(
                          color: colors.fgMuted,
                          letterSpacing: 11 * 0.18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final ScheduleEntity s in daySchedules)
                        _ScheduleRow(schedule: s),
                    ],
                  ),
                ),

              // 予定追加ボタン
              InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  ScheduleRecordScreen.push(context, initialDate: day);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: colors.line),
                    ),
                  ),
                  child: Text(
                    l10n.schedule_day_add_button,
                    style: typo.bodyMedium
                        .copyWith(color: colors.fg, fontWeight: FontWeight.w600),
                  ),
                ),
              ),

              // リスト
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          l10n.record_list_empty,
                          style:
                              typo.bodyMedium.copyWith(color: colors.fgMuted),
                        ),
                      )
                    : ListView.separated(
                        controller: scroll,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: colors.line,
                        ),
                        itemBuilder: (BuildContext c, int i) {
                          return _DayItemRow(item: items[i]);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDateLabel(DateTime d, AppLocalizations l10n) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime yest = today.subtract(const Duration(days: 1));
    if (d == today) return l10n.record_today_label;
    if (d == yest) return l10n.record_yesterday_label;
    return '${d.year}.${d.month.toString().padLeft(2, "0")}.${d.day.toString().padLeft(2, "0")}';
  }

  String _formatHeroDate(DateTime d) {
    final String locale =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    if (locale == 'ja' || locale == 'zh') {
      return '${d.month}月 ${d.day}日';
    }
    const List<String> months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }
}

// ============================================================================
// 1日分の収集ロジック (sealed _DayItem)
// ============================================================================
List<_DayItem> _collectItemsForDay(WidgetRef ref, DateTime day) {
  final String? petIdStr = ref.read(currentPetIdProvider);
  if (petIdStr == null || petIdStr == kAllPetsId) return <_DayItem>[];
  final int? petId = int.tryParse(petIdStr);
  if (petId == null) return <_DayItem>[];

  final int from = DateTime(day.year, day.month, day.day)
      .toUtc()
      .millisecondsSinceEpoch;
  final int to = DateTime(day.year, day.month, day.day + 1)
      .toUtc()
      .millisecondsSinceEpoch;

  bool inDay(int t) => t >= from && t < to;

  final List<_DayItem> items = <_DayItem>[];

  ref.read(recentMealsForHomeProvider).whenData((List<MealEntity> list) {
    for (final m in list) {
      if (inDay(m.eatenAt)) items.add(_DayItem.meal(m));
    }
  });
  ref.read(recentPoopsForHomeProvider).whenData((List<PoopEntity> list) {
    for (final p in list) {
      if (inDay(p.pooedAt)) items.add(_DayItem.poop(p));
    }
  });
  ref.read(recentPeesForHomeProvider).whenData((List<PeeEntity> list) {
    for (final p in list) {
      if (inDay(p.peedAt)) items.add(_DayItem.pee(p));
    }
  });
  ref.read(recentVomitsForHomeProvider).whenData((List<VomitEntity> list) {
    for (final v in list) {
      if (inDay(v.vomitedAt)) items.add(_DayItem.vomit(v));
    }
  });
  ref.read(currentPetWeightHistoryProvider).whenData((List<WeightEntity> list) {
    for (final w in list) {
      if (inDay(w.measuredAt)) items.add(_DayItem.weight(w));
    }
  });
  ref
      .read(currentPetTemperatureHistoryProvider)
      .whenData((List<TemperatureEntity> list) {
    for (final t in list) {
      if (inDay(t.measuredAt)) items.add(_DayItem.temperature(t));
    }
  });
  ref.read(currentPetVisitsProvider).whenData((List<VisitEntity> list) {
    for (final v in list) {
      if (inDay(v.visitedAt)) items.add(_DayItem.visit(v));
    }
  });
  ref
      .read(currentPetVaccinationsProvider)
      .whenData((List<VaccinationEntity> list) {
    for (final v in list) {
      if (inDay(v.administeredAt)) items.add(_DayItem.vaccination(v));
    }
  });
  ref.read(recentDiariesForHomeProvider).whenData((List<DiaryEntity> list) {
    for (final d in list) {
      if (inDay(d.eventAt)) items.add(_DayItem.diary(d));
    }
  });

  return items;
}

// ============================================================================
// _DayItem sealed
// ============================================================================
sealed class _DayItem {
  _DayItem(this.timestamp);

  factory _DayItem.meal(MealEntity m) = _MealItem;
  factory _DayItem.poop(PoopEntity p) = _PoopItem;
  factory _DayItem.pee(PeeEntity p) = _PeeItem;
  factory _DayItem.vomit(VomitEntity v) = _VomitItem;
  factory _DayItem.weight(WeightEntity w) = _WeightItem;
  factory _DayItem.temperature(TemperatureEntity t) = _TempItem;
  factory _DayItem.visit(VisitEntity v) = _VisitItem;
  factory _DayItem.vaccination(VaccinationEntity v) = _VaccinationItem;
  factory _DayItem.diary(DiaryEntity d) = _DiaryItem;

  final int timestamp;

  String kind(AppLocalizations l10n);
  String summary(AppLocalizations l10n);
  void onTap(BuildContext context);
}

class _MealItem extends _DayItem {
  _MealItem(this.entity) : super(entity.eatenAt);
  final MealEntity entity;
  @override
  String kind(AppLocalizations l10n) => l10n.record_kind_meal;
  @override
  String summary(AppLocalizations l10n) {
    final String name = entity.foodNameFreeText ?? l10n.record_kind_unspecified;
    return entity.amountG != null ? '$name · ${entity.amountG}g' : name;
  }

  @override
  void onTap(BuildContext c) =>
      MealRecordScreen.push(c, editingMealId: entity.id);
}

class _PoopItem extends _DayItem {
  _PoopItem(this.entity) : super(entity.pooedAt);
  final PoopEntity entity;
  @override
  String kind(AppLocalizations l10n) => l10n.record_kind_stool;
  @override
  String summary(AppLocalizations l10n) =>
      '${_dayPoopFormLabel(l10n, entity.form)} · ${_dayPoopColorLabel(l10n, entity.color)}';
  @override
  void onTap(BuildContext c) =>
      PoopRecordScreen.push(c, editingPoopId: entity.id);
}

class _PeeItem extends _DayItem {
  _PeeItem(this.entity) : super(entity.peedAt);
  final PeeEntity entity;
  @override
  String kind(AppLocalizations l10n) => l10n.record_kind_pee;
  @override
  String summary(AppLocalizations l10n) =>
      '${_dayPeeColorLabel(l10n, entity.color)} · ${entity.count}×';
  @override
  void onTap(BuildContext c) =>
      PeeRecordScreen.push(c, editingPeeId: entity.id);
}

class _VomitItem extends _DayItem {
  _VomitItem(this.entity) : super(entity.vomitedAt);
  final VomitEntity entity;
  @override
  String kind(AppLocalizations l10n) => l10n.record_kind_vomit;
  @override
  String summary(AppLocalizations l10n) {
    final String c = entity.color == VomitColor.other
        ? (entity.colorOtherText ?? l10n.vomit_color_other)
        : _dayVomitColorLabel(l10n, entity.color);
    return '$c · ${entity.count}×';
  }

  @override
  void onTap(BuildContext c) =>
      VomitRecordScreen.push(c, editingVomitId: entity.id);
}

class _WeightItem extends _DayItem {
  _WeightItem(this.entity) : super(entity.measuredAt);
  final WeightEntity entity;
  @override
  String kind(AppLocalizations l10n) => l10n.record_kind_weight;
  @override
  String summary(AppLocalizations l10n) =>
      '${(entity.weightG / 1000).toStringAsFixed(2)} kg';
  @override
  void onTap(BuildContext c) =>
      WeightRecordScreen.push(c, editingWeightId: entity.id);
}

class _TempItem extends _DayItem {
  _TempItem(this.entity) : super(entity.measuredAt);
  final TemperatureEntity entity;
  @override
  String kind(AppLocalizations l10n) => l10n.record_kind_temperature;
  @override
  String summary(AppLocalizations l10n) =>
      '${(entity.tempCelsiusX10 / 10).toStringAsFixed(1)}°C';
  @override
  void onTap(BuildContext c) =>
      TemperatureRecordScreen.push(c, editingTempId: entity.id);
}

class _VisitItem extends _DayItem {
  _VisitItem(this.entity) : super(entity.visitedAt);
  final VisitEntity entity;
  @override
  String kind(AppLocalizations l10n) => l10n.record_kind_visit;
  @override
  String summary(AppLocalizations l10n) => entity.reason;
  @override
  void onTap(BuildContext c) =>
      VisitRecordScreen.push(c, editingVisitId: entity.id);
}

class _VaccinationItem extends _DayItem {
  _VaccinationItem(this.entity) : super(entity.administeredAt);
  final VaccinationEntity entity;
  @override
  String kind(AppLocalizations l10n) => l10n.record_kind_vaccination;
  @override
  String summary(AppLocalizations l10n) => entity.kind;
  @override
  void onTap(BuildContext c) =>
      VaccinationRecordScreen.push(c, editingVaccinationId: entity.id);
}

class _DiaryItem extends _DayItem {
  _DiaryItem(this.entity) : super(entity.eventAt);
  final DiaryEntity entity;
  @override
  String kind(AppLocalizations l10n) => l10n.record_kind_diary;
  @override
  String summary(AppLocalizations l10n) {
    final String t = entity.title?.trim() ?? '';
    if (t.isNotEmpty) return t;
    final String firstLine = entity.body.trim().split('\n').first;
    return firstLine.length > 60
        ? '${firstLine.substring(0, 60)}…'
        : firstLine;
  }

  @override
  void onTap(BuildContext c) =>
      DiaryRecordScreen.push(c, editingDiaryId: entity.id);
}

String _dayPoopFormLabel(AppLocalizations l10n, PoopForm f) {
  switch (f) {
    case PoopForm.hard:
      return l10n.poop_form_hard;
    case PoopForm.lumpy:
      return l10n.poop_form_lumpy;
    case PoopForm.normal:
      return l10n.poop_form_normal;
    case PoopForm.soft:
      return l10n.poop_form_soft;
    case PoopForm.watery:
      return l10n.poop_form_watery;
  }
}

String _dayPoopColorLabel(AppLocalizations l10n, PoopColor c) {
  switch (c) {
    case PoopColor.brown:
      return l10n.poop_color_brown;
    case PoopColor.black:
      return l10n.poop_color_black;
    case PoopColor.red:
      return l10n.poop_color_red;
    case PoopColor.yellow:
      return l10n.poop_color_yellow;
    case PoopColor.pale:
      return l10n.poop_color_pale;
  }
}

String _dayPeeColorLabel(AppLocalizations l10n, PeeColor c) {
  switch (c) {
    case PeeColor.pale_yellow:
      return l10n.pee_color_pale;
    case PeeColor.yellow:
      return l10n.pee_color_yellow;
    case PeeColor.dark_yellow:
      return l10n.pee_color_dark;
    case PeeColor.amber:
      return l10n.pee_color_amber;
    case PeeColor.red:
      return l10n.pee_color_red;
    case PeeColor.cloudy:
      return l10n.pee_color_cloudy;
  }
}

String _dayVomitColorLabel(AppLocalizations l10n, VomitColor c) {
  switch (c) {
    case VomitColor.clear:
      return l10n.vomit_color_clear;
    case VomitColor.yellow:
      return l10n.vomit_color_yellow;
    case VomitColor.brown:
      return l10n.vomit_color_brown;
    case VomitColor.food:
      return l10n.vomit_color_food;
    case VomitColor.white_foam:
      return l10n.vomit_color_white_foam;
    case VomitColor.red:
      return l10n.vomit_color_red;
    case VomitColor.green:
      return l10n.vomit_color_green;
    case VomitColor.black:
      return l10n.vomit_color_black;
    case VomitColor.other:
      return l10n.vomit_color_other;
  }
}

// ============================================================================
// 行表示
// ============================================================================
class _DayItemRow extends StatelessWidget {
  const _DayItemRow({required this.item});
  final _DayItem item;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    final DateTime t = DateTime.fromMillisecondsSinceEpoch(item.timestamp);
    final String time =
        '${t.hour.toString().padLeft(2, "0")}:${t.minute.toString().padLeft(2, "0")}';

    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        item.onTap(context);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 50,
              child: Text(
                time,
                style: typo.metaSmall.copyWith(
                  color: colors.fgMuted,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 56,
              child: Text(
                item.kind(l10n),
                style: typo.metaSmall.copyWith(color: colors.fg),
              ),
            ),
            Expanded(
              child: Text(
                item.summary(l10n),
                style: typo.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// _ScheduleRow - 予定の行
// ============================================================================
class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.schedule});

  final ScheduleEntity schedule;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DateTime t =
        DateTime.fromMillisecondsSinceEpoch(schedule.scheduledAt);
    final String time = schedule.hasTime
        ? '${t.hour.toString().padLeft(2, "0")}:${t.minute.toString().padLeft(2, "0")}'
        : '';

    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        ScheduleRecordScreen.push(
          context,
          editingScheduleId: schedule.id,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: <Widget>[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: scheduleCategoryColor(colors, schedule.category),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            if (time.isNotEmpty) ...<Widget>[
              SizedBox(
                width: 44,
                child: Text(
                  time,
                  style: typo.bodySmall.copyWith(
                    color: colors.fgMuted,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
            ],
            Expanded(
              child: Text(
                schedule.title,
                style: typo.bodyMedium.copyWith(color: colors.fg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              scheduleCategoryLabel(l10n, schedule.category),
              style: typo.bodySmall.copyWith(color: colors.fgMuted),
            ),
          ],
        ),
      ),
    );
  }
}
