// ============================================================================
// petlo - Auto Select First Pet helper (build 7)
// ============================================================================
//
// ホーム / きろく / みまもる の3タブでは All Pets ピルを出さず、
// 個別ペットを強制選択する。タブ表示時に currentPetId が kAllPetsId なら
// 自動的に最初のペットに切り替える。
//
// PetSelectionController.syncWithCurrentGroup は kAllPets を維持する仕様
// なので、タブ側で明示的に最初のペットへ移すフックを設ける。
//
// ============================================================================

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/app_database.dart';
import '../../providers/pet_selection_controller.dart';
import '../../providers/pets_providers.dart';
import '../../providers/scope_providers.dart';

/// 現在 currentPetId が All Pets を指していれば、最初のペットに自動切替。
/// 0匹のときは何もしない。タブの build 内で呼ぶ想定(safe to call repeatedly)。
void autoSelectFirstPetIfAllSelected(WidgetRef ref) {
  final String? petIdStr = ref.read(currentPetIdProvider);
  if (petIdStr != kAllPetsId) return;

  final List<PetEntity>? pets =
      ref.read(currentGroupPetsProvider).valueOrNull;
  if (pets == null || pets.isEmpty) return;

  final int firstPetId = pets.first.id;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ref.read(petSelectionControllerProvider.notifier).selectPet(firstPetId);
  });
}
