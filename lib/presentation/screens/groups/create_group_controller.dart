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

import '../../../core/groups/group_api_error_messages.dart';
import '../../../core/groups/group_api_exceptions.dart';
import '../../../core/groups/group_api_service.dart';
import '../../../core/preferences/user_preferences.dart';
import '../../../core/utils/logger.dart';
import '../../../data/local/database_enums.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/display_name_provider.dart';
import '../../providers/group_api_service_provider.dart';
import '../../providers/groups_providers.dart';
import '../../providers/pro_status_provider.dart';

@immutable
class CreateGroupState {
  const CreateGroupState({
    this.name = '',
    this.displayName = '',
    this.isSubmitting = false,
    this.errorMessage,
    this.nameError,
    this.displayNameError,
  });

  final String name;
  final String displayName;
  final bool isSubmitting;
  final String? errorMessage;
  final String? nameError;
  final String? displayNameError;

  CreateGroupState copyWith({
    String? name,
    String? displayName,
    bool? isSubmitting,
    Object? errorMessage = _sentinel,
    Object? nameError = _sentinel,
    Object? displayNameError = _sentinel,
  }) {
    return CreateGroupState(
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage == _sentinel
          ? this.errorMessage
          : errorMessage as String?,
      nameError: nameError == _sentinel
          ? this.nameError
          : nameError as String?,
      displayNameError: displayNameError == _sentinel
          ? this.displayNameError
          : displayNameError as String?,
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
    // build 18: 既に保存済みの表示名でプリフィル (家族共有 2 回目以降の利用)
    return CreateGroupState(
      displayName: UserPreferences.instance.displayName ?? '',
    );
  }

  void updateName(String v) {
    state = state.copyWith(name: v, nameError: null, errorMessage: null);
  }

  void updateDisplayName(String v) {
    state = state.copyWith(
      displayName: v,
      displayNameError: null,
      errorMessage: null,
    );
  }

  CreateGroupState _validate(CreateGroupState s, AppLocalizations l10n) {
    final String trimmed = s.name.trim();
    String? err;
    if (trimmed.isEmpty) {
      err = l10n.create_group_validation_name_required;
    } else if (trimmed.length > 50) {
      err = l10n.create_group_validation_name_max;
    }
    final String dn = s.displayName.trim();
    String? dnErr;
    if (dn.isEmpty) {
      dnErr = l10n.create_group_validation_display_name_required;
    } else if (dn.length > 20) {
      dnErr = l10n.create_group_validation_display_name_max;
    }
    return s.copyWith(nameError: err, displayNameError: dnErr);
  }

  Future<({CreateGroupOutcome outcome, String? createdGroupId})> submit(
      AppLocalizations l10n) async {
    if (state.isSubmitting) {
      return (outcome: CreateGroupOutcome.unknown, createdGroupId: null);
    }

    // ローカルバリデート
    final CreateGroupState validated = _validate(state, l10n);
    if (validated.nameError != null || validated.displayNameError != null) {
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
        errorMessage: l10n.create_group_pro_required_message,
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
          errorMessage: l10n.create_group_validation_limit_reached,
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
      final result = await api.createGroup(
        state.name.trim(),
        displayName: state.displayName.trim(),
      );

      // 表示名をローカルキャッシュ + reactive provider に反映
      // (PATCH /me は別経路 — グループ作成の trip にまとめる)
      await ref
          .read(displayNameProvider.notifier)
          .setLocal(state.displayName.trim());

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
        errorMessage: groupApiErrorMessage(e, l10n),
      );
      return (
        outcome: CreateGroupOutcome.proRequired,
        createdGroupId: null
      );
    } on GroupNetworkException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: groupApiErrorMessage(e, l10n),
      );
      return (
        outcome: CreateGroupOutcome.network,
        createdGroupId: null
      );
    } on GroupServerException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: groupApiErrorMessage(e, l10n),
      );
      return (
        outcome: CreateGroupOutcome.serverError,
        createdGroupId: null
      );
    } on GroupApiException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: groupApiErrorMessage(e, l10n),
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
        errorMessage: l10n.common_unexpected_error,
      );
      return (
        outcome: CreateGroupOutcome.unknown,
        createdGroupId: null
      );
    }
  }
}
