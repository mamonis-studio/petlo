// ============================================================================
// petlo - Pro Status Provider
// ============================================================================
//
// Pro 契約状態のリアクティブ管理。
//
// 起動時は UserPreferences から復元、購入/解約時は updateStatus() で更新。
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/billing/pro_status.dart';
import '../../core/preferences/user_preferences.dart';

final NotifierProvider<ProStatusNotifier, ProStatus> proStatusProvider =
    NotifierProvider<ProStatusNotifier, ProStatus>(
  ProStatusNotifier.new,
);

class ProStatusNotifier extends Notifier<ProStatus> {
  @override
  ProStatus build() {
    return UserPreferences.instance.proStatus;
  }

  Future<void> updateStatus(ProStatus status) async {
    state = status;
    await UserPreferences.instance.setProStatus(status);
  }

  Future<void> clear() async {
    state = ProStatus.free;
    await UserPreferences.instance.clearProStatus();
  }
}

// ============================================================================
// 便利な派生Provider
// ============================================================================

/// Pro機能が利用可能か (active / grace / cancelled の有効期限内)
final Provider<bool> isProProvider = Provider<bool>(
  (Ref ref) => ref.watch(proStatusProvider).isPro,
);

/// トライアル期間中か
final Provider<bool> isInTrialProvider = Provider<bool>(
  (Ref ref) => ref.watch(proStatusProvider).isInTrial,
);
