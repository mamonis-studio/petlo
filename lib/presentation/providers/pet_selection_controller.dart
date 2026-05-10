// ============================================================================
// petlo - Pet Selection Controller
// ============================================================================
//
// ペット選択に関する以下のロジックを集約:
//
//   1. ユーザータップでのペット切替 (currentPetIdProvider更新)
//   2. グループ切替時の自動フォールバック:
//      - 該当グループの「最後に見ていたペット」を復元
//      - 復元できなければ先頭のペット
//      - ペット0匹なら未選択のまま
//   3. ペット削除時の自動再選択
//   4. AI画面でのペット切替確認 (rev5.1 F-00d) のためのフラグ管理
//
// rev5.1: ペット中心UI、currentPetIdは全画面共通
// rev5.5: グループ別の「最後ペット」記憶を SharedPreferences に保存
//
// ============================================================================

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/logger.dart';
import '../../data/local/app_database.dart';
import 'pets_providers.dart';
import 'scope_providers.dart';
import 'storage_providers.dart';

/// グループごとの「最後に見ていたペットID」を保存するキー。
/// 例: "last_pet_in_group:personal" → "42"
String _lastPetKey(String groupId) => 'last_pet_in_group:$groupId';

// ============================================================================
// Pet Selection Controller
// ============================================================================

/// ペット切替の単一窓口Provider。
///
/// UIから呼び出せるアクション:
///   - selectPet(petId) — ユーザーがピルをタップ
///   - selectAll() — "All pets" ピルをタップ
///   - syncWithCurrentGroup() — グループ切替時の復元 (内部で呼ばれる)
///
/// グループ切替の検知は `ref.listen(currentGroupIdProvider)` で行う。
final NotifierProvider<PetSelectionController, void>
    petSelectionControllerProvider =
    NotifierProvider<PetSelectionController, void>(
  PetSelectionController.new,
);

class PetSelectionController extends Notifier<void> {
  StreamSubscription<List<PetEntity>>? _petsSub;

  @override
  void build() {
    // グループ切替を検知して、新スコープのペットに自動切替
    ref.listen<String>(
      currentGroupIdProvider,
      (String? previous, String next) {
        if (previous != null && previous != next) {
          PetloLogger.instance
              .i('Group changed: $previous -> $next, syncing pet selection');
          syncWithCurrentGroup();
        }
      },
    );

    // 起動時にも一度同期 (Provider 初期化のタイミングで)
    Future<void>.microtask(syncWithCurrentGroup);

    ref.onDispose(() {
      _petsSub?.cancel();
    });
  }

  // ============================================================================
  // Public actions
  // ============================================================================

  /// 単一ペット選択。SharedPreferencesにも記録 (グループ別)。
  Future<void> selectPet(int petId) async {
    await ref.read(currentPetIdProvider.notifier).selectPet(petId);
    await _rememberPetForCurrentGroup(petId.toString());
  }

  /// "All pets" モード選択。
  Future<void> selectAll() async {
    await ref.read(currentPetIdProvider.notifier).selectAll();
    await _rememberPetForCurrentGroup(kAllPetsId);
  }

  /// グループ切替時の自動復元/フォールバック。
  ///
  /// ロジック:
  ///   1. 「このグループで最後に見ていたペット」を SharedPreferences から取得
  ///   2. それが現存するペット (active) なら選択
  ///   3. なければ先頭のペットを選択
  ///   4. ペット0匹なら未選択 (null) のまま
  Future<void> syncWithCurrentGroup() async {
    final String groupId = ref.read(currentGroupIdProvider);

    // 現在グループのペット一覧を取得 (1回だけ)
    final List<PetEntity> pets =
        await ref.read(currentGroupPetsProvider.future);

    if (pets.isEmpty) {
      await ref.read(currentPetIdProvider.notifier).clear();
      return;
    }

    // 1. 最後に見ていたペットを復元
    final String? remembered = await _recallLastPetForGroup(groupId);
    if (remembered != null) {
      // "all" モードの記憶
      if (remembered == kAllPetsId) {
        await ref.read(currentPetIdProvider.notifier).selectAll();
        return;
      }
      // 単一ペットの記憶 → 現存確認
      final int? rememberedId = int.tryParse(remembered);
      if (rememberedId != null &&
          pets.any((PetEntity p) => p.id == rememberedId)) {
        await ref.read(currentPetIdProvider.notifier).selectPet(rememberedId);
        return;
      }
    }

    // 2. フォールバック: 先頭ペット
    await ref.read(currentPetIdProvider.notifier).selectPet(pets.first.id);
    await _rememberPetForCurrentGroup(pets.first.id.toString());
  }

  /// ペット削除後の自動再選択。
  /// 削除したペットが現在選択中なら、別のペットへ切替。
  Future<void> handlePetDeleted(int deletedPetId) async {
    final String? current = ref.read(currentPetIdProvider);
    if (current == null) return;
    final int? currentId = int.tryParse(current);
    if (currentId != deletedPetId) return;

    // 削除したペットが選択中だった → 残りから選び直す
    await syncWithCurrentGroup();
  }

  // ============================================================================
  // Private: グループ別のペット記憶
  // ============================================================================

  Future<void> _rememberPetForCurrentGroup(String petIdStr) async {
    final String groupId = ref.read(currentGroupIdProvider);
    try {
      final SharedPreferencesAsync prefs =
          ref.read(sharedPreferencesProvider);
      await prefs.setString(_lastPetKey(groupId), petIdStr);
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to remember last pet', error: e, stackTrace: st);
    }
  }

  Future<String?> _recallLastPetForGroup(String groupId) async {
    try {
      final SharedPreferencesAsync prefs =
          ref.read(sharedPreferencesProvider);
      return prefs.getString(_lastPetKey(groupId));
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to recall last pet', error: e, stackTrace: st);
      return null;
    }
  }
}
