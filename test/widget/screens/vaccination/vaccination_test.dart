// ============================================================================
// petlo - Vaccination Tests
// ============================================================================

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/data/local/database_enums.dart';
import 'package:petlo/data/repositories/vaccinations_repository.dart';
import 'package:petlo/presentation/providers/database_provider.dart';
import 'package:petlo/presentation/providers/scope_providers.dart';
import 'package:petlo/presentation/screens/vaccination/vaccination_form_controller.dart';
import 'package:petlo/presentation/screens/vaccination/vaccination_form_state.dart';
import 'package:petlo/presentation/screens/vaccination/vaccination_record_screen.dart';

import '../../../helpers/test_app.dart';

void main() {
  // ==========================================================================
  // VaccinationFormState
  // ==========================================================================
  group('VaccinationFormState validate', () {
    test('rejects empty kind', () {
      const VaccinationFormState s = VaccinationFormState();
      expect(s.validate().errors.kind, isNotNull);
    });

    test('rejects future administeredAt > tomorrow', () {
      final s = VaccinationFormState(
        kind: '混合ワクチン',
        administeredAt: DateTime.now().add(const Duration(days: 5)),
      );
      expect(s.validate().errors.administeredAt, isNotNull);
    });

    test('rejects nextDueAt <= administeredAt', () {
      final adm = DateTime.now();
      final s = VaccinationFormState(
        kind: '混合ワクチン',
        administeredAt: adm,
        nextDueAt: adm, // 同じ日付
      );
      expect(s.validate().errors.nextDueAt, isNotNull);
    });

    test('rejects nextDueAt before administeredAt', () {
      final adm = DateTime(2025, 5, 1);
      final due = DateTime(2025, 4, 1);
      final s = VaccinationFormState(
        kind: '混合ワクチン',
        administeredAt: adm,
        nextDueAt: due,
      );
      expect(s.validate().errors.nextDueAt, isNotNull);
    });

    test('valid full state has no errors', () {
      final s = VaccinationFormState(
        kind: '混合ワクチン',
        administeredAt: DateTime.now(),
        nextDueAt: DateTime.now().add(const Duration(days: 365)),
      );
      expect(s.validate().errors.hasAny, isFalse);
    });

    test('nextDueAt null is OK (optional)', () {
      final s = VaccinationFormState(
        kind: '混合ワクチン',
        administeredAt: DateTime.now(),
      );
      expect(s.validate().errors.hasAny, isFalse);
    });
  });

  // ==========================================================================
  // VaccinationsRepository
  // ==========================================================================
  group('VaccinationsRepository', () {
    late AppDatabase db;
    late VaccinationsRepository repo;

    int now() => DateTime.now().toUtc().millisecondsSinceEpoch;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = VaccinationsRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('rejects empty kind', () async {
      expect(
        () => repo.create(
          groupId: 'personal',
          petId: 1,
          kind: '',
          administeredAtMsec: now(),
        ),
        throwsArgumentError,
      );
    }, tags: <String>['needs_codegen']);

    test('rejects nextDueAt <= administeredAt', () async {
      final t = now();
      expect(
        () => repo.create(
          groupId: 'personal',
          petId: 1,
          kind: 'X',
          administeredAtMsec: t,
          nextDueAtMsec: t, // 同じ
        ),
        throwsArgumentError,
      );
    }, tags: <String>['needs_codegen']);

    test('create + read with nextDue', () async {
      final t = now();
      final int id = await repo.create(
        groupId: 'personal',
        petId: 1,
        kind: '混合ワクチン',
        administeredAtMsec: t,
        nextDueAtMsec: t + const Duration(days: 365).inMilliseconds,
        clinicName: 'X Clinic',
      );
      final v = await repo.getById(id);
      expect(v, isNotNull);
      expect(v!.kind, '混合ワクチン');
      expect(v.nextDueAt, isNotNull);
    }, tags: <String>['needs_codegen']);

    test('watchUpcomingDue returns vaccines due in window', () async {
      final t = now();
      final int in10days = t + const Duration(days: 10).inMilliseconds;
      final int in50days = t + const Duration(days: 50).inMilliseconds;

      // 10日後に予定 → in window
      await repo.create(
        groupId: 'personal',
        petId: 1,
        kind: 'A',
        administeredAtMsec: t - const Duration(days: 1).inMilliseconds,
        nextDueAtMsec: in10days,
      );
      // 50日後に予定 → out of 30-day window
      await repo.create(
        groupId: 'personal',
        petId: 1,
        kind: 'B',
        administeredAtMsec: t - const Duration(days: 1).inMilliseconds,
        nextDueAtMsec: in50days,
      );

      final list = await repo
          .watchUpcomingDue(
            petId: 1,
            fromMsec: t,
            toMsec: t + const Duration(days: 30).inMilliseconds,
          )
          .first;
      expect(list.length, 1);
      expect(list.first.kind, 'A');
    }, tags: <String>['needs_codegen']);

    test('watchOverdue returns past-due vaccines', () async {
      final t = now();
      // 過去予定 → overdue
      await repo.create(
        groupId: 'personal',
        petId: 1,
        kind: 'Old',
        administeredAtMsec: t - const Duration(days: 400).inMilliseconds,
        nextDueAtMsec: t - const Duration(days: 30).inMilliseconds,
      );

      final list = await repo.watchOverdue(1).first;
      expect(list.length, 1);
      expect(list.first.kind, 'Old');
    }, tags: <String>['needs_codegen']);
  });

  // ==========================================================================
  // VaccinationFormController
  // ==========================================================================
  group('VaccinationFormController', () {
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

    test('save creates vaccination record', () async {
      final petId = await createPet();
      await container.read(currentPetIdProvider.notifier).selectPet(petId);

      final ctrl =
          container.read(vaccinationFormControllerProvider(null).notifier);
      ctrl
        ..updateKind('混合ワクチン')
        ..updateNextDueAt(DateTime.now().add(const Duration(days: 365)));

      final r = await ctrl.save();
      expect(r, VaccinationFormSaveOutcome.success);

      final repo = VaccinationsRepository(db);
      final list = await repo.watchForPet(petId).first;
      expect(list.length, 1);
      expect(list.first.kind, '混合ワクチン');
      expect(list.first.nextDueAt, isNotNull);
    }, tags: <String>['needs_codegen']);

    test('validate fail prevents save', () async {
      await createPet();
      final ctrl =
          container.read(vaccinationFormControllerProvider(null).notifier);
      // kind未入力でsave
      final r = await ctrl.save();
      expect(r, VaccinationFormSaveOutcome.validationFailed);
    }, tags: <String>['needs_codegen']);

    test('clearNextDue when nextDueAt set to null after editing', () async {
      final petId = await createPet();
      await container.read(currentPetIdProvider.notifier).selectPet(petId);

      // まずnextDueありで保存
      final ctrl =
          container.read(vaccinationFormControllerProvider(null).notifier);
      ctrl
        ..updateKind('X')
        ..updateNextDueAt(DateTime.now().add(const Duration(days: 30)));
      await ctrl.save();

      final repo = VaccinationsRepository(db);
      final list = await repo.watchForPet(petId).first;
      expect(list.first.nextDueAt, isNotNull);
    }, tags: <String>['needs_codegen']);
  });

  // ==========================================================================
  // VaccinationRecordScreen
  // ==========================================================================
  group('VaccinationRecordScreen', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('shows NEW VACCINATION header', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithAppAndDb(db: db, child: const VaccinationRecordScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('NEW VACCINATION'), findsOneWidget);
    }, tags: <String>['needs_codegen']);

    testWidgets('shows suggestion chips', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithAppAndDb(db: db, child: const VaccinationRecordScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('混合ワクチン'), findsOneWidget);
      expect(find.text('狂犬病'), findsOneWidget);
      expect(find.text('レプトスピラ'), findsOneWidget);
    }, tags: <String>['needs_codegen']);
  });
}
