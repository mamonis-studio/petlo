// ============================================================================
// petlo - Application Constants
// ============================================================================
//
// アプリ全体で使う定数を一箇所に集約。
// バージョン、URL、各種制限値など。
//
// 個別の機能ドメインに紐づく定数は、それぞれのドメインフォルダに置く。
// ここはあくまでアプリ全体に関わる横断的なもののみ。
//
// ============================================================================

abstract final class AppConstants {
  AppConstants._();

  // ===== アプリ基本情報 =====
  static const String appName = 'petlo';
  static const String appVersion = '1.1.0';
  static const int appBuildNumber = 76;
  static const String bundleId = 'mamonis.studio.petlo';
  static const String developerName = 'mamonis.studio';

  // ===== URL =====
  static const String websiteUrl = 'https://petlo.mamonis.studio';
  static const String privacyPolicyUrl = '$websiteUrl/privacy_policy.html';
  static const String termsOfUseUrl = '$websiteUrl/terms_of_use.html';
  static const String supportUrl = '$websiteUrl/contact';
  static const String contactEmail = 'contact@mamonis.studio';

  // ===== mamonis.studio SNS =====
  static const String xUrl = 'https://x.com/mamonis_studio';
  static const String instagramUrl = 'https://instagram.com/mamonis.studio';
  static const String tiktokUrl = 'https://tiktok.com/@mamonis.studio';

  // ===== API =====
  static const String apiBaseUrl = 'https://api.petlo.mamonis.studio';

  // ===== IAP Product IDs =====
  static const String iapMonthlyProductId = 'mamonis.studio.petlo.monthly';
  static const String iapYearlyProductId = 'mamonis.studio.petlo.yearly';

  // ===== 各種上限 (rev5.5仕様準拠) =====
  // 無料プラン
  static const int freeMaxPets = 1;
  static const int freeMaxRecordsPerMonth = 30; // ご飯/うんち/おしっこ/嘔吐
  static const int freeMaxDiaryPerMonth = 10;
  static const int freeMaxVisits = 10;
  // build 47b で medication_reminders → schedules に統合済み。
  // 投薬の Pro 制限は撤廃したので freeMaxMedicationReminders 定数も削除
  // (build 49)。schedules 全体に同じ制限がかかる将来仕様には別キーを用意。
  static const int freeMaxExpirationItems = 3;
  static const int freeWeightHistoryMonths = 3;
  static const int freeTemperatureHistoryMonths = 3;

  // ===== 予防コースのキルスイッチ (build 73) =====
  /// 予防コース機能を有効にするか。
  ///
  /// false に倒すと以下が **すべて** 止まる:
  ///   1. 健康タブの予防セクションを表示しない
  ///   2. rescheduleAllPreventions() を呼ばない
  ///   3. 通知バジェットを予防導入前の 50 slot に戻す
  ///
  /// 3 を忘れると意味がない。#4 (iOS 64 slot 超え) の原因は予防の通知そのもの
  /// ではなく、schedule 系のバジェットを 50 → 38 に下げたこと。UI だけ隠しても
  /// 既存のワクチン・投薬通知が 12 slot 損したまま生き続ける。
  ///
  /// **DB には一切触らない。** フラグを倒しても schemaVersion は 10 のまま、
  /// prevention_courses / prevention_doses も残す。migration の巻き戻しだけが
  /// 本当に破壊的な操作であり、キルスイッチでやってよいことではない。
  /// 再度 true に戻せば、記録は無傷のまま機能が復帰する。
  static const bool enablePrevention = true;

  // ===== 予防コース (build 72) =====
  /// 無料プランで作成できる予防コース数 (created_at 昇順で先着)
  static const int freeMaxPreventionCourses = 1;
  /// 無料プランで閲覧できる予防履歴の年数
  static const int freePreventionHistoryYears = 1;

  // Pro
  static const int proAiChatPerMonth = 100;
  static const int proAiImageDiagnosisPerMonth = 10;
  static const int proGracePeriodDays = 14; // オフライン課金検証猶予

  // 共有
  static const int maxGroupsPerUser = 3;
  static const int maxMembersPerGroup = 5;
  static const int inviteCodeTtlSeconds = 72 * 60 * 60; // 72時間

  // ===== AI =====
  static const int aiMaxMessageLength = 500; // プロンプトインジェクション対策
  static const int aiSessionContextTurns = 5; // 直近5往復保持
  static const int aiSessionTimeoutMinutes = 30;
  static const int aiResponseTimeoutSeconds = 30;

  // ===== 同期 (rev5.5: ジッター対応) =====
  static const int syncIntervalSecondsMin = 90; // 120 - 30
  static const int syncIntervalSecondsMax = 150; // 120 + 30

  // ===== タイミング (rev5.5) =====
  static const Duration undoSnackBarDuration = Duration(seconds: 3);
  static const Duration petSwitchAnimationDuration = Duration(milliseconds: 300);
  static const Duration groupSwitchAnimationDuration = Duration(milliseconds: 400);
  static const Duration aiThinkingDotInterval = Duration(milliseconds: 400);

  // ===== ストリーク =====
  static const int streakFreezePerMonth = 1; // Pro限定、月1回

  // ===== 警告バナー =====
  static const int backupWarningRecordThreshold = 100;
  static const int backupWarningVisitThreshold = 5;
  static const int backupWarningRemindLaterDays = 30;

  // ===== Pro解約後 =====
  static const int proCancelGroupFreezeDays = 30;
  static const int proCancelGroupDeleteDays = 90;

  // ===== 写真 =====
  static const int photoMaxLongSide = 1280; // 圧縮後の長辺(rev3)
  static const int photoJpegQuality = 85;
  static const int photoMaxSizeMb = 5;

  // ===== レビュー誘導 (rev4) =====
  static const int reviewPromptMinAppLaunches = 10;
  static const int reviewPromptMinRecords = 30;
}
