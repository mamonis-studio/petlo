// ============================================================================
// petlo - Test Helpers
// ============================================================================
//
// 全テストで使う共通ヘルパー関数。
// Widget テスト、Unit テスト両方で利用。
//
// ============================================================================

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/core/theme/app_theme.dart';
import 'package:petlo/core/utils/logger.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/l10n/generated/app_localizations.dart';
import 'package:petlo/presentation/providers/database_provider.dart';

// ============================================================================
// テスト環境の既定ロケール
// ============================================================================
//
// wrapWithApp は以前 locale を渡さないと MaterialApp が
// **プラットフォームのロケール** を採用していた。flutter_test の既定は
// en_US なので、テストは黙って英語で描画されていた。
//
// このため `expect(find.text('2 個まで'), ...)` のような
// 日本語リテラルのアサーションは "Up to 2" と突き合わされて落ちる。
// しかもテストごとの locale 指定漏れなので、書いた本人には
// 「なぜかこのテストだけ落ちる」としか見えない。
//
// 既定を ja に固定して、この種の取りこぼしを構造的に潰す。
// en / zh を検証したいテストは locale を明示的に渡す。
//
// 「環境が決める」のではなく「こちらが決める」形にするのが要点。
// ============================================================================
const Locale kTestDefaultLocale = Locale('ja');

/// drift のクエリストリームを使うウィジェットを検証したテストの末尾で呼ぶ。
///
/// drift は最後のリスナーが外れてもクエリストリームをしばらく生かしておく
/// ためにタイマーを張る。ウィジェットツリーを破棄しただけではそのタイマーが
/// 残り、テスト本体が全部成功していても
/// `A Timer is still pending even after the widget tree was disposed.`
/// で落ちる。
///
/// さらに厄介なことに、この状態のテストは 10 分のテストタイムアウトまで
/// 解放されず、**次のテストまで `!inTest` で巻き添えにする**。
/// 「関係ないテストが2件落ちている」ようにしか見えないので原因が追いにくい。
///
/// ツリーを外してから疑似時計を進め、タイマーを消化させる。
///
/// 注意: `await db.close()` をテスト本体で待つ形にしてはいけない。
/// テストバインディングの疑似時計では完了せずデッドロックする
/// (`tester.runAsync` 経由でも同じ)。DB の後始末は addTearDown に任せる。
Future<void> disposeTreeAndDrainTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 5));
}

/// テストから AppLocalizations を直接得る。
///
/// フォームの `validate()` はエラーメッセージを多言語化した際に
/// `validate(AppLocalizations l10n)` へ変わった。State 単体のテストは
/// ウィジェットツリーを組まないので `AppLocalizations.of(context)` が
/// 使えず、デリゲートから直接ロードする。
///
/// 既定は [kTestDefaultLocale] (ja)。ウィジェット側の描画ロケールと
/// 揃えておかないと、同じ文言でも突き合わせが食い違う。
Future<AppLocalizations> loadTestL10n([
  Locale locale = kTestDefaultLocale,
]) =>
    AppLocalizations.delegate.load(locale);

/// PetloLogger を初期化する。
///
/// scope_providers / pet_edit_hint_provider などが build 中に
/// PetloLogger.instance を触るため、初期化せずにウィジェットツリーを
/// 組むと `Bad state: PetloLogger.initialize() must be called` で落ちる。
///
/// 冪等なので setUp から毎回呼んでよい。
Future<void> initTestLogger() => PetloLogger.initialize();

/// Widget テストで `MaterialApp` を含んだルートを生成するヘルパー。
///
/// 使い方:
/// ```dart
/// await tester.pumpWidget(
///   wrapWithApp(
///     child: MyWidget(),
///     overrides: [...],
///   ),
/// );
/// ```
Widget wrapWithApp({
  required Widget child,
  List<Override> overrides = const <Override>[],
  Locale locale = kTestDefaultLocale,
  ThemeMode themeMode = ThemeMode.light,
  ProviderContainer? container,
}) {
  final Widget app = MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
  );
  // container を渡された場合は既存のコンテナをそのまま使う。
  // テスト側で先に状態を仕込んでから pump したいケース用。
  // 素の MaterialApp を自前で組むとテーマ (AppColors extension) と
  // l10n デリゲートが入らず、AppColors.of() が投げる。
  if (container != null) {
    return UncontrolledProviderScope(container: container, child: app);
  }
  return ProviderScope(overrides: overrides, child: app);
}

/// AppDatabase をインメモリで提供するProviderScopeを返す。
/// PetloScaffoldなど DB に依存するUIをテストする時に使う。
///
/// 使い方:
/// ```dart
/// final db = AppDatabase.forTesting(NativeDatabase.memory());
/// addTearDown(db.close);
///
/// await tester.pumpWidget(
///   wrapWithAppAndDb(child: ..., db: db),
/// );
/// ```
Widget wrapWithAppAndDb({
  required Widget child,
  required AppDatabase db,
  List<Override> additionalOverrides = const <Override>[],
  Locale locale = kTestDefaultLocale,
  ThemeMode themeMode = ThemeMode.light,
}) {
  return wrapWithApp(
    child: child,
    locale: locale,
    themeMode: themeMode,
    overrides: <Override>[
      appDatabaseProvider.overrideWithValue(db),
      ...additionalOverrides,
    ],
  );
}

/// インメモリ AppDatabase を作成する便利関数。
/// テストの setUp / tearDown と組み合わせて使う。
AppDatabase createInMemoryDb() {
  return AppDatabase.forTesting(NativeDatabase.memory());
}

/// テスト用の小さな待機ヘルパー。
/// `await tester.pumpAndSettle()` の前に短い `pump` が必要なケースで使用。
Future<void> pumpForFrames(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}
