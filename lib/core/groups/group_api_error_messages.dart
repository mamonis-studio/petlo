// ============================================================================
// petlo - Group API Error Messages (UI helper)
// ============================================================================
//
// GroupApiException → 多言語化された UI 表示文字列への写像。
// UI 側 (Controller / Screen) は必ずこのヘルパー経由でメッセージを取得する。
// 例外側の `message` フィールドはログ用途のみ。
//
// build 35: H1 対応で導入。switch は exhaustive (default 無し) なので
// GroupApiErrorCode に追加した瞬間に未網羅を analyzer が指摘する。
//
// ============================================================================

import '../../l10n/generated/app_localizations.dart';
import 'group_api_exceptions.dart';

String groupApiErrorMessage(GroupApiException e, AppLocalizations l10n) {
  return _messageForCode(e.code, l10n);
}

String _messageForCode(GroupApiErrorCode code, AppLocalizations l10n) {
  switch (code) {
    case GroupApiErrorCode.network:
      return l10n.group_api_error_network;
    case GroupApiErrorCode.authRequired:
      return l10n.group_api_error_authRequired;
    case GroupApiErrorCode.permissionDenied:
      return l10n.group_api_error_permissionDenied;
    case GroupApiErrorCode.notFound:
      return l10n.group_api_error_notFound;
    case GroupApiErrorCode.conflict:
      return l10n.group_api_error_conflict;
    case GroupApiErrorCode.badRequest:
      return l10n.group_api_error_badRequest;
    case GroupApiErrorCode.serverError:
      return l10n.group_api_error_serverError;
    case GroupApiErrorCode.notImplemented:
      return l10n.group_api_error_notImplemented;
    case GroupApiErrorCode.unknown:
      return l10n.group_api_error_unknown;
    case GroupApiErrorCode.proRequired:
      return l10n.group_api_error_proRequired;
    case GroupApiErrorCode.invalidGroupName:
      return l10n.group_api_error_invalidGroupName;
    case GroupApiErrorCode.invalidDisplayName:
      return l10n.group_api_error_invalidDisplayName;
    case GroupApiErrorCode.missingGroupId:
      return l10n.group_api_error_missingGroupId;
    case GroupApiErrorCode.cannotPromoteToOwner:
      return l10n.group_api_error_cannotPromoteToOwner;
    case GroupApiErrorCode.ownerInviteForbidden:
      return l10n.group_api_error_ownerInviteForbidden;
    case GroupApiErrorCode.emptyInviteCode:
      return l10n.group_api_error_emptyInviteCode;
    case GroupApiErrorCode.invalidInviteCodeFormat:
      return l10n.group_api_error_invalidInviteCodeFormat;
    case GroupApiErrorCode.inviteCodeInvalid:
      return l10n.group_api_error_inviteCodeInvalid;
    case GroupApiErrorCode.inviteCodeAlreadyUsed:
      return l10n.group_api_error_inviteCodeAlreadyUsed;
    case GroupApiErrorCode.groupFull:
      return l10n.group_api_error_groupFull;
    case GroupApiErrorCode.alreadyMember:
      return l10n.group_api_error_alreadyMember;
    case GroupApiErrorCode.groupLimitReached:
      return l10n.group_api_error_groupLimitReached;
  }
}
