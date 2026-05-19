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
//   - レシート検証 (POST /receipt/verify、petlo-api 経由で Apple 検証)
//   - 購入の復元 (端末買い替え時)
//
// 設計:
//   - シングルトンで全アプリ共有
//   - 状態は Stream で外部に公開、ProStatusProvider に橋渡しする
//   - 7日トライアルは StoreKit/Play Console 側で設定済みの前提
//
// レシート検証フロー (build 32 で本実装):
//   1. purchased / restored 受信
//   2. POST /receipt/verify { platform: 'ios', receipt: serverVerificationData }
//   3. verified=true → Pro 反映 + completePurchase
//   4. verified=false (apple_status_nonzero 等) → 拒否 + completePurchase
//      (receipt は確定的に無効、Apple に retry させない)
//   5. 502 / 503 / network → completePurchase **しない**
//      → Apple が次回起動時に purchaseStream 経由で再送 → 自動リトライ
//
// rev3: in_app_purchase 直接利用 (RevenueCat なし、mamonis.studio 標準)
//
// ============================================================================

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../auth/api_dio.dart';
import '../constants/app_constants.dart';
import '../utils/logger.dart';
import 'pro_status.dart';
import 'purchase_exceptions.dart';

/// 購入完了の結果 (サーバー検証 verified=true のみ emit される)
@immutable
class PurchaseSuccess {
  const PurchaseSuccess({
    required this.productId,
    required this.tier,
    required this.purchaseId,
    required this.expiresAt,
    this.environment,
  });

  final String productId;
  final ProTier tier;
  final String purchaseId;

  /// サーバー検証で確定した有効期限 (UTC msec)
  final DateTime expiresAt;

  /// 'Sandbox' or 'Production' (任意、ログ用)
  final String? environment;
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
        await _verifyAndApply(p);
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

  // ==========================================================================
  // build 32: レシート検証 (POST /receipt/verify)
  // ==========================================================================

  /// 購入完了 (purchased / restored) を server で検証し、
  /// 結果に応じて Pro 反映 / 拒否 / リトライ待機 を行う。
  Future<void> _verifyAndApply(PurchaseDetails p) async {
    final String receipt = p.verificationData.serverVerificationData;
    // ★形式確認用ログ: StoreKit 1 base64 receipt なら 'MII...' 等の長文字列、
    // StoreKit 2 JWS なら 'eyJ...' で始まる。本番ログでも一目で判別できるよう
    // 先頭 12 文字 + 長さを出す。
    final String head =
        receipt.length > 12 ? receipt.substring(0, 12) : receipt;
    PetloLogger.instance.d(
      'receipt verify: product=${p.productID}, '
      'len=${receipt.length}, head="$head..."',
    );

    if (receipt.isEmpty) {
      _onError.add(const ReceiptVerificationException(
          'レシートが空です'));
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
      return;
    }

    Response<dynamic> resp;
    try {
      resp = await ApiDio.instance.post<dynamic>(
        '/receipt/verify',
        data: <String, dynamic>{
          'platform': 'ios', // Android は将来 (501 で弾かれる)
          'receipt': receipt,
        },
      );
    } on DioException catch (e) {
      final int? status = e.response?.statusCode;
      // 502 (Apple 到達不可) / 503 (secret 未設定) / ネットワーク失敗
      // → completePurchase **しない** → Apple が次回起動で再送 → 自然リトライ
      if (status == 502 ||
          status == 503 ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.receiveTimeout) {
        PetloLogger.instance.w(
          'verify retryable failure: status=$status type=${e.type} '
          '— leaving transaction open for retry',
        );
        _onError.add(ReceiptVerificationException(
            status == 503
                ? '課金検証が一時的に利用できません'
                : 'ネットワークエラー: 次回起動時に再検証されます'));
        return; // completePurchase 呼ばない
      }
      if (status == 501) {
        PetloLogger.instance.w('verify 501: Android not supported yet');
        _onError.add(const ReceiptVerificationException(
            'Android の課金検証は近日対応予定です'));
        if (p.pendingCompletePurchase) {
          await _iap.completePurchase(p);
        }
        return;
      }
      // 400 / その他 → 確定エラー、completePurchase で transaction 終了
      PetloLogger.instance.w(
        'verify failed: status=$status msg=${e.message}',
      );
      _onError.add(ReceiptVerificationException(
          'レシート検証に失敗しました (HTTP $status)'));
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
      return;
    }

    // 2xx 応答 (verified true/false の判別は body 内)
    final dynamic body = resp.data;
    if (body is! Map<String, dynamic>) {
      _onError.add(const ReceiptVerificationException(
          'レシート検証のレスポンスが不正です'));
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
      return;
    }

    final bool verified = body['verified'] == true;
    if (!verified) {
      // 確定的に無効なレシート (apple_status_nonzero / no_matching_product /
      // subscription_expired) → completePurchase で Apple リトライを止める
      final String? reason = body['reason'] as String?;
      PetloLogger.instance.w(
        'verify rejected: reason=$reason appleStatus=${body['appleStatus']}',
      );
      _onError.add(ReceiptVerificationException(
          _reasonToUserMessage(reason)));
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
      return;
    }

    // verified=true: tier / expiresAt をサーバ値から確定して emit
    final ProTier tier = _tierFromString(body['tier'] as String?);
    final num? expMs = body['expiresAt'] as num?;
    if (tier == ProTier.free || expMs == null) {
      PetloLogger.instance.w(
        'verified=true だが tier/expiresAt が不正: tier=${body['tier']} exp=$expMs',
      );
      _onError.add(const ReceiptVerificationException(
          '課金情報の取得に失敗しました'));
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
      return;
    }

    _onPurchase.add(PurchaseSuccess(
      productId: (body['productId'] as String?) ?? p.productID,
      tier: tier,
      purchaseId: p.purchaseID ?? '',
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expMs.toInt()),
      environment: body['environment'] as String?,
    ));
    PetloLogger.instance.i(
      'verify ok: tier=${tier.name} env=${body['environment']} '
      'expiresAt=${DateTime.fromMillisecondsSinceEpoch(expMs.toInt())}',
    );

    if (p.pendingCompletePurchase) {
      await _iap.completePurchase(p);
    }
  }

  String _reasonToUserMessage(String? reason) {
    switch (reason) {
      case 'apple_status_nonzero':
        return 'Apple のレシート検証が失敗しました';
      case 'no_matching_product':
        return '購入された商品が確認できませんでした';
      case 'subscription_expired':
        return 'サブスクリプションの有効期限が切れています';
      default:
        return 'レシート検証に失敗しました';
    }
  }

  ProTier _tierFromString(String? s) {
    switch (s) {
      case 'monthly':
        return ProTier.monthly;
      case 'yearly':
        return ProTier.yearly;
      default:
        return ProTier.free;
    }
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
