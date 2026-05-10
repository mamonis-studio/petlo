// ============================================================================
// petlo - Pet Selector Widget Tests
// ============================================================================
//
// PetSelectorPill (純UI) と PetSelectorBar (Provider絡み) の両方をテスト。
// PetSelectorPill は build_runner なしでも動く (純UI)。
// PetSelectorBar は実DBを使うので needs_codegen タグ。
//
// ============================================================================

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/data/local/database_enums.dart';
import 'package:petlo/data/repositories/pets_repository.dart';
import 'package:petlo/presentation/providers/database_provider.dart';
import 'package:petlo/presentation/providers/pets_providers.dart';
import 'package:petlo/presentation/providers/scope_providers.dart';
import 'package:petlo/presentation/widgets/pet_selector/pet_selector_bar.dart';
import 'package:petlo/presentation/widgets/pet_selector/pet_selector_pill.dart';

import '../helpers/test_app.dart';

// ============================================================================
// PetSelectorPill (Pure UI tests)
// ============================================================================

void main() {
  group('PetSelectorPill.pet', () {
    testWidgets('renders name and meta', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: PetSelectorPill.pet(
            name: 'Taro',
            petType: PetType.dog,
            breedDisplay: 'shiba',
            petAgeYears: 4,
            isActive: true,
            onTap: () {},
          ),
        ),
      );

      expect(find.text('Taro'), findsOneWidget);
      expect(find.text('shiba · 4Y'), findsOneWidget);
    });

    testWidgets('triggers onTap', (WidgetTester tester) async {
      var taps = 0;
      await tester.pumpWidget(
        wrapWithApp(
          child: PetSelectorPill.pet(
            name: 'Mike',
            petType: PetType.cat,
            breedDisplay: 'mix',
            petAgeYears: 6,
            isActive: false,
            onTap: () => taps++,
          ),
        ),
      );

      await tester.tap(find.text('Mike'));
      expect(taps, 1);
    });

    testWidgets('semantics include selected state',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrapWithApp(
          child: PetSelectorPill.pet(
            name: 'Hana',
            petType: PetType.cat,
            breedDisplay: 'persian',
            petAgeYears: 3,
            isActive: true,
            onTap: () {},
          ),
        ),
      );

      // selected フラグが立ったSemanticsノードがあるはず
      expect(
        tester.getSemantics(find.byType(PetSelectorPill)),
        matchesSemantics(
          isSelected: true,
          isButton: true,
          hasTapAction: true,
          label: contains('Hana'),
        ),
      );
      handle.dispose();
    });
  });

  group('PetSelectorPill.allPets', () {
    testWidgets('renders "All pets" label and pet count',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: PetSelectorPill.allPets(
            petCount: 3,
            isActive: false,
            onTap: () {},
          ),
        ),
      );
      expect(find.text('All pets'), findsOneWidget);
      expect(find.text('3 pets'), findsOneWidget);
    });
  });

  group('PetSelectorPill.add', () {
    testWidgets('renders + and Add', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: PetSelectorPill.add(onTap: () {}),
        ),
      );
      expect(find.text('+'), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);
    });
  });

  // ==========================================================================
  // PetSelectorBar (実DB必要)
  // ==========================================================================
  group('PetSelectorBar (with DB)', () {
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

    Widget wrap({bool showAllPets = true, VoidCallback? onAdd}) {
      return UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: PetSelectorBar(
              showAllPets: showAllPets,
              onAddPetTapped: onAdd,
            ),
          ),
        ),
      );
    }

    testWidgets('shows empty state when no pets', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(onAdd: () {}));
      await tester.pumpAndSettle();

      // ペット0匹なら「No pets in this group yet」 or 「+」 ピル(canEdit=true)が出る
      // PersonalスコープはownerなのでcanEditはtrue → "+"が出る
      expect(find.text('+'), findsOneWidget);
    }, tags: <String>['needs_codegen']);

    testWidgets('shows pets when available', (WidgetTester tester) async {
      // ペット2匹追加
      final PetsRepository repo = PetsRepository(db);
      await repo.createPet(
        groupId: 'personal',
        name: 'Taro',
        type: PetType.dog,
        breed: 'shiba',
        sex: PetSex.male,
      );
      await repo.createPet(
        groupId: 'personal',
        name: 'Mike',
        type: PetType.cat,
        breed: 'mix',
        sex: PetSex.male,
      );

      await tester.pumpWidget(wrap(showAllPets: true));
      await tester.pumpAndSettle();

      expect(find.text('Taro'), findsOneWidget);
      expect(find.text('Mike'), findsOneWidget);
      // 2匹以上なので "All pets" ピル表示
      expect(find.text('All pets'), findsOneWidget);
    }, tags: <String>['needs_codegen']);

    testWidgets('hides All pets pill when only 1 pet',
        (WidgetTester tester) async {
      final PetsRepository repo = PetsRepository(db);
      await repo.createPet(
        groupId: 'personal',
        name: 'Solo',
        type: PetType.dog,
        breed: 'b',
        sex: PetSex.male,
      );

      await tester.pumpWidget(wrap(showAllPets: true));
      await tester.pumpAndSettle();

      expect(find.text('Solo'), findsOneWidget);
      expect(find.text('All pets'), findsNothing);
    }, tags: <String>['needs_codegen']);

    testWidgets('hides Add pill when canEdit is false (Viewer)',
        (WidgetTester tester) async {
      // Viewerシミュレート: 共有グループ + role=viewer
      await container
          .read(currentGroupIdProvider.notifier)
          .switchTo('group-x');
      container
          .read(currentRoleProvider.notifier)
          .update(MemberPermission.viewer);

      // ペット1匹追加(別スコープなのでgroup-xに作る)
      final PetsRepository repo = PetsRepository(db);
      await repo.createPet(
        groupId: 'group-x',
        name: 'Taro',
        type: PetType.dog,
        breed: 'b',
        sex: PetSex.male,
      );

      await tester.pumpWidget(wrap(onAdd: () {}));
      await tester.pumpAndSettle();

      expect(find.text('Taro'), findsOneWidget);
      expect(find.text('+'), findsNothing); // Viewerには表示されない
    }, tags: <String>['needs_codegen']);
  });
}
