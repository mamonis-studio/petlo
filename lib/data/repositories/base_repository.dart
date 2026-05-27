// ============================================================================
// petlo - Base Repository
// ============================================================================
//
// 全Repositoryの基底。共通処理を集約。
//
// 役割:
//   - createdAt / updatedAt / lastModifiedAtClient の自動設定
//   - 共有スコープ時の sync_queue へのpush統一
//   - groupId のスコープ判定 (personal / shared)
//
// 各テーブル別Repository (PetsRepository, MealsRepository...) は
// このクラスを継承し、テーブル固有のCRUDを実装する。
//
// ============================================================================

import 'package:uuid/uuid.dart';

import '../../core/sync/sync_service.dart';
import '../../data/local/app_database.dart';
import '../../data/local/database_enums.dart';

abstract class BaseRepository {
  BaseRepository(this.db);

  final AppDatabase db;

  static const Uuid _uuid = Uuid();

  /// 現在のUTCミリ秒
  int now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  /// 共有スコープか判定
  bool isSharedScope(String groupId) => groupId != 'personal';

  /// レコード作成時のメタ情報を組み立てる。
  /// すべてのテーブルで使う共通カラムをまとめて埋める。
  ///
  /// 戻り値はMap形式、各テーブルのCompanionに展開する想定。
  ({int createdAt, int updatedAt, int lastModifiedAtClient, SyncStatus initialSyncStatus})
      buildCreateMetadata({required String groupId}) {
    final int t = now();
    return (
      createdAt: t,
      updatedAt: t,
      lastModifiedAtClient: t,
      // Personal は同期不要なので即 synced、共有は pending で sync_queue 入り
      initialSyncStatus:
          isSharedScope(groupId) ? SyncStatus.pending : SyncStatus.synced,
    );
  }

  /// レコード更新時のメタ情報。
  /// updatedAt と lastModifiedAtClient を新しい値に更新。
  /// rev5.3: クライアント時刻はあくまで参考値、サーバー受信時にserver_timeで上書きされる。
  ({int updatedAt, int lastModifiedAtClient, SyncStatus updatedSyncStatus})
      buildUpdateMetadata({required String groupId}) {
    final int t = now();
    return (
      updatedAt: t,
      lastModifiedAtClient: t,
      updatedSyncStatus:
          isSharedScope(groupId) ? SyncStatus.pending : SyncStatus.synced,
    );
  }

  /// 論理削除のメタ情報。
  /// deletedAt をセット、updatedAt も更新、syncStatusはpending。
  ({int deletedAt, int updatedAt, int lastModifiedAtClient, SyncStatus updatedSyncStatus})
      buildDeleteMetadata({required String groupId}) {
    final int t = now();
    return (
      deletedAt: t,
      updatedAt: t,
      lastModifiedAtClient: t,
      updatedSyncStatus:
          isSharedScope(groupId) ? SyncStatus.pending : SyncStatus.synced,
    );
  }

  /// 共有スコープのレコードを sync_queue に積むためのヘルパー。
  /// personalスコープでは何もしない。
  ///
  /// 各Repository は insert/update/delete 後に呼び出す。
  Future<void> enqueueSyncIfShared({
    required String groupId,
    required SyncOperation operation,
    required String targetTable,
    required int recordId,
    required String payloadJson,
    int? clientTimestamp,
  }) async {
    if (!isSharedScope(groupId)) {
      return;
    }
    final int t = now();
    await db.into(db.syncQueue).insert(
          SyncQueueCompanion.insert(
            opId: _uuid.v4(),
            operation: operation,
            targetTable: targetTable,
            recordId: recordId,
            groupId: groupId,
            clientTimestamp: clientTimestamp ?? t,
            payload: payloadJson,
            queuedAt: t,
          ),
        );
    // build 19: 編集の都度 2.5s デバウンスで同期トリガー
    SyncService.instance.scheduleDebouncedSync();
  }
}
