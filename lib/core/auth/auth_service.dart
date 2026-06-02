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
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:uuid/uuid.dart';

import '../../presentation/providers/storage_providers.dart';
import '../preferences/user_preferences.dart';
import '../utils/logger.dart';
import 'api_dio.dart';
import 'auth_dio_interceptor.dart';

/// 認証・連携の現在状態。reactive provider 経由で UI が監視する。
///
/// - [anonymous]: 匿名 user (deviceId 紐付け、SIWA 未連携)
/// - [appleLinked]: Sign in with Apple で連携済み
///
/// 値の変化は AuthService の `authStatus` (ValueListenable) を通じて
/// 観測可能 (build 65 / T4)。
enum AuthStatus { anonymous, appleLinked }

/// Sign in with Apple 連携 (`/auth/link`) の呼び出し結果。
///
/// - [success]: 200 で連携成功
/// - [subAlreadyLinked]: 409 `sub_already_linked` — その Apple ID は
///   別のサーバユーザに既に紐付いている (ローカル状態は変更しない)
/// - [alreadyLinked]: 409 `already_linked` — この user は別の Apple アカウントに
///   紐付け済み。ローカル状態は変更しない。UI 側で
///   `auth_sign_in_error_already_linked` (別の Apple ID に連携済み) を
///   エラー表示する。
/// - [canceled]: ユーザーが Apple 認可シートを閉じた (エラー扱いしない)
/// - [failed]: identityToken 取得失敗 / その他の不明エラー / 想定外 HTTP ステータス
enum AppleSignInResult {
  success,
  subAlreadyLinked,
  alreadyLinked,
  canceled,
  failed,
}

/// `restoreWithApple()` (`POST /auth/apple`) の結果。
///
/// 元の anonymous user は破棄し、Apple ID と紐付いた server 上の既存ユーザに
/// 切り替える「フル sign-in」用なので、`subAlreadyLinked` / `alreadyLinked`
/// のような細かい意味分岐は持たない。
///
/// - [success]: 200、Bearer / userId を server 既存ユーザのものに切り替えた
/// - [canceled]: ユーザーが Apple 認可シートを閉じた
/// - [failed]: identityToken 取得失敗 / 400 / 401 / 500 / その他ネット例外
enum AppleRestoreResult { success, canceled, failed }

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
  // build 65: SIWA 連携済かどうかをメモリ上で保持。
  // initialize() 時に SecureStorage の appleUserIdentifier を見て初期化する。
  bool _appleLinked = false;

  // build 65 / T4: reactive UI のための status notifier。
  // initialize() / signInWithApple() success / deleteAccount() / forceReset()
  // で .value を書き換える。subAlreadyLinked / alreadyLinked / canceled /
  // failed の各分岐では値を変えない。
  final ValueNotifier<AuthStatus> _authStatusNotifier =
      ValueNotifier<AuthStatus>(AuthStatus.anonymous);

  /// public Dio (interceptor 装着済)
  Dio get dio => ApiDio.instance;

  String? get userId => _userId;
  String? get deviceId => _deviceId;
  bool get isAuthenticated => _token != null && _userId != null;
  bool get isLinkedWithApple => _appleLinked;

  /// 認証状態の変化を観測する Listenable。書き込み禁止 (内部だけが mutate)。
  ValueListenable<AuthStatus> get authStatus => _authStatusNotifier;

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

    // build 65: SIWA 連携状態の復元。Apple userIdentifier が Keychain に
    // 残っていれば連携済みとみなす。
    final String? appleUid =
        await storage.read(key: SecureStorageKeys.appleUserIdentifier);
    _appleLinked = appleUid != null && appleUid.isNotEmpty;
    // T4: notifier の初期値を確定。UI が watch しても整合した状態が見える。
    _authStatusNotifier.value =
        _appleLinked ? AuthStatus.appleLinked : AuthStatus.anonymous;

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
    // build 65: SIWA 連携状態もクリア (完全リセットなので残してはいけない)。
    await storage.delete(key: SecureStorageKeys.appleUserIdentifier);
    await storage.delete(key: _deviceIdKey);
    // build 18: display_name もリセット (新規ユーザー扱いなので)
    await UserPreferences.instance.setDisplayName(null);
    _token = null;
    _refreshToken = null;
    _userId = null;
    _accessExpiresAt = 0;
    _appleLinked = false;
    _authStatusNotifier.value = AuthStatus.anonymous;
    await _establishFreshAnonymous();
  }

  /// build 66 共通化: 「auth 情報ゼロ」の状態から新 deviceId + 新 anonymous
  /// user を立ち上げ直す。 secure_storage / メモリ状態が全クリアされている
  /// ことを前提とする。
  ///
  /// ネットワーク失敗時は warn ログだけ出して飲み込む (呼び出し側のセマンティクス
  /// を壊さない。次回 initialize() で `_token == null` を検出して再試行される)。
  Future<void> _establishFreshAnonymous() async {
    final FlutterSecureStorage storage = _storage();
    _deviceId = const Uuid().v4();
    try {
      await storage.write(key: _deviceIdKey, value: _deviceId);
    } catch (e, st) {
      PetloLogger.instance.w(
        'fresh anonymous: write deviceId failed',
        error: e,
        stackTrace: st,
      );
      // deviceId が secure_storage に残らなくてもメモリに乗っているので
      // この場の _anonymous() は試みる。次回起動時は再生成される。
    }
    try {
      await _anonymous();
    } catch (e, st) {
      PetloLogger.instance.w(
        'fresh anonymous registration failed',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// アカウント削除 (DELETE /auth/me)。
  ///
  /// build 65 (バグ修正): 「アカウント削除」のセマンティクスを満たすため、
  /// API 成功時はローカルデータも完全に消去する。
  /// build 66 (バグ修正): 削除後に新 anonymous user を立ち上げ直すよう変更。
  /// これで「削除直後の再サインイン」が `requireAuth` の 401 で詰まらなくなる。
  ///
  /// 順序 (各段で失敗したら以降をスキップする保護を入れる):
  ///   1. DELETE /auth/me — 失敗したらローカルは 1 バイトも変えず false 返却
  ///   2. drift DB を close ([closeDatabase] callback 経由で UI 層が
  ///      Provider invalidate と handle 解放を担当)
  ///   3. Documents/petlo.sqlite (+ wal / shm) を削除
  ///   4. Documents 配下の写真サブツリー (pets / meals / diaries / visits /
  ///      ai_diagnoses) を削除
  ///   5. secure_storage 全クリア (token / refreshToken / userId /
  ///      appleUserIdentifier / deviceId) + display_name + メモリ状態リセット
  ///   6. 新 deviceId 生成 + /auth/anonymous で新 anonymous user 確立
  ///      (ネットワーク失敗時は warn ログのみ、delete 自体は成功扱い)
  ///   7. true を返す
  ///
  /// 注意: drift DB は close 後にファイル削除する。close せずに sqlite を
  /// 削除すると iOS は inode を残したまま open file handle が使い続け、
  /// 次回 ref.read 時に drift が古い inode で書き込みを試みて整合が崩れる。
  /// 呼び出し側は `ref.read(appDatabaseProvider).close()` →
  /// `ref.invalidate(appDatabaseProvider)` を [closeDatabase] で行う想定。
  Future<bool> deleteAccount({
    required Future<void> Function() closeDatabase,
  }) async {
    // === Stage 1: server delete ===
    // 失敗時は「ローカル無傷で false 返却」のセマンティクスを守る。
    try {
      await ApiDio.instance.delete<dynamic>('/auth/me');
    } catch (e, st) {
      PetloLogger.instance
          .w('delete account API failed', error: e, stackTrace: st);
      return false;
    }

    // === Stage 2: close drift DB before file removal ===
    try {
      await closeDatabase();
    } catch (e, st) {
      PetloLogger.instance.w(
        'closeDatabase before wipe failed (continuing)',
        error: e,
        stackTrace: st,
      );
      // close 失敗でも削除は試みる。ファイル削除自体が成功すれば
      // 次回起動で drift がクリーンに DB を作り直す。
    }

    // === Stage 3 & 4: wipe local files ===
    await _wipeLocalDatabaseFiles();
    await _wipeLocalPhotoDirs();

    // === Stage 5: clear secure_storage + memory state ===
    final FlutterSecureStorage storage = _storage();
    await storage.delete(key: SecureStorageKeys.apiAuthToken);
    await storage.delete(key: SecureStorageKeys.apiRefreshToken);
    await storage.delete(key: SecureStorageKeys.userId);
    await storage.delete(key: SecureStorageKeys.appleUserIdentifier);
    await storage.delete(key: _deviceIdKey);
    await UserPreferences.instance.setDisplayName(null);
    _token = null;
    _refreshToken = null;
    _userId = null;
    _deviceId = null;
    _accessExpiresAt = 0;
    _appleLinked = false;
    _authStatusNotifier.value = AuthStatus.anonymous;

    // === Stage 6: establish fresh anonymous user (build 66) ===
    // 削除直後の「再サインイン」を可能にするため、新 deviceId で /auth/anonymous
    // を叩いて Bearer を持つ新規 user を確立する。失敗しても delete 自体は
    // 成功扱い (return true)、次回 initialize() で再試行される。
    await _establishFreshAnonymous();

    return true;
  }

  /// `petlo.sqlite` (+ WAL / SHM) を Documents から削除。
  /// drift が close されていることを前提とする。
  Future<void> _wipeLocalDatabaseFiles() async {
    try {
      final Directory docs = await getApplicationDocumentsDirectory();
      for (final String name in const <String>[
        'petlo.sqlite',
        'petlo.sqlite-wal',
        'petlo.sqlite-shm',
      ]) {
        final File f = File(p.join(docs.path, name));
        if (!await f.exists()) continue;
        try {
          await f.delete();
        } catch (e) {
          PetloLogger.instance.w('failed to delete $name: $e');
        }
      }
    } catch (e, st) {
      PetloLogger.instance
          .w('local DB wipe failed', error: e, stackTrace: st);
    }
  }

  /// Documents 配下の写真サブツリーを丸ごと削除。サブディレクトリ規則は
  /// `lib/data/storage/photo_storage.dart` と
  /// `lib/core/backup/backup_archive_service.dart` の `_photoSubdirs` と同期。
  Future<void> _wipeLocalPhotoDirs() async {
    try {
      final Directory docs = await getApplicationDocumentsDirectory();
      for (final String sub in const <String>[
        'pets',
        'meals',
        'diaries',
        'visits',
        'ai_diagnoses',
      ]) {
        final Directory d = Directory(p.join(docs.path, sub));
        if (!await d.exists()) continue;
        try {
          await d.delete(recursive: true);
        } catch (e) {
          PetloLogger.instance.w('failed to delete photo dir $sub: $e');
        }
      }
    } catch (e, st) {
      PetloLogger.instance
          .w('local photo wipe failed', error: e, stackTrace: st);
    }
  }

  /// build 65: Sign in with Apple で既存匿名アカウントを Apple ID と紐付ける。
  ///
  /// 既存 anonymous user (deviceId 紐付け) はそのまま、サーバ側で Apple
  /// credential を attach する。匿名のまま蓄積したペット・記録は失われない。
  ///
  /// 認証付き Dio (interceptor が Bearer 自動付与) で `POST /auth/link` を叩く。
  Future<AppleSignInResult> signInWithApple() async {
    final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: <AppleIDAuthorizationScopes>[
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        // ユーザーが認可シートを閉じた — エラー表示はしない。
        return AppleSignInResult.canceled;
      }
      PetloLogger.instance.w(
        'SIWA authorization failed code=${e.code} message=${e.message}',
      );
      return AppleSignInResult.failed;
    } catch (e, st) {
      PetloLogger.instance
          .w('SIWA credential request threw', error: e, stackTrace: st);
      return AppleSignInResult.failed;
    }

    final String? identityToken = credential.identityToken;
    if (identityToken == null || identityToken.isEmpty) {
      PetloLogger.instance.w('SIWA: identityToken null');
      return AppleSignInResult.failed;
    }

    // sign_in_with_apple 6.x の AuthorizationCredentialAppleID では
    // authorizationCode は non-nullable String。常に同梱する。
    final Map<String, dynamic> body = <String, dynamic>{
      'identityToken': identityToken,
      'authorizationCode': credential.authorizationCode,
    };

    try {
      final Response<dynamic> resp = await ApiDio.instance.post<dynamic>(
        '/auth/link',
        data: body,
      );
      if (resp.statusCode == 200) {
        final String? appleUid = credential.userIdentifier;
        if (appleUid != null && appleUid.isNotEmpty) {
          await _storage().write(
            key: SecureStorageKeys.appleUserIdentifier,
            value: appleUid,
          );
        }
        _appleLinked = true;
        // T4: success 時のみ reactive provider に通知。subAlreadyLinked /
        // alreadyLinked / canceled / failed では状態を変えない。
        _authStatusNotifier.value = AuthStatus.appleLinked;
        PetloLogger.instance.i('SIWA: linked successfully');
        return AppleSignInResult.success;
      }
      // 200 以外で例外でなかった = サーバ実装上の想定外応答。
      PetloLogger.instance
          .w('SIWA: link unexpected status ${resp.statusCode}');
      return AppleSignInResult.failed;
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        // 409 は body の error コードで意味が分かれる。
        final Object? data = e.response?.data;
        final String? errorCode =
            data is Map<String, dynamic> ? data['error'] as String? : null;
        switch (errorCode) {
          case 'sub_already_linked':
            // この Apple ID は別のサーバユーザに既に紐付いている。
            // ローカル状態は変更しない (連携扱いにしてはいけない)。
            PetloLogger.instance.w('SIWA: 409 sub_already_linked');
            return AppleSignInResult.subAlreadyLinked;
          case 'already_linked':
            // 自分のサーバアカウントは既に Apple と連携済み。
            // ローカル状態は触らない (Keychain も _appleLinked も既に
            // 正しい値が入っているはず。サーバとローカルがズレている
            // ケースは sign-out / アプリ再インストール側の責務で扱う)。
            PetloLogger.instance.i('SIWA: 409 already_linked');
            return AppleSignInResult.alreadyLinked;
          default:
            PetloLogger.instance.w(
              'SIWA: 409 with unknown error code: $errorCode',
            );
            return AppleSignInResult.failed;
        }
      }
      PetloLogger.instance.w(
        'SIWA: link failed status=${e.response?.statusCode} '
        'data=${e.response?.data}',
      );
      return AppleSignInResult.failed;
    } catch (e, st) {
      PetloLogger.instance
          .w('SIWA: link threw', error: e, stackTrace: st);
      return AppleSignInResult.failed;
    }
  }

  /// build 69: Apple ID で「フル sign-in」する。 `signInWithApple()` が link
  /// 用 (既存 anonymous user に attach) なのに対し、これは server に既に存在
  /// する Apple-linked user の **Bearer に切り替える** ためのもの。機種変・
  /// 新端末の入り口で使う。
  ///
  /// 認証付き Dio (`ApiDio.instance`) ではなく **interceptor 無しの
  /// [ApiDio.raw] で叩く** — 現匿名ユーザの Bearer を /auth/apple に渡しても
  /// 意味がなく (server は Apple credential だけで識別する)、また 401 で
  /// 既存 token の自動 refresh が誤発火するのを避けるため。
  Future<AppleRestoreResult> restoreWithApple() async {
    final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: <AppleIDAuthorizationScopes>[
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return AppleRestoreResult.canceled;
      }
      PetloLogger.instance.w(
        'Apple restore: authorization failed code=${e.code} '
        'message=${e.message}',
      );
      return AppleRestoreResult.failed;
    } catch (e, st) {
      PetloLogger.instance.w(
        'Apple restore: credential request threw',
        error: e,
        stackTrace: st,
      );
      return AppleRestoreResult.failed;
    }

    final String? identityToken = credential.identityToken;
    if (identityToken == null || identityToken.isEmpty) {
      PetloLogger.instance.w('Apple restore: identityToken null');
      return AppleRestoreResult.failed;
    }

    try {
      final Response<dynamic> resp = await ApiDio.raw.post<dynamic>(
        '/auth/apple',
        data: <String, dynamic>{
          'identityToken': identityToken,
          'authorizationCode': credential.authorizationCode,
          'platform': _platformName(),
        },
      );
      if (resp.statusCode != 200) {
        PetloLogger.instance
            .w('Apple restore: unexpected status ${resp.statusCode}');
        return AppleRestoreResult.failed;
      }
      final Map<String, dynamic> data = resp.data as Map<String, dynamic>;
      final String token = data['token'] as String;
      final String refreshToken = data['refreshToken'] as String;
      final String userId = data['userId'] as String;
      final int expiresAt = (data['expiresAt'] as num).toInt();
      // 既存 anonymous user の secure_storage 値を上書きして Bearer を切り替え。
      // /backup などの認証必須エンドポイントは次の呼び出しから新 token になる。
      await _persist(
        token: token,
        refreshToken: refreshToken,
        userId: userId,
      );
      _accessExpiresAt = expiresAt;
      // Apple userIdentifier も保存して、再起動後の連携状態を維持する。
      final String? appleUid = credential.userIdentifier;
      if (appleUid != null && appleUid.isNotEmpty) {
        await _storage().write(
          key: SecureStorageKeys.appleUserIdentifier,
          value: appleUid,
        );
      }
      _appleLinked = true;
      _authStatusNotifier.value = AuthStatus.appleLinked;
      final String masked = userId.length >= 8
          ? '${userId.substring(0, 8)}***'
          : '***';
      PetloLogger.instance.i('Apple restore: switched to userId=$masked');
      return AppleRestoreResult.success;
    } on DioException catch (e) {
      PetloLogger.instance.w(
        'Apple restore: /auth/apple failed '
        'status=${e.response?.statusCode} data=${e.response?.data}',
      );
      return AppleRestoreResult.failed;
    } catch (e, st) {
      PetloLogger.instance
          .w('Apple restore: threw', error: e, stackTrace: st);
      return AppleRestoreResult.failed;
    }
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
