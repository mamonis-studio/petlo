// ============================================================================
// petlo - AI Service
// ============================================================================
//
// Cloudflare Workers `/api/chat` への HTTP 通信を担うサービス。
//
// rev3 F-18: AI相談チャット
// rev5.5 F-23a: プロンプトインジェクション対策
//   1. 入力500文字制限 (PromptValidator で検証済みの前提だが、再チェック)
//   2. 危険キーワード検知 (PromptValidator で実施)
//   3. XML構造で送信 → サーバー側プロンプトと混ざらないようラップ
//
// ============================================================================

import 'package:dio/dio.dart';

import '../auth/api_dio.dart';
import '../utils/logger.dart';
import 'ai_pet_context.dart';
import 'ai_service_exceptions.dart';
import 'prompt_validator.dart';

class AiChatResult {
  AiChatResult({
    required this.message,
    required this.messageId,
    required this.remainingCount,
  });

  final String message;
  final String messageId;
  final int remainingCount;
}

class AiService {
  /// 共通 Dio (AuthDioInterceptor 装着済) を使う。
  /// 認証ヘッダーは AuthService が一元管理するので、ここでは何も操作しない。
  AiService({Dio? dio}) : _dio = dio ?? ApiDio.instance;

  final Dio _dio;

  /// AI に質問を送信。
  ///
  /// 事前に [PromptValidator.validate] を通っていることが期待されるが、
  /// このメソッド内でも再度バリデーションする(2重防御)。
  Future<AiChatResult> sendMessage({
    required String message,
    required AiPetContextDto petContext,
    String? messageId,
  }) async {
    // 入力バリデーション(2重防御)
    final PromptValidationResult result = PromptValidator.validate(message);
    if (result is PromptValidationError) {
      throw AiBadRequestException(result.message);
    }
    final String sanitized = (result as PromptValidationOk).sanitized;

    // XML 構造でラップ:
    //   サーバー側プロンプトと混ざらないよう <user_question> でくるむ
    //   (サーバー側 prompts.ts でも同じタグを期待)
    final String wrapped = _wrapInXml(sanitized);

    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        '/chat',
        data: <String, dynamic>{
          'pet_context': petContext.toJson(),
          'message': wrapped,
          if (messageId != null) 'message_id': messageId,
        },
      );

      final dynamic data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const AiUnknownException('Invalid response format');
      }

      final String? respMsg = data['message'] as String?;
      final String? respId = data['message_id'] as String?;
      final int remaining = (data['remaining_count'] as num?)?.toInt() ?? 0;

      if (respMsg == null || respMsg.isEmpty || respId == null) {
        throw const AiUnknownException('Empty response');
      }

      return AiChatResult(
        message: respMsg,
        messageId: respId,
        remainingCount: remaining,
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    } catch (e, st) {
      PetloLogger.instance
          .w('AiService.sendMessage unexpected error',
              error: e, stackTrace: st);
      throw AiUnknownException(e.toString());
    }
  }

  // ==========================================================================
  // Helpers
  // ==========================================================================

  /// ユーザー入力を XML 構造化(サーバー側プロンプトと混ざるのを防ぐ)
  String _wrapInXml(String message) {
    // 念のため、ユーザー入力中の `</user_question>` を無害化
    final String safe =
        message.replaceAll(RegExp(r'<\s*/\s*user_question\s*>',
            caseSensitive: false), '');
    return '<user_question>$safe</user_question>';
  }

  /// DioException を AiServiceException にマップ
  AiServiceException _mapDioError(DioException e) {
    PetloLogger.instance.d(
        'DioException type=${e.type}, status=${e.response?.statusCode}, msg=${e.message}');

    // ネットワーク系
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      // オフライン or サーバー到達不能の区別はここでは難しいので、
      // 上位 (UI) で connectivityProvider を見て判断する想定
      return AiNetworkException(e.message ?? 'ネットワークエラー');
    }

    // HTTP ステータス系
    if (e.type == DioExceptionType.badResponse) {
      final int? status = e.response?.statusCode;
      final dynamic body = e.response?.data;
      final String? errMsg =
          (body is Map<String, dynamic> ? body['error'] as String? : null);

      switch (status) {
        case 400:
          return AiBadRequestException(errMsg ?? 'リクエストが不正です');
        case 401:
          return const AiUnauthorizedException();
        case 403:
          return const AiProRequiredException();
        case 429:
          // remaining_count が body に含まれてる可能性
          final int remaining = (body is Map<String, dynamic>
                  ? (body['remaining_count'] as num?)?.toInt()
                  : null) ??
              0;
          return AiQuotaExceededException(remaining);
        case 500:
        case 502:
        case 503:
        case 504:
          return AiServerException(errMsg ?? 'サーバーエラー');
        default:
          return AiUnknownException(errMsg ?? 'HTTP $status');
      }
    }

    // Cancel など
    return AiUnknownException(e.message ?? e.type.toString());
  }
}
