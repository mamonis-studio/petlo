// ============================================================================
// petlo - Purchase Error Messages (UI helper)
// ============================================================================
//
// PurchaseException → 多言語化された UI 表示文字列への写像。
// UI 側 (Controller / Screen) は必ずこのヘルパー経由でメッセージを取得する。
// 例外側の `message` フィールドはログ用途のみ。
//
// build 35: H2 対応で導入。switch は exhaustive (default 無し) なので
// PurchaseErrorCode に追加した瞬間に未網羅を analyzer が指摘する。
//
// ============================================================================

import '../../l10n/generated/app_localizations.dart';
import 'purchase_exceptions.dart';

String purchaseErrorMessage(PurchaseException e, AppLocalizations l10n) {
  return _messageForCode(e.code, l10n);
}

String _messageForCode(PurchaseErrorCode code, AppLocalizations l10n) {
  switch (code) {
    case PurchaseErrorCode.storeUnavailable:
      return l10n.purchase_error_storeUnavailable;
    case PurchaseErrorCode.productNotFound:
      return l10n.purchase_error_productNotFound;
    case PurchaseErrorCode.cannotBuyFreeTier:
      return l10n.purchase_error_cannotBuyFreeTier;
    case PurchaseErrorCode.purchaseCancelled:
      return l10n.purchase_error_purchaseCancelled;
    case PurchaseErrorCode.purchasePending:
      return l10n.purchase_error_purchasePending;
    case PurchaseErrorCode.purchaseStartFailed:
      return l10n.purchase_error_purchaseStartFailed;
    case PurchaseErrorCode.purchaseFailed:
      return l10n.purchase_error_purchaseFailed;
    case PurchaseErrorCode.nothingToRestore:
      return l10n.purchase_error_nothingToRestore;
    case PurchaseErrorCode.receiptEmpty:
      return l10n.purchase_error_receiptEmpty;
    case PurchaseErrorCode.receiptRetryableNetwork:
      return l10n.purchase_error_receiptRetryableNetwork;
    case PurchaseErrorCode.receiptRetryableServer:
      return l10n.purchase_error_receiptRetryableServer;
    case PurchaseErrorCode.receiptAndroidNotSupported:
      return l10n.purchase_error_receiptAndroidNotSupported;
    case PurchaseErrorCode.receiptHttpError:
      return l10n.purchase_error_receiptHttpError;
    case PurchaseErrorCode.receiptInvalidResponse:
      return l10n.purchase_error_receiptInvalidResponse;
    case PurchaseErrorCode.receiptRejectedAppleStatus:
      return l10n.purchase_error_receiptRejectedAppleStatus;
    case PurchaseErrorCode.receiptRejectedNoMatchingProduct:
      return l10n.purchase_error_receiptRejectedNoMatchingProduct;
    case PurchaseErrorCode.receiptRejectedSubscriptionExpired:
      return l10n.purchase_error_receiptRejectedSubscriptionExpired;
    case PurchaseErrorCode.receiptRejectedUnknown:
      return l10n.purchase_error_receiptRejectedUnknown;
    case PurchaseErrorCode.receiptInvalidTierOrExpiry:
      return l10n.purchase_error_receiptInvalidTierOrExpiry;
    case PurchaseErrorCode.unknown:
      return l10n.purchase_error_unknown;
  }
}
