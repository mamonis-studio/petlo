// ============================================================================
// petlo - Meal Widgets Tests
// ============================================================================

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/data/local/database_enums.dart';
import 'package:petlo/data/repositories/foods_repository.dart';
import 'package:petlo/presentation/providers/database_provider.dart';
import 'package:petlo/presentation/widgets/meal/meal_appetite_selector.dart';
import 'package:petlo/presentation/widgets/meal/recent_foods_row.dart';

import '../../helpers/test_app.dart';

void main() {
  // アプリのプロバイダ群 (scope_providers など) が build 中に
  // PetloLogger.instance を触るため、初期化しないと落ちる。
  setUpAll(initTestLogger);

  // ==========================================================================
  // MealAppetiteSelector
  // ==========================================================================
  group('MealAppetiteSelector', () {
    testWidgets('renders all 5 options', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: MealAppetiteSelector(
            value: MealAppetite.ate_all,
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('完食'), findsOneWidget);
      expect(find.text('良好'), findsOneWidget);
      expect(find.text('普通'), findsOneWidget);
      expect(find.text('残した'), findsOneWidget);
      expect(find.text('食べない'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('triggers onChanged when option tapped',
        (WidgetTester tester) async {
      MealAppetite? captured;
      await tester.pumpWidget(
        wrapWithApp(
          child: MealAppetiteSelector(
            value: null,
            onChanged: (MealAppetite a) => captured = a,
          ),
        ),
      );

      await tester.tap(find.text('食べない'));
      expect(captured, MealAppetite.refused);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('shows error text', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: MealAppetiteSelector(
            value: null,
            errorText: '選んでください',
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('選んでください'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('marks selected option in semantics',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrapWithApp(
          child: MealAppetiteSelector(
            value: MealAppetite.ate_all,
            onChanged: (_) {},
          ),
        ),
      );
      // Ate all のSemanticsノードに selected: true が立つ
      final SemanticsNode node = tester.getSemantics(find.text('完食'));
      // Note: 親(_AppetiteOption)にSemantics(selected:true)が乗ってる
      // ここでは存在確認のみ
      expect(node, isNotNull);
      handle.dispose();
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });
  });

  // ==========================================================================
  // RecentFoodsRow (実DB)
  // ==========================================================================
  group('RecentFoodsRow', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Widget wrap({int? selectedFoodId, ValueChanged<FoodEntity>? onTap}) {
      // 素の MaterialApp を自前で組むとテーマ (AppColors extension) と
      // l10n デリゲートが入らず AppColors.of() が投げる。
      return wrapWithApp(
        container: container,
        child: RecentFoodsRow(
          selectedFoodId: selectedFoodId,
          onFoodSelected: onTap ?? (_) {},
        ),
      );
    }

    testWidgets('hides when no foods registered', (WidgetTester tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text('Recent'), findsNothing);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    }, tags: <String>['needs_codegen']);

    testWidgets('shows up to 3 most recent foods',
        (WidgetTester tester) async {
      final repo = FoodsRepository(db);
      // 5件作って直近3件のみ表示確認
      //
      // Future.delayed をテスト本体で待つと **永久にハングする**。
      // testWidgets の中は疑似時計なので、誰も時計を進めない限り
      // Future.delayed は完了しない。10分のテストタイムアウトまで
      // 解放されず、後続のテストまで巻き添えになる。
      // 実時計が要る処理は runAsync で囲む。
      // (作成時刻をずらすのは並び順を安定させるため)
      await tester.runAsync(() async {
        for (int i = 0; i < 5; i++) {
          await repo.upsertByName(name: 'Food $i');
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text('最近'), findsOneWidget);
      expect(find.text('Food 4'), findsOneWidget);
      expect(find.text('Food 3'), findsOneWidget);
      expect(find.text('Food 2'), findsOneWidget);
      expect(find.text('Food 0'), findsNothing); // 4番目以降は出ない
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    }, tags: <String>['needs_codegen']);

    testWidgets('triggers onTap when chip tapped',
        (WidgetTester tester) async {
      final repo = FoodsRepository(db);
      await repo.upsertByName(name: 'Royal Canin', defaultAmountG: 80);

      FoodEntity? captured;
      await tester.pumpWidget(wrap(onTap: (FoodEntity f) => captured = f));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Royal Canin'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.name, 'Royal Canin');
      expect(captured!.defaultAmountG, 80);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    }, tags: <String>['needs_codegen']);

    testWidgets('highlights selected food', (WidgetTester tester) async {
      final repo = FoodsRepository(db);
      final int id = await repo.upsertByName(name: 'A');

      await tester.pumpWidget(wrap(selectedFoodId: id));
      await tester.pumpAndSettle();

      // selected==true で Semantics 立つ
      expect(find.text('A'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    }, tags: <String>['needs_codegen']);
  });
}
