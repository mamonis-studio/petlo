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
import '../../../core/utils/logger.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/section_label.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_enums.dart';
import '../../providers/groups_providers.dart';
import '../../providers/pet_scopes_providers.dart';
import '../../providers/pets_providers.dart';
import '../../providers/scope_providers.dart';
import '../../widgets/dialogs/duplicate_name_dialog.dart';
import '../groups/pet_share_picker.dart';
import '../../widgets/forms/date_field.dart';
import '../../widgets/forms/editorial_text_field.dart';
import '../../widgets/forms/pet_photo_picker.dart';
import '../../widgets/forms/segmented_selector.dart';
import '../../widgets/forms/tag_input_field.dart';
import '../paywall/paywall_screen.dart';
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
                // build 20: 編集時のみスコープ管理 UI を出す。
                // build 46 (Phase G4b): 「移動」モデルから「共有先一覧」モデルに転換。
                // 旧 _ScopeMoverSection の代わりに _PetScopesSection を表示する。
                if (s.isEditing && widget.editingPetId != null) ...<Widget>[
                  const SizedBox(height: AppDimensions.paddingSection),
                  SectionLabel(
                      AppLocalizations.of(context).pet_share_section_title),
                  _PetScopesSection(petId: widget.editingPetId!),
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

              // build 47 (Scope A1): 編集時のみ「お別れ」「完全削除」を表示。
              // 新規ペット作成画面では出さない (まだ保存していないので意味がない)。
              if (s.isEditing && widget.editingPetId != null) ...<Widget>[
                const SizedBox(height: AppDimensions.paddingSection * 2),
                _PetLifecycleSection(petId: widget.editingPetId!),
              ],
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

      case PetFormSaveOutcome.proLimitReached:
        if (mounted) {
          final AppLocalizations l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.pro_limit_pet),
              behavior: SnackBarBehavior.floating,
            ),
          );
          await PaywallScreen.push(context);
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
// _PetScopesSection (Phase G4b, build 46)
// ============================================================================
//
// 旧 _ScopeMoverSection (build 20-45) を multi-scope 共有先一覧に転換。
// pet の現在の共有先 (pet_scopes 経由) を縦リストで表示し、
//   - primary scope は `Primary` バッジ + 操作不可
//   - 非 primary scope は permission ラベル + 「共有を解除」アクション
//   - 0 件なら hint テキスト
// その下に「共有を追加 / 編集」ボタン → PetSharePicker.showForPet を開く。
//
// ============================================================================
class _PetScopesSection extends ConsumerWidget {
  const _PetScopesSection({required this.petId});

  final int petId;

  String _permissionLabel(MemberPermission p, AppLocalizations l10n) {
    switch (p) {
      case MemberPermission.owner:
        return l10n.pet_share_permission_owner;
      case MemberPermission.editor:
        return l10n.pet_share_permission_editor;
      case MemberPermission.viewer:
        return l10n.pet_share_permission_viewer;
    }
  }

  String _groupLabel(
    PetScopeEntity scope,
    List<GroupEntity> groups,
  ) {
    if (scope.groupId == kPersonalGroupId) return 'Personal';
    for (final GroupEntity g in groups) {
      if (g.remoteId == scope.groupId) return g.name;
    }
    return scope.groupId;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<PetScopeEntity>> scopesAsync =
        ref.watch(petScopesForPetProvider(petId));
    final AsyncValue<List<GroupEntity>> groupsAsync =
        ref.watch(userGroupsProvider);

    return scopesAsync.when(
      loading: () => const SizedBox(height: 48),
      error: (Object e, _) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          l10n.pet_form_scope_load_error(e.toString()),
          style: typo.bodySmall.copyWith(color: colors.accentDanger),
        ),
      ),
      data: (List<PetScopeEntity> scopes) {
        final List<GroupEntity> groups = groupsAsync.maybeWhen(
          data: (List<GroupEntity> g) => g,
          orElse: () => const <GroupEntity>[],
        );
        final List<PetScopeEntity> live = scopes
            .where((PetScopeEntity s) => s.deletedAt == null)
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 8),
            if (live.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l10n.pet_share_section_hint_empty,
                  style: typo.bodySmall
                      .copyWith(color: colors.fgMuted, height: 1.5),
                ),
              )
            else
              for (final PetScopeEntity s in live)
                _ScopeListRow(
                  petId: petId,
                  scope: s,
                  groupLabel: _groupLabel(s, groups),
                  permissionLabel: _permissionLabel(s.permission, l10n),
                  colors: colors,
                  typo: typo,
                  l10n: l10n,
                ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => PetSharePicker.showForPet(context, petId),
              child: Text(l10n.pet_share_add_action),
            ),
          ],
        );
      },
    );
  }
}

class _ScopeListRow extends ConsumerStatefulWidget {
  const _ScopeListRow({
    required this.petId,
    required this.scope,
    required this.groupLabel,
    required this.permissionLabel,
    required this.colors,
    required this.typo,
    required this.l10n,
  });

  final int petId;
  final PetScopeEntity scope;
  final String groupLabel;
  final String permissionLabel;
  final AppColors colors;
  final AppTypography typo;
  final AppLocalizations l10n;

  @override
  ConsumerState<_ScopeListRow> createState() => _ScopeListRowState();
}

class _ScopeListRowState extends ConsumerState<_ScopeListRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final bool isPrimary = widget.scope.isPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: widget.colors.line)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        widget.groupLabel,
                        style: widget.typo.bodyLarge
                            .copyWith(color: widget.colors.fg),
                      ),
                    ),
                    if (isPrimary) ...<Widget>[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: widget.colors.fgMuted, width: 1),
                        ),
                        child: Text(
                          widget.l10n.pet_share_primary_badge.toUpperCase(),
                          style: TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 8,
                            letterSpacing: 8 * 0.18,
                            color: widget.colors.fgMuted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  widget.permissionLabel,
                  style: widget.typo.bodySmall.copyWith(
                      color: widget.colors.fgMuted, height: 1.5),
                ),
              ],
            ),
          ),
          if (!isPrimary)
            TextButton(
              onPressed: _busy ? null : _confirmUnshare,
              child: Text(widget.l10n.pet_share_unshare_action),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmUnshare() async {
    final PetEntity? pet =
        await ref.read(petsRepositoryProvider).getPet(widget.petId);
    if (!mounted) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final AppLocalizations dl10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(dl10n.pet_share_unshare_confirm_title),
          content: Text(
            dl10n.pet_share_unshare_confirm_body(
              pet?.name ?? '',
              widget.groupLabel,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(dl10n.common_cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(dl10n.pet_share_unshare_action),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(petScopesRepositoryProvider).removePetScope(
            petId: widget.petId,
            groupId: widget.scope.groupId,
          );
    } catch (e, st) {
      PetloLogger.instance
          .w('removePetScope failed', error: e, stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.l10n.pet_share_action_failed),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// ============================================================================
// _PetLifecycleSection (build 47, Scope A1)
// ============================================================================
//
// 編集モードのフォーム末尾に表示する「お別れ」「完全削除」アクションエリア。
// build 47 まで UI から到達できなかった markAsParted / softDeletePet を
// ユーザに開放する。
//
// お別れ (markAsParted): 記録はそのまま残し、命日通知を設定する。
// 完全削除 (softDeletePet): ペット + 紐づく全子レコードを論理削除。
//   30 日以内なら復元可能 (復元 UI は v1.1+ で実装予定)。
//
// ============================================================================
class _PetLifecycleSection extends ConsumerWidget {
  const _PetLifecycleSection({required this.petId});

  final int petId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionLabel(l10n.pet_form_lifecycle_section),
        const SizedBox(height: 16),

        // お別れ
        _LifecycleButton(
          label: l10n.pet_action_part,
          hint: l10n.pet_action_part_hint,
          onPressed: () => _openPartDialog(context, ref),
          colors: colors,
          typo: typo,
          destructive: false,
        ),
        const SizedBox(height: 16),

        // 完全削除
        _LifecycleButton(
          label: l10n.pet_action_delete,
          hint: l10n.pet_action_delete_hint,
          onPressed: () => _openDeleteDialog(context, ref),
          colors: colors,
          typo: typo,
          destructive: true,
        ),
      ],
    );
  }

  Future<void> _openPartDialog(BuildContext context, WidgetRef ref) async {
    final PetEntity? pet =
        await ref.read(petsRepositoryProvider).getPet(petId);
    if (!context.mounted) return;
    if (pet == null) return;

    final ({int partedAtMsec, MemorialNotifyFrequency notify})? result =
        await showDialog<({int partedAtMsec, MemorialNotifyFrequency notify})>(
      context: context,
      builder: (BuildContext dialogContext) =>
          _PartDialog(petName: pet.name),
    );
    if (result == null || !context.mounted) return;

    try {
      await ref.read(petsRepositoryProvider).markAsParted(
            petId: petId,
            partedAtMsec: result.partedAtMsec,
            notify: result.notify,
          );
      if (!context.mounted) return;
      final AppLocalizations l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pet_part_success_snack(pet.name)),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e, st) {
      PetloLogger.instance
          .w('markAsParted failed', error: e, stackTrace: st);
      if (!context.mounted) return;
      final AppLocalizations l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pet_part_failed(e.toString()))),
      );
    }
  }

  Future<void> _openDeleteDialog(BuildContext context, WidgetRef ref) async {
    final PetEntity? pet =
        await ref.read(petsRepositoryProvider).getPet(petId);
    if (!context.mounted) return;
    if (pet == null) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final AppLocalizations dl10n = AppLocalizations.of(dialogContext);
        final AppColors colors = AppColors.of(dialogContext);
        return AlertDialog(
          title: Text(dl10n.pet_delete_confirm_title),
          content: Text(dl10n.pet_delete_confirm_body(pet.name)),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(dl10n.common_cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: colors.accentDanger),
              child: Text(dl10n.pet_delete_action_confirm),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(petsRepositoryProvider).softDeletePet(petId);
      if (!context.mounted) return;
      final AppLocalizations l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pet_delete_success_snack(pet.name))),
      );
      Navigator.of(context).pop(true);
    } catch (e, st) {
      PetloLogger.instance
          .w('softDeletePet failed', error: e, stackTrace: st);
      if (!context.mounted) return;
      final AppLocalizations l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pet_delete_failed(e.toString()))),
      );
    }
  }
}

class _LifecycleButton extends StatelessWidget {
  const _LifecycleButton({
    required this.label,
    required this.hint,
    required this.onPressed,
    required this.colors,
    required this.typo,
    required this.destructive,
  });

  final String label;
  final String hint;
  final VoidCallback onPressed;
  final AppColors colors;
  final AppTypography typo;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final Color fg = destructive ? colors.accentDanger : colors.fg;
    return InkWell(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(color: fg, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: typo.bodyMedium.copyWith(
                color: fg,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hint,
              style: typo.bodySmall.copyWith(
                color: colors.fgMuted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartDialog extends StatefulWidget {
  const _PartDialog({required this.petName});

  final String petName;

  @override
  State<_PartDialog> createState() => _PartDialogState();
}

class _PartDialogState extends State<_PartDialog> {
  late DateTime _date;
  MemorialNotifyFrequency _notify = MemorialNotifyFrequency.monthly;

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
  }

  String _notifyLabel(MemorialNotifyFrequency f, AppLocalizations l10n) {
    switch (f) {
      case MemorialNotifyFrequency.monthly:
        return l10n.pet_memorial_notify_monthly;
      case MemorialNotifyFrequency.yearly:
        return l10n.pet_memorial_notify_yearly;
      case MemorialNotifyFrequency.off:
        return l10n.pet_memorial_notify_none;
    }
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: today,
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    return AlertDialog(
      title: Text(l10n.pet_part_confirm_title),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(l10n.pet_part_confirm_body(widget.petName)),
            const SizedBox(height: 16),

            // 日付
            Text(
              l10n.pet_part_field_date,
              style: typo.bodySmall.copyWith(color: colors.fgMuted),
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: _pickDate,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.line),
                ),
                child: Text(
                  '${_date.year}-${_date.month.toString().padLeft(2, '0')}-'
                  '${_date.day.toString().padLeft(2, '0')}',
                  style: typo.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 通知頻度
            Text(
              l10n.pet_part_field_notify,
              style: typo.bodySmall.copyWith(color: colors.fgMuted),
            ),
            for (final MemorialNotifyFrequency f
                in MemorialNotifyFrequency.values)
              RadioListTile<MemorialNotifyFrequency>(
                title: Text(_notifyLabel(f, l10n)),
                value: f,
                groupValue: _notify,
                contentPadding: EdgeInsets.zero,
                dense: true,
                onChanged: (MemorialNotifyFrequency? v) {
                  if (v != null) setState(() => _notify = v);
                },
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.common_cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            (
              partedAtMsec: _date.millisecondsSinceEpoch,
              notify: _notify,
            ),
          ),
          child: Text(l10n.pet_part_action_confirm),
        ),
      ],
    );
  }
}
