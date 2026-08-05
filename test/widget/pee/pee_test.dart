// ============================================================================
// petlo - Pee Tests
// ============================================================================

// Value を使うため。native.dart だけでは Value が入ってこない。
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/data/local/database_enums.dart';
import 'package:petlo/data/repositories/pees_repository.dart';
import 'package:petlo/l10n/generated/app_localizations.dart';
import 'package:petlo/presentation/providers/database_provider.dart';
import 'package:petlo/presentation/providers/scope_providers.dart';
import 'package:petlo/presentation/screens/pee/pee_form_controller.dart';
import 'package:petlo/presentation/screens/pee/pee_form_state.dart';
import 'package:petlo/presentation/screens/pee/pee_record_screen.dart';
import 'package:petlo/presentation/widgets/pee/pee_color_selector.dart';
import 'package:petlo/presentation/widgets/records/count_stepper.dart';

import '../../helpers/test_app.dart';

// build 39: validate/save(l10n) シグネチャ化に伴い l10n を渡す。
final AppLocalizations _l10n = lookupAppLocalizations(const Locale('ja'));

void main() {
  // アプリのプロバイダ群 (scope_providers など) が build 中に
  // PetloLogger.instance を触るため、初期化しないと落ちる。
  setUpAll(initTestLogger);

  // ==========================================================================
  // PeeFormState
  // ==========================================================================
  group('PeeFormState', () {
    test('default count is 1', () {
      const PeeFormState s = PeeFormState();
      expect(s.count, 1);
    });

    test('validate rejects out-of-range count', () {
      const PeeFormState s = PeeFormState(
        color: PeeColor.yellow,
        amount: RecordAmount.normal,
        count: 11,
      );
      expect(s.validate(_l10n).errors.count, isNotNull);
    });

    test('valid state passes', () {
      final s = PeeFormState(
        color: PeeColor.yellow,
        amount: RecordAmount.normal,
        count: 1,
        peedAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(s.validate(_l10n).errors.hasAny, isFalse);
    });
  });

  // ==========================================================================
  // PeeColorSelector
  // ==========================================================================
  group('PeeColorSelector', () {
    testWidgets('renders all 6 colors', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: PeeColorSelector(
            value: PeeColor.yellow,
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('淡色'), findsOneWidget);
      expect(find.text('黄'), findsOneWidget);
      expect(find.text('濃い'), findsOneWidget);
      expect(find.text('琥珀'), findsOneWidget);
      expect(find.text('赤'), findsOneWidget);
      expect(find.text('濁り'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('triggers onChanged on tap', (WidgetTester tester) async {
      PeeColor? captured;
      await tester.pumpWidget(
        wrapWithApp(
          child: PeeColorSelector(
            value: null,
            onChanged: (PeeColor c) => captured = c,
          ),
        ),
      );
      await tester.tap(find.text('赤'));
      expect(captured, PeeColor.red);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });
  });

  // ==========================================================================
  // CountStepper
  // ==========================================================================
  group('CountStepper', () {
    testWidgets('renders value', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: CountStepper(
            label: 'Count',
            value: 3,
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('3'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('+ button increments', (WidgetTester tester) async {
      int captured = 0;
      await tester.pumpWidget(
        wrapWithApp(
          child: CountStepper(
            label: 'Count',
            value: 3,
            onChanged: (int v) => captured = v,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.add));
      expect(captured, 4);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('- button decrements', (WidgetTester tester) async {
      int captured = 0;
      await tester.pumpWidget(
        wrapWithApp(
          child: CountStepper(
            label: 'Count',
            value: 3,
            onChanged: (int v) => captured = v,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.remove));
      expect(captured, 2);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('- disabled at min', (WidgetTester tester) async {
      int? captured;
      await tester.pumpWidget(
        wrapWithApp(
          child: CountStepper(
            label: 'Count',
            value: 1,
            min: 1,
            onChanged: (int v) => captured = v,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.remove));
      expect(captured, isNull);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('+ disabled at max', (WidgetTester tester) async {
      int? captured;
      await tester.pumpWidget(
        wrapWithApp(
          child: CountStepper(
            label: 'Count',
            value: 10,
            max: 10,
            onChanged: (int v) => captured = v,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.add));
      expect(captured, isNull);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });
  });

  // ==========================================================================
  // PeesRepository (DB)
  // ==========================================================================
  group('PeesRepository', () {
    late AppDatabase db;
    late PeesRepository repo;

    int now() => DateTime.now().toUtc().millisecondsSinceEpoch;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = PeesRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('create rejects count < 1', () async {
      expect(
        () => repo.create(
          groupId: 'personal',
          petId: 1,
          color: PeeColor.yellow,
          amount: RecordAmount.normal,
          count: 0,
          peedAtMsec: now(),
        ),
        throwsArgumentError,
      );
    }, tags: <String>['needs_codegen']);

    test('create + read', () async {
      final int id = await repo.create(
        groupId: 'personal',
        petId: 1,
        color: PeeColor.yellow,
        amount: RecordAmount.normal,
        count: 3,
        peedAtMsec: now(),
      );
      final p = await repo.getById(id);
      expect(p, isNotNull);
      expect(p!.count, 3);
      expect(p.color, PeeColor.yellow);
    }, tags: <String>['needs_codegen']);
  });

  // ==========================================================================
  // PeeFormController (DB)
  // ==========================================================================
  group('PeeFormController', () {
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

    test('save creates pee record', () async {
      final petId = await createPet();
      await container.read(currentPetIdProvider.notifier).selectPet(petId);

      final ctrl = container.read(peeFormControllerProvider(null).notifier);
      ctrl
        ..updateColor(PeeColor.yellow)
        ..updateAmount(RecordAmount.normal)
        ..updateCount(2);

      final r = await ctrl.save(_l10n);
      expect(r, PeeFormSaveOutcome.success);

      final repo = PeesRepository(db);
      final list = await repo.watchForPet(petId).first;
      expect(list.length, 1);
      expect(list.first.count, 2);
    }, tags: <String>['needs_codegen']);
  });

  // ==========================================================================
  // PeeRecordScreen
  // ==========================================================================
  group('PeeRecordScreen', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('shows NEW PEE header', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithAppAndDb(db: db, child: const PeeRecordScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('新しいおしっこ'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    }, tags: <String>['needs_codegen']);
  });
}
