// ============================================================================
// petlo - Diary Tests
// ============================================================================

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/data/local/database_enums.dart';
import 'package:petlo/data/repositories/diaries_repository.dart';
import 'package:petlo/presentation/providers/database_provider.dart';
import 'package:petlo/presentation/providers/scope_providers.dart';
import 'package:petlo/presentation/screens/diary/diary_form_controller.dart';
import 'package:petlo/presentation/screens/diary/diary_form_state.dart';
import 'package:petlo/presentation/screens/diary/diary_record_screen.dart';
import 'package:petlo/presentation/widgets/forms/multi_photo_picker.dart';

import '../../../helpers/test_app.dart';

void main() {
  // ==========================================================================
  // DiaryFormState validate
  // ==========================================================================
  group('DiaryFormState validate', () {
    test('rejects empty body', () {
      const DiaryFormState s = DiaryFormState();
      expect(s.validate().errors.body, isNotNull);
    });

    test('rejects whitespace-only body', () {
      const DiaryFormState s = DiaryFormState(body: '    ');
      expect(s.validate().errors.body, isNotNull);
    });

    test('rejects null eventAt', () {
      const DiaryFormState s = DiaryFormState(body: 'something');
      expect(s.validate().errors.eventAt, isNotNull);
    });

    test('rejects future eventAt > tomorrow', () {
      final s = DiaryFormState(
        body: 'something',
        eventAt: DateTime.now().add(const Duration(days: 5)),
      );
      expect(s.validate().errors.eventAt, isNotNull);
    });

    test('valid full state has no errors', () {
      final s = DiaryFormState(
        body: 'today we walked in the park',
        eventAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(s.validate().errors.hasAny, isFalse);
    });

    test('title is optional', () {
      final s = DiaryFormState(
        title: '',
        body: 'something',
        eventAt: DateTime.now(),
      );
      expect(s.validate().errors.hasAny, isFalse);
    });
  });

  // ==========================================================================
  // DiariesRepository
  // ==========================================================================
  group('DiariesRepository', () {
    late AppDatabase db;
    late DiariesRepository repo;

    int now() => DateTime.now().toUtc().millisecondsSinceEpoch;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = DiariesRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('rejects empty body', () async {
      expect(
        () => repo.create(
          groupId: 'personal',
          petId: 1,
          body: '',
          eventAtMsec: now(),
        ),
        throwsArgumentError,
      );
    }, tags: <String>['needs_codegen']);

    test('create + read with tags + photos', () async {
      final int id = await repo.create(
        groupId: 'personal',
        petId: 1,
        title: '公園散歩',
        body: '今日は天気が良くて公園で遊んだ',
        tags: <String>['散歩', '公園'],
        photoPaths: <String>['diaries/1/0.jpg'],
        eventAtMsec: now(),
      );
      final d = await repo.getById(id);
      expect(d, isNotNull);
      expect(d!.title, '公園散歩');
      expect(d.tags?.length, 2);
      expect(d.photoPaths?.length, 1);
    }, tags: <String>['needs_codegen']);

    test('countInMonth counts only undeleted in month', () async {
      final DateTime now = DateTime.now().toUtc();
      final int t = now.millisecondsSinceEpoch;

      // 今月分2件作成
      await repo.create(
        groupId: 'personal',
        petId: 1,
        body: 'a',
        eventAtMsec: t,
      );
      final int id2 = await repo.create(
        groupId: 'personal',
        petId: 1,
        body: 'b',
        eventAtMsec: t,
      );
      await repo.softDelete(id2);

      final int count = await repo.countInMonth(
        groupId: 'personal',
        year: now.year,
        month: now.month,
      );
      expect(count, 1);
    }, tags: <String>['needs_codegen']);

    test('watchWithPhotos excludes diaries without photos', () async {
      await repo.create(
        groupId: 'personal',
        petId: 1,
        body: 'no photo',
        eventAtMsec: now(),
      );
      await repo.create(
        groupId: 'personal',
        petId: 1,
        body: 'with photo',
        photoPaths: <String>['diaries/x/0.jpg'],
        eventAtMsec: now(),
      );

      final list = await repo.watchWithPhotos(1).first;
      expect(list.length, 1);
      expect(list.first.body, 'with photo');
    }, tags: <String>['needs_codegen']);
  });

  // ==========================================================================
  // DiaryFormController
  // ==========================================================================
  group('DiaryFormController', () {
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

    test('save creates diary record', () async {
      final petId = await createPet();
      await container.read(currentPetIdProvider.notifier).selectPet(petId);

      final ctrl =
          container.read(diaryFormControllerProvider(null).notifier);
      ctrl
        ..updateBody('Today was a fun day')
        ..updateTags(<String>['散歩', '公園']);

      final r = await ctrl.save();
      expect(r, DiaryFormSaveOutcome.success);

      final repo = DiariesRepository(db);
      final list = await repo.watchForPet(petId).first;
      expect(list.length, 1);
      expect(list.first.body, 'Today was a fun day');
      expect(list.first.tags?.length, 2);
    }, tags: <String>['needs_codegen']);

    test('validate fail prevents save', () async {
      await createPet();
      final ctrl =
          container.read(diaryFormControllerProvider(null).notifier);
      // body 未入力で save
      final r = await ctrl.save();
      expect(r, DiaryFormSaveOutcome.validationFailed);
    }, tags: <String>['needs_codegen']);

    test('photoSlots are tracked', () async {
      final petId = await createPet();
      await container.read(currentPetIdProvider.notifier).selectPet(petId);

      final ctrl =
          container.read(diaryFormControllerProvider(null).notifier);
      ctrl.updatePhotoSlots(<PhotoSlot>[
        const PhotoSlot(savedRelativePath: 'diaries/x/0.jpg'),
      ]);
      final state = container.read(diaryFormControllerProvider(null));
      expect(state.photoSlots.length, 1);
      expect(state.photoSlots.first.isExisting, isTrue);
    }, tags: <String>['needs_codegen']);
  });

  // ==========================================================================
  // DiaryRecordScreen
  // ==========================================================================
  group('DiaryRecordScreen', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('shows NEW DIARY header', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithAppAndDb(db: db, child: const DiaryRecordScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('NEW DIARY'), findsOneWidget);
    }, tags: <String>['needs_codegen']);

    testWidgets('shows hero title', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithAppAndDb(db: db, child: const DiaryRecordScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('A moment'), findsOneWidget);
    }, tags: <String>['needs_codegen']);
  });
}
