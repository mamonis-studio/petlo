// ============================================================================
// petlo - Group API Exceptions
// ============================================================================
//
// GroupApiService が投げるエラー。
// UI 側で SnackBar / Paywall / 確認ダイアログ等の対応を切り替えるために
// sealed class で網羅。
//
// ============================================================================

sealed class GroupApiException implements Exception {
  const GroupApiException(this.message);
  final String message;

  @override
  String toString() => 'GroupApiException: $message';
}

/// オフライン or サーバー到達不能
class GroupNetworkException extends GroupApiException {
  const GroupNetworkException(super.message);
}

/// 認証エラー (401) — 再ログイン必要
class GroupUnauthorizedException extends GroupApiException {
  const GroupUnauthorizedException()
      : super('認証エラーです。再ログインしてください');
}

/// Pro プラン未契約 (グループ作成 / 招待発行に必要)
class GroupProRequiredException extends GroupApiException {
  const GroupProRequiredException()
      : super('Pro プランが必要です');
}

/// 権限不足 (403)
class GroupForbiddenException extends GroupApiException {
  const GroupForbiddenException(super.message);
}

/// 招待コードが無効 / 期限切れ
class InviteCodeInvalidException extends GroupApiException {
  const InviteCodeInvalidException()
      : super('招待コードが無効か、期限切れです');
}

/// 招待コードが既に使用済み
class InviteCodeAlreadyUsedException extends GroupApiException {
  const InviteCodeAlreadyUsedException()
      : super('この招待コードは既に使用されています');
}

/// グループが満員 (5人上限)
class GroupFullException extends GroupApiException {
  const GroupFullException()
      : super('このグループは満員です(最大5人)');
}

/// 自分が既にメンバー
class AlreadyMemberException extends GroupApiException {
  const AlreadyMemberException()
      : super('既にこのグループのメンバーです');
}

/// グループ作成上限超過 (3つ)
class GroupLimitReachedException extends GroupApiException {
  const GroupLimitReachedException()
      : super('参加できるグループは最大3つまでです');
}

/// 入力バリデーションエラー (400)
class GroupBadRequestException extends GroupApiException {
  const GroupBadRequestException(super.message);
}

/// サーバーエラー (5xx)
class GroupServerException extends GroupApiException {
  const GroupServerException(super.message);
}

/// 未実装エンドポイント (将来対応)
class GroupNotImplementedException extends GroupApiException {
  const GroupNotImplementedException(String operation)
      : super('$operation はまだサーバー側で実装されていません');
}

/// 想定外
class GroupUnknownException extends GroupApiException {
  const GroupUnknownException(super.message);
}
