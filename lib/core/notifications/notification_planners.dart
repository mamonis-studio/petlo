// ============================================================================
// petlo - Notification Planners
// ============================================================================
//
// 3 系統それぞれの「積みたい通知」を **純粋関数** で組み立てる (build 73)。
//
// build 72 までは各系統が直接プラットフォームへ登録していたため、
//   - 合計を見ている者が居ない
//   - 何が溢れたか分からない
//   - テストで配分を確かめられない
// という状態だった。ここで「計画」と「実行」を分離する。
//
//   [planner] → List<NotificationCandidate> → [Allocator] → [Executor]
//
// planner はリポジトリにもプラットフォームにも触れない。入力はエンティティ、
// 出力は候補リストだけ。時刻計算と文言解決だけを担当する。
//
// rank の意味 (Allocator の Tier 1 で使う系統内優先度):
//   vaccination / schedule … 直近順。3 か月先より明日を優先する
//   prevention             … 優先度ラダー (v2 §5.4)。検査リマインドが先頭
//
// ============================================================================

import 'dart:convert';

import '../../data/local/app_database.dart';
import '../../l10n/generated/app_localizations.dart';
import '../prevention/prevention_labels.dart';
import '../prevention/prevention_notification_scheduler.dart';
import '../utils/date_formatters.dart';
import '../utils/logger.dart';
import 'notification_budget_allocator.dart';
import 'notification_service.dart';

// ============================================================================
// ワクチン
// ============================================================================

abstract final class VaccinationNotificationPlanner {
  VaccinationNotificationPlanner._();

  static const String channelId = 'petlo_vaccinations';
  static const String channelName = 'petlo vaccinations';

  /// 1 件につき 3 日前 (slot 0) と当日 (slot 1) の 2 候補。
  /// どちらも朝 9 時に発火する。
  static List<NotificationCandidate> plan({
    required List<VaccinationEntity> vaccinations,
    required AppLocalizations l10n,
    required DateTime now,
  }) {
    final List<NotificationCandidate> out = <NotificationCandidate>[];

    for (final VaccinationEntity v in vaccinations) {
      if (v.deletedAt != null) continue;
      final int? nextDue = v.nextDueAt;
      if (nextDue == null) continue;

      final DateTime due = DateTime.fromMillisecondsSinceEpoch(nextDue);
      final DateTime onDay = DateTime(due.year, due.month, due.day, 9);
      final DateTime threeDaysBefore = onDay.subtract(const Duration(days: 3));

      if (threeDaysBefore.isAfter(now)) {
        out.add(NotificationCandidate(
          system: NotificationSystem.vaccination,
          id: NotificationService.idForVaccination(v.id, 0),
          fireAt: threeDaysBefore,
          rank: 0, // 後でまとめて直近順に振り直す
          title: l10n.notification_vaccination_upcoming_title,
          body: l10n.notification_vaccination_upcoming_body(v.kind),
          channelId: channelId,
          channelName: channelName,
        ));
      }
      if (onDay.isAfter(now)) {
        out.add(NotificationCandidate(
          system: NotificationSystem.vaccination,
          id: NotificationService.idForVaccination(v.id, 1),
          fireAt: onDay,
          rank: 0,
          title: l10n.notification_vaccination_today_title,
          body: l10n.notification_vaccination_today_body(v.kind),
          channelId: channelId,
          channelName: channelName,
        ));
      }
    }

    return assignRankByFireAt(out);
  }
}

// ============================================================================
// schedule (投薬など)
// ============================================================================

abstract final class ScheduleNotificationPlanner {
  ScheduleNotificationPlanner._();

  /// timeIndex の上限。ID 幅 64 に収めるため 0-6 まで (weekdaySlot と合わせて)。
  static const int maxTimes = 7;

  static List<NotificationCandidate> plan({
    required List<ScheduleEntity> schedules,
    required AppLocalizations l10n,
    required DateTime now,
  }) {
    final List<NotificationCandidate> out = <NotificationCandidate>[];

    for (final ScheduleEntity s in schedules) {
      if (s.deletedAt != null) continue;
      final String body = _body(s, l10n);

      // ===== 繰り返し (medication カテゴリ + times) =====
      if (s.category == ScheduleCategory.medication && s.times != null) {
        final List<String> times = decodeTimes(s.times);
        final Set<int> weekdays = decodeWeekdays(s.weekdaysBits);
        final int limit = times.length > maxTimes ? maxTimes : times.length;

        for (int i = 0; i < limit; i++) {
          final ({int hour, int minute})? t = parseHHmm(times[i]);
          if (t == null) continue;

          if (weekdays.isEmpty) {
            // 毎日 → weekdaySlot 7
            out.add(NotificationCandidate(
              system: NotificationSystem.schedule,
              id: NotificationService.idForSchedule(s.id, i, 7),
              fireAt: nextDailyOccurrence(now, t.hour, t.minute),
              rank: 0,
              title: s.title,
              body: body,
              kind: NotificationKind.dailyRepeat,
              hour: t.hour,
              minute: t.minute,
            ));
          } else {
            for (final int wd in weekdays) {
              if (wd < 0 || wd > 6) continue;
              out.add(NotificationCandidate(
                system: NotificationSystem.schedule,
                id: NotificationService.idForSchedule(s.id, i, wd),
                fireAt: nextWeeklyOccurrence(now, t.hour, t.minute, wd),
                rank: 0,
                title: s.title,
                body: body,
                kind: NotificationKind.dailyRepeat,
                hour: t.hour,
                minute: t.minute,
                weekday: wd,
              ));
            }
          }
        }
      }

      // ===== one-shot (notificationTiming) =====
      final DateTime? oneShot = oneShotFireTime(s);
      if (oneShot != null && oneShot.isAfter(now)) {
        out.add(NotificationCandidate(
          system: NotificationSystem.schedule,
          id: NotificationService.idForScheduleOneShot(s.id),
          fireAt: oneShot,
          rank: 0,
          title: s.title,
          body: body,
        ));
      }
    }

    return assignRankByFireAt(out);
  }

  static String _body(ScheduleEntity s, AppLocalizations l10n) {
    final String? notes = s.notes;
    if (notes != null && notes.trim().isNotEmpty) return notes.trim();
    return l10n.notification_medication_default_body;
  }
}

// ============================================================================
// 予防
// ============================================================================

abstract final class PreventionNotificationPlanner {
  PreventionNotificationPlanner._();

  static const String channelId = 'petlo_prevention';
  static const String channelName = 'petlo prevention';

  /// PreventionSlotPlanner に「打ち切らせない」ための十分大きな値。
  /// 打ち切りは Allocator の責任に一元化した。ここでは順序だけが欲しい。
  static const int _unbounded = 1 << 20;

  /// 予防のラダー順 (v2 §5.4) をそのまま rank にする。
  /// 先頭 4 件が検査リマインドなので、どこで打ち切られても予約枠が保たれる。
  static List<NotificationCandidate> plan({
    required List<PreventionCoursePlanInput> inputs,
    required Map<int, PreventionCourseEntity> courseById,
    required Map<int, PreventionDoseEntity> doseById,
    required Map<int, String> petNames,
    required AppLocalizations l10n,
    required String localeTag,
    required DateTime now,
    required bool isPro,
  }) {
    final List<PreventionNotificationSlot> planned =
        PreventionSlotPlanner.plan(
      inputs: inputs,
      now: now,
      isPro: isPro,
      budget: _unbounded,
    );

    final List<NotificationCandidate> out = <NotificationCandidate>[];
    for (int i = 0; i < planned.length; i++) {
      final PreventionNotificationSlot s = planned[i];
      final PreventionCourseEntity? course = courseById[s.courseId];
      if (course == null) continue;
      final String petName = petNames[course.petId] ?? '';

      final ({String title, String body}) text = _textFor(
        slot: s,
        course: course,
        dose: s.doseId == null ? null : doseById[s.doseId],
        petName: petName,
        l10n: l10n,
        localeTag: localeTag,
      );

      out.add(NotificationCandidate(
        system: NotificationSystem.prevention,
        id: s.doseId == null
            ? NotificationService.idForPreventionCourse(
                s.courseId, s.notificationSlot)
            : NotificationService.idForPreventionDose(
                s.doseId!, s.notificationSlot),
        fireAt: s.fireAt,
        rank: i, // ラダー順をそのまま優先度にする
        title: text.title,
        body: text.body,
        channelId: channelId,
        channelName: channelName,
      ));
    }
    return out;
  }

  static ({String title, String body}) _textFor({
    required PreventionNotificationSlot slot,
    required PreventionCourseEntity course,
    required PreventionDoseEntity? dose,
    required String petName,
    required AppLocalizations l10n,
    required String localeTag,
  }) {
    switch (slot.kind) {
      case PreventionSlotKind.testReminder30:
        return (
          title: l10n.prevention_notify_test_title(petName),
          body: l10n.prevention_notify_test_body,
        );
      case PreventionSlotKind.testReminder7:
        return (
          title: l10n.prevention_notify_test_again_title(petName),
          body: l10n.prevention_notify_test_again_body,
        );
      case PreventionSlotKind.doseDue:
        return (
          title: l10n.prevention_notify_due_title(petName),
          body: l10n.prevention_notify_due_body(
            PreventionLabels.kind(course.kind, l10n),
          ),
        );
      case PreventionSlotKind.doseFinal:
        final DateTime onDay = slot.fireAt.add(const Duration(days: 3));
        return (
          title: l10n.prevention_notify_final_title(petName),
          body: l10n.prevention_notify_final_body(
            formatMonthDay(onDay, localeTag),
          ),
        );
      case PreventionSlotKind.doseFollowUp:
        return (
          title: l10n.prevention_notify_followup_title(petName),
          body: l10n.prevention_notify_followup_body,
        );
      case PreventionSlotKind.nextSeason:
        return (
          title: l10n.prevention_notify_next_season_title(petName),
          body: l10n.prevention_notify_next_season_body,
        );
    }
  }
}

// ============================================================================
// 共有ヘルパー (テストからも使えるよう公開)
// ============================================================================

/// 直近順に rank を振り直す。同時刻は id で安定化する。
List<NotificationCandidate> assignRankByFireAt(
  List<NotificationCandidate> candidates,
) {
  final List<NotificationCandidate> sorted =
      List<NotificationCandidate>.of(candidates)
        ..sort((NotificationCandidate a, NotificationCandidate b) {
          final int f = a.fireAt.compareTo(b.fireAt);
          return f != 0 ? f : a.id.compareTo(b.id);
        });
  return <NotificationCandidate>[
    for (int i = 0; i < sorted.length; i++)
      NotificationCandidate(
        system: sorted[i].system,
        id: sorted[i].id,
        fireAt: sorted[i].fireAt,
        rank: i,
        title: sorted[i].title,
        body: sorted[i].body,
        kind: sorted[i].kind,
        channelId: sorted[i].channelId,
        channelName: sorted[i].channelName,
        hour: sorted[i].hour,
        minute: sorted[i].minute,
        weekday: sorted[i].weekday,
      ),
  ];
}

/// 次に来る指定時刻 (今日その時刻が過ぎていれば明日)
DateTime nextDailyOccurrence(DateTime now, int hour, int minute) {
  DateTime d = DateTime(now.year, now.month, now.day, hour, minute);
  if (!d.isAfter(now)) d = d.add(const Duration(days: 1));
  return d;
}

/// 次に来る指定曜日の指定時刻。[weekday] は 0=日曜 .. 6=土曜
/// (NotificationService._nextInstanceOfWeekday と同じ規約)
DateTime nextWeeklyOccurrence(
  DateTime now,
  int hour,
  int minute,
  int weekday,
) {
  // DateTime.weekday は 1=月 .. 7=日
  final int target = weekday == 0 ? 7 : weekday;
  DateTime d = DateTime(now.year, now.month, now.day, hour, minute);
  int add = (target - d.weekday) % 7;
  if (add < 0) add += 7;
  d = d.add(Duration(days: add));
  if (!d.isAfter(now)) d = d.add(const Duration(days: 7));
  return d;
}

({int hour, int minute})? parseHHmm(String hhmm) {
  final RegExpMatch? m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(hhmm);
  if (m == null) return null;
  final int h = int.parse(m.group(1)!);
  final int min = int.parse(m.group(2)!);
  if (h < 0 || h > 23 || min < 0 || min > 59) return null;
  return (hour: h, minute: min);
}

List<String> decodeTimes(String? raw) {
  if (raw == null || raw.isEmpty) return const <String>[];
  try {
    final dynamic decoded = jsonDecode(raw);
    if (decoded is List) return decoded.whereType<String>().toList();
  } catch (e, st) {
    // build 73: 黙って空を返さない。ここが空になると
    // 「時刻が設定されていない」のと区別がつかず、通知が 1 件も
    // 積まれない状態が正常に見えてしまう。
    PetloLogger.instance.w('decodeTimes failed (notifications will be empty)',
        error: e, stackTrace: st);
  }
  return const <String>[];
}

Set<int> decodeWeekdays(int? bits) {
  if (bits == null || bits == 0) return const <int>{};
  final Set<int> out = <int>{};
  for (int i = 0; i < 7; i++) {
    if ((bits & (1 << i)) != 0) out.add(i);
  }
  return out;
}

/// notificationTiming に従った one-shot 発火時刻
DateTime? oneShotFireTime(ScheduleEntity s) {
  if (s.notificationTiming == ScheduleNotificationTiming.none) return null;
  final DateTime scheduledAt =
      DateTime.fromMillisecondsSinceEpoch(s.scheduledAt);
  final DateTime onDay = s.hasTime
      ? scheduledAt
      : DateTime(scheduledAt.year, scheduledAt.month, scheduledAt.day, 9);
  switch (s.notificationTiming) {
    case ScheduleNotificationTiming.on_day:
      return onDay;
    case ScheduleNotificationTiming.day_before:
      return onDay.subtract(const Duration(days: 1));
    case ScheduleNotificationTiming.week_before:
      return onDay.subtract(const Duration(days: 7));
    case ScheduleNotificationTiming.none:
      return null;
  }
}
