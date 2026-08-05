// ============================================================================
// petlo - Notification Permission Prompt
// ============================================================================
//
// 通知権限を「ユーザーが通知を期待した瞬間」に要求する (build 73)。
//
// build 72 まで requestPermissions() の呼び出しは設定画面の手動トグルだけ
// だった。DarwinInitializationSettings も requestAlertPermission: false で
// 起動時には要求しない。つまり **設定画面を開かない限り通知が一度も来ない**。
// リマインダーが主機能のアプリとして成立していなかった。
//
// ============================================================================
// 自前の「要求済みフラグ」を持たない理由
// ============================================================================
//
// requestPermissions() は OS が notDetermined を返すときだけダイアログを
// 出す。既に許可・拒否を選んだユーザーには何も表示されず、現在の状態が
// 即座に返るだけ。つまり **多重要求の防止は OS 側が既にやっている**。
//
// ここに自前フラグを重ねると、ユーザーが 1 回目のダイアログを誤って
// 閉じた場合に二度と要求できなくなる。OS の状態を唯一の真実とする。
//
// (「値が無い」ことと「まだ分からない」ことを自前で推測しない、という
//  build 73 で繰り返し踏んだ落とし穴と同じ話。)
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../../l10n/generated/app_localizations.dart';
import '../utils/logger.dart';
import 'notification_service.dart';

abstract final class NotificationPermissionPrompt {
  NotificationPermissionPrompt._();

  /// 通知を伴う保存の直後に呼ぶ。
  ///
  /// - 未確定なら OS のダイアログが出る (許可されれば以後は何も出ない)
  /// - 拒否されていれば SnackBar で設定への導線を出す
  /// - 許可済みなら何もしない
  ///
  /// 保存処理そのものは止めない。権限の有無に関わらず記録は保存され、
  /// DB を真実として次回起動時に通知が積み直される。
  static Future<void> ensureGranted(BuildContext context) async {
    try {
      // notDetermined ならここでダイアログが出る。
      // 確定済みなら OS が即座に現在の状態を返すだけで何も表示されない。
      final bool granted =
          await NotificationService.instance.requestPermissions();
      if (granted) return;

      if (!context.mounted) return;
      final AppLocalizations l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.notification_permission_denied_message),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: l10n.notification_permission_open_settings,
            onPressed: () {
              // permission_handler は既に依存に入っている。
              // iOS では UIApplication.openSettingsURLString を開く。
              ph.openAppSettings();
            },
          ),
        ),
      );
    } catch (e, st) {
      // 権限の確認に失敗しても保存自体は成功しているので、握り潰さず
      // ログだけ残して続行する。
      PetloLogger.instance
          .w('notification permission prompt failed', error: e, stackTrace: st);
    }
  }
}
