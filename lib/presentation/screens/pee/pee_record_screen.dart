// ============================================================================
// petlo - Pee Record Screen
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/section_label.dart';
import '../../widgets/forms/editorial_text_field.dart';
import '../../providers/pees_providers.dart';
import '../../widgets/pee/pee_color_selector.dart';
import '../../widgets/records/count_stepper.dart';
import '../../widgets/records/date_time_picker_row.dart';
import '../../widgets/records/record_amount_selector.dart';
import '../../widgets/records/record_delete_helper.dart';
import '../paywall/paywall_screen.dart';
import 'pee_form_controller.dart';
import 'pee_form_state.dart';

class PeeRecordScreen extends ConsumerStatefulWidget {
  const PeeRecordScreen({this.editingPeeId, super.key});

  final int? editingPeeId;

  static Future<bool?> push(BuildContext context, {int? editingPeeId}) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PeeRecordScreen(editingPeeId: editingPeeId),
      ),
    );
  }

  @override
  ConsumerState<PeeRecordScreen> createState() => _PeeRecordScreenState();
}

class _PeeRecordScreenState extends ConsumerState<PeeRecordScreen> {
  late final TextEditingController _notesC;
  bool _initialSynced = false;

  @override
  void initState() {
    super.initState();
    _notesC = TextEditingController();
  }

  @override
  void dispose() {
    _notesC.dispose();
    super.dispose();
  }

  void _syncControllers(PeeFormState s) {
    if (_initialSynced) return;
    // build 73: 編集モードかは **widget が最初から知っている**。
    // 以前は s.isEditing を見ていたが、これは
    // `editingXxxId != null` であり、ロード前の初期 State では false になる。
    // その結果「新規作成」と誤判定して _initialSynced を立ててしまい、
    // 後からデータが届いても controller へ反映されなかった
    // (アプリ再起動後の初回だけ入力欄が空になる不具合)。
    //
    // 「値が無い」と「まだ読めていない」を混同しないこと。
    if (widget.editingPeeId == null) {
      _initialSynced = true;
      return;
    }
    if (s.peedAt == null) return;
    _notesC.text = s.notes;
    _initialSynced = true;
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final PeeFormState s =
        ref.watch(peeFormControllerProvider(widget.editingPeeId));
    final PeeFormController controller =
        ref.read(peeFormControllerProvider(widget.editingPeeId).notifier);

    _syncControllers(s);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          s.isEditing
              ? AppLocalizations.of(context).appbar_edit_pee.toUpperCase()
              : AppLocalizations.of(context).appbar_new_pee.toUpperCase(),
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
          if (s.isEditing && widget.editingPeeId != null)
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
                s.isEditing
                    ? AppLocalizations.of(context).common_editing
                    : AppLocalizations.of(context).common_today,
                size: EyebrowSize.large,
                padding: const EdgeInsets.fromLTRB(
                    0, 0, 0, AppDimensions.paddingSection),
              ),

              PeeColorSelector(
                value: s.color,
                required: true,
                errorText: s.errors.color,
                onChanged: controller.updateColor,
              ),
              const SizedBox(height: AppDimensions.gapXLarge),

              RecordAmountSelector(
                value: s.amount,
                required: true,
                errorText: s.errors.amount,
                onChanged: controller.updateAmount,
              ),
              const SizedBox(height: AppDimensions.gapXLarge),

              CountStepper(
                label: AppLocalizations.of(context).record_field_count,
                value: s.count,
                onChanged: controller.updateCount,
                unitText: '×',
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              SectionLabel(AppLocalizations.of(context).common_when),
              DateTimePickerRow(
                value: s.peedAt,
                onChanged: controller.updatePeedAt,
                errorText: s.errors.peedAt,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              SectionLabel(AppLocalizations.of(context).common_notes),
              EditorialTextField(
                label: AppLocalizations.of(context).record_field_notes_label,
                controller: _notesC,
                hint: AppLocalizations.of(context).record_field_notes_hint,
                maxLines: 3,
                minLines: 2,
                onChanged: controller.updateNotes,
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
    if (widget.editingPeeId == null) return;
    final bool ok = await RecordDeleteHelper.confirm(context);
    if (!ok || !mounted) return;
    final bool deleted =
        await ref.read(peesRepositoryProvider).softDelete(widget.editingPeeId!);
    if (!mounted) return;
    if (deleted) {
      ref.invalidate(peeFormControllerProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).common_deleted),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _onSave(PeeFormController controller) async {
    final r = await controller.save(AppLocalizations.of(context));
    switch (r) {
      case PeeFormSaveOutcome.success:
        if (mounted) {
          ref.invalidate(peeFormControllerProvider);
          Navigator.of(context).pop(true);
        }
      case PeeFormSaveOutcome.validationFailed:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).common_input_invalid),
                behavior: SnackBarBehavior.floating),
          );
        }
      case PeeFormSaveOutcome.dbError:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).common_save_failed),
                behavior: SnackBarBehavior.floating),
          );
        }
      case PeeFormSaveOutcome.proLimitReached:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  AppLocalizations.of(context).pro_limit_record_monthly),
              behavior: SnackBarBehavior.floating,
            ),
          );
          await PaywallScreen.push(context);
        }
    }
  }
}
