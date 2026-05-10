// ============================================================================
// petlo - GroupApiException Tests
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/core/groups/group_api_exceptions.dart';

void main() {
  // ==========================================================================
  // 各例外型がメッセージを持つ
  // ==========================================================================
  group('GroupApiException messages', () {
    test('GroupNetworkException', () {
      const e = GroupNetworkException('接続失敗');
      expect(e.message, '接続失敗');
      expect(e.toString(), contains('接続失敗'));
    });

    test('GroupUnauthorizedException has fixed message', () {
      const e = GroupUnauthorizedException();
      expect(e.message, contains('再ログイン'));
    });

    test('GroupProRequiredException has fixed message', () {
      const e = GroupProRequiredException();
      expect(e.message, contains('Pro'));
    });

    test('GroupForbiddenException', () {
      const e = GroupForbiddenException('権限なし');
      expect(e.message, '権限なし');
    });

    test('InviteCodeInvalidException', () {
      const e = InviteCodeInvalidException();
      expect(e.message, contains('無効'));
    });

    test('InviteCodeAlreadyUsedException', () {
      const e = InviteCodeAlreadyUsedException();
      expect(e.message, contains('使用'));
    });

    test('GroupFullException mentions 5人上限', () {
      const e = GroupFullException();
      expect(e.message, contains('5'));
    });

    test('AlreadyMemberException', () {
      const e = AlreadyMemberException();
      expect(e.message, contains('既に'));
    });

    test('GroupLimitReachedException mentions 3つ上限', () {
      const e = GroupLimitReachedException();
      expect(e.message, contains('3'));
    });

    test('GroupBadRequestException', () {
      const e = GroupBadRequestException('不正リクエスト');
      expect(e.message, '不正リクエスト');
    });

    test('GroupServerException', () {
      const e = GroupServerException('500エラー');
      expect(e.message, '500エラー');
    });

    test('GroupNotImplementedException with operation name', () {
      const e = GroupNotImplementedException('権限変更');
      expect(e.message, contains('権限変更'));
      expect(e.message, contains('実装'));
    });

    test('GroupUnknownException', () {
      const e = GroupUnknownException('?');
      expect(e.message, '?');
    });
  });

  // ==========================================================================
  // sealed class での switch 網羅性
  // (コンパイル時チェック: すべての case をカバーすれば default 不要)
  // ==========================================================================
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
      expect(labelFor(const GroupNetworkException('a')), 'network');
      expect(labelFor(const GroupUnauthorizedException()), 'unauthorized');
      expect(labelFor(const GroupProRequiredException()), 'pro');
      expect(labelFor(const GroupForbiddenException('a')), 'forbidden');
      expect(labelFor(const InviteCodeInvalidException()), 'invalid');
      expect(labelFor(const InviteCodeAlreadyUsedException()), 'used');
      expect(labelFor(const GroupFullException()), 'full');
      expect(labelFor(const AlreadyMemberException()), 'already_member');
      expect(labelFor(const GroupLimitReachedException()), 'limit_reached');
      expect(labelFor(const GroupBadRequestException('a')), 'bad_request');
      expect(labelFor(const GroupServerException('a')), 'server');
      expect(labelFor(const GroupNotImplementedException('op')),
          'not_implemented');
      expect(labelFor(const GroupUnknownException('a')), 'unknown');
    });
  });
}
