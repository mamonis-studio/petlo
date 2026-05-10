// ============================================================================
// petlo - TemperatureInputField
// ============================================================================
//
// 体温入力フィールド。℃ / ℉ の単位切替トグル付き。
// 値は小数1桁で扱う。
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/unit_converters.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../data/local/database_enums.dart';

class TemperatureInputField extends StatefulWidget {
  const TemperatureInputField({
    required this.tempCelsiusX10,
    required this.unit,
    required this.onTemperatureChanged,
    required this.onUnitChanged,
    this.petType,
    this.label = 'Temperature',
    this.required = false,
    this.errorText,
    super.key,
  });

  final int? tempCelsiusX10;
  final TemperatureUnit unit;
  final ValueChanged<int?> onTemperatureChanged;
  final ValueChanged<TemperatureUnit> onUnitChanged;

  /// あれば正常範囲のヒントを下に表示
  final PetType? petType;

  final String label;
  final bool required;
  final String? errorText;

  @override
  State<TemperatureInputField> createState() => _TemperatureInputFieldState();
}

class _TemperatureInputFieldState extends State<TemperatureInputField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _displayText());
  }

  @override
  void didUpdateWidget(TemperatureInputField old) {
    super.didUpdateWidget(old);
    if (old.unit != widget.unit) {
      _controller.text = _displayText();
    } else if (old.tempCelsiusX10 != widget.tempCelsiusX10 &&
        _controller.text.isEmpty) {
      _controller.text = _displayText();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _displayText() {
    if (widget.tempCelsiusX10 == null) return '';
    return TemperatureConverter.formatX10(
      tempCelsiusX10: widget.tempCelsiusX10!,
      unit: widget.unit,
    );
  }

  String _normalRangeHint() {
    if (widget.petType == null) return '';
    final (int min, int max) = widget.petType == PetType.dog
        ? (375, 390)
        : (380, 395);
    final String minStr = TemperatureConverter.formatX10(
      tempCelsiusX10: min,
      unit: widget.unit,
    );
    final String maxStr = TemperatureConverter.formatX10(
      tempCelsiusX10: max,
      unit: widget.unit,
    );
    final String label = TemperatureConverter.label(widget.unit);
    final String petLabel =
        widget.petType == PetType.dog ? 'dog' : 'cat';
    return 'Normal range for $petLabel: $minStr–$maxStr$label';
  }

  Color? _statusColor() {
    if (widget.tempCelsiusX10 == null || widget.petType == null) return null;
    final status = TemperatureConverter.statusFor(
      tempCelsiusX10: widget.tempCelsiusX10!,
      petType: widget.petType!,
    );
    return switch (status) {
      TemperatureStatus.normal => null,
      TemperatureStatus.cautionLow ||
      TemperatureStatus.cautionHigh =>
        AppColors.of(context).accentWarn,
      TemperatureStatus.urgentLow ||
      TemperatureStatus.urgentHigh =>
        AppColors.of(context).accentDanger,
    };
  }

  String _statusLabel() {
    if (widget.tempCelsiusX10 == null || widget.petType == null) return '';
    final status = TemperatureConverter.statusFor(
      tempCelsiusX10: widget.tempCelsiusX10!,
      petType: widget.petType!,
    );
    return switch (status) {
      TemperatureStatus.normal => '',
      TemperatureStatus.cautionLow => 'Slightly low',
      TemperatureStatus.cautionHigh => 'Slightly high',
      TemperatureStatus.urgentLow => 'Hypothermia — see a vet',
      TemperatureStatus.urgentHigh => 'Fever — see a vet',
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final bool hasError = widget.errorText != null && widget.errorText!.isNotEmpty;
    final Color? statusColor = _statusColor();
    final String statusLabel = _statusLabel();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            EyebrowText(widget.label),
            if (widget.required) ...<Widget>[
              const SizedBox(width: 4),
              Text('*',
                  style: TextStyle(
                    color: colors.accentDanger,
                    fontFamily: 'JetBrainsMono',
                    fontSize: 10,
                  )),
            ],
            const Spacer(),
            _UnitToggle(
              currentUnit: widget.unit,
              onChanged: widget.onUnitChanged,
            ),
          ],
        ),
        const SizedBox(height: AppDimensions.gapSmall),

        TextField(
          controller: _controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          style: TextStyle(
            fontFamily: 'Fraunces',
            fontStyle: FontStyle.italic,
            fontSize: 32,
            height: 1.0,
            color: statusColor ?? colors.fg,
            fontFeatures: <FontFeature>[
              const FontFeature.tabularFigures(),
            ],
          ),
          decoration: InputDecoration(
            hintText: '0.0',
            hintStyle: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 32,
              color: colors.fgFaint,
            ),
            suffixText: TemperatureConverter.label(widget.unit),
            suffixStyle: typo.bodyMedium.copyWith(color: colors.fgMuted),
            border: _underline(hasError ? colors.accentDanger : colors.line),
            enabledBorder: _underline(
                hasError ? colors.accentDanger : (statusColor ?? colors.line)),
            focusedBorder: _underline(
              hasError ? colors.accentDanger : (statusColor ?? colors.fg),
              width: 2,
            ),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
            isDense: true,
          ),
          onChanged: (String v) {
            final int? c = TemperatureConverter.parseToCelsiusX10(
                input: v, unit: widget.unit);
            widget.onTemperatureChanged(c);
          },
        ),

        // ステータスラベル(異常値時のみ)
        if (statusLabel.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            statusLabel.toUpperCase(),
            style: typo.metaSmall.copyWith(color: statusColor),
          ),
        ],

        // 正常範囲のヒント (helperText 兼)
        if (widget.petType != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            _normalRangeHint(),
            style: typo.bodySmall.copyWith(color: colors.fgMuted),
          ),
        ],

        if (hasError) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            widget.errorText!,
            style: typo.bodySmall.copyWith(color: colors.accentDanger),
          ),
        ],
      ],
    );
  }

  UnderlineInputBorder _underline(Color color, {double width = 1}) {
    return UnderlineInputBorder(
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

class _UnitToggle extends StatelessWidget {
  const _UnitToggle({
    required this.currentUnit,
    required this.onChanged,
  });

  final TemperatureUnit currentUnit;
  final ValueChanged<TemperatureUnit> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Row(
      children: <Widget>[
        for (final TemperatureUnit u in TemperatureUnit.values)
          InkWell(
            onTap: () => onChanged(u),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: currentUnit == u ? colors.fg : colors.bg,
                border: Border.all(color: colors.fg, width: 1),
              ),
              child: Text(
                TemperatureConverter.label(u),
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 9,
                  letterSpacing: 9 * 0.15,
                  fontWeight: FontWeight.w500,
                  color: currentUnit == u ? colors.bg : colors.fg,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
