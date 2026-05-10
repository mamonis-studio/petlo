// ============================================================================
// petlo - Storage Providers
// ============================================================================
//
// SharedPreferences と FlutterSecureStorage の Provider。
//
// SharedPreferences:
//   - 設定値、UIフラグ、ローカル個人設定 (rev5.5: ペット並び順、メモリアル表示等)
//   - SharedPreferencesAsync (新API、推奨) を使用
//
// FlutterSecureStorage:
//   - APIトークン、認証情報など機密データ
//
// 設計:
//   - sharedPreferencesProvider は eager (起動時に initialize)
//   - 各機能別の専用 Provider をこの上に重ねる(currentGroupId 等)
//
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// SharedPreferences (instance)
// ============================================================================

/// SharedPreferencesAsync のインスタンス。
/// アプリ起動時に main() で先に初期化済みであること。
final Provider<SharedPreferencesAsync> sharedPreferencesProvider =
    Provider<SharedPreferencesAsync>(
  (Ref ref) => SharedPreferencesAsync(),
);

// ============================================================================
// SharedPreferences keys
// ============================================================================

/// SharedPreferencesで使う全キーの定義を集約。
/// 命名は `カテゴリ_詳細` のスネークケース。
abstract final class PrefsKeys {
  PrefsKeys._();

  // === スコープ系 (rev5.1, rev5.3) ===
  static const String currentGroupId = 'current_group_id';
  static const String currentPetId = 'current_pet_id';
  static const String currentRole = 'current_role';

  // === オンボーディング (rev5.4) ===
  static const String onboardingCompleted = 'onboarding_completed';
  static const String notificationPermissionAsked =
      'notification_permission_asked';

  // === Streak (rev5.4) ===
  /// "YYYY-MM" 形式
  static const String streakFreezeUsedMonth = 'streak_freeze_used_month';

  // === メモリアル個別表示 (rev5.4) ===
  /// "memorial_visibility:{petId}" → bool
  static String memorialVisibility(int petId) => 'memorial_visibility:$petId';

  // === バックアップ警告 (rev5.5) ===
  /// 警告バナーをdismissした最終日 (UTC msec)
  static const String backupWarningDismissedAt = 'backup_warning_dismissed_at';

  // === 単位設定 ===
  static const String weightUnit = 'weight_unit'; // 'kg' | 'lb'
  static const String temperatureUnit = 'temperature_unit'; // 'celsius' | 'fahrenheit'

  // === レビュー誘導 (rev4) ===
  static const String appLaunchCount = 'app_launch_count';
  static const String reviewPromptShownAt = 'review_prompt_shown_at';
}

// ============================================================================
// FlutterSecureStorage
// ============================================================================

final Provider<FlutterSecureStorage> secureStorageProvider =
    Provider<FlutterSecureStorage>(
  (Ref ref) => const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  ),
);

abstract final class SecureStorageKeys {
  SecureStorageKeys._();

  /// API認証トークン (Apple/Google Sign-In後に取得)
  static const String apiAuthToken = 'api_auth_token';

  /// APIリフレッシュトークン
  static const String apiRefreshToken = 'api_refresh_token';

  /// User ID (永続)
  static const String userId = 'user_id';
}
