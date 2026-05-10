// ============================================================================
// petlo - Smoke Test
// ============================================================================
//
// アプリが正常に起動し、最低限のUIが表示されるかを確認する。
// 後続Chunkで個別画面のテストを追加していく。
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/main.dart' as app;
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  group('Smoke test', () {
    testWidgets('PetloApp builds without errors', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: app.PetloApp(),
        ),
      );

      // プレースホルダー画面が表示される (Chunk 3 時点)
      expect(find.text('petlo'), findsOneWidget);
      expect(find.text('Implementation in progress'), findsOneWidget);
      // PetloScaffoldの brand bar
      expect(find.text('PETLO'), findsOneWidget);
    });

    testWidgets('App uses Material 3', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: app.PetloApp(),
        ),
      );

      final BuildContext context = tester.element(find.text('petlo'));
      final ThemeData theme = Theme.of(context);

      expect(theme.useMaterial3, isTrue);
    });
  });
}
