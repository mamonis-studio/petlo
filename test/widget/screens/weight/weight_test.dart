// ============================================================================
// petlo - Weight Tests
// ============================================================================

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/data/local/database_enums.dart';
import 'package:petlo/data/repositories/weights_repository.dart';
import 'package:petlo/presentation/providers/database_provider.dart';
import 'package:petlo/presentation/providers/scope_providers.dart';
import 'package:petlo/presentation/screens/weight/weight_form_controller.dart';
import 'package:petlo/presentation/screens/weight/weight_form_state.dart';
import 'package:petlo/presentation/screens/weight/weight_record_screen.dart';

import '../../../helpers/test_app.dart';

void main() {
  // ==========================================================================
  // WeightFormState
  // ==========================================================================
  group('WeightFormState validate', () {
    test('rejects null weight', () {
      const WeightFormState s = WeightFormState();
      expect(s.validate().errors.weightG, isNotNull);
    });

    test('rejects zero or negative weight', () {
      const WeightFormState s1 = WeightFormState(weightG: 0);
      expect(s1.validate().errors.weightG, isNotNull);
      const WeightFormState s2 = WeightFormState(weightG: -100);
      expect(s2.validate().errors.weightG, isNotNull);
    });

    test('rejects > 200kg', () {
      const WeightFormState s = WeightFormState(weightG: 201000);
      expect(s.validate().errors.weightG, isNotNull);
    });

    test('rejects future measuredAt', () {
      final s = WeightFormState(
        weightG: 5200,
        measuredAt: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(s.validate().errors.measuredAt, isNotNull);
    });

    test('valid full state has no errors', () {
      final s = WeightFormState(
        weightG: 5200,
        measuredAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(s.validate().errors.hasAny, isFalse);
    });
  });

  // ==========================================================================
  // WeightsRepository
  // ==========================================================================
  group('WeightsRepository', () {
    late AppDatabase db;
    late WeightsRepository repo;

    int now() => DateTime.now().toUtc().millisecondsSinceEpoch;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = WeightsRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('rejects weightG <= 0', () async {
      expect(
        () => repo.create(
          groupId: 'personal',
          petId: 1,
          weightG: 0,
          measuredAtMsec: now(),
        ),
        throwsArgumentError,
      );
    }, tags: <String>['needs_codegen']);

    test('rejects weightG > 200kg', () async {
      expect(
        () => repo.create(
          groupId: 'personal',
          petId: 1,
          weightG: 201000,
          measuredAtMsec: now(),
        ),
        throwsArgumentError,
      );
    }, tags: <String>['needs_codegen']);

    test('create + read', () async {
      final int id = await repo.create(
        groupId: 'personal',
        petId: 1,
        weightG: 5200,
        measuredAtMsec: now(),
      );
      final w = await repo.getById(id);
      expect(w, isNotNull);
      expect(w!.weightG, 5200);
    }, tags: <String>['needs_codegen']);

    test('watchLatest returns most recent', () async {
      final t = now();
      await repo.create(
        groupId: 'personal',
        petId: 1,
        weightG: 5000,
        measuredAtMsec: t - 86400000, // 昨日
      );
      await repo.create(
        groupId: 'personal',
        petId: 1,
        weightG: 5200,
        measuredAtMsec: t,
      );

      final latest = await repo.watchLatest(1).first;
      expect(latest, isNotNull);
      expect(latest!.weightG, 5200);
    }, tags: <String>['needs_codegen']);

    test('watchInRange filters correctly', () async {
      final t = now();
      // 古い記録(範囲外)
      await repo.create(
        groupId: 'personal',
        petId: 1,
        weightG: 5000,
        measuredAtMsec: t - (100 * 86400000), // 100日前
      );
      // 範囲内
      await repo.create(
        groupId: 'personal',
        petId: 1,
        weightG: 5200,
        measuredAtMsec: t - (10 * 86400000),
      );

      final from = t - (90 * 86400000);
      final list = await repo
          .watchInRange(petId: 1, fromMsec: from, toMsec: t)
          .first;
      expect(list.length, 1);
      expect(list.first.weightG, 5200);
    }, tags: <String>['needs_codegen']);
  });

  // ==========================================================================
  // WeightFormController
  // ==========================================================================
  group('WeightFormController', () {
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

    Future<int> createPet() async {
      final t = DateTime.now().millisecondsSinceEpoch;
      return db.into(db.pets).insert(
            PetsCompanion.insert(
              groupId: const Value('personal'),
              name: 'T',
              type: PetType.dog,
              breed: 'b',
              sex: PetSex.male,
              createdAt: t,
              updatedAt: t,
            ),
          );
    }

    test('save creates weight record', () async {
      final petId = await createPet();
      await container.read(currentPetIdProvider.notifier).selectPet(petId);

      final ctrl =
          container.read(weightFormControllerProvider(null).notifier);
      ctrl.updateWeightG(5200);

      final r = await ctrl.save();
      expect(r, WeightFormSaveOutcome.success);

      final repo = WeightsRepository(db);
      final list = await repo.watchForPet(petId).first;
      expect(list.length, 1);
      expect(list.first.weightG, 5200);
    }, tags: <String>['needs_codegen']);

    test('unit toggle does not affect saved weightG', () async {
      final petId = await createPet();
      await container.read(currentPetIdProvider.notifier).selectPet(petId);

      final ctrl =
          container.read(weightFormControllerProvider(null).notifier);
      ctrl.updateWeightG(5200);
      ctrl.updateUnit(WeightUnit.lb); // 単位変更だけしてSave

      final r = await ctrl.save();
      expect(r, WeightFormSaveOutcome.success);

      final repo = WeightsRepository(db);
      final list = await repo.watchForPet(petId).first;
      expect(list.first.weightG, 5200); // gで保存されてる
    }, tags: <String>['needs_codegen']);
  });

  // ==========================================================================
  // WeightRecordScreen
  // ==========================================================================
  group('WeightRecordScreen', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('shows NEW WEIGHT header', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithAppAndDb(db: db, child: const WeightRecordScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('NEW WEIGHT'), findsOneWidget);
    }, tags: <String>['needs_codegen']);
  });
}
