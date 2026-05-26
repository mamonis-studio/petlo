// ============================================================================
// petlo - Pet Form Screen
// ============================================================================
//
// ペット登録(新規) / 編集画面。
//
// 構造:
//   ┌──────────────────────────┐
//   │ ← Cancel    Add a pet  ⏎ │  ← AppBar(エディトリアル風)
//   ├──────────────────────────┤
//   │                          │
//   │  [PHOTO]                 │  ← 円形ピッカー
//   │  [Name]                  │
//   │  [Type: 犬 / 猫]         │
//   │  [Breed]                 │
//   │                          │
//   │  ─§ HEALTH ─             │
//   │  [Sex] [Neutered]        │
//   │  [Birthday]              │
//   │  [Ideal weight min/max]  │
//   │  [Chronic conditions]    │
//   │  [Allergies]             │
//   │                          │
//   │  ─§ CONTACTS ─           │
//   │  [Primary vet]           │
//   │  [Emergency vet]         │
//   │                          │
//   │  [SAVE]                  │
//   └──────────────────────────┘
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/section_label.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../../data/repositories/pets_repository.dart';
import '../../providers/groups_providers.dart';
import '../../providers/pets_providers.dart';
import '../../providers/scope_providers.dart';
import '../../widgets/dialogs/duplicate_name_dialog.dart';
import '../../widgets/forms/date_field.dart';
import '../../widgets/forms/editorial_text_field.dart';
import '../../widgets/forms/pet_photo_picker.dart';
import '../../widgets/forms/segmented_selector.dart';
import '../../widgets/forms/tag_input_field.dart';
import 'pet_form_controller.dart';
import 'pet_form_state.dart';

class PetFormScreen extends ConsumerStatefulWidget {
  const PetFormScreen({
    this.editingPetId,
    super.key,
  });

  /// 編集モード時のペットID。null なら新規作成。
  final int? editingPetId;

  /// このスクリーンへのナビゲーションヘルパー。
  /// 戻り値は保存成功なら true、キャンセルなら false/null。
  static Future<bool?> push(BuildContext context, {int? editingPetId}) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PetFormScreen(editingPetId: editingPetId),
      ),
    );
  }

  @override
  ConsumerState<PetFormScreen> createState() => _PetFormScreenState();
}

class _PetFormScreenState extends ConsumerState<PetFormScreen> {
  // テキスト系のControllerは画面の状態として持つ (FormStateで持つと面倒)
  late final TextEditingController _nameC;
  late final TextEditingController _breedC;
  late final TextEditingController _idealMinC;
  late final TextEditingController _idealMaxC;
  late final TextEditingController _primaryNameC;
  late final TextEditingController _primaryPhoneC;
  late final TextEditingController _primaryAddressC;
  late final TextEditingController _emergencyNameC;
  late final TextEditingController _emergencyPhoneC;
  late final TextEditingController _emergencyAddressC;

  bool _initialControllersSynced = false;

  /// 新規作成時に「詳細を登録する」セクションを展開しているか。
  /// 編集モードでは常に展開扱い。
  bool _expandedDetails = false;

  @override
  void initState() {
    super.initState();
    _nameC = TextEditingController();
    _breedC = TextEditingController();
    _idealMinC = TextEditingController();
    _idealMaxC = TextEditingController();
    _primaryNameC = TextEditingController();
    _primaryPhoneC = TextEditingController();
    _primaryAddressC = TextEditingController();
    _emergencyNameC = TextEditingController();
    _emergencyPhoneC = TextEditingController();
    _emergencyAddressC = TextEditingController();
  }

  @override
  void dispose() {
    _nameC.dispose();
    _breedC.dispose();
    _idealMinC.dispose();
    _idealMaxC.dispose();
    _primaryNameC.dispose();
    _primaryPhoneC.dispose();
    _primaryAddressC.dispose();
    _emergencyNameC.dispose();
    _emergencyPhoneC.dispose();
    _emergencyAddressC.dispose();
    super.dispose();
  }

  /// 編集モードで既存値ロード後にControllerにテキストを反映
  void _syncControllersFromState(PetFormState s) {
    if (_initialControllersSynced) return;
    if (!s.isEditing) {
      _initialControllersSynced = true;
      return;
    }
    // 編集モード: stateに値が入った段階でControllerに反映
    if (s.name.isEmpty &&
        s.breed.isEmpty &&
        s.primaryVetName.isEmpty) {
      // まだロード中
      return;
    }
    _nameC.text = s.name;
    _breedC.text = s.breed;
    _idealMinC.text = _gToKgString(s.idealWeightMinG);
    _idealMaxC.text = _gToKgString(s.idealWeightMaxG);
    _primaryNameC.text = s.primaryVetName;
    _primaryPhoneC.text = s.primaryVetPhone;
    _primaryAddressC.text = s.primaryVetAddress;
    _emergencyNameC.text = s.emergencyVetName;
    _emergencyPhoneC.text = s.emergencyVetPhone;
    _emergencyAddressC.text = s.emergencyVetAddress;
    _initialControllersSynced = true;
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final PetFormState s =
        ref.watch(petFormControllerProvider(widget.editingPetId));
    final PetFormController controller =
        ref.read(petFormControllerProvider(widget.editingPetId).notifier);

    _syncControllersFromState(s);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: _buildAppBar(context, s),
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
              _buildPageTitle(s.isEditing),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== Photo =====
              PetPhotoPicker(
                label: l10n.pet_form_field_photo,
                currentPhotoFile: s.photoFile,
                currentRelativePath: s.savedPhotoRelativePath,
                fallbackInitial:
                    s.name.isNotEmpty ? s.name.characters.first : null,
                onPicked: controller.updatePhotoFile,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== Basic =====
              _BasicSection(
                state: s,
                controller: controller,
                nameC: _nameC,
                breedC: _breedC,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              // ===== 詳細 (新規作成時はトグル、編集時は常に展開) =====
              if (s.isEditing || _expandedDetails) ...<Widget>[
                SectionLabel(l10n.pet_form_section_health),
                _HealthSection(
                  state: s,
                  controller: controller,
                  idealMinC: _idealMinC,
                  idealMaxC: _idealMaxC,
                ),
                const SizedBox(height: AppDimensions.paddingSection),
                SectionLabel(l10n.pet_form_section_contacts),
                _ContactsSection(
                  state: s,
                  controller: controller,
                  primaryNameC: _primaryNameC,
                  primaryPhoneC: _primaryPhoneC,
                  primaryAddressC: _primaryAddressC,
                  emergencyNameC: _emergencyNameC,
                  emergencyPhoneC: _emergencyPhoneC,
                  emergencyAddressC: _emergencyAddressC,
                ),
                // build 20: 編集時のみスコープ移動 UI を出す。
                if (s.isEditing && widget.editingPetId != null) ...<Widget>[
                  const SizedBox(height: AppDimensions.paddingSection),
                  const SectionLabel('Sharing scope'),
                  _ScopeMoverSection(petId: widget.editingPetId!),
                ],
              ] else
                _DetailsExpandHint(
                  onTap: () =>
                      setState(() => _expandedDetails = true),
                ),
              const SizedBox(height: AppDimensions.paddingSection * 1.5),

              // ===== Save Button =====
              PrimaryButton(
                label: s.isSubmitting
                    ? (s.isEditing ? l10n.common_updating : l10n.common_saving)
                    : (s.isEditing ? l10n.common_update : l10n.common_save),
                onPressed: s.isSubmitting ? null : () => _onSave(controller),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // AppBar
  // ============================================================================
  PreferredSizeWidget _buildAppBar(BuildContext context, PetFormState s) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return AppBar(
      backgroundColor: colors.bg,
      foregroundColor: colors.fg,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: Text(
        s.isEditing ? l10n.pet_form_app_bar_edit : l10n.pet_form_app_bar_new,
        style: typo.metaSmall.copyWith(letterSpacing: 0.5),
      ),
      centerTitle: true,
      leading: TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(
          l10n.common_cancel,
          style: typo.metaSmall.copyWith(color: colors.fgMuted),
        ),
      ),
      leadingWidth: 96,
    );
  }

  // ============================================================================
  // ページタイトル
  // ============================================================================
  Widget _buildPageTitle(bool isEditing) {
    return Builder(
      builder: (BuildContext context) {
        final AppLocalizations l10n = AppLocalizations.of(context);
        return SectionLabel(
          isEditing
              ? l10n.pet_form_eyebrow_edit
              : l10n.pet_form_eyebrow_new,
          size: EyebrowSize.large,
          padding: EdgeInsets.zero,
        );
      },
    );
  }

  // ============================================================================
  // Save handler
  // ============================================================================
  Future<void> _onSave(PetFormController controller) async {
    final PetFormSaveOutcome outcome =
        await controller.save(AppLocalizations.of(context));

    switch (outcome) {
      case PetFormSaveOutcome.success:
        if (mounted) Navigator.of(context).pop(true);

      case PetFormSaveOutcome.validationFailed:
        // バリデーションエラーは画面上に既に反映済み(state.errors)
        if (mounted) {
          final AppLocalizations l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.pet_form_error_validation),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }

      case PetFormSaveOutcome.duplicateNameNeedsConfirmation:
        await _handleDuplicateName(controller);

      case PetFormSaveOutcome.dbError:
        if (mounted) {
          final AppLocalizations l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.pet_form_error_save_failed),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
    }
  }

  Future<void> _handleDuplicateName(PetFormController controller) async {
    if (!mounted) return;
    final String groupName = ref.read(currentGroupProvider).maybeWhen(
          data: (group) => group?.name ?? 'This group',
          orElse: () => 'This group',
        );

    final bool? confirmed = await showDuplicateNameDialog(
      context: context,
      petName: ref.read(petFormControllerProvider(widget.editingPetId)).name.trim(),
      groupDisplayName: groupName,
    );

    if (confirmed == true) {
      final PetFormFinalSaveOutcome outcome =
          await controller.confirmAndSave(AppLocalizations.of(context));
      if (!mounted) return;
      if (outcome == PetFormFinalSaveOutcome.success) {
        Navigator.of(context).pop(true);
      } else {
        final AppLocalizations l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.pet_form_error_save_failed),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

// ============================================================================
// Basic Section
// ============================================================================
class _BasicSection extends StatelessWidget {
  const _BasicSection({
    required this.state,
    required this.controller,
    required this.nameC,
    required this.breedC,
  });

  final PetFormState state;
  final PetFormController controller;
  final TextEditingController nameC;
  final TextEditingController breedC;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        EditorialTextField(
          label: l10n.pet_form_field_name,
          controller: nameC,
          required: true,
          maxLength: 50,
          errorText: state.errors.name,
          onChanged: controller.updateName,
        ),
        const SizedBox(height: AppDimensions.gapXLarge),

        SegmentedSelector<PetType>(
          label: l10n.pet_form_field_type,
          options: PetType.values,
          value: state.type,
          required: true,
          errorText: state.errors.type,
          optionLabel: (PetType t) =>
              t == PetType.dog ? l10n.pet_type_dog : l10n.pet_type_cat,
          onChanged: controller.updateType,
        ),
        const SizedBox(height: AppDimensions.gapXLarge),

        // TODO: Chunk 16 で犬種マスタを統合 → ドロップダウン化
        // build 6 で任意化、build 12 で required アスタリスクを削除
        EditorialTextField(
          label: l10n.pet_form_field_breed,
          controller: breedC,
          hint: l10n.pet_form_field_breed_hint,
          errorText: state.errors.breed,
          onChanged: controller.updateBreed,
        ),
      ],
    );
  }
}

// ============================================================================
// Health Section
// ============================================================================
class _HealthSection extends StatelessWidget {
  const _HealthSection({
    required this.state,
    required this.controller,
    required this.idealMinC,
    required this.idealMaxC,
  });

  final PetFormState state;
  final PetFormController controller;
  final TextEditingController idealMinC;
  final TextEditingController idealMaxC;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SegmentedSelector<PetSex>(
          label: l10n.pet_form_field_sex,
          options: PetSex.values,
          value: state.sex,
          // build 22: 性別は任意項目 (必須マーク * を出さない)
          errorText: state.errors.sex,
          optionLabel: (PetSex s) => switch (s) {
            PetSex.male => l10n.pet_sex_male,
            PetSex.female => l10n.pet_sex_female,
            PetSex.unknown => l10n.pet_sex_unknown,
          },
          onChanged: controller.updateSex,
        ),
        const SizedBox(height: AppDimensions.gapXLarge),

        _NeuteredToggle(
          value: state.neutered,
          onChanged: controller.updateNeutered,
        ),
        const SizedBox(height: AppDimensions.gapXLarge),

        DateField(
          label: l10n.pet_form_field_birthday,
          value: state.birthday,
          onChanged: controller.updateBirthday,
          firstDate: DateTime(DateTime.now().year - 30),
          lastDate: DateTime.now(),
        ),
        const SizedBox(height: AppDimensions.gapXLarge),

        // 理想体重 (min/max を kg 入力で横並び。DB は g で保持)
        Row(
          children: <Widget>[
            Expanded(
              child: EditorialTextField(
                label: l10n.pet_form_field_ideal_weight_min,
                controller: idealMinC,
                hint: '0.0',
                suffixText: 'kg',
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                errorText: state.errors.idealWeightMinG,
                onChanged: (String v) {
                  controller.updateIdealWeightMinG(_kgStringToG(v));
                },
              ),
            ),
            const SizedBox(width: AppDimensions.gapLarge),
            Expanded(
              child: EditorialTextField(
                label: l10n.pet_form_field_ideal_weight_max,
                controller: idealMaxC,
                hint: '0.0',
                suffixText: 'kg',
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                errorText: state.errors.idealWeightMaxG,
                onChanged: (String v) {
                  controller.updateIdealWeightMaxG(_kgStringToG(v));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimensions.gapXLarge),

        TagInputField(
          label: l10n.pet_form_field_chronic_conditions,
          tags: state.chronicConditions,
          hint: l10n.pet_form_field_chronic_conditions_hint,
          helperText: l10n.pet_form_helper_tap_plus,
          onChanged: controller.updateChronicConditions,
        ),
        const SizedBox(height: AppDimensions.gapXLarge),

        TagInputField(
          label: l10n.pet_form_field_allergies,
          tags: state.allergies,
          hint: l10n.pet_form_field_allergies_hint,
          helperText: l10n.pet_form_helper_tap_plus,
          onChanged: controller.updateAllergies,
        ),
      ],
    );
  }
}

// ============================================================================
// Neutered Toggle (custom)
// ============================================================================
class _NeuteredToggle extends StatelessWidget {
  const _NeuteredToggle({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        EyebrowText(l10n.pet_form_field_neutered),
        const SizedBox(height: AppDimensions.gapSmall),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              value ? l10n.common_yes : l10n.common_no,
              style: typo.bodyLarge.copyWith(
                fontFamily: 'Fraunces',
                fontStyle: FontStyle.italic,
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: colors.bg,
              activeTrackColor: colors.fg,
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================================
// Contacts Section
// ============================================================================
class _ContactsSection extends StatelessWidget {
  const _ContactsSection({
    required this.state,
    required this.controller,
    required this.primaryNameC,
    required this.primaryPhoneC,
    required this.primaryAddressC,
    required this.emergencyNameC,
    required this.emergencyPhoneC,
    required this.emergencyAddressC,
  });

  final PetFormState state;
  final PetFormController controller;
  final TextEditingController primaryNameC;
  final TextEditingController primaryPhoneC;
  final TextEditingController primaryAddressC;
  final TextEditingController emergencyNameC;
  final TextEditingController emergencyPhoneC;
  final TextEditingController emergencyAddressC;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Primary vet
        EditorialTextField(
          label: l10n.pet_form_field_primary_vet_name,
          controller: primaryNameC,
          onChanged: (String v) =>
              controller.updatePrimaryVet(name: v),
        ),
        const SizedBox(height: AppDimensions.gapXLarge),

        EditorialTextField(
          label: l10n.pet_form_field_primary_vet_phone,
          controller: primaryPhoneC,
          keyboardType: TextInputType.phone,
          errorText: state.errors.primaryVetPhone,
          onChanged: (String v) =>
              controller.updatePrimaryVet(phone: v),
        ),
        const SizedBox(height: AppDimensions.gapXLarge),

        EditorialTextField(
          label: l10n.pet_form_field_primary_vet_address,
          controller: primaryAddressC,
          maxLines: 2,
          onChanged: (String v) =>
              controller.updatePrimaryVet(address: v),
        ),
        const SizedBox(height: AppDimensions.gapXLarge * 1.2),

        // Emergency vet
        EditorialTextField(
          label: l10n.pet_form_field_emergency_vet_name,
          controller: emergencyNameC,
          helperText: l10n.pet_form_field_emergency_vet_helper,
          onChanged: (String v) =>
              controller.updateEmergencyVet(name: v),
        ),
        const SizedBox(height: AppDimensions.gapXLarge),

        EditorialTextField(
          label: l10n.pet_form_field_emergency_vet_phone,
          controller: emergencyPhoneC,
          keyboardType: TextInputType.phone,
          errorText: state.errors.emergencyVetPhone,
          onChanged: (String v) =>
              controller.updateEmergencyVet(phone: v),
        ),
        const SizedBox(height: AppDimensions.gapXLarge),

        EditorialTextField(
          label: l10n.pet_form_field_emergency_vet_address,
          controller: emergencyAddressC,
          maxLines: 2,
          onChanged: (String v) =>
              controller.updateEmergencyVet(address: v),
        ),
      ],
    );
  }
}

/// 新規作成時に表示する「詳細情報を登録する」展開リンク。
class _DetailsExpandHint extends StatelessWidget {
  const _DetailsExpandHint({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.pet_form_details_later_helper,
          style: typo.bodySmall.copyWith(color: colors.fgMuted, height: 1.5),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: colors.fg, width: 1),
            ),
            child: Text(
              l10n.pet_form_show_more_details,
              style: typo.bodyMedium.copyWith(
                color: colors.fg,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// g (DB保存単位) → kg 表示用文字列。null なら空文字。
String _gToKgString(int? grams) {
  if (grams == null) return '';
  final double kg = grams / 1000;
  // 整数 kg は小数点なし、それ以外は最大2桁
  if (kg == kg.roundToDouble()) return kg.toStringAsFixed(0);
  return kg
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// kg 入力文字列 → g (int)。空または不正なら null。
int? _kgStringToG(String s) {
  final String trimmed = s.trim();
  if (trimmed.isEmpty) return null;
  final double? kg = double.tryParse(trimmed);
  if (kg == null) return null;
  return (kg * 1000).round();
}

// ============================================================================
// _ScopeMoverSection (build 20) — ペットを personal / 任意グループ間で移動
// ============================================================================
class _ScopeMoverSection extends ConsumerStatefulWidget {
  const _ScopeMoverSection({required this.petId});

  final int petId;

  @override
  ConsumerState<_ScopeMoverSection> createState() => _ScopeMoverSectionState();
}

class _ScopeMoverSectionState extends ConsumerState<_ScopeMoverSection> {
  bool _isMoving = false;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    final AsyncValue<PetEntity?> petAsync = ref.watch(
      _scopedPetProvider(widget.petId),
    );
    final AsyncValue<List<GroupEntity>> groups = ref.watch(userGroupsProvider);

    return petAsync.when(
      loading: () => const SizedBox(height: 48),
      error: (Object e, _) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          AppLocalizations.of(context).pet_form_scope_load_error(e.toString()),
          style: typo.bodySmall.copyWith(color: colors.accentDanger),
        ),
      ),
      data: (PetEntity? pet) {
        if (pet == null) return const SizedBox.shrink();
        final AppLocalizations l10n = AppLocalizations.of(context);
        final String currentGid = pet.groupId;
        final List<GroupEntity> groupList = groups.maybeWhen(
          data: (List<GroupEntity> v) => v,
          orElse: () => const <GroupEntity>[],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 8),
            Text(
              currentGid == kPersonalGroupId
                  ? l10n.pet_form_scope_current_personal
                  : l10n.pet_form_scope_current_group(
                      _groupName(groupList, currentGid)),
              style: typo.bodySmall
                  .copyWith(color: colors.fgMuted, height: 1.5),
            ),
            const SizedBox(height: 12),
            // Personal 行
            _ScopeRow(
              label: 'Personal',
              note: l10n.pet_form_scope_personal_note,
              isCurrent: currentGid == kPersonalGroupId,
              enabled: !_isMoving && currentGid != kPersonalGroupId,
              onTap: () => _moveTo(context, pet, kPersonalGroupId, 'Personal'),
              colors: colors,
              typo: typo,
            ),
            for (final GroupEntity g in groupList)
              _ScopeRow(
                label: g.name,
                note: l10n.pet_form_scope_group_note,
                isCurrent: currentGid == g.remoteId,
                enabled: !_isMoving && currentGid != g.remoteId,
                onTap: () => _moveTo(context, pet, g.remoteId, g.name),
                colors: colors,
                typo: typo,
              ),
            if (_isMoving)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Text(
              l10n.pet_form_scope_move_note,
              style: typo.bodySmall.copyWith(color: colors.fgFaint, height: 1.5),
            ),
          ],
        );
      },
    );
  }

  String _groupName(List<GroupEntity> list, String gid) {
    for (final GroupEntity g in list) {
      if (g.remoteId == gid) return g.name;
    }
    return gid; // fallback
  }

  Future<void> _moveTo(
    BuildContext context,
    PetEntity pet,
    String targetGid,
    String label,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isToPersonal = targetGid == kPersonalGroupId;
    final String title = isToPersonal
        ? l10n.pet_form_scope_move_to_personal_title
        : l10n.pet_form_scope_move_to_group_title(label);
    final String body = isToPersonal
        ? l10n.pet_form_scope_move_to_personal_body(pet.name)
        : l10n.pet_form_scope_move_to_group_body(pet.name, label);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(isToPersonal
                ? l10n.pet_form_scope_action_unshare
                : l10n.pet_form_scope_action_share),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isMoving = true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      // ignore: deprecated_member_use_from_same_package
      // build 45: G4b で _ScopeMoverSection を「共有先一覧」セクションに転換
      // する際、本呼び出しは addPetScope / removePetScope に置換予定。
      final int n = await ref
          .read(petsRepositoryProvider)
          .movePetToGroup(pet.id, targetGid);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(isToPersonal
              ? l10n.pet_form_scope_move_to_personal_success(pet.name, n)
              : l10n.pet_form_scope_move_to_group_success(pet.name, label, n)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content:
              Text(l10n.pet_form_scope_move_failed(e.toString())),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isMoving = false);
    }
  }
}

/// このペットの最新状態だけを watch する provider。
/// (currentPetProvider は「現在選択中のペット」を返すので、編集対象が
///  current でない場合や、移動直後の自動切替などを起こさないよう専用に分ける)
final StreamProviderFamily<PetEntity?, int> _scopedPetProvider =
    StreamProvider.family<PetEntity?, int>(
  (Ref ref, int petId) {
    final PetsRepository repo = ref.watch(petsRepositoryProvider);
    return repo.watchPet(petId);
  },
);

class _ScopeRow extends StatelessWidget {
  const _ScopeRow({
    required this.label,
    required this.note,
    required this.isCurrent,
    required this.enabled,
    required this.onTap,
    required this.colors,
    required this.typo,
  });

  final String label;
  final String note;
  final bool isCurrent;
  final bool enabled;
  final VoidCallback onTap;
  final AppColors colors;
  final AppTypography typo;

  @override
  Widget build(BuildContext context) {
    final Color titleColor = enabled ? colors.fg : colors.fgFaint;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.line)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        label,
                        style: typo.bodyLarge.copyWith(color: titleColor),
                      ),
                      if (isCurrent) ...<Widget>[
                        const SizedBox(width: 8),
                        Text(
                          'CURRENT',
                          style: TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 9,
                            letterSpacing: 9 * 0.18,
                            color: colors.fgMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    note,
                    style:
                        typo.bodySmall.copyWith(color: colors.fgMuted, height: 1.5),
                  ),
                ],
              ),
            ),
            if (enabled) Icon(Icons.chevron_right, size: 18, color: colors.fgMuted),
          ],
        ),
      ),
    );
  }
}
