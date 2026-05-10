// ============================================================================
// petlo - User Preferences
// ============================================================================
//
// アプリ全体のユーザー設定を永続化する SharedPreferences ラッパー。
//
// 役割:
//   - テーマモード (light/dark/system)
//   - 将来: バックアップ警告 "Remind me later" の押下日付など
//
// 設計:
//   - シングルトンで全アプリ共有
//   - 起動時に initialize() で1回だけロード、その後は同期アクセス
//   - 値の更新は async (await SharedPreferences の書き込み完了を保証)
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../backup/backup_settings.dart';
import '../billing/pro_status.dart';
import '../utils/logger.dart';

/// テーマモード
enum AppThemeMode {
  light,
  dark,
  system;

  ThemeMode toFlutter() {
    switch (this) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  static AppThemeMode fromString(String? s) {
    switch (s) {
      case 'light':
        return AppThemeMode.light;
      case 'dark':
        return AppThemeMode.dark;
      case 'system':
      default:
        return AppThemeMode.system;
    }
  }
}

class UserPreferences {
  UserPreferences._();
  static final UserPreferences instance = UserPreferences._();

  SharedPreferences? _prefs;
  bool _initialized = false;

  // ===== Keys =====
  static const String _kThemeMode = 'pref.theme_mode';
  static const String _kProTier = 'pref.pro.tier';
  static const String _kProState = 'pref.pro.state';
  static const String _kProExpiresAt = 'pref.pro.expires_at';
  static const String _kProTrialEndsAt = 'pref.pro.trial_ends_at';
  static const String _kBackupState = 'pref.backup.state';
  static const String _kBackupProvider = 'pref.backup.provider';
  static const String _kBackupLastSuccessAt = 'pref.backup.last_success_at';
  static const String _kBackupLastError = 'pref.backup.last_error';
  static const String _kBackupRemindLaterAt = 'pref.backup.remind_later_at';
  static const String _kOnboardingCompleted = 'pref.onboarding.completed';

  /// アプリ起動時に1度だけ呼ぶ
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
      PetloLogger.instance
          .i('UserPreferences initialized (themeMode=${themeMode.name})');
    } catch (e, st) {
      PetloLogger.instance.w('UserPreferences init failed',
          error: e, stackTrace: st);
    }
  }

  // ==========================================================================
  // ThemeMode
  // ==========================================================================

  AppThemeMode get themeMode {
    final String? raw = _prefs?.getString(_kThemeMode);
    return AppThemeMode.fromString(raw);
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    if (_prefs == null) return;
    try {
      await _prefs!.setString(_kThemeMode, mode.name);
    } catch (e) {
      PetloLogger.instance.d('setThemeMode failed: $e');
    }
  }

  // ==========================================================================
  // Pro Status (ローカルキャッシュ、サーバー検証は将来Chunk)
  // ==========================================================================

  ProStatus get proStatus {
    final SharedPreferences? p = _prefs;
    if (p == null) return ProStatus.free;
    return ProStatus.fromMap(<String, String?>{
      'tier': p.getString(_kProTier),
      'state': p.getString(_kProState),
      'expiresAt': p.getString(_kProExpiresAt),
      'trialEndsAt': p.getString(_kProTrialEndsAt),
    });
  }

  Future<void> setProStatus(ProStatus status) async {
    final SharedPreferences? p = _prefs;
    if (p == null) return;
    try {
      await p.setString(_kProTier, status.tier.name);
      await p.setString(_kProState, status.state.name);
      if (status.expiresAt != null) {
        await p.setString(
            _kProExpiresAt, status.expiresAt!.toIso8601String());
      } else {
        await p.remove(_kProExpiresAt);
      }
      if (status.trialEndsAt != null) {
        await p.setString(
            _kProTrialEndsAt, status.trialEndsAt!.toIso8601String());
      } else {
        await p.remove(_kProTrialEndsAt);
      }
    } catch (e) {
      PetloLogger.instance.d('setProStatus failed: $e');
    }
  }

  Future<void> clearProStatus() async {
    await setProStatus(ProStatus.free);
  }

  // ==========================================================================
  // Backup Settings (rev3 + rev5.5 F-79)
  // ==========================================================================

  BackupSettings get backupSettings {
    final SharedPreferences? p = _prefs;
    if (p == null) return BackupSettings.off;
    return BackupSettings.fromMap(<String, String?>{
      'state': p.getString(_kBackupState),
      'provider': p.getString(_kBackupProvider),
      'lastSuccessAt': p.getString(_kBackupLastSuccessAt),
      'lastErrorMessage': p.getString(_kBackupLastError),
      'remindLaterAt': p.getString(_kBackupRemindLaterAt),
    });
  }

  Future<void> setBackupSettings(BackupSettings settings) async {
    final SharedPreferences? p = _prefs;
    if (p == null) return;
    try {
      await p.setString(_kBackupState, settings.state.name);
      await p.setString(_kBackupProvider, settings.provider.name);
      if (settings.lastSuccessAt != null) {
        await p.setString(_kBackupLastSuccessAt,
            settings.lastSuccessAt!.toIso8601String());
      } else {
        await p.remove(_kBackupLastSuccessAt);
      }
      if (settings.lastErrorMessage != null) {
        await p.setString(_kBackupLastError, settings.lastErrorMessage!);
      } else {
        await p.remove(_kBackupLastError);
      }
      if (settings.remindLaterAt != null) {
        await p.setString(_kBackupRemindLaterAt,
            settings.remindLaterAt!.toIso8601String());
      } else {
        await p.remove(_kBackupRemindLaterAt);
      }
    } catch (e) {
      PetloLogger.instance.d('setBackupSettings failed: $e');
    }
  }

  // ==========================================================================
  // Onboarding (rev5.4 §4.7)
  // ==========================================================================

  bool get onboardingCompleted {
    return _prefs?.getBool(_kOnboardingCompleted) ?? false;
  }

  Future<void> setOnboardingCompleted(bool value) async {
    if (_prefs == null) return;
    try {
      await _prefs!.setBool(_kOnboardingCompleted, value);
    } catch (e) {
      PetloLogger.instance.d('setOnboardingCompleted failed: $e');
    }
  }
}
