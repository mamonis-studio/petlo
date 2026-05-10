// ============================================================================
// petlo - TagInputField
// ============================================================================
//
// 複数タグを追加/削除できるフィールド。
// 用途: 持病一覧、アレルギー一覧、日記タグ
//
// UX:
//   - 入力欄に文字打って Enter or "+" ボタンで追加
//   - 追加されたタグは下に並ぶ、× で削除可能
//
// ============================================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';

class TagInputField extends StatefulWidget {
  const TagInputField({
    required this.label,
    required this.tags,
    required this.onChanged,
    this.hint,
    this.helperText,
    this.maxTags = 10,
    super.key,
  });

  final String label;
  final List<String> tags;
  final ValueChanged<List<String>> onChanged;
  final String? hint;
  final String? helperText;
  final int maxTags;

  @override
  State<TagInputField> createState() => _TagInputFieldState();
}

class _TagInputFieldState extends State<TagInputField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _addTag() {
    final String tag = _controller.text.trim();
    if (tag.isEmpty) return;
    if (widget.tags.contains(tag)) return; // 重複防止
    if (widget.tags.length >= widget.maxTags) return;

    final List<String> newTags = <String>[...widget.tags, tag];
    widget.onChanged(newTags);
    _controller.clear();
    _focusNode.requestFocus();
  }

  void _removeTag(String tag) {
    final List<String> newTags = widget.tags.where((String t) => t != tag).toList();
    widget.onChanged(newTags);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final bool atLimit = widget.tags.length >= widget.maxTags;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        EyebrowText(widget.label),
        const SizedBox(height: AppDimensions.gapSmall),

        // 入力欄 + 追加ボタン
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                enabled: !atLimit,
                onSubmitted: (_) => _addTag(),
                textInputAction: TextInputAction.done,
                style: typo.bodyLarge,
                decoration: InputDecoration(
                  hintText:
                      atLimit ? '${widget.maxTags} 個まで' : (widget.hint ?? '入力して追加'),
                  hintStyle: typo.bodyLarge.copyWith(color: colors.fgFaint),
                  border: _underline(colors.line),
                  enabledBorder: _underline(colors.line),
                  focusedBorder: _underline(colors.fg, width: 2),
                  disabledBorder: _underline(colors.line),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: atLimit ? null : _addTag,
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: atLimit ? colors.fgFaint : colors.fg,
                  ),
                ),
                child: Text(
                  '+',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 18,
                    color: atLimit ? colors.fgFaint : colors.fg,
                  ),
                ),
              ),
            ),
          ],
        ),

        if (widget.helperText != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(widget.helperText!, style: typo.bodySmall.copyWith(color: colors.fgMuted)),
        ],

        // タグ一覧
        if (widget.tags.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppDimensions.gapMedium),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final String tag in widget.tags)
                _Chip(label: tag, onRemove: () => _removeTag(tag)),
            ],
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

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
      decoration: BoxDecoration(
        border: Border.all(color: colors.fg, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: typo.bodySmall.copyWith(color: colors.fg)),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close, size: 14, color: colors.fgMuted),
            ),
          ),
        ],
      ),
    );
  }
}
