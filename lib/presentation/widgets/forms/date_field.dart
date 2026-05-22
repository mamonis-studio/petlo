// ============================================================================
// petlo - DateField
// ============================================================================
//
// 日付選択フィールド。タップで CupertinoDatePicker 風モーダル表示。
// (rev3 で誕生日や予定日に多用)
//
// 値:
//   - DateTime? (null = 未選択)
//   - 表示は yyyy/MM/dd (簡易、L10n は Chunk 15)
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../core/widgets/eyebrow_text.dart';

class DateField extends StatelessWidget {
  const DateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.required = false,
    this.errorText,
    this.placeholder = 'タップして選択',
    super.key,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool required;
  final String? errorText;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final bool hasError = errorText != null && errorText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            EyebrowText(label),
            if (required) ...<Widget>[
              const SizedBox(width: 4),
              Text(
                '*',
                style: TextStyle(
                  color: colors.accentDanger,
                  fontFamily: 'JetBrainsMono',
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppDimensions.gapSmall),

        InkWell(
          onTap: () => _openPicker(context),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: hasError ? colors.accentDanger : colors.line,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  value != null
                      ? formatFullDate(value!,
                          Localizations.localeOf(context).toLanguageTag())
                      : placeholder,
                  style: typo.bodyLarge.copyWith(
                    color: value != null ? colors.fg : colors.fgFaint,
                    fontFeatures: <FontFeature>[
                      const FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                Row(
                  children: <Widget>[
                    if (value != null) ...<Widget>[
                      GestureDetector(
                        onTap: () => onChanged(null),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            'CLEAR',
                            style: typo.metaSmall.copyWith(color: colors.fgMuted),
                          ),
                        ),
                      ),
                    ],
                    Icon(Icons.calendar_today_outlined,
                        size: 18, color: colors.fgMuted),
                  ],
                ),
              ],
            ),
          ),
        ),

        if (hasError) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            errorText!,
            style: typo.bodySmall.copyWith(color: colors.accentDanger),
          ),
        ],
      ],
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final DateTime now = DateTime.now();
    final DateTime initial = value ?? now;
    final DateTime first = firstDate ?? DateTime(now.year - 30);
    final DateTime last = lastDate ?? now;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first)
          ? first
          : (initial.isAfter(last) ? last : initial),
      firstDate: first,
      lastDate: last,
      builder: (BuildContext context, Widget? child) {
        // テーマを petlo 風に上書き
        final AppColors colors = AppColors.of(context);
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: colors.fg,
              onPrimary: colors.bg,
              surface: colors.bg,
              onSurface: colors.fg,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      onChanged(picked);
    }
  }

}
