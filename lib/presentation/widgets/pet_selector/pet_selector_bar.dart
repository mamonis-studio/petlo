// ============================================================================
// petlo - PetSelectorBar
// ============================================================================
//
// rev5.1 F-00 実装。全画面共通のペットセレクターバー。
//
// 構成 (左から右へ):
//   [All pets] [Pet1] [Pet2] [Pet3] ... [+ Add]
//
// 状態:
//   - currentPetIdProvider と双方向連動
//   - currentGroupPetsProvider のペット一覧を表示
//   - グループ切替時は petSelectionController が自動でフォールバック
//
// アクセシビリティ:
//   - 各ピルにSemantics (selected, button, label)
//   - スクロール可能領域を1つのリストとして扱う
//
// "All pets" ピルの表示条件 (rev5.1 F-00b):
//   - ペット2匹以上のときのみ表示
//   - "All pets" は Home 画面の集約表示専用、他画面では利用不可
//   - showAllPets=false で個別画面から無効化可能
//
// "+" 追加ピルの表示:
//   - canEdit=true のときのみ表示 (Viewer権限では非表示、rev5.3)
//   - タップで pet_registration 画面へ (Chunk 8で実装、ここではコールバック)
//
// 0匹時:
//   - PetSelectorEmptyState を表示 (バー自体を出さない選択もある)
//   - 詳細は PetloScaffold 側で判定、このWidgetは「ペット>0」前提
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../data/local/app_database.dart';
import '../../providers/pet_selection_controller.dart';
import '../../providers/pets_providers.dart';
import '../../providers/scope_providers.dart';
import 'pet_selector_pill.dart';

class PetSelectorBar extends ConsumerWidget {
  const PetSelectorBar({
    this.showAllPets = true,
    this.onAddPetTapped,
    super.key,
  });

  /// "All pets" ピルを表示するか (Home画面のみtrue、それ以外false推奨)
  final bool showAllPets;

  /// "+" 追加ピル押下時のコールバック (Chunk 8で本実装と接続)
  final VoidCallback? onAddPetTapped;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AsyncValue<List<PetEntity>> petsAsync =
        ref.watch(currentGroupPetsProvider);
    final String? currentPetIdStr = ref.watch(currentPetIdProvider);
    final bool canEdit = ref.watch(canEditProvider);

    return Container(
      height: AppDimensions.petSelectorHeight,
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: petsAsync.when(
        loading: () => const _LoadingPlaceholder(),
        error: (Object e, StackTrace st) => _ErrorPlaceholder(error: e),
        data: (List<PetEntity> pets) => _buildBar(
          context: context,
          ref: ref,
          pets: pets,
          currentPetIdStr: currentPetIdStr,
          canEdit: canEdit,
        ),
      ),
    );
  }

  Widget _buildBar({
    required BuildContext context,
    required WidgetRef ref,
    required List<PetEntity> pets,
    required String? currentPetIdStr,
    required bool canEdit,
  }) {
    if (pets.isEmpty) {
      // ペット0匹 → エンプティステート (PetloScaffold側でも処理可能)
      return PetSelectorEmptyState(
        canCreate: canEdit,
        onAddPetTapped: onAddPetTapped,
      );
    }

    final PetSelectionController controller =
        ref.read(petSelectionControllerProvider.notifier);

    final bool showAllPill = showAllPets && pets.length >= 2;
    final bool isAllSelected = currentPetIdStr == kAllPetsId;

    return Semantics(
      explicitChildNodes: true,
      label: AppLocalizations.of(context).pet_selector_a11y_label,
      // ListView でフルワイド横スクロール。先頭・末尾に余白を入れて
      // 最初・最後のピルが画面端で見切れて見えるようにする。
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: <Widget>[
          if (showAllPill)
            PetSelectorPill.allPets(
              petCount: pets.length,
              isActive: isAllSelected,
              onTap: controller.selectAll,
            ),
          for (final PetEntity pet in pets)
            PetSelectorPill.pet(
              name: pet.name,
              petType: pet.type,
              breedDisplay: pet.breed ?? '',
              petAgeYears: _calculateAgeYears(pet.birthday),
              isActive:
                  !isAllSelected && currentPetIdStr == pet.id.toString(),
              relativePhotoPath: pet.photoPath,
              onTap: () => controller.selectPet(pet.id),
            ),
          if (canEdit && onAddPetTapped != null)
            PetSelectorPill.add(onTap: onAddPetTapped!),
        ],
      ),
    );
  }

  /// 誕生日 (UTC msec) から年齢 (年) を計算。
  /// 1歳未満は 0 を返す (UI側で「8mo」のような月齢表示が望ましいが、Chunk 8の課題)。
  static int? _calculateAgeYears(int? birthdayMsec) {
    if (birthdayMsec == null) return null;
    final DateTime birthday =
        DateTime.fromMillisecondsSinceEpoch(birthdayMsec);
    final DateTime now = DateTime.now();
    int years = now.year - birthday.year;
    final bool hasNotHadBirthdayThisYear = now.month < birthday.month ||
        (now.month == birthday.month && now.day < birthday.day);
    if (hasNotHadBirthdayThisYear) {
      years -= 1;
    }
    return years.clamp(0, 50);
  }
}

// ============================================================================
// 0匹時のエンプティステート
// ============================================================================

class PetSelectorEmptyState extends StatelessWidget {
  const PetSelectorEmptyState({
    required this.canCreate,
    required this.onAddPetTapped,
    super.key,
  });

  final bool canCreate;
  final VoidCallback? onAddPetTapped;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (canCreate && onAddPetTapped != null)
            PetSelectorPill.add(onTap: onAddPetTapped!)
          else
            Text(
              AppLocalizations.of(context).pet_selector_no_pets,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w400,
                fontSize: 13,
                color: colors.fgMuted,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// Loading / Error
// ============================================================================

class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    // 静かなプレースホルダー (スピナー出さない、petloの落ち着いたトーン)
    return const SizedBox.shrink();
  }
}

class _ErrorPlaceholder extends StatelessWidget {
  const _ErrorPlaceholder({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Center(
        child: Text(
          'Pet list unavailable',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 12,
            color: colors.accentDanger,
          ),
        ),
      ),
    );
  }
}
