// ============================================================================
// petlo - Onboarding Pet Form Page
// ============================================================================
//
// オンボーディング中のペット登録(簡易版)。
// 名前 / 種類 / 誕生日(任意)のみ。詳細は後から編集画面で。
//
// breed/sex/neutered などはデフォルト値で登録、
// ユーザーは後でペット編集画面で詳細を埋められる。
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_service.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/widgets/eyebrow_text.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../data/local/database_enums.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../providers/pets_providers.dart';
import '../../../providers/pro_status_provider.dart';
import '../../../providers/schedules_providers.dart';
import '../../../providers/scope_providers.dart';
import '../../paywall/paywall_screen.dart';
import '../../../widgets/forms/date_field.dart';
import '../../../widgets/forms/editorial_text_field.dart';

class OnboardingPetFormPage extends ConsumerStatefulWidget {
  const OnboardingPetFormPage({
    required this.onNext,
    required this.onSkip,
    super.key,
  });

  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  ConsumerState<OnboardingPetFormPage> createState() =>
      _OnboardingPetFormPageState();
}

class _OnboardingPetFormPageState
    extends ConsumerState<OnboardingPetFormPage> {
  late final TextEditingController _nameC;
  PetType? _selectedType;
  DateTime? _birthday;
  bool _isSubmitting = false;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _nameC = TextEditingController();
  }

  @override
  void dispose() {
    _nameC.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    if (_isSubmitting) return;

    final AppLocalizations l10n = AppLocalizations.of(context);
    final String name = _nameC.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = l10n.pet_validation_name_required);
      return;
    }
    if (name.length > 50) {
      setState(() => _nameError = l10n.create_group_validation_name_max);
      return;
    }
    if (_selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
              content: Text(AppLocalizations.of(context).onboarding_pet_form_select_type),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // build 71: onboarding 経路でも Free 上限を尊重する。通常 onboarding は
    // 「ペット 0 件 → 1 件目作成」なので非ブロックだが、再 onboarding 等の
    // 経路で既に 1 件保持しているケースを防ぐ defensive gate。
    if (!ref.read(isProProvider)) {
      try {
        final int activeCount =
            await ref.read(petsRepositoryProvider).countActivePets();
        if (activeCount >= AppConstants.freeMaxPets) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).pro_limit_pet),
              behavior: SnackBarBehavior.floating,
            ),
          );
          await PaywallScreen.push(context);
          return;
        }
      } catch (e, st) {
        PetloLogger.instance.w(
          'pet count check failed in onboarding',
          error: e,
          stackTrace: st,
        );
      }
    }

    setState(() {
      _isSubmitting = true;
      _nameError = null;
    });

    try {
      final int petId = await ref.read(petsRepositoryProvider).createPet(
            groupId: kPersonalGroupId,
            name: name,
            type: _selectedType!,
            breed: '', // 後から編集
            sex: PetSex.unknown,
            birthday: _birthday?.millisecondsSinceEpoch,
            // build 60: 登録者の user_id を記録 (v1.1 ガード用の土台)。
            createdBy: AuthService.instance.userId,
          );

      // 誕生日 schedule 自動同期
      if (_birthday != null) {
        try {
          await ref.read(schedulesRepositoryProvider).upsertBirthdaySchedule(
                groupId: kPersonalGroupId,
                petId: petId,
                petName: name,
                birthdayMsec: _birthday!.millisecondsSinceEpoch,
                birthdaySuffix: l10n.onboarding_pet_birthday_suffix,
              );
        } catch (e, st) {
          PetloLogger.instance.w('upsert birthday schedule failed',
              error: e, stackTrace: st);
        }
      }

      if (!mounted) return;
      widget.onNext();
    } catch (e, st) {
      PetloLogger.instance
          .w('createPet failed in onboarding', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
              content: Text(AppLocalizations.of(context).onboarding_pet_form_register_failed),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionLabel(
            l10n.onboarding_petform_eyebrow,
            size: EyebrowSize.large,
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
          ),
          Text(
            l10n.onboarding_petform_body,
            style: typo.bodyMedium
                .copyWith(color: colors.fgMuted, height: 1.5),
          ),
          const SizedBox(height: 20),

          // ===== 名前 =====
          EditorialTextField(
            label: l10n.onboarding_petform_name_label,
            controller: _nameC,
            hint: l10n.onboarding_petform_name_hint,
            required: true,
            maxLength: 50,
            errorText: _nameError,
            onChanged: (_) {
              if (_nameError != null) {
                setState(() => _nameError = null);
              }
            },
          ),
          const SizedBox(height: 24),

          // ===== 種類 (Dog / Cat) =====
          Text(
            l10n.onboarding_petform_type_label,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 11,
              color: colors.fgMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: _TypePill(
                  label: l10n.pet_type_dog,
                  selected: _selectedType == PetType.dog,
                  onTap: () =>
                      setState(() => _selectedType = PetType.dog),
                  colors: colors,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TypePill(
                  label: l10n.pet_type_cat,
                  selected: _selectedType == PetType.cat,
                  onTap: () =>
                      setState(() => _selectedType = PetType.cat),
                  colors: colors,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ===== 誕生日 (任意) =====
          DateField(
            label: l10n.onboarding_petform_birthday_label,
            value: _birthday,
            onChanged: (DateTime? d) => setState(() => _birthday = d),
          ),
          const SizedBox(height: 32),

          // ===== CTA =====
          _PrimaryCta(
            label: _isSubmitting
                ? l10n.common_saving
                : l10n.onboarding_petform_cta,
            enabled: !_isSubmitting,
            onTap: _onSubmit,
            colors: colors,
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _isSubmitting ? null : widget.onSkip,
              child: Text(
                l10n.onboarding_petform_skip,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 13,
                  color: colors.fgMuted,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// _TypePill - Dog / Cat 選択
// ============================================================================
class _TypePill extends StatelessWidget {
  const _TypePill({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.fg : colors.bg,
          border: Border.all(
            color: colors.fg,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Fraunces',
            fontStyle: FontStyle.italic,
            fontSize: 22,
            color: selected ? colors.bg : colors.fg,
          ),
        ),
      ),
    );
  }
}

class _PrimaryCta extends StatelessWidget {
  const _PrimaryCta({
    required this.label,
    required this.enabled,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? colors.fg : colors.bgSoft,
          border: Border.all(
            color: enabled ? colors.fg : colors.line,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            color: enabled ? colors.bg : colors.fgFaint,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

