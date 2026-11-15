# derby

授業用のオンライン対戦競馬ゲーム。クラス全員が同じ自動レースに架空コインを賭け、所持金を競う。

- `lib/` 生徒用アプリ(Flutter / Android)
- `server/` Cloudflare Worker + Durable Object(部屋)と、先生用の管理ページ(`server/public/admin/`)
- `docs/teacher-guide.md` 先生向けの手順書(公開・配布・当日の進め方)
- `docs/superpowers/specs/` 設計書

## 開発用の起動

```
# サーバー(http://127.0.0.1:8787、先生用パスワードは server/.dev.vars の TEACHER_KEY。なければ TEACHER_KEY=dev と書いたファイルを作る)
cd server
npm install
npm run dev

# 管理ページ: http://127.0.0.1:8787/admin
# アプリ(エミュレータからは既定で ws://10.0.2.2:8787/ws につながる)
flutter run
```

## テスト

```
cd server
npm test          # ルールと進行の単体テスト
npm run typecheck
npm run sim       # サーバー起動中に実行。擬似生徒 40 人で 1 試合を通して検証(約 2 分)
node scripts/sim.mjs --no-admin --players 10   # 生徒役だけ。管理ページの操作に合わせて賭け続ける

cd ..
flutter test
flutter analyze
```

Windows の Git Bash では、`cd /c/...` ではなく `cd "C:/..."` の形で移動してから `npm test` を実行すること(前者だと vitest が起動に失敗する)。
