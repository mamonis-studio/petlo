// ============================================================================
// petlo - Purchase Provider
// ============================================================================
//
// PurchaseService の Provider + 購入成功時に ProStatusProvider を更新する
// リスナー。
//
// ============================================================================

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/billing/pro_status.dart';
import '../../core/billing/purchase_exceptions.dart';
import '../../core/billing/purchase_service.dart';
import '../../core/utils/logger.dart';
import 'pro_status_provider.dart';

// ============================================================================
// Service
// ============================================================================
final Provider<PurchaseService> purchaseServiceProvider =
    Provider<PurchaseService>((Ref ref) => PurchaseService.instance);

// ============================================================================
// Streams (UI で listen して SnackBar / トースト出すために露出)
// ============================================================================
final StreamProvider<PurchaseSuccess> purchaseSuccessStreamProvider =
    StreamProvider<PurchaseSuccess>(
  (Ref ref) => ref.watch(purchaseServiceProvider).purchases,
);

final StreamProvider<PurchaseException> purchaseErrorStreamProvider =
    StreamProvider<PurchaseException>(
  (Ref ref) => ref.watch(purchaseServiceProvider).errors,
);

// ============================================================================
// 起動時のリスナー設定
// ============================================================================
//
// PurchaseService の `purchases` Stream を listen して、
// 成功時に ProStatusProvider に反映する。
//
// main.dart の PetloApp.initState で 1度だけ初期化される。
//
class PurchaseListener {
  PurchaseListener(this._ref);
  final Ref _ref;

  StreamSubscription<PurchaseSuccess>? _sub;

  void start() {
    final PurchaseService service = _ref.read(purchaseServiceProvider);
    _sub = service.purchases.listen(_onPurchase);
  }

  Future<void> _onPurchase(PurchaseSuccess success) async {
    PetloLogger.instance
        .i('Purchase success: ${success.productId} (${success.tier.name})');

    // 期限の暫定計算 (サーバー検証実装までのプレースホルダ):
    //   月額: +30日、年額: +365日
    // 実運用ではAppStore receipt の expires_date を使う
    final DateTime expires = switch (success.tier) {
      ProTier.monthly => DateTime.now().add(const Duration(days: 30)),
      ProTier.yearly => DateTime.now().add(const Duration(days: 365)),
      ProTier.free => DateTime.now(),
    };

    final ProStatus next = ProStatus(
      tier: success.tier,
      state: ProState.active,
      expiresAt: expires,
    );
    await _ref.read(proStatusProvider.notifier).updateStatus(next);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
  }
}

final Provider<PurchaseListener> purchaseListenerProvider =
    Provider<PurchaseListener>((Ref ref) {
  final PurchaseListener listener = PurchaseListener(ref);
  ref.onDispose(() => listener.dispose());
  return listener;
});
