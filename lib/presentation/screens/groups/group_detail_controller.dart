// ============================================================================
// petlo - Group Detail Controller
// ============================================================================
//
// グループ詳細画面のアクション(招待コード発行 / メンバー権限変更 / 除名 / 退出)。
//
// rev5.3 F-25 / F-29a / F-29b / F-30
//
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/groups/group_api_dtos.dart';
import '../../../core/groups/group_api_exceptions.dart';
import '../../../core/groups/group_api_service.dart';
import '../../../core/utils/logger.dart';
import '../../../data/local/database_enums.dart';
import '../../providers/group_api_service_provider.dart';
import '../../providers/group_members_providers.dart';
import '../../providers/groups_providers.dart';

@immutable
class GroupDetailState {
  const GroupDetailState({
    this.isIssuingInvite = false,
    this.isUpdatingMember = false,
    this.isLeaving = false,
    this.lastIssuedCode,
    this.errorMessage,
  });

  final bool isIssuingInvite;
  final bool isUpdatingMember;
  final bool isLeaving;
  final CreateInviteResultDto? lastIssuedCode;
  final String? errorMessage;

  GroupDetailState copyWith({
    bool? isIssuingInvite,
    bool? isUpdatingMember,
    bool? isLeaving,
    Object? lastIssuedCode = _sentinel,
    Object? errorMessage = _sentinel,
  }) {
    return GroupDetailState(
      isIssuingInvite: isIssuingInvite ?? this.isIssuingInvite,
      isUpdatingMember: isUpdatingMember ?? this.isUpdatingMember,
      isLeaving: isLeaving ?? this.isLeaving,
      lastIssuedCode: lastIssuedCode == _sentinel
          ? this.lastIssuedCode
          : lastIssuedCode as CreateInviteResultDto?,
      errorMessage: errorMessage == _sentinel
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  static const Object _sentinel = Object();
}

final NotifierProviderFamily<GroupDetailController, GroupDetailState, String>
    groupDetailControllerProvider = NotifierProviderFamily<
        GroupDetailController, GroupDetailState, String>(
  GroupDetailController.new,
);

class GroupDetailController
    extends FamilyNotifier<GroupDetailState, String> {
  @override
  GroupDetailState build(String groupRemoteId) {
    return const GroupDetailState();
  }

  void clearLastIssuedCode() {
    state = state.copyWith(lastIssuedCode: null);
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  // ==========================================================================
  // 招待コード発行
  // ==========================================================================
  Future<CreateInviteResultDto?> issueInvite(
      MemberPermission permission) async {
    if (state.isIssuingInvite) return null;
    state = state.copyWith(
      isIssuingInvite: true,
      errorMessage: null,
    );

    try {
      final GroupApiService api = ref.read(groupApiServiceProvider);
      final CreateInviteResultDto result = await api.createInvite(
        groupRemoteId: arg,
        grantedPermission: permission,
      );

      // ローカルDBに保存
      await ref.read(inviteCodesRepositoryProvider).insertCode(
            code: result.code,
            groupRemoteId: arg,
            grantedPermission: result.grantedPermission,
            issuedAt: DateTime.now().millisecondsSinceEpoch,
            expiresAt: result.expiresAt.millisecondsSinceEpoch,
          );

      state = state.copyWith(
        isIssuingInvite: false,
        lastIssuedCode: result,
      );
      return result;
    } on GroupApiException catch (e) {
      state = state.copyWith(
        isIssuingInvite: false,
        errorMessage: e.message,
      );
      return null;
    } catch (e, st) {
      PetloLogger.instance
          .w('issueInvite unexpected', error: e, stackTrace: st);
      state = state.copyWith(
        isIssuingInvite: false,
        errorMessage: '予期しないエラーが発生しました',
      );
      return null;
    }
  }

  // ==========================================================================
  // メンバー権限変更
  // ==========================================================================
  Future<bool> updateMemberPermission({
    required String userId,
    required MemberPermission permission,
  }) async {
    if (state.isUpdatingMember) return false;
    state = state.copyWith(
      isUpdatingMember: true,
      errorMessage: null,
    );

    try {
      final GroupApiService api = ref.read(groupApiServiceProvider);
      await api.updateMemberPermission(
        groupRemoteId: arg,
        userId: userId,
        permission: permission,
      );

      // ローカルキャッシュも更新
      final repo = ref.read(groupMembersRepositoryProvider);
      final existing = await repo.getMember(
        groupRemoteId: arg,
        userId: userId,
      );
      if (existing != null) {
        await repo.upsertMember(
          groupRemoteId: arg,
          userId: userId,
          displayName: existing.displayName,
          avatarLabel: existing.avatarLabel,
          permission: permission,
          joinedAt: existing.joinedAt,
          lastActiveAt: existing.lastActiveAt,
        );
      }

      state = state.copyWith(isUpdatingMember: false);
      return true;
    } on GroupApiException catch (e) {
      state = state.copyWith(
        isUpdatingMember: false,
        errorMessage: e.message,
      );
      return false;
    } catch (e, st) {
      PetloLogger.instance.w('updateMemberPermission unexpected',
          error: e, stackTrace: st);
      state = state.copyWith(
        isUpdatingMember: false,
        errorMessage: '予期しないエラーが発生しました',
      );
      return false;
    }
  }

  // ==========================================================================
  // メンバー除名
  // ==========================================================================
  Future<bool> removeMember(String userId) async {
    if (state.isUpdatingMember) return false;
    state = state.copyWith(
      isUpdatingMember: true,
      errorMessage: null,
    );

    try {
      final GroupApiService api = ref.read(groupApiServiceProvider);
      await api.removeMember(groupRemoteId: arg, userId: userId);

      await ref.read(groupMembersRepositoryProvider).removeMemberLocally(
            groupRemoteId: arg,
            userId: userId,
          );

      state = state.copyWith(isUpdatingMember: false);
      return true;
    } on GroupApiException catch (e) {
      state = state.copyWith(
        isUpdatingMember: false,
        errorMessage: e.message,
      );
      return false;
    } catch (e, st) {
      PetloLogger.instance
          .w('removeMember unexpected', error: e, stackTrace: st);
      state = state.copyWith(
        isUpdatingMember: false,
        errorMessage: '予期しないエラーが発生しました',
      );
      return false;
    }
  }

  // ==========================================================================
  // グループ退出
  // ==========================================================================
  Future<bool> leaveGroup() async {
    if (state.isLeaving) return false;
    state = state.copyWith(isLeaving: true, errorMessage: null);

    try {
      final GroupApiService api = ref.read(groupApiServiceProvider);
      await api.leaveGroup(arg);

      // ローカル削除 (groups + members + invite_codes)
      // rev5.5 §F-30 対応: 写真の削除は呼び出し側 (UI) で別途実施
      await ref.read(groupMembersRepositoryProvider)
          .deleteAllForGroup(arg);
      await ref.read(inviteCodesRepositoryProvider)
          .deleteAllForGroup(arg);
      await ref.read(groupsRepositoryProvider).leaveGroupLocally(arg);

      state = state.copyWith(isLeaving: false);
      return true;
    } on GroupApiException catch (e) {
      state = state.copyWith(
        isLeaving: false,
        errorMessage: e.message,
      );
      return false;
    } catch (e, st) {
      PetloLogger.instance
          .w('leaveGroup unexpected', error: e, stackTrace: st);
      state = state.copyWith(
        isLeaving: false,
        errorMessage: '予期しないエラーが発生しました',
      );
      return false;
    }
  }
}
