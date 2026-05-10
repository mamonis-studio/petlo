// ============================================================================
// petlo - Group Members & Invite Codes Providers
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/group_members_repository.dart';
import '../../data/repositories/invite_codes_repository.dart';
import 'database_provider.dart';

// ============================================================================
// Group Members
// ============================================================================
final Provider<GroupMembersRepository> groupMembersRepositoryProvider =
    Provider<GroupMembersRepository>(
  (Ref ref) => GroupMembersRepository(ref.watch(appDatabaseProvider)),
);

/// 指定グループの全メンバー Stream
final StreamProviderFamily<List<GroupMemberEntity>, String>
    membersForGroupProvider =
    StreamProviderFamily<List<GroupMemberEntity>, String>(
  (Ref ref, String groupRemoteId) =>
      ref.watch(groupMembersRepositoryProvider)
          .watchMembersForGroup(groupRemoteId),
);

// ============================================================================
// Invite Codes
// ============================================================================
final Provider<InviteCodesRepository> inviteCodesRepositoryProvider =
    Provider<InviteCodesRepository>(
  (Ref ref) => InviteCodesRepository(ref.watch(appDatabaseProvider)),
);

/// 指定グループの active な招待コード Stream
final StreamProviderFamily<List<InviteCodeEntity>, String>
    activeInviteCodesForGroupProvider =
    StreamProviderFamily<List<InviteCodeEntity>, String>(
  (Ref ref, String groupRemoteId) =>
      ref.watch(inviteCodesRepositoryProvider)
          .watchActiveCodesForGroup(groupRemoteId),
);
