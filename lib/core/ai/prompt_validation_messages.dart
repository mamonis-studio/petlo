// ============================================================================
// petlo - Prompt Validation Messages (UI helper)
// ============================================================================
//
// PromptValidationErrorReason → 多言語化された UI 表示文字列への写像。
// build 37 (M4): バリデータ自体を reason のみ返す設計に変更したので、UI 側で
// この helper 経由でメッセージを取得する。
//
// switch は exhaustive (default 無し) — 新 reason を追加した瞬間に analyzer が
// 未網羅を指摘する。
//
// ============================================================================

import '../../l10n/generated/app_localizations.dart';
import 'prompt_validator.dart';

String promptValidationErrorMessage(
  PromptValidationErrorReason reason,
  AppLocalizations l10n,
) {
  switch (reason) {
    case PromptValidationErrorReason.empty:
      return l10n.prompt_validation_empty;
    case PromptValidationErrorReason.tooLong:
      return l10n.prompt_validation_too_long(kMaxPromptLength);
    case PromptValidationErrorReason.dangerousKeyword:
      return l10n.prompt_validation_dangerous_keyword;
    case PromptValidationErrorReason.xmlInjection:
      return l10n.prompt_validation_xml_injection;
  }
}
