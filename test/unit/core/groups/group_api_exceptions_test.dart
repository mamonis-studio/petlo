// ============================================================================
// petlo - GroupApiException Tests
// ============================================================================
//
// build 35 (H1) で enum 化。各サブクラスは GroupApiErrorCode を持ち、UI 表示は
// helper (groupApiErrorMessage) で l10n 経由に解決する設計。本テストは
//   - code が正しく付与されているか
//   - sealed switch が網羅できているか
//   - log 用 message が引数経由で保持されるか
// を確認する。l10n 解決はヘルパー側のスナップショットテスト対象。
//
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/core/groups/group_api_exceptions.dart';

void main() {
  group('GroupApiException codes', () {
    test('GroupNetworkException', () {
      const e = GroupNetworkException(message: '接続失敗');
      expect(e.code, GroupApiErrorCode.network);
      expect(e.message, '接続失敗');
      expect(e.toString(), contains('network'));
    });

    test('GroupUnauthorizedException', () {
      const e = GroupUnauthorizedException();
      expect(e.code, GroupApiErrorCode.authRequired);
    });

    test('GroupProRequiredException', () {
      const e = GroupProRequiredException();
      expect(e.code, GroupApiErrorCode.proRequired);
    });

    test('GroupForbiddenException', () {
      const e = GroupForbiddenException(message: '権限なし');
      expect(e.code, GroupApiErrorCode.permissionDenied);
      expect(e.message, '権限なし');
    });

    test('InviteCodeInvalidException', () {
      const e = InviteCodeInvalidException();
      expect(e.code, GroupApiErrorCode.inviteCodeInvalid);
    });

    test('InviteCodeAlreadyUsedException', () {
      const e = InviteCodeAlreadyUsedException();
      expect(e.code, GroupApiErrorCode.inviteCodeAlreadyUsed);
    });

    test('GroupFullException', () {
      const e = GroupFullException();
      expect(e.code, GroupApiErrorCode.groupFull);
    });

    test('AlreadyMemberException', () {
      const e = AlreadyMemberException();
      expect(e.code, GroupApiErrorCode.alreadyMember);
    });

    test('GroupLimitReachedException', () {
      const e = GroupLimitReachedException();
      expect(e.code, GroupApiErrorCode.groupLimitReached);
    });

    test('GroupBadRequestException carries the given code', () {
      const e =
          GroupBadRequestException(GroupApiErrorCode.invalidGroupName);
      expect(e.code, GroupApiErrorCode.invalidGroupName);
    });

    test('GroupServerException', () {
      const e = GroupServerException(message: '500エラー');
      expect(e.code, GroupApiErrorCode.serverError);
      expect(e.message, '500エラー');
    });

    test('GroupNotImplementedException carries operation in message', () {
      const e = GroupNotImplementedException('権限変更');
      expect(e.code, GroupApiErrorCode.notImplemented);
      expect(e.message, '権限変更');
    });

    test('GroupUnknownException', () {
      const e = GroupUnknownException(message: '?');
      expect(e.code, GroupApiErrorCode.unknown);
      expect(e.message, '?');
    });
  });

  group('GroupApiException sealed switch', () {
    String labelFor(GroupApiException e) {
      return switch (e) {
        GroupNetworkException() => 'network',
        GroupUnauthorizedException() => 'unauthorized',
        GroupProRequiredException() => 'pro',
        GroupForbiddenException() => 'forbidden',
        InviteCodeInvalidException() => 'invalid',
        InviteCodeAlreadyUsedException() => 'used',
        GroupFullException() => 'full',
        AlreadyMemberException() => 'already_member',
        GroupLimitReachedException() => 'limit_reached',
        GroupBadRequestException() => 'bad_request',
        GroupServerException() => 'server',
        GroupNotImplementedException() => 'not_implemented',
        GroupUnknownException() => 'unknown',
      };
    }

    test('all 13 types map correctly', () {
      expect(labelFor(const GroupNetworkException()), 'network');
      expect(labelFor(const GroupUnauthorizedException()), 'unauthorized');
      expect(labelFor(const GroupProRequiredException()), 'pro');
      expect(labelFor(const GroupForbiddenException()), 'forbidden');
      expect(labelFor(const InviteCodeInvalidException()), 'invalid');
      expect(labelFor(const InviteCodeAlreadyUsedException()), 'used');
      expect(labelFor(const GroupFullException()), 'full');
      expect(labelFor(const AlreadyMemberException()), 'already_member');
      expect(labelFor(const GroupLimitReachedException()), 'limit_reached');
      expect(
        labelFor(const GroupBadRequestException(GroupApiErrorCode.badRequest)),
        'bad_request',
      );
      expect(labelFor(const GroupServerException()), 'server');
      expect(labelFor(const GroupNotImplementedException('op')),
          'not_implemented');
      expect(labelFor(const GroupUnknownException()), 'unknown');
    });
  });
}
