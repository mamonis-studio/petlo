// ============================================================================
// petlo - Bootstrap Status Provider (build 55-client)
// ============================================================================
//
// アプリ起動シーケンス中の状態を一元的に表すフラグ。
// 主な利用ケース:
//   - 認証直後の SyncService.fullPull が走っている間、UI にローディング
//     表示を出す
//   - 初回起動 / 復元時のみ true。通常のセッション復帰では touch しない
//
// 設計:
//   - main.dart の _PetloAppState._bootstrapSync が fullPull 起動時に
//     true をセットし、完了 (成功・失敗問わず) で false を戻す
//   - UI 側 (PetloApp の MaterialApp.builder) はこの値を watch して
//     splash overlay の出し入れを行う
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 「fullPull / 初期同期」が走っている間 true。
/// それ以外(通常起動・通常同期中)は false。
final NotifierProvider<BootstrapStatusNotifier, bool>
    bootstrapStatusProvider =
    NotifierProvider<BootstrapStatusNotifier, bool>(
  BootstrapStatusNotifier.new,
);

class BootstrapStatusNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void begin() => state = true;
  void end() => state = false;
}
