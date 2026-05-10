// ============================================================================
// petlo - Auth Dio Interceptor
// ============================================================================
//
// 1. onRequest: Authorization Bearer header を自動付与
//    (認証不要 endpoint は path で判定してスキップ)
// 2. onError: 401 を受け取ったら /auth/refresh で更新 → 元リクエスト再送
//    refresh 失敗時は AuthService に投げ戻し → /auth/anonymous で再認証 or
//    secure_storage クリア
// 3. 同時 401 リクエスト多発時は単純化のため最初のリフレッシュ完了を待ってリトライ
//
// ============================================================================

import 'dart:async';

import 'package:dio/dio.dart';

import '../utils/logger.dart';
import 'auth_service.dart';

class AuthDioInterceptor extends Interceptor {
  AuthDioInterceptor(this._authService);

  final AuthService _authService;

  /// 認証ヘッダーを付けない path
  static const Set<String> _publicPaths = <String>{
    '/health',
    '/',
    '/auth/anonymous',
    '/auth/refresh',
  };

  /// refresh 中に他のリクエストが 401 を返した時、待機させるための Completer
  Completer<void>? _refreshing;

  bool _isPublicPath(String path) {
    return _publicPaths.contains(path);
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_isPublicPath(options.path)) {
      handler.next(options);
      return;
    }

    final String? token = await _authService.currentToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final RequestOptions req = err.requestOptions;
    final int? status = err.response?.statusCode;

    // 401 以外、または public path 由来は素通り
    if (status != 401 || _isPublicPath(req.path)) {
      handler.next(err);
      return;
    }

    // 既にリトライ済みのリクエストは無限ループ回避でそのまま失敗
    if (req.extra['_retried'] == true) {
      handler.next(err);
      return;
    }

    // 既に他のリクエストが refresh 中なら待つ
    if (_refreshing != null) {
      try {
        await _refreshing!.future;
      } catch (_) {
        handler.next(err);
        return;
      }
      // 待機中に refresh 成功 → リトライ
      try {
        final Response<dynamic> retry = await _retry(req);
        handler.resolve(retry);
      } catch (e) {
        handler.next(err);
      }
      return;
    }

    // 自分が refresh を実行する番
    _refreshing = Completer<void>();
    try {
      final bool ok = await _authService.refreshTokens();
      if (!ok) {
        // refresh 失敗 → 匿名で再認証(同じ deviceId なので同じ user に紐付く)
        final bool reauth = await _authService.reauthenticate();
        if (!reauth) {
          _refreshing!.completeError('reauth_failed');
          _refreshing = null;
          handler.next(err);
          return;
        }
      }
      _refreshing!.complete();
      _refreshing = null;
    } catch (e, st) {
      PetloLogger.instance
          .w('Auth refresh failed', error: e, stackTrace: st);
      _refreshing?.completeError(e);
      _refreshing = null;
      handler.next(err);
      return;
    }

    // リトライ
    try {
      final Response<dynamic> retry = await _retry(req);
      handler.resolve(retry);
    } catch (_) {
      handler.next(err);
    }
  }

  Future<Response<dynamic>> _retry(RequestOptions req) async {
    final String? token = await _authService.currentToken();
    final Map<String, dynamic> headers = Map<String, dynamic>.from(req.headers);
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    final Map<String, dynamic> extra = Map<String, dynamic>.from(req.extra);
    extra['_retried'] = true;

    final RequestOptions next = req.copyWith(
      headers: headers,
      extra: extra,
    );

    // _authService.dio は AuthDioInterceptor が刺さっている同じ Dio。
    // _retried フラグで再帰を回避する設計のため安全。
    return _authService.dio.fetch<dynamic>(next);
  }
}
