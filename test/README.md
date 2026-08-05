# petlo テスト規約

ウィジェットテストを書く前に読むこと。

ここに書いてあるのは全部、**実際に踏んで半日溶かした落とし穴**。
どれも共通の性質を持っている ——

> テストは緑になるが、何も検証していない。あるいは、
> 症状が原因からひどく離れたところに出る。

だから「動いたからいい」で済ませず、なぜそう書くのかまで書いておく。

---

## 1. 描画ロケールは ja に固定してある

`wrapWithApp` / `wrapWithAppAndDb` の `locale` の既定値は
`kTestDefaultLocale = Locale('ja')`。

**en / zh の挙動を見たいときだけ明示的に渡す。**

```dart
// 通常 (ja で描画される)
await tester.pumpWidget(wrapWithApp(child: const MyWidget()));

// en を検証したいとき
await tester.pumpWidget(
  wrapWithApp(child: const MyWidget(), locale: const Locale('en')),
);
```

### なぜ固定したのか

以前は `locale` を渡しておらず、`MaterialApp` は
**プラットフォームのロケール** を採用していた。
`flutter_test` の既定は `en_US` なので、
テストは全部 **黙って英語で描画されていた**。

実測値:

```
platformLocale  = en_US
localeOf(ctx)   = en
supportedLocales = [en, ja, zh]
```

この状態で日本語リテラルを検索すると当然落ちる。

```dart
expect(find.text('2 個まで'), findsOneWidget);  // 実際は "Up to 2" が描画されている
```

厄介なのは、これが **テストごとの指定漏れ** に見えることだった。
書いた本人には「なぜかこのテストだけ落ちる」としか映らない。
20 ファイル中 locale を明示していたのは 2 つだけで、
残りは全部この状態だった。

さらに悪いことに、**落ちないケースの方が多かった**。
テスト自身が渡した文字列 (`errorText: '選択してください'`、
ペット名など) は l10n を経由しないのでロケール非依存。
つまり「たまたま英語でも通る」テストに紛れて、
本物の依存が隠れていた。

要点は「en か ja か」ではなく、
**既定が環境依存だったこと**。環境が決めるのではなく、
こちらが決める形にした。

### 日本語リテラルを書くときの注意

l10n 由来の文言を検索するときは、**キーを ARB で確認してから**書く。
英語の見た目から推測すると外す。実例:

| 見えている英語 | 推測しがちなキー | 実際のキー |
|---|---|---|
| `Other` (嘔吐の色を開くボタン) | `vomit_color_other` (その他) | `vomit_color_more` (他の色) |
| `HEALTH` (タブ) | `pet_form_section_health` (健康情報) | `tab_health` (みまもる) |
| `OWNER` (ロールバッジ) | `group_detail_change_role_owner` | **l10n ではない**。英語ハードコード |

`toUpperCase()` されて描画される文言もある。
ja では大文字化しても変わらないので、
en の値だけ見て `'CANCEL'` のまま残さないこと。

---

## 2. testWidgets の末尾に `disposeTreeAndDrainTimers(tester)` を入れる

```dart
testWidgets('...', (WidgetTester tester) async {
  final db = createInMemoryDb();
  addTearDown(db.close);

  await tester.pumpWidget(wrapWithAppAndDb(db: db, child: const Foo()));
  await tester.pumpAndSettle();

  expect(...);

  await disposeTreeAndDrainTimers(tester);   // ← これ
});
```

### なぜ必要か

タイマーを張るものが 2 つある。

- **drift のクエリストリーム** — 最後のリスナーが外れても
  しばらくストリームを生かしておくためのタイマー
- **`SyncService.scheduleDebouncedSync`** — 2.5 秒のデバウンス。
  リポジトリに書き込むと発火する

ウィジェットツリーを破棄しただけではこれらが残り、
テスト本体が全部成功していても
`A Timer is still pending even after the widget tree was disposed.`
で落ちる。

**ここからが本題。** この状態のテストは
**10 分のテストタイムアウトまで解放されない**。
そして次のテストが `!inTest` で道連れになる。

つまり画面には

```
-2: PetloScaffold renders bars ... [E]
-2: PetloScaffold hides bars ...   [E]     ← 巻き添え。無実
10:02 Some tests failed.
```

としか出ない。「無関係なテストが 2 件落ちている」ようにしか見えず、
真犯人が 1 件のタイマーだと気づけない。

スイート全体が 10 分かかっていた原因はこれで、
入れた後は **19 秒** になった。

### やってはいけない対処

`await db.close()` を **テスト本体で待ってはいけない**。
テストバインディングの疑似時計では完了せず、デッドロックする。
`tester.runAsync` 経由でも同じ。

```dart
await db.close();                    // ✗ ハングする
await tester.runAsync(db.close);     // ✗ これもハングする
```

DB の後始末は `addTearDown(db.close)` に任せ、
タイマーは疑似時計を進めて消化する。それが
`disposeTreeAndDrainTimers` の中身:

```dart
await tester.pumpWidget(const SizedBox.shrink());
await tester.pump(const Duration(seconds: 5));
```

---

## 3. 実時計が要る処理は `tester.runAsync` で囲む

```dart
// ✗ 永久にハングする
for (int i = 0; i < 5; i++) {
  await repo.upsertByName(name: 'Food $i');
  await Future<void>.delayed(const Duration(milliseconds: 5));
}

// ✓
await tester.runAsync(() async {
  for (int i = 0; i < 5; i++) {
    await repo.upsertByName(name: 'Food $i');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
});
```

`testWidgets` の中は疑似時計。誰も時計を進めない限り
`Future.delayed` は完了しない。
2 と同じく 10 分のタイムアウトまで解放されず、後続を巻き添えにする。

素の `test(...)` (ウィジェットを使わないユニットテスト) は
実時計なのでそのままでよい。混在しているファイルがあるので注意。

---

## 4. 画面外のウィジェットへの tap は「警告だけ」で通る

**これが一番たちが悪い。**

```dart
await tester.tap(find.text('保存'));
await tester.pumpAndSettle();
expect(find.textContaining('銘柄'), findsOneWidget);   // 0 件で落ちる
```

保存ボタンはフォーム末尾にあり、
既定のテスト画面 (800x600) では `y=1093`、つまり画面外にいる。
`tester.tap` はこれを **警告** としか扱わない:

```
Warning: A call to tap() with finder "..." derived an Offset (Offset(400.0, 1093.0))
that would not hit test on the specified widget.
```

警告はテスト失敗にならない。**tap は何も起こさず素通りする。**
結果として症状は「バリデーションエラーが表示されない」に見え、
アプリ側のバグを疑って時間を溶かすことになる。

さらに、この警告は `flutter test` の出力に埋もれる。
`| tail -1` などで絞っていると存在にすら気づかない。

### 対処

`ensureVisible` は効かないことがある (実際に効かなかった)。
確実なのは画面自体を広げること。

```dart
testWidgets('...', (WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(...);
  ...
});
```

`addTearDown` でのリセットを忘れないこと。忘れると
後続のテストが広い画面のまま走り、
レイアウト崩れの検証が意味を失う。

### 予防

フォーム末尾のボタンを押すテストを書いたら、
**一度わざと期待値を外して落としてみる**。
落ちなければ tap が効いていない。

---

## 5. `PetloLogger` の初期化

```dart
void main() {
  setUpAll(initTestLogger);
  ...
}
```

`scope_providers` / `pet_edit_hint_provider` などが
build 中に `PetloLogger.instance` を触るため、
初期化しないと
`Bad state: PetloLogger.initialize() must be called before accessing instance`
で落ちる。`initTestLogger` は冪等。

---

## 6. Semantics の検証は `containsSemantics` を使う

```dart
// ✗ SDK が action を足すたびに落ちる
expect(node, matchesSemantics(isSelected: true, isButton: true, hasTapAction: true));

// ✗ SemanticsData.hasFlag は flagsCollection (Tristate) に置き換わった
expect(node.getSemanticsData().hasFlag(SemanticsFlag.isSelected), isTrue);

// ✓ 部分一致。フラグの内部表現にも依存しない
expect(node, containsSemantics(isSelected: true, isButton: true, hasTapAction: true));
```

`matchesSemantics` は「列挙した属性と完全一致」を要求する。
Flutter が新しい action (`focus` など) を足しただけで落ちる。
ラベルの部分一致を見たいときは分離する:

```dart
expect(node, containsSemantics(isSelected: true));
expect(node.label, contains('Hana'));   // label に Matcher は渡せなくなった
```

---

## 7. 自前で `MaterialApp` を組まない

```dart
// ✗ AppColors.of() が投げる。l10n デリゲートも入らない
return UncontrolledProviderScope(
  container: container,
  child: const MaterialApp(home: Scaffold(body: MyWidget())),
);

// ✓
return wrapWithApp(container: container, child: const MyWidget());
```

素の `MaterialApp` にはテーマ (`AppColors` extension) が入らないので、
`AppColors.of(context)` が
`AppColors extension not found in current Theme` を投げる。
ロケールも 1 の既定が効かなくなる。

`ProviderContainer` を先に作って状態を仕込みたい場合は
`wrapWithApp(container: ...)` を使う。

---

## 8. Free / Pro のゲーティングに注意

build 71 で Free プランの上限が入った (`AppConstants.freeMaxPets = 1`)。
2 匹目以降を扱うテストは、本来見たい分岐より先に
`proLimitReached` が返る。

```dart
container = ProviderContainer(
  overrides: <Override>[
    appDatabaseProvider.overrideWithValue(db),
    isProProvider.overrideWithValue(true),
  ],
);
```

---

## 9. drift の `Value`

`Companion.insert` に渡す省略可能フィールドは `Value` で包む。

```dart
import 'package:drift/drift.dart' hide isNull, isNotNull;

PetsCompanion.insert(
  groupId: const Value('personal'),
  name: 'Taro',
  type: PetType.dog,
  breed: const Value('shiba'),   // 省略可能 → Value 必須
  sex: const Value(PetSex.male),
  createdAt: t,
  updatedAt: t,
)
```

`drift/native.dart` だけでは `Value` は入ってこない。
`hide isNull, isNotNull` は `flutter_test` の同名マッチャーとの衝突回避。

**リポジトリのメソッド (`repo.createPet(...)`) は Companion ではない。**
そちらは素の値を渡す。一括置換で両方まとめて包むと壊れる (実際に壊した)。

---

## 迷ったときの原則

今日直したバグは、アプリ側もテスト側も同じ形をしていた:

> **「値が無い」ことから状態を推測しない。**

- `groups.isEmpty` から「初回起動だ」と推測 → 圏外でも初回扱い
- `pending()` が空だから「通知が無い」と推測 → 実は例外で落ちていた
- `s.isEditing` が false だから「新規作成だ」と推測 → ロード前だっただけ
- テストが緑だから「検証できている」と推測 → 英語で描画されていた

判定に使う情報は、推測ではなく **明示的に持たせる**。
テストなら、期待値を一度わざと外して
「落ちること」を確認するのが一番確実な検算になる。
