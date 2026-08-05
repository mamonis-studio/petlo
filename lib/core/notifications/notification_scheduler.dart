// ============================================================================
// petlo - Notification Scheduler
// ============================================================================
//
// DBの状態とローカル通知のスケジュールを同期させる中央集権サービス。
//
// 役割:
//   1. schedules (category=medication 等) の create/update/delete 時に通知を再構築
//   2. ワクチン期限通知の create/update/delete 時に通知を再構築
//   3. アプリ起動時に全アクティブを再スケジュール(端末再起動後の復元)
//
// build 47b (Scope B3): 旧 syncReminder (medication_reminders ベース) は
//   廃止し、syncSchedule (schedules ベース) に統合。category=medication で
//   times が立っていれば毎日/曜日通知、それ以外は scheduledAt + notification
//   Timing で one-shot 通知。
//
// iOS 64 timeslot 上限への対応 (build 47b):
//   - 1 schedule あたり最大 32 slots (時刻 × 曜日) で頭打ち。
//   - rescheduleAllSchedules で複数 schedule を直列に積むので、
//     最大同時 ~50 slot を超えるとワクチン通知が枯渇する恐れあり。
//     その場合は早い者勝ち(scheduledAt の早い側を優先)で打ち切る。
//   - 実運用上、ユーザが持つ medication schedules は ≤ 2-3 件想定なので
//     当面は per-schedule cap だけで十分。
//
// build 72: グローバル 50 slot を kScheduleSlotBudget (38) と
//   kPreventionSlotBudget (12) に分割。予防コースは
//   PreventionNotificationScheduler が後者の枠内で積む。
//
// ============================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show PendingNotificationRequest;

import '../../data/local/app_database.dart';
import '../../data/repositories/schedules_repository.dart';
import '../../data/repositories/vaccinations_repository.dart';
import '../../l10n/generated/app_localizations.dart';
import '../constants/app_constants.dart';
import '../preferences/user_preferences.dart';
import '../utils/logger.dart';
import 'notification_service.dart';

/// グローバル通知 slot バジェット。iOS のシステム上限 (64) から
/// ワクチン枠 (典型 ≤ 8) を引いた値を上限の目安にする。
///
/// build 72: グローバル 50 slot を schedule 系 / 予防系に分割する。
/// 予防を無制限に積むと既存のワクチン通知が枯渇するため、予防側は
/// 優先度ラダーで 12 slot に収める (PreventionNotificationScheduler)。
/// schedules を 50 → 38 に下げるが、実運用でユーザが持つ medication
/// schedule は 2-3 件 (= 最大 ~6 slot) 想定なので実害はない。
const int _kGlobalSlotBudget = 50;
const int _kPreventionSlotBudgetWhenEnabled = 12;

/// 予防系に割り当てる slot 数。キルスイッチが倒れていれば 0。
const int kPreventionSlotBudget =
    AppConstants.enablePrevention ? _kPreventionSlotBudgetWhenEnabled : 0;

/// schedule 系に割り当てる slot 数。
///
/// **build 73 のキルスイッチで最も重要な一行。**
/// 予防を止めたら 50 に戻さないと、既存のワクチン・投薬通知が
/// 12 slot 損したまま生き続ける。UI を隠すだけでは #4 は直らない。
const int kScheduleSlotBudget =
    _kGlobalSlotBudget - kPreventionSlotBudget;

/// ワクチン 1 件が確保する ID 幅 (build 73)。現在使うのは 2 slot
/// (3日前 / 当日) だが、将来「1 週間前」等を足す余地として 4 を取る。
const int kVaccinationSlotSpan = 4;

/// 旧採番 (`1000000 + vaccinationId`、幅 1) で積まれた通知が残る ID レンジ。
/// 新採番と重ならない保証が無いため、起動時に一度だけ全掃除する。
const int kVaccinationIdRangeStart = 1000000;
const int kVaccinationIdRangeEnd = 10000000; // medication レンジの先頭 (排他)

/// 旧採番 (`100000000 + scheduleId * 32 + slot` と内部の `+ wd`) で
/// 積まれた通知が残る ID レンジ。新採番も同じレンジを使うので、
/// 起動時に一度だけ全掃除してから積み直す。
const int kScheduleIdRangeStart = 100000000;
const int kScheduleIdRangeEnd = 400000000; // prevention dose レンジの先頭 (排他)

class NotificationScheduler {
  NotificationScheduler({
    required NotificationService service,
    required SchedulesRepository schedulesRepo,
    required VaccinationsRepository vaccinationsRepo,
  })  : _service = service,
        _schedulesRepo = schedulesRepo,
        _vaccinationsRepo = vaccinationsRepo;

  final NotificationService _service;
  final SchedulesRepository _schedulesRepo;
  final VaccinationsRepository _vaccinationsRepo;

  // ==========================================================================
  // schedules (build 47b: 旧 reminders を統合)
  // ==========================================================================

  /// schedule 1 件分の通知を再構築。冪等(同じ ID を cancel してから再登録)。
  ///
  /// 振る舞い:
  ///   - category=medication で times が立っている → 毎日/曜日繰り返し通知
  ///     (旧 syncReminder と同じセマンティクス)。
  ///   - notificationTiming != none → scheduledAt から逆算して one-shot 通知
  ///     (1日前 / 当日朝9時 / 1週間前)。
  ///   - 両方該当する schedule (= 例: 投薬で時刻あり + 1日前リマインダー) は
  ///     両方積む。slot ID 範囲は 0..31 (繰り返し) と 32..33 (one-shot) で
  ///     分けて衝突を避ける。
  Future<int> syncSchedule(int scheduleId) async {
    try {
      final ScheduleEntity? s = await _schedulesRepo.getById(scheduleId);
      if (s == null || s.deletedAt != null) {
        await cancelSchedule(scheduleId);
        return 0;
      }

      await cancelSchedule(scheduleId);

      int slotIdx = 0;
      final AppLocalizations l10n = _platformL10n();
      final String body = _scheduleBody(s, l10n);

      // ===== 繰り返し通知 (medication カテゴリ + times) =====
      // build 73: ID は通し番号ではなく (timeIndex, weekdaySlot) から決める。
      // 通し番号 + scheduleDailyAt 内部の `id + wd` で衝突していたため。
      if (s.category == ScheduleCategory.medication && s.times != null) {
        final List<String> times = _decodeTimes(s.times);
        final Set<int> weekdays = _decodeWeekdays(s.weekdaysBits);

        // timeIndex は 0-6 まで (weekdaySlot 7 と合わせて幅 64 に収める)
        final int maxTimes = times.length > 7 ? 7 : times.length;

        for (int i = 0; i < maxTimes; i++) {
          final ({int hour, int minute})? parsed = _parseHHmm(times[i]);
          if (parsed == null) continue;

          if (weekdays.isEmpty) {
            // 毎日 → weekdaySlot 7
            await _service.scheduleDailyAt(
              id: NotificationService.idForSchedule(scheduleId, i, 7),
              title: s.title,
              body: body,
              hour: parsed.hour,
              minute: parsed.minute,
              weekday: null,
            );
            slotIdx++;
          } else {
            for (final int wd in weekdays) {
              if (wd < 0 || wd > 6) continue;
              await _service.scheduleDailyAt(
                id: NotificationService.idForSchedule(scheduleId, i, wd),
                title: s.title,
                body: body,
                hour: parsed.hour,
                minute: parsed.minute,
                weekday: wd,
              );
              slotIdx++;
            }
          }
        }
      }

      // ===== one-shot 通知 (notificationTiming) =====
      // 繰り返しと衝突しない専用オフセット (63) を使う。
      final DateTime? oneShotAt = _oneShotFireTime(s);
      if (oneShotAt != null && oneShotAt.isAfter(DateTime.now())) {
        await _service.scheduleOneTime(
          id: NotificationService.idForScheduleOneShot(scheduleId),
          title: s.title,
          body: body,
          scheduledAt: oneShotAt,
        );
        slotIdx++;
      }

      if (kDebugMode) {
        PetloLogger.instance
            .d('Synced schedule $scheduleId: $slotIdx slot(s) scheduled');
      }
      return slotIdx;
    } catch (e, st) {
      PetloLogger.instance.w('syncSchedule failed: id=$scheduleId',
          error: e, stackTrace: st);
      return 0;
    }
  }

  /// schedule 由来の通知を全部キャンセル。
  /// build 73: 採番で幅 64 を確保したので、その全域を掃除する。
  Future<void> cancelSchedule(int scheduleId) async {
    final int baseId = NotificationService.idForSchedule(scheduleId, 0, 0);
    await _service.cancelRange(baseId, NotificationService.kScheduleIdSpan);
  }

  /// 起動時に全 schedule を読んで再スケジュール。
  /// global budget を超えそうな場合は scheduledAt の早い側を優先する。
  Future<void> rescheduleAllSchedules() async {
    try {
      final List<ScheduleEntity> schedules =
          await _schedulesRepo.getAllForRescheduling();
      PetloLogger.instance
          .i('Rescheduling ${schedules.length} schedule(s) on app start');

      int slotBudget = kScheduleSlotBudget;
      int skipped = 0;
      for (final ScheduleEntity s in schedules) {
        if (slotBudget <= 0) {
          skipped++;
          continue;
        }
        final int used = await syncSchedule(s.id);
        slotBudget -= used;
      }
      if (skipped > 0) {
        PetloLogger.instance.w(
            'rescheduleAllSchedules: slot budget exhausted, '
            '$skipped schedule(s) skipped');
      }
    } catch (e, st) {
      PetloLogger.instance
          .w('rescheduleAllSchedules failed', error: e, stackTrace: st);
    }
  }

  /// 全ワクチン期限通知を再スケジュール(起動時など)
  Future<void> rescheduleAllVaccinationAlerts() async {
    try {
      final List<VaccinationEntity> vaccinations =
          await _vaccinationsRepo.getAllUpcomingDueAlerts();
      int used = 0;
      for (final VaccinationEntity v in vaccinations) {
        used += await syncVaccinationDueAlert(v.id);
      }
      // build 73: 件数だけでなく実際に積んだ slot 数も出す。
      // 「N 件登録したのに slot が増えない」を検知できるようにするため。
      PetloLogger.instance.i(
        'Rescheduling ${vaccinations.length} vaccination alert(s) on app '
        'start: $used slot(s) scheduled',
      );
    } catch (e, st) {
      PetloLogger.instance.w('rescheduleAllVaccinationAlerts failed',
          error: e, stackTrace: st);
    }
  }

  /// build 73: 旧採番で積まれた schedule 通知を一度だけ掃除する。
  ///
  /// 旧採番は通し番号 slot + scheduleDailyAt 内部の `+ wd` で実 ID が
  /// ずれていたため、新採番の cancelRange では消しきれない残骸が残る。
  /// ワクチンと同じ方式で、レンジ全域を列挙して消す。
  ///
  /// **DB には一切触らない。** 通知の積み直しのみ。
  Future<void> migrateLegacyScheduleNotificationIds() async {
    if (UserPreferences.instance.scheduleIdMigratedV2) return;
    try {
      final List<PendingNotificationRequest> pending =
          await _service.pending();
      final List<int> legacy = pending
          .map((PendingNotificationRequest r) => r.id)
          .where((int id) =>
              id >= kScheduleIdRangeStart && id < kScheduleIdRangeEnd)
          .toList();

      for (final int id in legacy) {
        await _service.cancel(id);
      }
      await UserPreferences.instance.setScheduleIdMigratedV2(true);
      await UserPreferences.instance
          .setScheduleIdMigratedCount(legacy.length);
      PetloLogger.instance.i(
        'Schedule notification id migration (v2): '
        'cleared ${legacy.length} legacy notification(s)',
      );
    } catch (e, st) {
      // 失敗してもフラグは立てない。次回起動で再試行する。
      PetloLogger.instance.w('schedule id migration failed',
          error: e, stackTrace: st);
    }
  }

  /// build 73: 旧採番で積まれたワクチン通知を一度だけ掃除する。
  ///
  /// 旧採番は `1000000 + vaccinationId` (幅 1)。新採番 `+ id * 4 + slot` とは
  /// ID が重ならない保証が無いため、残骸が生き残ると
  ///   - 消せない通知が居座る
  ///   - 新採番の通知と衝突して片方が消える
  /// のどちらかが起きる。pending() が読めるようになった今なら確実に列挙できる。
  ///
  /// **DB には一切触らない。** 通知の積み直しのみ。
  /// 掃除は 1 回だけ。フラグは UserPreferences に持つ。
  Future<void> migrateLegacyVaccinationNotificationIds() async {
    if (UserPreferences.instance.vaccinationIdMigratedV2) return;
    try {
      final List<PendingNotificationRequest> pending =
          await _service.pending();
      final List<int> legacy = pending
          .map((PendingNotificationRequest r) => r.id)
          .where((int id) =>
              id >= kVaccinationIdRangeStart && id < kVaccinationIdRangeEnd)
          .toList();

      for (final int id in legacy) {
        await _service.cancel(id);
      }
      await UserPreferences.instance.setVaccinationIdMigratedV2(true);
      // ログは debug でしか出ないので、結果を永続化して画面から読めるようにする
      await UserPreferences.instance
          .setVaccinationIdMigratedCount(legacy.length);
      PetloLogger.instance.i(
        'Vaccination notification id migration (v2): '
        'cleared ${legacy.length} legacy notification(s)',
      );
    } catch (e, st) {
      // 失敗してもフラグは立てない。次回起動で再試行する。
      PetloLogger.instance.w('vaccination id migration failed',
          error: e, stackTrace: st);
    }
  }

  // ==========================================================================
  // ワクチン期限通知
  // ==========================================================================

  /// ワクチン1件分の通知を再構築。
  /// 3日前と当日(0時相当の朝9時)に通知。
  /// nextDueAt が null なら何もしない(キャンセルのみ)。
  /// 実際に積んだ slot 数を返す (build 73)。
  /// 以前は「ワクチン 1 件につき 1 行」のログしか出しておらず、
  /// 2 slot 積まれたのかを判定できなかった。schedule 系の
  /// "N slot(s) scheduled" に粒度を揃える。
  Future<int> syncVaccinationDueAlert(int vaccinationId) async {
    try {
      final VaccinationEntity? v = await _vaccinationsRepo.getById(vaccinationId);
      if (v == null || v.deletedAt != null) {
        await cancelVaccinationDueAlert(vaccinationId);
        return 0;
      }

      // 一旦削除
      await cancelVaccinationDueAlert(vaccinationId);

      final int? nextDue = v.nextDueAt;
      if (nextDue == null) return 0;

      final DateTime dueDate =
          DateTime.fromMillisecondsSinceEpoch(nextDue);

      // 当日通知: 朝9時に発火
      final DateTime onDay =
          DateTime(dueDate.year, dueDate.month, dueDate.day, 9, 0);

      // 3日前通知
      final DateTime threeDaysBefore =
          onDay.subtract(const Duration(days: 3));

      // build 34: 通知文言を l10n 化 (context 無いので platform locale を読む)
      final AppLocalizations l10n = _platformL10n();
      int used = 0;

      // slot 0: 3日前
      if (threeDaysBefore.isAfter(DateTime.now())) {
        await _service.scheduleOneTime(
          id: NotificationService.idForVaccination(vaccinationId, 0),
          title: l10n.notification_vaccination_upcoming_title,
          body: l10n.notification_vaccination_upcoming_body(v.kind),
          scheduledAt: threeDaysBefore,
          channelId: 'petlo_vaccinations',
          channelName: 'petlo vaccinations',
        );
        used++;
      }

      // slot 1: 当日
      if (onDay.isAfter(DateTime.now())) {
        await _service.scheduleOneTime(
          id: NotificationService.idForVaccination(vaccinationId, 1),
          title: l10n.notification_vaccination_today_title,
          body: l10n.notification_vaccination_today_body(v.kind),
          scheduledAt: onDay,
          channelId: 'petlo_vaccinations',
          channelName: 'petlo vaccinations',
        );
        used++;
      }

      if (kDebugMode) {
        PetloLogger.instance.d(
            'Synced vaccination $vaccinationId: $used slot(s) scheduled '
            '(due=$dueDate)');
      }
      return used;
    } catch (e, st) {
      PetloLogger.instance
          .w('syncVaccinationDueAlert failed: id=$vaccinationId',
              error: e, stackTrace: st);
      return 0;
    }
  }

  /// ワクチン通知を全部キャンセル。
  /// build 73: 採番で幅 4 を確保したので、余った slot も含めて掃除する。
  Future<void> cancelVaccinationDueAlert(int vaccinationId) async {
    final int baseId =
        NotificationService.idForVaccination(vaccinationId, 0);
    await _service.cancelRange(baseId, kVaccinationSlotSpan);
  }

  // ==========================================================================
  // Helpers
  // ==========================================================================

  ({int hour, int minute})? _parseHHmm(String hhmm) {
    final RegExpMatch? m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(hhmm);
    if (m == null) return null;
    final int h = int.parse(m.group(1)!);
    final int min = int.parse(m.group(2)!);
    if (h < 0 || h > 23 || min < 0 || min > 59) return null;
    return (hour: h, minute: min);
  }

  /// schedule の本文を組み立て。notes が無ければデフォルト文言。
  String _scheduleBody(ScheduleEntity s, AppLocalizations l10n) {
    final String? notes = s.notes;
    if (notes != null && notes.trim().isNotEmpty) return notes.trim();
    return l10n.notification_medication_default_body;
  }

  List<String> _decodeTimes(String? raw) {
    if (raw == null || raw.isEmpty) return const <String>[];
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is List) return decoded.whereType<String>().toList();
    } catch (_) {
      // ignore — fall through
    }
    return const <String>[];
  }

  Set<int> _decodeWeekdays(int? bits) {
    if (bits == null || bits == 0) return const <int>{};
    final Set<int> out = <int>{};
    for (int i = 0; i < 7; i++) {
      if ((bits & (1 << i)) != 0) out.add(i);
    }
    return out;
  }

  /// notificationTiming に従って one-shot 発火時刻を算出する。
  /// none / 過去 / 値解釈不能 なら null。
  DateTime? _oneShotFireTime(ScheduleEntity s) {
    if (s.notificationTiming == ScheduleNotificationTiming.none) return null;
    final DateTime scheduledAt =
        DateTime.fromMillisecondsSinceEpoch(s.scheduledAt);
    switch (s.notificationTiming) {
      case ScheduleNotificationTiming.on_day:
        // 当日朝 9 時 (時刻指定が無ければ朝 9 時、あればその時刻)
        if (s.hasTime) return scheduledAt;
        return DateTime(
            scheduledAt.year, scheduledAt.month, scheduledAt.day, 9, 0);
      case ScheduleNotificationTiming.day_before:
        final DateTime onDay = s.hasTime
            ? scheduledAt
            : DateTime(scheduledAt.year, scheduledAt.month, scheduledAt.day,
                9, 0);
        return onDay.subtract(const Duration(days: 1));
      case ScheduleNotificationTiming.week_before:
        final DateTime onDay = s.hasTime
            ? scheduledAt
            : DateTime(scheduledAt.year, scheduledAt.month, scheduledAt.day,
                9, 0);
        return onDay.subtract(const Duration(days: 7));
      case ScheduleNotificationTiming.none:
        return null;
    }
  }

  /// build 34: context が無いコードパス用に platform locale で l10n を解決する。
  /// supportedLocales に含まれていれば一致、そうでなければ template (ja) に
  /// フォールバックする。
  AppLocalizations _platformL10n() {
    final Locale platform =
        WidgetsBinding.instance.platformDispatcher.locale;
    final Locale chosen = AppLocalizations.supportedLocales.firstWhere(
      (Locale l) => l.languageCode == platform.languageCode,
      orElse: () => const Locale('ja'),
    );
    return lookupAppLocalizations(chosen);
  }
}
