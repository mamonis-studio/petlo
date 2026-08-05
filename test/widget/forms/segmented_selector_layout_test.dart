// ============================================================================
// petlo - SegmentedSelector レイアウト回帰テスト
// ============================================================================
//
// SegmentedSelector は Row + Expanded で全選択肢を必ず 1 行に詰める。
// 長いラベルが入ると、その子だけ 2 行に折り返して箱が縦に膨らむ。
// 予防コース画面ではこれで実害が出て _ChoiceChips に置き換えた。
//
// 残る利用箇所 (pet_form_screen 2箇所 / record_amount_selector) は
// ja のラベルが短いので今は見えていないだけで、翻訳次第で同じ崩れ方をする。
//
// ここで見るのは:
//   - 長いラベルでもオーバーフローしないこと
//   - セグメントの高さが揃うこと (1つだけ膨らまない)
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/presentation/widgets/forms/segmented_selector.dart';

import '../../helpers/test_app.dart';

void main() {
  setUpAll(initTestLogger);

  /// 同じ選択群のセグメント高さがすべて等しいこと。
  void expectUniformHeights(WidgetTester tester) {
    final List<double> heights = tester
        .widgetList<Text>(find.byType(Text))
        .toList()
        .asMap()
        .keys
        .map((int i) => 0.0)
        .toList();
    heights.clear();
    for (final Element e in find.byType(InkWell).evaluate()) {
      heights.add(tester.getSize(find.byWidget(e.widget)).height);
    }
    expect(heights, isNotEmpty);
    expect(
      heights.toSet().length,
      1,
      reason: 'セグメントの高さが揃っていない: $heights',
    );
  }

  testWidgets('短いラベル: 高さが揃う (現状の正常系)',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        child: SegmentedSelector<String>(
          label: 'Type',
          options: const <String>['犬', '猫'],
          value: '犬',
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expectUniformHeights(tester);
    await disposeTreeAndDrainTimers(tester);
  });

  testWidgets('長いラベル混在: 箱が膨らまない', (WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        child: SegmentedSelector<String>(
          label: 'Type',
          options: const <String>[
            'Dog',
            'Flea & tick prevention',
            'Cat',
          ],
          value: 'Dog',
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expectUniformHeights(tester);
    await disposeTreeAndDrainTimers(tester);
  });

  testWidgets('文字サイズ 200% + 長いラベル: オーバーフローしない',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: SegmentedSelector<String>(
            label: 'Type',
            options: const <String>[
              'Heartworm prevention',
              'Flea & tick prevention',
            ],
            value: null,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expectUniformHeights(tester);
    await disposeTreeAndDrainTimers(tester);
  });

  // ==========================================================================
  // 実際の利用箇所のラベルで固定する
  // ==========================================================================
  //
  // pet_form_screen (種別 / 性別) と record_amount_selector が
  // SegmentedSelector を使い続ける。どれも 2〜3 択で最長が "Unknown" (7字)
  // なので前提に収まっているが、翻訳が伸びたら気づけるようにしておく。
  //
  // 3 言語 x 文字サイズ 200% で、高さが揃うこと・省略が出ないことを見る。

  const Map<String, List<List<String>>> realLabels = <String, List<List<String>>>{
    'ja': <List<String>>[
      <String>['犬', '猫'],
      <String>['オス', 'メス', '不明'],
      <String>['少量', '普通', '多量'],
    ],
    'en': <List<String>>[
      <String>['Dog', 'Cat'],
      <String>['Male', 'Female', 'Unknown'],
      <String>['Little', 'Normal', 'A lot'],
    ],
    'zh': <List<String>>[
      <String>['狗', '猫'],
      <String>['公', '母', '未知'],
      <String>['少', '正常', '多'],
    ],
  };

  for (final MapEntry<String, List<List<String>>> loc in realLabels.entries) {
    for (int g = 0; g < loc.value.length; g++) {
      testWidgets('実ラベル ${loc.key}[$g]: 200% でも高さが揃い省略されない',
          (WidgetTester tester) async {
        final List<String> opts = loc.value[g];
        await tester.pumpWidget(
          wrapWithApp(
            locale: Locale(loc.key),
            child: MediaQuery(
              data: const MediaQueryData(
                textScaler: TextScaler.linear(2.0),
              ),
              child: SegmentedSelector<String>(
                label: 'L',
                options: opts,
                value: opts.first,
                onChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expectUniformHeights(tester);

        // 省略が起きていないこと。ellipsis は最後の安全網であって、
        // 実ラベルで発動しているなら設計側の問題。
        for (final String o in opts) {
          expect(
            find.text(o),
            findsOneWidget,
            reason: '$o が見つからない (省略された可能性)',
          );
          final RenderParagraph p = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.text(o),
              matching: find.byType(RichText),
              matchRoot: true,
            ),
          );
          expect(
            p.didExceedMaxLines,
            isFalse,
            reason: '$o が maxLines を超えて省略されている',
          );
        }
        await disposeTreeAndDrainTimers(tester);
      });
    }
  }
}
