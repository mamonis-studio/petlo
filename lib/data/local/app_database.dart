// ============================================================================
// petlo - App Database
// ============================================================================
//
// driftデータベース本体。全28テーブルを統合。
//
// 構成:
//   ペット中心:  pets
//   記録系(7):  meals, foods, poops, pees, vomits, weights, temperatures, diaries
//   健康(5):    visits, medications, medication_reminders, vaccinations, bcs_checks
//   予定(2):    expiration_items, streak_statuses
//   共有(5):    groups, group_members, invite_codes, pending_transfers, cancel_feedback
//   AI(4):      ai_chat_messages, ai_sessions, ai_image_diagnoses, weekly_summaries
//   同期(3):    sync_queue, upload_queue, account_deletion_queue
//   合計:       28テーブル
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
import 'tables/medication_reminders.dart';
import 'tables/medications.dart';
import 'tables/pees.dart';
import 'tables/pending_transfers.dart';
import 'tables/pets.dart';
import 'tables/poops.dart';
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
export 'tables/medication_reminders.dart';
export 'tables/medications.dart';
export 'tables/pees.dart';
export 'tables/pending_transfers.dart';
export 'tables/pets.dart';
export 'tables/poops.dart';
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
    MedicationReminders,
    Vaccinations,
    BcsChecks,

    // 予定・ストリーク
    ExpirationItems,
    Schedules,
    StreakStatuses,

    // 共有
    Groups,
    GroupMembers,
    InviteCodes,
    PendingTransfers,
    CancelFeedback,

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
          await AppDatabaseMigrations.onUpgrade(m, from, to);
        },
        beforeOpen: (OpeningDetails details) async {
          await customStatement('PRAGMA foreign_keys = ON;');
          await customStatement('PRAGMA journal_mode = WAL;');
        },
      );
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
