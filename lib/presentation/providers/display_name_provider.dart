// ============================================================================
// petlo - Display Name Provider (build 18)
// ============================================================================
//
// 家族共有メンバーとして表示される名前のローカル状態。
// SharedPreferences に永続化、PATCH /me で backend にも同期。
//
// nullable: null = まだ未設定 (グループ作成・参加時に初めて要求される)。
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/user_profile_service.dart';
import '../../core/preferences/user_preferences.dart';

final NotifierProvider<DisplayNameNotifier, String?> displayNameProvider =
    NotifierProvider<DisplayNameNotifier, String?>(DisplayNameNotifier.new);

class DisplayNameNotifier extends Notifier<String?> {
  @override
  String? build() {
    return UserPreferences.instance.displayName;
  }

  /// PATCH /me + ローカルキャッシュ更新。
  /// backend 未デプロイ環境ではローカルだけ更新。
  Future<bool> save(String name) async {
    final bool ok = await UserProfileService.instance.updateDisplayName(name);
    // updateDisplayName は内部で UserPreferences を先に書く
    state = UserPreferences.instance.displayName;
    return ok;
  }

  /// ローカルキャッシュのみ更新 (グループ作成・参加の submit から呼ぶ
  /// fast path、サーバ送信は ownerDisplayName / displayName 付きの
  /// 既存 POST に乗るのでここでは PATCH しない)。
  Future<void> setLocal(String name) async {
    await UserPreferences.instance.setDisplayName(name);
    state = UserPreferences.instance.displayName;
  }
}
