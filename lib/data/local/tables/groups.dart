// ============================================================================
// petlo - Groups Table
// ============================================================================
//
// 共有グループの情報 (rev5.3新規、rev5.5でPro解約フロー追加)。
//
// 1ユーザーは最大3グループ参加可能 (Personal含めて4スコープ)。
//
// rev5.5: Pro解約検知後の段階的freeze:
//   - 0-30日: pendingDeletion、警告バナー
//   - 30日: frozen、操作不可
//   - 90日: 物理削除
//
// ============================================================================

import 'package:drift/drift.dart';

import '../database_converters.dart';
import '../database_enums.dart';

@DataClassName('GroupEntity')
class Groups extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// サーバー側ID (UUID)
  TextColumn get remoteId => text().unique()();

  /// グループ名 (例: "お父さん家族", "ご近所ペットの会")
  TextColumn get name => text().withLength(min: 1, max: 50)();

  /// オーナーのユーザーID
  TextColumn get ownerUserId => text()();

  /// 自分のこのグループ内権限 (rev5.3)
  TextColumn get myPermission =>
      text().map(const AppEnumConverter(MemberPermission.values))();

  /// グループ状態 (rev5.5)
  TextColumn get status => text()
      .map(const AppEnumConverter(GroupStatus.values))
      .withDefault(const Constant('active'))();

  /// pending_deletion 状態の開始日時 (UTC msec、rev5.5)
  /// オーナーのPro解約後にセットされる、ここから30日でfrozen、90日で削除
  IntColumn get pendingDeletionAt => integer().nullable()();

  /// 自分が参加した日時 (UTC msec)
  IntColumn get joinedAt => integer()();

  /// 最終アクティブ日時 (UTC msec、rev5.4: オーナー30日不在検知用)
  IntColumn get lastActiveAt => integer()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
}
