// ============================================================================
// petlo - Notification Scheduler
// ============================================================================
//
// DBの状態とローカル通知のスケジュールを同期させる中央集権サービス。
//
// 役割:
//   1. 投薬リマインダーの create/update/delete 時に通知を再構築
//   2. ワクチン期限通知の create/update/delete 時に通知を再構築
//   3. アプリ起動時に全アクティブを再スケジュール(端末再起動後の復元)
//
// 設計:
//   - NotificationService と MedicationRemindersRepository / VaccinationsRepository
//     を internal で持つ
//   - 各操作は冪等(同じ ID を一度 cancel してから schedule)
//   - DBスキーマ:
//     * MedicationReminder: times[] × weekdays{} の組み合わせで複数通知
//     * Vaccination: nextDueAt の3日前 + 当日の2通知
//
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/medication_reminders_repository.dart';
import '../../data/repositories/vaccinations_repository.dart';
import '../../l10n/generated/app_localizations.dart';
import '../utils/logger.dart';
import 'notification_service.dart';

class NotificationScheduler {
  NotificationScheduler({
    required NotificationService service,
    required MedicationRemindersRepository remindersRepo,
    required VaccinationsRepository vaccinationsRepo,
  })  : _service = service,
        _remindersRepo = remindersRepo,
        _vaccinationsRepo = vaccinationsRepo;

  final NotificationService _service;
  final MedicationRemindersRepository _remindersRepo;
  final VaccinationsRepository _vaccinationsRepo;

  // ==========================================================================
  // 投薬リマインダー
  // ==========================================================================

  /// リマインダー1件分の通知を再構築。
  /// `enabled=false` の場合は cancel のみ。
  Future<void> syncReminder(int reminderId) async {
    try {
      final MedicationReminderEntity? r =
          await _remindersRepo.getById(reminderId);
      if (r == null || r.deletedAt != null) {
        await cancelReminder(reminderId);
        return;
      }

      // 一旦すべての関連通知を削除
      await cancelReminder(reminderId);

      if (!r.enabled) {
        PetloLogger.instance.d(
            'Reminder $reminderId is disabled — keeping notifications cancelled');
        return;
      }

      // times × weekdays の組み合わせで通知を生成
      // weekdaysが空 = 毎日 → 各時刻ごとに1つの通知 (DateTimeComponents.time で繰り返し)
      // weekdaysが指定 → 各 (時刻, 曜日) で1つの通知
      final List<String> times = r.times;
      final Set<int> weekdays = r.weekdaysBits;

      int slotIdx = 0;

      if (weekdays.isEmpty) {
        // 毎日モード: 各時刻ごとに1通知
        for (int i = 0; i < times.length && slotIdx < 32; i++) {
          final ({int hour, int minute})? parsed = _parseHHmm(times[i]);
          if (parsed == null) continue;
          await _service.scheduleDailyAt(
            id: NotificationService.idForMedicationReminder(
                reminderId, slotIdx),
            title: r.medicineName,
            body: _buildBody(dosage: r.dosage, notes: r.notes),
            hour: parsed.hour,
            minute: parsed.minute,
            weekdays: null, // null = 毎日
          );
          slotIdx++;
        }
      } else {
        // 特定曜日モード: 各 (時刻, 曜日) ペアで1通知
        for (int i = 0; i < times.length; i++) {
          final ({int hour, int minute})? parsed = _parseHHmm(times[i]);
          if (parsed == null) continue;
          for (final int wd in weekdays) {
            if (slotIdx >= 32) break; // 安全弁
            await _service.scheduleDailyAt(
              id: NotificationService.idForMedicationReminder(
                  reminderId, slotIdx),
              title: r.medicineName,
              body: _buildBody(dosage: r.dosage, notes: r.notes),
              hour: parsed.hour,
              minute: parsed.minute,
              weekdays: <int>{wd},
            );
            slotIdx++;
          }
        }
      }

      if (kDebugMode) {
        PetloLogger.instance
            .d('Synced reminder $reminderId: $slotIdx slot(s) scheduled');
      }
    } catch (e, st) {
      PetloLogger.instance
          .w('syncReminder failed: id=$reminderId',
              error: e, stackTrace: st);
    }
  }

  /// リマインダーの通知を全部キャンセル
  Future<void> cancelReminder(int reminderId) async {
    // ID 範囲: NotificationService.idForMedicationReminder(reminderId, 0..31)
    // scheduleDailyAt(weekdays: {wd}) は ID + wd で個別予約することもあるが、
    // syncReminder が slot ベースで採番しているので 0..31 を消せばOK
    // ただし scheduleDailyAt 内部で ID + 0..6 する経路もあるため、
    // 念のため ID + 0..31 + 0..6 = 0..37 をクリアする
    final int baseId =
        NotificationService.idForMedicationReminder(reminderId, 0);
    await _service.cancelRange(baseId, 38);
  }

  /// 全リマインダーをDBから読み出して再スケジュール(起動時など)
  Future<void> rescheduleAllReminders() async {
    try {
      final List<MedicationReminderEntity> reminders =
          await _remindersRepo.getAllEnabled();
      PetloLogger.instance
          .i('Rescheduling ${reminders.length} reminder(s) on app start');
      for (final MedicationReminderEntity r in reminders) {
        await syncReminder(r.id);
      }
    } catch (e, st) {
      PetloLogger.instance
          .w('rescheduleAllReminders failed', error: e, stackTrace: st);
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

  String _buildBody({String? dosage, String? notes}) {
    final List<String> parts = <String>[];
    if (dosage != null && dosage.trim().isNotEmpty) parts.add(dosage);
    if (notes != null && notes.trim().isNotEmpty) parts.add(notes);
    return parts.isEmpty
        ? _platformL10n().notification_medication_default_body
        : parts.join(' · ');
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
