// ============================================================================
// petlo - EditorialTextField
// ============================================================================
//
// petloのエディトリアルトーンに合わせたテキスト入力。
//
// 特徴:
//   - ラベルは上部に小さく eyebrow スタイル
//   - 下線一本のみ (枠線なし)
//   - フォーカス時は下線が太く+黒に
//   - エラー時は赤下線 + エラーテキスト下に
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';

class EditorialTextField extends StatefulWidget {
  const EditorialTextField({
    required this.label,
    this.controller,
    this.initialValue,
    this.hint,
    this.helperText,
    this.errorText,
    this.keyboardType = TextInputType.text,
    this.textCapitalization = TextCapitalization.none,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.obscureText = false,
    this.autofocus = false,
    this.enabled = true,
    this.required = false,
    this.suffixText,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  /// ラベル(常時表示、eyebrowスタイル)
  final String label;

  /// テキストコントローラ (initialValue と排他)
  final TextEditingController? controller;

  /// 初期値 (controller 使ってない時)
  final String? initialValue;

  final String? hint;
  final String? helperText;
  final String? errorText;
  final TextInputType keyboardType;
  final TextCapitalization textCapitalization;
  final int? maxLength;
  final int maxLines;
  final int? minLines;
  final bool obscureText;
  final bool autofocus;
  final bool enabled;

  /// trueなら "*" を label の右に表示
  final bool required;

  /// 入力欄の右端にサフィックステキスト (例: "kg", "℃", "g")
  final String? suffixText;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<EditorialTextField> createState() => _EditorialTextFieldState();
}

class _EditorialTextFieldState extends State<EditorialTextField> {
  late final FocusNode _focusNode;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() => _hasFocus = _focusNode.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final bool hasError = widget.errorText != null && widget.errorText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Label
        Row(
          children: <Widget>[
            EyebrowText(widget.label),
            if (widget.required) ...<Widget>[
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

        // TextField
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          enabled: widget.enabled,
          obscureText: widget.obscureText,
          keyboardType: widget.keyboardType,
          textCapitalization: widget.textCapitalization,
          maxLength: widget.maxLength,
          maxLines: widget.maxLines,
          minLines: widget.minLines,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          style: typo.bodyLarge.copyWith(
            color: widget.enabled ? colors.fg : colors.fgFaint,
          ),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: typo.bodyLarge.copyWith(color: colors.fgFaint),
            suffixText: widget.suffixText,
            suffixStyle: typo.bodySmall.copyWith(color: colors.fgMuted),
            counterText: '',
            border: _underline(colors.line),
            enabledBorder: _underline(hasError ? colors.accentDanger : colors.line),
            focusedBorder: _underline(
              hasError ? colors.accentDanger : colors.fg,
              width: 2,
            ),
            disabledBorder: _underline(colors.line),
            errorBorder: _underline(colors.accentDanger),
            focusedErrorBorder: _underline(colors.accentDanger, width: 2),
            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
            isDense: true,
          ),
        ),

        // Helper / Error text
        if (hasError) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            widget.errorText!,
            style: typo.bodySmall.copyWith(color: colors.accentDanger),
          ),
        ] else if (widget.helperText != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            widget.helperText!,
            style: typo.bodySmall.copyWith(color: colors.fgMuted),
          ),
        ],

        // 文字数カウンター(maxLength設定時のみ + フォーカス中のみ)
        if (widget.maxLength != null && _hasFocus)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${(widget.controller?.text ?? widget.initialValue ?? '').length} / ${widget.maxLength}',
                style: typo.metaSmall,
              ),
            ),
          ),
      ],
    );
  }

  UnderlineInputBorder _underline(Color color, {double width = 1}) {
    return UnderlineInputBorder(
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
