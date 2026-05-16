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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/auth_service.dart';
import 'core/auth/user_profile_service.dart';
import 'core/billing/purchase_service.dart';
import 'core/constants/app_constants.dart';
import 'core/notifications/notification_service.dart';
import 'core/preferences/user_preferences.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/locale_aware_theme.dart';
import 'core/utils/logger.dart';
import 'l10n/generated/app_localizations.dart';
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

class _PetloAppState extends ConsumerState<PetloApp> {
  @override
  void initState() {
    super.initState();
    // 起動時に通知を再スケジュール (端末再起動・アプリkill対応)
    // fire-and-forget — UI起動を遅延させない
    Future<void>.microtask(_rescheduleNotifications);
    // IAP 購入リスナーを起動 (購入成功時に ProStatusProvider を更新)
    ref.read(purchaseListenerProvider).start();
  }

  Future<void> _rescheduleNotifications() async {
    try {
      final scheduler = ref.read(notificationSchedulerProvider);
      await scheduler.rescheduleAllReminders();
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
            child: child ?? const SizedBox.shrink(),
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
