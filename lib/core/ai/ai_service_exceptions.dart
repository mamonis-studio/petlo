// ============================================================================
// petlo - AI Service Exceptions
// ============================================================================
//
// AiService が投げるエラーの分類。
// 各エラーで UI 側の対応を変える。
//
// ============================================================================

sealed class AiServiceException implements Exception {
  const AiServiceException(this.message);
  final String message;

  @override
  String toString() => 'AiServiceException: $message';
}

/// オフライン
class AiOfflineException extends AiServiceException {
  const AiOfflineException()
      : super('オフラインです。接続を確認してください');
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
  const AiUnauthorizedException()
      : super('認証エラーです。再ログインしてください');
}

/// Pro プラン未契約 (403)
class AiProRequiredException extends AiServiceException {
  const AiProRequiredException()
      : super('AI機能は Pro プラン限定です');
}

/// 月内利用制限超過 (429)
class AiQuotaExceededException extends AiServiceException {
  const AiQuotaExceededException(this.remaining)
      : super('今月の利用回数を超えました');
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
