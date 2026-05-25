// ============================================================================
// petlo - Sync Service (build 19, phase 2)
// ============================================================================
//
// 家族共有 (groupId != 'personal') スコープの双方向同期。
//
//   push: sync_queue → POST /sync/push
//   pull: GET /sync/pull?groupId=&since= → ローカル DB upsert
//
// 設計:
//   - シングルトン (SyncService.instance)
//   - _isSyncing で多重実行を抑止
//   - 各グループの nextSince は SharedPreferences (`sync.next_since.<gid>`)
//   - personal スコープ ('personal') は完全にスキップ
//   - push の payload は (targetTable, recordId) でローカル行を再読み込みして
//     その場で組み立てる (キューに保存された payload は無視、build 19 時点)
//   - pull の upsert は customStatement で raw SQL → notifyUpdates で
//     drift watchers を発火させる
//
// 認証:
//   - ApiDio.instance を使うので AuthDioInterceptor 経由で JWT が自動付与される。
//
// ============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/local/app_database.dart';
import '../auth/api_dio.dart';
import '../utils/logger.dart';

class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  /// build 26: フォアグラウンド定期ポーリング間隔。
  /// 家族共有にリアルタイム性は不要なので 2 分でバランス。
  /// 将来変更しやすいよう定数化。
  static const Duration pollingInterval = Duration(minutes: 2);

  AppDatabase? _db;
  void bindDatabase(AppDatabase db) {
    _db = db;
  }

  bool _isSyncing = false;
  DateTime? _lastSyncAt;
  Timer? _debounce;
  Timer? _polling;

  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncAt => _lastSyncAt;

  /// 編集の都度呼ぶ。2.5 秒後に sync を発火する。
  void scheduleDebouncedSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 2500), () {
      unawaited(syncAll());
    });
  }

  /// build 26: フォアグラウンド定期ポーリング開始。
  /// 既存タイマーはキャンセルしてから新規発火 (多重起動防止)。
  /// _isSyncing ガードがある (`syncAll`/`syncGroup`) ので他トリガーと衝突しても
  /// 二重 push/pull は起きない。
  void startPolling() {
    _polling?.cancel();
    _polling = Timer.periodic(pollingInterval, (_) {
      unawaited(syncAll());
    });
    PetloLogger.instance.d(
      'SyncService: polling started (${pollingInterval.inMinutes}min)',
    );
  }

  /// build 26: バックグラウンド遷移時に呼ぶ。
  /// タイマーを止めてバッテリー・通信を節約する。
  void stopPolling() {
    if (_polling != null) {
      _polling!.cancel();
      _polling = null;
      PetloLogger.instance.d('SyncService: polling stopped');
    }
  }

  /// build 25: グループに新規参加した直後に呼ぶ。
  /// `sync.next_since.<groupId>` を削除して次回 pull を since=0 (全件取得) にする。
  /// 既存値がある場合 (旧テスト時の残存・race race による先行更新等) を
  /// 確実にリセットして「参加前にオーナーが共有した過去データ」を取りこぼさない。
  Future<void> resetCursorForGroup(String groupId) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove('sync.next_since.$groupId');
      PetloLogger.instance
          .i('SyncService: cursor reset for group=$groupId (full re-pull next)');
    } catch (e, st) {
      PetloLogger.instance.w(
        'SyncService: cursor reset failed for $groupId',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// build 25: 指定グループだけ即時 push→pull する。
  /// 参加直後 / 「同期する」UI から呼ぶ想定。
  /// 多重実行ガードは syncAll と共有。
  Future<void> syncGroup(String groupId) async {
    final AppDatabase? db = _db;
    if (db == null) {
      PetloLogger.instance.d('SyncService.syncGroup: db not bound, skipping');
      return;
    }
    if (_isSyncing) {
      PetloLogger.instance
          .d('SyncService.syncGroup: already syncing, skipping');
      return;
    }
    _isSyncing = true;
    try {
      await _pushGroup(db, groupId);
      await _pullGroup(db, groupId);
      _lastSyncAt = DateTime.now();
    } catch (e, st) {
      PetloLogger.instance.w(
        'SyncService.syncGroup($groupId) failed',
        error: e,
        stackTrace: st,
      );
    } finally {
      _isSyncing = false;
    }
  }

  /// 起動 / フォアグラウンド復帰 / 手動ボタン から呼ぶ。
  /// 全所属グループに対し push → pull を実行。
  Future<void> syncAll() async {
    final AppDatabase? db = _db;
    if (db == null) {
      PetloLogger.instance.d('SyncService: db not bound, skipping');
      return;
    }
    if (_isSyncing) {
      PetloLogger.instance.d('SyncService: already syncing, skipping');
      return;
    }
    _isSyncing = true;
    try {
      // 所属グループ (active のみ) を取得
      final List<GroupEntity> groups = await (db.select(db.groups)
            ..where(($GroupsTable t) =>
                t.status.equalsValue(GroupStatus.active)))
          .get();
      if (groups.isEmpty) {
        PetloLogger.instance.d('SyncService: no active groups');
        return;
      }
      for (final GroupEntity g in groups) {
        try {
          await _pushGroup(db, g.remoteId);
          await _pullGroup(db, g.remoteId);
        } catch (e, st) {
          PetloLogger.instance.w(
            'SyncService: group ${g.remoteId} failed',
            error: e,
            stackTrace: st,
          );
          // 1 グループ失敗でも他は試みる
        }
      }
      _lastSyncAt = DateTime.now();
    } finally {
      _isSyncing = false;
    }
  }

  // ==========================================================================
  // PUSH
  // ==========================================================================
  Future<void> _pushGroup(AppDatabase db, String groupId) async {
    // 100 件ずつバッチで処理。
    while (true) {
      final List<SyncQueueItemEntity> batch = await (db.select(db.syncQueue)
            ..where((SyncQueue t) => t.groupId.equals(groupId))
            ..orderBy(<OrderClauseGenerator<SyncQueue>>[
              (SyncQueue t) => OrderingTerm(expression: t.id),
            ])
            ..limit(100))
          .get();
      if (batch.isEmpty) return;

      final List<Map<String, dynamic>> operations = <Map<String, dynamic>>[];
      final List<int> skippedIds = <int>[];

      for (final SyncQueueItemEntity row in batch) {
        final Map<String, dynamic>? op = await _buildOperation(db, row);
        if (op == null) {
          // 行を読めない (hard delete された等) → invalid_operation 扱いで除去
          skippedIds.add(row.id);
          continue;
        }
        operations.add(op);
      }

      // 読めなかった分は先に削除しておく
      if (skippedIds.isNotEmpty) {
        await (db.delete(db.syncQueue)
              ..where((SyncQueue t) => t.id.isIn(skippedIds)))
            .go();
      }

      if (operations.isEmpty) {
        // 全 skip ならバッチ進める意味なし
        if (skippedIds.length == batch.length) return;
        continue;
      }

      // backend へ送信
      Map<String, dynamic>? respBody;
      try {
        final Response<dynamic> resp = await ApiDio.instance.post<dynamic>(
          '/sync/push',
          data: <String, dynamic>{'operations': operations},
        );
        respBody = resp.data is Map<String, dynamic>
            ? resp.data as Map<String, dynamic>
            : null;
      } on DioException catch (e) {
        // 通信失敗 → リトライ。attempts++、queue は残す。
        await _bumpAttempts(db, batch.map((r) => r.id).toList(),
            e.message ?? e.type.toString());
        return;
      }
      if (respBody == null) return;

      final Set<String> accepted = (respBody['accepted'] as List<dynamic>?)
              ?.whereType<String>()
              .toSet() ??
          <String>{};
      final List<dynamic> rejectedRaw =
          (respBody['rejected'] as List<dynamic>?) ?? <dynamic>[];
      final Map<String, String> rejectedReason = <String, String>{
        for (final dynamic r in rejectedRaw)
          if (r is Map<String, dynamic> && r['opId'] is String)
            r['opId'] as String:
                (r['reason'] as String?) ?? 'unknown',
      };

      // accepted: queue から削除 + entity を synced にマーク
      final List<SyncQueueItemEntity> acceptedRows =
          batch.where((r) => accepted.contains(r.opId)).toList();
      if (acceptedRows.isNotEmpty) {
        await db.transaction(() async {
          await (db.delete(db.syncQueue)
                ..where((SyncQueue t) =>
                    t.id.isIn(acceptedRows.map((r) => r.id))))
              .go();
          // 各 entity の sync_status を 'synced' に更新 (deletedAt の場合も含む)
          for (final SyncQueueItemEntity row in acceptedRows) {
            await db.customStatement(
              'UPDATE ${row.targetTable} SET sync_status = ? WHERE id = ?',
              <Object?>['synced', row.recordId],
            );
          }
        });
      }

      // rejected: reason 別処理
      for (final SyncQueueItemEntity row in batch) {
        final String? reason = rejectedReason[row.opId];
        if (reason == null) continue; // accepted か unknown
        switch (reason) {
          case 'stale':
            // サーバーが新しい。ローカル変更は破棄して queue から削除。
            // entity 自体は次回 pull で正しい状態に上書きされる前提。
            await (db.delete(db.syncQueue)
                  ..where((SyncQueue t) => t.id.equals(row.id)))
                .go();
            PetloLogger.instance
                .d('SyncService: stale op ${row.opId} discarded');
          case 'pet_not_found':
            // 関連 pet がまだサーバーに無い → 次回 pet 同期後にリトライ。
            // attempts++ で残す。
            await _bumpAttempts(db, <int>[row.id], reason);
            PetloLogger.instance.d(
                'SyncService: pet_not_found, will retry op ${row.opId}');
          case 'not_a_member':
          case 'forbidden':
          case 'invalid_operation':
          default:
            // 異常系 → queue から削除 + ログ
            await (db.delete(db.syncQueue)
                  ..where((SyncQueue t) => t.id.equals(row.id)))
                .go();
            PetloLogger.instance.w(
              'SyncService: op ${row.opId} rejected ($reason), dropped',
            );
        }
      }
      // 進捗無しの場合 (全 reject かつ pet_not_found で残った等) → 次回まで保留
      final int processed = acceptedRows.length +
          rejectedReason.entries
              .where((MapEntry<String, String> e) =>
                  e.value != 'pet_not_found')
              .length;
      if (processed == 0) return;
    }
  }

  /// (targetTable, recordId) からローカル行を読み出して backend 用の
  /// operation map を組み立てる。行が見つからなければ null。
  ///
  /// build 44 (Phase G2): entityType に 'pet_scope' を追加。
  /// `pet_scopes` 行に対する変更を server に伝達するために使う。
  /// server-side fanout (Phase G3) を想定: client は primary scope への 1 経路
  /// だけ push し、subscriber 群への配信はサーバ側が行う。
  Future<Map<String, dynamic>?> _buildOperation(
    AppDatabase db,
    SyncQueueItemEntity row,
  ) async {
    final Map<String, Object?>? data =
        await _readRow(db, row.targetTable, row.recordId);
    if (data == null) return null;

    final bool isPet = row.targetTable == 'pets';
    final bool isPetScope = row.targetTable == 'pet_scopes';
    final String entityType = isPet
        ? 'pet'
        : (isPetScope ? 'pet_scope' : 'record');

    // record / pet_scope の場合は pet_id を抜き出して petClientId に詰める
    int? petClientId;
    if (!isPet) {
      final dynamic raw = data['pet_id'];
      if (raw is int) {
        petClientId = raw;
      } else if (raw is num) {
        petClientId = raw.toInt();
      }
    }

    // backend は "create" を期待 — Flutter 側の enum は `insert`
    final String typeStr =
        row.operation == SyncOperation.insert ? 'create' : row.operation.name;
    final bool isDelete = row.operation == SyncOperation.delete;

    return <String, dynamic>{
      'opId': row.opId,
      'type': typeStr,
      'entityType': entityType,
      if (!isPet && !isPetScope) 'tableName': row.targetTable,
      'groupId': row.groupId,
      'clientEntityId': row.recordId,
      if (petClientId != null) 'petClientId': petClientId,
      // backend 契約: payload は create/update のみ必須、delete では送らない
      if (!isDelete) 'payload': data,
      'clientTimestamp': row.clientTimestamp,
    };
  }

  Future<Map<String, Object?>?> _readRow(
    AppDatabase db,
    String table,
    int id,
  ) async {
    try {
      final result = await db.customSelect(
        'SELECT * FROM $table WHERE id = ?',
        variables: <Variable<Object>>[Variable<int>(id)],
      ).getSingleOrNull();
      return result?.data;
    } catch (e) {
      PetloLogger.instance.d('SyncService._readRow($table:$id) failed: $e');
      return null;
    }
  }

  Future<void> _bumpAttempts(
    AppDatabase db,
    List<int> ids,
    String error,
  ) async {
    if (ids.isEmpty) return;
    final int t = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.customStatement(
      'UPDATE sync_queue SET attempts = attempts + 1, last_error = ?, '
      'last_attempt_at = ? WHERE id IN (${List<String>.filled(ids.length, '?').join(',')})',
      <Object?>[error, t, ...ids],
    );
  }

  // ==========================================================================
  // PULL
  // ==========================================================================
  Future<void> _pullGroup(AppDatabase db, String groupId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String sinceKey = 'sync.next_since.$groupId';
    final int since = prefs.getInt(sinceKey) ?? 0;

    Response<dynamic> resp;
    try {
      resp = await ApiDio.instance.get<dynamic>(
        '/sync/pull',
        queryParameters: <String, dynamic>{
          'groupId': groupId,
          'since': since,
        },
      );
    } on DioException catch (e) {
      PetloLogger.instance.w(
        'SyncService: pull failed (group=$groupId since=$since): ${e.message}',
      );
      return;
    }
    final dynamic body = resp.data;
    if (body is! Map<String, dynamic>) return;

    final List<dynamic> pets = (body['pets'] as List<dynamic>?) ?? const [];
    final List<dynamic> records =
        (body['records'] as List<dynamic>?) ?? const [];
    // build 44 (Phase G2): server-side fanout で配信される pet_scopes イベント。
    // backend (Phase G3) で実装予定、それまでは empty list が来る想定。
    final List<dynamic> petScopes =
        (body['petScopes'] as List<dynamic>?) ?? const [];

    // upsert を 1 トランザクションで実行
    final Set<String> touchedTables = <String>{};
    await db.transaction(() async {
      for (final dynamic p in pets) {
        if (p is! Map<String, dynamic>) continue;
        if (await _applyPetEvent(db, p, groupId)) {
          touchedTables.add('pets');
        }
      }
      for (final dynamic r in records) {
        if (r is! Map<String, dynamic>) continue;
        final String? table = r['tableName'] as String?;
        if (table == null) continue;
        if (await _applyRecordEvent(db, r, groupId, table)) {
          touchedTables.add(table);
        }
      }
      for (final dynamic s in petScopes) {
        if (s is! Map<String, dynamic>) continue;
        if (await _applyPetScopeEvent(db, s, groupId)) {
          touchedTables.add('pet_scopes');
        }
      }
    });

    // drift watchers 発火
    if (touchedTables.isNotEmpty) {
      db.notifyUpdates(<TableUpdate>{
        for (final String t in touchedTables) TableUpdate(t, kind: UpdateKind.update),
      });
    }

    // nextSince を保存 (server 提供のクライアント時計に依存しない値)
    final dynamic next = body['nextSince'];
    if (next is num) {
      await prefs.setInt(sinceKey, next.toInt());
    } else if (body['serverTimestamp'] is num) {
      // backup として serverTimestamp も受け入れ
      await prefs.setInt(sinceKey, (body['serverTimestamp'] as num).toInt());
    }
  }

  /// payload は backend の不透明 JSON。中身は `_readRow` で送ったときと
  /// 同じカラム名キーを期待する (蓄積された shared_pets.payload は
  /// その形で保管される設計)。
  ///
  /// build 44 (Phase G2): LWW を pull 側で実装。ローカル行の
  /// `last_modified_at_client` と payload の同名フィールドを比較し、ローカルが
  /// 新しければ apply をスキップする。ローカル変更が server pull で上書きされる
  /// 事故を防ぐ。
  Future<bool> _applyPetEvent(
    AppDatabase db,
    Map<String, dynamic> event,
    String groupId,
  ) async {
    final int? clientId = (event['clientPetId'] as num?)?.toInt();
    if (clientId == null) return false;
    final dynamic rawPayload = event['payload'];
    final Map<String, dynamic>? payload = rawPayload is String
        ? jsonDecode(rawPayload) as Map<String, dynamic>?
        : (rawPayload is Map<String, dynamic> ? rawPayload : null);
    if (payload == null) return false;

    // group_id は event 側を尊重して上書き
    payload['group_id'] = groupId;
    // id は client id を採用 (ローカル PK と一致させる)
    payload['id'] = clientId;
    final num? deletedAt = event['deletedAt'] as num?;
    if (deletedAt != null) payload['deleted_at'] = deletedAt.toInt();

    if (!await _isPayloadFresher(db, 'pets', clientId, payload)) {
      return false; // ローカルが新しい → スキップ
    }

    await _upsertByPk(db, 'pets', payload);
    return true;
  }

  Future<bool> _applyRecordEvent(
    AppDatabase db,
    Map<String, dynamic> event,
    String groupId,
    String tableName,
  ) async {
    final int? clientId = (event['clientRecordId'] as num?)?.toInt();
    if (clientId == null) return false;
    final dynamic rawPayload = event['payload'];
    final Map<String, dynamic>? payload = rawPayload is String
        ? jsonDecode(rawPayload) as Map<String, dynamic>?
        : (rawPayload is Map<String, dynamic> ? rawPayload : null);
    if (payload == null) return false;

    payload['group_id'] = groupId;
    payload['id'] = clientId;
    final dynamic petServer = event['petId'];
    if (petServer is num) {
      payload['pet_id'] = petServer.toInt();
    }
    final num? deletedAt = event['deletedAt'] as num?;
    if (deletedAt != null) payload['deleted_at'] = deletedAt.toInt();

    if (!await _isPayloadFresher(db, tableName, clientId, payload)) {
      return false; // ローカルが新しい → スキップ
    }

    await _upsertByPk(db, tableName, payload);
    return true;
  }

  /// build 44 (Phase G2): pet_scope イベントの apply。
  /// payload 形式は `_buildOperation` で送ったときと同じ snake_case 列キー。
  /// LWW: permission の race だけは server-side rule (owner 優先) に委ねる
  /// 想定なので、client 側は受信値をそのまま信じて upsert する
  /// (Decision Log #3)。
  Future<bool> _applyPetScopeEvent(
    AppDatabase db,
    Map<String, dynamic> event,
    String groupId,
  ) async {
    final int? clientId = (event['clientScopeId'] as num?)?.toInt();
    if (clientId == null) return false;
    final dynamic rawPayload = event['payload'];
    final Map<String, dynamic>? payload = rawPayload is String
        ? jsonDecode(rawPayload) as Map<String, dynamic>?
        : (rawPayload is Map<String, dynamic> ? rawPayload : null);
    if (payload == null) return false;

    // group_id は event 側 (= サーバが配信する scope) を尊重して上書き
    payload['group_id'] = groupId;
    payload['id'] = clientId;
    final num? deletedAt = event['deletedAt'] as num?;
    if (deletedAt != null) payload['deleted_at'] = deletedAt.toInt();

    if (!await _isPayloadFresher(db, 'pet_scopes', clientId, payload)) {
      return false;
    }

    await _upsertByPk(db, 'pet_scopes', payload);
    return true;
  }

  /// LWW 判定: 該当行の `last_modified_at_client` を読み、payload より古ければ
  /// true (上書きしてよい) を返す。ローカルにまだ行がなければ常に true。
  /// 比較対象カラムが無いテーブル / payload にも無い場合は安全側で true を返す。
  Future<bool> _isPayloadFresher(
    AppDatabase db,
    String table,
    int recordId,
    Map<String, dynamic> payload,
  ) async {
    final dynamic remoteRaw = payload['last_modified_at_client'];
    if (remoteRaw is! num) {
      return true; // payload に時計情報なし → 比較不能、上書き許可
    }
    try {
      final QueryRow? row = await db.customSelect(
        'SELECT last_modified_at_client FROM $table WHERE id = ?',
        variables: <Variable<Object>>[Variable<int>(recordId)],
      ).getSingleOrNull();
      if (row == null) return true; // ローカル行なし → 上書き許可
      final dynamic localRaw = row.data['last_modified_at_client'];
      if (localRaw is! num) return true; // ローカル時計なし → 上書き許可
      // payload の時計の方が新しいかちょうど同じなら上書き許可。
      // ローカルの方が厳密に新しい時のみスキップする。
      return remoteRaw.toInt() >= localRaw.toInt();
    } catch (_) {
      // 列が存在しない等の例外時は安全側で上書き
      return true;
    }
  }

  /// INSERT OR REPLACE で payload を行に焼く。
  /// payload は snake_case の列名キーを持つ Map である前提。
  Future<void> _upsertByPk(
    AppDatabase db,
    String table,
    Map<String, dynamic> payload,
  ) async {
    if (payload.isEmpty) return;
    final List<String> cols = payload.keys.toList();
    final String placeholders = List<String>.filled(cols.length, '?').join(', ');
    final List<Object?> values = cols.map((String c) => payload[c]).toList();
    try {
      await db.customStatement(
        'INSERT OR REPLACE INTO $table (${cols.join(',')}) VALUES ($placeholders)',
        values,
      );
    } catch (e, st) {
      PetloLogger.instance
          .w('SyncService._upsertByPk($table) failed', error: e, stackTrace: st);
    }
  }
}
