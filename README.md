# petlo

> うちの子のすべて、家族とAIで見守る — A pet life log app for dogs and cats.

**Status**: v1.0 implementation in progress (~8.8 months total)
**Bundle ID**: `mamonis.studio.petlo`
**Platform**: iOS / iPadOS / Android (+ Apple Watch / Wear OS notification only)

## 概要

petloは犬・猫の日常(食事・うんち・おしっこ・嘔吐・体温・体重・通院・投薬)を体系的に記録し、AIに相談でき、複数の家族・友人グループで共有可能で、お別れの後も思い出として残せる、犬猫飼い向けの総合ライフログアプリ。

## 五本柱の差別化

1. **体系的記録** — 獣医提示に耐える記録項目体系
2. **AI相談** — 過去7日詳細+30日サマリ+セッション履歴を文脈にAIが返答
3. **AI画像診断** — うんち写真をAI(犬猫別プロンプト)が分析
4. **家族共有** — 6桁コードで5人まで同期、最大3グループ参加可能
5. **お別れの後も** — 虹の橋を渡った後も思い出として記録継続

## 開発ガイド

### 必要なツール

```
Flutter SDK >= 3.24.0
Dart SDK >= 3.5.0
Xcode >= 15.0 (for iOS)
Android Studio Iguana+ (for Android)
```

### セットアップ

```bash
# 依存パッケージインストール
flutter pub get

# コード生成 (drift, freezed, riverpod, l10n)
flutter pub run build_runner build --delete-conflicting-outputs

# ローカル実行
flutter run --dart-define=ENV=development
```

### コード生成のwatch mode (開発中)

```bash
flutter pub run build_runner watch --delete-conflicting-outputs
```

### テスト実行

```bash
# Unit + Widget tests
flutter test

# Coverage付き
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html

# Integration tests
flutter test integration_test/

# ゴールデンテスト更新
flutter test --update-goldens
```

### ビルド

```bash
# iOS (Release)
flutter build ipa --release \
  --dart-define=ENV=production \
  --build-number=$BUILD_NUMBER

# Android (Release)
flutter build appbundle --release \
  --dart-define=ENV=production \
  --build-number=$BUILD_NUMBER
```

## アーキテクチャ

Clean Architecture + Riverpod風

```
lib/
├── core/                  # アプリ全体の基盤
│   ├── constants/         # 定数(色、サイズ、タイミング等)
│   ├── theme/             # デザイントークン、Light/Dark
│   ├── utils/             # ヘルパー関数
│   ├── errors/            # 例外クラス
│   ├── extensions/        # Dart/Flutter拡張
│   └── widgets/           # 共通ウィジェット(再利用部品)
│
├── data/                  # データ層
│   ├── local/             # drift (SQLite)
│   │   ├── daos/          # Data Access Objects
│   │   ├── migrations/    # マイグレーション
│   │   └── app_database.dart
│   ├── remote/            # Cloudflare Workers API
│   ├── repositories/      # 実装(domain/repositoriesの実装)
│   └── models/            # DTO (data transfer objects)
│
├── domain/                # ドメイン層(ビジネスロジック)
│   ├── entities/          # ドメインモデル(immutable)
│   ├── repositories/      # インターフェース
│   └── usecases/          # 個別ユースケース
│
├── presentation/          # プレゼンテーション層(UI)
│   ├── providers/         # Riverpod Provider
│   ├── screens/           # 画面ごとに分割
│   │   ├── home/
│   │   ├── life/
│   │   ├── health/
│   │   ├── plans/
│   │   ├── settings/
│   │   ├── onboarding/
│   │   ├── ai/
│   │   └── group/
│   ├── widgets/           # screen固有のウィジェット
│   └── routing/           # 画面遷移
│
└── l10n/                  # 多言語対応
    ├── app_ja.arb
    ├── app_en.arb
    ├── app_zh.arb
    └── generated/
```

## 仕様書

詳細仕様書は `petlo.md` (rev5.5 / FROZEN) を参照。

## 実装フェーズ

| Phase | 期間 | 内容 |
|---|---|---|
| Phase 1 | 6.5週 | コア機能 + 基盤 |
| Phase 2 | 2.7週 | 健康・予定機能 |
| Phase 3 | 4.3週 | AI機能 + バックエンド |
| Phase 4 | 6.1週 | 家族共有 |
| Phase 5 | 5.9週 | バックアップ + 課金 + PDF + 権限制御 |
| Phase 6 | 2.5週 | ホーム画面ウィジェット |
| Phase 7 | 2.2週 | アクセシビリティ仕上げ |
| Phase 8 | 1.7週 | 申請準備 |
| **合計** | **35.2週** | **約8.8ヶ月** |

## ブランドガイドライン

- 白黒ミニマル、エディトリアル振り(雑誌的・知的・冷たい)
- フォント: Fraunces(セリフ) + Manrope(サンセリフ) + JetBrains Mono(等幅)
- 中国語フォールバック: Noto Serif/Sans SC
- 警告: `#C24A00` (Amber) / 至急: `#9B0F0F` (Crimson)
- 色覚異常配慮: 色 + 文字ラベル併記
- 絵文字は使わない、線画アイコン統一(stroke 1.4px)

## 関連リンク

- 仕様書: `petlo.md`
- ビジュアルモック: `petlo_mock.html`
- API実装: `petlo-api/`
- ブランド: https://mamonis.studio
- サポート: contact@mamonis.studio

## ライセンス

Proprietary © 2026 mamonis.studio
