// ============================================================================
// petlo - Auto Select First Pet helper (build 7-8)
// ============================================================================
//
// ホーム / きろく / みまもる の3タブでは All Pets ピルを出さず、
// 個別ペットを強制選択する。タブ表示時に currentPetId が kAllPetsId なら
// 自動的に最初のペットに切り替える。
//
// build 8 修正: IndexedStack で全タブが alive のため、よていタブで
// All Pets を選ぶと他タブの hook が反応して即座に上書きされる問題があった。
// `forTab` を受け取り、現在のタブと一致する場合のみ実行する。
//
// ============================================================================

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/app_database.dart';
import '../../providers/pet_selection_controller.dart';
import '../../providers/pets_providers.dart';
import '../../providers/scope_providers.dart';
import '../../providers/tab_provider.dart';

/// 現在 currentPetId が All Pets を指していれば、最初のペットに自動切替。
/// 0匹のときは何もしない。
/// `forTab` がアクティブタブと一致しない場合は何もしない
/// (IndexedStack で全タブが build されるため必須)。
void autoSelectFirstPetIfAllSelected(WidgetRef ref, {required AppTab forTab}) {
  final AppTab activeTab = ref.read(currentTabProvider);
  if (activeTab != forTab) return;

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
