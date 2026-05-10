// ============================================================================
// petlo - RecordAmountSelector
// ============================================================================
//
// 量の3段階セレクター。うんち/おしっこ/嘔吐で共通。
//
// 3段階 (RecordAmount enum):
//   little  少なめ
//   normal  普通
//   alot    多め
//
// SegmentedSelector<RecordAmount> をラップした使いやすい版。
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../../data/local/database_enums.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../forms/segmented_selector.dart';

class RecordAmountSelector extends StatelessWidget {
  const RecordAmountSelector({
    required this.value,
    required this.onChanged,
    this.label,
    this.required = false,
    this.errorText,
    super.key,
  });

  final RecordAmount? value;
  final ValueChanged<RecordAmount> onChanged;
  final String? label;
  final bool required;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return SegmentedSelector<RecordAmount>(
      label: label ?? l10n.record_field_amount,
      options: RecordAmount.values,
      value: value,
      required: required,
      errorText: errorText,
      optionLabel: (RecordAmount a) => switch (a) {
        RecordAmount.little => l10n.record_amount_little,
        RecordAmount.normal => l10n.record_amount_normal,
        RecordAmount.alot => l10n.record_amount_alot,
      },
      onChanged: onChanged,
    );
  }
}
