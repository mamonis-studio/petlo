// ============================================================================
// petlo - Prevention Notification Scheduler
// ============================================================================
//
// 予防コース (build 72 / v2 で配分方式を変更) の通知を DB の状態から組み立てる。
//
// ============================================================================
// v2 §5.4: スロット配分は「優先度ラダー」方式
// ============================================================================
//
// build 72 は course slot もまとめて scheduledDate 昇順の先着で 12 slot を
// 埋めていた。この方式には穴が 2 つあった。
//
//   (a) 月次の dose 通知が枠を食い尽くすと、シーズン前検査のリマインドが
//       押し出される。検査リマインドは安全に直結し §7 で無料開放と決めた
//       最優先事項であり、通常の投薬通知に負けてはならない。
//   (b) 「1 コースあたり直近 2 回だけ積む」は、記録もアプリ起動もしない
//       ユーザーに対して機能しない。2 回発火し切った時点で無通知になる。
//       月次リマインダーを最も必要とするのはまさにその層である。
//
// そこで配分を先着から **優先度順の貪欲充填** に変更した。
//
//   Tier 1 [予約 最大 4]  course slot 0/1  検査リマインド (シーズン開始日 昇順)
//   Tier 2                dose slot 0      当日通知 (scheduledDate 昇順)
//                                          ★ 1 コースあたりの上限を持たない
//   Tier 3                dose slot 2      最終回 3 日前 (Pro / isFinal)
//   Tier 4                dose slot 1      翌日の追撃 (Pro)
//   Tier 5                course slot 2    翌シーズン案内 (Pro)
//
// Tier 1 の「予約」は、Tier 2 以降を積む前に min(所要数, 4) を残バジェットから
// 先に差し引くことで実現する。Tier 1 が 1 slot しか使わなければ残り 11 が
// 下位ティアに回る。
//
// 過去日 (fireAt <= now) は積まない。これにより §8.4 の「過去年コースには
// 通知を一切スケジュールしない」も自動的に満たされる。
//
// 配分ロジックは PreventionSlotPlanner に純粋関数として切り出してある。
// プラットフォーム呼び出しを伴わないためユニットテストで検算できる。
//
// 通知 ID:
//   dose   → NotificationService.idForPreventionDose(doseId, slot)   slot 0-2
//   course → NotificationService.idForPreventionCourse(courseId, s)  slot 0-2
//
// 課金ゲート (§7):
//   dose slot 0 (当日) と course slot 0/1 (検査) は無料でも通知する。
//   検査リマインドは安全に直結するので課金の壁にしない。
//   dose slot 1/2 と course slot 2 は Pro のみ。
//
// 文言に医学的な断定を入れてはならない (§9.2)。
//
// ============================================================================

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/pets_repository.dart';
import '../../data/repositories/prevention_courses_repository.dart';
import '../../data/repositories/prevention_doses_repository.dart';
import '../../l10n/generated/app_localizations.dart';
import '../constants/app_constants.dart';
import '../notifications/notification_scheduler.dart';
import '../notifications/notification_service.dart';
import '../utils/date_formatters.dart';
import '../utils/logger.dart';
import 'prevention_labels.dart';

/// dose 1 件が使う slot 数 (当日 / 翌日 / 最終回3日前)
const int _kDoseSlotSpan = 3;

/// course 1 件が使う slot 数 (検査30日前 / 検査7日前 / 翌シーズン案内)
const int _kCourseSlotSpan = 3;

/// build 73 (v2): 予防バジェット内で検査リマインドに予約する上限。
const int kPreventionTestReminderReserve = 4;

// ============================================================================
// 配分の型
// ============================================================================

/// 積むべき通知 1 件の種別。ティアの優先順位もこの順序に対応する。
enum PreventionSlotKind {
  /// Tier 1: シーズン開始 30 日前の検査リマインド (course slot 0)
  testReminder30,

  /// Tier 1: シーズン開始 7 日前の検査リマインド (course slot 1)
  testReminder7,

  /// Tier 2: 予定日当日 (dose slot 0)
  doseDue,

  /// Tier 3: 最終回の 3 日前 (dose slot 2)
  doseFinal,

  /// Tier 4: 予定日翌日の追撃 (dose slot 1)
  doseFollowUp,

  /// Tier 5: 翌シーズン案内 (course slot 2)
  nextSeason,
}

/// 配分結果の 1 件。実際の通知登録はこの計画に従って行う。
@immutable
class PreventionNotificationSlot {
  const PreventionNotificationSlot({
    required this.kind,
    required this.courseId,
    required this.notificationSlot,
    required this.fireAt,
    this.doseId,
  });

  final PreventionSlotKind kind;
  final int courseId;

  /// dose 由来の通知のみ非 null
  final int? doseId;

  /// NotificationService の slot 番号 (0-2)
  final int notificationSlot;

  final DateTime fireAt;

  @override
  String toString() => 'PreventionNotificationSlot(${kind.name}, '
      'course=$courseId, dose=$doseId, slot=$notificationSlot, at=$fireAt)';
}

/// 1 コース分の計画入力 (コース本体 + その dose 群)
typedef PreventionCoursePlanInput = ({
  PreventionCourseEntity course,
  List<PreventionDoseEntity> doses,
});

// ============================================================================
// PreventionSlotPlanner — 配分の純粋ロジック (v2 §5.4)
// ============================================================================

abstract final class PreventionSlotPlanner {
  PreventionSlotPlanner._();

  /// 優先度ラダーに従って積むべき通知を決める。
  ///
  /// プラットフォームに触れないので、§5.4「配分の検算」をそのまま
  /// ユニットテストで確認できる。
  static List<PreventionNotificationSlot> plan({
    required List<PreventionCoursePlanInput> inputs,
    required DateTime now,
    required bool isPro,
    int budget = kPreventionSlotBudget,
    int testReserve = kPreventionTestReminderReserve,
  }) {
    final List<_Candidate> tier1 = <_Candidate>[];
    final List<_Candidate> tier2 = <_Candidate>[];
    final List<_Candidate> tier3 = <_Candidate>[];
    final List<_Candidate> tier4 = <_Candidate>[];
    final List<_Candidate> tier5 = <_Candidate>[];

    for (final PreventionCoursePlanInput input in inputs) {
      final PreventionCourseEntity course = input.course;
      if (!course.notificationEnabled) continue;
      if (course.deletedAt != null) continue;

      // ===== course 由来 =====
      final DateTime seasonStart9am = _seasonStart9am(course);

      // Tier 1: シーズン前検査。ノミダニ単独は検査対象外なので出さない。
      final bool wantsTestReminder = course.kind != PreventionKind.flea_tick &&
          course.testReminderEnabled &&
          course.testedAt == null;
      if (wantsTestReminder) {
        final DateTime t30 = seasonStart9am.subtract(const Duration(days: 30));
        if (t30.isAfter(now)) {
          tier1.add(_Candidate(
            slot: PreventionNotificationSlot(
              kind: PreventionSlotKind.testReminder30,
              courseId: course.id,
              notificationSlot: 0,
              fireAt: t30,
            ),
            // 「シーズン開始日の昇順」で並べる (§5.4)
            sortKey: seasonStart9am.millisecondsSinceEpoch,
            tieBreak: 0,
          ));
        }
        final DateTime t7 = seasonStart9am.subtract(const Duration(days: 7));
        if (t7.isAfter(now)) {
          tier1.add(_Candidate(
            slot: PreventionNotificationSlot(
              kind: PreventionSlotKind.testReminder7,
              courseId: course.id,
              notificationSlot: 1,
              fireAt: t7,
            ),
            sortKey: seasonStart9am.millisecondsSinceEpoch,
            tieBreak: 1,
          ));
        }
      }

      // Tier 5: 翌シーズン案内 (Pro)
      if (isPro) {
        final DateTime? nextSeasonAt = _nextSeasonAt(course);
        if (nextSeasonAt != null && nextSeasonAt.isAfter(now)) {
          tier5.add(_Candidate(
            slot: PreventionNotificationSlot(
              kind: PreventionSlotKind.nextSeason,
              courseId: course.id,
              notificationSlot: 2,
              fireAt: nextSeasonAt,
            ),
            sortKey: nextSeasonAt.millisecondsSinceEpoch,
            tieBreak: 0,
          ));
        }
      }

      // ===== dose 由来 =====
      for (final PreventionDoseEntity dose in input.doses) {
        if (dose.deletedAt != null) continue;
        if (dose.administeredAt != null || dose.skipped) continue;

        final DateTime onDay = _doseFireTime(course, dose);

        // Tier 2: 当日通知。1 コースあたりの上限は設けない (v2)。
        if (onDay.isAfter(now)) {
          tier2.add(_Candidate(
            slot: PreventionNotificationSlot(
              kind: PreventionSlotKind.doseDue,
              courseId: course.id,
              doseId: dose.id,
              notificationSlot: 0,
              fireAt: onDay,
            ),
            sortKey: dose.scheduledDate,
            tieBreak: dose.id,
          ));
        }

        // Tier 3: 最終回の 3 日前 (Pro)
        if (isPro && dose.isFinal) {
          final DateTime t3 = onDay.subtract(const Duration(days: 3));
          if (t3.isAfter(now)) {
            tier3.add(_Candidate(
              slot: PreventionNotificationSlot(
                kind: PreventionSlotKind.doseFinal,
                courseId: course.id,
                doseId: dose.id,
                notificationSlot: 2,
                fireAt: t3,
              ),
              sortKey: t3.millisecondsSinceEpoch,
              tieBreak: dose.id,
            ));
          }
        }

        // Tier 4: 翌日の追撃 (Pro)
        if (isPro) {
          final DateTime followUp = onDay.add(const Duration(days: 1));
          if (followUp.isAfter(now)) {
            tier4.add(_Candidate(
              slot: PreventionNotificationSlot(
                kind: PreventionSlotKind.doseFollowUp,
                courseId: course.id,
                doseId: dose.id,
                notificationSlot: 1,
                fireAt: followUp,
              ),
              sortKey: followUp.millisecondsSinceEpoch,
              tieBreak: dose.id,
            ));
          }
        }
      }
    }

    for (final List<_Candidate> tier in <List<_Candidate>>[
      tier1,
      tier2,
      tier3,
      tier4,
      tier5,
    ]) {
      tier.sort(_Candidate.compare);
    }

    // Tier 1 の予約: 所要数と上限の小さい方を先に確保し、残りを下位へ流す。
    final int reserve = math.min(tier1.length, math.max(0, testReserve));
    final int reserved = math.min(reserve, math.max(0, budget));
    int remaining = math.max(0, budget - reserved);

    final List<PreventionNotificationSlot> out = <PreventionNotificationSlot>[];
    for (final _Candidate c in tier1.take(reserved)) {
      out.add(c.slot);
    }
    for (final List<_Candidate> tier in <List<_Candidate>>[
      tier2,
      tier3,
      tier4,
      tier5,
    ]) {
      for (final _Candidate c in tier) {
        if (remaining <= 0) break;
        out.add(c.slot);
        remaining--;
      }
      if (remaining <= 0) break;
    }
    return out;
  }

  /// シーズン開始日の朝 9 時
  static DateTime _seasonStart9am(PreventionCourseEntity course) {
    final DateTime start = DateTime.fromMillisecondsSinceEpoch(
      PreventionCoursesRepository.scheduledDateFor(
        course.year,
        course.startMonth,
        course.dayOfMonth,
      ),
    );
    return DateTime(start.year, start.month, start.day, 9);
  }

  /// シーズン終了 + 90 日後の朝 9 時
  static DateTime? _nextSeasonAt(PreventionCourseEntity course) {
    final List<PreventionPlannedMonth> planned =
        PreventionCoursesRepository.plannedMonthsOf(course);
    if (planned.isEmpty) return null;
    final PreventionPlannedMonth last = planned.last;
    final DateTime end = DateTime.fromMillisecondsSinceEpoch(
      PreventionCoursesRepository.scheduledDateFor(
        last.year,
        last.month,
        course.dayOfMonth,
      ),
    );
    return DateTime(end.year, end.month, end.day, 9)
        .add(const Duration(days: 90));
  }

  /// dose の発火時刻 (予定日の notifyTime)
  static DateTime _doseFireTime(
    PreventionCourseEntity course,
    PreventionDoseEntity dose,
  ) {
    final DateTime scheduled =
        DateTime.fromMillisecondsSinceEpoch(dose.scheduledDate);
    final ({int hour, int minute}) time = parseHHmm(course.notifyTime);
    return DateTime(
      scheduled.year,
      scheduled.month,
      scheduled.day,
      time.hour,
      time.minute,
    );
  }

  /// "HH:mm" を解釈する。壊れていれば 09:00 に倒す。
  static ({int hour, int minute}) parseHHmm(String hhmm) {
    final RegExpMatch? m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(hhmm);
    if (m == null) return (hour: 9, minute: 0);
    final int h = int.parse(m.group(1)!);
    final int min = int.parse(m.group(2)!);
    if (h < 0 || h > 23 || min < 0 || min > 59) return (hour: 9, minute: 0);
    return (hour: h, minute: min);
  }
}

@immutable
class _Candidate {
  const _Candidate({
    required this.slot,
    required this.sortKey,
    required this.tieBreak,
  });

  final PreventionNotificationSlot slot;
  final int sortKey;
  final int tieBreak;

  static int compare(_Candidate a, _Candidate b) {
    final int c = a.sortKey.compareTo(b.sortKey);
    return c != 0 ? c : a.tieBreak.compareTo(b.tieBreak);
  }
}

// ============================================================================
// PreventionNotificationScheduler — 計画の実行
// ============================================================================

class PreventionNotificationScheduler {
  PreventionNotificationScheduler({
    required NotificationService service,
    required PreventionCoursesRepository coursesRepo,
    required PreventionDosesRepository dosesRepo,
    required PetsRepository petsRepo,
  })  : _service = service,
        _coursesRepo = coursesRepo,
        _dosesRepo = dosesRepo,
        _petsRepo = petsRepo;

  final NotificationService _service;
  final PreventionCoursesRepository _coursesRepo;
  final PreventionDosesRepository _dosesRepo;
  final PetsRepository _petsRepo;

  static const String _channelId = 'petlo_prevention';
  static const String _channelName = 'petlo prevention';

  // ==========================================================================
  // 再構築
  // ==========================================================================

  /// 全コースの予防通知を組み直す。冪等 (cancel してから積み直す)。
  ///
  /// [isPro] が false のときは Pro 限定 slot を積まない。
  Future<void> rescheduleAllPreventions({required bool isPro}) async {
    try {
      final List<PreventionCourseEntity> courses =
          await _coursesRepo.getAllActiveByCreation();

      // 先に全部消す (コース削除・dose 削除の取りこぼしを防ぐ)
      for (final PreventionCourseEntity c in courses) {
        await cancelCourse(c.id);
      }

      // build 73: キルスイッチ (2)。main.dart 側でも弾いているが、UI からの
      // 呼び出し (投与記録 / コース編集 / 削除) をまとめて塞ぐためここでも見る。
      // 上の cancel は通したので、フラグを倒した状態で起動すれば
      // 既に積まれている予防通知も一掃される。
      if (!AppConstants.enablePrevention) {
        PetloLogger.instance
            .i('Prevention is disabled by kill switch; cleared notifications');
        return;
      }

      final List<PreventionCoursePlanInput> inputs =
          <PreventionCoursePlanInput>[];
      final Map<int, PreventionCourseEntity> courseById =
          <int, PreventionCourseEntity>{};
      final Map<int, PreventionDoseEntity> doseById =
          <int, PreventionDoseEntity>{};
      for (final PreventionCourseEntity c in courses) {
        final List<PreventionDoseEntity> doses =
            await _dosesRepo.getForCourse(c.id);
        inputs.add((course: c, doses: doses));
        courseById[c.id] = c;
        for (final PreventionDoseEntity d in doses) {
          doseById[d.id] = d;
        }
      }

      final List<PreventionNotificationSlot> planned =
          PreventionSlotPlanner.plan(
        inputs: inputs,
        now: DateTime.now(),
        isPro: isPro,
      );

      PetloLogger.instance.i(
        'Rescheduling prevention: ${courses.length} course(s), '
        '${planned.length}/$kPreventionSlotBudget slot(s)',
      );

      final AppLocalizations l10n = _platformL10n();
      final Map<int, String> petNames = <int, String>{};

      for (final PreventionNotificationSlot s in planned) {
        final PreventionCourseEntity? course = courseById[s.courseId];
        if (course == null) continue;
        final String petName =
            petNames[course.petId] ??= await _petName(course.petId);
        await _schedule(
          slot: s,
          course: course,
          dose: s.doseId == null ? null : doseById[s.doseId],
          petName: petName,
          l10n: l10n,
        );
      }
    } catch (e, st) {
      PetloLogger.instance
          .w('rescheduleAllPreventions failed', error: e, stackTrace: st);
    }
  }

  /// コース 1 件分の通知をすべてキャンセルする。
  /// dose 側は「そのコースに属する全 dose」を対象にする。
  Future<void> cancelCourse(int courseId) async {
    await _service.cancelRange(
      NotificationService.idForPreventionCourse(courseId, 0),
      _kCourseSlotSpan,
    );
    final List<PreventionDoseEntity> doses =
        await _dosesRepo.getForCourse(courseId);
    for (final PreventionDoseEntity d in doses) {
      await cancelDose(d.id);
    }
  }

  /// dose 1 件分の通知 (slot 0-2) をキャンセルする。
  Future<void> cancelDose(int doseId) {
    return _service.cancelRange(
      NotificationService.idForPreventionDose(doseId, 0),
      _kDoseSlotSpan,
    );
  }

  // ==========================================================================
  // 1 件の実行
  // ==========================================================================

  Future<void> _schedule({
    required PreventionNotificationSlot slot,
    required PreventionCourseEntity course,
    required PreventionDoseEntity? dose,
    required String petName,
    required AppLocalizations l10n,
  }) async {
    final int id = slot.doseId == null
        ? NotificationService.idForPreventionCourse(
            slot.courseId, slot.notificationSlot)
        : NotificationService.idForPreventionDose(
            slot.doseId!, slot.notificationSlot);

    late final String title;
    late final String body;

    switch (slot.kind) {
      case PreventionSlotKind.testReminder30:
        title = l10n.prevention_notify_test_title(petName);
        body = l10n.prevention_notify_test_body;
      case PreventionSlotKind.testReminder7:
        title = l10n.prevention_notify_test_again_title(petName);
        body = l10n.prevention_notify_test_again_body;
      case PreventionSlotKind.doseDue:
        title = l10n.prevention_notify_due_title(petName);
        body = l10n.prevention_notify_due_body(
          PreventionLabels.kind(course.kind, l10n),
        );
      case PreventionSlotKind.doseFinal:
        final DateTime onDay = dose == null
            ? slot.fireAt.add(const Duration(days: 3))
            : PreventionSlotPlanner._doseFireTime(course, dose);
        title = l10n.prevention_notify_final_title(petName);
        body = l10n.prevention_notify_final_body(
          formatMonthDay(onDay, _platformLocale().toLanguageTag()),
        );
      case PreventionSlotKind.doseFollowUp:
        title = l10n.prevention_notify_followup_title(petName);
        body = l10n.prevention_notify_followup_body;
      case PreventionSlotKind.nextSeason:
        title = l10n.prevention_notify_next_season_title(petName);
        body = l10n.prevention_notify_next_season_body;
    }

    await _service.scheduleOneTime(
      id: id,
      title: title,
      body: body,
      scheduledAt: slot.fireAt,
      channelId: _channelId,
      channelName: _channelName,
    );

    if (kDebugMode) {
      PetloLogger.instance.d('Scheduled prevention $slot');
    }
  }

  // ==========================================================================
  // Helpers
  // ==========================================================================

  Future<String> _petName(int petId) async {
    try {
      final PetEntity? pet = await _petsRepo.getPet(petId);
      return pet?.name ?? '';
    } catch (_) {
      return '';
    }
  }

  /// context が無いコードパス用に platform locale で l10n を解決する。
  AppLocalizations _platformL10n() {
    return lookupAppLocalizations(_platformLocale());
  }

  Locale _platformLocale() {
    final Locale platform =
        WidgetsBinding.instance.platformDispatcher.locale;
    return AppLocalizations.supportedLocales.firstWhere(
      (Locale l) => l.languageCode == platform.languageCode,
      orElse: () => const Locale('ja'),
    );
  }
}
