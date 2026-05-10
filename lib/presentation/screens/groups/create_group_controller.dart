// ============================================================================
// petlo - Create Group Controller
// ============================================================================
//
// 新規グループ作成のロジック。
// rev5.3 F-24: グループ作成(オーナーProのみ、最大3つ)
//
// フロー:
//   1. Pro チェック (UI 側で先に確認するが二重防御)
//   2. グループ枠の残り数チェック (3つ上限)
//   3. サーバーへ POST /groups
//   4. ローカル DB に upsert
//   5. オーナーは自動で myPermission = owner
//
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/groups/group_api_exceptions.dart';
import '../../../core/groups/group_api_service.dart';
import '../../../core/utils/logger.dart';
import '../../../data/local/database_enums.dart';
import '../../providers/group_api_service_provider.dart';
import '../../providers/groups_providers.dart';
import '../../providers/pro_status_provider.dart';

@immutable
class CreateGroupState {
  const CreateGroupState({
    this.name = '',
    this.isSubmitting = false,
    this.errorMessage,
    this.nameError,
  });

  final String name;
  final bool isSubmitting;
  final String? errorMessage;
  final String? nameError;

  CreateGroupState copyWith({
    String? name,
    bool? isSubmitting,
    Object? errorMessage = _sentinel,
    Object? nameError = _sentinel,
  }) {
    return CreateGroupState(
      name: name ?? this.name,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage == _sentinel
          ? this.errorMessage
          : errorMessage as String?,
      nameError: nameError == _sentinel
          ? this.nameError
          : nameError as String?,
    );
  }

  static const Object _sentinel = Object();
}

enum CreateGroupOutcome {
  success,
  validationFailed,
  proRequired,
  limitReached,
  network,
  serverError,
  unknown,
}

final NotifierProvider<CreateGroupController, CreateGroupState>
    createGroupControllerProvider =
    NotifierProvider<CreateGroupController, CreateGroupState>(
  CreateGroupController.new,
);

class CreateGroupController extends Notifier<CreateGroupState> {
  @override
  CreateGroupState build() {
    return const CreateGroupState();
  }

  void updateName(String v) {
    state = state.copyWith(name: v, nameError: null, errorMessage: null);
  }

  CreateGroupState _validate(CreateGroupState s) {
    final String trimmed = s.name.trim();
    String? err;
    if (trimmed.isEmpty) {
      err = 'グループ名を入力してください';
    } else if (trimmed.length > 50) {
      err = '50文字以内で入力してください';
    }
    return s.copyWith(nameError: err);
  }

  Future<({CreateGroupOutcome outcome, String? createdGroupId})>
      submit() async {
    if (state.isSubmitting) {
      return (outcome: CreateGroupOutcome.unknown, createdGroupId: null);
    }

    // ローカルバリデート
    final CreateGroupState validated = _validate(state);
    if (validated.nameError != null) {
      state = validated;
      return (
        outcome: CreateGroupOutcome.validationFailed,
        createdGroupId: null
      );
    }

    // Pro チェック (二重防御)
    final bool isPro = ref.read(isProProvider);
    if (!isPro) {
      state = state.copyWith(
        errorMessage: 'グループ作成は Pro プラン限定です',
      );
      return (
        outcome: CreateGroupOutcome.proRequired,
        createdGroupId: null
      );
    }

    // グループ枠の残り数チェック
    try {
      final int remaining = await ref
          .read(groupsRepositoryProvider)
          .remainingGroupSlots();
      if (remaining <= 0) {
        state = state.copyWith(
          errorMessage: 'グループは最大3つまで作成できます',
        );
        return (
          outcome: CreateGroupOutcome.limitReached,
          createdGroupId: null
        );
      }
    } catch (e, st) {
      PetloLogger.instance.d(
          'remainingGroupSlots check failed: $e',
          stackTrace: st);
      // 失敗時は通す方針
    }

    state = state.copyWith(isSubmitting: true, errorMessage: null);

    try {
      final GroupApiService api = ref.read(groupApiServiceProvider);
      final result = await api.createGroup(state.name.trim());

      // サーバー側 owner_user_id は本来サーバーが返すが、
      // 仕様簡略化のため自分の userId は別途認証から取得する想定。
      // 暫定では空文字を入れておき、次の sync で正しい値で上書きされる前提
      final int now = DateTime.now().millisecondsSinceEpoch;
      await ref.read(groupsRepositoryProvider).upsertGroupFromServer(
            remoteId: result.groupId,
            name: result.name,
            ownerUserId: '', // 認証実装後に注入
            myPermission: MemberPermission.owner,
            status: GroupStatus.active,
            joinedAt: now,
            lastActiveAt: now,
          );

      state = state.copyWith(isSubmitting: false);
      return (
        outcome: CreateGroupOutcome.success,
        createdGroupId: result.groupId,
      );
    } on GroupProRequiredException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.message,
      );
      return (
        outcome: CreateGroupOutcome.proRequired,
        createdGroupId: null
      );
    } on GroupNetworkException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.message,
      );
      return (
        outcome: CreateGroupOutcome.network,
        createdGroupId: null
      );
    } on GroupServerException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.message,
      );
      return (
        outcome: CreateGroupOutcome.serverError,
        createdGroupId: null
      );
    } on GroupApiException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.message,
      );
      return (
        outcome: CreateGroupOutcome.unknown,
        createdGroupId: null
      );
    } catch (e, st) {
      PetloLogger.instance
          .w('createGroup unexpected', error: e, stackTrace: st);
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: '予期しないエラーが発生しました',
      );
      return (
        outcome: CreateGroupOutcome.unknown,
        createdGroupId: null
      );
    }
  }
}
