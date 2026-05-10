// ============================================================================
// petlo - Group Selection Controller
// ============================================================================
//
// グループ選択に関するロジックを集約。
//
//   1. ユーザーがグループを選んだ時の切替処理
//   2. 切替後の権限同期 (currentRoleProvider 更新)
//   3. グループ参加・退出のフロー
//
// rev5.3: グループ切替時はクロスフェード 0.4秒 (AppDurations.groupSwitch)
// rev5.4: lastActiveAt 更新 (オーナー30日不在検知)
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/logger.dart';
import '../../data/local/app_database.dart';
import '../../data/local/database_enums.dart';
import 'groups_providers.dart';
import 'scope_providers.dart';

final NotifierProvider<GroupSelectionController, void>
    groupSelectionControllerProvider =
    NotifierProvider<GroupSelectionController, void>(
  GroupSelectionController.new,
);

class GroupSelectionController extends Notifier<void> {
  @override
  void build() {
    // currentGroupId 変化を検知して権限を同期
    ref.listen<String>(
      currentGroupIdProvider,
      (String? previous, String next) {
        if (previous != next) {
          PetloLogger.instance.i('Group changed: $previous -> $next, syncing role');
          _syncRoleForGroup(next);
        }
      },
    );

    // 起動時にも一度同期
    Future<void>.microtask(() {
      final String current = ref.read(currentGroupIdProvider);
      _syncRoleForGroup(current);
    });
  }

  // ============================================================================
  // Public actions
  // ============================================================================

  /// グループを切り替える (Personal も含む)。
  /// 自動的に権限・ペット選択も連動する。
  Future<void> switchTo(String groupId) async {
    await ref.read(currentGroupIdProvider.notifier).switchTo(groupId);

    // 共有グループの場合は lastActiveAt を更新 (オーナー不在検知用、rev5.4)
    if (groupId != kPersonalGroupId) {
      try {
        final repo = ref.read(groupsRepositoryProvider);
        await repo.touchLastActive(groupId);
      } catch (e, st) {
        PetloLogger.instance
            .w('Failed to touch lastActiveAt', error: e, stackTrace: st);
      }
    }
  }

  /// Personal に戻す
  Future<void> switchToPersonal() => switchTo(kPersonalGroupId);

  // ============================================================================
  // Internal: 権限同期
  // ============================================================================

  Future<void> _syncRoleForGroup(String groupId) async {
    if (groupId == kPersonalGroupId) {
      // Personal は常に owner
      ref.read(currentRoleProvider.notifier).update(MemberPermission.owner);
      return;
    }

    try {
      final repo = ref.read(groupsRepositoryProvider);
      final GroupEntity? group = await repo.getGroupByRemoteId(groupId);
      if (group != null) {
        ref.read(currentRoleProvider.notifier).update(group.myPermission);
      } else {
        // ローカルキャッシュにグループがない → 安全側 viewer
        PetloLogger.instance
            .w('Group not in local cache: $groupId, defaulting to viewer');
        ref.read(currentRoleProvider.notifier).update(MemberPermission.viewer);
      }
    } catch (e, st) {
      PetloLogger.instance
          .w('Failed to sync role', error: e, stackTrace: st);
      // 失敗時は安全側
      ref.read(currentRoleProvider.notifier).update(MemberPermission.viewer);
    }
  }
}
