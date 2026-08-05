// ============================================================================
// petlo - App Database
// ============================================================================
//
// driftデータベース本体。全28テーブルを統合。
//
// 構成:
//   ペット中心:  pets
//   記録系(7):  meals, foods, poops, pees, vomits, weights, temperatures, diaries
//   健康(4):    visits, medications, vaccinations, bcs_checks
//   予定(2):    expiration_items, streak_statuses
//   予防(2):    prevention_courses, prevention_doses
//   共有(5):    groups, group_members, invite_codes, pending_transfers, cancel_feedback
//   AI(4):      ai_chat_messages, ai_sessions, ai_image_diagnoses, weekly_summaries
//   同期(3):    sync_queue, upload_queue, account_deletion_queue
//   合計:       29テーブル (build 72 で予防 2 テーブル追加)
//
// 使い方:
//   final db = AppDatabase();
//   await db.into(db.pets).insert(...);
//
// コード生成: `flutter pub run build_runner build`
//
// ============================================================================

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

// Converters と enums を library scope に import する。
// `app_database.g.dart` は part-of でこの library に統合されるので、
// drift が生成する型注釈 (`GeneratedColumnWithTypeConverter<PetType, String>` 等) を
// 解決するために enum / converter を直接 import しておく必要がある。
// (これらは下の export 文で外部にも再公開する。)
import 'database_converters.dart';
import 'database_enums.dart';
import 'migrations/migrations.dart';
// Tables
import 'tables/account_deletion_queue.dart';
import 'tables/ai_chat_messages.dart';
import 'tables/ai_image_diagnoses.dart';
import 'tables/ai_sessions.dart';
import 'tables/bcs_checks.dart';
import 'tables/cancel_feedback.dart';
import 'tables/diaries.dart';
import 'tables/expiration_items.dart';
import 'tables/foods.dart';
import 'tables/group_members.dart';
import 'tables/groups.dart';
import 'tables/invite_codes.dart';
import 'tables/meals.dart';
import 'tables/medications.dart';
import 'tables/pees.dart';
import 'tables/pending_transfers.dart';
import 'tables/pet_scopes.dart';
import 'tables/pets.dart';
import 'tables/poops.dart';
import 'tables/prevention_courses.dart';
import 'tables/prevention_doses.dart';
import 'tables/schedules.dart';
import 'tables/streak_statuses.dart';
import 'tables/sync_queue.dart';
import 'tables/temperatures.dart';
import 'tables/upload_queue.dart';
import 'tables/vaccinations.dart';
import 'tables/visits.dart';
import 'tables/vomits.dart';
import 'tables/weekly_summaries.dart';
import 'tables/weights.dart';

// ============================================================================
// テーブルクラスを再エクスポート
// リポジトリは `import '../local/app_database.dart';` 1行で
// `Pets` 等のテーブルクラス + drift 生成された Companion/Entity の双方を参照可能にする。
// ============================================================================
export 'database_converters.dart';
export 'database_enums.dart';
export 'tables/account_deletion_queue.dart';
export 'tables/ai_chat_messages.dart';
export 'tables/ai_image_diagnoses.dart';
export 'tables/ai_sessions.dart';
export 'tables/bcs_checks.dart';
export 'tables/cancel_feedback.dart';
export 'tables/diaries.dart';
export 'tables/expiration_items.dart';
export 'tables/foods.dart';
export 'tables/group_members.dart';
export 'tables/groups.dart';
export 'tables/invite_codes.dart';
export 'tables/meals.dart';
export 'tables/medications.dart';
export 'tables/pees.dart';
export 'tables/pending_transfers.dart';
export 'tables/pet_scopes.dart';
export 'tables/pets.dart';
export 'tables/poops.dart';
export 'tables/prevention_courses.dart';
export 'tables/prevention_doses.dart';
export 'tables/schedules.dart';
export 'tables/streak_statuses.dart';
export 'tables/sync_queue.dart';
export 'tables/temperatures.dart';
export 'tables/upload_queue.dart';
export 'tables/vaccinations.dart';
export 'tables/visits.dart';
export 'tables/vomits.dart';
export 'tables/weekly_summaries.dart';
export 'tables/weights.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: <Type>[
    // ペット中心
    Pets,

    // 記録系
    Meals,
    Foods,
    Poops,
    Pees,
    Vomits,
    Weights,
    Temperatures,
    Diaries,

    // 健康
    Visits,
    Medications,
    // build 49 (C1): MedicationReminders は schedules に統合済み、
    // v8 で物理削除。
    Vaccinations,
    BcsChecks,

    // 予定・ストリーク
    ExpirationItems,
    Schedules,
    StreakStatuses,

    // 予防 (build 72)
    PreventionCourses,
    PreventionDoses,

    // 共有
    Groups,
    GroupMembers,
    InviteCodes,
    PendingTransfers,
    CancelFeedback,
    PetScopes,

    // AI
    AiChatMessages,
    AiSessions,
    AiImageDiagnoses,
    WeeklySummaries,

    // 同期インフラ
    SyncQueue,
    UploadQueue,
    AccountDeletionQueue,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// テスト用にQueryExecutorを直接渡せるコンストラクタ
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => AppDatabaseMigrations.currentVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: AppDatabaseMigrations.onCreate,
        onUpgrade: (Migrator m, int from, int to) async {
          // build 5: schedules テーブル追加
          if (from < 2) {
            await m.createTable(schedules);
          }
          // build 15: ai_chat_messages.image_path カラム追加
          if (from < 3) {
            await m.addColumn(aiChatMessages, aiChatMessages.imagePath);
          }
          // build 19: sync_queue を新スキーマで再作成。
          // 旧バージョンに積まれていた行はグループ共有 UI 未実装のため
          // 実害ゼロ (家族共有スコープのオペが事実上発生していない)。
          if (from < 4) {
            await m.deleteTable('sync_queue');
            await m.createTable(syncQueue);
          }
          // build 22: pets.sex を NOT NULL → nullable に変更。
          // drift の alterTable は内部で「新スキーマで temp table 作成 →
          // 既存データコピー → 旧 table drop → rename」を実行するため
          // 既存ペットの値は保持される。
          if (from < 5) {
            await m.alterTable(TableMigration(pets));
          }
          // build 43 / Phase G1: pet_scopes テーブル追加 + 既存 pets を 1:1 backfill。
          // Decision Log #1/#2: primary scope に既存 group_id を採用し、ユーザー
          // 視点で「1 ペット = 1 scope」の挙動を維持する。
          if (from < 6) {
            await m.createTable(petScopes);
            await backfillPetScopesFromPets();
          }
          // build 47b / Scope B1+B2: schedules テーブルに times / weekdaysBits
          // を足し、既存 medication_reminders 行を schedules (category=medication)
          // に 1:1 移行する。元テーブル DROP は build 49 (v8) で実施。
          if (from < 7) {
            await m.addColumn(schedules, schedules.times);
            await m.addColumn(schedules, schedules.weekdaysBits);
            await migrateMedicationRemindersToSchedules();
          }
          // build 49 / Scope C1: medication_reminders テーブルを物理削除。
          // v7 のデータ移行は完了済みなので元テーブルは不要。
          // 注: v7→v8 へ skip 上がりするユーザはまずいないが、v6→v8 のような
          // 飛び級でも v7 step が先に走るので順序的に安全。rollback 不可。
          if (from < 8) {
            await customStatement('DROP TABLE IF EXISTS medication_reminders');
          }
          // build 57 / Decision D 純粋実装: 全 pets に Personal scope を常在化。
          if (from < 9) {
            await backfillPersonalScopes();
          }
          // build 72: 予防コース機能。テーブル 2 本の新規作成のみ。
          // backfill なし、既存テーブルへの ALTER なし。
          if (from < 10) {
            await m.createTable(preventionCourses);
            await m.createTable(preventionDoses);
          }
          await AppDatabaseMigrations.onUpgrade(m, from, to);
        },
        beforeOpen: (OpeningDetails details) async {
          await customStatement('PRAGMA foreign_keys = ON;');
          await customStatement('PRAGMA journal_mode = WAL;');
          // build 43 セーフティネット: 万一 v6 migration の backfill が
          // 一部失敗・スキップしていても、pet_scopes が空の pets を見つけたら
          // 起動時に補完する。permission=owner / is_primary=true で確定。
          // build 57 セーフティネット: v9 で導入した Personal scope 常在化も
          // 同様に起動時に再走させる (冪等)。
          if (details.wasCreated || details.hadUpgrade) {
            await backfillPetScopesFromPets();
            await backfillPersonalScopes();
          }
        },
      );

  /// 既存 pets を 1:1 で pet_scopes に backfill する。
  /// 既に pet_scopes に行がある pet はスキップする (UNIQUE(pet_id, group_id) で
  /// 二重挿入は防がれるが、明示的にスキップして noise を減らす)。
  ///
  /// Decision Log #1/#2: 既存 `pets.group_id` を primary scope として採用。
  /// permission は owner 固定 (既存 pets は皆「自分が owner」だった)。
  ///
  /// 通常は migration v5→v6 と beforeOpen フックから自動呼び出される。
  /// build 43 (Phase G1) のテストから明示的に呼べるように public 化している。
  Future<void> backfillPetScopesFromPets() async {
    final int t = DateTime.now().toUtc().millisecondsSinceEpoch;
    await customStatement(
      "INSERT OR IGNORE INTO pet_scopes "
      "(pet_id, group_id, permission, is_primary, shared_at, "
      "shared_by_user_id, sync_status, deleted_at, created_at, updated_at, "
      "last_modified_at_client) "
      "SELECT p.id, p.group_id, 'owner', 1, p.created_at, NULL, 'synced', "
      "NULL, ?, ?, NULL "
      "FROM pets p "
      "WHERE NOT EXISTS ("
      "  SELECT 1 FROM pet_scopes s "
      "  WHERE s.pet_id = p.id AND s.group_id = p.group_id"
      ")",
      <Object?>[t, t],
    );
  }

  /// build 57 (Decision D 純粋実装): 既存 pets で Personal scope が無いものに
  /// Personal scope を追加する。
  ///
  /// 不変条件 (1 ペット 1 primary) を維持するため、Personal を新たに primary に
  /// するペットでは既存の non-Personal primary scope を is_primary=0 に降格する。
  /// 順序:
  ///   1. Personal scope を不在 pets に INSERT
  ///   2. それらの pet で既存 non-Personal scope を is_primary=0 に降格
  ///
  /// 冪等性: WHERE NOT EXISTS により再実行しても重複 INSERT しない。
  /// step 2 の UPDATE も既に is_primary=0 なら影響なし。
  Future<void> backfillPersonalScopes() async {
    final int t = DateTime.now().toUtc().millisecondsSinceEpoch;

    // 1. Personal scope を追加 (deleted_at IS NULL の pets のみ)
    await customStatement(
      "INSERT INTO pet_scopes "
      "(pet_id, group_id, permission, is_primary, shared_at, "
      "sync_status, created_at, updated_at, last_modified_at_client) "
      "SELECT p.id, 'personal', 'owner', 1, ?, 'synced', ?, ?, ? "
      "FROM pets p "
      "WHERE p.deleted_at IS NULL "
      "AND NOT EXISTS ("
      "  SELECT 1 FROM pet_scopes ps "
      "  WHERE ps.pet_id = p.id "
      "  AND ps.group_id = 'personal' "
      "  AND ps.deleted_at IS NULL"
      ")",
      <Object?>[t, t, t, t],
    );

    // 2. 上記 1 で Personal scope を獲得した pet たちの、既存の
    //    non-Personal primary scope を is_primary=0 に降格。
    //    (1 ペット 1 primary を維持、Personal を canonical primary に)
    //    既に is_primary=0 なら何も起きない、冪等。
    await customStatement(
      "UPDATE pet_scopes SET is_primary = 0, updated_at = ?, "
      "last_modified_at_client = ? "
      "WHERE group_id != 'personal' "
      "AND is_primary = 1 "
      "AND deleted_at IS NULL "
      "AND EXISTS ("
      "  SELECT 1 FROM pet_scopes ps2 "
      "  WHERE ps2.pet_id = pet_scopes.pet_id "
      "  AND ps2.group_id = 'personal' "
      "  AND ps2.is_primary = 1 "
      "  AND ps2.deleted_at IS NULL"
      ")",
      <Object?>[t, t],
    );
  }

  /// build 47b (Scope B2): medication_reminders テーブルの全行を schedules
  /// (category=medication) に 1:1 で移行する。
  ///
  /// マッピング:
  ///   - title          ← medicine_name
  ///   - notes          ← notes + (dosage があれば追記)
  ///   - scheduledAt    ← start_date or 今日 (start_date が null の場合)
  ///   - hasTime        ← false (時刻は times[] で別途持つので scheduledAt
  ///                            自体は 00:00 扱い)
  ///   - times          ← times (JSON 配列文字列、そのまま)
  ///   - weekdaysBits   ← weekdays_bits
  ///   - recurrence     ← times が non-null なら 'daily'、それ以外は 'none'
  ///   - relatedPetIds  ← [pet_id] を JSON 配列にエンコード
  ///   - source_type    ← 'manual' (medication_reminders 由来であることは
  ///                            notes へのトレースで識別)
  ///   - deleted_at     ← そのまま (削除済みは削除済みのまま移行する)
  ///   - sync_status    ← 'pending' (サーバ側にも反映が必要)
  ///   - last_modified_at_client ← 現在時刻 (LWW で新しい方が勝つように)
  ///
  /// 安全性:
  ///   - 同じ source_pet_id + title の schedule が既にあれば INSERT を
  ///     スキップ (idempotent 化、複数回起動の保護)。
  ///   - medication_reminders テーブル本体は **削除しない**。失敗時に
  ///     原本が残ることで rollback と再実行が可能。
  ///   - 件数を logger に出す (TestFlight ユーザの dev 確認で利用)。
  Future<void> migrateMedicationRemindersToSchedules() async {
    final int t = DateTime.now().toUtc().millisecondsSinceEpoch;
    final int today00 = DateTime.now().toUtc().millisecondsSinceEpoch -
        (DateTime.now().toUtc().millisecondsSinceEpoch %
            const Duration(days: 1).inMilliseconds);

    // before: medication_reminders 件数
    final List<QueryRow> beforeRow = await customSelect(
      'SELECT COUNT(*) AS c FROM medication_reminders WHERE deleted_at IS NULL',
    ).get();
    final int beforeCount =
        beforeRow.isEmpty ? 0 : (beforeRow.first.read<int>('c'));

    // SELECT で旧データを引き、行ごとに INSERT する。
    // CTE を含む 1 文の INSERT ... SELECT でもできるが、
    //   - 既存 schedules で重複を判定したい
    //   - notes に dosage を追記する文字列加工が必要
    // のため Dart 側でループする方が読みやすい。
    final List<QueryRow> rows = await customSelect(
      'SELECT id, remote_id, group_id, pet_id, medicine_name, dosage, '
      'times, weekdays_bits, enabled, start_date, end_date, notes, '
      'created_by, sync_status, deleted_at, created_at, updated_at, '
      'last_modified_at_client '
      'FROM medication_reminders',
    ).get();

    int migrated = 0;
    int skipped = 0;
    for (final QueryRow row in rows) {
      final int petId = row.read<int>('pet_id');
      final String title = row.read<String>('medicine_name');
      final String? dosage = row.read<String?>('dosage');
      final String? legacyNotes = row.read<String?>('notes');
      final String? times = row.read<String?>('times');
      final int? weekdaysBits = row.read<int?>('weekdays_bits');
      final int? startDate = row.read<int?>('start_date');
      final int? legacyDeletedAt = row.read<int?>('deleted_at');
      final int legacyCreatedAt = row.read<int>('created_at');
      final String groupId = row.read<String>('group_id');

      // 同名タイトル + 関連 pet_id + category=medication で既存があれば skip
      final List<QueryRow> existing = await customSelect(
        "SELECT id FROM schedules WHERE category = 'medication' "
        "AND title = ? AND related_pet_ids = ? AND deleted_at IS NULL",
        variables: <Variable<Object>>[
          Variable<String>(title),
          Variable<String>('["$petId"]'),
        ],
      ).get();
      if (existing.isNotEmpty) {
        skipped++;
        continue;
      }

      final String mergedNotes = <String>[
        if (legacyNotes != null && legacyNotes.isNotEmpty) legacyNotes,
        if (dosage != null && dosage.isNotEmpty) '[dosage] $dosage',
      ].join('\n');

      // 旧 enabled=0 (disabled) は schedules に「times なし」で移行する。
      // 新 schema には enabled フラグがないため、times が null だと
      // notification scheduler が発火しない = disabled 状態に相当する。
      // ユーザが後で再有効化したければ times を入力し直してもらう。
      final bool wasEnabled = (row.read<int?>('enabled') ?? 1) != 0;
      final String? effectiveTimes = wasEnabled ? times : null;
      final String recurrence = effectiveTimes != null ? 'daily' : 'none';
      final int scheduledAt = startDate ?? today00;

      await customStatement(
        'INSERT INTO schedules '
        '(remote_id, group_id, title, category, scheduled_at, has_time, '
        'recurrence, notification_timing, notes, related_pet_ids, '
        'is_auto_generated, source_type, source_pet_id, created_by, '
        'sync_status, deleted_at, created_at, updated_at, '
        'last_modified_at_client, times, weekdays_bits) '
        'VALUES (NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '
        '?, ?, ?)',
        <Object?>[
          groupId,
          title,
          'medication',
          scheduledAt,
          0, // has_time = false (時刻は times[] で持つ)
          recurrence,
          'none',
          mergedNotes.isEmpty ? null : mergedNotes,
          '["$petId"]',
          0,
          'manual',
          petId,
          row.read<String?>('created_by'),
          'pending',
          legacyDeletedAt,
          legacyCreatedAt,
          t,
          t,
          effectiveTimes,
          weekdaysBits,
        ],
      );
      migrated++;
    }

    // ignore: avoid_print
    print(
      '[migrate v6→v7] medication_reminders→schedules: '
      'before=$beforeCount migrated=$migrated skipped=$skipped',
    );
  }
}

// ============================================================================
// DB接続の初期化
// ============================================================================
QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    // sqlite3_flutter_libs の初期化
    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }

    final Directory dbFolder = await getApplicationDocumentsDirectory();
    final File file = File(p.join(dbFolder.path, 'petlo.sqlite'));

    // 一時ファイルディレクトリの設定
    final Directory cachebase = (await getTemporaryDirectory());
    sqlite3.tempDirectory = cachebase.path;

    return NativeDatabase.createInBackground(
      file,
      logStatements: false,
    );
  });
}
