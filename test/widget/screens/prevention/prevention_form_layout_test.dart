// ============================================================================
// petlo - Prevention Course Form Layout Tests
// ============================================================================
//
// 予防コース作成画面のレイアウト回帰。
//
// 元の不具合: 種別 (3択) と剤型 (4択) を SegmentedSelector (Row + Expanded) で
// 描いていたため、長いラベルが 2 行に折り返した子だけ箱が縦に膨らみ、
// 左右の要素に食い込んでいた。Wrap ベースのチップに統一して解消した。
//
// ここで見るのは:
//   - オーバーフロー (RenderFlex overflow) が出ないこと
//   - 同じ選択群のチップの高さが揃うこと
//   - ラベルが省略 (ellipsis) されないこと
//   - ja / en / zh すべてで成り立つこと。特に英語は語長が違う
//
// 注意: 画面が drift のクエリストリームを張るため、テスト本体の最後で
// ツリーを畳んでタイマーを消化する必要がある (withForm が面倒を見る)。
// tearDown では間に合わない。保留タイマーの検査が先に走るため。
//
// ============================================================================

@Tags(<String>['needs_codegen'])
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/core/preferences/user_preferences.dart';
import 'package:petlo/core/theme/app_dimensions.dart';
import 'package:petlo/core/utils/logger.dart';
import 'package:petlo/data/local/app_database.dart';
import 'package:petlo/l10n/generated/app_localizations.dart';
import 'package:petlo/presentation/providers/database_provider.dart';
import 'package:petlo/presentation/screens/prevention/prevention_course_form_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/test_app.dart';

void main() {
  // アプリのプロバイダ群 (scope_providers など) が build 中に
  // PetloLogger.instance を触るため、初期化しないと落ちる。
  setUpAll(initTestLogger);

  late AppDatabase db;

  // 画面が currentPetIdProvider → PetloLogger / SharedPreferences を触るため
  // 先に初期化する。ここが未初期化だとレイアウト以前に落ちる。
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await PetloLogger.initialize();
    await UserPreferences.instance.initialize();
  });

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // ペットが 0 件だと _PetSelector 自体が描画されない (正しい挙動) ので、
    // pets + pet_scopes に 1 匹用意する。scope 経由で引かれるため両方必要。
    final int t = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.customStatement(
      'INSERT INTO pets (name, type, group_id, sync_status, '
      'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      <Object?>['ぽち', 'dog', 'personal', 'synced', t, t],
    );
    await db.customStatement(
      'INSERT INTO pet_scopes (pet_id, group_id, permission, is_primary, '
      'shared_at, sync_status, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[1, 'personal', 'owner', 1, t, 'synced', t, t],
    );
  });

  tearDown(() async {
    await db.close();
  });

  /// フォームを描画し、[body] で検証し、最後にツリーを畳む。
  Future<void> withForm(
    WidgetTester tester,
    Locale locale,
    Future<void> Function(AppLocalizations l10n) body, {
    double textScale = 1.0,
  }) async {
    await tester.pumpWidget(
      wrapWithApp(
        locale: locale,
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: Builder(
          builder: (BuildContext context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: const PreventionCourseFormScreen(),
          ),
        ),
      ),
    );
    // pumpAndSettle は drift のストリームで settle しきらないので固定回数
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await body(lookupAppLocalizations(locale));

    // drift のストリーム破棄が仕掛けるタイマーを消化してから抜ける
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// ラベルを持つチップの箱の高さ
  List<double> chipHeights(WidgetTester tester, List<String> labels) {
    final List<double> out = <double>[];
    for (final String l in labels) {
      final Finder f = find.text(l);
      if (f.evaluate().isEmpty) continue;
      final Finder box =
          find.ancestor(of: f, matching: find.byType(Container));
      if (box.evaluate().isEmpty) continue;
      out.add(tester.getSize(box.first).height);
    }
    return out;
  }

  Finder textLike(String s) => find.byWidgetPredicate((Widget w) =>
      w is Text && (w.data ?? '').toLowerCase() == s.toLowerCase());

  const List<Locale> locales = <Locale>[
    Locale('ja'),
    Locale('en'),
    Locale('zh'),
  ];

  for (final Locale locale in locales) {
    final String lang = locale.languageCode;

    group('locale=$lang', () {
      testWidgets('オーバーフローせずに描画できる', (WidgetTester tester) async {
        await withForm(tester, locale, (AppLocalizations l10n) async {
          // RenderFlex overflow は tester が例外として拾う
          expect(tester.takeException(), isNull);
        });
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
      });

      testWidgets('種別チップの高さが揃う', (WidgetTester tester) async {
        await withForm(tester, locale, (AppLocalizations l10n) async {
          final List<double> hs = chipHeights(tester, <String>[
            l10n.prevention_kind_filaria,
            l10n.prevention_kind_flea_tick,
            l10n.prevention_kind_combo,
          ]);
          expect(hs, hasLength(3));
          expect(hs.toSet(), hasLength(1),
              reason: '長いラベルの子だけ膨らんではいけない: $hs');
        });
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
      });

      testWidgets('剤型チップの高さが揃う', (WidgetTester tester) async {
        await withForm(tester, locale, (AppLocalizations l10n) async {
          final List<double> hs = chipHeights(tester, <String>[
            l10n.prevention_form_chewable,
            l10n.prevention_form_tablet,
            l10n.prevention_form_spot_on,
            l10n.prevention_form_injection,
          ]);
          expect(hs, hasLength(4));
          expect(hs.toSet(), hasLength(1), reason: '高さが不揃い: $hs');
        });
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
      });

      testWidgets('等倍ではラベルが実際に省略されない', (WidgetTester tester) async {
        // ellipsis は「200% 等で入り切らないときの最後の安全網」であり、
        // 通常サイズで発動してはいけない。設定値ではなく実測で見る。
        await withForm(tester, locale, (AppLocalizations l10n) async {
          final double pageWidth =
              tester.getSize(find.byType(Scaffold).first).width -
                  AppDimensions.paddingPage * 2;
          for (final String label in <String>[
            l10n.prevention_kind_filaria,
            l10n.prevention_kind_flea_tick,
            l10n.prevention_kind_combo,
            l10n.prevention_form_chewable,
            l10n.prevention_form_injection,
          ]) {
            final Finder f = find.text(label);
            expect(f, findsOneWidget, reason: '$label が見つからない');
            expect(tester.widget<Text>(f).maxLines, 1);

            // 上限に触れていない = 切り詰めが起きていない
            final Finder box =
                find.ancestor(of: f, matching: find.byType(Container));
            expect(
              tester.getSize(box.first).width,
              lessThan(pageWidth),
              reason: '$label のチップが利用可能幅いっぱいで、省略の恐れがある',
            );
          }
        });
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
      });

      testWidgets('文字サイズ 200% でもオーバーフローしない',
          (WidgetTester tester) async {
        // Dynamic Type を上げた端末で、チップ 1 個が親の幅を超えるケース。
        // Wrap は次の行へ送れないので、maxWidth 制約 + ellipsis で受ける。
        await withForm(
          tester,
          locale,
          (AppLocalizations l10n) async {
            expect(tester.takeException(), isNull);

            final double pageWidth =
                tester.getSize(find.byType(Scaffold).first).width -
                    AppDimensions.paddingPage * 2;
            for (final String label in <String>[
              l10n.prevention_kind_filaria,
              l10n.prevention_kind_flea_tick,
              l10n.prevention_kind_combo,
              l10n.prevention_form_chewable,
              l10n.prevention_form_tablet,
              l10n.prevention_form_spot_on,
              l10n.prevention_form_injection,
            ]) {
              final Finder f = find.text(label);
              if (f.evaluate().isEmpty) continue;
              final Finder box =
                  find.ancestor(of: f, matching: find.byType(Container));
              expect(
                tester.getSize(box.first).width,
                lessThanOrEqualTo(pageWidth + 0.5),
                reason: '$label のチップが親の幅を超えている',
              );
            }
          },
          textScale: 2.0,
        );
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
      });

      testWidgets('文字サイズ 200% でもチップの高さは揃う',
          (WidgetTester tester) async {
        await withForm(
          tester,
          locale,
          (AppLocalizations l10n) async {
            final List<double> hs = chipHeights(tester, <String>[
              l10n.prevention_form_chewable,
              l10n.prevention_form_tablet,
              l10n.prevention_form_spot_on,
              l10n.prevention_form_injection,
            ]);
            expect(hs, hasLength(4));
            expect(hs.toSet(), hasLength(1), reason: '高さが不揃い: $hs');
          },
          textScale: 2.0,
        );
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
      });

      testWidgets('修正後の見出しが出ている', (WidgetTester tester) async {
        await withForm(tester, locale, (AppLocalizations l10n) async {
          expect(textLike(l10n.prevention_pet_label), findsWidgets,
              reason: 'ペットの見出し');
          expect(textLike(l10n.prevention_kind_label), findsWidgets,
              reason: '予防の種類の見出し');
          expect(textLike(l10n.prevention_form_label), findsWidgets,
              reason: '剤型の見出し');
          expect(textLike(l10n.prevention_period_start_label), findsWidgets,
              reason: '開始の見出し');
          expect(textLike(l10n.prevention_period_end_label), findsWidgets,
              reason: '終了の見出し');
        });
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
      });

      testWidgets('通知トグルと時刻ピッカーが別々に出る', (WidgetTester tester) async {
        await withForm(tester, locale, (AppLocalizations l10n) async {
          // 以前は両方 prevention_time_label で同じ見出しが 2 つ出ていた
          expect(textLike(l10n.prevention_notification_enabled_label),
              findsOneWidget);
          expect(textLike(l10n.prevention_time_label), findsOneWidget);

          // 時刻ピッカーの現在値 (既定 09:00) が出ていて、タップできる
          expect(find.text('09:00'), findsOneWidget,
              reason: 'notifyTime を変更する手段が画面に無い');
          expect(
            find.ancestor(
              of: find.text('09:00'),
              matching: find.byType(InkWell),
            ),
            findsWidgets,
          );
        });
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
      });

      testWidgets('期間ステッパーの値に月の単位が付く', (WidgetTester tester) async {
        await withForm(tester, locale, (AppLocalizations l10n) async {
          // 既定は関東プリセット = 5月〜12月
          expect(
            find.text(
                l10n.prevention_month_value(lang == 'en' ? 'May' : '5')),
            findsWidgets,
          );
          expect(
            find.text(
                l10n.prevention_month_value(lang == 'en' ? 'Dec' : '12')),
            findsWidgets,
          );
        });
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
      });

      testWidgets('検査日の未入力表示が「未実施」相当になる',
          (WidgetTester tester) async {
        await withForm(tester, locale, (AppLocalizations l10n) async {
          expect(find.text(l10n.prevention_test_date_empty), findsOneWidget);
        });
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
      });

      testWidgets('免責文が 2 つとも常設表示されている (v2 §9)',
          (WidgetTester tester) async {
        await withForm(tester, locale, (AppLocalizations l10n) async {
          expect(
              find.text(l10n.prevention_disclaimer_period), findsOneWidget);
          expect(find.text(l10n.prevention_disclaimer_test), findsOneWidget);
        });
      // drift のクエリストリームと SyncService の debounce タイマーを消化する。
      await disposeTreeAndDrainTimers(tester);
      });
    });
  }
}
