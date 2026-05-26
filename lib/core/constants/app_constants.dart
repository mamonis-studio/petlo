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
  static const String appVersion = '1.0.0';
  static const int appBuildNumber = 48;
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
  static const int freeMaxMedicationReminders = 1;
  static const int freeMaxExpirationItems = 3;
  static const int freeWeightHistoryMonths = 3;
  static const int freeTemperatureHistoryMonths = 3;

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
