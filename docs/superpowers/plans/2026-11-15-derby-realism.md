# derby 本物らしさの強化 Implementation Plan

**Goal:** 馬の詳細パラメータ・調子・表情を出走表に出し(調子は勝敗に影響)、コースを長くしてカメラが追うようにする。

**Spec:** `docs/superpowers/specs/2026-11-15-derby-design.md` の「追記: 本物らしさの強化」

## Global Constraints
- 従来の制約(日本語表示、架空コイン、サーバーが唯一の正、画像素材なし、依存追加なし)を引き継ぐ。
- 本当の調子(`trueCond`)と勝率(`prob`)は、どの端末にも送らない。
- 追加の通信項目: `horses[]` に `sex, age, weight, weightDiff, style, recent[3], pop, cond(1〜5), mood`、ビューに `course: {distance, going}`。アプリは欠けていても既定値で動く。
- `mood` の値: `fired`(気合十分) / `happy`(ごきげん) / `calm`(落ち着き) / `restless`(そわそわ) / `sleepy`(眠そう)。`cond` は 5=絶好調 … 1=絶不調。
- レース時間はレースごとの `race.durationMs`(= 最後の馬のゴール + 1500ms)。

## Review Focus
1. 古いサーバー/古いアプリの組み合わせ(項目が欠けた出走馬)→ 落ちずに従来どおり表示。
2. 調子の手がかりから本当の調子や勝率が逆算できる形で漏れていないか(`prob`/`trueCond` が view に無い)。
3. 小さい画面・長い馬名で出走表がはみ出さない(アプリ 320 幅、管理ページ 1366x768)。
4. レース途中から開いたとき、カメラ位置も経過時間に合っている。
5. 距離や馬場が違っても、映像のゴール順が着順と一致し、時間どおりに結果へ進む。

## Tasks
1. **サーバーのルール** (`server/src/rules.ts`, `game.ts`, tests): `makeCourse`, 拡張した `makeField`(実力→オッズ、調子→勝率、手がかりの生成)、脚質に基づく `makeTimes(order, horses, course, rng)`、`viewFor` の公開項目。テスト: オッズの性質は従来どおり / 調子の良い馬はオッズより勝つ / 手がかりの的中率が約 80% / view に `prob`・`trueCond` が無い / ゴール順と着順の一致 / 時間が 24〜32 秒。
2. **管理ページ**: 出走表に詳細・調子・表情、レース映像をスクロール式に。
3. **アプリ**: `protocol.dart`(欠損に強い)、`race_math.dart` にカメラ計算、出走表の2行表示と顔、スクロールするコース。
4. **確認**: `npm run sim`、管理ページとエミュレータの画面確認、手順書の更新、最終レビュー。
