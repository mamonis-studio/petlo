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
import 'dart:convert';

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
  // build 62 でクラウド連携プレースホルダ撤去に伴い、_kBackupState /
  // _kBackupProvider / _kBackupLastError は廃止。残存値は読み出さない。
  static const String _kBackupLastExportAt = 'pref.backup.last_export_at';
  static const String _kBackupRemindLaterAt = 'pref.backup.remind_later_at';
  // build 68: R2 クラウドバックアップ
  static const String _kBackupLastCloudAt = 'pref.backup.last_cloud_at';
  static const String _kBackupCloudByteSize = 'pref.backup.cloud_byte_size';
  static const String _kBackupCloudAutoEnabled =
      'pref.backup.cloud_auto_enabled';
  static const String _kOnboardingCompleted = 'pref.onboarding.completed';
  static const String _kForcePro = 'pref.dev.force_pro';
  static const String _kDisplayName = 'pref.user.display_name';
  // build 73: ワクチン通知 ID の採番変更に伴う旧レンジ掃除の実行済みフラグ
  static const String _kVaccinationIdMigratedV2 =
      'pref.notifications.vaccination_id_migrated_v2';
  // build 73: 掃除で消した件数。ログに頼らず画面で確認できるようにする
  static const String _kVaccinationIdMigratedCount =
      'pref.notifications.vaccination_id_migrated_count';
  // build 73: schedule 通知 ID の採番変更に伴う旧レンジ掃除
  static const String _kScheduleIdMigratedV2 =
      'pref.notifications.schedule_id_migrated_v2';
  static const String _kScheduleIdMigratedCount =
      'pref.notifications.schedule_id_migrated_count';
  // build 73: 直近の通知割り当てレポート (JSON)
  static const String _kNotificationAllocationReport =
      'pref.notifications.allocation_report';
  // build 73: 起動シーケンスの所要時間 (JSON)
  static const String _kStartupTrace = 'pref.debug.startup_trace';
  // build 73: 初回 fullPull を実施済みか
  /// バックアップ復元後にこのキーを直接消したい箇所があるため公開する
  /// (復元は SharedPreferences を直接触るので、setter 経由だと
  ///  UserPreferences の初期化順に依存してしまう)。
  static const String kDidInitialFullPull = 'pref.sync.did_initial_full_pull';
  static const String _kDidInitialFullPull = kDidInitialFullPull;

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
    if (p == null) return BackupSettings.initial;
    return BackupSettings.fromMap(<String, String?>{
      'lastExportAt': p.getString(_kBackupLastExportAt),
      'remindLaterAt': p.getString(_kBackupRemindLaterAt),
      // build 68: クラウドバックアップ系
      'lastCloudBackupAt': p.getString(_kBackupLastCloudAt),
      'cloudBackupByteSize': p.getString(_kBackupCloudByteSize),
      // bool は明示的に '0' / '1' で保存。キー欠落 (未保存ユーザ) は default
      // true を返したいので、null をそのまま fromMap に渡す (fromMap 側で
      // `!= '0'` 判定にしている)。
      'cloudBackupAutoEnabled': p.getString(_kBackupCloudAutoEnabled),
    });
  }

  Future<void> setBackupSettings(BackupSettings settings) async {
    final SharedPreferences? p = _prefs;
    if (p == null) return;
    try {
      if (settings.lastExportAt != null) {
        await p.setString(
            _kBackupLastExportAt, settings.lastExportAt!.toIso8601String());
      } else {
        await p.remove(_kBackupLastExportAt);
      }
      if (settings.remindLaterAt != null) {
        await p.setString(_kBackupRemindLaterAt,
            settings.remindLaterAt!.toIso8601String());
      } else {
        await p.remove(_kBackupRemindLaterAt);
      }
      // build 68: クラウドバックアップ系
      if (settings.lastCloudBackupAt != null) {
        await p.setString(_kBackupLastCloudAt,
            settings.lastCloudBackupAt!.toIso8601String());
      } else {
        await p.remove(_kBackupLastCloudAt);
      }
      if (settings.cloudBackupByteSize != null) {
        await p.setString(
            _kBackupCloudByteSize, settings.cloudBackupByteSize!.toString());
      } else {
        await p.remove(_kBackupCloudByteSize);
      }
      await p.setString(_kBackupCloudAutoEnabled,
          settings.cloudBackupAutoEnabled ? '1' : '0');
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

  // ==========================================================================
  // Developer: Force Pro (build 11)
  // ==========================================================================

  bool get forcePro {
    return _prefs?.getBool(_kForcePro) ?? false;
  }

  Future<void> setForcePro(bool value) async {
    if (_prefs == null) return;
    try {
      await _prefs!.setBool(_kForcePro, value);
    } catch (e) {
      PetloLogger.instance.d('setForcePro failed: $e');
    }
  }

  // ==========================================================================
  // ワクチン通知 ID の移行 (build 73)
  // ==========================================================================

  /// 旧採番 (`1000000 + vaccinationId`) で積まれた通知の掃除が済んでいるか。
  /// 掃除は 1 回だけ。毎起動で走らせない。
  bool get vaccinationIdMigratedV2 {
    return _prefs?.getBool(_kVaccinationIdMigratedV2) ?? false;
  }

  Future<void> setVaccinationIdMigratedV2(bool value) async {
    if (_prefs == null) return;
    try {
      await _prefs!.setBool(_kVaccinationIdMigratedV2, value);
    } catch (e) {
      PetloLogger.instance.d('setVaccinationIdMigratedV2 failed: $e');
    }
  }

  /// 掃除で消した旧採番通知の件数。未実行なら null。
  ///
  /// ログは debug ビルドでしか出ない (DevelopmentFilter) 一方、
  /// debug は端末によっては JIT で起動できない。
  /// 「未実行」と「実行して 0 件」を確実に区別するため、
  /// 結果そのものを永続化して開発者設定から読めるようにする。
  int? get vaccinationIdMigratedCount {
    return _prefs?.getInt(_kVaccinationIdMigratedCount);
  }

  Future<void> setVaccinationIdMigratedCount(int value) async {
    if (_prefs == null) return;
    try {
      await _prefs!.setInt(_kVaccinationIdMigratedCount, value);
    } catch (e) {
      PetloLogger.instance.d('setVaccinationIdMigratedCount failed: $e');
    }
  }

  // ==========================================================================
  // schedule 通知 ID の移行 (build 73)
  // ==========================================================================

  /// 旧採番 (通し番号 slot + 内部の `+ wd`) で積まれた通知の掃除が済んでいるか。
  bool get scheduleIdMigratedV2 {
    return _prefs?.getBool(_kScheduleIdMigratedV2) ?? false;
  }

  Future<void> setScheduleIdMigratedV2(bool value) async {
    if (_prefs == null) return;
    try {
      await _prefs!.setBool(_kScheduleIdMigratedV2, value);
    } catch (e) {
      PetloLogger.instance.d('setScheduleIdMigratedV2 failed: $e');
    }
  }

  /// 掃除で消した旧採番通知の件数。未実行なら null。
  int? get scheduleIdMigratedCount {
    return _prefs?.getInt(_kScheduleIdMigratedCount);
  }

  Future<void> setScheduleIdMigratedCount(int value) async {
    if (_prefs == null) return;
    try {
      await _prefs!.setInt(_kScheduleIdMigratedCount, value);
    } catch (e) {
      PetloLogger.instance.d('setScheduleIdMigratedCount failed: $e');
    }
  }

  // ==========================================================================
  // 通知の割り当てレポート (build 73)
  // ==========================================================================

  /// 直近の再割り当てで「何を積み、何が溢れたか」。
  ///
  /// ログは debug ビルドでしか出ないうえ、debug は端末によっては JIT で
  /// 起動できない。可観測性はこの永続化で担保する。
  Map<String, dynamic>? get notificationAllocationReport {
    final String? raw = _prefs?.getString(_kNotificationAllocationReport);
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      PetloLogger.instance.d('notificationAllocationReport decode failed: $e');
      return null;
    }
  }

  Future<void> setNotificationAllocationReport(
      Map<String, dynamic> value) async {
    if (_prefs == null) return;
    try {
      await _prefs!
          .setString(_kNotificationAllocationReport, jsonEncode(value));
    } catch (e) {
      PetloLogger.instance.d('setNotificationAllocationReport failed: $e');
    }
  }

  // ==========================================================================
  // 起動シーケンスの計測 (build 73)
  // ==========================================================================

  /// 各処理の所要時間。ログは debug でしか出ず、この端末では debug が
  /// 起動できないため、profile / release でも読めるよう永続化する。
  Map<String, dynamic>? get startupTrace {
    final String? raw = _prefs?.getString(_kStartupTrace);
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      PetloLogger.instance.d('startupTrace decode failed: $e');
      return null;
    }
  }

  Future<void> setStartupTrace(Map<String, dynamic> value) async {
    if (_prefs == null) return;
    try {
      await _prefs!.setString(_kStartupTrace, jsonEncode(value));
    } catch (e) {
      PetloLogger.instance.d('setStartupTrace failed: $e');
    }
  }

  // ==========================================================================
  // 初回 fullPull (build 73)
  // ==========================================================================

  /// サーバからの初回一括取得 (fullPull) が済んでいるか。
  ///
  /// build 72 以前は `groups テーブルが空か` で判定していたが、
  /// groups は **家族共有グループの一覧** であり、共有機能を使っていない
  /// ユーザーでは常に空。その結果、通常起動のたびに fullPull が走り
  /// 「データを復元しています」のオーバーレイが出ていた。
  ///
  /// 「値が無い」ことを「まだ処理していない」と読み替えず、
  /// 状態は明示的に持つ。
  ///
  /// **バックアップ復元時は明示的に false へ戻すこと。**
  /// DB は差し替わるが SharedPreferences は残るため、落とさないと
  /// 復元した端末でサーバ側のグループデータが取得されない。
  bool get didInitialFullPull {
    return _prefs?.getBool(_kDidInitialFullPull) ?? false;
  }

  Future<void> setDidInitialFullPull(bool value) async {
    if (_prefs == null) return;
    try {
      await _prefs!.setBool(_kDidInitialFullPull, value);
    } catch (e) {
      PetloLogger.instance.d('setDidInitialFullPull failed: $e');
    }
  }

  // ==========================================================================
  // Display Name (build 18: 家族共有で初めて要求される表示名)
  // ==========================================================================

  String? get displayName {
    final String? v = _prefs?.getString(_kDisplayName);
    if (v == null || v.isEmpty) return null;
    return v;
  }

  Future<void> setDisplayName(String? value) async {
    if (_prefs == null) return;
    try {
      if (value == null || value.trim().isEmpty) {
        await _prefs!.remove(_kDisplayName);
      } else {
        await _prefs!.setString(_kDisplayName, value.trim());
      }
    } catch (e) {
      PetloLogger.instance.d('setDisplayName failed: $e');
    }
  }
}
