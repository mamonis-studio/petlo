// ============================================================================
// petlo - Diary Record Screen
// ============================================================================
//
// 日記の作成/編集画面。本文 (body) が主役なので大きく扱う。
//
// レイアウト:
//   - エディトリアル見出し
//   - 日付 (DateField)
//   - タイトル (任意、Frauncesイタリック大)
//   - 本文 (Manrope、複数行、無制限近い)
//   - タグ (TagInputField, 最大10個)
//   - 写真 (MultiPhotoPicker, 最大10枚 — rev3でDiaryは多めに許容)
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/section_label.dart';
import '../../providers/diaries_providers.dart';
import '../../widgets/forms/multi_photo_picker.dart';
import '../../widgets/forms/tag_input_field.dart';
import '../../widgets/records/date_time_picker_row.dart';
import '../../widgets/records/record_delete_helper.dart';
import '../paywall/paywall_screen.dart';
import 'diary_form_controller.dart';
import 'diary_form_state.dart';

class DiaryRecordScreen extends ConsumerStatefulWidget {
  const DiaryRecordScreen({this.editingDiaryId, super.key});

  final int? editingDiaryId;

  static Future<bool?> push(BuildContext context, {int? editingDiaryId}) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => DiaryRecordScreen(editingDiaryId: editingDiaryId),
      ),
    );
  }

  @override
  ConsumerState<DiaryRecordScreen> createState() =>
      _DiaryRecordScreenState();
}

class _DiaryRecordScreenState extends ConsumerState<DiaryRecordScreen> {
  late final TextEditingController _titleC;
  late final TextEditingController _bodyC;

  bool _initialSynced = false;

  @override
  void initState() {
    super.initState();
    _titleC = TextEditingController();
    _bodyC = TextEditingController();
  }

  @override
  void dispose() {
    _titleC.dispose();
    _bodyC.dispose();
    super.dispose();
  }

  void _syncControllers(DiaryFormState s) {
    if (_initialSynced) return;
    // build 73: 編集モードかは **widget が最初から知っている**。
    // 以前は s.isEditing を見ていたが、これは
    // `editingXxxId != null` であり、ロード前の初期 State では false になる。
    // その結果「新規作成」と誤判定して _initialSynced を立ててしまい、
    // 後からデータが届いても controller へ反映されなかった
    // (アプリ再起動後の初回だけ入力欄が空になる不具合)。
    //
    // 「値が無い」と「まだ読めていない」を混同しないこと。
    if (widget.editingDiaryId == null) {
      _initialSynced = true;
      return;
    }
    if (s.eventAt == null) return;
    _titleC.text = s.title;
    _bodyC.text = s.body;
    _initialSynced = true;
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final DiaryFormState s =
        ref.watch(diaryFormControllerProvider(widget.editingDiaryId));
    final DiaryFormController controller =
        ref.read(diaryFormControllerProvider(widget.editingDiaryId).notifier);

    _syncControllers(s);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          s.isEditing
              ? AppLocalizations.of(context).appbar_edit_diary.toUpperCase()
              : AppLocalizations.of(context).appbar_new_diary.toUpperCase(),
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            letterSpacing: 10 * 0.2,
            color: colors.fg,
          ),
        ),
        centerTitle: true,
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            AppLocalizations.of(context).common_cancel.toUpperCase(),
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 9,
              letterSpacing: 9 * 0.15,
              color: colors.fgMuted,
            ),
          ),
        ),
        leadingWidth: 80,
        actions: <Widget>[
          if (s.isEditing && widget.editingDiaryId != null)
            IconButton(
              icon: Icon(Icons.delete_outline, color: colors.fgMuted, size: 22),
              onPressed: _onDelete,
              tooltip: AppLocalizations.of(context).common_delete,
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.paddingPage,
            AppDimensions.paddingPage,
            AppDimensions.paddingPage,
            AppDimensions.paddingPage * 2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SectionLabel(
                AppLocalizations.of(context).record_diary_eyebrow,
                size: EyebrowSize.large,
                padding: const EdgeInsets.fromLTRB(
                    0, 0, 0, AppDimensions.paddingSection),
              ),

              // ===== Date + Time =====
              DateTimePickerRow(
                value: s.eventAt,
                onChanged: controller.updateEventAt,
                errorText: s.errors.eventAt,
                firstDate: DateTime(DateTime.now().year - 10),
                lastDate: DateTime.now().add(const Duration(days: 1)),
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== Title =====
              EyebrowText(AppLocalizations.of(context).record_diary_title_optional),
              const SizedBox(height: AppDimensions.gapSmall),
              _TitleField(
                controller: _titleC,
                onChanged: controller.updateTitle,
                hintText: AppLocalizations.of(context).record_field_diary_untitled,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== Body =====
              Row(
                children: <Widget>[
                  EyebrowText(AppLocalizations.of(context).record_diary_body_label),
                  const SizedBox(width: 4),
                  Text('*',
                      style: TextStyle(
                        color: colors.accentDanger,
                        fontFamily: 'JetBrainsMono',
                        fontSize: 10,
                      )),
                ],
              ),
              const SizedBox(height: AppDimensions.gapSmall),
              _BodyField(
                controller: _bodyC,
                onChanged: controller.updateBody,
                errorText: s.errors.body,
                hintText: AppLocalizations.of(context).record_field_diary_body_hint,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== Tags =====
              TagInputField(
                label: AppLocalizations.of(context).record_field_tags_label,
                tags: s.tags,
                onChanged: controller.updateTags,
                hint: AppLocalizations.of(context).record_field_tags_hint,
                maxTags: 10,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== Photos (最大10枚) =====
              MultiPhotoPicker(
                label: AppLocalizations.of(context).record_field_photos_label,
                slots: s.photoSlots,
                onSlotsChanged: controller.updatePhotoSlots,
                maxPhotos: 10,
              ),
              const SizedBox(height: AppDimensions.paddingSection * 1.5),

              PrimaryButton(
                label: s.isSubmitting
                    ? AppLocalizations.of(context).common_saving
                    : (s.isEditing
                        ? AppLocalizations.of(context).common_update
                        : AppLocalizations.of(context).common_save),
                onPressed: s.isSubmitting ? null : () => _onSave(controller),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onDelete() async {
    if (widget.editingDiaryId == null) return;
    final bool ok = await RecordDeleteHelper.confirm(context);
    if (!ok || !mounted) return;
    final bool deleted = await ref
        .read(diariesRepositoryProvider)
        .softDelete(widget.editingDiaryId!);
    if (!mounted) return;
    if (deleted) {
      ref.invalidate(diaryFormControllerProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).common_deleted),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _onSave(DiaryFormController controller) async {
    final r = await controller.save(AppLocalizations.of(context));
    switch (r) {
      case DiaryFormSaveOutcome.success:
        if (mounted) {
          ref.invalidate(diaryFormControllerProvider);
          Navigator.of(context).pop(true);
        }
      case DiaryFormSaveOutcome.validationFailed:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).common_input_invalid),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      case DiaryFormSaveOutcome.dbError:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).common_save_failed),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      case DiaryFormSaveOutcome.proLimitReached:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  AppLocalizations.of(context).pro_limit_diary_monthly),
              behavior: SnackBarBehavior.floating,
            ),
          );
          await PaywallScreen.push(context);
        }
    }
  }
}

// ============================================================================
// _TitleField - Frauncesイタリック大きめ + 下線
// ============================================================================
class _TitleField extends StatelessWidget {
  const _TitleField({
    required this.controller,
    required this.onChanged,
    required this.hintText,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return TextField(
      controller: controller,
      onChanged: onChanged,
      maxLength: 100,
      maxLines: 2,
      minLines: 1,
      style: TextStyle(
        fontFamily: 'Fraunces',
        fontStyle: FontStyle.italic,
        fontSize: 22,
        height: 1.3,
        color: colors.fg,
      ),
      decoration: InputDecoration(
        counterText: '',
        hintText: hintText,
        hintStyle: TextStyle(
          fontFamily: 'Fraunces',
          fontStyle: FontStyle.italic,
          fontSize: 22,
          color: colors.fgFaint,
        ),
        border: UnderlineInputBorder(
          borderSide: BorderSide(color: colors.line),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: colors.line),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: colors.fg, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        isDense: true,
      ),
    );
  }
}

// ============================================================================
// _BodyField - Manrope本文、複数行、ふっくらした行間
// ============================================================================
class _BodyField extends StatelessWidget {
  const _BodyField({
    required this.controller,
    required this.onChanged,
    required this.hintText,
    this.errorText,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final bool hasError = errorText != null && errorText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: controller,
          onChanged: onChanged,
          maxLines: 12,
          minLines: 6,
          maxLength: 5000,
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 16,
            height: 1.7,
            color: colors.fg,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: hintText,
            hintStyle: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 16,
              height: 1.7,
              color: colors.fgFaint,
            ),
            border: OutlineInputBorder(
              borderSide:
                  BorderSide(color: hasError ? colors.accentDanger : colors.line),
              borderRadius: BorderRadius.zero,
            ),
            enabledBorder: OutlineInputBorder(
              borderSide:
                  BorderSide(color: hasError ? colors.accentDanger : colors.line),
              borderRadius: BorderRadius.zero,
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: hasError ? colors.accentDanger : colors.fg,
                width: 2,
              ),
              borderRadius: BorderRadius.zero,
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
        if (hasError) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              color: colors.accentDanger,
            ),
          ),
        ],
      ],
    );
  }
}
