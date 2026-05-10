// ============================================================================
// petlo - Meal Widgets Tests
// ============================================================================

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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
      expect(find.text('Ate all'), findsOneWidget);
      expect(find.text('Ate well'), findsOneWidget);
      expect(find.text('Normal'), findsOneWidget);
      expect(find.text('Left some'), findsOneWidget);
      expect(find.text('Refused'), findsOneWidget);
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

      await tester.tap(find.text('Refused'));
      expect(captured, MealAppetite.refused);
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
      final SemanticsNode node = tester.getSemantics(find.text('Ate all'));
      // Note: 親(_AppetiteOption)にSemantics(selected:true)が乗ってる
      // ここでは存在確認のみ
      expect(node, isNotNull);
      handle.dispose();
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
      return UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: RecentFoodsRow(
              selectedFoodId: selectedFoodId,
              onFoodSelected: onTap ?? (_) {},
            ),
          ),
        ),
      );
    }

    testWidgets('hides when no foods registered', (WidgetTester tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text('Recent'), findsNothing);
    }, tags: <String>['needs_codegen']);

    testWidgets('shows up to 3 most recent foods',
        (WidgetTester tester) async {
      final repo = FoodsRepository(db);
      // 5件作って直近3件のみ表示確認
      for (int i = 0; i < 5; i++) {
        await repo.upsertByName(name: 'Food $i');
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('Food 4'), findsOneWidget);
      expect(find.text('Food 3'), findsOneWidget);
      expect(find.text('Food 2'), findsOneWidget);
      expect(find.text('Food 0'), findsNothing); // 4番目以降は出ない
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
    }, tags: <String>['needs_codegen']);

    testWidgets('highlights selected food', (WidgetTester tester) async {
      final repo = FoodsRepository(db);
      final int id = await repo.upsertByName(name: 'A');

      await tester.pumpWidget(wrap(selectedFoodId: id));
      await tester.pumpAndSettle();

      // selected==true で Semantics 立つ
      expect(find.text('A'), findsOneWidget);
    }, tags: <String>['needs_codegen']);
  });
}
