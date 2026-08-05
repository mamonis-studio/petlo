// ============================================================================
// petlo - Meal Form Tests
// ============================================================================

// Value を使うため。native.dart だけでは Value が入ってこない。
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:petlo/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/data/local/database_enums.dart';
import 'package:petlo/data/repositories/foods_repository.dart';
import 'package:petlo/data/repositories/meals_repository.dart';
import 'package:petlo/presentation/providers/database_provider.dart';
import 'package:petlo/presentation/providers/scope_providers.dart';
import 'package:petlo/presentation/screens/meal/meal_form_controller.dart';
import 'package:petlo/presentation/screens/meal/meal_form_state.dart';
import 'package:petlo/presentation/screens/meal/meal_record_screen.dart';

import '../../../helpers/test_app.dart';

void main() {
  // validate() が AppLocalizations を取るようになったため、
  // State 単体のテストでもロケールを用意する。
  late AppLocalizations l10n;
  setUpAll(() async {
    await initTestLogger();
    l10n = await loadTestL10n();
  });

  // ==========================================================================
  // MealFormState (Pure DTO)
  // ==========================================================================
  group('MealFormState', () {
    test('default state has no food selected', () {
      const MealFormState s = MealFormState();
      expect(s.hasFoodSelected, isFalse);
      expect(s.isEditing, isFalse);
    });

    test('hasFoodSelected when foodId is set', () {
      const MealFormState s = MealFormState(foodId: 1);
      expect(s.hasFoodSelected, isTrue);
    });

    test('hasFoodSelected when freeText is non-empty', () {
      const MealFormState s = MealFormState(foodNameFreeText: 'A');
      expect(s.hasFoodSelected, isTrue);
    });

    test('hasFoodSelected false when freeText is whitespace only', () {
      const MealFormState s = MealFormState(foodNameFreeText: '   ');
      expect(s.hasFoodSelected, isFalse);
    });

    group('validate', () {
      test('rejects when no food info', () {
        const MealFormState s = MealFormState();
        expect(s.validate(l10n).errors.foodName, isNotNull);
      });

      test('rejects negative amount', () {
        const MealFormState s = MealFormState(
          foodNameFreeText: 'A',
          amountG: -10,
          appetite: MealAppetite.ate_all,
        );
        expect(s.validate(l10n).errors.amountG, isNotNull);
      });

      test('rejects too-large amount', () {
        const MealFormState s = MealFormState(
          foodNameFreeText: 'A',
          amountG: 99999,
          appetite: MealAppetite.ate_all,
        );
        expect(s.validate(l10n).errors.amountG, isNotNull);
      });

      test('rejects null appetite', () {
        const MealFormState s = MealFormState(foodNameFreeText: 'A');
        expect(s.validate(l10n).errors.appetite, isNotNull);
      });

      test('rejects future eatenAt', () {
        final MealFormState s = MealFormState(
          foodNameFreeText: 'A',
          appetite: MealAppetite.ate_all,
          eatenAt: DateTime.now().add(const Duration(hours: 2)),
        );
        expect(s.validate(l10n).errors.eatenAt, isNotNull);
      });

      test('valid full state has no errors', () {
        final MealFormState s = MealFormState(
          foodNameFreeText: 'Royal Canin',
          amountG: 80,
          appetite: MealAppetite.ate_all,
          eatenAt: DateTime.now().subtract(const Duration(minutes: 1)),
        );
        expect(s.validate(l10n).errors.hasAny, isFalse);
      });
    });
  });

  // ==========================================================================
  // MealFormController (with DB)
  // ==========================================================================
  group('MealFormController', () {
    late AppDatabase db;
    late ProviderContainer container;

    Future<int> createPet(AppDatabase db) async {
      final t = DateTime.now().millisecondsSinceEpoch;
      // pets テーブルにcreatePetでなく直接insert (テスト簡略化)
      // 実コードと同じ経路を通したい場合は PetsRepository.createPet 使う
      return db.into(db.pets).insert(
            PetsCompanion.insert(
              groupId: const Value('personal'),
              name: 'Taro',
              type: PetType.dog,
              breed: const Value('shiba'),
              sex: const Value(PetSex.male),
              createdAt: t,
              updatedAt: t,
            ),
          );
    }

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

    test('initial state takes petId from currentPetIdProvider', () async {
      final int petId = await createPet(db);
      await container.read(currentPetIdProvider.notifier).selectPet(petId);

      final state = container.read(mealFormControllerProvider(null));
      expect(state.petId, petId);
      expect(state.eatenAt, isNotNull); // 現在時刻で初期化
    }, tags: <String>['needs_codegen']);

    test('save creates meal and registers food in master', () async {
      final int petId = await createPet(db);
      await container.read(currentPetIdProvider.notifier).selectPet(petId);

      final ctrl = container.read(mealFormControllerProvider(null).notifier);
      ctrl
        ..updateFoodNameFreeText('NewFood')
        ..updateAmountG(80)
        ..updateAppetite(MealAppetite.ate_all);

      final r = await ctrl.save(l10n);
      expect(r, MealFormSaveOutcome.success);

      // foodsマスタに登録される
      final foodsRepo = FoodsRepository(db);
      final FoodEntity? f = await foodsRepo.findByExactName('NewFood');
      expect(f, isNotNull);
      expect(f!.useCount, 1);

      // mealsに記録される
      final mealsRepo = MealsRepository(db);
      final List<MealEntity> meals =
          await mealsRepo.watchMealsForPet(petId).first;
      expect(meals.length, 1);
      expect(meals.first.foodId, f.id); // foodIdに統一されている
      expect(meals.first.amountG, 80);
    }, tags: <String>['needs_codegen']);

    test('save with existing food increments useCount', () async {
      final int petId = await createPet(db);
      await container.read(currentPetIdProvider.notifier).selectPet(petId);

      // 既存銘柄を1つ作る
      final foodsRepo = FoodsRepository(db);
      final int foodId = await foodsRepo.upsertByName(name: 'Existing');
      // useCount 1 になっている

      // 直近銘柄チップから選んだシナリオ
      final ctrl = container.read(mealFormControllerProvider(null).notifier);
      final FoodEntity? food = await foodsRepo.getById(foodId);
      ctrl.selectExistingFood(food!);
      ctrl.updateAppetite(MealAppetite.ate_normal);

      await ctrl.save(l10n);

      final FoodEntity? after = await foodsRepo.getById(foodId);
      expect(after!.useCount, 2); // 1 → 2
    }, tags: <String>['needs_codegen']);

    test('validate failure does not create meal', () async {
      final int petId = await createPet(db);
      await container.read(currentPetIdProvider.notifier).selectPet(petId);

      final ctrl = container.read(mealFormControllerProvider(null).notifier);
      // 何も入れずsave
      final r = await ctrl.save(l10n);
      expect(r, MealFormSaveOutcome.validationFailed);

      final mealsRepo = MealsRepository(db);
      final List<MealEntity> meals =
          await mealsRepo.watchMealsForPet(petId).first;
      expect(meals, isEmpty);
    }, tags: <String>['needs_codegen']);

    test('selectExistingFood sets foodId and copies defaultAmountG', () async {
      final int petId = await createPet(db);
      await container.read(currentPetIdProvider.notifier).selectPet(petId);

      final foodsRepo = FoodsRepository(db);
      final int foodId = await foodsRepo.upsertByName(
        name: 'Royal',
        defaultAmountG: 100,
      );
      final FoodEntity? food = await foodsRepo.getById(foodId);

      final ctrl = container.read(mealFormControllerProvider(null).notifier);
      ctrl.selectExistingFood(food!);

      final state = container.read(mealFormControllerProvider(null));
      expect(state.foodId, foodId);
      expect(state.foodNameFreeText, 'Royal');
      expect(state.amountG, 100);
    }, tags: <String>['needs_codegen']);

    test('editing existing meal loads data', () async {
      final int petId = await createPet(db);
      final mealsRepo = MealsRepository(db);
      final int mealId = await mealsRepo.createMeal(
        groupId: 'personal',
        petId: petId,
        foodNameFreeText: 'X',
        appetite: MealAppetite.ate_well,
        eatenAtMsec: DateTime.now().millisecondsSinceEpoch,
        amountG: 60,
      );

      // build()トリガー
      container.read(mealFormControllerProvider(mealId));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(mealFormControllerProvider(mealId));
      expect(state.foodNameFreeText, 'X');
      expect(state.amountG, 60);
      expect(state.appetite, MealAppetite.ate_well);
    }, tags: <String>['needs_codegen']);
  });

  // ==========================================================================
  // MealRecordScreen Widget tests
  // ==========================================================================
  group('MealRecordScreen', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('shows NEW MEAL header for new entry',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithAppAndDb(
          db: db,
          child: const MealRecordScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('新しい食事'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    }, tags: <String>['needs_codegen']);

    testWidgets('CANCEL pops with false', (WidgetTester tester) async {
      bool? popResult;
      await tester.pumpWidget(
        wrapWithAppAndDb(
          db: db,
          child: Builder(
            builder: (BuildContext context) => Center(
              child: TextButton(
                onPressed: () async {
                  popResult = await MealRecordScreen.push(context);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      expect(popResult, isFalse);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    }, tags: <String>['needs_codegen']);

    testWidgets('shows validation error when Save tapped on empty form',
        (WidgetTester tester) async {
      // 保存ボタンはフォーム末尾にあり、既定のテスト画面 (800x600) では
      // 画面外 (y=1093) にいる。そのまま tap すると
      // 「hit test しない Offset」という **警告が出るだけで何も起きない**。
      // 警告はテスト失敗にならないので、症状は「バリデーションエラーが
      // 表示されない」ようにしか見えず原因が分かりにくい。
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        wrapWithAppAndDb(
          db: db,
          child: const MealRecordScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // 銘柄エラー
      expect(find.textContaining('銘柄'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    }, tags: <String>['needs_codegen']);
  });
}
