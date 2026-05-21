// ============================================================================
// petlo - Form Validators
// ============================================================================
//
// フォーム入力のバリデーションロジックを集約。
//
// 設計:
//   - 各バリデータは String? を受け取り、エラー文字列 (null = OK) を返す
//   - エラー文字列は L10n キー化済 (build 34)。
//     呼び出し側が AppLocalizations を渡し、各 helper が l10n キーから
//     デフォルトメッセージを構築する。
//   - 個別カスタムメッセージは引数 `message` で上書き可能。
//   - 複数バリデータの合成: Validators.compose([...])
//
// ============================================================================

import '../../../l10n/generated/app_localizations.dart';

typedef Validator = String? Function(String? value);

abstract final class Validators {
  Validators._();

  /// 必須入力
  static Validator required(AppLocalizations l10n, {String? message}) {
    final String msg = message ?? l10n.validator_required;
    return (String? v) {
      if (v == null || v.trim().isEmpty) return msg;
      return null;
    };
  }

  /// 最小文字数
  static Validator minLength(AppLocalizations l10n, int min,
      {String? message}) {
    final String msg = message ?? l10n.validator_min_length(min);
    return (String? v) {
      if (v == null || v.length < min) return msg;
      return null;
    };
  }

  /// 最大文字数
  static Validator maxLength(AppLocalizations l10n, int max,
      {String? message}) {
    final String msg = message ?? l10n.validator_max_length(max);
    return (String? v) {
      if (v != null && v.length > max) return msg;
      return null;
    };
  }

  /// 数値変換可能か (省略可)
  static Validator numericOrEmpty(AppLocalizations l10n, {String? message}) {
    final String msg = message ?? l10n.validator_numeric;
    return (String? v) {
      if (v == null || v.isEmpty) return null;
      if (num.tryParse(v) == null) return msg;
      return null;
    };
  }

  /// 整数のみ
  static Validator integerOrEmpty(AppLocalizations l10n, {String? message}) {
    final String msg = message ?? l10n.validator_integer;
    return (String? v) {
      if (v == null || v.isEmpty) return null;
      if (int.tryParse(v) == null) return msg;
      return null;
    };
  }

  /// 範囲チェック (数値、minとmax込みで境界含む)
  static Validator numberRange(
    AppLocalizations l10n, {
    required num min,
    required num max,
    String? message,
  }) {
    final String rangeMsg =
        message ?? l10n.validator_number_range(min.toString(), max.toString());
    final String numericMsg = l10n.validator_numeric;
    return (String? v) {
      if (v == null || v.isEmpty) return null;
      final num? n = num.tryParse(v);
      if (n == null) return numericMsg;
      if (n < min || n > max) return rangeMsg;
      return null;
    };
  }

  /// 電話番号(緩い、数字+ハイフンのみ)
  static Validator phoneNumberOrEmpty(AppLocalizations l10n,
      {String? message}) {
    final String msg = message ?? l10n.validator_phone;
    return (String? v) {
      if (v == null || v.isEmpty) return null;
      // 数字、+ - スペース、() のみ許可、最低7桁
      final RegExp r = RegExp(r'^[+\d\s\-()]{7,20}$');
      if (!r.hasMatch(v)) return msg;
      return null;
    };
  }

  /// 複数バリデータを合成。最初に失敗したものを返す。
  static Validator compose(List<Validator> validators) {
    return (String? v) {
      for (final Validator validator in validators) {
        final String? err = validator(v);
        if (err != null) return err;
      }
      return null;
    };
  }
}
