// ============================================================================
// petlo - Auth Provider
// ============================================================================
//
// AuthService.instance を Riverpod 経由で参照可能にする。
//
// 設計:
//   - main.dart で AuthService.instance.initialize() を runApp 前に await
//   - 各画面 / repository は ref.read(authServiceProvider) で取得
//   - userId / isAuthenticated はリアクティブには変えず、初期化時の値で固定
//     (ログアウト → 再起動 で更新する v1.0 設計)
//   - build 65 / T4 で SIWA 用に AuthStatus の reactive provider を追加。
//     こちらは AuthService の ValueListenable<AuthStatus> を watch し、
//     signInWithApple() success / deleteAccount() / forceReset() の瞬間に
//     UI が追従するようにする。
//
// ============================================================================

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_service.dart';

final Provider<AuthService> authServiceProvider = Provider<AuthService>(
  (Ref ref) => AuthService.instance,
);

final Provider<String?> currentApiUserIdProvider = Provider<String?>(
  (Ref ref) => ref.watch(authServiceProvider).userId,
);

final Provider<bool> isAuthenticatedProvider = Provider<bool>(
  (Ref ref) => ref.watch(authServiceProvider).isAuthenticated,
);

// ============================================================================
// build 65 / T4: AuthStatus reactive provider
// ============================================================================
//
// AuthService.instance.authStatus (ValueListenable<AuthStatus>) を Riverpod の
// Notifier でラップし、UI が `ref.watch(authStatusProvider)` で監視できる
// ようにする。NotifierProvider を選んだのは proStatusProvider /
// backupSettingsProvider と同じ既存パターンに馴染ませるため。
//
// ライフサイクル:
//   - build() 時に AuthService の Listenable に listener を addListener
//   - ref.onDispose で removeListener (Provider 破棄時にリーク防止)
//   - listenable.value 変化のたびに `state = listenable.value` で再 emit
//
// ============================================================================

class AuthStatusNotifier extends Notifier<AuthStatus> {
  @override
  AuthStatus build() {
    final ValueListenable<AuthStatus> listenable =
        ref.watch(authServiceProvider).authStatus;
    void listener() {
      state = listenable.value;
    }
    listenable.addListener(listener);
    ref.onDispose(() => listenable.removeListener(listener));
    return listenable.value;
  }
}

final NotifierProvider<AuthStatusNotifier, AuthStatus> authStatusProvider =
    NotifierProvider<AuthStatusNotifier, AuthStatus>(
  AuthStatusNotifier.new,
);
