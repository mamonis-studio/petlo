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
import 'package:flutter/services.dart' show MethodChannel;
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

  /// pending() のフォールバック用。プラグインが内部で使っているものと同じ
  /// チャンネル名。プラグイン更新時は追従が必要 (詳細は pending() を参照)。
  static const MethodChannel _rawChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');

  bool _initialized = false;

  /// schedule 1 件が確保する ID 幅 (build 73)。
  /// timeIndex(0-7) * 8 + weekdaySlot(0-7) = 0..63。
  static const int kScheduleIdSpan = 64;

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
    } catch (e, st) {
      // build 73: 以前は黙って false を返していた。
      // これは pending() と同じ「失敗を『無い』と偽る」形で、
      // 「未許可」と「問い合わせに失敗」が区別できなくなる。
      // 開発者設定の権限表示がこの値を出すため、診断を誤らせる。
      PetloLogger.instance
          .w('hasPermissions failed (reported as not granted)',
              error: e, stackTrace: st);
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
  /// 毎日 / 毎週指定曜日の繰り返し通知。
  ///
  /// build 73: 以前は `Set<int>? weekdays` を受け取り、曜日ごとに
  /// **内部で `id + wd` して登録**していた。呼び出し側は通し番号の
  /// slot を渡していたため、実 ID が `base + slotIdx + wd` になり
  /// 衝突していた (例: slotIdx=0/wd=1 と slotIdx=1/wd=0 が同じ ID)。
  ///
  /// ID の採番はすべて呼び出し側 (idForSchedule) の責任とし、
  /// ここでは **渡された id をそのまま使う**。曜日は 1 回 1 つ。
  Future<void> scheduleDailyAt({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    int? weekday, // null なら毎日。0=日, 6=土
    String? channelId,
    String? channelName,
  }) async {
    if (!_initialized) await initialize();

    try {
      final bool daily = weekday == null || weekday < 0 || weekday > 6;
      final tz.TZDateTime when = daily
          ? _nextInstanceOf(hour, minute)
          : _nextInstanceOfWeekday(hour, minute, weekday);

      await _plugin.zonedSchedule(
        id,
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
        matchDateTimeComponents: daily
            ? DateTimeComponents.time
            : DateTimeComponents.dayOfWeekAndTime,
      );
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
  /// 現在予約中の通知一覧。
  ///
  /// build 73: 以前は例外を握り潰して空リストを返していたため、
  /// 「本当に 0 件」と「読み出しに失敗」が区別できなかった。
  ///
  /// プラグインの Dart 側マッピングには null 安全の穴がある:
  ///
  ///     ?.map((p) => PendingNotificationRequest(
  ///         p['id'], p['title'], p['body'], p['payload']))
  ///
  /// `p['id']` は non-nullable int へ暗黙キャストされる。iOS 側は
  /// `request.content.userInfo[NOTIFICATION_ID]` から id を読むので、
  /// **このプラグイン以外が登録した pending request** (例: FCM 由来) には
  /// このキーが無く id が null になる。すると 1 件の異物でリスト全体が
  /// 例外になり、こちらの通知まで丸ごと見えなくなる。
  ///
  /// そこで例外時は生のチャンネルへフォールバックし、壊れた要素だけを
  /// 捨てて残りを返す。捨てた件数はログに出す。
  Future<List<PendingNotificationRequest>> pending() async {
    if (!_initialized) await initialize();
    try {
      return await _plugin.pendingNotificationRequests();
    } catch (e, st) {
      PetloLogger.instance.w(
        'pending() failed in plugin mapping; falling back to raw channel',
        error: e,
        stackTrace: st,
      );
      return _pendingViaRawChannel();
    }
  }

  /// プラグインと同じメソッドチャンネルを直接叩き、要素単位で防御的に読む。
  ///
  /// チャンネル名とメソッド名はプラグイン内部の実装に合わせている
  /// (`platform_flutter_local_notifications.dart` / `FlutterLocalNotificationsPlugin.m`)。
  /// プラグイン更新時はここも追従が必要。
  Future<List<PendingNotificationRequest>> _pendingViaRawChannel() async {
    try {
      final List<Map<dynamic, dynamic>>? raw =
          await _rawChannel.invokeListMethod<Map<dynamic, dynamic>>(
        'pendingNotificationRequests',
      );
      if (raw == null) return <PendingNotificationRequest>[];

      final List<PendingNotificationRequest> out =
          <PendingNotificationRequest>[];
      int dropped = 0;
      for (final Map<dynamic, dynamic> p in raw) {
        final Object? id = p['id'];
        if (id is! int) {
          // 他プラグイン由来などで id を持たない要素。こちらの通知ではない。
          dropped++;
          continue;
        }
        out.add(PendingNotificationRequest(
          id,
          p['title'] as String?,
          p['body'] as String?,
          p['payload'] as String?,
        ));
      }
      PetloLogger.instance.i(
        'pending() via raw channel: ${out.length} readable, '
        '$dropped dropped (no usable id)',
      );
      return out;
    } catch (e, st) {
      PetloLogger.instance
          .w('pending() raw channel failed', error: e, stackTrace: st);
      return <PendingNotificationRequest>[];
    }
  }

  // ==========================================================================
  // ID 採番ヘルパー
  // ==========================================================================

  /// ワクチン期限通知 ID
  /// ワクチン期限通知 ID (build 73 で採番変更)。slot は 0-3。
  ///
  /// 旧採番は `1000000 + vaccinationId` で **幅 1 しか確保していないのに
  /// 2 slot (3日前 / 当日) を使っていた**。そのため隣接 ID のワクチン同士が
  /// 必ず衝突し、N 件登録しても distinct な ID は N+1 個にしかならず、
  /// 当日通知が後から登録したワクチンに上書きされて消えていた。
  ///
  /// 幅 4 を確保する。現在は 2 slot だが「1 週間前」等を足す余地を残す
  /// (prevention dose と同じ幅)。
  ///
  /// レンジ境界: 次の medication レンジは 10,000,000 から始まる。
  ///   1,000,000 + id * 4 < 10,000,000  ⇔  id < 2,250,000
  /// vaccinationId が約 225 万を超えると medication レンジに食い込むが、
  /// 1 ユーザーが記録するワクチンの件数として現実的に到達不能。
  static int idForVaccination(int vaccinationId, int slot) {
    return 1000000 + vaccinationId * 4 + slot;
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
  /// schedule 由来の通知 ID (build 73 で採番変更)。
  ///
  /// 旧採番は `100000000 + scheduleId * 32 + timeSlot` で、呼び出し側が
  /// (時刻 × 曜日) の通し番号を渡していた。ところが scheduleDailyAt が
  /// 内部で `id + wd` していたため実 ID は `base + slotIdx + wd` となり、
  /// (時刻0,曜日1) と (時刻1,曜日0) のように別 slot が同じ ID に潰れていた。
  ///
  /// 新採番は意味のある座標から決める:
  ///   timeIndex   : times[] の添字 (0-7)
  ///   weekdaySlot : 0-6 = 曜日指定 / 7 = 毎日 (曜日を絞らない)
  ///   one-shot 通知は (timeIndex=7, weekdaySlot=7) = オフセット 63 を使う
  ///
  /// 1 schedule あたり幅 [kScheduleIdSpan] (64) を確保する。
  /// 繰り返しは最大 7 時刻 × 8 = 56 slot まで表現でき、旧実装の 32 上限より広い。
  ///
  /// レンジ境界: 次の prevention dose レンジは 400,000,000 から始まる。
  ///   100,000,000 + id * 64 < 400,000,000  ⇔  id < 4,687,500
  /// scheduleId が約 468 万を超えると食い込むが現実的に到達不能。
  static int idForSchedule(int scheduleId, int timeIndex, int weekdaySlot) {
    return 100000000 + scheduleId * kScheduleIdSpan + timeIndex * 8 + weekdaySlot;
  }

  /// one-shot (notificationTiming 由来) が使うオフセット
  static int idForScheduleOneShot(int scheduleId) {
    return idForSchedule(scheduleId, 7, 7);
  }

  /// 予防 1 回分の通知 ID (build 72)。slot は 0-3。
  /// 400_000_000 + doseId * 4 + slot。
  /// doseId が 24_999_999 を超えると course レンジと衝突するが、
  /// 現実的に到達不能 (1 ペット年 8 件想定) なので無視する。
  static int idForPreventionDose(int doseId, int slot) {
    return 400000000 + doseId * 4 + slot;
  }

  /// 予防コース単位の通知 ID (build 72)。slot は 0-3。
  /// Android の通知 ID は int32 (上限 2,147,483,647) なので
  /// 500_000_000 + courseId * 4 は十分に収まる。
  static int idForPreventionCourse(int courseId, int slot) {
    return 500000000 + courseId * 4 + slot;
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
