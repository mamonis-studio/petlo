// ============================================================================
// petlo - Scope Providers (rev5.1 + rev5.3)
// ============================================================================
//
// petlo は 「グループ → ペット」 の2階層スコープを持つ。
// アプリ全体の状態は以下3つで決まる:
//
//   currentGroupId : 'personal' | <group_uuid>
//   currentPetId   : <pet_id> | 'all'
//   currentRole    : Owner / Editor / Viewer  (Personalは常にOwner)
//
// すべての画面はこれらをwatchして、自動的に画面内容を切り替える。
//
// 永続化:
//   SharedPreferencesに保存、起動時に復元。
//   未保存時は ('personal', 未選択, owner) で開始。
//
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/logger.dart';
import '../../data/local/database_enums.dart';
import 'storage_providers.dart';

// ============================================================================
// 定数
// ============================================================================

/// Personal スコープを表す予約済み groupId。
const String kPersonalGroupId = 'personal';

/// 「全ペット」を表す予約済み petId (Home画面の "All pets" モード)。
const String kAllPetsId = 'all';

// ============================================================================
// 1. currentGroupId
// ============================================================================

/// 現在選択中のスコープ (グループ or Personal)。
///
/// 値は 'personal' か group_uuid 文字列。
/// state 変更時に SharedPreferences に永続化する。
final NotifierProvider<CurrentGroupIdNotifier, String> currentGroupIdProvider =
    NotifierProvider<CurrentGroupIdNotifier, String>(
  CurrentGroupIdNotifier.new,
);

class CurrentGroupIdNotifier extends Notifier<String> {
  @override
  String build() {
    // 起動直後はPersonal、SharedPreferencesからの読み込みは
    // _restoreFromPrefs() で非同期に行う(画面表示後に切り替わる)
    _restoreFromPrefs();
    return kPersonalGroupId;
  }

  Future<void> _restoreFromPrefs() async {
    try {
      final SharedPreferencesAsync prefs =
          ref.read(sharedPreferencesProvider);
      final String? saved = await prefs.getString(PrefsKeys.currentGroupId);
      if (saved != null && saved != state) {
        state = saved;
      }
    } catch (e, st) {
      PetloLogger.instance.w('Failed to restore currentGroupId', error: e, stackTrace: st);
    }
  }

  /// グループ切替。currentPetId は呼び出し側で再選択する想定
  /// (グループ切替時は最後に見ていたペット、なければ先頭、なければ未選択)。
  Future<void> switchTo(String groupId) async {
    if (state == groupId) return;
    state = groupId;
    await _save();
  }

  /// Personalに戻す
  Future<void> switchToPersonal() => switchTo(kPersonalGroupId);

  Future<void> _save() async {
    try {
      final SharedPreferencesAsync prefs =
          ref.read(sharedPreferencesProvider);
      await prefs.setString(PrefsKeys.currentGroupId, state);
    } catch (e, st) {
      PetloLogger.instance.w('Failed to persist currentGroupId', error: e, stackTrace: st);
    }
  }

  /// 現在Personalかどうか
  bool get isPersonal => state == kPersonalGroupId;
}

// ============================================================================
// 2. currentPetId
// ============================================================================

/// 現在選択中のペット。
/// 値は pet_id (int) を String 化したもの、または 'all' (Home画面 "All pets" モード)、
/// または null (未選択 = ペット未登録)。
///
/// グループ切替時には外部から null にリセット → 該当グループのペット一覧を取得 → デフォルト選択、
/// というフローを別 Provider (Chunk 6 の pet_selector_controller) で実装する。
final NotifierProvider<CurrentPetIdNotifier, String?> currentPetIdProvider =
    NotifierProvider<CurrentPetIdNotifier, String?>(
  CurrentPetIdNotifier.new,
);

class CurrentPetIdNotifier extends Notifier<String?> {
  @override
  String? build() {
    _restoreFromPrefs();
    return null;
  }

  Future<void> _restoreFromPrefs() async {
    try {
      final SharedPreferencesAsync prefs =
          ref.read(sharedPreferencesProvider);
      final String? saved = await prefs.getString(PrefsKeys.currentPetId);
      if (saved != null && saved != state) {
        state = saved;
      }
    } catch (e, st) {
      PetloLogger.instance.w('Failed to restore currentPetId', error: e, stackTrace: st);
    }
  }

  /// ペット切替。引数はペットID (int) または null (未選択)
  Future<void> selectPet(int? petId) async {
    final String? newValue = petId?.toString();
    if (state == newValue) return;
    state = newValue;
    await _save();
  }

  /// "All pets" モードへ
  Future<void> selectAll() async {
    if (state == kAllPetsId) return;
    state = kAllPetsId;
    await _save();
  }

  /// 未選択にする (グループ切替時の一時状態)
  Future<void> clear() async {
    state = null;
    await _save();
  }

  Future<void> _save() async {
    try {
      final SharedPreferencesAsync prefs =
          ref.read(sharedPreferencesProvider);
      if (state == null) {
        await prefs.remove(PrefsKeys.currentPetId);
      } else {
        await prefs.setString(PrefsKeys.currentPetId, state!);
      }
    } catch (e, st) {
      PetloLogger.instance.w('Failed to persist currentPetId', error: e, stackTrace: st);
    }
  }

  /// "All pets"モードかどうか
  bool get isAllPetsMode => state == kAllPetsId;

  /// 単一ペット選択中の場合、そのペットIDをintで取得
  int? get singlePetIdOrNull {
    if (state == null || state == kAllPetsId) return null;
    return int.tryParse(state!);
  }
}

// ============================================================================
// 3. currentRole (rev5.3)
// ============================================================================

/// 現在のグループ内での自分の権限。
/// Personal時は常に owner。
/// グループ参加時は groups.myPermission の値が反映される。
///
/// 切り替えロジック:
///   - currentGroupId が変わった時にRepositoryから取得して更新
///   - サーバー側で権限変更があった時にも更新
///
/// 注: このProviderは一旦「Personal時 = owner」のシンプルな実装で開始。
///     共有グループ実装時 (Chunk 7) に上書きする。
final NotifierProvider<CurrentRoleNotifier, MemberPermission>
    currentRoleProvider = NotifierProvider<CurrentRoleNotifier, MemberPermission>(
  CurrentRoleNotifier.new,
);

class CurrentRoleNotifier extends Notifier<MemberPermission> {
  @override
  MemberPermission build() {
    // Personal時はowner
    final String groupId = ref.watch(currentGroupIdProvider);
    if (groupId == kPersonalGroupId) {
      return MemberPermission.owner;
    }
    // 共有グループ時は Chunk 7 で実装
    return MemberPermission.viewer; // 安全側のデフォルト
  }

  /// 共有グループ時に権限を明示更新するための公開API
  void update(MemberPermission permission) {
    state = permission;
    // 永続化はオプション (キャッシュ)
    _save();
  }

  Future<void> _save() async {
    try {
      final SharedPreferencesAsync prefs =
          ref.read(sharedPreferencesProvider);
      await prefs.setString(PrefsKeys.currentRole, state.name);
    } catch (e, st) {
      PetloLogger.instance.w('Failed to persist currentRole', error: e, stackTrace: st);
    }
  }
}

// ============================================================================
// 派生Provider: 権限に基づくUI判定
// ============================================================================

/// 編集権限があるか (Owner or Editor)。
/// Viewer権限のメンバーには記録ボタンを非表示にする等で使う (rev5.3 §4.3)。
final Provider<bool> canEditProvider = Provider<bool>(
  (Ref ref) {
    final MemberPermission role = ref.watch(currentRoleProvider);
    return role == MemberPermission.owner || role == MemberPermission.editor;
  },
);

/// オーナー権限があるか。
/// メンバー除名、招待コード発行等のオーナー専用機能の表示判定。
final Provider<bool> isOwnerProvider = Provider<bool>(
  (Ref ref) {
    final MemberPermission role = ref.watch(currentRoleProvider);
    return role == MemberPermission.owner;
  },
);

/// 現在Personalスコープか (共有なし、ローカルのみ)
final Provider<bool> isPersonalScopeProvider = Provider<bool>(
  (Ref ref) {
    final String groupId = ref.watch(currentGroupIdProvider);
    return groupId == kPersonalGroupId;
  },
);

// ============================================================================
// デバッグ用 (本番では削除可能)
// ============================================================================

@visibleForTesting
ProviderContainer createTestContainer({
  String currentGroupId = kPersonalGroupId,
  String? currentPetId,
  MemberPermission currentRole = MemberPermission.owner,
}) {
  // テスト時のScope override設定の便利関数
  // 実装はテストファイル側で
  throw UnimplementedError('Use override directly in tests');
}
