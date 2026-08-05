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
import 'package:intl/date_symbol_data_local.dart';

import 'core/auth/auth_service.dart';
import 'core/auth/user_profile_service.dart';
import 'core/backup/backup_scheduler.dart';
import 'core/billing/purchase_service.dart';
import 'core/constants/app_constants.dart';
import 'core/notifications/notification_service.dart';
import 'core/preferences/user_preferences.dart';
import 'core/sync/sync_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/locale_aware_theme.dart';
import 'core/utils/logger.dart';
import 'core/utils/startup_trace.dart';
import 'l10n/generated/app_localizations.dart';
import 'presentation/providers/bootstrap_provider.dart';
import 'presentation/providers/database_provider.dart';
import 'presentation/providers/group_api_service_provider.dart';
import 'presentation/providers/notification_coordinator_provider.dart';
import 'presentation/providers/notification_scheduler_provider.dart';
import 'presentation/providers/onboarding_completed_provider.dart';
import 'presentation/providers/pro_status_provider.dart';
import 'presentation/providers/purchase_provider.dart';
import 'presentation/providers/theme_mode_provider.dart';
import 'presentation/screens/onboarding/onboarding_flow.dart';
import 'presentation/screens/tab_shell.dart';

Future<void> main() async {
  // build 73: 起動シーケンスの計測を開始する。
  // 結果は UserPreferences に永続化し、開発者設定から読む
  // (ログは debug でしか出ず、この端末では debug が起動できないため)。
  StartupTrace.begin();
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
  await StartupTrace.measure('PetloLogger.initialize', PetloLogger.initialize);
  PetloLogger.instance
      .i('petlo starting up... version=${AppConstants.appVersion}');

  // === 日付フォーマットのロケールデータ初期化 ===
  // build 73: 通知の文言組み立ては Widget ツリーの外 (NotificationCoordinator)
  // で走るため、GlobalMaterialLocalizations による暗黙の初期化に頼れない。
  // 未初期化だと DateFormat が LocaleDataException を投げ、通知の再割り当てが
  // 丸ごと失敗する。
  StartupTrace.measureSync('initializeDateFormatting', initializeDateFormatting);

  // === ユーザー設定の初期化(テーマ等) ===
  await StartupTrace.measure(
      'UserPreferences.initialize', UserPreferences.instance.initialize);

  // === 通知初期化 ===
  await StartupTrace.measure(
      'NotificationService.initialize', NotificationService.instance.initialize);

  // === IAP 初期化 (失敗してもアプリは起動する) ===
  await StartupTrace.measure(
      'PurchaseService.initialize', PurchaseService.instance.initialize);

  // === API 認証初期化 (初回 /auth/anonymous + secure_storage 同期、
  //     ネットワーク不通でも起動継続)
  try {
    await StartupTrace.measure(
        'AuthService.initialize', AuthService.instance.initialize);
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
    // build 73: 初回フレーム描画までの時間を記録する
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(StartupTrace.markFirstFrame());
    });
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
        // build 68: 自動クラウドバックアップ。Pro + Apple 連携 + オンライン +
        // 24h 経過の全条件を満たした時だけ送信。失敗は静かにログのみ。
        unawaited(BackupScheduler.maybeRunCloudBackup(ref));
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
      // サーバから自分の全グループを取得 + 各 group を since=0 で pull する。
      //
      // build 73: 判定を「groups テーブルが空か」から専用フラグへ変更した。
      // groups は **家族共有グループの一覧** であり、共有機能を使っていない
      // ユーザーでは常に空。匿名認証も必ず成功するため、旧条件
      // (groups.isEmpty && isAuthenticated) は毎回成立し、通常起動のたびに
      // fullPull とオーバーレイが走っていた。
      final bool needFullPull = !UserPreferences.instance.didInitialFullPull &&
          AuthService.instance.isAuthenticated;
      if (needFullPull) {
        ref.read(bootstrapStatusProvider.notifier).begin();
        try {
          PetloLogger.instance.i(
            '[bootstrap] initial fullPull not done yet → fullPull',
          );
          final bool ok = await SyncService.instance
              .fullPull(ref.read(groupApiServiceProvider));
          // 成功したときだけフラグを立てる。
          // 圏外・タイムアウトで失敗した場合は落としたままにして、
          // 次回起動でリトライさせる。
          if (ok) {
            await UserPreferences.instance.setDidInitialFullPull(true);
          }
        } catch (e, st) {
          PetloLogger.instance.w(
            '[bootstrap] fullPull failed (will retry next launch)',
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
      // build 73: 旧採番の残骸を一度だけ掃除する (DB には触らない)。
      // 採番を変えた分は新採番の cancelRange では消しきれないため。
      final Stopwatch migSw = Stopwatch()..start();
      await scheduler.migrateLegacyScheduleNotificationIds();
      await scheduler.migrateLegacyVaccinationNotificationIds();
      migSw.stop();
      await StartupTrace.addAfterFirstFrame(
          'migrateLegacyIds', migSw.elapsedMilliseconds);

      // build 73: 3 系統の合計を見て 64 枠に収める。
      // 起動のたびに無条件で走らせることが、再割り当ての途中で落ちた場合の
      // 回復経路になっている (DB が真実、OS 側の通知は導出物)。
      final Stopwatch reSw = Stopwatch()..start();
      await ref
          .read(notificationCoordinatorProvider)
          .rescheduleAll(isPro: ref.read(isProProvider));
      reSw.stop();
      await StartupTrace.addAfterFirstFrame(
          'rescheduleAll', reSw.elapsedMilliseconds);
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
    final ThemeData theme = Theme.of(context);
    return Stack(
      children: <Widget>[
        child,
        // build 73: Material で包む。
        //
        // このオーバーレイは MaterialApp.builder の位置、つまり Navigator の
        // **外側** に置かれている。そこには Material も DefaultTextStyle も
        // 無いため、素の Text が「赤文字 + 黄色の二重下線」(Flutter が
        // 未設定のテキストに出す debug 表示) になっていた。
        // 文字色を指定しても下線は消えない。Material 祖先を与えるのが正解。
        //
        // type: transparency にして Material 自身は何も描かせず、背景色は
        // 従来どおり ColoredBox が担当する (見た目を変えないため)。
        Positioned.fill(
          child: Material(
            type: MaterialType.transparency,
            child: ColoredBox(
              color: theme.scaffoldBackgroundColor.withOpacity(0.92),
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
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 11,
                        letterSpacing: 11 * 0.18,
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
