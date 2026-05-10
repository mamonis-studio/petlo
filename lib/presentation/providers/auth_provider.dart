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
//
// ============================================================================

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
