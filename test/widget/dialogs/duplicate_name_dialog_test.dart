// ============================================================================
// petlo - DuplicateNameDialog Tests
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/presentation/widgets/dialogs/duplicate_name_dialog.dart';

import '../../helpers/test_app.dart';

void main() {
  group('DuplicateNameDialog', () {
    Future<bool?> openDialog(WidgetTester tester) async {
      bool? result;

      await tester.pumpWidget(
        wrapWithApp(
          child: Builder(
            builder: (BuildContext context) => Center(
              child: TextButton(
                onPressed: () async {
                  result = await showDuplicateNameDialog(
                    context: context,
                    petName: 'Taro',
                    groupDisplayName: 'お父さん家族',
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      return result;
    }

    testWidgets('shows pet name and group name', (WidgetTester tester) async {
      await openDialog(tester);

      expect(find.textContaining('"Taro"'), findsOneWidget);
      expect(find.textContaining('お父さん家族'), findsOneWidget);
      expect(find.text('NAME CONFLICT'), findsOneWidget);
      expect(find.text('Two pets, same name?'), findsOneWidget);
    });

    testWidgets('returns true when user taps "GOT IT, CONTINUE"',
        (WidgetTester tester) async {
      bool? captured;

      await tester.pumpWidget(
        wrapWithApp(
          child: Builder(
            builder: (BuildContext context) => Center(
              child: TextButton(
                onPressed: () async {
                  captured = await showDuplicateNameDialog(
                    context: context,
                    petName: 'Taro',
                    groupDisplayName: 'Group',
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('GOT IT, CONTINUE'));
      await tester.pumpAndSettle();

      expect(captured, isTrue);
    });

    testWidgets('returns false when user taps CANCEL',
        (WidgetTester tester) async {
      bool? captured;

      await tester.pumpWidget(
        wrapWithApp(
          child: Builder(
            builder: (BuildContext context) => Center(
              child: TextButton(
                onPressed: () async {
                  captured = await showDuplicateNameDialog(
                    context: context,
                    petName: 'Taro',
                    groupDisplayName: 'Group',
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();

      expect(captured, isFalse);
    });

    testWidgets('cannot dismiss by tapping outside (barrierDismissible: false)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: Builder(
            builder: (BuildContext context) => Center(
              child: TextButton(
                onPressed: () => showDuplicateNameDialog(
                  context: context,
                  petName: 'Taro',
                  groupDisplayName: 'Group',
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('NAME CONFLICT'), findsOneWidget);

      // 画面の隅をタップ
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // ダイアログはまだ表示中
      expect(find.text('NAME CONFLICT'), findsOneWidget);
    });
  });
}
