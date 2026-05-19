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
// 設計:
//   - グループ作成・参加・設定画面いずれもまずローカルキャッシュを見て
//     プリフィル、submit 時に PATCH /me + setDisplayName を行う。
//   - 通信失敗時はローカルキャッシュを真実として継続、エラーを上位に
//     伝播しない (UI を遅延させない / オフライン継続)。
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
      // ネットワーク失敗等は想定内、ローカルキャッシュ継続
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
  /// 戻り値: サーバ更新成功なら true、通信失敗等で false。
  /// ローカルキャッシュは常に先書きするので、戻り値が false でも UI には反映される。
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
