// ============================================================================
// petlo - Paywall Controller
// ============================================================================
//
// Paywall 画面の状態とアクション。
//
// 状態:
//   - selectedTier: 現在選択中の tier (デフォルトは年額: 一番得)
//   - isProcessing: 購入処理中
//   - errorMessage: 直近のエラー
//
// アクション:
//   - selectTier(tier) — 選択切替
//   - purchase() — 購入開始 → PurchaseService に委譲
//   - restore() — 購入の復元
//
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/billing/pro_status.dart';
import '../../../core/billing/purchase_exceptions.dart';
import '../../../core/billing/purchase_service.dart';
import '../../../core/utils/logger.dart';
import '../../providers/purchase_provider.dart';

@immutable
class PaywallState {
  const PaywallState({
    this.selectedTier = ProTier.yearly,
    this.isProcessing = false,
    this.errorMessage,
  });

  /// 現在の選択(月額/年額)。free は不可。
  final ProTier selectedTier;
  final bool isProcessing;
  final String? errorMessage;

  PaywallState copyWith({
    ProTier? selectedTier,
    bool? isProcessing,
    Object? errorMessage = _sentinel,
  }) {
    return PaywallState(
      selectedTier: selectedTier ?? this.selectedTier,
      isProcessing: isProcessing ?? this.isProcessing,
      errorMessage: errorMessage == _sentinel
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  static const Object _sentinel = Object();
}

final NotifierProvider<PaywallController, PaywallState>
    paywallControllerProvider =
    NotifierProvider<PaywallController, PaywallState>(
  PaywallController.new,
);

class PaywallController extends Notifier<PaywallState> {
  @override
  PaywallState build() {
    return const PaywallState();
  }

  void selectTier(ProTier tier) {
    if (tier == ProTier.free) return;
    state = state.copyWith(
      selectedTier: tier,
      errorMessage: null,
    );
  }

  /// 購入を開始する。成功/失敗は PurchaseService の Stream 経由で
  /// PurchaseListener が ProStatus を更新する。
  /// このメソッドは「購入トリガーが投げられたか」だけを返す。
  Future<void> purchase() async {
    if (state.isProcessing) return;

    state = state.copyWith(isProcessing: true, errorMessage: null);

    try {
      final PurchaseService service = ref.read(purchaseServiceProvider);
      await service.buy(state.selectedTier);
      // 成功時は purchaseStream に流れて isProcessing を別途 false にする
      // (画面からは purchaseSuccessStreamProvider を listen して pop)
    } on PurchaseException catch (e) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: e.message,
      );
    } catch (e, st) {
      PetloLogger.instance
          .w('Paywall purchase unexpected', error: e, stackTrace: st);
      // build 33: errorMessage は UI で表示してないので null。
      // ユーザー向け通知は purchaseErrorStreamProvider 経由 (PurchaseException
      // 由来) で行う。ここでの予期しない catch はログのみ。
      state = state.copyWith(
        isProcessing: false,
        errorMessage: null,
      );
    }
  }

  /// 購入完了通知を受け取った時に呼ぶ(画面から listen 経由で)
  void markCompleted() {
    state = state.copyWith(isProcessing: false, errorMessage: null);
  }

  /// 購入の復元
  Future<bool> restore() async {
    if (state.isProcessing) return false;
    state = state.copyWith(isProcessing: true, errorMessage: null);
    try {
      final PurchaseService service = ref.read(purchaseServiceProvider);
      await service.restore();
      // 成功 / 失敗は purchaseStream / errorStream で通知される
      return true;
    } on PurchaseException catch (e) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: e.message,
      );
      return false;
    } catch (e, st) {
      PetloLogger.instance
          .w('Paywall restore unexpected', error: e, stackTrace: st);
      // build 33: errorMessage は UI で表示してないので null。
      // ユーザー向け通知は purchaseErrorStreamProvider 経由 (PurchaseException
      // 由来) で行う。ここでの予期しない catch はログのみ。
      state = state.copyWith(
        isProcessing: false,
        errorMessage: null,
      );
      return false;
    }
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }
}
