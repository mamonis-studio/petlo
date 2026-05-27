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
    // build 27: currentRoleProvider が drift から自動派生になったため
    // ここでの手動 sync は不要 (削除)。
    // switchTo / switchToPersonal は引き続き提供。
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

}
