// ============================================================================
// petlo - PetloCalendarView
// ============================================================================
//
// table_calendar をエディトリアル風にカスタムしたカレンダーウィジェット。
//
// rev5.2: 月表示UI + 各日付の記録数を dot indicator として表示。
//
// デザイン:
//   - 黒白基調、線画
//   - 選択中: 黒塗り反転、未選択: 透明
//   - 今日: 細い円(angularDecoration の代わり)
//   - イベントマーカー: 4種の dot
//     · daily(食事/排泄) → 中性の小さい点
//     · health(体重/体温/通院/ワクチン) → 円
//     · urgent(嘔吐/通院) → 赤い小さい点
//     · memory(日記) → ベージュ系の小さい点
//
// 親側で:
//   - currentMonth の YearMonth を持つ
//   - 月切替を通知
//   - 日付タップ時の callback
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../../data/models/day_summary.dart';

class PetloCalendarView extends StatefulWidget {
  const PetloCalendarView({
    required this.focusedMonth,
    required this.summaries,
    required this.onMonthChanged,
    required this.onDaySelected,
    this.selectedDay,
    this.schedulesByDay = const <DateTime, List<ScheduleEntity>>{},
    this.onDayLongPressed,
    super.key,
  });

  /// 表示中の月の任意の日(table_calendar の focusedDay)
  final DateTime focusedMonth;

  /// 表示月の DaySummary Map (key は localDayKey)
  final Map<DateTime, DaySummary> summaries;

  /// 表示月の予定 Map (key: 当月の YYYY-MM-DD, value: 当日の schedule)
  final Map<DateTime, List<ScheduleEntity>> schedulesByDay;

  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDaySelected;

  /// 日付長押し時のコールバック(新規予定追加へ誘導)
  final ValueChanged<DateTime>? onDayLongPressed;

  final DateTime? selectedDay;

  @override
  State<PetloCalendarView> createState() => _PetloCalendarViewState();
}

class _PetloCalendarViewState extends State<PetloCalendarView> {
  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    final String localeCode = Localizations.localeOf(context).languageCode;

    return TableCalendar<DaySummary>(
      firstDay: DateTime(2020),
      lastDay: DateTime(DateTime.now().year + 5, 12, 31),
      focusedDay: widget.focusedMonth,
      locale: localeCode,
      selectedDayPredicate: (DateTime day) =>
          widget.selectedDay != null &&
          isSameDay(day, widget.selectedDay),

      // ===== レイアウト =====
      rowHeight: 50,
      daysOfWeekHeight: 26,
      headerVisible: false, // 親側でカスタムヘッダー
      sixWeekMonthsEnforced: true,

      // ===== 曜日ラベル(JP/ZH は単漢字、EN は intl 既定の Mon/Tue) =====
      startingDayOfWeek: StartingDayOfWeek.sunday,
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: TextStyle(
          fontFamily: localeCode == 'en' ? 'JetBrainsMono' : 'Manrope',
          fontSize: localeCode == 'en' ? 9 : 12,
          fontWeight: FontWeight.w600,
          letterSpacing: localeCode == 'en' ? 9 * 0.18 : 0,
          color: colors.fgMuted,
        ),
        weekendStyle: TextStyle(
          fontFamily: localeCode == 'en' ? 'JetBrainsMono' : 'Manrope',
          fontSize: localeCode == 'en' ? 9 : 12,
          fontWeight: FontWeight.w600,
          letterSpacing: localeCode == 'en' ? 9 * 0.18 : 0,
          color: colors.fgMuted,
        ),
        dowTextFormatter: (DateTime day, dynamic dynamicLocale) {
          if (localeCode == 'ja') {
            const List<String> wd = <String>['日', '月', '火', '水', '木', '金', '土'];
            return wd[day.weekday % 7];
          }
          if (localeCode == 'zh') {
            const List<String> wd = <String>['日', '一', '二', '三', '四', '五', '六'];
            return wd[day.weekday % 7];
          }
          // English: short DOW (Mon, Tue, ...)
          const List<String> en = <String>[
            'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'
          ];
          return en[day.weekday % 7];
        },
      ),

      // ===== イベントローダー =====
      eventLoader: (DateTime day) {
        final DateTime key = DateTime(day.year, day.month, day.day);
        final DaySummary? s = widget.summaries[key];
        return s == null ? <DaySummary>[] : <DaySummary>[s];
      },

      // ===== コールバック =====
      onDaySelected: (DateTime selected, DateTime focused) {
        widget.onDaySelected(selected);
      },
      onDayLongPressed: widget.onDayLongPressed == null
          ? null
          : (DateTime selected, DateTime focused) {
              widget.onDayLongPressed!(selected);
            },
      onPageChanged: (DateTime focused) {
        widget.onMonthChanged(focused);
      },

      // ===== スタイル =====
      calendarStyle: CalendarStyle(
        outsideDaysVisible: true,
        cellMargin: const EdgeInsets.all(2),
        defaultTextStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          color: colors.fg,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
        weekendTextStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          color: colors.fg,
        ),
        outsideTextStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          color: colors.fgFaint,
        ),
        // 今日 (selected でない時): 細い枠
        todayDecoration: BoxDecoration(
          shape: BoxShape.rectangle,
          border: Border.all(color: colors.fgMuted, width: 1),
        ),
        todayTextStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          color: colors.fg,
          fontWeight: FontWeight.w600,
        ),
        // 選択中: 黒塗り反転
        selectedDecoration: BoxDecoration(
          shape: BoxShape.rectangle,
          color: colors.fg,
        ),
        selectedTextStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          color: colors.bg,
          fontWeight: FontWeight.w600,
        ),
        markersMaxCount: 0, // 自前でcalendarBuildersのmarkerBuilderで描画
      ),

      // ===== カスタムビルダー (dot indicator) =====
      calendarBuilders: CalendarBuilders<DaySummary>(
        markerBuilder:
            (BuildContext context, DateTime day, List<DaySummary> events) {
          final DateTime key = DateTime(day.year, day.month, day.day);
          final List<ScheduleEntity> schedules =
              widget.schedulesByDay[key] ?? const <ScheduleEntity>[];
          if (events.isEmpty && schedules.isEmpty) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _DotIndicators(
              summary: events.isEmpty ? DaySummary.empty : events.first,
              schedules: schedules,
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// DotIndicators - 4種(daily / health / urgent / memory)の dot
// ============================================================================
class _DotIndicators extends StatelessWidget {
  const _DotIndicators({
    required this.summary,
    this.schedules = const <ScheduleEntity>[],
  });

  final DaySummary summary;
  final List<ScheduleEntity> schedules;

  bool _scheduleHasUrgent() =>
      schedules.any((ScheduleEntity s) =>
          s.category == ScheduleCategory.urgent);

  bool _scheduleHasHealth() => schedules.any((ScheduleEntity s) =>
      s.category == ScheduleCategory.vaccination ||
      s.category == ScheduleCategory.medication ||
      s.category == ScheduleCategory.visit);

  bool _scheduleHasDaily() => schedules.any((ScheduleEntity s) =>
      s.category == ScheduleCategory.grooming ||
      s.category == ScheduleCategory.meal ||
      s.category == ScheduleCategory.custom);

  bool _scheduleHasMemory() => schedules.any((ScheduleEntity s) =>
      s.category == ScheduleCategory.birthday ||
      s.category == ScheduleCategory.memorial ||
      s.category == ScheduleCategory.anniversary);

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    final List<Widget> dots = <Widget>[];

    if (summary.hasUrgent || _scheduleHasUrgent()) {
      dots.add(_dot(colors.accentDanger, 4));
    }
    if (summary.hasHealth || _scheduleHasHealth()) {
      dots.add(_dot(colors.fg, 3));
    }
    if (summary.hasDaily || _scheduleHasDaily()) {
      dots.add(_dot(colors.fgMuted, 3));
    }
    if (summary.hasMemory || _scheduleHasMemory()) {
      dots.add(_dot(colors.accentWarn, 3));
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < dots.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 2),
          dots[i],
        ],
      ],
    );
  }

  Widget _dot(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
