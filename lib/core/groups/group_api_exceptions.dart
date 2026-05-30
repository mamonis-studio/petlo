// ============================================================================
// petlo - Group API Exceptions
// ============================================================================
//
// GroupApiService が投げるエラー。
//
// build 35: エラーコード enum 化 (H1 対応)。
//   - `code` (GroupApiErrorCode) が UI 表示の正、l10n キーマッピングの起点
//   - `message` は **英語フォールバック / ログ用途のみ** で UI 表示禁止。
//     UI は必ず groupApiErrorMessage(e, l10n) ヘルパー経由で訳す
//   - 例外サブクラスは catch 時の粒度切替 (`on InviteCodeInvalidException`)
//     のために維持。各サブクラスは固有 code を super に渡す
//   - 入力バリデーション系 (`GroupBadRequestException`) は code を引数で受ける
//
// ============================================================================

enum GroupApiErrorCode {
  // 通信 / 共通 HTTP
  network,
  authRequired, // 401
  permissionDenied, // 403
  notFound, // 404
  conflict, // 409
  badRequest, // 400 generic
  serverError, // 5xx
  notImplemented, // legacy 404 マッピング (現状未使用、将来 endpoint 用)
  unknown,

  // ローカル入力バリデーション (グループ系)
  proRequired,
  invalidGroupName,
  invalidDisplayName,
  missingGroupId,
  cannotPromoteToOwner,
  ownerInviteForbidden,

  // 招待コード系
  emptyInviteCode,
  invalidInviteCodeFormat,
  inviteCodeInvalid,
  inviteCodeAlreadyUsed,
  groupFull,
  alreadyMember,
  groupLimitReached,

  // build 55-client: POST /groups の 409 で server が error_code を付ける。
  // 旧来の `conflict` (= 詳細不明) は後方互換維持用に残す。
  duplicateGroupName, // 同名グループ既存
  userAtGroupLimit, // 3 グループ上限到達 (group_limit_reached と意味は同じだが
                    // server-side error_code に厳密対応)
  userAlreadyHasData, // 予約済み: アカウント既存データ検知
}

sealed class GroupApiException implements Exception {
  const GroupApiException(this.code, {this.message});

  /// 唯一の真の識別子。UI はこれを見て l10n キーへ写像する。
  final GroupApiErrorCode code;

  /// 英語フォールバック / ログ用途のみ。UI 表示禁止 (代わりに
  /// groupApiErrorMessage(this, l10n) を使う)。
  final String? message;

  @override
  String toString() => 'GroupApiException(code=$code, msg=$message)';
}

/// オフライン or サーバー到達不能
class GroupNetworkException extends GroupApiException {
  const GroupNetworkException({String? message})
      : super(GroupApiErrorCode.network, message: message);
}

/// 認証エラー (401)
class GroupUnauthorizedException extends GroupApiException {
  const GroupUnauthorizedException()
      : super(GroupApiErrorCode.authRequired);
}

/// Pro プラン未契約
class GroupProRequiredException extends GroupApiException {
  const GroupProRequiredException()
      : super(GroupApiErrorCode.proRequired);
}

/// 権限不足 (403)
class GroupForbiddenException extends GroupApiException {
  const GroupForbiddenException({String? message})
      : super(GroupApiErrorCode.permissionDenied, message: message);
}

/// 招待コードが無効 / 期限切れ
class InviteCodeInvalidException extends GroupApiException {
  const InviteCodeInvalidException()
      : super(GroupApiErrorCode.inviteCodeInvalid);
}

/// 招待コードが既に使用済み
class InviteCodeAlreadyUsedException extends GroupApiException {
  const InviteCodeAlreadyUsedException()
      : super(GroupApiErrorCode.inviteCodeAlreadyUsed);
}

/// グループが満員 (5人上限)
class GroupFullException extends GroupApiException {
  const GroupFullException() : super(GroupApiErrorCode.groupFull);
}

/// 自分が既にメンバー
class AlreadyMemberException extends GroupApiException {
  const AlreadyMemberException() : super(GroupApiErrorCode.alreadyMember);
}

/// グループ参加上限超過
class GroupLimitReachedException extends GroupApiException {
  const GroupLimitReachedException()
      : super(GroupApiErrorCode.groupLimitReached);
}

/// 400 系。code で具体的理由を識別する。
class GroupBadRequestException extends GroupApiException {
  const GroupBadRequestException(GroupApiErrorCode code, {String? message})
      : super(code, message: message);
}

/// サーバーエラー (5xx)
class GroupServerException extends GroupApiException {
  const GroupServerException({String? message})
      : super(GroupApiErrorCode.serverError, message: message);
}

/// 未実装エンドポイント (legacy、build 31 以降は通常起こらない)
class GroupNotImplementedException extends GroupApiException {
  const GroupNotImplementedException(String operation)
      : super(GroupApiErrorCode.notImplemented, message: operation);
}

/// 想定外
class GroupUnknownException extends GroupApiException {
  const GroupUnknownException({String? message})
      : super(GroupApiErrorCode.unknown, message: message);
}
