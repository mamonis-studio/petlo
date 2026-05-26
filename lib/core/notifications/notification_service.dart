// ============================================================================
// petlo - Notification Service
// ============================================================================
//
// flutter_local_notifications のラッパー。
// アプリ全体で1つのインスタンスを共有。
//
// 役割:
//   - 通知プラグインの初期化
//   - パーミッション取得
//   - 通知のスケジュール / キャンセル
//   - Notification ID 採番ヘルパー
//
// Notification ID 採番ルール (32bit signed int 範囲を分割):
//   - 1_000_000 〜  9_999_999  : ワクチン期限通知 (vaccinationId基準)
//   - 10_000_000 〜 99_999_999 : 旧 投薬リマインダー (reminderId * 32 + slot)
//                                 [build 47b で schedule に統合、コードからは
//                                  参照されないが既存 OS スケジュール ID と
//                                  衝突しないよう保持]
//   - 100_000_000〜 199_999_999: schedules 由来通知 (scheduleId * 32 + slot)
//                                  [build 47b 新設、medication カテゴリの
//                                   times×weekdays、および notificationTiming
//                                   1-shot]
//
// rev3 §7.5 ローカル通知設計
//
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../utils/logger.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// アプリ起動時に一度だけ呼ぶ
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // タイムゾーン初期化
      tz_data.initializeTimeZones();
      final String localTz = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTz));

      // プラグイン初期化
      const AndroidInitializationSettings androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings iosInit =
          DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const InitializationSettings settings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      );

      await _plugin.initialize(settings);
      _initialized = true;
      PetloLogger.instance
          .i('NotificationService initialized (tz=$localTz)');
    } catch (e, st) {
      PetloLogger.instance
          .w('NotificationService init failed', error: e, stackTrace: st);
    }
  }

  /// 通知パーミッション取得 (iOS は明示要求、Android 13+ は POST_NOTIFICATIONS)
  Future<bool> requestPermissions() async {
    if (!_initialized) await initialize();

    try {
      // iOS
      final IOSFlutterLocalNotificationsPlugin? ios =
          _plugin.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        final bool? granted = await ios.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }

      // Android
      final AndroidFlutterLocalNotificationsPlugin? android =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final bool? granted = await android.requestNotificationsPermission();
        // 13以下では常にtrue扱い
        return granted ?? true;
      }
      return false;
    } catch (e, st) {
      PetloLogger.instance.w('requestPermissions failed',
          error: e, stackTrace: st);
      return false;
    }
  }

  /// 通知が許可されているか確認
  Future<bool> hasPermissions() async {
    if (!_initialized) await initialize();

    try {
      final IOSFlutterLocalNotificationsPlugin? ios =
          _plugin.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        final NotificationsEnabledOptions? opts =
            await ios.checkPermissions();
        return opts?.isAlertEnabled ?? false;
      }

      final AndroidFlutterLocalNotificationsPlugin? android =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        return await android.areNotificationsEnabled() ?? false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// 単発の予約通知 (期限通知などの 1回だけ)
  Future<void> scheduleOneTime({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledAt,
    String? channelId,
    String? channelName,
  }) async {
    if (!_initialized) await initialize();
    if (scheduledAt.isBefore(DateTime.now())) {
      PetloLogger.instance
          .d('Skip past notification: id=$id, scheduledAt=$scheduledAt');
      return;
    }

    final tz.TZDateTime tzTime = tz.TZDateTime.from(scheduledAt, tz.local);

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tzTime,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId ?? 'petlo_default',
            channelName ?? 'petlo',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        // 廃止予定だが呼び出しが残る場合がある
        // ignore: deprecated_member_use
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e, st) {
      PetloLogger.instance
          .w('scheduleOneTime failed: id=$id', error: e, stackTrace: st);
    }
  }

  /// 毎日 / 毎週指定時刻の繰り返し通知
  Future<void> scheduleDailyAt({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    Set<int>? weekdays, // null なら毎日。0=日, 6=土
    String? channelId,
    String? channelName,
  }) async {
    if (!_initialized) await initialize();

    try {
      // weekdays が指定なし → 毎日
      // 指定あり → 該当曜日それぞれ翌日以降の最初の発火日を計算
      if (weekdays == null || weekdays.isEmpty) {
        final tz.TZDateTime first = _nextInstanceOf(hour, minute);
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          first,
          NotificationDetails(
            android: AndroidNotificationDetails(
              channelId ?? 'petlo_meds',
              channelName ?? 'petlo medications',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: const DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          // ignore: deprecated_member_use
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time, // 毎日同じ時刻
        );
      } else {
        // 各曜日に対して個別 ID で予約 (offset 0-6)
        for (final int wd in weekdays) {
          if (wd < 0 || wd > 6) continue;
          final tz.TZDateTime when = _nextInstanceOfWeekday(hour, minute, wd);
          await _plugin.zonedSchedule(
            id + wd, // ID +0..6
            title,
            body,
            when,
            NotificationDetails(
              android: AndroidNotificationDetails(
                channelId ?? 'petlo_meds',
                channelName ?? 'petlo medications',
                importance: Importance.high,
                priority: Priority.high,
              ),
              iOS: const DarwinNotificationDetails(),
            ),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            // ignore: deprecated_member_use
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          );
        }
      }
    } catch (e, st) {
      PetloLogger.instance
          .w('scheduleDailyAt failed: id=$id', error: e, stackTrace: st);
    }
  }

  /// 通知キャンセル(個別)
  Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (e) {
      PetloLogger.instance.d('cancel failed: id=$id, $e');
    }
  }

  /// 範囲キャンセル ([baseId, baseId+span) を全部消す)
  Future<void> cancelRange(int baseId, int span) async {
    for (int i = 0; i < span; i++) {
      await cancel(baseId + i);
    }
  }

  /// 全キャンセル(リセット用)
  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (e) {
      PetloLogger.instance.d('cancelAll failed: $e');
    }
  }

  /// 現在予約中の通知一覧 (debug用)
  Future<List<PendingNotificationRequest>> pending() async {
    try {
      return await _plugin.pendingNotificationRequests();
    } catch (e) {
      return <PendingNotificationRequest>[];
    }
  }

  // ==========================================================================
  // ID 採番ヘルパー
  // ==========================================================================

  /// ワクチン期限通知 ID
  static int idForVaccination(int vaccinationId) {
    return 1000000 + vaccinationId;
  }

  /// 投薬リマインダー ID (slot は 0-31、weekday/time index)。
  /// build 47b 以降は schedules への移行に伴い新規スケジュールに使わない
  /// が、起動時の cancel 用に残す。
  static int idForMedicationReminder(int reminderId, int timeSlot) {
    // 1リマインダーに最大 32 slots (時刻 × 曜日)
    return 10000000 + reminderId * 32 + timeSlot;
  }

  /// schedule 由来の通知 ID (build 47b 新設)。
  /// scheduleId * 32 + slot、slot は 0-31 で時刻×曜日の組み合わせを表す。
  /// scheduleId が 3_124_999 を越えると衝突する (3_124_999 * 32 = 99_999_968)
  /// が、現実的に発生し得ない上限なので無視する。
  static int idForSchedule(int scheduleId, int timeSlot) {
    return 100000000 + scheduleId * 32 + timeSlot;
  }

  // ==========================================================================
  // Internal time math
  // ==========================================================================

  /// 翌回の指定時刻 (今日この時刻が過ぎていれば明日)
  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// 次の指定曜日のhh:mm
  /// weekday: 0=日曜, 1=月曜...6=土曜
  /// (DateTime.weekday は 1=月..7=日 なので変換)
  tz.TZDateTime _nextInstanceOfWeekday(int hour, int minute, int weekday) {
    // weekday(0=日)→ DateTime.weekday(1-7、月=1)
    final int targetDtWd = weekday == 0 ? 7 : weekday;

    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduled = _nextInstanceOf(hour, minute);

    while (scheduled.weekday != targetDtWd) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    if (kDebugMode) {
      PetloLogger.instance.d(
          'Next instance for wd=$weekday at $hour:$minute → $scheduled');
    }
    return scheduled;
  }
}
