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
// ============================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/schedules_repository.dart';
import '../../data/repositories/vaccinations_repository.dart';
import '../../l10n/generated/app_localizations.dart';
import '../utils/logger.dart';
import 'notification_service.dart';

/// グローバル通知 slot バジェット。iOS のシステム上限 (64) から
/// ワクチン枠 (典型 ≤ 8) を引いた値を上限の目安にする。
const int _kGlobalSlotBudget = 50;

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
      if (s.category == ScheduleCategory.medication && s.times != null) {
        final List<String> times = _decodeTimes(s.times);
        final Set<int> weekdays = _decodeWeekdays(s.weekdaysBits);

        if (weekdays.isEmpty) {
          for (int i = 0; i < times.length && slotIdx < 32; i++) {
            final ({int hour, int minute})? parsed = _parseHHmm(times[i]);
            if (parsed == null) continue;
            await _service.scheduleDailyAt(
              id: NotificationService.idForSchedule(scheduleId, slotIdx),
              title: s.title,
              body: body,
              hour: parsed.hour,
              minute: parsed.minute,
              weekdays: null, // null = 毎日
            );
            slotIdx++;
          }
        } else {
          for (int i = 0; i < times.length; i++) {
            final ({int hour, int minute})? parsed = _parseHHmm(times[i]);
            if (parsed == null) continue;
            for (final int wd in weekdays) {
              if (slotIdx >= 32) break;
              await _service.scheduleDailyAt(
                id: NotificationService.idForSchedule(scheduleId, slotIdx),
                title: s.title,
                body: body,
                hour: parsed.hour,
                minute: parsed.minute,
                weekdays: <int>{wd},
              );
              slotIdx++;
            }
          }
        }
      }

      // ===== one-shot 通知 (notificationTiming) =====
      // 繰り返し通知の slot を 0..31 で確保したので、one-shot は 32 から。
      final DateTime? oneShotAt = _oneShotFireTime(s);
      if (oneShotAt != null && oneShotAt.isAfter(DateTime.now())) {
        await _service.scheduleOneTime(
          id: NotificationService.idForSchedule(scheduleId, 32),
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
  /// slot 範囲: 0..31 (繰り返し) + 32 (one-shot) = 33 個。
  Future<void> cancelSchedule(int scheduleId) async {
    final int baseId = NotificationService.idForSchedule(scheduleId, 0);
    await _service.cancelRange(baseId, 33);
    // scheduleDailyAt(weekdays: {wd}) は内部で ID + wd するため、繰り返し
    // 通知 baseId+0..7 もクリアしておく (cancelRange で吸収済みだが念のため)。
  }

  /// 起動時に全 schedule を読んで再スケジュール。
  /// global budget を超えそうな場合は scheduledAt の早い側を優先する。
  Future<void> rescheduleAllSchedules() async {
    try {
      final List<ScheduleEntity> schedules =
          await _schedulesRepo.getAllForRescheduling();
      PetloLogger.instance
          .i('Rescheduling ${schedules.length} schedule(s) on app start');

      int slotBudget = _kGlobalSlotBudget;
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
      PetloLogger.instance
          .i('Rescheduling ${vaccinations.length} vaccination alert(s) on app start');
      for (final VaccinationEntity v in vaccinations) {
        await syncVaccinationDueAlert(v.id);
      }
    } catch (e, st) {
      PetloLogger.instance.w('rescheduleAllVaccinationAlerts failed',
          error: e, stackTrace: st);
    }
  }

  // ==========================================================================
  // ワクチン期限通知
  // ==========================================================================

  /// ワクチン1件分の通知を再構築。
  /// 3日前と当日(0時相当の朝9時)に通知。
  /// nextDueAt が null なら何もしない(キャンセルのみ)。
  Future<void> syncVaccinationDueAlert(int vaccinationId) async {
    try {
      final VaccinationEntity? v = await _vaccinationsRepo.getById(vaccinationId);
      if (v == null || v.deletedAt != null) {
        await cancelVaccinationDueAlert(vaccinationId);
        return;
      }

      // 一旦削除
      await cancelVaccinationDueAlert(vaccinationId);

      final int? nextDue = v.nextDueAt;
      if (nextDue == null) return;

      final DateTime dueDate =
          DateTime.fromMillisecondsSinceEpoch(nextDue);

      // 当日通知: 朝9時に発火
      final DateTime onDay =
          DateTime(dueDate.year, dueDate.month, dueDate.day, 9, 0);

      // 3日前通知
      final DateTime threeDaysBefore =
          onDay.subtract(const Duration(days: 3));

      final int baseId = NotificationService.idForVaccination(vaccinationId);

      // build 34: 通知文言を l10n 化 (context 無いので platform locale を読む)
      final AppLocalizations l10n = _platformL10n();

      // 3日前
      if (threeDaysBefore.isAfter(DateTime.now())) {
        await _service.scheduleOneTime(
          id: baseId,
          title: l10n.notification_vaccination_upcoming_title,
          body: l10n.notification_vaccination_upcoming_body(v.kind),
          scheduledAt: threeDaysBefore,
          channelId: 'petlo_vaccinations',
          channelName: 'petlo vaccinations',
        );
      }

      // 当日
      if (onDay.isAfter(DateTime.now())) {
        await _service.scheduleOneTime(
          id: baseId + 1,
          title: l10n.notification_vaccination_today_title,
          body: l10n.notification_vaccination_today_body(v.kind),
          scheduledAt: onDay,
          channelId: 'petlo_vaccinations',
          channelName: 'petlo vaccinations',
        );
      }

      if (kDebugMode) {
        PetloLogger.instance
            .d('Synced vaccination $vaccinationId: due=$dueDate');
      }
    } catch (e, st) {
      PetloLogger.instance
          .w('syncVaccinationDueAlert failed: id=$vaccinationId',
              error: e, stackTrace: st);
    }
  }

  /// ワクチン通知を全部キャンセル(3日前 + 当日 = 2通知)
  Future<void> cancelVaccinationDueAlert(int vaccinationId) async {
    final int baseId =
        NotificationService.idForVaccination(vaccinationId);
    // 範囲: baseId, baseId+1
    await _service.cancelRange(baseId, 2);
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
