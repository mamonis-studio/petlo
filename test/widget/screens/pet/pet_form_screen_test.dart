// ============================================================================
// petlo - PetForm Tests
// ============================================================================
//
// PetFormState (純DTO、codegen不要) と PetFormScreen (codegen必要) の両方。
//
// ============================================================================

import 'package:drift/native.dart';
import 'package:petlo/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/data/local/database_enums.dart';
import 'package:petlo/data/repositories/pets_repository.dart';
import 'package:petlo/presentation/providers/database_provider.dart';
import 'package:petlo/presentation/providers/pro_status_provider.dart';
import 'package:petlo/presentation/providers/scope_providers.dart';
import 'package:petlo/presentation/screens/pet/pet_form_controller.dart';
import 'package:petlo/presentation/screens/pet/pet_form_screen.dart';
import 'package:petlo/presentation/screens/pet/pet_form_state.dart';

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
  // PetFormState (Pure DTO)
  // ==========================================================================
  // build 73: 'empty breed yields error' / 'null sex yields error' は削除した。
  // breed は build 12、sex は build 22 で任意化され (DB も nullable)、
  // validate() は両方とも常に null を返す。存在しない仕様の検証だった。
  group('PetFormState', () {
    test('default state is empty', () {
      const PetFormState s = PetFormState();
      expect(s.name, '');
      expect(s.type, isNull);
      expect(s.isEditing, isFalse);
      expect(s.errors.hasAny, isFalse);
    });

    test('isEditing reflects editingPetId presence', () {
      const PetFormState s = PetFormState(editingPetId: 42);
      expect(s.isEditing, isTrue);
    });

    test('copyWith preserves untouched fields', () {
      const PetFormState s = PetFormState(name: 'Taro', neutered: true);
      final PetFormState s2 = s.copyWith(name: 'Mike');
      expect(s2.name, 'Mike');
      expect(s2.neutered, isTrue);
    });

    test('copyWith with explicit null clears nullable fields', () {
      final PetFormState s = PetFormState(birthday: DateTime(2020));
      final PetFormState s2 = s.copyWith(birthday: null);
      expect(s2.birthday, isNull);
    });

    group('validate()', () {
      test('empty name yields error', () {
        const PetFormState s = PetFormState();
        final PetFormState v = s.validate(l10n);
        expect(v.errors.name, isNotNull);
      });

      test('long name (>50) yields error', () {
        final String longName = 'X' * 51;
        final PetFormState s = PetFormState(name: longName);
        final PetFormState v = s.validate(l10n);
        expect(v.errors.name, isNotNull);
      });

      test('null type yields error', () {
        const PetFormState s = PetFormState(name: 'Taro');
        final PetFormState v = s.validate(l10n);
        expect(v.errors.type, isNotNull);
      });

      test('idealWeight min > max yields error', () {
        const PetFormState s = PetFormState(
          name: 'Taro',
          type: PetType.dog,
          breed: 'b',
          sex: PetSex.male,
          idealWeightMinG: 5000,
          idealWeightMaxG: 4000,
        );
        final PetFormState v = s.validate(l10n);
        expect(v.errors.idealWeightMinG, isNotNull);
        expect(v.errors.idealWeightMaxG, isNotNull);
      });

      test('valid full input has no errors', () {
        const PetFormState s = PetFormState(
          name: 'Taro',
          type: PetType.dog,
          breed: 'shiba',
          sex: PetSex.male,
          idealWeightMinG: 4000,
          idealWeightMaxG: 6000,
        );
        final PetFormState v = s.validate(l10n);
        expect(v.errors.hasAny, isFalse);
      });

      test('invalid phone yields error', () {
        const PetFormState s = PetFormState(
          name: 'Taro',
          type: PetType.dog,
          breed: 'b',
          sex: PetSex.male,
          primaryVetPhone: 'abc-def',
        );
        final PetFormState v = s.validate(l10n);
        expect(v.errors.primaryVetPhone, isNotNull);
      });
    });
  });

  // ==========================================================================
  // PetFormController (with DB)
  // ==========================================================================
  group('PetFormController', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          // build 71 で Free プランのペット上限 (freeMaxPets = 1) が入った。
          // 同名確認は 2 匹目を作ろうとしたときの挙動なので、Pro 扱いに
          // しないと上限判定が先に当たり proLimitReached が返る。
          isProProvider.overrideWithValue(true),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('save() creates new pet on success', () async {
      final ctrl = container.read(petFormControllerProvider(null).notifier);
      ctrl
        ..updateName('Taro')
        ..updateType(PetType.dog)
        ..updateBreed('shiba')
        ..updateSex(PetSex.male);

      final PetFormSaveOutcome r = await ctrl.save(l10n);
      expect(r, PetFormSaveOutcome.success);

      // ペットが作成されている
      final repo = PetsRepository(db);
      final List<PetEntity> pets =
          await repo.watchActivePetsInScope('personal').first;
      expect(pets.length, 1);
      expect(pets.first.name, 'Taro');
    }, tags: <String>['needs_codegen']);

    test('save() returns validationFailed when invalid', () async {
      final ctrl = container.read(petFormControllerProvider(null).notifier);
      // 名前なしで save
      final PetFormSaveOutcome r = await ctrl.save(l10n);
      expect(r, PetFormSaveOutcome.validationFailed);

      final state = container.read(petFormControllerProvider(null));
      expect(state.errors.hasAny, isTrue);
    }, tags: <String>['needs_codegen']);

    test('save() returns duplicateNameNeedsConfirmation when same name exists',
        () async {
      // 既存ペット作成
      final repo = PetsRepository(db);
      await repo.createPet(
        groupId: 'personal',
        name: 'Taro',
        type: PetType.dog,
        breed: 'shiba',
        sex: PetSex.male,
      );

      // 同じ名前で新規登録
      final ctrl = container.read(petFormControllerProvider(null).notifier);
      ctrl
        ..updateName('Taro')
        ..updateType(PetType.dog)
        ..updateBreed('shiba')
        ..updateSex(PetSex.male);

      final PetFormSaveOutcome r = await ctrl.save(l10n);
      expect(r, PetFormSaveOutcome.duplicateNameNeedsConfirmation);

      // ペットはまだ作成されてない
      final List<PetEntity> pets =
          await repo.watchActivePetsInScope('personal').first;
      expect(pets.length, 1);
    }, tags: <String>['needs_codegen']);

    test('confirmAndSave() bypasses duplicate check', () async {
      final repo = PetsRepository(db);
      await repo.createPet(
        groupId: 'personal',
        name: 'Taro',
        type: PetType.dog,
        breed: 'shiba',
        sex: PetSex.male,
      );

      final ctrl = container.read(petFormControllerProvider(null).notifier);
      ctrl
        ..updateName('Taro')
        ..updateType(PetType.dog)
        ..updateBreed('shiba')
        ..updateSex(PetSex.female);

      // 同名チェックを回避して保存
      final PetFormFinalSaveOutcome r = await ctrl.confirmAndSave(l10n);
      expect(r, PetFormFinalSaveOutcome.success);

      final List<PetEntity> pets =
          await repo.watchActivePetsInScope('personal').first;
      expect(pets.length, 2);
    }, tags: <String>['needs_codegen']);

    test('save() new pet auto-switches currentPetId', () async {
      final ctrl = container.read(petFormControllerProvider(null).notifier);
      ctrl
        ..updateName('Mike')
        ..updateType(PetType.cat)
        ..updateBreed('mix')
        ..updateSex(PetSex.male);

      // 保存前は未選択
      expect(container.read(currentPetIdProvider), isNull);

      await ctrl.save(l10n);
      // pet_selection_controller のmicrotask完了を待つ
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 保存後は currentPetId が新しいペットを指す
      final String? newPetId = container.read(currentPetIdProvider);
      expect(newPetId, isNotNull);
      expect(int.tryParse(newPetId ?? ''), isNotNull);
    }, tags: <String>['needs_codegen']);

    test('editing mode preserves existing values', () async {
      final repo = PetsRepository(db);
      final int petId = await repo.createPet(
        groupId: 'personal',
        name: 'Original',
        type: PetType.dog,
        breed: 'shiba',
        sex: PetSex.male,
        chronicConditions: <String>['持病A'],
      );

      // 編集モードで開く
      container.read(petFormControllerProvider(petId)); // build()トリガー
      // 非同期ロード待ち
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(petFormControllerProvider(petId));
      expect(state.name, 'Original');
      expect(state.breed, 'shiba');
      expect(state.chronicConditions, <String>['持病A']);
    }, tags: <String>['needs_codegen']);
  });

  // ==========================================================================
  // PetFormScreen Widget tests
  // ==========================================================================
  group('PetFormScreen', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('shows "Add a pet" header for new pet', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithAppAndDb(
          db: db,
          child: const PetFormScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('新しいペット'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    }, tags: <String>['needs_codegen']);

    testWidgets('shows "Edit" header for existing pet',
        (WidgetTester tester) async {
      // 既存ペット作成
      final repo = PetsRepository(db);
      final int petId = await repo.createPet(
        groupId: 'personal',
        name: 'Taro',
        type: PetType.dog,
        breed: 'shiba',
        sex: PetSex.male,
      );

      await tester.pumpWidget(
        wrapWithAppAndDb(
          db: db,
          child: PetFormScreen(editingPetId: petId),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ペットを編集'), findsOneWidget);
      expect(find.text('更新'), findsOneWidget);
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
                  popResult = await PetFormScreen.push(context);
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

    testWidgets('shows validation errors when Save tapped on empty form',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithAppAndDb(
          db: db,
          child: const PetFormScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Saveをタップ
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // 名前必須エラー
      expect(find.textContaining('名前'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    }, tags: <String>['needs_codegen']);
  });
}
