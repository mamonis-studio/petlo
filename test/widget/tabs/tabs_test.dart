// ============================================================================
// petlo - Tabs Tests
// ============================================================================

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/presentation/providers/tab_provider.dart';
import 'package:petlo/presentation/screens/tab_shell.dart';
import 'package:petlo/presentation/widgets/tabs/petlo_tab_bar.dart';

import '../../helpers/test_app.dart';

void main() {
  // ==========================================================================
  // AppTab labels
  // ==========================================================================
  group('AppTab', () {
    test('all 5 tabs have human-readable labels', () {
      expect(AppTab.home.label, 'Home');
      expect(AppTab.life.label, 'Life');
      expect(AppTab.health.label, 'Health');
      expect(AppTab.plans.label, 'Plans');
      expect(AppTab.more.label, 'More');
    });

    test('enum order matches IndexedStack expectation', () {
      expect(AppTab.home.index, 0);
      expect(AppTab.life.index, 1);
      expect(AppTab.health.index, 2);
      expect(AppTab.plans.index, 3);
      expect(AppTab.more.index, 4);
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

      container.read(currentTabProvider.notifier).select(AppTab.more);
      expect(container.read(currentTabProvider), AppTab.more);
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
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('LIFE'), findsOneWidget);
      expect(find.text('HEALTH'), findsOneWidget);
      expect(find.text('PLANS'), findsOneWidget);
      expect(find.text('MORE'), findsOneWidget);
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
      await tester.tap(find.text('HEALTH'));
      expect(captured, AppTab.health);
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
      final SemanticsNode lifeNode = tester.getSemantics(find.text('LIFE'));
      expect(
        lifeNode.getSemanticsData().hasFlag(SemanticsFlag.isSelected),
        isTrue,
      );

      final SemanticsNode homeNode = tester.getSemantics(find.text('HOME'));
      expect(
        homeNode.getSemanticsData().hasFlag(SemanticsFlag.isSelected),
        isFalse,
      );
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
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('LIFE'), findsOneWidget);
      expect(find.text('HEALTH'), findsOneWidget);
      expect(find.text('PLANS'), findsOneWidget);
      expect(find.text('MORE'), findsOneWidget);
    }, tags: <String>['needs_codegen']);

    testWidgets('tap switches active tab', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithAppAndDb(db: db, child: const TabShell()),
      );
      await tester.pumpAndSettle();

      // 初期: Home(petlo タイトル表示)
      expect(find.text('petlo'), findsOneWidget);

      // Life タブをタップ
      await tester.tap(find.text('LIFE'));
      await tester.pumpAndSettle();

      // Life画面のヒーロー文言を確認
      expect(find.textContaining('Daily,'), findsOneWidget);
    }, tags: <String>['needs_codegen']);

    testWidgets('IndexedStack preserves Home state when returning',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithAppAndDb(db: db, child: const TabShell()),
      );
      await tester.pumpAndSettle();

      // Home → Health → Home に戻ってもHomeのヒーローが見える
      await tester.tap(find.text('HEALTH'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HOME'));
      await tester.pumpAndSettle();

      expect(find.text('petlo'), findsOneWidget);
    }, tags: <String>['needs_codegen']);
  });
}
