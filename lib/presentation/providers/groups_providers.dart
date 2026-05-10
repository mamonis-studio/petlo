// ============================================================================
// petlo - Groups Providers
// ============================================================================
//
// グループ関連のProvider群。
//
// 階層:
//   GroupsRepository → userGroupsProvider → currentGroupProvider (派生)
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/groups_repository.dart';
import 'database_provider.dart';
import 'scope_providers.dart';

// ============================================================================
// Repository本体
// ============================================================================

final Provider<GroupsRepository> groupsRepositoryProvider =
    Provider<GroupsRepository>(
  (Ref ref) {
    final AppDatabase db = ref.watch(appDatabaseProvider);
    return GroupsRepository(db);
  },
);

// ============================================================================
// 自分が参加してる全グループ
// ============================================================================

/// Personal を含まない、共有グループのみ。
/// セレクターのモーダルで一覧表示する用途。
final StreamProvider<List<GroupEntity>> userGroupsProvider =
    StreamProvider<List<GroupEntity>>(
  (Ref ref) {
    final GroupsRepository repo = ref.watch(groupsRepositoryProvider);
    return repo.watchMyActiveGroups();
  },
);

// ============================================================================
// 現在選択中のグループ詳細
// ============================================================================

/// currentGroupId が 'personal' の時は null。
/// グループ uuid の時は対応する GroupEntity を返す。
final StreamProvider<GroupEntity?> currentGroupProvider =
    StreamProvider<GroupEntity?>(
  (Ref ref) {
    final String groupId = ref.watch(currentGroupIdProvider);
    if (groupId == kPersonalGroupId) {
      return Stream<GroupEntity?>.value(null);
    }
    final GroupsRepository repo = ref.watch(groupsRepositoryProvider);
    return repo.watchGroupByRemoteId(groupId);
  },
);

// ============================================================================
// 派生Provider: 「あと何個グループ作れるか」
// ============================================================================

/// rev5.5: ユーザー1人につき最大3グループ。
/// 「+ Create new group」ボタンの活性/非活性判定に使用。
final FutureProvider<int> remainingGroupSlotsProvider = FutureProvider<int>(
  (Ref ref) async {
    final GroupsRepository repo = ref.watch(groupsRepositoryProvider);
    return repo.remainingGroupSlots();
  },
);

// ============================================================================
// Pro解約警告中グループの監視
// ============================================================================

/// pendingDeletion 状態のグループ一覧 (rev5.5 §4.15 警告バナー用)。
final StreamProvider<List<GroupEntity>> pendingDeletionGroupsProvider =
    StreamProvider<List<GroupEntity>>(
  (Ref ref) {
    final GroupsRepository repo = ref.watch(groupsRepositoryProvider);
    return repo.watchPendingDeletionGroups();
  },
);
