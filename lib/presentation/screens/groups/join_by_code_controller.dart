// ============================================================================
// petlo - Join By Code Controller
// ============================================================================
//
// 6桁招待コードでグループに参加。
//
// rev5.3 F-26: 招待コードで参加(誰でも無料)
// rev5.3 F-31: 同名ペット警告(参加成功時に注意喚起)
//
// フロー:
//   1. 6桁コード + 表示名のローカルバリデート
//   2. グループ参加上限(3つ)チェック
//   3. POST /join → グループ情報 + メンバー一覧取得
//   4. ローカル DB に upsert (groups + group_members)
//   5. 成功時に groupRemoteId を画面に返す
//
// 同名ペット警告はサーバー側ペット同期実装後に強化される予定。
// v1.0 ではローカルの Personal ペット名と、参加グループ名から
// 名前重複の可能性のみ警告(あくまで注意喚起)。
//
// ============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/groups/group_api_dtos.dart';
import '../../../core/groups/group_api_exceptions.dart';
import '../../../core/groups/group_api_service.dart';
import '../../../core/preferences/user_preferences.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/utils/logger.dart';
import '../../../data/local/database_enums.dart';
import '../../providers/display_name_provider.dart';
import '../../providers/group_api_service_provider.dart';
import '../../providers/group_members_providers.dart';
import '../../providers/groups_providers.dart';
import '../../providers/pets_providers.dart';

@immutable
class JoinByCodeState {
  const JoinByCodeState({
    this.code = '',
    this.displayName = '',
    this.isSubmitting = false,
    this.codeError,
    this.nameError,
    this.errorMessage,
  });

  final String code;
  final String displayName;
  final bool isSubmitting;
  final String? codeError;
  final String? nameError;
  final String? errorMessage;

  bool get canSubmit =>
      !isSubmitting &&
      RegExp(r'^\d{6}$').hasMatch(code) &&
      displayName.trim().isNotEmpty;

  JoinByCodeState copyWith({
    String? code,
    String? displayName,
    bool? isSubmitting,
    Object? codeError = _sentinel,
    Object? nameError = _sentinel,
    Object? errorMessage = _sentinel,
  }) {
    return JoinByCodeState(
      code: code ?? this.code,
      displayName: displayName ?? this.displayName,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      codeError: codeError == _sentinel
          ? this.codeError
          : codeError as String?,
      nameError: nameError == _sentinel
          ? this.nameError
          : nameError as String?,
      errorMessage: errorMessage == _sentinel
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  static const Object _sentinel = Object();
}

class JoinResult {
  const JoinResult({
    required this.groupRemoteId,
    required this.groupName,
    required this.memberDisplayNames,
  });

  final String groupRemoteId;
  final String groupName;
  /// 参加したグループのメンバー displayName 一覧 (自分を除く、F-31 準備用)
  final List<String> memberDisplayNames;
}

enum JoinByCodeOutcome {
  success,
  validationFailed,
  invalid,
  alreadyUsed,
  full,
  alreadyMember,
  limitReached,
  network,
  serverError,
  unknown,
}

final NotifierProvider<JoinByCodeController, JoinByCodeState>
    joinByCodeControllerProvider =
    NotifierProvider<JoinByCodeController, JoinByCodeState>(
  JoinByCodeController.new,
);

class JoinByCodeController extends Notifier<JoinByCodeState> {
  @override
  JoinByCodeState build() {
    // build 18: 既に保存済みの表示名でプリフィル
    return JoinByCodeState(
      displayName: UserPreferences.instance.displayName ?? '',
    );
  }

  void updateCode(String v) {
    // 数字のみ、6桁まで
    final String filtered =
        v.replaceAll(RegExp(r'\D'), '').padRight(0).substring(
              0,
              v.replaceAll(RegExp(r'\D'), '').length > 6
                  ? 6
                  : v.replaceAll(RegExp(r'\D'), '').length,
            );
    state = state.copyWith(
      code: filtered,
      codeError: null,
      errorMessage: null,
    );
  }

  void updateDisplayName(String v) {
    state = state.copyWith(
      displayName: v,
      nameError: null,
      errorMessage: null,
    );
  }

  JoinByCodeState _validate(JoinByCodeState s) {
    String? codeErr;
    if (!RegExp(r'^\d{6}$').hasMatch(s.code)) {
      codeErr = '6桁の数字を入力してください';
    }
    String? nameErr;
    final String trimmed = s.displayName.trim();
    if (trimmed.isEmpty) {
      nameErr = '表示名を入力してください';
    } else if (trimmed.length > 30) {
      nameErr = '30文字以内で入力してください';
    }
    return s.copyWith(codeError: codeErr, nameError: nameErr);
  }

  /// グループ参加を実行
  Future<({JoinByCodeOutcome outcome, JoinResult? result})>
      submit() async {
    if (state.isSubmitting) {
      return (outcome: JoinByCodeOutcome.unknown, result: null);
    }

    // バリデート
    final JoinByCodeState validated = _validate(state);
    if (validated.codeError != null || validated.nameError != null) {
      state = validated;
      return (
        outcome: JoinByCodeOutcome.validationFailed,
        result: null
      );
    }

    // グループ参加上限チェック (Personal は対象外で 3つまで)
    try {
      final int remaining = await ref
          .read(groupsRepositoryProvider)
          .remainingGroupSlots();
      if (remaining <= 0) {
        state = state.copyWith(
          errorMessage: '参加できるグループは最大3つまでです',
        );
        return (
          outcome: JoinByCodeOutcome.limitReached,
          result: null
        );
      }
    } catch (e) {
      PetloLogger.instance.d('remainingGroupSlots check failed: $e');
    }

    state = state.copyWith(isSubmitting: true, errorMessage: null);

    try {
      final GroupApiService api = ref.read(groupApiServiceProvider);
      final JoinGroupResultDto resp = await api.joinByCode(
        code: state.code,
        displayName: state.displayName.trim(),
      );

      // 表示名をローカルキャッシュ + reactive provider に反映
      await ref
          .read(displayNameProvider.notifier)
          .setLocal(state.displayName.trim());

      // ローカル DB に group を upsert
      final int now = DateTime.now().millisecondsSinceEpoch;
      // build 28: backend が返す myPermission をそのまま採用。
      // editor / viewer は招待発行時の grantedPermission に従う。
      // 不正値・欠落時は DTO 側で viewer に fallback 済み。
      final MemberPermission myPermission = resp.myPermission;

      // owner の userId を members から探す
      final String ownerUserId = resp.members
          .firstWhere(
            (m) => m.permission == MemberPermission.owner,
            orElse: () => GroupMemberDto(
              userId: '',
              displayName: '',
              permission: MemberPermission.owner,
              joinedAt: DateTime.fromMillisecondsSinceEpoch(0),
            ),
          )
          .userId;

      await ref.read(groupsRepositoryProvider).upsertGroupFromServer(
            remoteId: resp.groupId,
            name: resp.groupName,
            ownerUserId: ownerUserId,
            myPermission: myPermission,
            status: GroupStatus.active,
            joinedAt: now,
            lastActiveAt: now,
          );

      // メンバー一覧をローカルにキャッシュ(自分以外、ただし userId 未取得のため
      // とりあえず全員 upsert)
      final repo = ref.read(groupMembersRepositoryProvider);
      for (final GroupMemberDto m in resp.members) {
        if (m.userId.isEmpty) continue;
        await repo.upsertMember(
          groupRemoteId: resp.groupId,
          userId: m.userId,
          displayName: m.displayName,
          avatarLabel: null,
          permission: m.permission,
          joinedAt: m.joinedAt.millisecondsSinceEpoch,
        );
      }

      // build 25: 参加直後の初回 pull を「since=0」で必ず全件取得させる。
      //   - cursor キー (sync.next_since.<gid>) を削除
      //   - その上で対象グループだけ即時 sync (push→pull)
      // これで「オーナーが参加前に共有した過去ペット/記録」を取りこぼさない。
      await SyncService.instance.resetCursorForGroup(resp.groupId);
      // fire-and-forget。失敗してもユーザーは参加成功 (グループ詳細へ遷移)。
      unawaited(SyncService.instance.syncGroup(resp.groupId));

      state = state.copyWith(isSubmitting: false);
      return (
        outcome: JoinByCodeOutcome.success,
        result: JoinResult(
          groupRemoteId: resp.groupId,
          groupName: resp.groupName,
          memberDisplayNames:
              resp.members.map((m) => m.displayName).toList(),
        ),
      );
    } on InviteCodeInvalidException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.message,
      );
      return (outcome: JoinByCodeOutcome.invalid, result: null);
    } on InviteCodeAlreadyUsedException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.message,
      );
      return (outcome: JoinByCodeOutcome.alreadyUsed, result: null);
    } on GroupFullException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.message,
      );
      return (outcome: JoinByCodeOutcome.full, result: null);
    } on AlreadyMemberException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.message,
      );
      return (outcome: JoinByCodeOutcome.alreadyMember, result: null);
    } on GroupLimitReachedException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.message,
      );
      return (outcome: JoinByCodeOutcome.limitReached, result: null);
    } on GroupNetworkException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.message,
      );
      return (outcome: JoinByCodeOutcome.network, result: null);
    } on GroupServerException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.message,
      );
      return (outcome: JoinByCodeOutcome.serverError, result: null);
    } on GroupApiException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.message,
      );
      return (outcome: JoinByCodeOutcome.unknown, result: null);
    } catch (e, st) {
      PetloLogger.instance
          .w('joinByCode unexpected', error: e, stackTrace: st);
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: '予期しないエラーが発生しました',
      );
      return (outcome: JoinByCodeOutcome.unknown, result: null);
    }
  }

  /// F-31 同名ペット警告: ローカル Personal ペット名 と
  /// 参加したグループの memberDisplayNames を比較する
  /// (将来サーバー側 pet_id 同期実装時にもっと正確な検知に置き換え)
  Future<List<String>> findLocalPetNames() async {
    try {
      final pets = await ref.read(currentGroupPetsProvider.future);
      return pets.map((p) => p.name).toList();
    } catch (e) {
      PetloLogger.instance.d('findLocalPetNames failed: $e');
      return <String>[];
    }
  }
}
