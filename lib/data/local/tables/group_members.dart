// ============================================================================
// petlo - Group Members Table
// ============================================================================
//
// 共有グループ内の他のメンバー一覧 (自分以外)。
//
// 設計:
//   - 自分自身の権限はgroupsテーブルのmyPermissionにある
//   - このテーブルは「他人」の情報のみ
//   - サーバーから定期的にpullしてキャッシュ
//
// ============================================================================

import 'package:drift/drift.dart';

import '../database_converters.dart';
import '../database_enums.dart';

@DataClassName('GroupMemberEntity')
class GroupMembers extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 所属グループのremoteId
  TextColumn get groupRemoteId => text()();

  /// メンバーのユーザーID
  TextColumn get userId => text()();

  /// 表示名 (Apple Sign-In displayName, rev5.4: 初回取得して永続化)
  TextColumn get displayName => text()();

  /// アバター文字 (例: "父", "母", "M")
  TextColumn get avatarLabel => text().nullable()();

  /// 権限
  TextColumn get permission =>
      text().map(const AppEnumConverter(MemberPermission.values))();

  /// 参加日時 (UTC msec)
  IntColumn get joinedAt => integer()();

  /// 最終アクティブ日時 (UTC msec)
  IntColumn get lastActiveAt => integer().nullable()();

  IntColumn get updatedAt => integer()();
}
