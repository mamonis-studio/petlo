# Changelog

All notable changes to petlo will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Implementation in progress (rev5.5 spec)

#### ソース実装ステータス: 仕様書 Phase 1〜5 相当の機能ファイルが配置済み(Chunk 1-24)
#### ビルド可能性: 未達成(コード生成・L10n生成・アセット配置が未実施)

仕様書 §11 の Phase 区分では Phase 1 は「コア機能 + 基盤(6.5週)」のみを指す。
以下の Chunk 1-24 は実際には仕様書の Phase 1 〜 Phase 5(コア + 健康 + AI + 家族共有 + 課金/バックアップ)に相当する。

##### 実装ファイルが配置済みの Chunk
- [x] Chunk 1: プロジェクト初期化 + ディレクトリ構造
- [x] Chunk 2: デザイントークン + テーマ (Light/Dark)
- [x] Chunk 3: アクセシビリティ基盤 + 共通ウィジェット
- [x] Chunk 4: drift全28テーブル定義 + マイグレーション基盤
- [x] Chunk 5: Riverpod Provider基盤 (scope/db/storage/connectivity/repository)
- [x] Chunk 6: ペットセレクターバー (rev5.1 F-00)
- [x] Chunk 7: グループセレクター (rev5.3) — 3階層トップバー完成
- [x] Chunk 8: ペット登録/編集画面 (フォーム部品 + 写真選択 + 同名警告)
- [x] Chunk 9: ご飯記録 + foodsマスタ (rev3 F-01) — 直近3銘柄UI
- [x] Chunk 10: うんち/おしっこ/嘔吐記録 (rev5.5 嘔吐2階層色)
- [x] Chunk 11: 体重 / 体温 (kg-lb / ℃-℉ 切替 + ペット種別の正常範囲)
- [x] Chunk 12: 通院 / ワクチン (rev3 F-07/F-08, multi-photo support)
- [x] Chunk 13: 日記 / 写真ギャラリー (rev3 F-08, fullscreen viewer)
- [x] Chunk 14: 5タブ構造 (Home / Life / Health / Plans / More)
- [x] Chunk 15: カレンダー (rev5.2 月表示UI + dot indicators + 日付詳細)
- [x] Chunk 16: グラフ (rev3 F-06/F-07, fl_chart, Pro lock UI)
- [x] Chunk 17: リマインダー (rev3 F-13, ローカル通知 + ワクチン期限通知 + 起動時再スケジュール + Plans/More統合)
- [x] Chunk 18: AI機能 (rev3 F-18/F-21/F-22, F-23a/b/c プロンプトインジェクション対策 + thinking ドット + オフライン対応)
- [x] Chunk 19: Settings系 (テーマ切替 + 言語案内 + About + Privacy/Terms)
- [x] Chunk 20: 課金 (IAP実装、Pro機能ロック解除、Paywall + 月額/年額/トライアル + Restore)
- [x] Chunk 21: 家族共有 (グループ作成 + 6桁招待コード + メンバー管理 + 退出 + 同名警告)
- [x] Chunk 22: バックアップ (設定画面 + F-79警告バナー + 30日抑止、クラウド連携プレビュー版)
- [x] Chunk 23: オンボーディング (Welcome/Pillars/PetForm/Done 4ページ + 起動時ルーティング)
- [x] Chunk 24: E2E + 仕上げ (F-80 Pro解約30日カウントダウン + Developer隠しメニュー + 最終調整)

##### Phase D: L10n フル日本語化 ✅ 完走 (2026-05-06)
- [x] 全 5 タブバー(HOME→ホーム / LIFE→くらし / HEALTH→健康 / PLANS→予定 / MORE→その他)
- [x] オンボーディング 4 ページ全文(Welcome / Pillars / PetForm / Done)
- [x] 5 タブ画面(Home / Life / Health / Plans / More)の eyebrow / ヒーロー / セクション / 空状態 / CTA
- [x] PetForm 全画面(AppBar / Eyebrow / フィールドラベル / hint / SnackBar / Dialog)
- [x] Group 4 画面(GroupsList / GroupDetail / CreateGroup / JoinByCode)
- [x] Settings 5 画面(Theme / Language / About / Developer / Backup)
- [x] Record 9 画面(Meal / Poop / Pee / Vomit / Weight / Temperature / Visit / Vaccination / Diary)
- [x] AI Chat / Paywall / Medication Reminder / Gallery
- [x] enum 値の表示文字列(PetType / PetSex / PoopForm / PoopColor / VomitColor / MealAppetite / MemberPermission / GroupStatus / SyncStatus 等)
- [x] AppBar title 全 22 種(GROUPS→グループ / WEIGHT→体重 / VOMIT→嘔吐 等)
- [x] SnackBar 全文言(en/zh ロケール時の日本語残存問題を完全解消)
- [x] Pet selector / Group selector / Brand bar
- [x] **方針**: ヒーロー Fraunces italic 単語型(`petlo` / `Groups.` / `More.` / `Reminders.` / `Developer.`)+ 固有名詞(`mamonis.studio` / `X / INSTAGRAM / TIKTOK`)+ 単位(`kg / g / °C`)のみ英字維持、それ以外は全部日本語化
- [x] **ARB 規模**: en/ja/zh × 約 600 キー = 約 1,800 ARB エントリ
- [x] **生成ゲッター**: 607
- [x] **lib/ analyze error**: 0 件維持
- [x] **残ハードコード**: EyebrowText/SectionLabel = 0 件、AppBar title 大文字 = 0 件、SnackBar ベタ書き = 0 件

##### 未着手・未確認 (ビルド・リリースには必須)
- [ ] **コード生成**: `*.g.dart` / `*.freezed.dart` が一度も生成されていない (drift / freezed / riverpod_generator)
- [ ] **L10n 生成**: `lib/l10n/generated/` 未作成。`main.dart` の `app_localizations.dart` import は現状解決不能
- [ ] **L10n キー**: ARB は en=14 / ja=16 / zh=14 とパリティ崩れ + 95機能アプリには明らかに少なすぎる
- [ ] **アセット**: `assets/fonts/` 14本の .ttf、`assets/data/breeds_dogs.json` / `breeds_cats.json`、`assets/images/` がすべて空
- [ ] **DAO 層**: `lib/data/local/daos/` が空 (リポジトリ直叩き設計か、未実装かの確認が必要)
- [ ] **リモート層**: `lib/data/remote/` が空 (Cloudflare Workers クライアント未着手)
- [ ] **仕様書 Phase 6**: ホーム画面ウィジェット (2.5週)
- [ ] **仕様書 Phase 7**: アクセシビリティ仕上げ (2.2週)
- [ ] **仕様書 Phase 8**: 申請準備 (1.7週)
- [ ] **静的解析・テスト**: `flutter analyze` / `flutter test` の clean run 未確認

## [0.1.0] - TBD

### Added
- Initial release with Phase 1-8 features (rev5.5 spec)
- 5本柱機能完備
- 日本語/英語/簡体字中国語UI
- 全世界配信、AI動的多言語対応
