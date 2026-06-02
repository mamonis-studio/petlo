// ============================================================================
// petlo - Settings Screen (build 13 rev)
// ============================================================================
//
// 全タブ AppBar 右上の歯車から push される統合設定画面。
// build 13 で「その他」タブを廃止し、その中身をすべてここに集約。
//
// セクション構成:
//   - Pro バナー (無料時のみ)
//   - アカウント (ゲスト + バックアップ)
//   - 機能 (家族共有 / 投薬リマインダー)
//   - アプリ (テーマ / 言語 / 通知 / サブスク)
//   - サポート (お問い合わせ)
//   - 法的 (利用規約 / プライバシー)
//   - アプリについて (バージョン — 5タップで開発者設定)
//   - mamonis.studio (SNS + サイト)
//
// ============================================================================

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/backup/backup_archive_service.dart';
import '../../../core/billing/pro_status.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/section_label.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/display_name_provider.dart';
import '../../providers/pro_status_provider.dart';
import '../backup/backup_settings_screen.dart';
import '../groups/groups_list_screen.dart';
import '../paywall/paywall_screen.dart';
import '../pet/pets_management_screen.dart';
import 'developer_settings_screen.dart';
import 'display_name_screen.dart';
import 'theme_settings_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _versionTapCount = 0;
  // build 65 T5/T6: アカウント連携 / 削除中のボタン無効化フラグ。
  bool _signingInWithApple = false;
  bool _deletingAccount = false;
  // build 69: subAlreadyLinked 経路で /auth/apple → /backup 復元中。
  // この間は全画面に modal barrier を被せて操作を物理ブロック。
  bool _restoring = false;
  double _restoreProgress = 0;

  void _onVersionTap() {
    // build 61: Release ビルドではデバッグメニューを完全に塞ぐ。
    // 5 回タップのカウントすら開始しない。App Store 審査対策。
    if (kReleaseMode) return;
    setState(() => _versionTapCount++);
    if (_versionTapCount >= 5) {
      _versionTapCount = 0;
      DeveloperSettingsScreen.push(context);
    }
  }

  // ==========================================================================
  // T5: Sign in with Apple
  // ==========================================================================

  Future<void> _runAppleSignIn() async {
    if (_signingInWithApple || _deletingAccount || _restoring) return;
    setState(() => _signingInWithApple = true);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final AppleSignInResult result =
          await AuthService.instance.signInWithApple();
      if (!mounted) return;
      // build 69: subAlreadyLinked は復元フローへの入り口に切り替え。
      // この Apple ID は別端末で使った既存ユーザがいる → 機種変 / 再インストール
      // の典型ケース。エラー扱いせず「以前のデータがあります」と提示する。
      if (result == AppleSignInResult.subAlreadyLinked) {
        await _handleSubAlreadyLinked(l10n, messenger);
        return;
      }
      final String? message = switch (result) {
        AppleSignInResult.success => l10n.auth_sign_in_success,
        AppleSignInResult.subAlreadyLinked => null, // 上で処理済
        AppleSignInResult.alreadyLinked =>
          l10n.auth_sign_in_error_already_linked,
        AppleSignInResult.canceled => null,
        AppleSignInResult.failed => l10n.auth_sign_in_error_generic,
      };
      if (message != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _signingInWithApple = false);
    }
  }

  /// build 69: subAlreadyLinked 経路の復元フロー。
  ///   1. 「以前のデータがあります」確認ダイアログ
  ///   2. restoreWithApple() で /auth/apple → server 既存 user の Bearer に切替
  ///   3. downloadAndRestoreFromCloud() で /backup から ZIP DL → import
  ///   4. 成功 → 再起動案内、 404 → 「クラウドにバックアップなし」、 失敗 → エラー
  Future<void> _handleSubAlreadyLinked(
    AppLocalizations l10n,
    ScaffoldMessengerState messenger,
  ) async {
    final bool confirmed =
        await _showAuthRestorePromptDialog(l10n) ?? false;
    if (!confirmed || !mounted) return;

    setState(() {
      _restoring = true;
      _restoreProgress = 0;
    });
    try {
      // === Step 1: /auth/apple で Bearer 切替 ===
      final AppleRestoreResult auth =
          await AuthService.instance.restoreWithApple();
      if (!mounted) return;
      if (auth == AppleRestoreResult.canceled) {
        return; // 静かに中断
      }
      if (auth == AppleRestoreResult.failed) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.cloud_restore_error),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // === Step 2: /backup から DL → import ===
      final BackupArchiveService service =
          BackupArchiveService(ref.read(appDatabaseProvider));
      try {
        await service.downloadAndRestoreFromCloud(
          closeDatabase: () async {
            final db = ref.read(appDatabaseProvider);
            await db.close();
            ref.invalidate(appDatabaseProvider);
          },
          onReceiveProgress: (int received, int total) {
            if (!mounted || total <= 0) return;
            setState(() => _restoreProgress = received / total);
          },
        );
        if (!mounted) return;
        await _showCloudRestoreSuccessDialog(l10n);
      } on CloudBackupNotFound {
        // 連携自体は完了済 → エラーではなく「データ無しで続行」案内のみ。
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.cloud_restore_no_backup),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e, st) {
        PetloLogger.instance.w(
          'cloud restore failed after Apple switch',
          error: e,
          stackTrace: st,
        );
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.cloud_restore_error),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _restoring = false;
          _restoreProgress = 0;
        });
      }
    }
  }

  Future<bool?> _showAuthRestorePromptDialog(AppLocalizations l10n) {
    final AppColors colors = AppColors.of(context);
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: colors.bg,
          shape: const RoundedRectangleBorder(),
          title: Text(
            l10n.auth_restore_prompt_title,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 22,
              color: colors.fg,
            ),
          ),
          content: Text(
            l10n.auth_restore_prompt_message,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              color: colors.fg,
              height: 1.5,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                l10n.common_cancel,
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 11,
                  letterSpacing: 11 * 0.15,
                  color: colors.fgMuted,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                l10n.auth_restore_prompt_restore,
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 11,
                  letterSpacing: 11 * 0.15,
                  color: colors.accentDanger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCloudRestoreSuccessDialog(AppLocalizations l10n) {
    final AppColors colors = AppColors.of(context);
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: colors.bg,
          shape: const RoundedRectangleBorder(),
          title: Text(
            l10n.cloud_restore_success,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 22,
              color: colors.fg,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                l10n.common_ok,
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 11,
                  letterSpacing: 11 * 0.15,
                  color: colors.fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ==========================================================================
  // T6: Account delete
  // ==========================================================================

  Future<void> _runAccountDelete() async {
    if (_signingInWithApple || _deletingAccount || _restoring) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final bool confirmed = await _showAccountDeleteConfirmDialog(l10n) ?? false;
    if (!confirmed || !mounted) return;

    setState(() => _deletingAccount = true);
    try {
      // build 65 バグ修正: deleteAccount は drift DB を close できる callback を
      // 要求する (sqlite ファイル削除前に file handle を解放するため)。
      final bool ok = await AuthService.instance.deleteAccount(
        closeDatabase: () async {
          final db = ref.read(appDatabaseProvider);
          await db.close();
          ref.invalidate(appDatabaseProvider);
        },
      );
      if (!mounted) return;
      if (ok) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.account_delete_success),
            behavior: SnackBarBehavior.floating,
          ),
        );
        // 「アプリ初期状態へ遷移」: settings 画面を root まで pop。
        // authStatusProvider は既に anonymous に切り替わっているので、
        // 上位画面のアカウントセクションは再描画でサインインボタンを出す。
        Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.account_delete_error),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  Future<bool?> _showAccountDeleteConfirmDialog(AppLocalizations l10n) {
    final AppColors colors = AppColors.of(context);
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: colors.bg,
          shape: const RoundedRectangleBorder(),
          title: Text(
            l10n.account_delete_confirm_title,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 22,
              color: colors.fg,
            ),
          ),
          content: Text(
            l10n.account_delete_confirm_message,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              color: colors.fg,
              height: 1.5,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                l10n.common_cancel,
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 11,
                  letterSpacing: 11 * 0.15,
                  color: colors.fgMuted,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                l10n.account_delete_confirm_button,
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 11,
                  letterSpacing: 11 * 0.15,
                  color: colors.accentDanger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isPro = ref.watch(isProProvider);
    final AuthStatus authStatus = ref.watch(authStatusProvider);

    return Stack(
      children: <Widget>[
        Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        foregroundColor: colors.fg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          l10n.settings_app_bar_title.toUpperCase(),
          style: typo.metaSmall.copyWith(letterSpacing: 10 * 0.2),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // バナー類
              // build 62: クラウド連携プレースホルダ撤廃。代わりに「データ管理」
              // セクションからローカル ZIP エクスポートを提供する。
              if (!isPro)
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 16, 28, 8),
                  child: _ProCtaBanner(colors: colors, typo: typo),
                ),
              const SizedBox(height: 16),

              // ===== アカウント (build 65 T5/T6: SIWA + 削除動線) =====
              _SectionHeader(label: l10n.other_section_account),
              // 連携状態 × Pro 判定で 3 分岐:
              //   appleLinked              → 連携済み表示 (タップ不可)
              //   anonymous + isPro=true   → SIWA 直接実行
              //   anonymous + isPro=false  → Paywall へ誘導 (Pro hint 付き)
              if (authStatus == AuthStatus.appleLinked)
                _Row(
                  title: l10n.auth_account_linked_title,
                  subtitle: l10n.auth_account_linked_subtitle,
                )
              else if (isPro)
                _Row(
                  title: l10n.auth_sign_in_apple_button,
                  onTap: _signingInWithApple ? null : _runAppleSignIn,
                )
              else
                _Row(
                  title: l10n.auth_sign_in_apple_button,
                  subtitle: l10n.auth_sign_in_apple_pro_hint,
                  onTap: () => PaywallScreen.push(context),
                ),
              // build 18: 家族共有メンバー表示名
              _Row(
                title: l10n.settings_row_display_name_title,
                subtitle: ref.watch(displayNameProvider) ??
                    l10n.settings_row_display_name_unset,
                onTap: () => DisplayNameScreen.push(context),
              ),
              // build 65 T6: アカウント削除 (link 有無問わず常に表示)
              _DestructiveRow(
                title: _deletingAccount
                    ? l10n.account_delete_in_progress
                    : l10n.account_delete_button,
                enabled: !_deletingAccount && !_signingInWithApple,
                onTap: _runAccountDelete,
              ),

              // ===== 機能 =====
              _SectionHeader(label: l10n.more_section_family),
              _Row(
                title: l10n.more_item_groups,
                onTap: () => GroupsListScreen.push(context),
              ),
              // build 58: ペット編集動線の正規ルート (案 B)。
              _Row(
                title: l10n.more_item_pets_management,
                onTap: () => PetsManagementScreen.push(context),
              ),
              // build 47b (Scope B5): medication_reminders は schedules に
              // 統合された。投薬の設定は予定 (Plans) タブから行う。

              // ===== データ管理 (build 62) =====
              _SectionHeader(label: l10n.backup_section_title),
              _Row(
                title: l10n.backup_export_button,
                subtitle: l10n.backup_export_description,
                onTap: () => BackupSettingsScreen.push(context),
              ),

              // ===== アプリ =====
              _SectionHeader(label: l10n.settings_section_app),
              _Row(
                title: l10n.settings_item_theme,
                onTap: () => ThemeSettingsScreen.push(context),
              ),
              _Row(
                title: l10n.settings_item_language,
                subtitle: l10n.settings_item_language_subtitle,
                trailing: l10n.settings_item_open_ios_settings,
                onTap: () => _openOsSettings(context),
              ),
              _Row(
                title: l10n.settings_item_notifications,
                subtitle: const _NotificationStatus(),
                onTap: () async {
                  final bool granted = await NotificationService.instance
                      .requestPermissions();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(granted
                          ? l10n.notifications_enabled
                          : l10n.notifications_disabled_open_settings),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              _Row(
                title: l10n.settings_item_subscription,
                subtitle: const _SubscriptionStatus(),
                onTap: () => PaywallScreen.push(context),
              ),

              // ===== サポート =====
              _SectionHeader(label: l10n.settings_section_support),
              _Row(
                title: l10n.settings_item_contact,
                subtitle: AppConstants.contactEmail,
                onTap: () => _launchMail(context),
              ),

              // ===== 法的 =====
              _SectionHeader(label: l10n.settings_section_legal),
              _Row(
                title: l10n.settings_item_terms,
                onTap: () => _openUrl(context, AppConstants.termsOfUseUrl),
              ),
              _Row(
                title: l10n.settings_item_privacy,
                onTap: () => _openUrl(context, AppConstants.privacyPolicyUrl),
              ),

              // ===== アプリについて =====
              _SectionHeader(label: l10n.settings_section_about),
              _Row(
                title: l10n.settings_item_version,
                subtitle:
                    '${AppConstants.appVersion} (build ${AppConstants.appBuildNumber})',
                onTap: _onVersionTap,
              ),

              // ===== mamonis.studio =====
              _SectionHeader(label: l10n.other_section_studio),
              _Row(
                title: l10n.other_studio_x,
                onTap: () => _openUrl(context, AppConstants.xUrl),
              ),
              _Row(
                title: l10n.other_studio_instagram,
                onTap: () => _openUrl(context, AppConstants.instagramUrl),
              ),
              _Row(
                title: l10n.other_studio_tiktok,
                onTap: () => _openUrl(context, AppConstants.tiktokUrl),
              ),
              _Row(
                title: l10n.other_studio_website,
                subtitle: 'petlo.mamonis.studio',
                onTap: () => _openUrl(context, AppConstants.websiteUrl),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
        ),
        // build 69: 復元中は全画面 modal barrier + 進捗インジ + %。
        // バックボタンや他画面遷移を物理的にブロックして復元途中での
        // 操作事故を防ぐ。
        if (_restoring)
          ModalBarrier(
            color: colors.bg.withValues(alpha: 0.7),
            dismissible: false,
          ),
        if (_restoring)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation<Color>(colors.fg),
                    value: _restoreProgress > 0
                        ? _restoreProgress.clamp(0.0, 1.0)
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.cloud_restore_in_progress,
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 10,
                    letterSpacing: 10 * 0.18,
                    color: colors.fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_restoreProgress > 0) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    '${(_restoreProgress.clamp(0.0, 1.0) * 100).round()}%',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10,
                      color: colors.fgMuted,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    try {
      final Uri uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e, st) {
      PetloLogger.instance.w('open url failed', error: e, stackTrace: st);
    }
  }

  Future<void> _launchMail(BuildContext context) async {
    final Uri uri = Uri(
      scheme: 'mailto',
      path: AppConstants.contactEmail,
      queryParameters: <String, String>{
        'subject':
            'petlo ${AppConstants.appVersion}+${AppConstants.appBuildNumber}',
      },
    );
    try {
      await launchUrl(uri);
    } catch (e, st) {
      PetloLogger.instance.w('mailto failed', error: e, stackTrace: st);
    }
  }

  Future<void> _openOsSettings(BuildContext context) async {
    try {
      final Uri uri = Uri.parse('app-settings:');
      final bool ok =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (e, st) {
      PetloLogger.instance
          .w('open app-settings failed', error: e, stackTrace: st);
    }
    if (!context.mounted) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.settings_language_helper),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ============================================================================
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: SectionLabel(
        label,
        padding: const EdgeInsets.fromLTRB(0, 24, 0, 12),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  final String title;
  final Object? subtitle; // String or Widget
  final VoidCallback? onTap;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    final Widget? subtitleWidget = switch (subtitle) {
      final String s => Text(
          s,
          style: typo.bodySmall.copyWith(color: colors.fgMuted),
        ),
      final Widget w => w,
      _ => null,
    };

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(28, 14, 28, 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.line)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: typo.bodyLarge.copyWith(
                      color: onTap != null ? colors.fg : colors.fgMuted,
                    ),
                  ),
                  if (subtitleWidget != null) ...<Widget>[
                    const SizedBox(height: 2),
                    subtitleWidget,
                  ],
                ],
              ),
            ),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: 12),
              Text(
                trailing!,
                style: typo.bodySmall.copyWith(
                  color: colors.fgMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// build 65 T6: アカウント削除など destructive action 用の行。
/// _Row と同じレイアウトだが、本文を danger 色で出し、subtitle / trailing は
/// 取らない (用途を絞る)。enabled=false の間はタップ無効 + 色が薄くなる。
class _DestructiveRow extends StatelessWidget {
  const _DestructiveRow({
    required this.title,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(28, 14, 28, 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.line)),
        ),
        child: Text(
          title,
          style: typo.bodyLarge.copyWith(
            color: enabled ? colors.accentDanger : colors.fgFaint,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _NotificationStatus extends StatefulWidget {
  const _NotificationStatus();

  @override
  State<_NotificationStatus> createState() => _NotificationStatusState();
}

class _NotificationStatusState extends State<_NotificationStatus> {
  bool? _granted;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final bool g = await NotificationService.instance.hasPermissions();
    if (mounted) setState(() => _granted = g);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String label = switch (_granted) {
      true => l10n.notifications_enabled,
      false => l10n.notifications_disabled_open_settings,
      null => '...',
    };
    return Text(
      label,
      style: typo.bodySmall.copyWith(
        color: _granted == false ? colors.accentWarn : colors.fgMuted,
      ),
    );
  }
}

class _SubscriptionStatus extends ConsumerWidget {
  const _SubscriptionStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final ProStatus status = ref.watch(proStatusProvider);
    final bool isPro = ref.watch(isProProvider);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String label = switch (status.state) {
      ProState.active => isPro ? 'Pro' : 'Free',
      ProState.grace => l10n.settings_pro_status_grace,
      ProState.cancelled => l10n.settings_pro_status_cancelled,
      ProState.free => isPro ? 'Pro (Force)' : 'Free',
    };
    return Text(
      label,
      style: typo.bodySmall.copyWith(color: colors.fgMuted),
    );
  }
}

// ============================================================================
class _ProCtaBanner extends StatelessWidget {
  const _ProCtaBanner({required this.colors, required this.typo});

  final AppColors colors;
  final AppTypography typo;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: () => PaywallScreen.push(context),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: colors.fg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'petlo Pro',
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 11,
                color: colors.bg.withValues(alpha: 0.6),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.more_pro_cta_hero,
              style: TextStyle(
                fontFamily: 'Fraunces',
                fontStyle: FontStyle.italic,
                fontSize: 28,
                letterSpacing: -28 * 0.04,
                height: 1.0,
                color: colors.bg,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.more_pro_cta_body,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 13,
                color: colors.bg.withValues(alpha: 0.85),
                height: 1.6,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: colors.bg, width: 1),
              ),
              child: Text(
                '${l10n.more_pro_view_plans}  →',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  color: colors.bg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
