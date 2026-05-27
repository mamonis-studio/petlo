// ============================================================================
// petlo - Auth Service
// ============================================================================
//
// petlo-api 認証フロー:
//   1. main で AuthService.instance.initialize() を await
//   2. 起動済みかどうか secure_storage を確認
//      - 初回 (deviceId 無し): Uuid v4 を生成 → /auth/anonymous で認証
//      - 既存:                   token を読み込み、JWT exp を見て期限切れなら refresh
//   3. ApiDio に AuthDioInterceptor を装着
//   4. その後の API リクエストは自動的に Bearer 付き
//
// 失敗時:
//   - ネットワーク不通: ローカル既存 token のままアプリは起動 (オフライン耐性)
//   - 401 / refresh 失敗: secure_storage クリア → 次回起動で再 anonymous
//
// rev3: deviceId は アプリ削除で消える前提 (機種変は別途バックアップ ZIP 経路)
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../presentation/providers/storage_providers.dart';
import '../preferences/user_preferences.dart';
import '../utils/logger.dart';
import 'api_dio.dart';
import 'auth_dio_interceptor.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  // ---- 状態 ----
  String? _token;
  String? _refreshToken;
  String? _userId;
  String? _deviceId;
  int _accessExpiresAt = 0; // UTC msec
  bool _initialized = false;

  /// public Dio (interceptor 装着済)
  Dio get dio => ApiDio.instance;

  String? get userId => _userId;
  String? get deviceId => _deviceId;
  bool get isAuthenticated => _token != null && _userId != null;

  // ===========================================================================
  // 初期化 (main から呼ぶ)
  // ===========================================================================
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final FlutterSecureStorage storage = _storage();

    // device_id (永続、アプリ削除で消える)
    _deviceId = await storage.read(key: _deviceIdKey);
    if (_deviceId == null || _deviceId!.isEmpty) {
      _deviceId = const Uuid().v4();
      await storage.write(key: _deviceIdKey, value: _deviceId);
      PetloLogger.instance.i('Generated new deviceId: $_deviceId');
    }

    // 既存 token
    _token = await storage.read(key: SecureStorageKeys.apiAuthToken);
    _refreshToken = await storage.read(key: SecureStorageKeys.apiRefreshToken);
    _userId = await storage.read(key: SecureStorageKeys.userId);
    _accessExpiresAt = _parseExp(_token);

    // interceptor 装着 (1 回のみ)
    ApiDio.attachInterceptor(AuthDioInterceptor(this));

    if (_token == null || _userId == null) {
      // 初回 or storage クリア後 → anonymous 認証
      try {
        await _anonymous();
      } catch (e, st) {
        PetloLogger.instance
            .w('Initial anonymous auth failed', error: e, stackTrace: st);
        // ネット不通でも起動は続行 (オフライン耐性)
      }
    } else if (_isTokenExpiringSoon()) {
      // 期限切れ間近 → refresh。失敗したら同じ deviceId で再登録。
      // TestFlight 再インストール後など Keychain に残った orphan token を
      // 起動時に確実に正常化するための fallback。
      bool refreshed = false;
      try {
        refreshed = await refreshTokens();
      } catch (e, st) {
        PetloLogger.instance
            .w('Initial refresh threw', error: e, stackTrace: st);
      }
      if (!refreshed) {
        PetloLogger.instance.i(
          'refresh failed at startup → anonymous re-register',
        );
        try {
          await _anonymous();
        } catch (e, st) {
          PetloLogger.instance.w(
            'Startup re-register failed',
            error: e,
            stackTrace: st,
          );
        }
      }
    }

    PetloLogger.instance.i(
      'AuthService initialized: userId=$_userId, hasToken=${_token != null}',
    );
  }

  // ===========================================================================
  // public API
  // ===========================================================================

  /// AuthDioInterceptor が呼ぶ。期限間近なら refresh してから返す。
  Future<String?> currentToken() async {
    if (_token != null && _isTokenExpiringSoon()) {
      try {
        await refreshTokens();
      } catch (_) {
        // refresh 失敗時は古い token のまま返す (どのみち 401 で再 refresh が走る)
      }
    }
    return _token;
  }

  /// 401 を受け取った時に Interceptor から呼ばれる。
  /// refresh token で新 token を取得 → secure_storage 更新。
  Future<bool> refreshTokens() async {
    final String? rt = _refreshToken;
    if (rt == null || rt.isEmpty) return false;

    try {
      final Response<dynamic> resp = await ApiDio.raw.post<dynamic>(
        '/auth/refresh',
        data: <String, dynamic>{'refreshToken': rt},
      );
      final Map<String, dynamic> data = resp.data as Map<String, dynamic>;
      final String token = data['token'] as String;
      final String newRefresh = data['refreshToken'] as String;
      final int expiresAt = (data['expiresAt'] as num).toInt();
      await _persist(token: token, refreshToken: newRefresh, userId: _userId!);
      _accessExpiresAt = expiresAt;
      return true;
    } on DioException catch (e) {
      PetloLogger.instance.w(
        'refresh failed: ${e.response?.statusCode} ${e.response?.data}',
      );
      return false;
    } catch (e, st) {
      PetloLogger.instance.w('refresh failed', error: e, stackTrace: st);
      return false;
    }
  }

  /// refresh も失敗した時の最終手段: 同じ deviceId で再認証。
  /// (server 側は device_id 一致で同じ user に紐付ける)
  Future<bool> reauthenticate() async {
    try {
      await _anonymous();
      return _token != null;
    } catch (e, st) {
      PetloLogger.instance
          .w('reauthenticate failed', error: e, stackTrace: st);
      // secure_storage クリア (次回起動でクリーンに anonymous)
      final FlutterSecureStorage storage = _storage();
      await storage.delete(key: SecureStorageKeys.apiAuthToken);
      await storage.delete(key: SecureStorageKeys.apiRefreshToken);
      _token = null;
      _refreshToken = null;
      _accessExpiresAt = 0;
      return false;
    }
  }

  /// 開発者用「データリセット」: Keychain を完全クリア → 新しい deviceId で
  /// anonymous 再登録。サーバ側からは別 user 扱いになる。
  /// 呼び出し後、上位で drift DB drop + アプリ再起動を行う前提。
  Future<void> forceReset() async {
    final FlutterSecureStorage storage = _storage();
    await storage.delete(key: SecureStorageKeys.apiAuthToken);
    await storage.delete(key: SecureStorageKeys.apiRefreshToken);
    await storage.delete(key: SecureStorageKeys.userId);
    await storage.delete(key: _deviceIdKey);
    // build 18: display_name もリセット (新規ユーザー扱いなので)
    await UserPreferences.instance.setDisplayName(null);
    _token = null;
    _refreshToken = null;
    _userId = null;
    _accessExpiresAt = 0;
    _deviceId = const Uuid().v4();
    await storage.write(key: _deviceIdKey, value: _deviceId);
    try {
      await _anonymous();
    } catch (e, st) {
      PetloLogger.instance
          .w('forceReset re-anonymous failed', error: e, stackTrace: st);
    }
  }

  /// アカウント削除 (DELETE /auth/me)。
  /// 成功時は secure_storage を全クリア(deviceId 含めて)。
  Future<bool> deleteAccount() async {
    try {
      await ApiDio.instance.delete<dynamic>('/auth/me');
    } catch (e, st) {
      PetloLogger.instance
          .w('delete account API failed', error: e, stackTrace: st);
      // server 側削除に失敗してもローカル状態はクリアする
    }
    final FlutterSecureStorage storage = _storage();
    await storage.delete(key: SecureStorageKeys.apiAuthToken);
    await storage.delete(key: SecureStorageKeys.apiRefreshToken);
    await storage.delete(key: SecureStorageKeys.userId);
    await storage.delete(key: _deviceIdKey);
    // build 18: display_name もクリア
    await UserPreferences.instance.setDisplayName(null);
    _token = null;
    _refreshToken = null;
    _userId = null;
    _deviceId = null;
    _accessExpiresAt = 0;
    return true;
  }

  // ===========================================================================
  // 内部
  // ===========================================================================
  Future<void> _anonymous() async {
    if (_deviceId == null) {
      throw StateError('deviceId not set');
    }
    final Response<dynamic> resp = await ApiDio.raw.post<dynamic>(
      '/auth/anonymous',
      data: <String, dynamic>{
        'deviceId': _deviceId,
        'platform': _platformName(),
      },
    );
    final Map<String, dynamic> data = resp.data as Map<String, dynamic>;
    final String token = data['token'] as String;
    final String refreshToken = data['refreshToken'] as String;
    final String userId = data['userId'] as String;
    final int expiresAt = (data['expiresAt'] as num).toInt();
    await _persist(token: token, refreshToken: refreshToken, userId: userId);
    _accessExpiresAt = expiresAt;
    // build 49 (S1): userId は anonymous UUID だが、log に生で残すのは健全
    // ではないので先頭 8 文字だけ出す。デバッグでの相関は十分付けられる。
    final String masked = userId.length >= 8
        ? '${userId.substring(0, 8)}***'
        : '***';
    PetloLogger.instance.i('Anonymous auth ok: userId=$masked');
  }

  Future<void> _persist({
    required String token,
    required String refreshToken,
    required String userId,
  }) async {
    final FlutterSecureStorage storage = _storage();
    await storage.write(key: SecureStorageKeys.apiAuthToken, value: token);
    await storage.write(
      key: SecureStorageKeys.apiRefreshToken,
      value: refreshToken,
    );
    await storage.write(key: SecureStorageKeys.userId, value: userId);
    _token = token;
    _refreshToken = refreshToken;
    _userId = userId;
  }

  /// 5 分の余裕で期限切れ判定 (clock skew + refresh latency 対策)。
  bool _isTokenExpiringSoon() {
    if (_accessExpiresAt <= 0) return true;
    final int now = DateTime.now().millisecondsSinceEpoch;
    return _accessExpiresAt - now <= 5 * 60 * 1000;
  }

  /// JWT payload から exp (秒) を取り出して msec で返す。失敗時 0。
  int _parseExp(String? jwt) {
    if (jwt == null || jwt.isEmpty) return 0;
    final List<String> parts = jwt.split('.');
    if (parts.length != 3) return 0;
    try {
      final String normalized = base64Url.normalize(parts[1]);
      final String json = utf8.decode(base64Url.decode(normalized));
      final Map<String, dynamic> payload =
          jsonDecode(json) as Map<String, dynamic>;
      final num? exp = payload['exp'] as num?;
      if (exp == null) return 0;
      return (exp.toInt()) * 1000;
    } catch (_) {
      return 0;
    }
  }

  String _platformName() {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    // mobile target only, fallback to ios for unknown (シミュレータ等)
    return 'ios';
  }

  FlutterSecureStorage _storage() {
    // 直接 FlutterSecureStorage を生成 (Provider 経由でなく Service 内自前)。
    // iOS / Android のオプションは storage_providers.dart と同じ。
    return const FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock,
      ),
      aOptions: AndroidOptions(
        encryptedSharedPreferences: true,
      ),
    );
  }

  // 永続キー (secure_storage)
  static const String _deviceIdKey = 'auth_device_id';
}
