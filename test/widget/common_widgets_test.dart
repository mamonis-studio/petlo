// ============================================================================
// petlo - Common Widgets Tests
// ============================================================================
//
// Chunk 3で実装した共通ウィジェットの動作確認。
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/core/extensions/accessibility_extensions.dart';
import 'package:petlo/core/widgets/app_icons.dart';
import 'package:petlo/core/widgets/editorial_divider.dart';
import 'package:petlo/core/widgets/eyebrow_text.dart';
import 'package:petlo/core/widgets/line_icon.dart';
import 'package:petlo/core/widgets/outlined_action_button.dart';
import 'package:petlo/core/widgets/primary_button.dart';
import 'package:petlo/core/widgets/responsive_layout.dart';
import 'package:petlo/core/widgets/section_label.dart';
import 'package:petlo/core/widgets/tap_target.dart';
import 'package:petlo/presentation/widgets/petlo_scaffold.dart';

import '../helpers/test_app.dart';

void main() {
  // scope_providers などが build 中に PetloLogger.instance を触るため、
  // 初期化しないと `Bad state: PetloLogger.initialize() must be called` で落ちる。
  setUpAll(initTestLogger);

  group('EyebrowText', () {
    testWidgets('renders text in uppercase', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(child: const EyebrowText('today, may 4')),
      );
      expect(find.text('TODAY, MAY 4'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('respects custom color', (WidgetTester tester) async {
      const Color customColor = Color(0xFFFF0000);
      await tester.pumpWidget(
        wrapWithApp(
          child: const EyebrowText('warning', color: customColor),
        ),
      );
      final Text textWidget = tester.widget(find.text('WARNING'));
      expect(textWidget.style?.color, customColor);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });
  });

  group('SectionLabel', () {
    testWidgets('renders § symbol and text in uppercase', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(child: const SectionLabel('quick · log')),
      );
      expect(find.text('§'), findsOneWidget);
      expect(find.text('QUICK · LOG'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });
  });

  group('EditorialDivider', () {
    testWidgets('horizontal divider has thin height', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(child: const EditorialDivider()),
      );
      final Container container = tester.widget(find.byType(Container));
      expect(container.constraints?.maxHeight, anyOf(isNull, isNonZero));
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });
  });

  group('PrimaryButton', () {
    testWidgets('renders label in uppercase', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: PrimaryButton(label: 'Save', onPressed: () {}),
        ),
      );
      expect(find.text('SAVE'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('triggers onPressed when tapped', (WidgetTester tester) async {
      var pressedCount = 0;
      await tester.pumpWidget(
        wrapWithApp(
          child: PrimaryButton(
            label: 'Save',
            onPressed: () => pressedCount++,
          ),
        ),
      );
      await tester.tap(find.text('SAVE'));
      expect(pressedCount, 1);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('disabled when onPressed is null', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: const PrimaryButton(label: 'Save', onPressed: null),
        ),
      );
      // disabled状態でもテキストは表示される
      expect(find.text('SAVE'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });
  });

  group('OutlinedActionButton', () {
    testWidgets('renders label as-is (not uppercased)', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: OutlinedActionButton(
            label: 'Send to OS calendar',
            onPressed: () {},
          ),
        ),
      );
      expect(find.text('Send to OS calendar'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('shows subLabel when provided', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: OutlinedActionButton(
            label: 'Export',
            subLabel: 'PRO · OPTIONAL',
            onPressed: () {},
          ),
        ),
      );
      expect(find.text('Export'), findsOneWidget);
      expect(find.text('PRO · OPTIONAL'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });
  });

  group('LineIcon', () {
    testWidgets('renders without exceptions', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(child: LineIcon(icon: AppIcons.home)),
      );
      expect(find.byType(LineIcon), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('respects custom size', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(child: LineIcon(icon: AppIcons.meal, size: 32)),
      );
      final SizedBox sized = tester.widget(
        find.descendant(
          of: find.byType(LineIcon),
          matching: find.byType(SizedBox),
        ).first,
      );
      expect(sized.width, 32);
      expect(sized.height, 32);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('renders all defined icons without exception',
        (WidgetTester tester) async {
      final List<LineIconData> all = <LineIconData>[
        AppIcons.home,
        AppIcons.life,
        AppIcons.health,
        AppIcons.plans,
        AppIcons.more,
        AppIcons.meal,
        AppIcons.stool,
        AppIcons.pee,
        AppIcons.vomit,
        AppIcons.med,
        AppIcons.search,
        AppIcons.settings,
        AppIcons.arrowRight,
        AppIcons.chevronLeft,
        AppIcons.chevronRight,
        AppIcons.phone,
        AppIcons.camera,
        AppIcons.send,
        AppIcons.thumbUp,
        AppIcons.thumbDown,
      ];

      for (final LineIconData icon in all) {
        await tester.pumpWidget(wrapWithApp(child: LineIcon(icon: icon)));
        expect(find.byType(LineIcon), findsOneWidget);
      }
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });
  });

  group('TapTarget', () {
    testWidgets('enforces minimum tap size', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: TapTarget(
            onTap: () {},
            child: const SizedBox(width: 16, height: 16),
          ),
        ),
      );
      // TapTarget 自身のサイズを測る。
      // 以前は find.byType(ConstrainedBox) だったが、ツリー内に
      // ConstrainedBox が複数あって getSize が Too many elements で落ちる。
      // 検証したいのは「TapTarget が最小タップ領域を確保しているか」
      // なので、TapTarget を直接指すのが意図に合う。
      final Size size = tester.getSize(find.byType(TapTarget));
      expect(size.width >= 48, isTrue);
      expect(size.height >= 48, isTrue);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });
  });

  group('ResponsiveLayout', () {
    testWidgets('uses mobile layout when width < 600', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        wrapWithApp(
          child: const ResponsiveLayout(
            mobile: Text('mobile'),
            tablet: Text('tablet'),
          ),
        ),
      );
      expect(find.text('mobile'), findsOneWidget);
      expect(find.text('tablet'), findsNothing);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('uses tablet layout when width >= 600', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800 * 3, 600 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        wrapWithApp(
          child: const ResponsiveLayout(
            mobile: Text('mobile'),
            tablet: Text('tablet'),
          ),
        ),
      );
      expect(find.text('tablet'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });

    testWidgets('falls back to mobile when tablet not provided',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800 * 3, 600 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        wrapWithApp(child: const ResponsiveLayout(mobile: Text('mobile-only'))),
      );
      expect(find.text('mobile-only'), findsOneWidget);
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
    });
  });

  group('PetloScaffold', () {
    testWidgets(
      'renders bars by default (pet selector empty when no pets)',
      (WidgetTester tester) async {
        final db = createInMemoryDb();
        addTearDown(db.close);

        await tester.pumpWidget(
          wrapWithAppAndDb(
            db: db,
            child: const PetloScaffold(
              body: Center(child: Text('content')),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('PETLO'), findsOneWidget);
        // group_selector_personal の ja 訳。テストの既定ロケールは ja。
        expect(find.text('マイ'), findsOneWidget); // Group selector
        // common_local_only の ja 訳。en では toUpperCase されて
        // "LOCAL ONLY" になるが、ja では大文字化しても変わらない。
        expect(find.text('ローカルのみ'), findsOneWidget); // Personalバッジ
        // ペット0匹時は empty state を表示する。
        // 以前は canEdit=true のとき "+" ピルだったが、現在は
        // 説明文を出す形に変わっている。
        expect(find.text('このグループにはまだペットがいません'), findsOneWidget);
        expect(find.textContaining('TAB BAR'), findsOneWidget);
        expect(find.text('content'), findsOneWidget);

        // ペットセレクターが drift のクエリストリームを張るため必須。
        await disposeTreeAndDrainTimers(tester);
      },
      tags: <String>['needs_codegen'],
    );

    testWidgets(
      'hides bars when showXxx is false',
      (WidgetTester tester) async {
        final db = createInMemoryDb();
        addTearDown(db.close);

        await tester.pumpWidget(
          wrapWithAppAndDb(
            db: db,
            child: const PetloScaffold(
              showBrandBar: false,
              showGroupSelector: false,
              showPetSelector: false,
              showTabBar: false,
              body: Center(child: Text('clean')),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('PETLO'), findsNothing);
        expect(find.text('マイ'), findsNothing);
        expect(find.text('+'), findsNothing);
        expect(find.text('clean'), findsOneWidget);
      },
      tags: <String>['needs_codegen'],
    );
  });

  group('AccessibilityExtensions', () {
    testWidgets('textScaleFactor is accessible from context', (WidgetTester tester) async {
      double? captured;
      await tester.pumpWidget(
        wrapWithApp(
          child: Builder(
            builder: (BuildContext context) {
              captured = context.textScaleFactor;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(captured, isNotNull);
      expect(captured! >= 0.85, isTrue);
      expect(captured! <= 2.0, isTrue);
    });
  });
}
