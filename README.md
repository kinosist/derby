# derby

授業用のオンライン対戦競馬ゲームの、生徒用アプリ(Flutter / Android)。
クラス全員が同じ自動レースに架空コインを賭け、所持金を競う。

このリポジトリにあるのはアプリだけ。サーバー(部屋と先生用の管理ページ)のコードは含まない。

- `lib/` アプリのコード
- `test/` アプリのテスト
- `docs/teacher-guide.md` 先生向けの手順書(配布・当日の進め方・ゲームのルール)

## すぐ使う(ビルド不要)

ビルド済みのアプリ(APK)を [Releases](https://github.com/kinosist/derby/releases/latest) からダウンロードし、起動したエミュレータの画面にドラッグ&ドロップする。

## ソースから動かす

必要なもの:

- Flutter(Dart SDK 3.11.0 以上。Android のビルド設定は AGP 9.3.1 / Gradle 9.5.0 / Kotlin 2.4.20。Flutter 3.50 で確認)
- Windows でビルドする場合は「開発者モード」をオンにする(プラグインのビルドにシンボリックリンクが必要)

接続先(サーバーのアドレス)はコードに書かれていない。実行・ビルドのときに `--dart-define=SERVER_URL=…` で指定する。

```
flutter pub get
flutter run --dart-define=SERVER_URL=wss://<サーバーのアドレス>/ws
```

Android Studio で実行する場合は、Run → Edit Configurations… を開き、「Additional run args」に
`--dart-define=SERVER_URL=wss://<サーバーのアドレス>/ws` を入れる。

指定せずに起動すると、設定方法を案内する画面が出る。アドレスは先生に確認すること。

## テスト

```
flutter test
flutter analyze
```
