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
//   - DioException → GroupApiException マッピング
//   - 404 は「対象不在」(GroupBadRequestException)。build 31 以降、backend は
//     メンバー管理・退出 endpoint も実装済み。
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
      throw const GroupBadRequestException(
          GroupApiErrorCode.invalidGroupName);
    }
    if (displayName.trim().isEmpty || displayName.trim().length > 20) {
      throw const GroupBadRequestException(
          GroupApiErrorCode.invalidDisplayName);
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
        throw const GroupUnknownException(message: 'Invalid response format');
      }
      return CreateGroupResultDto.fromJson(body);
    } on DioException catch (e) {
      throw _mapDioError(e, operation: 'グループ作成');
    } catch (e, st) {
      PetloLogger.instance
          .w('createGroup failed', error: e, stackTrace: st);
      if (e is GroupApiException) rethrow;
      throw GroupUnknownException(message: e.toString());
    }
  }

  // ==========================================================================
  // 招待コード発行 (POST /groups/:gid/invites)
  // build 19: 旧 /invite から正しいパス /groups/:gid/invites へ移行。
  //           リクエストは camelCase、body は { permission, ttlHours? }。
  //           ttlHours 省略時は backend default 72 が適用される。
  // ==========================================================================
  Future<CreateInviteResultDto> createInvite({
    required String groupRemoteId,
    required MemberPermission grantedPermission,
    int? ttlHours,
  }) async {
    if (grantedPermission == MemberPermission.owner) {
      throw const GroupBadRequestException(
          GroupApiErrorCode.ownerInviteForbidden);
    }
    if (groupRemoteId.trim().isEmpty) {
      // build 21: 旧 DTO パースバグで groupId='' のままここまで来るのを防ぐ
      throw const GroupBadRequestException(
          GroupApiErrorCode.missingGroupId);
    }

    try {
      final Response<dynamic> resp = await _dio.post<dynamic>(
        '/groups/$groupRemoteId/invites',
        data: <String, dynamic>{
          'permission': grantedPermission.name,
          if (ttlHours != null) 'ttlHours': ttlHours,
        },
      );
      final dynamic body = resp.data;
      if (body is! Map<String, dynamic>) {
        throw const GroupUnknownException(message: 'Invalid response format');
      }
      return CreateInviteResultDto.fromJson(body, grantedPermission);
    } on DioException catch (e) {
      throw _mapDioError(e, operation: '招待コード発行');
    } catch (e, st) {
      PetloLogger.instance
          .w('createInvite failed', error: e, stackTrace: st);
      if (e is GroupApiException) rethrow;
      throw GroupUnknownException(message: e.toString());
    }
  }

  // ==========================================================================
  // 招待コードで参加 (POST /invites/<code>/join)
  // build 24: 旧 /join (code を body に詰める) から正しい RESTful path に修正。
  //           code は URL path、body は { displayName } のみ (camelCase)。
  // ==========================================================================
  Future<JoinGroupResultDto> joinByCode({
    required String code,
    required String displayName,
  }) async {
    if (code.trim().isEmpty) {
      // build 24: 空コードガード (path が /invites//join に崩れて 404 になるのを防ぐ)
      throw const GroupBadRequestException(
          GroupApiErrorCode.emptyInviteCode);
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const GroupBadRequestException(
          GroupApiErrorCode.invalidInviteCodeFormat);
    }
    if (displayName.trim().isEmpty || displayName.length > 20) {
      throw const GroupBadRequestException(
          GroupApiErrorCode.invalidDisplayName);
    }

    try {
      final Response<dynamic> resp = await _dio.post<dynamic>(
        '/invites/$code/join',
        data: <String, dynamic>{
          'displayName': displayName.trim(),
        },
      );
      final dynamic body = resp.data;
      if (body is! Map<String, dynamic>) {
        throw const GroupUnknownException(message: 'Invalid response format');
      }
      return JoinGroupResultDto.fromJson(body);
    } on DioException catch (e) {
      throw _mapJoinError(e);
    } catch (e, st) {
      PetloLogger.instance
          .w('joinByCode failed', error: e, stackTrace: st);
      if (e is GroupApiException) rethrow;
      throw GroupUnknownException(message: e.toString());
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
          GroupApiErrorCode.cannotPromoteToOwner);
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
      throw GroupUnknownException(message: e.toString());
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
      throw GroupUnknownException(message: e.toString());
    }
  }

  // ==========================================================================
  // 自分が属するグループ一覧 (GET /groups)
  // build 55-client: 認証直後の fullPull で「サーバが知ってる自分のグループ群」を
  // 列挙するのに使う。アプリ削除→再インストール時にローカル DB が空でも、
  // この endpoint でサーバ既存データへの足がかりを得る。
  //
  // レスポンス想定形式:
  //   { "groups": [ { "id": "<uuid>", "name": "...", "myPermission": "owner|editor|viewer", ... } ] }
  //
  // 旧サーバが未実装の場合は 404 → catch 側で空リスト扱い (fullPull が no-op)。
  // ==========================================================================
  Future<List<String>> listMyGroupRemoteIds() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('/groups');
      final dynamic body = resp.data;
      if (body is! Map<String, dynamic>) return const <String>[];
      final dynamic groups = body['groups'];
      if (groups is! List) return const <String>[];
      final List<String> out = <String>[];
      for (final dynamic g in groups) {
        if (g is Map<String, dynamic>) {
          final dynamic id = g['id'] ?? g['remoteId'] ?? g['groupId'];
          if (id is String && id.isNotEmpty) out.add(id);
        } else if (g is String && g.isNotEmpty) {
          out.add(g);
        }
      }
      return out;
    } on DioException catch (e) {
      // 404 (未実装) や 401 (auth 失敗) はすべて空リストで吸収。
      PetloLogger.instance.d(
        'listMyGroupRemoteIds: ${e.response?.statusCode} ${e.message}',
      );
      return const <String>[];
    } catch (e, st) {
      PetloLogger.instance
          .w('listMyGroupRemoteIds unexpected', error: e, stackTrace: st);
      return const <String>[];
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
      throw GroupUnknownException(message: e.toString());
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
      return GroupNetworkException(message: e.message);
    }

    if (e.type == DioExceptionType.badResponse) {
      final int? status = e.response?.statusCode;
      final dynamic body = e.response?.data;
      final String? errMsg =
          body is Map<String, dynamic> ? body['error'] as String? : null;
      // build 55-client: 新サーバ(Worker 3bd2e407)は 409 に
      // `error_code` を付与する。"duplicate_name" / "user_at_group_limit"
      // / "user_already_has_data" のいずれか。旧サーバは未設定 → 旧 conflict
      // にフォールバック。
      final String? errCode = body is Map<String, dynamic>
          ? body['error_code'] as String?
          : null;

      switch (status) {
        case 400:
          return GroupBadRequestException(
            GroupApiErrorCode.badRequest,
            message: errMsg,
          );
        case 401:
          return const GroupUnauthorizedException();
        case 403:
          // Pro 必須 / 権限不足の区別
          if (errMsg != null && errMsg.toLowerCase().contains('pro')) {
            return const GroupProRequiredException();
          }
          return GroupForbiddenException(message: errMsg);
        case 404:
          // build 31: backend のメンバー管理・退出 endpoint は実装済み。
          // 404 はリソース不在 (削除されたグループ / 存在しないメンバー) を意味する。
          return GroupBadRequestException(
            GroupApiErrorCode.notFound,
            message: errMsg,
          );
        case 409:
          // build 55-client: error_code 別に細かい例外へマッピング。
          switch (errCode) {
            case 'duplicate_name':
              return GroupBadRequestException(
                GroupApiErrorCode.duplicateGroupName,
                message: errMsg,
              );
            case 'user_at_group_limit':
              return GroupBadRequestException(
                GroupApiErrorCode.userAtGroupLimit,
                message: errMsg,
              );
            case 'user_already_has_data':
              return GroupBadRequestException(
                GroupApiErrorCode.userAlreadyHasData,
                message: errMsg,
              );
            default:
              // 旧サーバ互換 — 詳細不明の conflict として扱う
              return GroupBadRequestException(
                GroupApiErrorCode.conflict,
                message: errMsg,
              );
          }
        case 500:
        case 502:
        case 503:
        case 504:
          return GroupServerException(message: errMsg);
        default:
          return GroupUnknownException(message: errMsg ?? 'HTTP $status');
      }
    }

    return GroupUnknownException(message: e.message ?? e.type.toString());
  }

  /// join 専用のエラーマッピング
  /// 招待コード固有のエラー(無効/使用済み/満員)を分けて投げる
  GroupApiException _mapJoinError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return GroupNetworkException(message: e.message);
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
        return GroupBadRequestException(
          GroupApiErrorCode.inviteCodeInvalid,
          message: errMsg,
        );
      }
      if (status == 401) return const GroupUnauthorizedException();
      if (status == 409) return const AlreadyMemberException();
      if (status != null && status >= 500) {
        return GroupServerException(message: errMsg);
      }
      return GroupUnknownException(message: errMsg ?? 'HTTP $status');
    }

    return GroupUnknownException(message: e.message ?? e.type.toString());
  }
}
