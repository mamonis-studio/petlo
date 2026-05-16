// ============================================================================
// petlo - User Profile Service (build 18)
// ============================================================================
//
// petlo-api `/me` への薄いラッパー。
//   GET   /me                     → display_name 等のプロフィール取得
//   PATCH /me   {displayName}     → display_name 更新
//
// ローカルキャッシュ (UserPreferences.displayName) と同期する。
//
// 注意:
//   - backend は別途実装中。未デプロイ環境では 404 が返るが、その場合は
//     既存のローカルキャッシュを真実として継続。エラーを上位に伝播しない。
//   - グループ作成・参加・設定画面いずれもまずローカルキャッシュを見て
//     プリフィル、submit 時に PATCH /me + setDisplayName を行う設計。
//
// ============================================================================

import 'package:dio/dio.dart';

import '../preferences/user_preferences.dart';
import '../utils/logger.dart';
import 'api_dio.dart';

class UserProfileService {
  UserProfileService._();
  static final UserProfileService instance = UserProfileService._();

  /// 起動時に呼ぶ fire-and-forget な同期。
  /// 失敗してもアプリ続行に影響しない。
  Future<void> syncFromServer() async {
    try {
      final Response<dynamic> resp =
          await ApiDio.instance.get<dynamic>('/me');
      final dynamic body = resp.data;
      if (body is! Map<String, dynamic>) return;
      // 期待: { displayName: string|null, ... }
      // snake_case が来た場合の保険も入れておく。
      final dynamic raw = body['displayName'] ?? body['display_name'];
      if (raw is String && raw.trim().isNotEmpty) {
        await UserPreferences.instance.setDisplayName(raw);
      }
      // サーバが null を返したらローカルキャッシュは触らない
      // (端末側で先に決めて未同期の可能性があるため)。
    } on DioException catch (e) {
      // 404 (endpoint 未デプロイ) は想定内、その他もログのみ
      PetloLogger.instance.d(
        'UserProfileService.syncFromServer skipped: '
        'status=${e.response?.statusCode}',
      );
    } catch (e, st) {
      PetloLogger.instance
          .d('UserProfileService.syncFromServer error: $e', stackTrace: st);
    }
  }

  /// PATCH /me で display_name を更新し、ローカルキャッシュも更新する。
  /// サーバ側 endpoint 未実装 (404) でもローカルは更新する。
  /// 戻り値: 通信成功時 true / 失敗 (ネットワーク等) でも local 更新は成功なら true
  Future<bool> updateDisplayName(String name) async {
    final String trimmed = name.trim();
    // ローカルキャッシュを先に書く (オフラインでも UI が反映される)
    await UserPreferences.instance.setDisplayName(trimmed);
    try {
      await ApiDio.instance.patch<dynamic>(
        '/me',
        data: <String, dynamic>{'displayName': trimmed},
      );
      return true;
    } on DioException catch (e) {
      final int? status = e.response?.statusCode;
      // 404 は endpoint 未実装、ローカル保存だけで成功扱い
      if (status == 404) {
        PetloLogger.instance
            .d('PATCH /me 404 (endpoint not deployed yet) — local only');
        return true;
      }
      PetloLogger.instance.w(
        'PATCH /me failed: status=$status, msg=${e.message}',
      );
      return false;
    } catch (e, st) {
      PetloLogger.instance
          .w('PATCH /me unexpected', error: e, stackTrace: st);
      return false;
    }
  }
}
