// ============================================================================
// petlo - Group API DTOs
// ============================================================================
//
// Cloudflare Workers との通信で使う JSON 構造の Dart 表現。
// サーバー側 (petlo-api/src/types.ts) と対応。
//
// ============================================================================

import 'package:flutter/foundation.dart';

import '../../data/local/database_enums.dart';

// ============================================================================
// Create Invite
// ============================================================================
@immutable
class CreateInviteResultDto {
  const CreateInviteResultDto({
    required this.code,
    required this.expiresAt,
    required this.grantedPermission,
  });

  final String code;
  final DateTime expiresAt;
  final MemberPermission grantedPermission;

  static CreateInviteResultDto fromJson(
      Map<String, dynamic> json,
      MemberPermission requestedPermission,
      ) {
    // backend は camelCase で返す ({ code, expiresAt, grantedPermission })。
    // 旧 snake_case (expires_at) からの fallback も保険で残す。
    final num expMsec =
        (json['expiresAt'] as num?) ?? (json['expires_at'] as num?) ?? 0;
    return CreateInviteResultDto(
      code: (json['code'] as String?) ?? '',
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expMsec.toInt()),
      grantedPermission: requestedPermission,
    );
  }
}

// ============================================================================
// Join Group
// ============================================================================
@immutable
class JoinGroupResultDto {
  const JoinGroupResultDto({
    required this.groupId,
    required this.groupName,
    required this.myPermission,
    required this.members,
  });

  final String groupId;
  final String groupName;
  final MemberPermission myPermission;
  final List<GroupMemberDto> members;

  static JoinGroupResultDto fromJson(Map<String, dynamic> json) {
    // backend (build 21) は camelCase で返す。snake_case は旧 fallback。
    final List<dynamic> rawMembers =
        (json['members'] as List<dynamic>?) ?? <dynamic>[];
    // build 28: 招待時の権限 (viewer / editor) を backend から取得。
    // 旧 build 27 までは join controller 側で editor ハードコードしていた。
    final String? roleRaw =
        (json['myPermission'] as String?) ?? (json['my_permission'] as String?);
    return JoinGroupResultDto(
      groupId:
          (json['groupId'] as String?) ?? (json['group_id'] as String?) ?? '',
      groupName: (json['groupName'] as String?) ??
          (json['group_name'] as String?) ??
          '',
      myPermission: GroupMemberDto.permissionFromRole(roleRaw ?? 'viewer'),
      members: rawMembers
          .whereType<Map<String, dynamic>>()
          .map(GroupMemberDto.fromJson)
          .toList(),
    );
  }
}

// ============================================================================
// Group Member
// ============================================================================
@immutable
class GroupMemberDto {
  const GroupMemberDto({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.permission,
    required this.joinedAt,
  });

  final String userId;
  final String displayName;
  final String? avatarUrl;
  final MemberPermission permission;
  final DateTime joinedAt;

  static GroupMemberDto fromJson(Map<String, dynamic> json) {
    // backend (build 21) は camelCase + permission キーで返す。
    // 旧 snake_case + role キーは fallback。
    final String role = (json['permission'] as String?) ??
        (json['role'] as String?) ??
        'member';
    final num joined =
        (json['joinedAt'] as num?) ?? (json['joined_at'] as num?) ?? 0;
    return GroupMemberDto(
      userId:
          (json['userId'] as String?) ?? (json['user_id'] as String?) ?? '',
      displayName: (json['displayName'] as String?) ??
          (json['display_name'] as String?) ??
          '',
      avatarUrl:
          (json['avatarUrl'] as String?) ?? (json['avatar_url'] as String?),
      permission: permissionFromRole(role),
      joinedAt: DateTime.fromMillisecondsSinceEpoch(joined.toInt()),
    );
  }

  /// rev5.3 の3段階 (owner/editor/viewer) に対応。
  /// build 28: public 化 (JoinGroupResultDto からも再利用)。
  ///
  /// - 'owner' / 'editor' / 'viewer' → 一致
  /// - 旧 'member' → editor 互換 (rev5.3 移行前データ)
  /// - 不明値 / 空 → 安全側 viewer
  static MemberPermission permissionFromRole(String role) {
    switch (role) {
      case 'owner':
        return MemberPermission.owner;
      case 'editor':
        return MemberPermission.editor;
      case 'viewer':
        return MemberPermission.viewer;
      case 'member':
        return MemberPermission.editor;
      default:
        return MemberPermission.viewer;
    }
  }
}

// ============================================================================
// Create Group
// ============================================================================
@immutable
class CreateGroupResultDto {
  const CreateGroupResultDto({
    required this.groupId,
    required this.name,
  });

  final String groupId;
  final String name;

  static CreateGroupResultDto fromJson(Map<String, dynamic> json) {
    // backend (build 21) は camelCase で返す。snake_case は旧 fallback。
    return CreateGroupResultDto(
      groupId:
          (json['groupId'] as String?) ?? (json['group_id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
    );
  }
}
