// ============================================================================
// petlo - Poop Tests
// ============================================================================

// Value を使うため。native.dart だけでは Value が入ってこない。
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/data/local/database_enums.dart';
import 'package:petlo/data/repositories/poops_repository.dart';
import 'package:petlo/l10n/generated/app_localizations.dart';
import 'package:petlo/presentation/providers/database_provider.dart';
import 'package:petlo/presentation/providers/scope_providers.dart';
import 'package:petlo/presentation/screens/poop/poop_form_controller.dart';
import 'package:petlo/presentation/screens/poop/poop_form_state.dart';
import 'package:petlo/presentation/screens/poop/poop_record_screen.dart';
import 'package:petlo/presentation/widgets/poop/poop_color_selector.dart';
import 'package:petlo/presentation/widgets/poop/poop_form_selector.dart';

import '../../helpers/test_app.dart';

// build 39: validate/save(l10n) シグネチャ化に伴い l10n を渡す。
final AppLocalizations _l10n = lookupAppLocalizations(const Locale('ja'));

void main() {
  // アプリのプロバイダ群 (scope_providers など) が build 中に
  // PetloLogger.instance を触るため、初期化しないと落ちる。
  setUpAll(initTestLogger);

  // ==========================================================================
  // PoopFormState (Pure DTO)
  // ==========================================================================
  group('PoopFormState validate', () {
    test('rejects when required fields are missing', () {
      const PoopFormState s = PoopFormState();
      final v = s.validate(_l10n);
      expect(v.errors.form, isNotNull);
      expect(v.errors.color, isNotNull);
      expect(v.errors.amount, isNotNull);
      expect(v.errors.pooedAt, isNotNull);
    });

    test('rejects future pooedAt', () {
      final s = PoopFormState(
        form: PoopForm.normal,
        color: PoopColor.brown,
        amount: RecordAmount.normal,
        pooedAt: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(s.validate(_l10n).errors.pooedAt, isNotNull);
    });

    test('valid state has no errors', () {
      final s = PoopFormState(
        form: PoopForm.normal,
        color: PoopColor.brown,
        amount: RecordAmount.normal,
        pooedAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(s.validate(_l10n).errors.hasAny, isFalse);
    });
  });

  // ==========================================================================
  // Selector Widgets (Pure UI)
  // ==========================================================================
  group('PoopFormSelector', () {
    testWidgets('renders all 5 forms with labels', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: PoopFormSelector(
            value: PoopForm.normal,
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('硬便'), findsOneWidget);
      expect(find.text('コロコロ'), findsOneWidget);
      expect(find.text('普通'), findsOneWidget);
      expect(find.text('軟便'), findsOneWidget);
      expect(find.text('水様'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('triggers onChanged on tap', (WidgetTester tester) async {
      PoopForm? captured;
      await tester.pumpWidget(
        wrapWithApp(
          child: PoopFormSelector(
            value: null,
            onChanged: (PoopForm f) => captured = f,
          ),
        ),
      );
      await tester.tap(find.text('水様'));
      expect(captured, PoopForm.watery);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });
  });

  group('PoopColorSelector', () {
    testWidgets('renders all 5 colors', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: PoopColorSelector(
            value: PoopColor.brown,
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('茶'), findsOneWidget);
      expect(find.text('黒'), findsOneWidget);
      expect(find.text('赤'), findsOneWidget);
      expect(find.text('黄'), findsOneWidget);
      expect(find.text('淡色'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('triggers onChanged on tap', (WidgetTester tester) async {
      PoopColor? captured;
      await tester.pumpWidget(
        wrapWithApp(
          child: PoopColorSelector(
            value: null,
            onChanged: (PoopColor c) => captured = c,
          ),
        ),
      );
      await tester.tap(find.text('黒'));
      expect(captured, PoopColor.black);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });
  });

  // ==========================================================================
  // PoopsRepository (DB)
  // ==========================================================================
  group('PoopsRepository', () {
    late AppDatabase db;
    late PoopsRepository repo;

    int now() => DateTime.now().toUtc().millisecondsSinceEpoch;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = PoopsRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('create + read', () async {
      final int id = await repo.create(
        groupId: 'personal',
        petId: 1,
        form: PoopForm.normal,
        color: PoopColor.brown,
        amount: RecordAmount.normal,
        pooedAtMsec: now(),
      );
      final p = await repo.getById(id);
      expect(p, isNotNull);
      expect(p!.form, PoopForm.normal);
      expect(p.color, PoopColor.brown);
    }, tags: <String>['needs_codegen']);

    test('shared scope enqueues sync', () async {
      await repo.create(
        groupId: 'group-x',
        petId: 1,
        form: PoopForm.normal,
        color: PoopColor.brown,
        amount: RecordAmount.normal,
        pooedAtMsec: now(),
      );
      final List<SyncQueueItemEntity> q = await db.select(db.syncQueue).get();
      expect(q.length, 1);
      expect(q.first.targetTable, 'poops');
    }, tags: <String>['needs_codegen']);

    test('softDelete excludes from watchForPet', () async {
      final int id = await repo.create(
        groupId: 'personal', petId: 1, form: PoopForm.normal,
        color: PoopColor.brown, amount: RecordAmount.normal, pooedAtMsec: now(),
      );
      await repo.softDelete(id);
      final List<PoopEntity> list = await repo.watchForPet(1).first;
      expect(list, isEmpty);
    }, tags: <String>['needs_codegen']);
  });

  // ==========================================================================
  // PoopFormController (DB)
  // ==========================================================================
  group('PoopFormController', () {
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
              breed: const Value('b'),
              sex: const Value(PetSex.male),
              createdAt: t,
              updatedAt: t,
            ),
          );
    }

    test('save creates poop record', () async {
      final petId = await createPet();
      await container.read(currentPetIdProvider.notifier).selectPet(petId);

      final ctrl = container.read(poopFormControllerProvider(null).notifier);
      ctrl
        ..updateForm(PoopForm.normal)
        ..updateColor(PoopColor.brown)
        ..updateAmount(RecordAmount.normal);

      final r = await ctrl.save(_l10n);
      expect(r, PoopFormSaveOutcome.success);

      final repo = PoopsRepository(db);
      final list = await repo.watchForPet(petId).first;
      expect(list.length, 1);
    }, tags: <String>['needs_codegen']);

    test('validate fail prevents save', () async {
      await createPet();
      final ctrl = container.read(poopFormControllerProvider(null).notifier);
      final r = await ctrl.save(_l10n);
      expect(r, PoopFormSaveOutcome.validationFailed);

      final state = container.read(poopFormControllerProvider(null));
      expect(state.errors.hasAny, isTrue);
    }, tags: <String>['needs_codegen']);
  });

  // ==========================================================================
  // PoopRecordScreen Widget
  // ==========================================================================
  group('PoopRecordScreen', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('shows NEW STOOL header', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithAppAndDb(db: db, child: const PoopRecordScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('新しいうんち'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    }, tags: <String>['needs_codegen']);
  });
}
