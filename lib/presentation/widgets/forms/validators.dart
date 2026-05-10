// ============================================================================
// petlo - Form Validators
// ============================================================================
//
// フォーム入力のバリデーションロジックを集約。
//
// 設計:
//   - 各バリデータは String? を受け取り、エラー文字列 (null = OK) を返す
//   - エラー文字列は L10n キー化したいが、Chunk 15 までは日本語ハードコード
//   - 複数バリデータの合成: Validators.compose([...])
//
// ============================================================================

typedef Validator = String? Function(String? value);

abstract final class Validators {
  Validators._();

  /// 必須入力
  static Validator required({String message = 'この項目は必須です'}) {
    return (String? v) {
      if (v == null || v.trim().isEmpty) return message;
      return null;
    };
  }

  /// 最小文字数
  static Validator minLength(int min, {String? message}) {
    return (String? v) {
      if (v == null || v.length < min) {
        return message ?? '$min文字以上で入力してください';
      }
      return null;
    };
  }

  /// 最大文字数
  static Validator maxLength(int max, {String? message}) {
    return (String? v) {
      if (v != null && v.length > max) {
        return message ?? '$max文字以内で入力してください';
      }
      return null;
    };
  }

  /// 数値変換可能か (省略可)
  static Validator numericOrEmpty({String message = '数値を入力してください'}) {
    return (String? v) {
      if (v == null || v.isEmpty) return null;
      if (num.tryParse(v) == null) return message;
      return null;
    };
  }

  /// 整数のみ
  static Validator integerOrEmpty({String message = '整数で入力してください'}) {
    return (String? v) {
      if (v == null || v.isEmpty) return null;
      if (int.tryParse(v) == null) return message;
      return null;
    };
  }

  /// 範囲チェック (数値、minとmax込みで境界含む)
  static Validator numberRange({
    required num min,
    required num max,
    String? message,
  }) {
    return (String? v) {
      if (v == null || v.isEmpty) return null;
      final num? n = num.tryParse(v);
      if (n == null) return '数値を入力してください';
      if (n < min || n > max) {
        return message ?? '$min〜$max の範囲で入力してください';
      }
      return null;
    };
  }

  /// 電話番号(緩い、数字+ハイフンのみ)
  static Validator phoneNumberOrEmpty(
      {String message = '電話番号の形式が正しくありません'}) {
    return (String? v) {
      if (v == null || v.isEmpty) return null;
      // 数字、+ - スペース、() のみ許可、最低7桁
      final RegExp r = RegExp(r'^[+\d\s\-()]{7,20}$');
      if (!r.hasMatch(v)) return message;
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
