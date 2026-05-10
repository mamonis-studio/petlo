// ============================================================================
// petlo - VomitColorSelector (rev5.5 2階層色)
// ============================================================================
//
// rev5.5 §4.x: 嘔吐の色は2階層構造で選択。
//
//   階層1 (メイン4色、よくあるもの):
//     - clear     透明・水様
//     - yellow    黄色 (胃酸)
//     - brown     茶 (食物が消化されたもの)
//     - food      未消化の食べ物
//
//   階層1にない場合 → "Other" ボタンを押すと展開:
//
//   階層2 (詳細5色、緊急度高いもの中心):
//     - white_foam  白い泡 (要注意)
//     - red         赤・血混じり (至急)
//     - green       緑 (注意 — 胆汁等)
//     - black       黒 (至急 — 古い血液)
//     - other       上記以外 → 自由記述テキスト
//
// UI流れ:
//   1. 初期: メイン4色 + [+ Other]
//   2. Other押下: 詳細5色がアコーディオンで表示
//   3. other選択 → 自由記述テキストフィールド表示
//
// rev3 §4.7アクセシビリティ: 色だけに頼らず緊急度マーク + ラベル併記
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../data/local/database_enums.dart';
import '../forms/editorial_text_field.dart';

class VomitColorSelector extends StatefulWidget {
  const VomitColorSelector({
    required this.value,
    required this.onChanged,
    required this.colorOtherText,
    required this.onOtherTextChanged,
    this.label,
    this.required = false,
    this.errorText,
    super.key,
  });

  final VomitColor? value;
  final ValueChanged<VomitColor> onChanged;
  final String colorOtherText;
  final ValueChanged<String> onOtherTextChanged;
  final String? label;
  final bool required;
  final String? errorText;

  /// メイン4色 (rev5.5 階層1)
  static const List<VomitColor> mainColors = <VomitColor>[
    VomitColor.clear,
    VomitColor.yellow,
    VomitColor.brown,
    VomitColor.food,
  ];

  /// 詳細5色 (rev5.5 階層2)
  static const List<VomitColor> detailColors = <VomitColor>[
    VomitColor.white_foam,
    VomitColor.red,
    VomitColor.green,
    VomitColor.black,
    VomitColor.other,
  ];

  @override
  State<VomitColorSelector> createState() => _VomitColorSelectorState();
}

class _VomitColorSelectorState extends State<VomitColorSelector> {
  bool _showDetails = false;

  @override
  void initState() {
    super.initState();
    // 既に詳細色が選ばれていれば最初から展開
    if (widget.value != null &&
        VomitColorSelector.detailColors.contains(widget.value)) {
      _showDetails = true;
    }
  }

  @override
  void didUpdateWidget(VomitColorSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 編集モード等で外部からvalueが変わった場合、詳細色なら展開
    if (widget.value != null &&
        VomitColorSelector.detailColors.contains(widget.value) &&
        !_showDetails) {
      setState(() => _showDetails = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool hasError = widget.errorText != null && widget.errorText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            EyebrowText(widget.label ?? l10n.record_field_color),
            if (widget.required) ...<Widget>[
              const SizedBox(width: 4),
              Text('*',
                  style: TextStyle(
                    color: colors.accentDanger,
                    fontFamily: 'JetBrainsMono',
                    fontSize: 10,
                  )),
            ],
          ],
        ),
        const SizedBox(height: AppDimensions.gapMedium),

        // メイン4色 (2x2 グリッド)
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 0,
          crossAxisSpacing: 0,
          childAspectRatio: 3.5,
          children: <Widget>[
            for (final VomitColor c in VomitColorSelector.mainColors)
              _VomitColorOption(
                color: c,
                isSelected: widget.value == c,
                onTap: () => widget.onChanged(c),
              ),
          ],
        ),

        // Other展開トグル
        InkWell(
          onTap: () => setState(() => _showDetails = !_showDetails),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: colors.fg, width: 1),
                right: BorderSide(color: colors.fg, width: 1),
                bottom: BorderSide(color: colors.fg, width: 1),
              ),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  _showDetails ? '−' : '+',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 16,
                    color: colors.fgMuted,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _showDetails ? l10n.vomit_color_less : l10n.vomit_color_more,
                  style: typo.bodySmall.copyWith(color: colors.fgMuted),
                ),
              ],
            ),
          ),
        ),

        // 詳細5色 (展開時)
        if (_showDetails) ...<Widget>[
          const SizedBox(height: AppDimensions.gapSmall),
          Row(
            children: <Widget>[
              for (final VomitColor c in VomitColorSelector.detailColors.take(4))
                Expanded(
                  child: _VomitColorOption(
                    color: c,
                    isSelected: widget.value == c,
                    onTap: () => widget.onChanged(c),
                  ),
                ),
            ],
          ),
          // "Other" は単独で全幅表示
          _VomitColorOption(
            color: VomitColor.other,
            isSelected: widget.value == VomitColor.other,
            onTap: () => widget.onChanged(VomitColor.other),
            fullWidth: true,
          ),
        ],

        // other選択時の自由記述
        if (widget.value == VomitColor.other) ...<Widget>[
          const SizedBox(height: AppDimensions.gapLarge),
          EditorialTextField(
            label: l10n.vomit_color_describe_label,
            initialValue: widget.colorOtherText,
            hint: l10n.vomit_color_describe_hint,
            maxLength: 50,
            onChanged: widget.onOtherTextChanged,
          ),
        ],

        if (hasError) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            widget.errorText!,
            style: typo.bodySmall.copyWith(color: colors.accentDanger),
          ),
        ],
      ],
    );
  }
}

class _VomitColorOption extends StatelessWidget {
  const _VomitColorOption({
    required this.color,
    required this.isSelected,
    required this.onTap,
    this.fullWidth = false,
  });

  final VomitColor color;
  final bool isSelected;
  final VoidCallback onTap;
  final bool fullWidth;

  String _label(AppLocalizations l10n) {
    switch (color) {
      case VomitColor.clear:
        return l10n.vomit_color_clear;
      case VomitColor.yellow:
        return l10n.vomit_color_yellow;
      case VomitColor.brown:
        return l10n.vomit_color_brown;
      case VomitColor.food:
        return l10n.vomit_color_food;
      case VomitColor.white_foam:
        return l10n.vomit_color_white_foam;
      case VomitColor.red:
        return l10n.vomit_color_red;
      case VomitColor.green:
        return l10n.vomit_color_green;
      case VomitColor.black:
        return l10n.vomit_color_black;
      case VomitColor.other:
        return l10n.vomit_color_other_long;
    }
  }

  Color _swatchColor() {
    switch (color) {
      case VomitColor.clear:
        return const Color(0xFFE8F0F4);
      case VomitColor.yellow:
        return const Color(0xFFE5C547);
      case VomitColor.brown:
        return const Color(0xFF6B4423);
      case VomitColor.food:
        return const Color(0xFFB89A6E);
      case VomitColor.white_foam:
        return const Color(0xFFF5F5EE);
      case VomitColor.red:
        return const Color(0xFF9B2A2A);
      case VomitColor.green:
        return const Color(0xFF4A6B3D);
      case VomitColor.black:
        return const Color(0xFF1A1A1A);
      case VomitColor.other:
        return const Color(0xFFD9CFB8);
    }
  }

  _Urgency get _urgency {
    switch (color) {
      case VomitColor.clear:
      case VomitColor.food:
      case VomitColor.brown:
        return _Urgency.normal;
      case VomitColor.yellow:
      case VomitColor.green:
      case VomitColor.white_foam:
        return _Urgency.caution;
      case VomitColor.red:
      case VomitColor.black:
        return _Urgency.urgent;
      case VomitColor.other:
        return _Urgency.normal;
    }
  }

  String _semanticLabel(AppLocalizations l10n) {
    final String name = _label(l10n);
    switch (_urgency) {
      case _Urgency.normal:
        return name;
      case _Urgency.caution:
        return '$name, caution';
      case _Urgency.urgent:
        return '$name, URGENT — see a vet immediately';
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Semantics(
      label: _semanticLabel(l10n),
      selected: isSelected,
      button: true,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: colors.bgSoft,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? colors.fg : colors.bg,
            border: Border.all(color: colors.fg, width: 1),
          ),
          child: Row(
            mainAxisAlignment: fullWidth
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 22,
                height: 22,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _swatchColor(),
                        border: Border.all(
                          color: isSelected ? colors.bg : colors.fgMuted,
                          width: 1,
                        ),
                      ),
                    ),
                    if (_urgency == _Urgency.urgent)
                      Positioned(
                        top: 0,
                        right: 2,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: colors.accentDanger,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? colors.bg : colors.fg,
                              width: 0.8,
                            ),
                          ),
                        ),
                      )
                    else if (_urgency == _Urgency.caution)
                      Positioned(
                        top: 0,
                        right: 2,
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: colors.accentWarn,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _label(l10n),
                  style: typo.bodySmall.copyWith(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? colors.bg : colors.fg,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Urgency { normal, caution, urgent }
