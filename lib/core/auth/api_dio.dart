// ============================================================================
// petlo - 共通 Dio クライアント
// ============================================================================
//
// petlo-api (https://api.petlo.mamonis.studio) への HTTP 通信を一元管理する
// シングルトン Dio インスタンス。
//
// 設計:
//   - 認証ヘッダー注入 / 401 自動 refresh は AuthDioInterceptor が担当
//   - GroupApiService / AiService 等は ApiDio.instance を直接利用 (個別 Dio 作らない)
//   - refresh 用の Dio は別インスタンス (rawDio) を使い、interceptor の無限ループを回避
//
// ============================================================================

import 'package:dio/dio.dart';

import '../constants/app_constants.dart';

class ApiDio {
  ApiDio._();

  /// 認証付き共通 Dio。AuthDioInterceptor が自動装着される。
  /// AuthService.initialize() の後でないと未認証状態のまま。
  static final Dio _instance = _build();

  /// 認証なしの "raw" Dio。
  /// /auth/anonymous, /auth/refresh, /health 等の認証不要 endpoint と、
  /// AuthDioInterceptor 内部の refresh リクエストで使う。
  static final Dio _raw = _build();

  static Dio get instance => _instance;
  static Dio get raw => _raw;

  static Dio _build() {
    return Dio(
      BaseOptions(
        baseUrl: AppConstants.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 10),
        contentType: 'application/json',
        responseType: ResponseType.json,
      ),
    );
  }

  /// AuthService 初期化時に呼び、認証付き Dio に AuthDioInterceptor を装着。
  /// 装着済みなら何もしない。
  static void attachInterceptor(Interceptor interceptor) {
    final bool already = _instance.interceptors.any(
      (Interceptor i) => i.runtimeType == interceptor.runtimeType,
    );
    if (!already) {
      _instance.interceptors.add(interceptor);
    }
  }
}
