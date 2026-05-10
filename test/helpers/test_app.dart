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
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/l10n/generated/app_localizations.dart';
import 'package:petlo/presentation/providers/database_provider.dart';

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
  Locale? locale,
  ThemeMode themeMode = ThemeMode.light,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
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
  Locale? locale,
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
