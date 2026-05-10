// ============================================================================
// petlo - Purchase Exceptions
// ============================================================================
//
// PurchaseService が投げるエラー型。
// UI 側で適切な対応を取れるよう sealed class で網羅する。
//
// ============================================================================

sealed class PurchaseException implements Exception {
  const PurchaseException(this.message);
  final String message;

  @override
  String toString() => 'PurchaseException: $message';
}

/// ストアが利用できない (シミュレータ等)
class StoreUnavailableException extends PurchaseException {
  const StoreUnavailableException()
      : super('App Store / Play Store が利用できません');
}

/// 商品情報が取得できない (商品IDが見つからない、ストア接続不能)
class ProductNotFoundException extends PurchaseException {
  const ProductNotFoundException(String productId)
      : super('商品が見つかりません: $productId');
}

/// ユーザーが購入をキャンセル
class PurchaseCancelledException extends PurchaseException {
  const PurchaseCancelledException()
      : super('購入がキャンセルされました');
}

/// 親の許可待ち (Ask to Buy 等)
class PurchasePendingException extends PurchaseException {
  const PurchasePendingException()
      : super('購入が承認待ちです');
}

/// 購入処理エラー (ネットワーク、決済失敗等)
class PurchaseFailedException extends PurchaseException {
  const PurchaseFailedException(super.message);
}

/// レシート検証失敗
class ReceiptVerificationException extends PurchaseException {
  const ReceiptVerificationException(super.message);
}

/// 復元する購入が見つからない
class NothingToRestoreException extends PurchaseException {
  const NothingToRestoreException()
      : super('復元する購入が見つかりませんでした');
}

/// 想定外
class PurchaseUnknownException extends PurchaseException {
  const PurchaseUnknownException(super.message);
}
