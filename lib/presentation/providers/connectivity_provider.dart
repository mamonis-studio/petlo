// ============================================================================
// petlo - Connectivity Provider
// ============================================================================
//
// rev5.5 §4.13 に基づく、オンライン/オフライン状態の監視。
//
// 用途:
//   - オフライン時のAI相談ボタン薄化 (rev5.5 F-23c)
//   - 同期キューのpushタイミング判定
//   - 「オフラインです」スナックバー表示
//
// 設計:
//   - Stream を Riverpod の StreamProvider でラップ
//   - 値は bool (isOnline) — シンプル化
//   - WiFi/モバイル/ethernet のいずれか有 → online
//
// ============================================================================

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// connectivity_plus のインスタンス
final Provider<Connectivity> connectivityProvider = Provider<Connectivity>(
  (Ref ref) => Connectivity(),
);

/// 接続状態の Stream Provider。
///
/// 初期値はチェックされるまで loading、それ以降は true/false。
/// UI側は `.maybeWhen(data: ..., orElse: () => true)` で
/// 不明時は楽観的にonline扱いするのが推奨。
final StreamProvider<bool> isOnlineProvider = StreamProvider<bool>(
  (Ref ref) async* {
    final Connectivity connectivity = ref.watch(connectivityProvider);

    // 初期値を1回チェック
    final List<ConnectivityResult> initial = await connectivity.checkConnectivity();
    yield _hasConnection(initial);

    // 以降は変化を監視
    yield* connectivity.onConnectivityChanged.map(_hasConnection);
  },
);

/// 同期処理から見た「現在オンラインか?」を bool で取得する便利Provider。
/// 不明時は true (楽観的) を返す。
final Provider<bool> isOnlineSnapshotProvider = Provider<bool>(
  (Ref ref) {
    final AsyncValue<bool> async = ref.watch(isOnlineProvider);
    return async.maybeWhen(
      data: (bool isOnline) => isOnline,
      orElse: () => true,
    );
  },
);

bool _hasConnection(List<ConnectivityResult> results) {
  // none 以外が1つでもあれば接続あり
  return results.any((ConnectivityResult r) => r != ConnectivityResult.none);
}
