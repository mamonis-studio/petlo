// ============================================================================
// petlo - Pending Transfers Table
// ============================================================================
//
// オーナー権限譲渡フロー (rev5.4 F-34a/b)。
//
// 種類:
//   1. 手動譲渡 (Ownerが操作) — fromUserId=現Owner, status=pending → accepted
//   2. 自動譲渡 (30日不在) — システムが作成、即時accepted
//
// ============================================================================

import 'package:drift/drift.dart';

@DataClassName('PendingTransferEntity')
class PendingTransfers extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get groupRemoteId => text()();

  /// 譲渡元 (現オーナー)
  TextColumn get fromUserId => text()();

  /// 譲渡先 (新オーナー候補)
  TextColumn get toUserId => text()();

  /// 'pending' | 'accepted' | 'cancelled' | 'auto_inactive_owner'
  TextColumn get status => text().withDefault(const Constant('pending'))();

  /// 'manual' | 'auto_inactive_owner'
  TextColumn get reason => text().withDefault(const Constant('manual'))();

  /// 譲渡リクエスト日時 (UTC msec)
  IntColumn get requestedAt => integer()();

  /// 完了日時 (UTC msec、status=acceptedの時)
  IntColumn get completedAt => integer().nullable()();
}
