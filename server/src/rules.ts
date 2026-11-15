// ゲームのルール(純粋関数)。通信や保存には関与しない。

export type Rng = () => number; // [0,1)

export const TOTAL_RACES = 5;
export const START_COINS = 1000;
export const HORSES = 8;
export const MIN_BET = 10;
export const RESCUE_COINS = 100;
export const RACE_DURATION_MS = 20000;
export const NAME_MAX = 12;
export const MAX_PLAYERS = 60;

export type Horse = { no: number; name: string; prob: number; odds: number };

// 架空の馬名
const HORSE_NAMES = [
  'ハヤテオー', 'ミドリノカゼ', 'ホシゾラランナー', 'アサヤケゴー', 'ユウヤケキング',
  'カミナリダッシュ', 'ソヨカゼヒメ', 'ツキアカリ', 'ニジノカケハシ', 'オオゾラジャンプ',
  'モリノイナズマ', 'ウミカゼボーイ', 'ヤマビコスター', 'サクラフブキ', 'ヒマワリパワー',
  'コガネノツバサ', 'シロクマエース', 'クロネコターボ', 'アカトンボ', 'アオゾラキッド',
  'ポンポコダイオー', 'モチモチプリンス', 'オニギリロケット', 'タコヤキファイター', 'メロンパンナイト',
  'ドングリコロリン', 'ワタアメドリーム', 'カキゴオリブルー', 'ユキダルマッハ', 'ハナビスパーク',
  'ノンビリヤ', 'イッショウケンメイ', 'ネボスケチャンプ', 'ハラペコタイショー', 'ニコニコスマイル',
  'ガンバルゾー', 'マケズギライ', 'キラキラコメット', 'フワフワクラウド', 'ピカピカサンダー',
  'ドキドキハート', 'ワクワクジャーニー',
];

/** テスト用の再現可能な乱数(mulberry32) */
export function seededRng(seed: number): Rng {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** 本番用の乱数 */
export function cryptoRng(): Rng {
  const buf = new Uint32Array(1);
  return () => {
    crypto.getRandomValues(buf);
    return buf[0] / 4294967296;
  };
}

export function oddsFor(prob: number): number {
  return Math.max(1.1, Math.round((1 / prob) * 10) / 10);
}

/** 8頭の出走馬を作る。本命(4.0倍以下)と穴馬(8.0倍以上)が必ずいて、全馬 1.5〜30.0 倍に収まる。 */
export function makeField(rng: Rng): Horse[] {
  const names = pickNames(rng);
  for (;;) {
    const weights = Array.from({ length: HORSES }, () => Math.exp(rng() * 2.6));
    const total = weights.reduce((a, b) => a + b, 0);
    const probs = weights.map((w) => w / total);
    const odds = probs.map(oddsFor);
    const min = Math.min(...odds);
    const max = Math.max(...odds);
    if (min < 1.5 || min > 4.0 || max < 8.0 || max > 30.0) continue;
    return probs.map((prob, i) => ({ no: i + 1, name: names[i], prob, odds: odds[i] }));
  }
}

function pickNames(rng: Rng): string[] {
  const pool = [...HORSE_NAMES];
  const out: string[] = [];
  for (let i = 0; i < HORSES; i++) {
    out.push(pool.splice(Math.floor(rng() * pool.length), 1)[0]);
  }
  return out;
}

/** 着順(馬番の並び)を勝率に基づいて抽選する(Plackett–Luce)。 */
export function drawOrder(horses: Horse[], rng: Rng): number[] {
  const rest = [...horses];
  const order: number[] = [];
  while (rest.length > 0) {
    const total = rest.reduce((a, h) => a + h.prob, 0);
    let r = rng() * total;
    let idx = rest.length - 1;
    for (let i = 0; i < rest.length; i++) {
      r -= rest[i].prob;
      if (r < 0) {
        idx = i;
        break;
      }
    }
    order.push(rest.splice(idx, 1)[0].no);
  }
  return order;
}

/** 払い戻し(賭け金込み、端数切り捨て)。 */
export function payout(amount: number, odds: number): number {
  // 浮動小数の誤差(例: 300 × 5.1 = 1529.999…)を避けるため、オッズを 10 倍の整数で扱う
  return Math.floor((amount * Math.round(odds * 10)) / 10);
}

const SEGMENTS = 10;

/**
 * レース映像データ。times[馬番-1] は、コースを 10 区間に分けた 11 地点の通過時刻(累積 ms)。
 * ゴール時刻の小さい順が order と一致する。
 */
export function makeTimes(order: number[], rng: Rng): number[][] {
  const times: number[][] = new Array(order.length);
  let finish = 16000 + Math.floor(rng() * 800);
  for (const no of order) {
    times[no - 1] = splitTimes(finish, rng);
    finish += 100 + Math.floor(rng() * 200);
  }
  return times;
}

function splitTimes(finish: number, rng: Rng): number[] {
  // style > 0: 序盤に時間がかかり終盤に伸びる馬 / style < 0: 先行して終盤に鈍る馬
  const style = rng() * 2 - 1;
  const weights: number[] = [];
  for (let j = 0; j < SEGMENTS; j++) {
    const slope = -style * 0.14 * ((j - 4.5) / 4.5);
    weights.push(1 + slope + (rng() - 0.5) * 0.14);
  }
  const total = weights.reduce((a, b) => a + b, 0);
  const out = [0];
  let acc = 0;
  for (let j = 0; j < SEGMENTS - 1; j++) {
    acc += weights[j];
    out.push(Math.round((acc / total) * finish));
  }
  out.push(finish);
  return out;
}
