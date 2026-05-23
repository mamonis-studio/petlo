// ============================================================================
// petlo - Plans Tab Screen (Chunk 15: カレンダー実装)
// ============================================================================
//
// 月表示カレンダーを主役に据えたタブ。
//
// 構成:
//   - カスタムヘッダー(年 + 月名 Fraunces + 矢印 + TODAYボタン)
//   - PetloCalendarView (table_calendar カスタム)
//   - Legend (dot indicator の凡例)
//   - Upcoming セクション(overdue/upcoming vaccinations)
//
// rev5.2: カレンダー月表示
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/outlined_action_button.dart';
import '../../../core/widgets/section_label.dart';
import '../../../data/local/app_database.dart';
import '../../../data/models/day_summary.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/calendar_provider.dart';
import '../../providers/medication_reminders_providers.dart';
import '../../providers/pets_providers.dart';
import '../../providers/schedules_providers.dart';
import '../../providers/scope_providers.dart';
import '../../providers/vaccinations_providers.dart';
import '../../widgets/calendar/calendar_header.dart';
import '../../widgets/calendar/day_detail_sheet.dart';
import '../../widgets/calendar/petlo_calendar_view.dart';
import '../../widgets/petlo_scaffold.dart';
import '../medication_reminder/medication_reminders_list_screen.dart';
import '../pet/pet_form_screen.dart';
import '../schedule/schedule_record_screen.dart';
import '../vaccination/vaccination_record_screen.dart';

class PlansTabScreen extends ConsumerStatefulWidget {
  const PlansTabScreen({super.key});

  @override
  ConsumerState<PlansTabScreen> createState() => _PlansTabScreenState();
}

enum _PlanView { month, list }

class _PlansTabScreenState extends ConsumerState<PlansTabScreen> {
  late DateTime _focusedMonth;
  DateTime? _selectedDay;
  _PlanView _view = _PlanView.month;

  @override
  void initState() {
    super.initState();
    _focusedMonth = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final AppTypography typo = AppTypography.of(context);
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? currentPetId = ref.watch(currentPetIdProvider);
    final bool isAllPets = currentPetId == kAllPetsId;
    // build 9: ペットが 1匹以上いればカレンダーを表示(All Pets でも個別でも)。
    // 0匹の場合のみ select-pet 空状態。
    final bool noPets = ref.watch(hasNoPetsProvider).maybeWhen(
          data: (bool v) => v,
          orElse: () => false,
        );
    final bool canShow = !noPets;

    final double bottomInset = MediaQuery.of(context).padding.bottom;
    return PetloScaffold(
      showTabBar: false,
      showAllPetsInSelector: true,
      onAddPetTapped: () => PetFormScreen.push(context),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          28,
          0,
          28,
          24 + bottomInset + kBottomNavigationBarHeight,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionLabel(
              l10n.tab_eyebrow_schedule,
              size: EyebrowSize.large,
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
            ),
            // 月/リスト切替トグル(右寄せ単独配置)
            if (canShow)
              Align(
                alignment: Alignment.centerRight,
                child: _ViewToggle(
                  current: _view,
                  onChanged: (_PlanView v) => setState(() => _view = v),
                ),
              ),
            const SizedBox(height: 16),

            if (!canShow)
              _SelectPetEmpty(colors: colors, typo: typo)
            else if (_view == _PlanView.month) ...<Widget>[
              // ===== 月表示 =====
              CalendarHeader(
                focusedMonth: _focusedMonth,
                onPrev: () {
                  setState(() {
                    _focusedMonth = DateTime(
                      _focusedMonth.year,
                      _focusedMonth.month - 1,
                      1,
                    );
                  });
                },
                onNext: () {
                  setState(() {
                    _focusedMonth = DateTime(
                      _focusedMonth.year,
                      _focusedMonth.month + 1,
                      1,
                    );
                  });
                },
                onToday: () {
                  setState(() {
                    _focusedMonth = DateTime.now();
                    _selectedDay = null;
                  });
                },
              ),
              _CalendarSection(
                focusedMonth: _focusedMonth,
                selectedDay: _selectedDay,
                onMonthChanged: (DateTime focused) {
                  setState(() => _focusedMonth = focused);
                },
                onDaySelected: (DateTime day) {
                  setState(() => _selectedDay = day);
                  DayDetailSheet.show(context, day);
                },
              ),
              const SizedBox(height: 16),
              _Legend(colors: colors),
              const SizedBox(height: 32),
              const _UpcomingVaccinations(),
              const SizedBox(height: 32),
              const _ActiveReminders(),
            ] else ...<Widget>[
              // ===== リスト表示(schedules ベース) =====
              const _ScheduleListView(),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.current, required this.onChanged});

  final _PlanView current;
  final ValueChanged<_PlanView> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final _PlanView v in _PlanView.values)
          InkWell(
            onTap: () => onChanged(v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: current == v ? colors.fg : colors.bg,
                border: Border.all(color: colors.fg, width: 1),
              ),
              child: Text(
                v == _PlanView.month
                    ? l10n.plans_view_month
                    : l10n.plans_view_list,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 11,
                  fontWeight:
                      current == v ? FontWeight.w700 : FontWeight.w500,
                  color: current == v ? colors.bg : colors.fg,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SelectPetEmpty extends StatelessWidget {
  const _SelectPetEmpty({required this.colors, required this.typo});

  final AppColors colors;
  final AppTypography typo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Text(
        AppLocalizations.of(context).tab_select_pet_plans,
        style: typo.bodyMedium.copyWith(color: colors.fgMuted, height: 1.6),
      ),
    );
  }
}

// ============================================================================
// CalendarSection - 集計データを取得してCalendarViewへ渡す
// ============================================================================
class _CalendarSection extends ConsumerWidget {
  const _CalendarSection({
    required this.focusedMonth,
    required this.selectedDay,
    required this.onMonthChanged,
    required this.onDaySelected,
  });

  final DateTime focusedMonth;
  final DateTime? selectedDay;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final YearMonth ym = YearMonth(focusedMonth.year, focusedMonth.month);
    final AsyncValue<Map<DateTime, DaySummary>> summariesAsync =
        ref.watch(calendarMonthProvider(ym));

    final Map<DateTime, DaySummary> summaries = summariesAsync.maybeWhen(
      data: (Map<DateTime, DaySummary> m) => m,
      orElse: () => <DateTime, DaySummary>{},
    );

    // build 5: schedules を当月の day key 単位でグループ化
    final AsyncValue<List<ScheduleEntity>> schedulesAsync = ref.watch(
        schedulesInMonthProvider(
            YearMonthForSchedules(ym.year, ym.month)));
    final List<ScheduleEntity> schedules = schedulesAsync.maybeWhen(
      data: (List<ScheduleEntity> l) => l,
      orElse: () => <ScheduleEntity>[],
    );
    final Map<DateTime, List<ScheduleEntity>> schedulesByDay =
        <DateTime, List<ScheduleEntity>>{};
    for (final ScheduleEntity s in schedules) {
      final DateTime t = DateTime.fromMillisecondsSinceEpoch(s.scheduledAt);
      final DateTime key = DateTime(t.year, t.month, t.day);
      (schedulesByDay[key] ??= <ScheduleEntity>[]).add(s);
    }

    return PetloCalendarView(
      focusedMonth: focusedMonth,
      summaries: summaries,
      schedulesByDay: schedulesByDay,
      selectedDay: selectedDay,
      onMonthChanged: onMonthChanged,
      onDaySelected: onDaySelected,
      onDayLongPressed: (DateTime d) {
        ScheduleRecordScreen.push(context, initialDate: d);
      },
    );
  }
}

// ============================================================================
// Legend - dot indicator の凡例
// ============================================================================
class _Legend extends StatelessWidget {
  const _Legend({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: <Widget>[
        _LegendItem(color: colors.accentDanger, label: l10n.plans_legend_urgent),
        _LegendItem(color: colors.fg, label: l10n.plans_legend_health),
        _LegendItem(color: colors.fgMuted, label: l10n.plans_legend_daily),
        _LegendItem(color: colors.accentWarn, label: l10n.plans_legend_memory),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 11,
            color: colors.fgMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// UpcomingVaccinations (前のChunk 14版そのまま)
// ============================================================================
class _UpcomingVaccinations extends ConsumerWidget {
  const _UpcomingVaccinations();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    final AsyncValue<List<VaccinationEntity>> overdueAsync =
        ref.watch(overdueVaccinationsProvider);
    final AsyncValue<List<VaccinationEntity>> upcomingAsync =
        ref.watch(upcomingVaccinationsProvider);

    final List<VaccinationEntity> overdue = overdueAsync.maybeWhen(
      data: (l) => l,
      orElse: () => <VaccinationEntity>[],
    );
    final List<VaccinationEntity> upcoming = upcomingAsync.maybeWhen(
      data: (l) => l,
      orElse: () => <VaccinationEntity>[],
    );

    if (overdue.isEmpty && upcoming.isEmpty) {
      return Text(
        AppLocalizations.of(context).plans_no_upcoming,
        style: typo.bodySmall.copyWith(color: colors.fgMuted),
      );
    }

    return Column(
      children: <Widget>[
        for (final VaccinationEntity v in overdue)
          _PlanRow(vax: v, isOverdue: true),
        for (final VaccinationEntity v in upcoming)
          _PlanRow(vax: v, isOverdue: false),
      ],
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.vax, required this.isOverdue});

  final VaccinationEntity vax;
  final bool isOverdue;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    final DateTime? due = vax.nextDueAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(vax.nextDueAt!);

    final String dueLabel = due == null
        ? '—'
        : formatFullDate(
            due,
            Localizations.localeOf(context).toLanguageTag(),
          );

    return InkWell(
      onTap: () => VaccinationRecordScreen.push(
        context,
        editingVaccinationId: vax.id,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.line)),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 60,
              child: Text(
                isOverdue
                    ? AppLocalizations.of(context).plans_overdue_label
                    : AppLocalizations.of(context).plans_due_label,
                style: typo.metaSmall.copyWith(
                  color: isOverdue ? colors.accentDanger : colors.fgMuted,
                  fontWeight: isOverdue ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Text(
                vax.kind,
                style: typo.bodyMedium.copyWith(
                  color: isOverdue ? colors.accentDanger : colors.fg,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              dueLabel,
              style: typo.metaSmall.copyWith(color: colors.fgMuted),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// _ActiveReminders - グループ全体の有効リマインダー(最大3件プレビュー)
// ============================================================================
class _ActiveReminders extends ConsumerWidget {
  const _ActiveReminders();

  static List<String> _wdShort(BuildContext context) {
    final String locale = Localizations.localeOf(context).languageCode;
    if (locale == 'ja') {
      return const <String>['日', '月', '火', '水', '木', '金', '土'];
    }
    if (locale == 'zh') {
      return const <String>['日', '一', '二', '三', '四', '五', '六'];
    }
    return const <String>['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AsyncValue<List<MedicationReminderEntity>> remindersAsync =
        ref.watch(currentGroupEnabledRemindersProvider);

    return remindersAsync.maybeWhen(
      data: (List<MedicationReminderEntity> list) {
        if (list.isEmpty) {
          final AppLocalizations l10n = AppLocalizations.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.plans_no_reminders,
                style: typo.bodySmall.copyWith(color: colors.fgMuted),
              ),
              const SizedBox(height: 12),
              OutlinedActionButton(
                label: l10n.plans_set_reminder,
                onPressed: () =>
                    MedicationRemindersListScreen.push(context),
              ),
            ],
          );
        }
        // 最大3件をプレビュー
        return Column(
          children: <Widget>[
            for (final MedicationReminderEntity r in list.take(3))
              _MedRow(reminder: r),
            if (list.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: InkWell(
                  onTap: () =>
                      MedicationRemindersListScreen.push(context),
                  child: Text(
                    AppLocalizations.of(context)
                        .plans_more_count(list.length - 3),
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 12,
                      color: colors.fgMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _MedRow extends StatelessWidget {
  const _MedRow({required this.reminder});

  final MedicationReminderEntity reminder;

  String _formatTimes() {
    if (reminder.times.length <= 3) return reminder.times.join(' · ');
    return '${reminder.times.take(2).join(' · ')} +${reminder.times.length - 2}';
  }

  String _formatWeekdays(BuildContext context) {
    if (reminder.weekdaysBits.isEmpty) {
      return AppLocalizations.of(context).plans_every_day;
    }
    final List<int> sorted = reminder.weekdaysBits.toList()..sort();
    final List<String> wd = _ActiveReminders._wdShort(context);
    return sorted.map((int i) => wd[i]).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    return InkWell(
      onTap: () => MedicationRemindersListScreen.push(context),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.line)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    reminder.medicineName,
                    style: typo.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_formatTimes()} · ${_formatWeekdays(context)}',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10,
                      letterSpacing: 10 * 0.15,
                      color: colors.fgMuted,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// _ScheduleListView - 予定の一覧 (build 5)
//   フィルタ + 今日 / これから / 過去 のセクション分け
// ============================================================================
class _ScheduleListView extends ConsumerStatefulWidget {
  const _ScheduleListView();

  @override
  ConsumerState<_ScheduleListView> createState() =>
      _ScheduleListViewState();
}

class _ScheduleListViewState extends ConsumerState<_ScheduleListView> {
  ScheduleCategory? _filter; // null = すべて

  /// build 42: 過去の予定は默以折りたたみ。ephemeral state なので画面遷移後は
  /// 自動的に false にリセットされる(永続化しない方針)。
  bool _showPast = false;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    final AsyncValue<List<ScheduleEntity>> async =
        ref.watch(currentGroupSchedulesProvider);
    final List<ScheduleEntity> all = async.maybeWhen(
      data: (List<ScheduleEntity> l) => l,
      orElse: () => <ScheduleEntity>[],
    );

    final List<ScheduleEntity> filtered = _filter == null
        ? all
        : all.where((ScheduleEntity s) => s.category == _filter).toList();

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final List<ScheduleEntity> todays = <ScheduleEntity>[];
    final List<ScheduleEntity> upcoming = <ScheduleEntity>[];
    final List<ScheduleEntity> past = <ScheduleEntity>[];
    for (final ScheduleEntity s in filtered) {
      final DateTime t = DateTime.fromMillisecondsSinceEpoch(s.scheduledAt);
      final DateTime d = DateTime(t.year, t.month, t.day);
      if (d == today) {
        todays.add(s);
      } else if (d.isAfter(today)) {
        upcoming.add(s);
      } else {
        past.add(s);
      }
    }
    todays.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    upcoming.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    past.sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // フィルタチップ
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              _FilterChip(
                label: l10n.schedule_list_filter_all,
                selected: _filter == null,
                onTap: () => setState(() => _filter = null),
              ),
              for (final ScheduleCategory c in ScheduleCategory.values) ...<Widget>[
                const SizedBox(width: 6),
                _FilterChip(
                  label: scheduleCategoryLabel(l10n, c),
                  selected: _filter == c,
                  onTap: () => setState(() => _filter = c),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 追加ボタン
        InkWell(
          onTap: () => ScheduleRecordScreen.push(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: colors.fg, width: 1),
            ),
            child: Text(
              l10n.schedule_day_add_button,
              style: typo.bodyMedium.copyWith(
                color: colors.fg,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              l10n.schedule_list_empty,
              style: typo.bodyMedium.copyWith(color: colors.fgMuted),
            ),
          )
        else ...<Widget>[
          if (todays.isNotEmpty) ...<Widget>[
            SectionLabel(
              l10n.schedule_list_section_today,
              size: EyebrowSize.medium,
            ),
            const SizedBox(height: 8),
            for (final ScheduleEntity s in todays) _ScheduleListRow(s: s),
            const SizedBox(height: 24),
          ],
          if (upcoming.isNotEmpty) ...<Widget>[
            SectionLabel(
              l10n.schedule_list_section_upcoming,
              size: EyebrowSize.medium,
            ),
            const SizedBox(height: 8),
            for (final ScheduleEntity s in upcoming) _ScheduleListRow(s: s),
            const SizedBox(height: 24),
          ],
          // build 42: 過去予定は折りたたみ式トグルで表示切替
          _PastSectionToggle(
            expanded: _showPast,
            onTap: () => setState(() => _showPast = !_showPast),
            colors: colors,
            typo: typo,
            l10n: l10n,
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_showPast
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        SectionLabel(
                          l10n.schedule_list_section_past,
                          size: EyebrowSize.medium,
                        ),
                        const SizedBox(height: 8),
                        if (past.isEmpty)
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              l10n.plans_no_past_events,
                              style: typo.bodyMedium
                                  .copyWith(color: colors.fgMuted),
                            ),
                          )
                        else
                          for (final ScheduleEntity s in past)
                            _ScheduleListRow(s: s),
                      ],
                    ),
                  ),
          ),
        ],
      ],
    );
  }
}

/// build 42: 過去予定トグル行。アイコン + ラベルで「表示/隠す」を切り替える。
class _PastSectionToggle extends StatelessWidget {
  const _PastSectionToggle({
    required this.expanded,
    required this.onTap,
    required this.colors,
    required this.typo,
    required this.l10n,
  });

  final bool expanded;
  final VoidCallback onTap;
  final AppColors colors;
  final AppTypography typo;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              expanded
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down,
              size: 18,
              color: colors.fgMuted,
            ),
            const SizedBox(width: 6),
            Text(
              expanded
                  ? l10n.plans_hide_past_action
                  : l10n.plans_show_past_action,
              style: typo.bodySmall.copyWith(
                color: colors.fgMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? colors.fg : colors.bg,
          border: Border.all(color: colors.fg, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? colors.bg : colors.fg,
          ),
        ),
      ),
    );
  }
}

class _ScheduleListRow extends ConsumerWidget {
  const _ScheduleListRow({required this.s});

  final ScheduleEntity s;

  String _dateLabel(DateTime t, BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime d = DateTime(t.year, t.month, t.day);
    if (d == today) return l10n.record_today_label;
    return formatMonthDay(
      t,
      Localizations.localeOf(context).toLanguageTag(),
    );
  }

  String? _resolvePetName(WidgetRef ref) {
    if (s.relatedPetIds.isEmpty) return null;
    final int? firstId = int.tryParse(s.relatedPetIds.first);
    if (firstId == null) return null;
    final List<PetEntity>? pets =
        ref.watch(currentGroupPetsProvider).valueOrNull;
    if (pets == null) return null;
    for (final PetEntity p in pets) {
      if (p.id == firstId) return p.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(s.scheduledAt);

    final String? petIdStr = ref.watch(currentPetIdProvider);
    final bool isAllPets = petIdStr == kAllPetsId;
    final String? petName = isAllPets ? _resolvePetName(ref) : null;
    final String displayTitle =
        petName != null ? '$petName: ${s.title}' : s.title;

    return InkWell(
      onTap: () =>
          ScheduleRecordScreen.push(context, editingScheduleId: s.id),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.line)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: scheduleCategoryColor(colors, s.category),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 70,
              child: Text(
                _dateLabel(t, context),
                style: typo.bodySmall.copyWith(
                  color: colors.fgMuted,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Text(
                displayTitle,
                style: typo.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              scheduleCategoryLabel(l10n, s.category),
              style: typo.bodySmall.copyWith(color: colors.fgMuted),
            ),
          ],
        ),
      ),
    );
  }
}
