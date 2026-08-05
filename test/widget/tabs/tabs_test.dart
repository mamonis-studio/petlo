// ============================================================================
// petlo - Tabs Tests
// ============================================================================

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/presentation/providers/tab_provider.dart';
import 'package:petlo/presentation/screens/tab_shell.dart';
import 'package:petlo/presentation/widgets/tabs/petlo_tab_bar.dart';

import '../../helpers/test_app.dart';

void main() {
  // アプリのプロバイダ群 (scope_providers など) が build 中に
  // PetloLogger.instance を触るため、初期化しないと落ちる。
  setUpAll(initTestLogger);

  // ==========================================================================
  // AppTab labels
  // ==========================================================================
  group('AppTab', () {
    test('all 5 tabs have human-readable labels', () {
      expect(AppTab.home.label, 'Home');
      expect(AppTab.life.label, 'Life');
      expect(AppTab.health.label, 'Health');
      expect(AppTab.plans.label, 'Plans');
      // build 73: 5番目のタブは more から ai に置き換わった。
      expect(AppTab.ai.label, 'AI');
    });

    test('enum order matches IndexedStack expectation', () {
      expect(AppTab.home.index, 0);
      expect(AppTab.life.index, 1);
      expect(AppTab.health.index, 2);
      expect(AppTab.plans.index, 3);
      expect(AppTab.ai.index, 4);
    });
  });

  // ==========================================================================
  // CurrentTabNotifier
  // ==========================================================================
  group('CurrentTabNotifier', () {
    test('default tab is home', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(currentTabProvider), AppTab.home);
    });

    test('select() switches tab', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(currentTabProvider.notifier).select(AppTab.life);
      expect(container.read(currentTabProvider), AppTab.life);

      container.read(currentTabProvider.notifier).select(AppTab.ai);
      expect(container.read(currentTabProvider), AppTab.ai);
    });

    test('select same tab does nothing (no rebuild storm)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      int rebuildCount = 0;
      container.listen<AppTab>(
        currentTabProvider,
        (_, __) => rebuildCount++,
      );

      // 既にhomeなのにhome選択
      container.read(currentTabProvider.notifier).select(AppTab.home);
      expect(rebuildCount, 0);

      // life選択 → 1回rebuild
      container.read(currentTabProvider.notifier).select(AppTab.life);
      expect(rebuildCount, 1);

      // 再びlife選択 → rebuildしない
      container.read(currentTabProvider.notifier).select(AppTab.life);
      expect(rebuildCount, 1);
    });
  });

  // ==========================================================================
  // PetloTabBar widget
  // ==========================================================================
  group('PetloTabBar', () {
    testWidgets('renders all 5 tab labels', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: PetloTabBar(
            currentTab: AppTab.home,
            onTabSelected: (_) {},
          ),
        ),
      );
      expect(find.text('ホーム'), findsOneWidget);
      expect(find.text('あしあと'), findsOneWidget);
      expect(find.text('みまもる'), findsOneWidget);
      expect(find.text('よてい'), findsOneWidget);
      expect(find.text('AI相談'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('triggers onTabSelected on tap',
        (WidgetTester tester) async {
      AppTab? captured;
      await tester.pumpWidget(
        wrapWithApp(
          child: PetloTabBar(
            currentTab: AppTab.home,
            onTabSelected: (AppTab t) => captured = t,
          ),
        ),
      );
      await tester.tap(find.text('みまもる'));
      expect(captured, AppTab.health);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('Semantics announces selection state',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: PetloTabBar(
            currentTab: AppTab.life,
            onTabSelected: (_) {},
          ),
        ),
      );

      // life タブはSemantics.selected=true、それ以外はfalse
      //
      // build 73: SemanticsData.hasFlag(SemanticsFlag.isSelected) は
      // flagsCollection (Tristate) に置き換わった。フラグの表現に依存しない
      // containsSemantics を使う (matchesSemantics と違い部分一致)。
      expect(
        tester.getSemantics(find.text('あしあと')),
        containsSemantics(isSelected: true),
      );
      expect(
        tester.getSemantics(find.text('ホーム')),
        containsSemantics(isSelected: false),
      );
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });
  });

  // ==========================================================================
  // TabShell
  // ==========================================================================
  group('TabShell', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('renders bottom tab bar', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithAppAndDb(db: db, child: const TabShell()),
      );
      await tester.pumpAndSettle();
      // 5タブ全部表示
      //
      // TabShell はタブバーのラベルに加えてホーム画面自身も描画するため、
      // 'ホーム' はタブラベルと画面見出しの2箇所に出る。
      expect(find.text('ホーム'), findsWidgets);
      expect(find.text('あしあと'), findsOneWidget);
      expect(find.text('みまもる'), findsOneWidget);
      expect(find.text('よてい'), findsOneWidget);
      expect(find.text('AI相談'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    }, tags: <String>['needs_codegen']);

    testWidgets('tap switches active tab', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithAppAndDb(db: db, child: const TabShell()),
      );
      await tester.pumpAndSettle();

      // 初期は Home。ブランドバーは 'PETLO'、Home 画面の見出しは § ホーム。
      // (以前は 'petlo' / 'Daily,' というヒーロー文言を見ていたが
      //  どちらも現在のUIには存在しない)
      expect(find.text('PETLO'), findsOneWidget);

      // Life タブをタップ
      await tester.tap(find.text('あしあと'));
      await tester.pumpAndSettle();

      // Life 画面固有の文言。見出しの 'あしあと' はタブラベルとも
      // 一致してしまうので、画面本文で判定する。
      expect(find.textContaining('日々のあしあとが表示されます'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    }, tags: <String>['needs_codegen']);

    testWidgets('IndexedStack preserves Home state when returning',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithAppAndDb(db: db, child: const TabShell()),
      );
      await tester.pumpAndSettle();

      // Home → Health → Home に戻ってもHomeのヒーローが見える
      await tester.tap(find.text('みまもる'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ホーム').last);
      await tester.pumpAndSettle();

      // Home 画面固有の文言で判定する。
      // 'petlo' というタイトルは現在のUIには存在しない。
      expect(find.textContaining('うちの子から'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    }, tags: <String>['needs_codegen']);
  });
}
