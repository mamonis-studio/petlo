// ============================================================================
// petlo - Poop Record Screen
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
import '../../widgets/forms/pet_photo_picker.dart';
import '../../providers/poops_providers.dart';
import '../../widgets/poop/poop_color_selector.dart';
import '../../widgets/poop/poop_form_selector.dart';
import '../../widgets/records/date_time_picker_row.dart';
import '../../widgets/records/record_amount_selector.dart';
import '../../widgets/records/record_delete_helper.dart';
import 'poop_form_controller.dart';
import 'poop_form_state.dart';

class PoopRecordScreen extends ConsumerStatefulWidget {
  const PoopRecordScreen({this.editingPoopId, super.key});

  final int? editingPoopId;

  static Future<bool?> push(BuildContext context, {int? editingPoopId}) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PoopRecordScreen(editingPoopId: editingPoopId),
      ),
    );
  }

  @override
  ConsumerState<PoopRecordScreen> createState() => _PoopRecordScreenState();
}

class _PoopRecordScreenState extends ConsumerState<PoopRecordScreen> {
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

  void _syncControllers(PoopFormState s) {
    if (_initialSynced) return;
    if (!s.isEditing) {
      _initialSynced = true;
      return;
    }
    if (s.pooedAt == null) return;
    _notesC.text = s.notes;
    _initialSynced = true;
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final PoopFormState s =
        ref.watch(poopFormControllerProvider(widget.editingPoopId));
    final PoopFormController controller =
        ref.read(poopFormControllerProvider(widget.editingPoopId).notifier);

    _syncControllers(s);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          s.isEditing
              ? AppLocalizations.of(context).appbar_edit_poop.toUpperCase()
              : AppLocalizations.of(context).appbar_new_poop.toUpperCase(),
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
          if (s.isEditing && widget.editingPoopId != null)
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

              PoopFormSelector(
                value: s.form,
                required: true,
                errorText: s.errors.form,
                onChanged: controller.updateForm,
              ),
              const SizedBox(height: AppDimensions.gapXLarge),

              PoopColorSelector(
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
              const SizedBox(height: AppDimensions.paddingSection),

              SectionLabel(AppLocalizations.of(context).common_when),
              DateTimePickerRow(
                value: s.pooedAt,
                onChanged: controller.updatePooedAt,
                errorText: s.errors.pooedAt,
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
              const SizedBox(height: AppDimensions.paddingSection),

              SectionLabel(AppLocalizations.of(context).common_photo_label),
              PetPhotoPicker(
                label: AppLocalizations.of(context).record_field_photo_label,
                currentPhotoFile: s.photoFile,
                currentRelativePath: s.savedPhotoRelativePath,
                onPicked: controller.updatePhotoFile,
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
    if (widget.editingPoopId == null) return;
    final bool ok = await RecordDeleteHelper.confirm(context);
    if (!ok || !mounted) return;
    final bool deleted = await ref
        .read(poopsRepositoryProvider)
        .softDelete(widget.editingPoopId!);
    if (!mounted) return;
    if (deleted) {
      ref.invalidate(poopFormControllerProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).common_deleted),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _onSave(PoopFormController controller) async {
    final PoopFormSaveOutcome r = await controller.save();
    switch (r) {
      case PoopFormSaveOutcome.success:
        if (mounted) {
          ref.invalidate(poopFormControllerProvider);
          Navigator.of(context).pop(true);
        }
      case PoopFormSaveOutcome.validationFailed:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).common_input_invalid),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      case PoopFormSaveOutcome.dbError:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).common_save_failed),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
    }
  }
}
