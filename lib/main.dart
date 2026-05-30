// ============================================================================
// petlo - Application Entry Point
// ============================================================================
//
// このファイルは最小限のbootstrap処理のみ。
// 各責務はそれぞれのモジュールに分離。
//
// 起動順序:
//   1. WidgetsFlutterBinding初期化
//   2. システム設定(ステータスバー等)
//   3. ロガー初期化
//   4. ProviderScopeでRiverpod起動
//   5. PetloAppルート → TabShell起動
//
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/auth_service.dart';
import 'core/auth/user_profile_service.dart';
import 'data/local/app_database.dart';
import 'core/billing/purchase_service.dart';
import 'core/constants/app_constants.dart';
import 'core/notifications/notification_service.dart';
import 'core/preferences/user_preferences.dart';
import 'core/sync/sync_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/locale_aware_theme.dart';
import 'core/utils/logger.dart';
import 'l10n/generated/app_localizations.dart';
import 'presentation/providers/bootstrap_provider.dart';
import 'presentation/providers/database_provider.dart';
import 'presentation/providers/group_api_service_provider.dart';
import 'presentation/providers/notification_scheduler_provider.dart';
import 'presentation/providers/onboarding_completed_provider.dart';
import 'presentation/providers/purchase_provider.dart';
import 'presentation/providers/theme_mode_provider.dart';
import 'presentation/screens/onboarding/onboarding_flow.dart';
import 'presentation/screens/tab_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // === システム設定 ===
  // edge-to-edge は Flutter Window 上層に色が届かない問題があり、
  // ステータスバー / ホームインジケーター領域が黒く露出してしまう。
  // manual モードに戻し、statusBar / systemNavigationBar を白で塗る。
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: <SystemUiOverlay>[SystemUiOverlay.top, SystemUiOverlay.bottom],
  );

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFFFFFFFF),
      statusBarIconBrightness: Brightness.dark, // Android: 黒アイコン
      statusBarBrightness: Brightness.light, // iOS: 黒文字
      systemNavigationBarColor: Color(0xFFFFFFFF),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // === ロガー初期化 ===
  await PetloLogger.initialize();
  PetloLogger.instance
      .i('petlo starting up... version=${AppConstants.appVersion}');

  // === ユーザー設定の初期化(テーマ等) ===
  await UserPreferences.instance.initialize();

  // === 通知初期化 ===
  await NotificationService.instance.initialize();

  // === IAP 初期化 (失敗してもアプリは起動する) ===
  await PurchaseService.instance.initialize();

  // === API 認証初期化 (初回 /auth/anonymous + secure_storage 同期、
  //     ネットワーク不通でも起動継続)
  try {
    await AuthService.instance.initialize();
  } catch (e, st) {
    PetloLogger.instance.w(
      'AuthService.initialize failed (continuing without auth)',
      error: e,
      stackTrace: st,
    );
  }

  // === display_name の起動時同期 (build 18) ===
  // /me が未実装の本番環境でも 404 は無視、UI を遅延させない。
  Future<void>.microtask(UserProfileService.instance.syncFromServer);

  // === Riverpod起動 ===
  runApp(
    const ProviderScope(
      child: PetloApp(),
    ),
  );
}

// ============================================================================
// PetloApp - ルートWidget
// ============================================================================
class PetloApp extends ConsumerStatefulWidget {
  const PetloApp({super.key});

  @override
  ConsumerState<PetloApp> createState() => _PetloAppState();
}

class _PetloAppState extends ConsumerState<PetloApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 起動時に通知を再スケジュール (端末再起動・アプリkill対応)
    // fire-and-forget — UI起動を遅延させない
    Future<void>.microtask(_rescheduleNotifications);
    // IAP 購入リスナーを起動 (購入成功時に ProStatusProvider を更新)
    ref.read(purchaseListenerProvider).start();
    // build 19: 同期エンジンに DB を bind + 起動同期を発火
    Future<void>.microtask(_bootstrapSync);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // build 26: アプリ終了時はポーリング Timer を確実に止める
    SyncService.instance.stopPolling();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // build 26: フォアグラウンド状態にあるときだけポーリングを走らせる。
    switch (state) {
      case AppLifecycleState.resumed:
        // 復帰時: 即時 1 回同期 + 2 分ポーリング再開
        unawaited(SyncService.instance.syncAll());
        SyncService.instance.startPolling();
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // バックグラウンド遷移時: タイマー停止 (バッテリー / 通信節約)
        SyncService.instance.stopPolling();
    }
  }

  Future<void> _bootstrapSync() async {
    try {
      final db = ref.read(appDatabaseProvider);
      SyncService.instance.bindDatabase(db);

      // build 55-client: 初回起動 / アプリ削除→再インストール直後の検知。
      // ローカル groups テーブルが空で、かつ認証済みなら、サーバから自分の
      // 全グループを取得 + 各 group を since=0 で pull する (= fullPull)。
      // 通常のセッション復帰では skip し、syncAll の incremental pull に任せる。
      final List<GroupEntity> existingGroups =
          await db.select(db.groups).get();
      final bool needFullPull = existingGroups.isEmpty &&
          AuthService.instance.isAuthenticated;
      if (needFullPull) {
        ref.read(bootstrapStatusProvider.notifier).begin();
        try {
          PetloLogger.instance.i(
            '[bootstrap] local groups empty + authenticated → fullPull',
          );
          await SyncService.instance
              .fullPull(ref.read(groupApiServiceProvider));
        } catch (e, st) {
          PetloLogger.instance.w(
            '[bootstrap] fullPull failed (continuing)',
            error: e, stackTrace: st,
          );
        } finally {
          ref.read(bootstrapStatusProvider.notifier).end();
        }
      }

      await SyncService.instance.syncAll();
      // build 26: 起動完了 + 初回同期後、定期ポーリング開始
      SyncService.instance.startPolling();
    } catch (e, st) {
      PetloLogger.instance
          .w('Initial sync failed (continuing)', error: e, stackTrace: st);
    }
  }

  Future<void> _rescheduleNotifications() async {
    try {
      final scheduler = ref.read(notificationSchedulerProvider);
      // build 47b (Scope B3): schedules ベースに統合。
      // 旧 rescheduleAllReminders は廃止 — schedules.times を持つ
      // medication カテゴリは syncSchedule が拾うので等価。
      await scheduler.rescheduleAllSchedules();
      await scheduler.rescheduleAllVaccinationAlerts();
    } catch (e, st) {
      PetloLogger.instance.w('Failed to reschedule notifications on start',
          error: e, stackTrace: st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeMode themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,

      // === Themes ===
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode.toFlutter(),

      // === L10n ===
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,

      // === ロケール別フォント切替 (rev5.3)
      //   + edge-to-edge 化されたステータスバー / ホームインジケーター領域も
      //     アプリ背景色で塗るための ColoredBox ラップ。
      builder: (BuildContext context, Widget? child) {
        final Color bg = Theme.of(context).scaffoldBackgroundColor;
        return ColoredBox(
          color: bg,
          child: LocaleAwareTheme.applyLocaleAdaptation(
            context: context,
            child: _BootstrapGate(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },

      // === Home: 5タブ構造 (Chunk 14で実装完了) ===
      home: const _RootRouter(),
    );
  }
}

// ============================================================================
// _RootRouter - 起動時にオンボーディング完了状態で分岐
// ============================================================================
//
// onboardingCompleted = true → TabShell (通常画面)
// onboardingCompleted = false → OnboardingFlow (チュートリアル)
//
// 完了後は OnboardingFlow 内で Navigator.pushReplacement(TabShell()) するので、
// この Router 自体は再評価されないが、念のため Provider を watch して
// reset 時の挙動にも対応できるようにしている。
//
class _RootRouter extends ConsumerWidget {
  const _RootRouter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool completed = ref.watch(onboardingCompletedProvider);
    return completed ? const TabShell() : const OnboardingFlow();
  }
}

// ============================================================================
// _BootstrapGate (build 55-client)
// ============================================================================
//
// fullPull が走っている間だけ控えめなオーバーレイ(背景バリア + 中央スピナー
// + 文言)を被せる。普段は完全に素通し。
//
// 注意: TabShell 自体は描画させたまま上に被せる(完全な splash 置換に
// しない)。理由は fullPull 完了で各 StreamProvider が自然に更新され
// データが入り始める UX を優先するため。
//
// ============================================================================
class _BootstrapGate extends ConsumerWidget {
  const _BootstrapGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool inProgress = ref.watch(bootstrapStatusProvider);
    if (!inProgress) return child;
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Stack(
      children: <Widget>[
        child,
        Positioned.fill(
          child: ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.92),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const SizedBox(
                    width: 28, height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.bootstrap_restoring,
                    style: const TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 11,
                      letterSpacing: 11 * 0.18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
