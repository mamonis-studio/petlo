// ============================================================================
// petlo - Purchase Exceptions
// ============================================================================
//
// PurchaseService が投げるエラー型。
//
// build 35: エラーコード enum 化 (H2 対応)。
//   - `code` (PurchaseErrorCode) が UI 表示の正、l10n キーマッピングの起点
//   - `message` は **英語フォールバック / ログ用途のみ** で UI 表示禁止。
//     UI は必ず purchaseErrorMessage(e, l10n) ヘルパー経由で訳す
//   - 例外サブクラスは catch 時の粒度切替 (`on PurchaseCancelledException`)
//     のために維持。各サブクラスは固有 code を super に渡す
//   - レシート検証系 (`ReceiptVerificationException`) は code を引数で受ける
//
// ============================================================================

enum PurchaseErrorCode {
  // ストア / 商品取得
  storeUnavailable,
  productNotFound,
  cannotBuyFreeTier,

  // 購入フロー
  purchaseCancelled,
  purchasePending,
  purchaseStartFailed,
  purchaseFailed,

  // 復元
  nothingToRestore,

  // レシート検証 (build 32 で本実装)
  receiptEmpty,
  receiptRetryableNetwork, // 502 / connection / timeout
  receiptRetryableServer, // 503 (secret 未設定)
  receiptAndroidNotSupported, // 501
  receiptHttpError, // 400 / その他
  receiptInvalidResponse, // 2xx だが body 不正
  receiptRejectedAppleStatus, // reason=apple_status_nonzero
  receiptRejectedNoMatchingProduct, // reason=no_matching_product
  receiptRejectedSubscriptionExpired, // reason=subscription_expired
  receiptRejectedUnknown, // verified=false で reason が想定外
  receiptInvalidTierOrExpiry, // verified=true だが tier/expiresAt 不正

  unknown,
}

sealed class PurchaseException implements Exception {
  const PurchaseException(this.code, {this.message});

  /// 唯一の真の識別子。UI はこれを見て l10n キーへ写像する。
  final PurchaseErrorCode code;

  /// 英語フォールバック / ログ用途のみ。UI 表示禁止 (代わりに
  /// purchaseErrorMessage(this, l10n) を使う)。
  final String? message;

  @override
  String toString() => 'PurchaseException(code=$code, msg=$message)';
}

/// ストアが利用できない (シミュレータ等)
class StoreUnavailableException extends PurchaseException {
  const StoreUnavailableException()
      : super(PurchaseErrorCode.storeUnavailable);
}

/// 商品情報が取得できない (商品IDが見つからない、ストア接続不能)
class ProductNotFoundException extends PurchaseException {
  const ProductNotFoundException(String productId)
      : super(PurchaseErrorCode.productNotFound, message: productId);
}

/// ユーザーが購入をキャンセル
class PurchaseCancelledException extends PurchaseException {
  const PurchaseCancelledException()
      : super(PurchaseErrorCode.purchaseCancelled);
}

/// 親の許可待ち (Ask to Buy 等)
class PurchasePendingException extends PurchaseException {
  const PurchasePendingException()
      : super(PurchaseErrorCode.purchasePending);
}

/// 購入処理エラー (ネットワーク、決済失敗等)。code で具体的理由を識別する。
class PurchaseFailedException extends PurchaseException {
  const PurchaseFailedException(PurchaseErrorCode code, {String? message})
      : super(code, message: message);
}

/// レシート検証失敗。code で具体的理由を識別する。
class ReceiptVerificationException extends PurchaseException {
  const ReceiptVerificationException(
    PurchaseErrorCode code, {
    String? message,
  }) : super(code, message: message);
}

/// 復元する購入が見つからない
class NothingToRestoreException extends PurchaseException {
  const NothingToRestoreException()
      : super(PurchaseErrorCode.nothingToRestore);
}

/// 想定外
class PurchaseUnknownException extends PurchaseException {
  const PurchaseUnknownException({String? message})
      : super(PurchaseErrorCode.unknown, message: message);
}
