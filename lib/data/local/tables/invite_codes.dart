// ============================================================================
// petlo - Invite Codes Table
// ============================================================================
//
// 6桁招待コード (rev2新規、rev5.3で権限指定対応)。
// TTL 72時間、サーバーで管理されるためローカルにはキャッシュのみ。
//
// rev5.3: granted_permission で Editor / Viewer 指定可能
// (Owner権限は招待コード経由で付与不可、譲渡UIのみ)
//
// ============================================================================

import 'package:drift/drift.dart';

import '../database_converters.dart';
import '../database_enums.dart';

@DataClassName('InviteCodeEntity')
class InviteCodes extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 6桁コード
  TextColumn get code => text().withLength(min: 6, max: 6)();

  /// 所属グループremoteId
  TextColumn get groupRemoteId => text()();

  /// この招待で付与する権限 (Editor or Viewer のみ、rev5.3)
  TextColumn get grantedPermission =>
      text().map(const AppEnumConverter(MemberPermission.values))();

  /// 状態
  TextColumn get status => text()
      .map(const AppEnumConverter(InviteCodeStatus.values))
      .withDefault(const Constant('active'))();

  /// 発行日時 (UTC msec)
  IntColumn get issuedAt => integer()();

  /// 期限 (UTC msec、issuedAt + 72h)
  IntColumn get expiresAt => integer()();

  /// 使用日時 (UTC msec、status=usedの時)
  IntColumn get usedAt => integer().nullable()();

  /// 使用したユーザーID
  TextColumn get usedByUserId => text().nullable()();
}
