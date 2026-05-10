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
    final num expMsec = (json['expires_at'] as num?) ?? 0;
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
    required this.members,
  });

  final String groupId;
  final String groupName;
  final List<GroupMemberDto> members;

  static JoinGroupResultDto fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawMembers =
        (json['members'] as List<dynamic>?) ?? <dynamic>[];
    return JoinGroupResultDto(
      groupId: (json['group_id'] as String?) ?? '',
      groupName: (json['group_name'] as String?) ?? '',
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
    final String role = (json['role'] as String?) ?? 'member';
    final num joined = (json['joined_at'] as num?) ?? 0;
    return GroupMemberDto(
      userId: (json['user_id'] as String?) ?? '',
      displayName: (json['display_name'] as String?) ?? '',
      avatarUrl: json['avatar_url'] as String?,
      permission: _permissionFromRole(role),
      joinedAt: DateTime.fromMillisecondsSinceEpoch(joined.toInt()),
    );
  }

  /// rev5.3 の3段階 (owner/editor/viewer) に対応。
  /// サーバー側は将来更新で 3段階に拡張される想定。
  /// 現状は owner / member の2段階なので、
  /// 'member' は editor 扱い。
  static MemberPermission _permissionFromRole(String role) {
    switch (role) {
      case 'owner':
        return MemberPermission.owner;
      case 'editor':
        return MemberPermission.editor;
      case 'viewer':
        return MemberPermission.viewer;
      case 'member':
      default:
        return MemberPermission.editor;
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
    return CreateGroupResultDto(
      groupId: (json['group_id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
    );
  }
}
