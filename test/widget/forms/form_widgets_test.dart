// ============================================================================
// petlo - Form Widgets Tests
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/presentation/widgets/forms/editorial_text_field.dart';
import 'package:petlo/presentation/widgets/forms/segmented_selector.dart';
import 'package:petlo/presentation/widgets/forms/tag_input_field.dart';

import '../../helpers/test_app.dart';

void main() {
  // ==========================================================================
  // EditorialTextField
  // ==========================================================================
  group('EditorialTextField', () {
    testWidgets('renders label and hint', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: const EditorialTextField(
            label: 'Pet name',
            hint: 'Taro',
          ),
        ),
      );
      expect(find.text('PET NAME'), findsOneWidget);
      expect(find.text('Taro'), findsOneWidget);
    });

    testWidgets('shows asterisk when required', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: const EditorialTextField(label: 'Name', required: true),
        ),
      );
      expect(find.text('*'), findsOneWidget);
    });

    testWidgets('shows errorText when provided', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: const EditorialTextField(
            label: 'Name',
            errorText: 'Required',
          ),
        ),
      );
      expect(find.text('Required'), findsOneWidget);
    });

    testWidgets('hides helperText when error present',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: const EditorialTextField(
            label: 'Name',
            helperText: 'Helper',
            errorText: 'Error',
          ),
        ),
      );
      expect(find.text('Error'), findsOneWidget);
      expect(find.text('Helper'), findsNothing);
    });

    testWidgets('triggers onChanged', (WidgetTester tester) async {
      String? captured;
      await tester.pumpWidget(
        wrapWithApp(
          child: EditorialTextField(
            label: 'Name',
            onChanged: (String v) => captured = v,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'hello');
      expect(captured, 'hello');
    });

    testWidgets('shows suffix text', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: const EditorialTextField(
            label: 'Weight',
            suffixText: 'kg',
          ),
        ),
      );
      expect(find.text('kg'), findsOneWidget);
    });
  });

  // ==========================================================================
  // SegmentedSelector
  // ==========================================================================
  group('SegmentedSelector', () {
    testWidgets('renders all options', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: SegmentedSelector<String>(
            label: 'Sex',
            options: const <String>['male', 'female', 'unknown'],
            value: 'male',
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('male'), findsOneWidget);
      expect(find.text('female'), findsOneWidget);
      expect(find.text('unknown'), findsOneWidget);
    });

    testWidgets('triggers onChanged when tapped',
        (WidgetTester tester) async {
      String? selected;
      await tester.pumpWidget(
        wrapWithApp(
          child: SegmentedSelector<String>(
            label: 'Sex',
            options: const <String>['male', 'female'],
            value: 'male',
            onChanged: (String v) => selected = v,
          ),
        ),
      );

      await tester.tap(find.text('female'));
      expect(selected, 'female');
    });

    testWidgets('uses optionLabel mapper', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: SegmentedSelector<int>(
            label: 'Score',
            options: const <int>[1, 2, 3],
            value: 2,
            optionLabel: (int n) => 'Level $n',
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('Level 1'), findsOneWidget);
      expect(find.text('Level 2'), findsOneWidget);
      expect(find.text('Level 3'), findsOneWidget);
    });

    testWidgets('shows error text', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: SegmentedSelector<String>(
            label: 'Sex',
            options: const <String>['a', 'b'],
            value: null,
            errorText: '選択してください',
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('選択してください'), findsOneWidget);
    });
  });

  // ==========================================================================
  // TagInputField
  // ==========================================================================
  group('TagInputField', () {
    testWidgets('starts with empty tag list', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: TagInputField(
            label: 'Allergies',
            tags: const <String>[],
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('ALLERGIES'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('renders existing tags', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: TagInputField(
            label: 'Allergies',
            tags: const <String>['鶏肉', '小麦'],
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('鶏肉'), findsOneWidget);
      expect(find.text('小麦'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNWidgets(2));
    });

    testWidgets('adds new tag on submit', (WidgetTester tester) async {
      List<String>? captured;
      await tester.pumpWidget(
        wrapWithApp(
          child: TagInputField(
            label: 'Tags',
            tags: const <String>[],
            onChanged: (List<String> v) => captured = v,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '新タグ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(captured, <String>['新タグ']);
    });

    testWidgets('removes tag on close icon tap',
        (WidgetTester tester) async {
      List<String>? captured;
      await tester.pumpWidget(
        wrapWithApp(
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return TagInputField(
                label: 'Tags',
                tags: const <String>['A', 'B'],
                onChanged: (List<String> v) {
                  captured = v;
                },
              );
            },
          ),
        ),
      );

      // 最初のタグの×をタップ
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();

      expect(captured, <String>['B']);
    });

    testWidgets('rejects duplicates', (WidgetTester tester) async {
      List<String>? captured;
      await tester.pumpWidget(
        wrapWithApp(
          child: TagInputField(
            label: 'Tags',
            tags: const <String>['existing'],
            onChanged: (List<String> v) => captured = v,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'existing');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(captured, isNull); // onChanged は呼ばれない
    });

    testWidgets('disables input at maxTags', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          child: TagInputField(
            label: 'Tags',
            tags: const <String>['a', 'b'],
            maxTags: 2,
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('2 個まで'), findsOneWidget);
      // TextFieldが非活性
      final TextField tf = tester.widget(find.byType(TextField));
      expect(tf.enabled, isFalse);
    });
  });
}
