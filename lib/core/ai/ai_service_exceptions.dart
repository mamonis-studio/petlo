// ============================================================================
// petlo - AI Service Exceptions
// ============================================================================
//
// AiService が投げるエラーの分類。
// 各エラーで UI 側の対応を変える。
//
// build 39: super(message) のハードコード JP を撤廃し、message は
// `_platformL10n()` 経由で生成。core/ で context が無いので
// notification_scheduler / ai_service と同じパターン。
// メッセージ表示が UI 側 catch で `e.message` 経由のため、UI 起点に
// l10n を引数で受け取らせるのは過剰な変更になるため避けた。
//
// ============================================================================

import 'package:flutter/widgets.dart';

import '../../l10n/generated/app_localizations.dart';

sealed class AiServiceException implements Exception {
  const AiServiceException(this.message);
  final String message;

  @override
  String toString() => 'AiServiceException: $message';
}

/// オフライン
class AiOfflineException extends AiServiceException {
  AiOfflineException() : super(_l10n().ai_chat_error_offline);
}

/// サーバーへの接続失敗 (DNS / timeout など)
class AiNetworkException extends AiServiceException {
  const AiNetworkException(super.message);
}

/// 入力バリデーションエラー(400 Bad Request)
class AiBadRequestException extends AiServiceException {
  const AiBadRequestException(super.message);
}

/// 認証エラー(401)
class AiUnauthorizedException extends AiServiceException {
  AiUnauthorizedException() : super(_l10n().ai_service_error_auth_required);
}

/// Pro プラン未契約 (403)
class AiProRequiredException extends AiServiceException {
  AiProRequiredException() : super(_l10n().ai_chat_error_pro_required);
}

/// 月内利用制限超過 (429)
class AiQuotaExceededException extends AiServiceException {
  AiQuotaExceededException(this.remaining)
      : super(_l10n().ai_service_error_quota_generic);
  final int remaining;
}

/// サーバー側エラー(500台)
class AiServerException extends AiServiceException {
  const AiServerException(super.message);
}

/// 想定外
class AiUnknownException extends AiServiceException {
  const AiUnknownException(super.message);
}

/// build 39: context が無い core/ から l10n を解決するための platform locale
/// フォールバック。supportedLocales に含まれていれば一致、そうでなければ
/// template (ja) にフォールバックする (notification_scheduler と同じパターン)。
AppLocalizations _l10n() {
  final Locale platform =
      WidgetsBinding.instance.platformDispatcher.locale;
  final Locale chosen = AppLocalizations.supportedLocales.firstWhere(
    (Locale l) => l.languageCode == platform.languageCode,
    orElse: () => const Locale('ja'),
  );
  return lookupAppLocalizations(chosen);
}
