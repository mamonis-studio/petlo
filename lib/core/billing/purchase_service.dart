// ============================================================================
// petlo - Purchase Service
// ============================================================================
//
// in_app_purchase ラッパー。
//
// 役割:
//   - 起動時の初期化 + 商品情報取得 (¥480月 / ¥3,800年 をストアから引く)
//   - 購入フロー (StoreKit/Play Store のシステムUIに委譲)
//   - 購入完了通知の受信 (purchaseStream で iOS/Android 共通)
//   - レシート検証 (Cloudflare Workers /api/billing/verify は将来 Chunk)
//   - 購入の復元 (端末買い替え時)
//
// 設計:
//   - シングルトンで全アプリ共有
//   - 状態は Stream で外部に公開、ProStatusProvider に橋渡しする
//   - 7日トライアルは StoreKit/Play Console 側で設定済みの前提
//
// rev3: in_app_purchase 直接利用 (RevenueCat なし、mamonis.studio 標準)
//
// ============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../constants/app_constants.dart';
import '../utils/logger.dart';
import 'pro_status.dart';
import 'purchase_exceptions.dart';

/// 購入完了の結果
@immutable
class PurchaseSuccess {
  const PurchaseSuccess({
    required this.productId,
    required this.tier,
    required this.purchaseId,
    this.serverVerificationData,
  });

  final String productId;
  final ProTier tier;
  final String purchaseId;

  /// レシート検証用データ (将来 Workers に送る)
  final String? serverVerificationData;
}

class PurchaseService {
  PurchaseService._();
  static final PurchaseService instance = PurchaseService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  // 商品情報のキャッシュ
  final Map<String, ProductDetails> _products = <String, ProductDetails>{};

  bool _initialized = false;
  bool _storeAvailable = false;

  // 外部に状態を流す
  final StreamController<PurchaseSuccess> _onPurchase =
      StreamController<PurchaseSuccess>.broadcast();
  final StreamController<PurchaseException> _onError =
      StreamController<PurchaseException>.broadcast();

  /// 購入成功イベント (UI / ProStatusProvider が listen)
  Stream<PurchaseSuccess> get purchases => _onPurchase.stream;

  /// 購入エラーイベント
  Stream<PurchaseException> get errors => _onError.stream;

  /// 商品情報 (取得済みなら同期で返す)
  ProductDetails? productFor(String productId) => _products[productId];

  /// ストアが利用可能か
  bool get isStoreAvailable => _storeAvailable;

  // ==========================================================================
  // 初期化
  // ==========================================================================

  /// アプリ起動時に1度だけ呼ぶ。
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      _storeAvailable = await _iap.isAvailable();
      if (!_storeAvailable) {
        PetloLogger.instance.i('Store unavailable (simulator?)');
        _initialized = true;
        return;
      }

      // 購入ストリームを購読
      _purchaseSub = _iap.purchaseStream.listen(
        _handlePurchaseUpdates,
        onError: (Object e, StackTrace st) {
          PetloLogger.instance
              .w('purchaseStream error', error: e, stackTrace: st);
        },
      );

      // 商品情報を取得
      await _loadProducts();

      _initialized = true;
      PetloLogger.instance.i(
          'PurchaseService initialized (products=${_products.length})');
    } catch (e, st) {
      PetloLogger.instance
          .w('PurchaseService init failed', error: e, stackTrace: st);
    }
  }

  Future<void> _loadProducts() async {
    final Set<String> ids = <String>{
      AppConstants.iapMonthlyProductId,
      AppConstants.iapYearlyProductId,
    };

    final ProductDetailsResponse resp = await _iap.queryProductDetails(ids);
    if (resp.error != null) {
      PetloLogger.instance.w('queryProductDetails error: ${resp.error}');
    }
    if (resp.notFoundIDs.isNotEmpty) {
      PetloLogger.instance.w('Products not found: ${resp.notFoundIDs}');
    }
    for (final ProductDetails p in resp.productDetails) {
      _products[p.id] = p;
    }
  }

  /// 起動後の再ロード (App Store Connect で商品が後から有効化された場合等)
  Future<void> reloadProducts() async {
    if (!_storeAvailable) return;
    await _loadProducts();
  }

  // ==========================================================================
  // 購入
  // ==========================================================================

  /// 月額/年額の購入を開始する。
  /// 成功すると `purchases` ストリームに [PurchaseSuccess] が流れる。
  Future<void> buy(ProTier tier) async {
    if (!_storeAvailable) {
      throw const StoreUnavailableException();
    }
    final String productId = switch (tier) {
      ProTier.monthly => AppConstants.iapMonthlyProductId,
      ProTier.yearly => AppConstants.iapYearlyProductId,
      ProTier.free => throw const PurchaseUnknownException(
          'Cannot buy free tier'),
    };

    final ProductDetails? product = _products[productId];
    if (product == null) {
      throw ProductNotFoundException(productId);
    }

    final PurchaseParam param = PurchaseParam(productDetails: product);

    try {
      // サブスクは buyNonConsumable
      final bool started =
          await _iap.buyNonConsumable(purchaseParam: param);
      if (!started) {
        throw const PurchaseFailedException('購入を開始できませんでした');
      }
    } catch (e, st) {
      PetloLogger.instance
          .w('buy failed: $productId', error: e, stackTrace: st);
      if (e is PurchaseException) rethrow;
      throw PurchaseUnknownException(e.toString());
    }
  }

  /// 購入の復元 (端末買い替え時)
  Future<void> restore() async {
    if (!_storeAvailable) {
      throw const StoreUnavailableException();
    }
    try {
      await _iap.restorePurchases();
      // 結果は _handlePurchaseUpdates に流れてくる
    } catch (e, st) {
      PetloLogger.instance
          .w('restore failed', error: e, stackTrace: st);
      throw PurchaseUnknownException(e.toString());
    }
  }

  // ==========================================================================
  // 購入更新ハンドラ
  // ==========================================================================

  Future<void> _handlePurchaseUpdates(
      List<PurchaseDetails> purchases) async {
    for (final PurchaseDetails p in purchases) {
      try {
        await _handleSingle(p);
      } catch (e, st) {
        PetloLogger.instance.w(
            'handlePurchase failed: ${p.productID}',
            error: e,
            stackTrace: st);
      }
    }
  }

  Future<void> _handleSingle(PurchaseDetails p) async {
    PetloLogger.instance.d(
        'PurchaseUpdate: ${p.productID} status=${p.status} pending=${p.pendingCompletePurchase}');

    switch (p.status) {
      case PurchaseStatus.pending:
        // UI 側でローディング表示中。何もしない
        break;

      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        // レシート検証 (将来 Workers に送る、今はクライアント側で受け入れ)
        // TODO(billing): /api/billing/verify エンドポイントが実装されたら
        //   ここで dio.post() してサーバー側検証
        final ProTier tier = _tierFromProductId(p.productID);
        if (tier == ProTier.free) {
          PetloLogger.instance
              .w('Unknown product purchased: ${p.productID}');
        } else {
          _onPurchase.add(PurchaseSuccess(
            productId: p.productID,
            tier: tier,
            purchaseId: p.purchaseID ?? '',
            serverVerificationData:
                p.verificationData.serverVerificationData,
          ));
        }

        // トランザクション完了 (これを呼ばないと StoreKit が再送し続ける)
        if (p.pendingCompletePurchase) {
          await _iap.completePurchase(p);
        }
        break;

      case PurchaseStatus.error:
        final IAPError? err = p.error;
        PetloLogger.instance
            .w('Purchase error: ${err?.code} / ${err?.message}');
        _onError.add(PurchaseFailedException(
            err?.message ?? '購入処理に失敗しました'));
        if (p.pendingCompletePurchase) {
          await _iap.completePurchase(p);
        }
        break;

      case PurchaseStatus.canceled:
        _onError.add(const PurchaseCancelledException());
        if (p.pendingCompletePurchase) {
          await _iap.completePurchase(p);
        }
        break;
    }
  }

  ProTier _tierFromProductId(String productId) {
    if (productId == AppConstants.iapMonthlyProductId) {
      return ProTier.monthly;
    }
    if (productId == AppConstants.iapYearlyProductId) {
      return ProTier.yearly;
    }
    return ProTier.free;
  }

  // ==========================================================================
  // クリーンアップ
  // ==========================================================================
  Future<void> dispose() async {
    await _purchaseSub?.cancel();
    await _onPurchase.close();
    await _onError.close();
  }
}
