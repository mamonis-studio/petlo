// ============================================================================
// petlo - Visit Tests
// ============================================================================

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/data/local/database_enums.dart';
import 'package:petlo/data/repositories/visits_repository.dart';
import 'package:petlo/presentation/providers/database_provider.dart';
import 'package:petlo/presentation/providers/scope_providers.dart';
import 'package:petlo/presentation/screens/visit/visit_form_controller.dart';
import 'package:petlo/presentation/screens/visit/visit_form_state.dart';
import 'package:petlo/presentation/screens/visit/visit_record_screen.dart';
import 'package:petlo/presentation/widgets/forms/multi_photo_picker.dart';

import '../../../helpers/test_app.dart';

void main() {
  // ==========================================================================
  // VisitFormState
  // ==========================================================================
  group('VisitFormState validate', () {
    test('rejects empty reason', () {
      const VisitFormState s = VisitFormState();
      expect(s.validate().errors.reason, isNotNull);
    });

    test('rejects whitespace-only reason', () {
      const VisitFormState s = VisitFormState(reason: '   ');
      expect(s.validate().errors.reason, isNotNull);
    });

    test('rejects future visitedAt > tomorrow', () {
      final s = VisitFormState(
        reason: 'checkup',
        visitedAt: DateTime.now().add(const Duration(days: 5)),
      );
      expect(s.validate().errors.visitedAt, isNotNull);
    });

    test('rejects negative cost', () {
      final s = VisitFormState(
        reason: 'checkup',
        visitedAt: DateTime.now(),
        costJpy: -100,
      );
      expect(s.validate().errors.costJpy, isNotNull);
    });

    test('valid full state has no errors', () {
      final s = VisitFormState(
        reason: 'skin allergy',
        visitedAt: DateTime.now(),
        costJpy: 5000,
      );
      expect(s.validate().errors.hasAny, isFalse);
    });
  });

  // ==========================================================================
  // VisitsRepository
  // ==========================================================================
  group('VisitsRepository', () {
    late AppDatabase db;
    late VisitsRepository repo;

    int now() => DateTime.now().toUtc().millisecondsSinceEpoch;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = VisitsRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('rejects empty reason', () async {
      expect(
        () => repo.create(
          groupId: 'personal',
          petId: 1,
          visitedAtMsec: now(),
          reason: '',
        ),
        throwsArgumentError,
      );
    }, tags: <String>['needs_codegen']);

    test('rejects negative cost', () async {
      expect(
        () => repo.create(
          groupId: 'personal',
          petId: 1,
          visitedAtMsec: now(),
          reason: 'checkup',
          costJpy: -1,
        ),
        throwsArgumentError,
      );
    }, tags: <String>['needs_codegen']);

    test('create + read with photoPaths', () async {
      final int id = await repo.create(
        groupId: 'personal',
        petId: 1,
        visitedAtMsec: now(),
        reason: 'skin allergy',
        clinicName: 'X Clinic',
        diagnosis: 'allergic dermatitis',
        treatment: 'antibiotics',
        costJpy: 5000,
        photoPaths: <String>['visits/1/0.jpg', 'visits/1/1.jpg'],
      );
      final v = await repo.getById(id);
      expect(v, isNotNull);
      expect(v!.reason, 'skin allergy');
      expect(v.photoPaths?.length, 2);
      expect(v.costJpy, 5000);
    }, tags: <String>['needs_codegen']);

    test('countAllVisits counts only undeleted', () async {
      await repo.create(
        groupId: 'personal', petId: 1, visitedAtMsec: now(),
        reason: 'a',
      );
      final int id2 = await repo.create(
        groupId: 'personal', petId: 1, visitedAtMsec: now(),
        reason: 'b',
      );
      await repo.softDelete(id2);

      final int count = await repo.countAllVisits('personal');
      expect(count, 1);
    }, tags: <String>['needs_codegen']);
  });

  // ==========================================================================
  // VisitFormController
  // ==========================================================================
  group('VisitFormController', () {
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

    test('save creates visit record', () async {
      final petId = await createPet();
      await container.read(currentPetIdProvider.notifier).selectPet(petId);

      final ctrl =
          container.read(visitFormControllerProvider(null).notifier);
      ctrl
        ..updateReason('skin allergy')
        ..updateClinicName('X Clinic')
        ..updateCostJpy(5000);

      final r = await ctrl.save();
      expect(r, VisitFormSaveOutcome.success);

      final repo = VisitsRepository(db);
      final list = await repo.watchForPet(petId).first;
      expect(list.length, 1);
      expect(list.first.reason, 'skin allergy');
      expect(list.first.costJpy, 5000);
    }, tags: <String>['needs_codegen']);

    test('validate fail prevents save', () async {
      await createPet();
      final ctrl =
          container.read(visitFormControllerProvider(null).notifier);
      // reason 未入力で save 試行
      final r = await ctrl.save();
      expect(r, VisitFormSaveOutcome.validationFailed);
    }, tags: <String>['needs_codegen']);

    test('photoSlots are tracked', () async {
      final petId = await createPet();
      await container.read(currentPetIdProvider.notifier).selectPet(petId);

      final ctrl =
          container.read(visitFormControllerProvider(null).notifier);
      ctrl.updatePhotoSlots(<PhotoSlot>[
        const PhotoSlot(savedRelativePath: 'visits/x/0.jpg'),
      ]);
      final state = container.read(visitFormControllerProvider(null));
      expect(state.photoSlots.length, 1);
      expect(state.photoSlots.first.isExisting, isTrue);
    }, tags: <String>['needs_codegen']);
  });

  // ==========================================================================
  // VisitRecordScreen
  // ==========================================================================
  group('VisitRecordScreen', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('shows NEW VISIT header', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithAppAndDb(db: db, child: const VisitRecordScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('NEW VISIT'), findsOneWidget);
    }, tags: <String>['needs_codegen']);
  });
}
