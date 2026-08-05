// ============================================================================
// petlo - Vomit Tests (rev5.5)
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
import 'package:petlo/data/repositories/vomits_repository.dart';
import 'package:petlo/presentation/providers/database_provider.dart';
import 'package:petlo/presentation/providers/scope_providers.dart';
import 'package:petlo/presentation/screens/vomit/vomit_form_controller.dart';
import 'package:petlo/presentation/screens/vomit/vomit_form_state.dart';
import 'package:petlo/presentation/screens/vomit/vomit_record_screen.dart';
import 'package:petlo/presentation/widgets/vomit/vomit_color_selector.dart';

import '../../helpers/test_app.dart';

void main() {
  // validate() が AppLocalizations を取るようになったため、
  // State 単体のテストでもロケールを用意する。
  late AppLocalizations l10n;
  setUpAll(() async {
    await initTestLogger();
    l10n = await loadTestL10n();
  });

  // ==========================================================================
  // VomitFormState
  // ==========================================================================
  group('VomitFormState', () {
    test('rejects when color=other but colorOtherText empty', () {
      const VomitFormState s = VomitFormState(
        color: VomitColor.other,
        colorOtherText: '',
        amount: RecordAmount.normal,
      );
      expect(s.validate(l10n).errors.colorOtherText, isNotNull);
    });

    test('accepts when color=other with description', () {
      final s = VomitFormState(
        color: VomitColor.other,
        colorOtherText: 'Orange-ish',
        amount: RecordAmount.normal,
        vomitedAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(s.validate(l10n).errors.hasAny, isFalse);
    });

    test('valid mainColor state passes', () {
      final s = VomitFormState(
        color: VomitColor.yellow,
        amount: RecordAmount.little,
        vomitedAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(s.validate(l10n).errors.hasAny, isFalse);
    });
  });

  // ==========================================================================
  // VomitColorSelector (rev5.5 2階層UI)
  // ==========================================================================
  group('VomitColorSelector (rev5.5 2-tier)', () {
    testWidgets('shows 4 main colors initially',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: VomitColorSelector(
            value: null,
            colorOtherText: '',
            onChanged: (_) {},
            onOtherTextChanged: (_) {},
          ),
        ),
      );
      expect(find.text('透明'), findsOneWidget);
      expect(find.text('黄'), findsOneWidget);
      expect(find.text('茶'), findsOneWidget);
      expect(find.text('食べ物'), findsOneWidget);
      // 詳細色は最初は隠れている
      expect(find.text('白い泡'), findsNothing);
      expect(find.text('赤'), findsNothing);
      expect(find.text('黒'), findsNothing);
      // Otherボタンが見える
      expect(find.text('他の色'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('reveals 5 detail colors when Other tapped',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: VomitColorSelector(
            value: null,
            colorOtherText: '',
            onChanged: (_) {},
            onOtherTextChanged: (_) {},
          ),
        ),
      );
      await tester.tap(find.text('他の色'));
      await tester.pumpAndSettle();

      expect(find.text('白い泡'), findsOneWidget);
      expect(find.text('赤'), findsOneWidget);
      expect(find.text('緑'), findsOneWidget);
      expect(find.text('黒'), findsOneWidget);
      expect(find.textContaining('その他(詳しく)'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('shows free-text field when "other" selected',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: VomitColorSelector(
            value: VomitColor.other,
            colorOtherText: '',
            onChanged: (_) {},
            onOtherTextChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('色を説明'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('auto-expands details when value is detail color',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: VomitColorSelector(
            value: VomitColor.red,
            colorOtherText: '',
            onChanged: (_) {},
            onOtherTextChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // valueがredなのでdetail色エリアが自動展開
      expect(find.text('赤'), findsOneWidget);
      expect(find.text('白い泡'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('triggers onChanged on color tap',
        (WidgetTester tester) async {
      VomitColor? captured;
      await tester.pumpWidget(
        wrapWithApp(
          child: VomitColorSelector(
            value: null,
            colorOtherText: '',
            onChanged: (VomitColor c) => captured = c,
            onOtherTextChanged: (_) {},
          ),
        ),
      );
      await tester.tap(find.text('黄'));
      expect(captured, VomitColor.yellow);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });
  });

  // ==========================================================================
  // VomitsRepository
  // ==========================================================================
  group('VomitsRepository', () {
    late AppDatabase db;
    late VomitsRepository repo;

    int now() => DateTime.now().toUtc().millisecondsSinceEpoch;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = VomitsRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('rejects color=other without text', () async {
      expect(
        () => repo.create(
          groupId: 'personal',
          petId: 1,
          color: VomitColor.other,
          colorOtherText: null,
          amount: RecordAmount.normal,
          count: 1,
          containsFood: false,
          suspectIngestion: false,
          vomitedAtMsec: now(),
        ),
        throwsArgumentError,
      );
    }, tags: <String>['needs_codegen']);

    test('rejects count < 1', () async {
      expect(
        () => repo.create(
          groupId: 'personal',
          petId: 1,
          color: VomitColor.yellow,
          amount: RecordAmount.normal,
          count: 0,
          containsFood: false,
          suspectIngestion: false,
          vomitedAtMsec: now(),
        ),
        throwsArgumentError,
      );
    }, tags: <String>['needs_codegen']);

    test('persists rev5.5 fields', () async {
      final int id = await repo.create(
        groupId: 'personal',
        petId: 1,
        color: VomitColor.other,
        colorOtherText: 'Orange',
        amount: RecordAmount.alot,
        count: 3,
        containsFood: true,
        suspectIngestion: true,
        vomitedAtMsec: now(),
      );
      final v = await repo.getById(id);
      expect(v, isNotNull);
      expect(v!.color, VomitColor.other);
      expect(v.colorOtherText, 'Orange');
      expect(v.count, 3);
      expect(v.containsFood, isTrue);
      expect(v.suspectIngestion, isTrue);
    }, tags: <String>['needs_codegen']);
  });

  // ==========================================================================
  // VomitFormController
  // ==========================================================================
  group('VomitFormController', () {
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

    test('updateColor clears colorOtherText when not "other"', () async {
      final petId = await createPet();
      await container.read(currentPetIdProvider.notifier).selectPet(petId);
      final ctrl = container.read(vomitFormControllerProvider(null).notifier);

      ctrl.updateColor(VomitColor.other);
      ctrl.updateColorOtherText('Orange');
      expect(
        container.read(vomitFormControllerProvider(null)).colorOtherText,
        'Orange',
      );

      // 別の色を選んだら自動でクリア
      ctrl.updateColor(VomitColor.yellow);
      expect(
        container.read(vomitFormControllerProvider(null)).colorOtherText,
        '',
      );
    }, tags: <String>['needs_codegen']);

    test('save creates vomit record with rev5.5 fields', () async {
      final petId = await createPet();
      await container.read(currentPetIdProvider.notifier).selectPet(petId);

      final ctrl = container.read(vomitFormControllerProvider(null).notifier);
      ctrl
        ..updateColor(VomitColor.yellow)
        ..updateAmount(RecordAmount.little)
        ..updateCount(2)
        ..updateContainsFood(true)
        ..updateSuspectIngestion(false);

      final r = await ctrl.save(l10n);
      expect(r, VomitFormSaveOutcome.success);

      final repo = VomitsRepository(db);
      final list = await repo.watchForPet(petId).first;
      expect(list.length, 1);
      expect(list.first.containsFood, isTrue);
      expect(list.first.count, 2);
    }, tags: <String>['needs_codegen']);
  });

  // ==========================================================================
  // VomitRecordScreen
  // ==========================================================================
  group('VomitRecordScreen', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('shows NEW VOMIT header', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithAppAndDb(db: db, child: const VomitRecordScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('新しい嘔吐'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    }, tags: <String>['needs_codegen']);
  });
}
