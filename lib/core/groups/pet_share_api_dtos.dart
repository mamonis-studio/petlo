// ============================================================================
// petlo - Pet Share API DTOs
// ============================================================================
//
// Cloudflare Workers `/pets/{petServerId}/shares` 系 endpoint との通信で使う
// JSON 構造の Dart 表現。
//
// build 45 (Phase G4a) で新設。backend は G3-D で実装済み (multi_scope_pet
// _sharing_design.md §3.2 参照)。
//
// ============================================================================

import 'package:flutter/foundation.dart';

import '../../data/local/database_enums.dart';

/// 単一の pet_scope エントリ。`GET /pets/{petServerId}/shares` の配列要素
/// および `POST` / `PATCH` のレスポンス。
@immutable
class PetShareDto {
  const PetShareDto({
    required this.scopeId,
    required this.petServerId,
    required this.groupId,
    required this.permission,
    required this.isPrimary,
    required this.sharedAt,
    this.sharedByUserId,
    this.deletedAt,
  });

  /// pet_scopes.id (サーバ UUID)。
  final String scopeId;

  /// pets.id (サーバ UUID)。
  final String petServerId;

  /// groups.id。
  final String groupId;

  /// per-pet 権限 (Decision Log #4 で group 権限を上書き)。
  final MemberPermission permission;

  /// この scope が primary か (= pet の物理本籍)。
  final bool isPrimary;

  /// 共有開始日時。
  final DateTime sharedAt;

  /// 共有した user_id (null 可、backfill 行など)。
  final String? sharedByUserId;

  /// 共有解除日時 (null = 生存中)。
  final DateTime? deletedAt;

  static PetShareDto fromJson(Map<String, dynamic> json) {
    final num sharedAtMsec = (json['sharedAt'] as num?) ?? 0;
    final dynamic deletedRaw = json['deletedAt'];
    return PetShareDto(
      scopeId: (json['id'] as String?) ?? (json['scopeId'] as String?) ?? '',
      petServerId: (json['petId'] as String?) ??
          (json['petServerId'] as String?) ??
          '',
      groupId: (json['groupId'] as String?) ?? '',
      permission: _parsePermission(json['permission']),
      isPrimary: _parseBool(json['isPrimary']),
      sharedAt: DateTime.fromMillisecondsSinceEpoch(sharedAtMsec.toInt()),
      sharedByUserId: json['sharedByUserId'] as String?,
      deletedAt: deletedRaw is num
          ? DateTime.fromMillisecondsSinceEpoch(deletedRaw.toInt())
          : null,
    );
  }

  static MemberPermission _parsePermission(dynamic v) {
    if (v is String) {
      for (final MemberPermission p in MemberPermission.values) {
        if (p.name == v) return p;
      }
    }
    return MemberPermission.editor; // 安全側デフォルト (権限不明時は中間)
  }

  /// サーバが `is_primary` を 0/1 で返すことを想定。bool / num / null を全て吸収。
  static bool _parseBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v.toInt() != 0;
    return false;
  }
}

/// `GET /pets/{petServerId}/shares` のレスポンス body。
@immutable
class PetSharesListDto {
  const PetSharesListDto({required this.shares});

  final List<PetShareDto> shares;

  static PetSharesListDto fromJson(Map<String, dynamic> json) {
    final List<dynamic> raw =
        (json['shares'] as List<dynamic>?) ?? const <dynamic>[];
    return PetSharesListDto(
      shares: raw
          .whereType<Map<String, dynamic>>()
          .map(PetShareDto.fromJson)
          .toList(),
    );
  }
}
