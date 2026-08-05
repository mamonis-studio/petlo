// ============================================================================
// petlo - Notification Coordinator
// ============================================================================
//
// **3 系統の合計を見る唯一の場所** (build 73)。
//
//   [3 つの planner] → [Allocator] → [ここで実行] → [レポート永続化]
//
// ============================================================================
// なぜ部分更新をやめたか
// ============================================================================
//
// build 72 までは「ワクチンを 1 件足したら、その 1 件だけを登録する」形
// (syncVaccinationDueAlert(id)) だった。この形では総量を守れない。
// 追加する側は他系統が何件積んでいるかを知らないからである。
// 実際に Phase C ではワクチンが 64 枠中 47 を占領した。
//
// そこで **変更のたびに全体を再割り当てする**。上限 64 に対して
// 高々 64 件の登録なので、実測でも十分速い (§ 所要時間はレポート参照)。
//
// ============================================================================
// 落ちたときの回復経路
// ============================================================================
//
// cancel してから schedule するまでの間にアプリが死ぬと、通知が消えたまま
// 固定されるおそれがある。これを 2 段構えで防ぐ:
//
//   1. **差分キャンセル**
//      新しい割り当てに残る ID は cancel しない。実際に消すのは
//      「今 OS にあるが新しい割り当てに無い」ものだけ。
//      再割り当ての大半は「同じ ID を上書き登録するだけ」になり、
//      無通知になる窓がそもそも生まれない。
//
//   2. **起動時の無条件再実行**
//      main.dart が起動のたびに rescheduleAll() を呼ぶ。
//      仮に 1 の途中で死んでも、次回起動で必ず正しい状態に収束する。
//      DB が真実の source であり、OS 側の通知は導出物にすぎない。
//
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show PendingNotificationRequest;

import '../../data/local/app_database.dart';
import '../../data/repositories/pets_repository.dart';
import '../../data/repositories/prevention_courses_repository.dart';
import '../../data/repositories/prevention_doses_repository.dart';
import '../../data/repositories/schedules_repository.dart';
import '../../data/repositories/vaccinations_repository.dart';
import '../../l10n/generated/app_localizations.dart';
import '../constants/app_constants.dart';
import '../preferences/user_preferences.dart';
import '../prevention/prevention_notification_scheduler.dart';
import '../utils/logger.dart';
import 'notification_budget_allocator.dart';
import 'notification_planners.dart';
import 'notification_scheduler.dart';
import 'notification_service.dart';

class NotificationCoordinator {
  NotificationCoordinator({
    required NotificationService service,
    required SchedulesRepository schedulesRepo,
    required VaccinationsRepository vaccinationsRepo,
    required PreventionCoursesRepository preventionCoursesRepo,
    required PreventionDosesRepository preventionDosesRepo,
    required PetsRepository petsRepo,
  })  : _service = service,
        _schedulesRepo = schedulesRepo,
        _vaccinationsRepo = vaccinationsRepo,
        _preventionCoursesRepo = preventionCoursesRepo,
        _preventionDosesRepo = preventionDosesRepo,
        _petsRepo = petsRepo;

  final NotificationService _service;
  final SchedulesRepository _schedulesRepo;
  final VaccinationsRepository _vaccinationsRepo;
  final PreventionCoursesRepository _preventionCoursesRepo;
  final PreventionDosesRepository _preventionDosesRepo;
  final PetsRepository _petsRepo;

  /// 同時実行を防ぐ。連続編集で多重に走らせない。
  bool _running = false;

  /// 全系統を読み直し、64 枠に収めて積み直す。
  ///
  /// 変更のたびに呼ぶ (起動時 / ワクチン / schedule / 予防の作成・更新・削除)。
  Future<NotificationAllocationReport?> rescheduleAll({
    required bool isPro,
  }) async {
    if (_running) {
      PetloLogger.instance.d('rescheduleAll: already running, skipped');
      return null;
    }
    _running = true;
    final Stopwatch sw = Stopwatch()..start();

    try {
      final DateTime now = DateTime.now();
      final AppLocalizations l10n = _platformL10n();
      final String localeTag = _platformLocale().toLanguageTag();

      // ---- 1. 各系統の候補を組み立てる ----
      // 1 系統の失敗で全体を落とさない。ある系統の planner が壊れても、
      // 他系統の通知は積み直せるようにする (縮退動作)。
      final List<NotificationCandidate> candidates = <NotificationCandidate>[
        ...await _guard('vaccination', () => _planVaccinations(l10n, now)),
        ...await _guard('schedule', () => _planSchedules(l10n, now)),
        ...await _guard(
            'prevention', () => _planPreventions(l10n, localeTag, now, isPro)),
      ];

      // ---- 2. 3 系統の合計を見て配分する ----
      final NotificationAllocation allocation =
          NotificationBudgetAllocator.allocate(
        candidates: candidates,
        now: now,
        // キルスイッチの **二重防御**。
        //
        // 本命は _planPreventions() 側で、フラグが倒れていれば候補を
        // 0 件で返す。候補が 0 なら Tier 1 の取り分も min(12, 0) = 0 に
        // なるので、この reserveOverride が無くても 12 枠は自動的に
        // プールへ合流する。つまりここは冗長な保険である。
        //
        // 将来どちらかを消すときは **_planPreventions 側を残すこと**。
        // こちらだけを頼りにすると、候補が生成される限り予防が枠を
        // 取り続けてしまう。
        reserveOverride: AppConstants.enablePrevention
            ? null
            : <NotificationSystem, int>{
                NotificationSystem.vaccination:
                    NotificationBudget.vaccinationReserve,
                NotificationSystem.schedule:
                    NotificationBudget.scheduleReserve,
                NotificationSystem.prevention: 0,
              },
      );

      // ---- 3. 差分キャンセル → 登録 ----
      await _applyAllocation(allocation);

      // ---- 4. レポートを残す ----
      sw.stop();
      await UserPreferences.instance
          .setNotificationAllocationReport(allocation.report.toJson());
      PetloLogger.instance.i(
        'rescheduleAll: ${allocation.report.summary} '
        '(${sw.elapsedMilliseconds}ms)',
      );
      return allocation.report;
    } catch (e, st) {
      PetloLogger.instance
          .w('rescheduleAll failed', error: e, stackTrace: st);
      return null;
    } finally {
      _running = false;
    }
  }

  // ==========================================================================
  // 候補の組み立て
  // ==========================================================================

  /// planner 1 本ぶんを保護する。失敗したらその系統だけ 0 件にして続行する。
  Future<List<NotificationCandidate>> _guard(
    String label,
    Future<List<NotificationCandidate>> Function() body,
  ) async {
    try {
      return await body();
    } catch (e, st) {
      PetloLogger.instance.w('planner failed: $label (degraded to 0)',
          error: e, stackTrace: st);
      return const <NotificationCandidate>[];
    }
  }

  Future<List<NotificationCandidate>> _planVaccinations(
    AppLocalizations l10n,
    DateTime now,
  ) async {
    final List<VaccinationEntity> list =
        await _vaccinationsRepo.getAllUpcomingDueAlerts();
    return VaccinationNotificationPlanner.plan(
      vaccinations: list,
      l10n: l10n,
      now: now,
    );
  }

  Future<List<NotificationCandidate>> _planSchedules(
    AppLocalizations l10n,
    DateTime now,
  ) async {
    final List<ScheduleEntity> list =
        await _schedulesRepo.getAllForRescheduling();
    return ScheduleNotificationPlanner.plan(
      schedules: list,
      l10n: l10n,
      now: now,
    );
  }

  Future<List<NotificationCandidate>> _planPreventions(
    AppLocalizations l10n,
    String localeTag,
    DateTime now,
    bool isPro,
  ) async {
    if (!AppConstants.enablePrevention) return const <NotificationCandidate>[];

    final List<PreventionCourseEntity> courses =
        await _preventionCoursesRepo.getAllActiveByCreation();
    final List<PreventionCoursePlanInput> inputs =
        <PreventionCoursePlanInput>[];
    final Map<int, PreventionCourseEntity> courseById =
        <int, PreventionCourseEntity>{};
    final Map<int, PreventionDoseEntity> doseById =
        <int, PreventionDoseEntity>{};
    final Map<int, String> petNames = <int, String>{};

    for (final PreventionCourseEntity c in courses) {
      final List<PreventionDoseEntity> doses =
          await _preventionDosesRepo.getForCourse(c.id);
      inputs.add((course: c, doses: doses));
      courseById[c.id] = c;
      for (final PreventionDoseEntity d in doses) {
        doseById[d.id] = d;
      }
      if (!petNames.containsKey(c.petId)) {
        petNames[c.petId] = await _petName(c.petId);
      }
    }

    return PreventionNotificationPlanner.plan(
      inputs: inputs,
      courseById: courseById,
      doseById: doseById,
      petNames: petNames,
      l10n: l10n,
      localeTag: localeTag,
      now: now,
      isPro: isPro,
    );
  }

  // ==========================================================================
  // 実行
  // ==========================================================================

  /// 差分キャンセルしてから登録する。
  ///
  /// 「今 OS にあるが新しい割り当てに無い」ものだけを消すので、
  /// 生き残る通知は一瞬たりとも消えない。
  Future<void> _applyAllocation(NotificationAllocation allocation) async {
    final Set<int> keep = allocation.selected
        .map((NotificationCandidate c) => c.id)
        .toSet();

    // 自分が所有する ID レンジだけを対象にする。
    // 他プラグイン由来 (FCM 等) を巻き込まないため cancelAll() は使わない。
    final List<PendingNotificationRequest> pending = await _service.pending();
    int cancelled = 0;
    for (final PendingNotificationRequest r in pending) {
      if (!_isOwnedId(r.id)) continue;
      if (keep.contains(r.id)) continue;
      await _service.cancel(r.id);
      cancelled++;
    }

    for (final NotificationCandidate c in allocation.selected) {
      switch (c.kind) {
        case NotificationKind.oneTime:
          await _service.scheduleOneTime(
            id: c.id,
            title: c.title,
            body: c.body,
            scheduledAt: c.fireAt,
            channelId: c.channelId,
            channelName: c.channelName,
          );
        case NotificationKind.dailyRepeat:
          await _service.scheduleDailyAt(
            id: c.id,
            title: c.title,
            body: c.body,
            hour: c.hour ?? 9,
            minute: c.minute ?? 0,
            weekday: c.weekday,
            channelId: c.channelId,
            channelName: c.channelName,
          );
      }
    }

    if (kDebugMode) {
      PetloLogger.instance.d(
        'applyAllocation: cancelled $cancelled, scheduled '
        '${allocation.selected.length}',
      );
    }
  }

  /// petlo が採番している ID レンジか。
  static bool _isOwnedId(int id) {
    if (id >= kVaccinationIdRangeStart && id < kVaccinationIdRangeEnd) {
      return true;
    }
    if (id >= kScheduleIdRangeStart && id < kScheduleIdRangeEnd) return true;
    // prevention dose (400M) / course (500M)
    if (id >= 400000000 && id < 600000000) return true;
    return false;
  }

  Future<String> _petName(int petId) async {
    try {
      final PetEntity? pet = await _petsRepo.getPet(petId);
      return pet?.name ?? '';
    } catch (_) {
      return '';
    }
  }

  AppLocalizations _platformL10n() => lookupAppLocalizations(_platformLocale());

  Locale _platformLocale() {
    final Locale platform = WidgetsBinding.instance.platformDispatcher.locale;
    return AppLocalizations.supportedLocales.firstWhere(
      (Locale l) => l.languageCode == platform.languageCode,
      orElse: () => const Locale('ja'),
    );
  }
}
