// ============================================================================
// petlo - DateTimePickerRow
// ============================================================================
//
// 「日付」+「時刻」を横並びで入力する共通部品。
// 食事/うんち/おしっこ/嘔吐/体重 すべての記録画面で使用。
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../forms/date_field.dart';

class DateTimePickerRow extends StatelessWidget {
  const DateTimePickerRow({
    required this.value,
    required this.onChanged,
    this.dateLabel,
    this.timeLabel,
    this.errorText,
    this.firstDate,
    this.lastDate,
    super.key,
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String? dateLabel;
  final String? timeLabel;
  final String? errorText;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool hasError = errorText != null && errorText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              flex: 3,
              child: DateField(
                label: dateLabel ?? l10n.record_field_date,
                value: value,
                firstDate: firstDate ?? DateTime(DateTime.now().year - 1),
                lastDate: lastDate ?? DateTime.now(),
                onChanged: (DateTime? picked) {
                  if (picked == null) {
                    onChanged(null);
                  } else {
                    final DateTime t = value ?? DateTime.now();
                    onChanged(DateTime(picked.year, picked.month, picked.day,
                        t.hour, t.minute));
                  }
                },
              ),
            ),
            const SizedBox(width: AppDimensions.gapMedium),
            Expanded(
              flex: 2,
              child: _TimeField(
                label: timeLabel ?? l10n.common_time,
                value: value,
                onChanged: (TimeOfDay? t) {
                  if (t == null) return;
                  final DateTime base = value ?? DateTime.now();
                  onChanged(DateTime(base.year, base.month, base.day,
                      t.hour, t.minute));
                },
              ),
            ),
          ],
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
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<TimeOfDay?> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final TimeOfDay? tod = value == null
        ? null
        : TimeOfDay(hour: value!.hour, minute: value!.minute);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        EyebrowText(label),
        const SizedBox(height: AppDimensions.gapSmall),
        InkWell(
          onTap: () async {
            final TimeOfDay? picked = await showTimePicker(
              context: context,
              initialTime: tod ?? TimeOfDay.now(),
              builder: (BuildContext c, Widget? child) {
                return Theme(
                  data: Theme.of(c).copyWith(
                    colorScheme: ColorScheme.light(
                      primary: AppColors.of(c).fg,
                      onPrimary: AppColors.of(c).bg,
                      surface: AppColors.of(c).bg,
                      onSurface: AppColors.of(c).fg,
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (picked != null) onChanged(picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.line)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  tod == null
                      ? AppLocalizations.of(context).record_field_tap_to_select
                      : tod.format(context),
                  style: typo.bodyLarge.copyWith(
                    color: tod == null ? colors.fgFaint : colors.fg,
                    fontFeatures: <FontFeature>[
                      const FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                Icon(Icons.access_time, size: 18, color: colors.fgMuted),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
