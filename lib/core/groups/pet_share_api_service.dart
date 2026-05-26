// ============================================================================
// petlo - Pet Share API Service
// ============================================================================
//
// Cloudflare Workers `/pets/{petServerId}/shares` 系 endpoint への HTTP 通信。
// build 45 (Phase G4a) で新設。backend は G3-D で実装済み (Phase G3 完了報告
// 参照)。
//
// 提供する操作:
//   - GET    /pets/{petServerId}/shares           — 共有先一覧取得
//   - POST   /pets/{petServerId}/shares           — 新規共有 (scope 追加)
//   - DELETE /pets/{petServerId}/shares/{groupId} — 共有解除
//   - PATCH  /pets/{petServerId}/shares/{groupId} — per-pet 権限変更
//
// エラーは GroupApiException 系に集約 (HTTP 404 → notFound、403 →
// permissionDenied、ネットワーク → network、Pro 必須 → proRequired)。
// pet 単位の細粒度エラー型を別途切らないのは、UI 側で「グループ操作」と
// 同じ通知 UX に統合できるため。
//
// ============================================================================

import 'package:dio/dio.dart';

import '../../data/local/database_enums.dart';
import '../auth/api_dio.dart';
import '../utils/logger.dart';
import 'group_api_exceptions.dart';
import 'pet_share_api_dtos.dart';

class PetShareApiService {
  PetShareApiService({Dio? dio}) : _dio = dio ?? ApiDio.instance;

  final Dio _dio;

  // ==========================================================================
  // GET /pets/{petServerId}/shares
  // ==========================================================================
  Future<PetSharesListDto> listShares(String petServerId) async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('/pets/$petServerId/shares');
      final dynamic body = resp.data;
      if (body is! Map<String, dynamic>) {
        throw const GroupUnknownException(message: 'Invalid response format');
      }
      return PetSharesListDto.fromJson(body);
    } on DioException catch (e) {
      throw _mapDioError(e, operation: 'list shares');
    } catch (e, st) {
      PetloLogger.instance
          .w('listShares failed', error: e, stackTrace: st);
      if (e is GroupApiException) rethrow;
      throw GroupUnknownException(message: e.toString());
    }
  }

  // ==========================================================================
  // POST /pets/{petServerId}/shares
  // ==========================================================================
  Future<PetShareDto> createShare({
    required String petServerId,
    required String groupId,
    required MemberPermission permission,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.post<dynamic>(
        '/pets/$petServerId/shares',
        data: <String, dynamic>{
          'groupId': groupId,
          'permission': permission.name,
        },
      );
      final dynamic body = resp.data;
      if (body is! Map<String, dynamic>) {
        throw const GroupUnknownException(message: 'Invalid response format');
      }
      return PetShareDto.fromJson(body);
    } on DioException catch (e) {
      throw _mapDioError(e, operation: 'create share');
    } catch (e, st) {
      PetloLogger.instance
          .w('createShare failed', error: e, stackTrace: st);
      if (e is GroupApiException) rethrow;
      throw GroupUnknownException(message: e.toString());
    }
  }

  // ==========================================================================
  // DELETE /pets/{petServerId}/shares/{groupId}
  // ==========================================================================
  Future<void> deleteShare({
    required String petServerId,
    required String groupId,
  }) async {
    try {
      await _dio.delete<dynamic>('/pets/$petServerId/shares/$groupId');
    } on DioException catch (e) {
      throw _mapDioError(e, operation: 'delete share');
    } catch (e, st) {
      PetloLogger.instance
          .w('deleteShare failed', error: e, stackTrace: st);
      if (e is GroupApiException) rethrow;
      throw GroupUnknownException(message: e.toString());
    }
  }

  // ==========================================================================
  // PATCH /pets/{petServerId}/shares/{groupId}
  // ==========================================================================
  Future<PetShareDto> updatePermission({
    required String petServerId,
    required String groupId,
    required MemberPermission permission,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.patch<dynamic>(
        '/pets/$petServerId/shares/$groupId',
        data: <String, dynamic>{
          'permission': permission.name,
        },
      );
      final dynamic body = resp.data;
      if (body is! Map<String, dynamic>) {
        throw const GroupUnknownException(message: 'Invalid response format');
      }
      return PetShareDto.fromJson(body);
    } on DioException catch (e) {
      throw _mapDioError(e, operation: 'update permission');
    } catch (e, st) {
      PetloLogger.instance
          .w('updatePermission failed', error: e, stackTrace: st);
      if (e is GroupApiException) rethrow;
      throw GroupUnknownException(message: e.toString());
    }
  }

  // ==========================================================================
  // Error mapping (group_api_service と同一ポリシー)
  // ==========================================================================
  GroupApiException _mapDioError(
    DioException e, {
    required String operation,
  }) {
    PetloLogger.instance.d(
        'PetShareAPI DioException: type=${e.type}, '
        'status=${e.response?.statusCode}, op=$operation');

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

      switch (status) {
        case 400:
          return GroupBadRequestException(
            GroupApiErrorCode.badRequest,
            message: errMsg,
          );
        case 401:
          return const GroupUnauthorizedException();
        case 403:
          if (errMsg != null && errMsg.toLowerCase().contains('pro')) {
            return const GroupProRequiredException();
          }
          return GroupForbiddenException(message: errMsg);
        case 404:
          return GroupBadRequestException(
            GroupApiErrorCode.notFound,
            message: errMsg,
          );
        case 409:
          // primary scope の削除など。conflict として扱う。
          return GroupBadRequestException(
            GroupApiErrorCode.conflict,
            message: errMsg,
          );
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
}
