// ============================================================================
// petlo - Backup Archive Service (build 62 export / build 64 import)
// ============================================================================
//
// Free / Pro を問わず、すべてのユーザが DB + 写真サブツリーを 1 つの ZIP に
// 書き出し / 取り込みできるようにする。
//
// === exportToZip (build 62) ===
//   1. drift DB を WAL checkpoint(TRUNCATE) → 一時ディレクトリに sqlite コピー
//   2. Documents 直下の写真サブツリーを ZIP に追加(相対パス保持)
//   3. _meta.json 同梱 ({app, schemaVersion, appBuild, exportedAt, petCount,
//      photoCount})
//   4. ファイル名: petlo_backup_YYYYMMDD_HHmm.zip。共有は呼び出し側 (UI)
//
// === importFromZip (build 64) ===
//   1. ZIP を一時ディレクトリに展開、_meta.json を検証
//   2. 既存 Documents/{petlo.sqlite, photoSubdirs} を rollback ディレクトリに
//      フルコピー(失敗時の完全復元のため、参照ではなくコピー)
//   3. drift DB を close (UI から渡される callback で実施)
//   4. ZIP 内 sqlite を Documents/petlo.sqlite に上書き、写真ツリーを差し替え
//   5. 同期カーソル (sync.next_since.*) をリセット
//   6. 成功 → rollback ディレクトリ破棄。アプリ再起動を案内
//   7. 失敗 → rollback から完全復元、データは 1 バイトも失わせない
//
// 設計判断:
//   - ZIP 構築 / 展開 / 写真ツリー snapshot は compute() で別 isolate に
//     追い出して UI を止めない。
//   - rollback はトランザクション的に: 退避が完了するまで書き込みを始めない、
//     失敗時は退避から完全復元、両方失敗した場合は rollback ディレクトリを
//     残してユーザに通知 (手動復旧の余地を残す)。
//
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart' show DioException, Options, Response;
import 'package:drift/drift.dart' show QueryRow, Variable;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/local/app_database.dart';
import '../auth/api_dio.dart';
import '../constants/app_constants.dart';
import '../preferences/user_preferences.dart';
import '../utils/logger.dart';

/// バックアップ対象となる写真サブディレクトリ。
/// `lib/data/storage/photo_storage.dart` のサブディレクトリ規則と同期する。
const List<String> _photoSubdirs = <String>[
  'pets',
  'meals',
  'diaries',
  'visits',
  'ai_diagnoses',
];

/// 出力ファイル名: petlo_backup_YYYYMMDD_HHmm.zip
@visibleForTesting
String backupFileNameFor(DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  final String stamp =
      '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
  return 'petlo_backup_$stamp.zip';
}

/// エクスポート結果。
class BackupExportResult {
  const BackupExportResult({
    required this.zipPath,
    required this.exportedAt,
    required this.petCount,
    required this.photoCount,
    required this.sizeBytes,
  });

  final String zipPath;
  final DateTime exportedAt;
  final int petCount;
  final int photoCount;
  final int sizeBytes;
}

/// クラウドへの送信成功結果 (build 68)。
class BackupCloudUploadResult {
  const BackupCloudUploadResult({
    required this.completedAt,
    required this.byteSize,
  });
  final DateTime completedAt;
  final int byteSize;
}

/// `GET /backup/status` のレスポンスを表す (build 68)。
class CloudBackupStatus {
  const CloudBackupStatus({
    required this.exists,
    this.updatedAt,
    this.byteSize,
  });
  final bool exists;
  final DateTime? updatedAt;
  final int? byteSize;
}

/// build 69: クラウドにバックアップが無い (`GET /backup` が 404) ことを表す。
/// `BackupImportException` とは別系統 — 失敗ではなく「データ無し」状態。
class CloudBackupNotFound implements Exception {
  const CloudBackupNotFound();
  @override
  String toString() => 'CloudBackupNotFound: server returned 404';
}

class BackupArchiveService {
  BackupArchiveService(this._db);

  final AppDatabase _db;

  /// ZIP を作成して結果を返す。共有シートの起動は呼び出し側 (UI 層) で
  /// `Share.shareXFiles` を直接呼ぶ。`sharePositionOrigin` を渡すために UI
  /// 側で握る必要があるので、service は path を返すだけに分離した
  /// (build 63)。
  Future<BackupExportResult> exportToZip() async {
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory tempRoot = await getTemporaryDirectory();
    final DateTime exportedAt = DateTime.now();

    final Directory work = await Directory(
      p.join(tempRoot.path, 'petlo_backup_${exportedAt.microsecondsSinceEpoch}'),
    ).create(recursive: true);

    final String fileName = backupFileNameFor(exportedAt);
    final String outZipPath = p.join(work.path, fileName);
    final String dbSnapshotPath = p.join(work.path, 'petlo.sqlite');

    try {
      await _checkpointAndCopyDb(dbSnapshotPath);

      final int petCount = await _countPets();

      final _ZipBuildResult built = await compute<_ZipBuildArgs, _ZipBuildResult>(
        _buildZipInIsolate,
        _ZipBuildArgs(
          dbSnapshotPath: dbSnapshotPath,
          photosRootPath: docs.path,
          photoSubdirs: _photoSubdirs,
          outZipPath: outZipPath,
          manifest: <String, Object?>{
            'app': 'petlo',
            'schemaVersion': _db.schemaVersion,
            'appBuild': AppConstants.appBuildNumber,
            'exportedAt': exportedAt.toUtc().toIso8601String(),
            'petCount': petCount,
          },
        ),
      );

      // DB スナップショットは ZIP に取り込み済み — 早めに削除。
      await _safeDelete(File(dbSnapshotPath));

      final File outFile = File(built.zipPath);
      final int size = await outFile.length();

      return BackupExportResult(
        zipPath: built.zipPath,
        exportedAt: exportedAt,
        petCount: petCount,
        photoCount: built.photoCount,
        sizeBytes: size,
      );
    } catch (e, st) {
      PetloLogger.instance.w(
        'BackupArchiveService.exportToZip failed',
        error: e,
        stackTrace: st,
      );
      // 失敗時の一時ファイルは取り残さない。
      await _safeDelete(File(dbSnapshotPath));
      await _safeDelete(File(outZipPath));
      await _safeDeleteDir(work);
      rethrow;
    }
  }

  // ==========================================================================
  // Cloud backup (build 68)
  // ==========================================================================

  /// クラウド R2 へバックアップを送信する。
  ///
  /// 流れ:
  ///   1. [exportToZip] で ZIP を一時 work dir に作成
  ///   2. `File.openRead()` で Stream 化して `POST /backup` に流す
  ///      (`Content-Length` ヘッダを明示、`Content-Type: application/zip`)
  ///   3. 成功 → [BackupCloudUploadResult] を返す
  ///   4. `finally` で work dir を丸ごと削除 (export ZIP は v1.0 ではローカル
  ///      に残す意味がない、share_plus 経路でないため)
  ///
  /// 失敗時は例外を rethrow。UI 層で [DioException] / `BackupImportException`
  /// と同じくキャッチして SnackBar 等に変換する。
  ///
  /// [onSendProgress] は Dio の同名コールバックを素通しする。`(sent, total)`
  /// は upload バイト数 (= ZIP サイズ) と進捗バイト数で、`total` は Dio が
  /// `Content-Length` から復元する。
  Future<BackupCloudUploadResult> uploadToCloud({
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final BackupExportResult export = await exportToZip();
    final File zipFile = File(export.zipPath);
    final Directory workDir = zipFile.parent;
    try {
      await ApiDio.instance.post<dynamic>(
        '/backup',
        data: zipFile.openRead(),
        options: Options(
          headers: <String, dynamic>{
            'Content-Length': export.sizeBytes,
          },
          contentType: 'application/zip',
          // 数十 MB アップロード中に default 10s で send が切れないよう
          // 余裕を持って 5 分。slow 3G 想定。
          sendTimeout: const Duration(minutes: 5),
          // サーバが R2 put 完了まで待つので default 30s でも足りるが
          // 念のため 1 分。
          receiveTimeout: const Duration(minutes: 1),
        ),
        onSendProgress: onSendProgress,
      );
      return BackupCloudUploadResult(
        completedAt: DateTime.now(),
        byteSize: export.sizeBytes,
      );
    } catch (e, st) {
      PetloLogger.instance.w(
        'BackupArchiveService.uploadToCloud failed',
        error: e,
        stackTrace: st,
      );
      rethrow;
    } finally {
      await _safeDeleteDir(workDir);
    }
  }

  /// サーバが保持しているクラウドバックアップの状態を取得 (GET /backup/status)。
  /// レスポンス形: `{ exists: bool, updatedAt: int?, byteSize: int? }`
  /// (updatedAt は ms epoch)
  Future<CloudBackupStatus> fetchCloudStatus() async {
    final Response<dynamic> resp =
        await ApiDio.instance.get<dynamic>('/backup/status');
    final Object? data = resp.data;
    if (data is! Map<String, dynamic>) {
      throw StateError(
        'Invalid /backup/status response shape: ${data.runtimeType}',
      );
    }
    final bool exists = data['exists'] == true;
    final Object? updatedAtRaw = data['updatedAt'];
    final Object? byteSizeRaw = data['byteSize'];
    return CloudBackupStatus(
      exists: exists,
      updatedAt: updatedAtRaw is int
          ? DateTime.fromMillisecondsSinceEpoch(updatedAtRaw)
          : null,
      byteSize: byteSizeRaw is int ? byteSizeRaw : null,
    );
  }

  /// build 69: クラウド R2 からバックアップを取得して既存 [importFromZip] の
  /// rollback-safe pipeline に流す。
  ///
  /// 流れ:
  ///   1. tempDir 配下に一時 zip パスを用意
  ///   2. `ApiDio.instance.download('/backup', tempZipPath)` で取得
  ///   3. **404 の場合は [CloudBackupNotFound]** を投げる (専用例外)
  ///   4. importFromZip(zipPath, closeDatabase) で 9-stage 復元
  ///   5. `finally` で temp zip を削除
  ///
  /// 失敗系:
  ///   - 404 → [CloudBackupNotFound] (UI 側は「データ無しで続行」扱い)
  ///   - その他 [DioException] / [BackupImportException] → 素通し (UI が処理)
  Future<BackupImportResult> downloadAndRestoreFromCloud({
    required Future<void> Function() closeDatabase,
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    final Directory tempRoot = await getTemporaryDirectory();
    final int ts = DateTime.now().microsecondsSinceEpoch;
    final String tempZipPath = p.join(tempRoot.path, 'petlo_cloud_$ts.zip');

    try {
      // === Stage 1: download ===
      try {
        await ApiDio.instance.download(
          '/backup',
          tempZipPath,
          onReceiveProgress: onReceiveProgress,
          options: Options(
            // 数十 MB を 3G 等で取得するケースを想定。
            receiveTimeout: const Duration(minutes: 5),
          ),
        );
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          PetloLogger.instance.i('cloud restore: no backup on server');
          throw const CloudBackupNotFound();
        }
        PetloLogger.instance.w(
          'cloud restore: download failed '
          'status=${e.response?.statusCode}',
          error: e,
        );
        rethrow;
      }

      // === Stage 2: import (rollback-safe pipeline をそのまま流用) ===
      return await importFromZip(
        zipPath: tempZipPath,
        closeDatabase: closeDatabase,
      );
    } finally {
      await _safeDelete(File(tempZipPath));
    }
  }

  Future<void> _checkpointAndCopyDb(String snapshotPath) async {
    await _db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    final Directory docs = await getApplicationDocumentsDirectory();
    final File src = File(p.join(docs.path, 'petlo.sqlite'));
    if (!await src.exists()) {
      throw StateError('Database file not found at ${src.path}');
    }
    await src.copy(snapshotPath);
  }

  Future<int> _countPets() async {
    final List<QueryRow> rows = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM pets WHERE deleted_at IS NULL',
          variables: const <Variable<Object>>[],
        )
        .get();
    if (rows.isEmpty) return 0;
    return rows.first.read<int>('c');
  }

  // ==========================================================================
  // Import (build 64)
  // ==========================================================================

  /// ZIP を取り込んで DB + 写真を完全復元する。
  ///
  /// pipeline (各段で失敗したら前段に rollback):
  ///   1. ZIP を一時ディレクトリに展開
  ///   2. _meta.json を検証 (app == "petlo", schemaVersion <= 現在)
  ///   3. 既存 Documents の snapshot を rollback dir に作成
  ///   4. [closeDatabase] callback で drift DB を close
  ///   5. ZIP 内容を Documents に適用 (sqlite 上書き、写真サブツリー差し替え)
  ///   6. sync カーソルを reset
  ///   7. 成功 → rollback dir 破棄、戻り値で manifest を返す
  ///   8. 失敗 → rollback dir から Documents を完全復元、 rethrow
  ///
  /// 呼び出し側は戻り値受領後にアプリ再起動を案内するべき。再起動後の
  /// main.dart 起動で drift DB が新しい sqlite ファイルを開き直す。
  Future<BackupImportResult> importFromZip({
    required String zipPath,
    required Future<void> Function() closeDatabase,
  }) async {
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory tempRoot = await getTemporaryDirectory();
    final int ts = DateTime.now().microsecondsSinceEpoch;
    final Directory sessionDir = Directory(
      p.join(tempRoot.path, 'petlo_import_$ts'),
    );
    final Directory extractDir = Directory(p.join(sessionDir.path, 'extract'));
    final Directory rollbackDir =
        Directory(p.join(sessionDir.path, 'rollback'));

    bool rollbackCommitted = false;
    bool rollbackUsed = false;

    try {
      await sessionDir.create(recursive: true);
      await extractDir.create();

      // === Stage 1: extract ZIP into extract dir (isolate) ===
      await compute<_ExtractArgs, void>(
        _extractZipInIsolate,
        _ExtractArgs(
          zipPath: zipPath,
          extractDirPath: extractDir.path,
          allowedSubdirs: _photoSubdirs,
        ),
      );

      // === Stage 2: validate _meta.json ===
      final BackupManifest manifest =
          await _readAndValidateManifest(extractDir);

      // === Stage 3: snapshot Documents to rollback dir (isolate) ===
      await rollbackDir.create();
      await compute<_SnapshotArgs, void>(
        _snapshotForRollbackInIsolate,
        _SnapshotArgs(
          docsPath: docs.path,
          rollbackDirPath: rollbackDir.path,
          photoSubdirs: _photoSubdirs,
        ),
      );

      // === Stage 4: close DB (file handle must be released before overwrite) ===
      // ここまでで失敗していれば DB は触っていない → rollback 不要。
      await closeDatabase();

      // === Stage 5: apply extracted content to Documents (isolate) ===
      // ここで失敗したら Documents は中途半端な状態 → rollback 必須。
      try {
        await compute<_ApplyArgs, void>(
          _applyExtractedToDocumentsInIsolate,
          _ApplyArgs(
            extractDirPath: extractDir.path,
            docsPath: docs.path,
            photoSubdirs: _photoSubdirs,
          ),
        );
      } catch (e, st) {
        PetloLogger.instance.e(
          'importFromZip: apply failed, rolling back',
          error: e,
          stackTrace: st,
        );
        rollbackUsed = true;
        await compute<_SnapshotArgs, void>(
          _restoreFromRollbackInIsolate,
          _SnapshotArgs(
            docsPath: docs.path,
            rollbackDirPath: rollbackDir.path,
            photoSubdirs: _photoSubdirs,
          ),
        );
        rethrow;
      }

      // === Stage 6: reset sync cursors ===
      // ここで失敗しても DB / 写真は復元済みなので rollback 不要 (戻り値で
      // 警告は出せるが、ユーザデータは無事)。
      await _resetSyncCursors();

      // === Stage 7: success → discard rollback ===
      rollbackCommitted = true;
      return BackupImportResult(
        manifest: manifest,
        rolledBack: false,
      );
    } catch (e, st) {
      PetloLogger.instance.w(
        'BackupArchiveService.importFromZip failed',
        error: e,
        stackTrace: st,
      );
      // rollback 未実行で Stage 5 より前で死んだ場合は Documents 無傷。
      // Stage 5 で失敗して rollback 実行済み (rollbackUsed=true) なら完全復元済み。
      // どちらも「ユーザデータ無事」状態だが、呼び出し側に伝える。
      rethrow;
    } finally {
      // rollback ディレクトリは「成功時」または「rollback まで完了した時」のみ
      // 破棄する。どちらにも該当しない (rollback の最中に死んだ) ケースは
      // rollback ディレクトリを残しておく → ユーザに「アプリを再起動して
      // ください」のメッセージで案内、起動時検出は v1.1 で。
      final bool safeToDeleteRollback = rollbackCommitted || rollbackUsed;
      if (safeToDeleteRollback) {
        await _safeDeleteDir(rollbackDir);
      } else {
        PetloLogger.instance.w(
          'importFromZip: rollback dir kept at ${rollbackDir.path} '
          'for manual recovery',
        );
      }
      // 展開ディレクトリは常に破棄してよい (ZIP のコピーなのでロスなし)。
      await _safeDeleteDir(extractDir);
      // sessionDir 自体は rollback dir が残っていなければ破棄。
      if (safeToDeleteRollback) {
        await _safeDeleteDir(sessionDir);
      }
    }
  }

  /// _meta.json を読み込んで以下を検証:
  ///   - app == "petlo"
  ///   - schemaVersion が int で現在の drift schema version 以下
  ///   - extractDir/petlo.sqlite が実在
  Future<BackupManifest> _readAndValidateManifest(Directory extractDir) async {
    final File metaFile = File(p.join(extractDir.path, '_meta.json'));
    if (!await metaFile.exists()) {
      throw const BackupImportException(
        BackupImportFailure.invalidFile,
        'missing _meta.json',
      );
    }
    final Object? raw =
        jsonDecode(await metaFile.readAsString()) as Object?;
    if (raw is! Map<String, Object?>) {
      throw const BackupImportException(
        BackupImportFailure.invalidFile,
        '_meta.json is not an object',
      );
    }
    final Object? app = raw['app'];
    if (app != 'petlo') {
      throw BackupImportException(
        BackupImportFailure.invalidFile,
        'app != "petlo" (got $app)',
      );
    }
    final Object? schemaRaw = raw['schemaVersion'];
    final int? schema = schemaRaw is int ? schemaRaw : null;
    if (schema == null) {
      throw const BackupImportException(
        BackupImportFailure.invalidFile,
        'schemaVersion missing or non-int',
      );
    }
    if (schema > _db.schemaVersion) {
      throw BackupImportException(
        BackupImportFailure.versionTooNew,
        'backup schema $schema > app schema ${_db.schemaVersion}',
      );
    }
    final File sqliteEntry = File(p.join(extractDir.path, 'petlo.sqlite'));
    if (!await sqliteEntry.exists()) {
      throw const BackupImportException(
        BackupImportFailure.invalidFile,
        'missing petlo.sqlite in archive',
      );
    }
    return BackupManifest(
      schemaVersion: schema,
      appBuild: raw['appBuild'] is int ? raw['appBuild']! as int : 0,
      petCount: raw['petCount'] is int ? raw['petCount']! as int : 0,
      photoCount: raw['photoCount'] is int ? raw['photoCount']! as int : 0,
    );
  }

  /// `sync.next_since.<groupId>` 形式の全 cursor キーを削除。
  /// 復元後の DB は別タイミングのスナップショットなので、次回 sync で
  /// since=0 から全件再 pull させる。
  Future<void> _resetSyncCursors() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Set<String> toRemove = prefs
          .getKeys()
          .where((String k) => k.startsWith('sync.next_since.'))
          .toSet();
      for (final String k in toRemove) {
        await prefs.remove(k);
      }
      // build 73: 初回 fullPull 済みフラグも落とす。
      //
      // 復元した DB は「バックアップを取った時点」の状態であり、そこから
      // 現在までの差分はローカルに無い。カーソルを消すだけでは不十分で、
      // 「もう全件取得したことにする」フラグが立ったままだと次回起動で
      // fullPull が走らず、欠けたまま運用が続いてしまう
      // (Phase E で予防コースが 0 件のまま残った症状がこれ)。
      await prefs.remove(UserPreferences.kDidInitialFullPull);
      PetloLogger.instance.i(
        'importFromZip: cleared ${toRemove.length} sync cursor key(s) '
        '+ initial fullPull flag',
      );
    } catch (e, st) {
      PetloLogger.instance.w(
        'importFromZip: sync cursor reset failed (data still ok)',
        error: e,
        stackTrace: st,
      );
    }
  }

  static Future<void> _safeDelete(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {
      // 一時領域の取り残しは致命的ではないので握りつぶす。
    }
  }

  static Future<void> _safeDeleteDir(Directory d) async {
    try {
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {
      // 同上。
    }
  }
}

// ============================================================================
// Import 用 value types
// ============================================================================

class BackupManifest {
  const BackupManifest({
    required this.schemaVersion,
    required this.appBuild,
    required this.petCount,
    required this.photoCount,
  });
  final int schemaVersion;
  final int appBuild;
  final int petCount;
  final int photoCount;
}

class BackupImportResult {
  const BackupImportResult({
    required this.manifest,
    required this.rolledBack,
  });
  final BackupManifest manifest;
  final bool rolledBack;
}

enum BackupImportFailure {
  /// ZIP として読めない / app != "petlo" / 必須エントリ欠落 / _meta.json 壊れ
  invalidFile,

  /// 現在の drift schema より新しいバージョンで作られた ZIP
  versionTooNew,
}

class BackupImportException implements Exception {
  const BackupImportException(this.reason, this.detail);
  final BackupImportFailure reason;
  final String detail;
  @override
  String toString() => 'BackupImportException($reason): $detail';
}

// ============================================================================
// Isolate 側
// ============================================================================
//
// `compute()` に渡す引数 / 戻り値は const 化できる単純なデータのみ。
// ============================================================================

class _ZipBuildArgs {
  const _ZipBuildArgs({
    required this.dbSnapshotPath,
    required this.photosRootPath,
    required this.photoSubdirs,
    required this.outZipPath,
    required this.manifest,
  });

  final String dbSnapshotPath;
  final String photosRootPath;
  final List<String> photoSubdirs;
  final String outZipPath;
  final Map<String, Object?> manifest;
}

class _ZipBuildResult {
  const _ZipBuildResult({required this.zipPath, required this.photoCount});

  final String zipPath;
  final int photoCount;
}

/// 別 Isolate で動くトップレベル関数。
/// 1) DB スナップショットを追加
/// 2) 写真サブツリーを相対パス維持で追加
/// 3) _meta.json (photoCount を確定後に書き込み)
///
/// build 63: async 化して addFile / close をすべて await する。同期関数の
/// まま fire-and-forget だと、AOT (Release) で isolate 終了が microtask
/// drain より先行することがあり、 OutputFileStream の _fileHandle.close()
/// が完了する前に compute() が return → カーネルバッファが flush されない
/// 壊れた ZIP が main 側に渡る、という挙動になっていた可能性が高い。
/// JIT (Debug) は event loop が緩いので顕在化しない。
Future<_ZipBuildResult> _buildZipInIsolate(_ZipBuildArgs args) async {
  final ZipFileEncoder encoder = ZipFileEncoder()..create(args.outZipPath);
  int photoCount = 0;

  try {
    final File dbFile = File(args.dbSnapshotPath);
    if (dbFile.existsSync()) {
      await encoder.addFile(dbFile, 'petlo.sqlite');
    }

    for (final String sub in args.photoSubdirs) {
      final Directory dir = Directory(p.join(args.photosRootPath, sub));
      if (!dir.existsSync()) continue;
      for (final FileSystemEntity ent
          in dir.listSync(recursive: true, followLinks: false)) {
        if (ent is! File) continue;
        final String rel = p.relative(ent.path, from: args.photosRootPath);
        await encoder.addFile(ent, rel);
        photoCount++;
      }
    }

    final Map<String, Object?> manifest = <String, Object?>{
      ...args.manifest,
      'photoCount': photoCount,
    };
    final List<int> metaBytes =
        utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest));
    final ArchiveFile metaEntry =
        ArchiveFile('_meta.json', metaBytes.length, metaBytes);
    encoder.addArchiveFile(metaEntry);

    await encoder.close();
  } catch (_) {
    // 途中失敗時は encoder を閉じて (二重 close は内部で is-open 判定済) 、
    // 壊れた部分 ZIP を削除する。build 63 バグ C 対応。
    try {
      await encoder.close();
    } catch (_) {
      // close 自体が失敗してもこれ以上できることはない。
    }
    final File partial = File(args.outZipPath);
    if (partial.existsSync()) {
      try {
        partial.deleteSync();
      } catch (_) {
        // ignore
      }
    }
    rethrow;
  }

  return _ZipBuildResult(zipPath: args.outZipPath, photoCount: photoCount);
}

// ============================================================================
// Import 用 isolate (build 64)
// ============================================================================

class _ExtractArgs {
  const _ExtractArgs({
    required this.zipPath,
    required this.extractDirPath,
    required this.allowedSubdirs,
  });
  final String zipPath;
  final String extractDirPath;
  final List<String> allowedSubdirs;
}

class _SnapshotArgs {
  const _SnapshotArgs({
    required this.docsPath,
    required this.rollbackDirPath,
    required this.photoSubdirs,
  });
  final String docsPath;
  final String rollbackDirPath;
  final List<String> photoSubdirs;
}

class _ApplyArgs {
  const _ApplyArgs({
    required this.extractDirPath,
    required this.docsPath,
    required this.photoSubdirs,
  });
  final String extractDirPath;
  final String docsPath;
  final List<String> photoSubdirs;
}

/// ZIP を展開。エントリ名にゴミ (絶対パス / 親へ抜ける `..`) を含むものは
/// 拒否し、ホワイトリストに該当するもの (`petlo.sqlite`, `_meta.json`,
/// photoSubdirs 配下) だけを書き出す。zip-slip 対策。
Future<void> _extractZipInIsolate(_ExtractArgs args) async {
  final Archive archive = ZipDecoder().decodeBytes(
    File(args.zipPath).readAsBytesSync(),
    verify: true,
  );
  for (final ArchiveFile entry in archive.files) {
    if (!entry.isFile) continue;
    final String name = entry.name;
    if (!_isAcceptableEntryName(name, args.allowedSubdirs)) continue;

    final String outPath = p.normalize(p.join(args.extractDirPath, name));
    if (!p.isWithin(args.extractDirPath, outPath)) {
      // zip-slip 防御: 正規化後に extractDir の外に出るエントリは拒否
      continue;
    }
    final File outFile = File(outPath);
    await outFile.parent.create(recursive: true);
    final Object? content = entry.content;
    if (content is List<int>) {
      await outFile.writeAsBytes(content, flush: true);
    } else {
      // Stream 形式の場合 (archive 3.6: 通常は List<int> なのでここは fallback)
      await outFile.writeAsBytes(entry.content as List<int>, flush: true);
    }
  }
}

bool _isAcceptableEntryName(String name, List<String> allowedSubdirs) {
  if (name.startsWith('/')) return false;
  if (name.contains('..')) return false;
  if (name == 'petlo.sqlite' || name == '_meta.json') return true;
  for (final String sub in allowedSubdirs) {
    if (name.startsWith('$sub/')) return true;
  }
  return false;
}

/// 現在の Documents 配下の petlo.sqlite (+ wal/shm) と写真サブツリーを
/// rollbackDir にフルコピー。シンボリックリンクは辿らず、ファイルだけを
/// コピーする (権限ビットは保持しない: iOS sandbox 内なので不要)。
Future<void> _snapshotForRollbackInIsolate(_SnapshotArgs args) async {
  final Directory rollback = Directory(args.rollbackDirPath);
  await rollback.create(recursive: true);

  // sqlite + 補助ファイル
  for (final String fname in <String>[
    'petlo.sqlite',
    'petlo.sqlite-wal',
    'petlo.sqlite-shm',
  ]) {
    final File src = File(p.join(args.docsPath, fname));
    if (!src.existsSync()) continue;
    await src.copy(p.join(rollback.path, fname));
  }

  // 写真サブツリー
  for (final String sub in args.photoSubdirs) {
    final Directory srcDir = Directory(p.join(args.docsPath, sub));
    if (!srcDir.existsSync()) continue;
    final Directory dstDir = Directory(p.join(rollback.path, sub));
    await _copyDirRecursiveSync(srcDir, dstDir);
  }
}

/// Documents 配下を rollbackDir 内容で完全に置き換える (中身を空にしてから
/// rollback のコピーを書き戻す)。bug C 用の Apply で書き散らかしたファイルが
/// 残らないようにするため、写真サブツリーは丸ごと削除してから復元する。
Future<void> _restoreFromRollbackInIsolate(_SnapshotArgs args) async {
  final Directory rollback = Directory(args.rollbackDirPath);

  // 写真サブツリー: Documents 側を削除してから rollback から戻す。
  for (final String sub in args.photoSubdirs) {
    final Directory dst = Directory(p.join(args.docsPath, sub));
    if (dst.existsSync()) {
      dst.deleteSync(recursive: true);
    }
    final Directory src = Directory(p.join(rollback.path, sub));
    if (src.existsSync()) {
      await _copyDirRecursiveSync(src, dst);
    }
  }

  // sqlite: 書き戻し前に既存 wal/shm を消す (古い WAL が新 DB に紐付くと整合
  // が壊れる)。元 wal/shm が rollback に含まれていれば一緒に戻す。
  for (final String fname in <String>[
    'petlo.sqlite',
    'petlo.sqlite-wal',
    'petlo.sqlite-shm',
  ]) {
    final File dst = File(p.join(args.docsPath, fname));
    if (dst.existsSync()) {
      dst.deleteSync();
    }
    final File src = File(p.join(rollback.path, fname));
    if (src.existsSync()) {
      await src.copy(dst.path);
    }
  }
}

/// 展開 dir の内容を Documents に適用。
/// - sqlite: 既存 wal/shm を消してから上書き
/// - 写真: 既存サブツリーを削除してから ZIP の構造を配置
Future<void> _applyExtractedToDocumentsInIsolate(_ApplyArgs args) async {
  // sqlite を差し替える前に WAL の残骸を消しておく (古い journal が新しい
  // メイン DB に対して矛盾するため SQLite が開けなくなる)。
  for (final String fname in <String>['petlo.sqlite-wal', 'petlo.sqlite-shm']) {
    final File f = File(p.join(args.docsPath, fname));
    if (f.existsSync()) f.deleteSync();
  }
  final File extractedSqlite =
      File(p.join(args.extractDirPath, 'petlo.sqlite'));
  if (extractedSqlite.existsSync()) {
    final File dst = File(p.join(args.docsPath, 'petlo.sqlite'));
    if (dst.existsSync()) dst.deleteSync();
    await extractedSqlite.copy(dst.path);
  }

  // 写真サブツリー差し替え
  for (final String sub in args.photoSubdirs) {
    final Directory dst = Directory(p.join(args.docsPath, sub));
    if (dst.existsSync()) {
      dst.deleteSync(recursive: true);
    }
    final Directory src = Directory(p.join(args.extractDirPath, sub));
    if (src.existsSync()) {
      await _copyDirRecursiveSync(src, dst);
    }
  }
}

/// 再帰ファイルコピー (シンボリックリンクは無視、ファイルは中身コピー、
/// ディレクトリは構造再現)。dart:io の同期 API でシンプルに書く。
Future<void> _copyDirRecursiveSync(Directory src, Directory dst) async {
  await dst.create(recursive: true);
  for (final FileSystemEntity ent
      in src.listSync(recursive: true, followLinks: false)) {
    if (ent is! File) continue;
    final String rel = p.relative(ent.path, from: src.path);
    final File out = File(p.join(dst.path, rel));
    await out.parent.create(recursive: true);
    await ent.copy(out.path);
  }
}
