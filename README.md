# derby

授業用のオンライン対戦競馬ゲームの、生徒用アプリ(Flutter / Android)。
クラス全員が同じ自動レースに架空コインを賭け、所持金を競う。

このリポジトリにあるのはアプリだけ。サーバー(部屋と先生用の管理ページ)のコードは含まない。
アプリは、公開中のサーバーにそのままつながる。

- `lib/` アプリのコード
- `test/` アプリのテスト
- `docs/teacher-guide.md` 先生向けの手順書(配布・当日の進め方・ゲームのルール)

## すぐ使う(ビルド不要)

ビルド済みのアプリ(APK)を [Releases](https://github.com/kinosist/derby/releases/latest) からダウンロードし、起動したエミュレータの画面にドラッグ&ドロップする。

## ソースから動かす

必要なもの:

- Flutter(Dart SDK 3.11.0 以上。Android のビルド設定は AGP 9.3.1 / Gradle 9.5.0 / Kotlin 2.4.20。Flutter 3.50 で確認)
- Windows でビルドする場合は「開発者モード」をオンにする(プラグインのビルドにシンボリックリンクが必要)

```
flutter pub get
flutter run
```

何も指定しなければ、公開中のサーバー(`wss://derby.versailles747.workers.dev/ws`)につながる。
別のサーバーにつなぐときは `flutter run --dart-define=SERVER_URL=wss://<アドレス>/ws` のように指定する。

## テスト

```
flutter test
flutter analyze
```
