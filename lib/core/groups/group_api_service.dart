// ============================================================================
// petlo - Group API Service
// ============================================================================
//
// Cloudflare Workers `/api/...` への HTTP 通信を担うサービス。
//
// 提供する操作:
//   - グループ作成 (Pro オーナー必須)
//   - 招待コード発行 (Pro オーナー必須、72h TTL)
//   - 招待コードで参加
//   - メンバー権限変更 / 除名 (Owner のみ)
//   - グループ退出
//
// 設計:
//   - dio で HTTP 通信、AiService と同じパターン
//   - サーバー側未実装エンドポイントは GroupNotImplementedException
//   - DioException → GroupApiException マッピング
//
// 注意:
//   - サーバー側の現状は invite/join のみ実装
//   - 他のエンドポイントはハンドラ未実装、404 が返る → GroupNotImplemented
//   - 本番では Workers 側を Chunk 21 後半 / 別 PR で拡張する
//
// ============================================================================

import 'package:dio/dio.dart';

import '../../data/local/database_enums.dart';
import '../auth/api_dio.dart';
import '../utils/logger.dart';
import 'group_api_dtos.dart';
import 'group_api_exceptions.dart';

class GroupApiService {
  /// 共通 Dio (AuthDioInterceptor 装着済) を使う。
  /// 認証ヘッダーは AuthService が一元管理するので、ここでは何も操作しない。
  GroupApiService({Dio? dio}) : _dio = dio ?? ApiDio.instance;

  final Dio _dio;

  // ==========================================================================
  // グループ作成 (POST /groups)
  // build 18: ownerDisplayName 必須 (backend が 400 'display_name_required'
  //           を返すため、必ず送信する)
  // ==========================================================================
  Future<CreateGroupResultDto> createGroup(
    String name, {
    required String displayName,
  }) async {
    if (name.trim().isEmpty || name.trim().length > 50) {
      throw const GroupBadRequestException('グループ名は1〜50文字で入力してください');
    }
    if (displayName.trim().isEmpty || displayName.trim().length > 30) {
      throw const GroupBadRequestException('表示名は1〜30文字で入力してください');
    }

    try {
      final Response<dynamic> resp = await _dio.post<dynamic>(
        '/groups',
        data: <String, dynamic>{
          'name': name.trim(),
          'ownerDisplayName': displayName.trim(),
        },
      );
      final dynamic body = resp.data;
      if (body is! Map<String, dynamic>) {
        throw const GroupUnknownException('Invalid response format');
      }
      return CreateGroupResultDto.fromJson(body);
    } on DioException catch (e) {
      throw _mapDioError(e, operation: 'グループ作成');
    } catch (e, st) {
      PetloLogger.instance
          .w('createGroup failed', error: e, stackTrace: st);
      if (e is GroupApiException) rethrow;
      throw GroupUnknownException(e.toString());
    }
  }

  // ==========================================================================
  // 招待コード発行 (POST /invite)
  // ==========================================================================
  Future<CreateInviteResultDto> createInvite({
    required String groupRemoteId,
    required MemberPermission grantedPermission,
  }) async {
    if (grantedPermission == MemberPermission.owner) {
      throw const GroupBadRequestException(
          'Owner権限の招待コードは発行できません');
    }

    try {
      final Response<dynamic> resp = await _dio.post<dynamic>(
        '/invite',
        data: <String, dynamic>{
          'group_id': groupRemoteId,
          // サーバー側 3段階対応待ち、暫定で permission を送る
          'granted_permission': grantedPermission.name,
        },
      );
      final dynamic body = resp.data;
      if (body is! Map<String, dynamic>) {
        throw const GroupUnknownException('Invalid response format');
      }
      return CreateInviteResultDto.fromJson(body, grantedPermission);
    } on DioException catch (e) {
      throw _mapDioError(e, operation: '招待コード発行');
    } catch (e, st) {
      PetloLogger.instance
          .w('createInvite failed', error: e, stackTrace: st);
      if (e is GroupApiException) rethrow;
      throw GroupUnknownException(e.toString());
    }
  }

  // ==========================================================================
  // 招待コードで参加 (POST /join)
  // ==========================================================================
  Future<JoinGroupResultDto> joinByCode({
    required String code,
    required String displayName,
  }) async {
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const GroupBadRequestException(
          '6桁の数字を入力してください');
    }
    if (displayName.trim().isEmpty || displayName.length > 30) {
      throw const GroupBadRequestException(
          '表示名は1〜30文字で入力してください');
    }

    try {
      final Response<dynamic> resp = await _dio.post<dynamic>(
        '/join',
        data: <String, dynamic>{
          'code': code,
          'display_name': displayName.trim(),
        },
      );
      final dynamic body = resp.data;
      if (body is! Map<String, dynamic>) {
        throw const GroupUnknownException('Invalid response format');
      }
      return JoinGroupResultDto.fromJson(body);
    } on DioException catch (e) {
      throw _mapJoinError(e);
    } catch (e, st) {
      PetloLogger.instance
          .w('joinByCode failed', error: e, stackTrace: st);
      if (e is GroupApiException) rethrow;
      throw GroupUnknownException(e.toString());
    }
  }

  // ==========================================================================
  // メンバー権限変更 (PATCH /groups/:id/members/:uid)
  // ==========================================================================
  Future<void> updateMemberPermission({
    required String groupRemoteId,
    required String userId,
    required MemberPermission permission,
  }) async {
    if (permission == MemberPermission.owner) {
      throw const GroupBadRequestException(
          'Ownerへの昇格は譲渡UIから行ってください');
    }

    try {
      await _dio.patch<dynamic>(
        '/groups/$groupRemoteId/members/$userId',
        data: <String, dynamic>{
          'permission': permission.name,
        },
      );
    } on DioException catch (e) {
      throw _mapDioError(e, operation: '権限変更');
    } catch (e, st) {
      PetloLogger.instance
          .w('updateMemberPermission failed', error: e, stackTrace: st);
      if (e is GroupApiException) rethrow;
      throw GroupUnknownException(e.toString());
    }
  }

  // ==========================================================================
  // メンバー除名 (DELETE /groups/:id/members/:uid)
  // ==========================================================================
  Future<void> removeMember({
    required String groupRemoteId,
    required String userId,
  }) async {
    try {
      await _dio.delete<dynamic>(
        '/groups/$groupRemoteId/members/$userId',
      );
    } on DioException catch (e) {
      throw _mapDioError(e, operation: 'メンバー除名');
    } catch (e, st) {
      PetloLogger.instance
          .w('removeMember failed', error: e, stackTrace: st);
      if (e is GroupApiException) rethrow;
      throw GroupUnknownException(e.toString());
    }
  }

  // ==========================================================================
  // グループ退出 (DELETE /groups/:id/leave)
  // ==========================================================================
  Future<void> leaveGroup(String groupRemoteId) async {
    try {
      await _dio.delete<dynamic>('/groups/$groupRemoteId/leave');
    } on DioException catch (e) {
      throw _mapDioError(e, operation: 'グループ退出');
    } catch (e, st) {
      PetloLogger.instance
          .w('leaveGroup failed', error: e, stackTrace: st);
      if (e is GroupApiException) rethrow;
      throw GroupUnknownException(e.toString());
    }
  }

  // ==========================================================================
  // Helpers
  // ==========================================================================

  GroupApiException _mapDioError(
    DioException e, {
    required String operation,
  }) {
    PetloLogger.instance.d(
        'GroupAPI DioException: type=${e.type}, status=${e.response?.statusCode}, op=$operation');

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return GroupNetworkException(e.message ?? 'ネットワークエラー');
    }

    if (e.type == DioExceptionType.badResponse) {
      final int? status = e.response?.statusCode;
      final dynamic body = e.response?.data;
      final String? errMsg =
          body is Map<String, dynamic> ? body['error'] as String? : null;

      switch (status) {
        case 400:
          return GroupBadRequestException(errMsg ?? 'リクエストが不正です');
        case 401:
          return const GroupUnauthorizedException();
        case 403:
          // Pro 必須 / 権限不足の区別
          if (errMsg != null && errMsg.toLowerCase().contains('pro')) {
            return const GroupProRequiredException();
          }
          return GroupForbiddenException(errMsg ?? '権限がありません');
        case 404:
          return GroupNotImplementedException(operation);
        case 409:
          return GroupBadRequestException(errMsg ?? '競合が発生しました');
        case 500:
        case 502:
        case 503:
        case 504:
          return GroupServerException(errMsg ?? 'サーバーエラー');
        default:
          return GroupUnknownException(errMsg ?? 'HTTP $status');
      }
    }

    return GroupUnknownException(e.message ?? e.type.toString());
  }

  /// join 専用のエラーマッピング
  /// 招待コード固有のエラー(無効/使用済み/満員)を分けて投げる
  GroupApiException _mapJoinError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return GroupNetworkException(e.message ?? 'ネットワークエラー');
    }

    if (e.type == DioExceptionType.badResponse) {
      final int? status = e.response?.statusCode;
      final dynamic body = e.response?.data;
      final String? errMsg =
          body is Map<String, dynamic> ? body['error'] as String? : null;
      final String lower = (errMsg ?? '').toLowerCase();

      if (status == 400 || status == 410 || status == 404) {
        if (lower.contains('expired') || lower.contains('not found')) {
          return const InviteCodeInvalidException();
        }
        if (lower.contains('used') || lower.contains('already')) {
          return const InviteCodeAlreadyUsedException();
        }
        if (lower.contains('full') || lower.contains('member')) {
          return const GroupFullException();
        }
        if (lower.contains('limit') ||
            lower.contains('max') ||
            lower.contains('3 ')) {
          return const GroupLimitReachedException();
        }
        return GroupBadRequestException(errMsg ?? '招待コードが無効です');
      }
      if (status == 401) return const GroupUnauthorizedException();
      if (status == 409) return const AlreadyMemberException();
      if (status != null && status >= 500) {
        return GroupServerException(errMsg ?? 'サーバーエラー');
      }
      return GroupUnknownException(errMsg ?? 'HTTP $status');
    }

    return GroupUnknownException(e.message ?? e.type.toString());
  }
}
