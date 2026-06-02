// ============================================================================
// petlo - Backup Settings Screen
// ============================================================================
//
// build 62: クラウド連携プレースホルダ撤廃、ローカル ZIP エクスポートへ全面差替
// build 63: SnackBar 一時診断 + iPad popover 対応 + AOT 安全化 (await 化)
// build 64: ZIP インポート (復元) を追加、診断 SnackBar 撤回
//
// 振る舞い (export):
//   - 「データを書き出す」ボタンで service.exportToZip()
//   - 圧縮中はインジで block、共有シートを上げる
//   - 失敗は l10n.backup_export_error の短文 SnackBar
//
// 振る舞い (import):
//   - 「データを復元する」ボタンで file_picker → ZIP 選択
//   - 確認ダイアログ (destructive) で 1 段ガード
//   - 復元中はモーダル進捗
//   - 成功: 再起動案内ダイアログ (drift DB を別ファイルに差し替えたので、
//     UI を hot reload するより素直に再起動を促す方が安全)
//   - 失敗: l10n.backup_import_error (「元データは保持されました」明記) +
//     versionTooNew / invalidFile は専用文言で出し分け
//
// ============================================================================

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/backup/backup_archive_service.dart';
import '../../../core/backup/backup_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/section_label.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/backup_settings_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/pro_status_provider.dart';
import '../paywall/paywall_screen.dart';

class BackupSettingsScreen extends ConsumerStatefulWidget {
  const BackupSettingsScreen({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const BackupSettingsScreen(),
      ),
    );
  }

  @override
  ConsumerState<BackupSettingsScreen> createState() =>
      _BackupSettingsScreenState();
}

class _BackupSettingsScreenState extends ConsumerState<BackupSettingsScreen> {
  bool _exporting = false;
  bool _importing = false;
  // build 68: クラウドバックアップ進行中フラグと進捗率 (0.0 - 1.0)。
  bool _cloudUploading = false;
  double _cloudUploadProgress = 0;
  // build 69: クラウド復元進行中フラグと進捗率。
  bool _cloudRestoring = false;
  double _cloudRestoreProgress = 0;
  // share_plus iPad popover 用 — export button RenderBox を参照する。
  final GlobalKey _exportButtonKey = GlobalKey();

  // ==========================================================================
  // Export
  // ==========================================================================

  Future<void> _runExport() async {
    if (_exporting || _importing) return;
    setState(() => _exporting = true);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    // タップ瞬間に Rect を確定 (進捗インジで geometry が変わる前)。
    final Rect? originRect = _shareOriginRect();
    try {
      final BackupArchiveService service =
          BackupArchiveService(ref.read(appDatabaseProvider));
      final BackupExportResult result = await service.exportToZip();
      if (!mounted) return;
      await ref
          .read(backupSettingsProvider.notifier)
          .markExported(at: result.exportedAt);
      await Share.shareXFiles(
        <XFile>[XFile(result.zipPath, mimeType: 'application/zip')],
        sharePositionOrigin: originRect,
      );
    } catch (e, st) {
      PetloLogger.instance
          .w('Backup export failed', error: e, stackTrace: st);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.backup_export_error),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Rect? _shareOriginRect() {
    final BuildContext? ctx = _exportButtonKey.currentContext;
    if (ctx == null) return null;
    final RenderObject? renderObj = ctx.findRenderObject();
    if (renderObj is! RenderBox || !renderObj.hasSize) return null;
    final Offset topLeft = renderObj.localToGlobal(Offset.zero);
    return topLeft & renderObj.size;
  }

  // ==========================================================================
  // Import
  // ==========================================================================

  Future<void> _runImport() async {
    if (_exporting || _importing) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    // 1. ZIP 選択
    final FilePickerResult? picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['zip'],
      withData: false,
    );
    if (picked == null || picked.files.isEmpty) return;
    final String? zipPath = picked.files.single.path;
    if (zipPath == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.backup_import_invalid_file),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!mounted) return;
    // 2. 確認ダイアログ (destructive)
    final bool confirmed = await _showConfirmDialog(l10n) ?? false;
    if (!confirmed || !mounted) return;

    setState(() => _importing = true);
    try {
      final BackupArchiveService service =
          BackupArchiveService(ref.read(appDatabaseProvider));
      await service.importFromZip(
        zipPath: zipPath,
        closeDatabase: () async {
          // drift DB を close → Provider invalidate で再生成口を空ける。
          // 再起動を案内するので、ここで再 open はしない。
          final db = ref.read(appDatabaseProvider);
          await db.close();
          ref.invalidate(appDatabaseProvider);
        },
      );
      if (!mounted) return;
      // 3. 成功 → 再起動案内
      await _showRestartDialog(l10n);
    } on BackupImportException catch (e, st) {
      PetloLogger.instance
          .w('Backup import refused', error: e, stackTrace: st);
      if (!mounted) return;
      final String message;
      switch (e.reason) {
        case BackupImportFailure.versionTooNew:
          message = l10n.backup_import_version_too_new;
        case BackupImportFailure.invalidFile:
          message = l10n.backup_import_invalid_file;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e, st) {
      PetloLogger.instance
          .e('Backup import failed', error: e, stackTrace: st);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.backup_import_error),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  // ==========================================================================
  // Cloud backup (build 68)
  // ==========================================================================

  Future<void> _runCloudBackup() async {
    if (_exporting || _importing || _cloudUploading) return;
    setState(() {
      _cloudUploading = true;
      _cloudUploadProgress = 0;
    });
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final BackupArchiveService service =
          BackupArchiveService(ref.read(appDatabaseProvider));
      final BackupCloudUploadResult result = await service.uploadToCloud(
        onSendProgress: (int sent, int total) {
          if (!mounted || total <= 0) return;
          setState(() => _cloudUploadProgress = sent / total);
        },
      );
      if (!mounted) return;
      await ref.read(backupSettingsProvider.notifier).markCloudBackupCompleted(
            at: result.completedAt,
            byteSize: result.byteSize,
          );
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.cloud_backup_success),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e, st) {
      PetloLogger.instance
          .w('Cloud backup failed', error: e, stackTrace: st);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.cloud_backup_error),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _cloudUploading = false;
          _cloudUploadProgress = 0;
        });
      }
    }
  }

  /// build 69: クラウドから復元 (経路2 - 同一端末・連携済み)。
  /// downloadAndRestoreFromCloud → 成功で再起動案内、 404 で no_backup、
  /// その他失敗で cloud_restore_error。
  Future<void> _runCloudRestore() async {
    if (_exporting || _importing || _cloudUploading || _cloudRestoring) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final bool confirmed =
        await _showCloudRestoreConfirmDialog(l10n) ?? false;
    if (!confirmed || !mounted) return;

    setState(() {
      _cloudRestoring = true;
      _cloudRestoreProgress = 0;
    });
    try {
      final BackupArchiveService service =
          BackupArchiveService(ref.read(appDatabaseProvider));
      await service.downloadAndRestoreFromCloud(
        closeDatabase: () async {
          final db = ref.read(appDatabaseProvider);
          await db.close();
          ref.invalidate(appDatabaseProvider);
        },
        onReceiveProgress: (int received, int total) {
          if (!mounted || total <= 0) return;
          setState(() => _cloudRestoreProgress = received / total);
        },
      );
      if (!mounted) return;
      // 成功 → 既存 import の「再起動が必要」ダイアログを再利用 (文言は
      // cloud_restore_success が「アプリを再起動してください」を内包)。
      await _showCloudRestoreSuccessDialog(l10n);
    } on CloudBackupNotFound {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.cloud_restore_no_backup),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e, st) {
      PetloLogger.instance
          .w('Cloud restore failed', error: e, stackTrace: st);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.cloud_restore_error),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _cloudRestoring = false;
          _cloudRestoreProgress = 0;
        });
      }
    }
  }

  Future<bool?> _showCloudRestoreConfirmDialog(AppLocalizations l10n) {
    final AppColors colors = AppColors.of(context);
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: colors.bg,
          shape: const RoundedRectangleBorder(),
          title: Text(
            l10n.cloud_restore_confirm_title,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 22,
              color: colors.fg,
            ),
          ),
          content: Text(
            l10n.cloud_restore_confirm_message,
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
                l10n.common_continue,
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
          // cloud_restore_success は「復元しました。アプリを再起動して
          // ください。」を内包しているので、title だけで意味が通る。
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

  Future<bool?> _showConfirmDialog(AppLocalizations l10n) {
    final AppColors colors = AppColors.of(context);
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: colors.bg,
          shape: const RoundedRectangleBorder(),
          title: Text(
            l10n.backup_import_confirm_title,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 22,
              color: colors.fg,
            ),
          ),
          content: Text(
            l10n.backup_import_confirm_message,
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
                l10n.common_continue,
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

  Future<void> _showRestartDialog(AppLocalizations l10n) {
    final AppColors colors = AppColors.of(context);
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: colors.bg,
          shape: const RoundedRectangleBorder(),
          title: Text(
            l10n.backup_import_success,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 22,
              color: colors.fg,
            ),
          ),
          content: Text(
            l10n.backup_import_restart_required,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              color: colors.fg,
              height: 1.5,
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
  // Build
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String localeTag = Localizations.localeOf(context).toLanguageTag();
    final BackupSettings settings = ref.watch(backupSettingsProvider);
    final bool isPro = ref.watch(isProProvider);
    final AuthStatus authStatus = ref.watch(authStatusProvider);
    final bool isOnline = ref.watch(isOnlineSnapshotProvider);
    final bool canCloudBackup = isPro &&
        authStatus == AuthStatus.appleLinked &&
        isOnline;
    final bool busy =
        _exporting || _importing || _cloudUploading || _cloudRestoring;

    return Stack(
      children: <Widget>[
        Scaffold(
          backgroundColor: colors.bg,
          appBar: AppBar(
            backgroundColor: colors.bg,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              l10n.backup_app_bar,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 10,
                letterSpacing: 10 * 0.2,
                color: colors.fg,
              ),
            ),
            centerTitle: true,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: colors.fg),
              onPressed:
                  busy ? null : () => Navigator.of(context).pop(),
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SectionLabel(
                    l10n.backup_section_title,
                    size: EyebrowSize.large,
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.backup_export_description,
                    style: typo.bodyMedium
                        .copyWith(color: colors.fgMuted, height: 1.6),
                  ),
                  const SizedBox(height: 24),
                  _LastExportRow(
                    lastExportAt: settings.lastExportAt,
                    localeTag: localeTag,
                  ),
                  const SizedBox(height: 24),
                  _PrimaryActionButton(
                    key: _exportButtonKey,
                    label: _exporting
                        ? l10n.backup_exporting
                        : l10n.backup_export_button,
                    enabled: !busy,
                    showProgress: _exporting,
                    onTap: _runExport,
                  ),
                  const SizedBox(height: 32),
                  _SecondaryActionButton(
                    label: _importing
                        ? l10n.backup_importing
                        : l10n.backup_import_button,
                    enabled: !busy,
                    showProgress: _importing,
                    onTap: _runImport,
                  ),
                  // build 68: クラウドバックアップブロック (ローカル ZIP の下)。
                  const SizedBox(height: 40),
                  _CloudBackupSection(
                    settings: settings,
                    localeTag: localeTag,
                    isPro: isPro,
                    appleLinked: authStatus == AuthStatus.appleLinked,
                    isOnline: isOnline,
                    canCloudBackup: canCloudBackup,
                    busy: busy,
                    uploading: _cloudUploading,
                    progress: _cloudUploadProgress,
                    onTapEnabled: _runCloudBackup,
                    onTapPaywall: () => PaywallScreen.push(context),
                    restoring: _cloudRestoring,
                    restoreProgress: _cloudRestoreProgress,
                    onTapRestore: _runCloudRestore,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_importing)
          // インポート中は外側 Stack で全画面に薄幕 + インジ。
          // 復元中にバックボタンや別画面遷移を物理的に防ぐ。
          ModalBarrier(
            color: colors.bg.withValues(alpha: 0.7),
            dismissible: false,
          ),
        if (_importing)
          Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(colors.fg),
              ),
            ),
          ),
      ],
    );
  }
}

class _LastExportRow extends StatelessWidget {
  const _LastExportRow({required this.lastExportAt, required this.localeTag});

  final DateTime? lastExportAt;
  final String localeTag;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String value = lastExportAt == null
        ? l10n.backup_status_never
        : formatDateTime(lastExportAt!, localeTag);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.line),
          bottom: BorderSide(color: colors.line),
        ),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              l10n.backup_status_last_backup,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 9,
                letterSpacing: 9 * 0.2,
                color: colors.fgMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 11,
                letterSpacing: 11 * 0.05,
                color: colors.fg,
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Primary CTA (filled, 反転色)。エクスポート用。
class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.showProgress,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final bool showProgress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? colors.fg : colors.fgFaint,
          border: Border.all(
            color: enabled ? colors.fg : colors.fgFaint,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (showProgress) ...<Widget>[
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.bg),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 10,
                letterSpacing: 10 * 0.18,
                color: colors.bg,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Secondary CTA (outline、destructive 系)。インポート用。
class _SecondaryActionButton extends StatelessWidget {
  const _SecondaryActionButton({
    required this.label,
    required this.enabled,
    required this.showProgress,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final bool showProgress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.bg,
          border: Border.all(
            color: enabled ? colors.fg : colors.fgFaint,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (showProgress) ...<Widget>[
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.fg),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 10,
                letterSpacing: 10 * 0.18,
                color: enabled ? colors.fg : colors.fgFaint,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// build 68: クラウドバックアップ用ブロック。
///
/// 状態は `canCloudBackup` (= isPro && appleLinked && isOnline) で 4 通り:
///   - canCloudBackup = true  : 「いますぐクラウドにバックアップ」ボタン
///   - !isPro                 : "Proプランでクラウドバックアップ" ヒント
///                              タップで Paywall へ
///   - isPro && !appleLinked  : "Appleアカウント連携が必要です" ヒント
///                              タップ不可 (settings 画面で連携してもらう)
///   - !isOnline              : "オフラインです" でボタン無効化
class _CloudBackupSection extends StatelessWidget {
  const _CloudBackupSection({
    required this.settings,
    required this.localeTag,
    required this.isPro,
    required this.appleLinked,
    required this.isOnline,
    required this.canCloudBackup,
    required this.busy,
    required this.uploading,
    required this.progress,
    required this.onTapEnabled,
    required this.onTapPaywall,
    // build 69: 復元 (canCloudBackup=true の時だけ表示)
    required this.restoring,
    required this.restoreProgress,
    required this.onTapRestore,
  });

  final BackupSettings settings;
  final String localeTag;
  final bool isPro;
  final bool appleLinked;
  final bool isOnline;
  final bool canCloudBackup;
  final bool busy;
  final bool uploading;
  final double progress; // 0.0 - 1.0
  final VoidCallback onTapEnabled;
  final VoidCallback onTapPaywall;
  final bool restoring;
  final double restoreProgress;
  final VoidCallback onTapRestore;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String value = settings.lastCloudBackupAt == null
        ? l10n.cloud_backup_never
        : formatDateTime(settings.lastCloudBackupAt!, localeTag);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // last cloud backup 表示行 (ローカル _LastExportRow と同じ意匠)。
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: colors.line),
              bottom: BorderSide(color: colors.line),
            ),
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 110,
                child: Text(
                  l10n.cloud_backup_last_label,
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 9,
                    letterSpacing: 9 * 0.2,
                    color: colors.fgMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 11,
                    letterSpacing: 11 * 0.05,
                    color: colors.fg,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildCta(context, colors, typo, l10n),
        // build 69: canCloudBackup の時だけ「クラウドから復元」を上下並びで提示。
        // Pro 未加入 / 未連携 / オフラインでは復元の余地が無いので非表示。
        if (canCloudBackup) ...<Widget>[
          const SizedBox(height: 12),
          _CloudRestoreButton(
            label: restoring
                ? l10n.cloud_restore_in_progress
                : l10n.cloud_restore_button,
            enabled: !busy,
            restoring: restoring,
            progress: restoreProgress,
            onTap: onTapRestore,
          ),
        ],
      ],
    );
  }

  Widget _buildCta(
    BuildContext context,
    AppColors colors,
    AppTypography typo,
    AppLocalizations l10n,
  ) {
    // 3-way gate のうち、!isPro と (isPro && !appleLinked) はそれぞれ
    // ヒント文 + タップ動作で出し分ける。!isOnline は単にボタン無効化。
    if (!isPro) {
      return _CloudHintButton(
        label: l10n.cloud_backup_button,
        hint: l10n.cloud_backup_pro_hint,
        enabled: !busy,
        onTap: onTapPaywall,
      );
    }
    if (!appleLinked) {
      return _CloudHintButton(
        label: l10n.cloud_backup_button,
        hint: l10n.cloud_backup_link_required,
        enabled: false, // settings 画面で SIWA してもらう想定 → タップ無効
        onTap: () {},
      );
    }
    if (!isOnline) {
      return _CloudHintButton(
        label: l10n.cloud_backup_button,
        hint: l10n.cloud_backup_offline,
        enabled: false,
        onTap: () {},
      );
    }
    // canCloudBackup = true の正規ルート。
    return _CloudPrimaryButton(
      label:
          uploading ? l10n.cloud_backup_in_progress : l10n.cloud_backup_button,
      enabled: !busy,
      uploading: uploading,
      progress: progress,
      onTap: onTapEnabled,
    );
  }
}

/// 連携前 / オフライン / Pro 未加入 用のヒント表示付きアウトラインボタン。
/// label = メインタイトル、hint = 下にサブテキスト。
class _CloudHintButton extends StatelessWidget {
  const _CloudHintButton({
    required this.label,
    required this.hint,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        // build 70: 他の全幅ボタンと同じく Container を親の最大幅まで広げる。
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.bg,
          border: Border.all(
            color: enabled ? colors.fg : colors.fgFaint,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 10,
                letterSpacing: 10 * 0.18,
                color: enabled ? colors.fg : colors.fgFaint,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hint,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 11,
                color: colors.fgMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// canCloudBackup = true 用の filled ボタン。アップロード中は determinate
/// LinearProgressIndicator + 進捗 % ラベル。
class _CloudPrimaryButton extends StatelessWidget {
  const _CloudPrimaryButton({
    required this.label,
    required this.enabled,
    required this.uploading,
    required this.progress,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final bool uploading;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final int pct = (progress.clamp(0.0, 1.0) * 100).round();
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        // build 70: 他の全幅ボタン (_PrimaryActionButton / _SecondaryActionButton /
        // _CloudRestoreButton) と同じく alignment を入れて Container を親の
        // 利用可能幅まで広げる。これが無いと Container は子の Column のサイズに
        // 縮退して content-width になり、縦並びのボタン群で 1 つだけ幅が
        // 違って見えてしまっていた。
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? colors.fg : colors.fgFaint,
          border: Border.all(
            color: enabled ? colors.fg : colors.fgFaint,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              uploading ? '${label.toUpperCase()}  $pct%' : label.toUpperCase(),
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 10,
                letterSpacing: 10 * 0.18,
                color: colors.bg,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (uploading) ...<Widget>[
              const SizedBox(height: 8),
              SizedBox(
                height: 2,
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  backgroundColor: colors.bg.withValues(alpha: 0.25),
                  valueColor: AlwaysStoppedAnimation<Color>(colors.bg),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// build 69: クラウドから復元する secondary outline ボタン。意匠は
/// `_SecondaryActionButton` をベースに、復元中は determinate な
/// LinearProgressIndicator を下に薄く出す。
class _CloudRestoreButton extends StatelessWidget {
  const _CloudRestoreButton({
    required this.label,
    required this.enabled,
    required this.restoring,
    required this.progress,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final bool restoring;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final int pct = (progress.clamp(0.0, 1.0) * 100).round();
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.bg,
          border: Border.all(
            color: enabled ? colors.fg : colors.fgFaint,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              restoring ? '${label.toUpperCase()}  $pct%' : label.toUpperCase(),
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 10,
                letterSpacing: 10 * 0.18,
                color: enabled ? colors.fg : colors.fgFaint,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (restoring) ...<Widget>[
              const SizedBox(height: 8),
              SizedBox(
                height: 2,
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  backgroundColor: colors.line,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.fg),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
