// ============================================================================
// petlo - Temperature Tests
// ============================================================================

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/data/local/database_enums.dart';
import 'package:petlo/data/repositories/temperatures_repository.dart';
import 'package:petlo/presentation/providers/database_provider.dart';
import 'package:petlo/presentation/providers/scope_providers.dart';
import 'package:petlo/presentation/screens/temperature/temperature_form_controller.dart';
import 'package:petlo/presentation/screens/temperature/temperature_form_state.dart';
import 'package:petlo/presentation/screens/temperature/temperature_record_screen.dart';

import '../../../helpers/test_app.dart';

void main() {
  // ==========================================================================
  // TemperatureFormState
  // ==========================================================================
  group('TemperatureFormState validate', () {
    test('rejects null temp', () {
      const TemperatureFormState s = TemperatureFormState();
      expect(s.validate().errors.tempCelsiusX10, isNotNull);
    });

    test('rejects out-of-range temp (< 30°C)', () {
      const TemperatureFormState s = TemperatureFormState(tempCelsiusX10: 250);
      expect(s.validate().errors.tempCelsiusX10, isNotNull);
    });

    test('rejects out-of-range temp (> 45°C)', () {
      const TemperatureFormState s = TemperatureFormState(tempCelsiusX10: 460);
      expect(s.validate().errors.tempCelsiusX10, isNotNull);
    });

    test('valid normal range passes', () {
      final s = TemperatureFormState(
        tempCelsiusX10: 385,
        measuredAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(s.validate().errors.hasAny, isFalse);
    });

    test('rejects future measuredAt', () {
      final s = TemperatureFormState(
        tempCelsiusX10: 385,
        measuredAt: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(s.validate().errors.measuredAt, isNotNull);
    });
  });

  // ==========================================================================
  // TemperaturesRepository
  // ==========================================================================
  group('TemperaturesRepository', () {
    late AppDatabase db;
    late TemperaturesRepository repo;

    int now() => DateTime.now().toUtc().millisecondsSinceEpoch;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = TemperaturesRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('rejects out-of-range tempCelsiusX10', () async {
      expect(
        () => repo.create(
          groupId: 'personal',
          petId: 1,
          tempCelsiusX10: 250,
          measuredAtMsec: now(),
        ),
        throwsArgumentError,
      );
      expect(
        () => repo.create(
          groupId: 'personal',
          petId: 1,
          tempCelsiusX10: 500,
          measuredAtMsec: now(),
        ),
        throwsArgumentError,
      );
    }, tags: <String>['needs_codegen']);

    test('create + read', () async {
      final int id = await repo.create(
        groupId: 'personal',
        petId: 1,
        tempCelsiusX10: 385,
        measuredAtMsec: now(),
      );
      final t = await repo.getById(id);
      expect(t, isNotNull);
      expect(t!.tempCelsiusX10, 385);
    }, tags: <String>['needs_codegen']);

    test('watchLatest returns most recent', () async {
      final t = now();
      await repo.create(
        groupId: 'personal', petId: 1, tempCelsiusX10: 380,
        measuredAtMsec: t - 86400000,
      );
      await repo.create(
        groupId: 'personal', petId: 1, tempCelsiusX10: 390,
        measuredAtMsec: t,
      );

      final latest = await repo.watchLatest(1).first;
      expect(latest, isNotNull);
      expect(latest!.tempCelsiusX10, 390);
    }, tags: <String>['needs_codegen']);
  });

  // ==========================================================================
  // TemperatureFormController
  // ==========================================================================
  group('TemperatureFormController', () {
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

    Future<int> createPet({PetType type = PetType.dog}) async {
      final t = DateTime.now().millisecondsSinceEpoch;
      return db.into(db.pets).insert(
            PetsCompanion.insert(
              groupId: const Value('personal'),
              name: 'T',
              type: type,
              breed: 'b',
              sex: PetSex.male,
              createdAt: t,
              updatedAt: t,
            ),
          );
    }

    test('save creates temperature record', () async {
      final petId = await createPet();
      await container.read(currentPetIdProvider.notifier).selectPet(petId);

      final ctrl = container
          .read(temperatureFormControllerProvider(null).notifier);
      ctrl.updateTempCelsiusX10(385);

      final r = await ctrl.save();
      expect(r, TemperatureFormSaveOutcome.success);

      final repo = TemperaturesRepository(db);
      final list = await repo.watchForPet(petId).first;
      expect(list.length, 1);
      expect(list.first.tempCelsiusX10, 385);
    }, tags: <String>['needs_codegen']);

    test('petType is loaded from DB on build', () async {
      final petId = await createPet(type: PetType.cat);
      await container.read(currentPetIdProvider.notifier).selectPet(petId);

      // build()トリガー
      container.read(temperatureFormControllerProvider(null));
      // 非同期loadPetType待ち
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state =
          container.read(temperatureFormControllerProvider(null));
      expect(state.petType, PetType.cat);
    }, tags: <String>['needs_codegen']);
  });

  // ==========================================================================
  // TemperatureRecordScreen
  // ==========================================================================
  group('TemperatureRecordScreen', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('shows NEW TEMP header', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithAppAndDb(db: db, child: const TemperatureRecordScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('NEW TEMP'), findsOneWidget);
    }, tags: <String>['needs_codegen']);
  });
}
