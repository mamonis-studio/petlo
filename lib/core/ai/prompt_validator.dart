// ============================================================================
// petlo - Prompt Validator
// ============================================================================
//
// AIへの送信前に必ず通すバリデーション。
// rev5.5 F-23a: プロンプトインジェクション対策。
//
// 検証項目:
//   1. 文字数 500文字以内 (HARD LIMIT、超えたら即拒否)
//   2. 危険キーワード検知 (英日両対応、よく使われるバイパス試行を弾く)
//   3. XML タグらしき注入を弾く (例: </user_question>...で会話の流れを破壊)
//
// 検出時はサーバーには送らず、クライアント側で「再入力してください」を表示。
//
// build 37 (M4): 拒否文言の l10n 化。`PromptValidationError` は `reason` のみ
// 保持し、UI 側は `promptValidationErrorMessage(reason, l10n)` で訳す。
// 危険キーワード検出パターン (`_dangerousKeywords`) は文言ではなく検出ロジック
// なので英日リテラルのまま保持。
//
// ============================================================================

/// 入力の許容文字数 (rev5.5 ハードリミット)
const int kMaxPromptLength = 500;

/// 危険キーワードのリスト(英日)
/// LLM へのバイパス指示でよく使われる典型パターン。
const List<String> _dangerousKeywords = <String>[
  // 英語: 標準的な jailbreak
  'ignore previous instructions',
  'ignore the above',
  'ignore all previous',
  'disregard previous',
  'forget the above',
  'forget previous',
  'system:',
  'system prompt',
  'you are now',
  'pretend to be',
  'pretend you are',
  'act as',
  'roleplay as',
  'reveal your prompt',
  'show your prompt',
  'reveal system prompt',
  'reveal instructions',
  // 日本語: よくある翻訳パターン
  '前の指示を無視',
  '上記を無視',
  '今までの指示',
  'あなたは今から',
  'あなたは今後',
  'システムプロンプト',
  'システムメッセージ',
  '指示を忘れ',
  '本来のあなた',
  'ロールプレイ',
];

/// XMLタグらしきパターン (送信時にXMLでラップするので、ユーザーがタグ injection してきたら拒否)
final RegExp _xmlTagPattern = RegExp(r'<\s*/?\s*[a-z_][a-z0-9_]*\s*>',
    caseSensitive: false);

/// バリデーションの結果
sealed class PromptValidationResult {
  const PromptValidationResult();
}

class PromptValidationOk extends PromptValidationResult {
  const PromptValidationOk(this.sanitized);
  final String sanitized;
}

class PromptValidationError extends PromptValidationResult {
  const PromptValidationError(this.reason);

  final PromptValidationErrorReason reason;
}

enum PromptValidationErrorReason {
  empty,
  tooLong,
  dangerousKeyword,
  xmlInjection,
}

/// プロンプトのバリデータ
abstract final class PromptValidator {
  /// メイン検証。OK の場合は sanitize 済みの文字列を返す。
  static PromptValidationResult validate(String input) {
    final String trimmed = input.trim();

    if (trimmed.isEmpty) {
      return const PromptValidationError(PromptValidationErrorReason.empty);
    }

    if (trimmed.length > kMaxPromptLength) {
      return const PromptValidationError(PromptValidationErrorReason.tooLong);
    }

    // 危険キーワード(大文字小文字無視)
    final String lower = trimmed.toLowerCase();
    for (final String kw in _dangerousKeywords) {
      if (lower.contains(kw.toLowerCase())) {
        return const PromptValidationError(
          PromptValidationErrorReason.dangerousKeyword,
        );
      }
    }

    // XMLタグ injection
    if (_xmlTagPattern.hasMatch(trimmed)) {
      return const PromptValidationError(
        PromptValidationErrorReason.xmlInjection,
      );
    }

    return PromptValidationOk(trimmed);
  }
}

// ============================================================================
// 文字数情報(UI のカウンター用)
// ============================================================================
class PromptLengthInfo {
  PromptLengthInfo(String input)
      : current = input.runes.length,
        max = kMaxPromptLength;

  final int current;
  final int max;

  bool get isOver => current > max;
  bool get isNearLimit => current >= (max - 50) && current <= max;
  int get remaining => max - current;
}
