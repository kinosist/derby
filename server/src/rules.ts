// ゲームのルール(純粋関数)。通信や保存には関与しない。

export type Rng = () => number; // [0,1)

export const TOTAL_RACES = 5;
export const START_COINS = 1000;
export const HORSES = 8;
export const MIN_BET = 10;
export const RESCUE_COINS = 100;
export const NAME_MAX = 12;
export const MAX_PLAYERS = 60;

export const STYLES = ['逃げ', '先行', '差し', '追込'] as const;
export type Style = (typeof STYLES)[number];

/** 表情。並びは調子の 1(絶不調)〜 5(絶好調)に対応する。 */
export const MOODS = ['sleepy', 'restless', 'calm', 'happy', 'fired'] as const;
export type Mood = (typeof MOODS)[number];

/** 調子 1(絶不調)〜 5(絶好調)が勝率に掛かる倍率 */
export const COND_FACTORS = [0.55, 0.8, 1.0, 1.3, 1.7];

export const GOINGS = ['良', '稍重', '重', '不良'] as const;
export type Going = (typeof GOINGS)[number];
export type Course = { distance: number; going: Going };

export type Horse = {
  no: number;
  name: string;
  /** 実力だけの勝率。オッズはここから決める。端末には送らない。 */
  baseProb: number;
  /** 当日の調子を含めた実際の勝率。端末には送らない。 */
  prob: number;
  /** 本当の調子 1〜5。端末には送らない。 */
  trueCond: number;
  odds: number;
  // ここから下は出走表に出す
  sex: '牡' | '牝' | 'セ';
  age: number;
  weight: number;
  weightDiff: number;
  style: Style;
  /** 近3走の着順(新しい順) */
  recent: number[];
  /** 人気順(オッズの低い順) */
  pop: number;
  /** 出走表に出す調子 1〜5(本当の調子の手がかり。80% で当たる) */
  cond: number;
  /** 表情(本当の調子の手がかり。80% で当たる) */
  mood: Mood;
};

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

/**
 * 8頭の出走馬を作る。
 * オッズは実力だけから決める: 本命(4.0倍以下)と穴馬(8.0倍以上)が必ずいて、全馬 1.5〜30.0 倍に収まる。
 * 当日の調子は実際の勝率にだけ効くので、調子の良い馬はオッズより勝ちやすい。
 */
export function makeField(rng: Rng): Horse[] {
  const names = pickNames(rng);
  let baseProbs: number[];
  let odds: number[];
  for (;;) {
    const weights = Array.from({ length: HORSES }, () => Math.exp(rng() * 2.6));
    const total = weights.reduce((a, b) => a + b, 0);
    baseProbs = weights.map((w) => w / total);
    odds = baseProbs.map(oddsFor);
    const min = Math.min(...odds);
    const max = Math.max(...odds);
    if (min >= 1.5 && min <= 4.0 && max >= 8.0 && max <= 30.0) break;
  }

  const trueConds = baseProbs.map(() => pickWeighted([0.1, 0.2, 0.4, 0.2, 0.1], rng) + 1);
  const raw = baseProbs.map((p, i) => p * COND_FACTORS[trueConds[i] - 1]);
  const rawTotal = raw.reduce((a, b) => a + b, 0);

  // 実力の順位(1 = 最も強い)。近走の着順に使う。
  const abilityRank = baseProbs.map((p) => 1 + baseProbs.filter((q) => q > p).length);
  const popOrder = baseProbs.map((_, i) => i).sort((a, b) => odds[a] - odds[b] || a - b);

  let styles: Style[];
  do {
    styles = baseProbs.map(() => STYLES[pickWeighted([0.2, 0.3, 0.3, 0.2], rng)]);
  } while (new Set(styles).size < 2);

  return baseProbs.map((baseProb, i) => ({
    no: i + 1,
    name: names[i],
    baseProb,
    prob: raw[i] / rawTotal,
    trueCond: trueConds[i],
    odds: odds[i],
    sex: (['牡', '牡', '牝', '牝', 'セ'] as const)[Math.floor(rng() * 5)],
    age: 3 + pickWeighted([0.3, 0.3, 0.2, 0.12, 0.08], rng),
    weight: 420 + 2 * Math.floor(rng() * 51),
    weightDiff: 2 * (Math.floor(rng() * 11) - 5),
    style: styles[i],
    recent: [0, 1, 2].map(() => recentFinish(abilityRank[i], rng)),
    pop: popOrder.indexOf(i) + 1,
    cond: noisyHint(trueConds[i], rng),
    mood: MOODS[noisyHint(trueConds[i], rng) - 1],
  }));
}

function pickWeighted(weights: number[], rng: Rng): number {
  let r = rng() * weights.reduce((a, b) => a + b, 0);
  for (let i = 0; i < weights.length; i++) {
    r -= weights[i];
    if (r < 0) return i;
  }
  return weights.length - 1;
}

/** 本当の調子の手がかり。80% でそのまま、20% で 1 段階ずれる。 */
function noisyHint(level: number, rng: Rng): number {
  if (rng() < 0.8) return level;
  if (level === 1) return 2;
  if (level === 5) return 4;
  return rng() < 0.5 ? level - 1 : level + 1;
}

/** 近走の着順。実力の順位に近い着順になりやすく、下位の馬は大きく負けることもある。 */
function recentFinish(abilityRank: number, rng: Rng): number {
  const noise = (rng() * 2 - 1) * 2.5 + (abilityRank > 5 ? rng() * 3 : 0);
  return Math.min(12, Math.max(1, Math.round(abilityRank + noise)));
}

export function makeCourse(rng: Rng): Course {
  const distances = [1200, 1400, 1600, 1800, 2000, 2400];
  return {
    distance: distances[Math.floor(rng() * distances.length)],
    going: GOINGS[pickWeighted([0.55, 0.2, 0.15, 0.1], rng)],
  };
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

const GOING_FACTORS: Record<Going, number> = { 良: 1, 稍重: 1.02, 重: 1.04, 不良: 1.06 };
const STYLE_SHAPES: Record<Style, number> = { 逃げ: -1, 先行: -0.4, 差し: 0.4, 追込: 1 };

/**
 * レース映像データ。times[馬番-1] は、コースを 10 区間に分けた 11 地点の通過時刻(累積 ms)。
 * ゴール時刻の小さい順が order と一致する。長い距離・重い馬場ほど時間がかかり、
 * 脚質によって前半型(逃げ)か後半型(追込)かが決まる。
 */
export function makeTimes(order: number[], horses: Horse[], course: Course, rng: Rng): number[][] {
  const times: number[][] = new Array(order.length);
  const base = (21000 + (course.distance - 1200) * 5.5) * GOING_FACTORS[course.going];
  let finish = Math.round(base) + Math.floor(rng() * 800);
  for (const no of order) {
    const style = horses.find((h) => h.no === no)?.style ?? '先行';
    times[no - 1] = splitTimes(finish, STYLE_SHAPES[style], rng);
    finish += 100 + Math.floor(rng() * 200);
  }
  return times;
}

/** レースの長さ: 最後の馬がゴールしてから 1.5 秒後に結果へ進む。 */
export function raceDuration(times: number[][]): number {
  return Math.max(...times.map((t) => t[t.length - 1])) + 1500;
}

function splitTimes(finish: number, shape: number, rng: Rng): number[] {
  // shape > 0: 序盤に時間がかかり終盤に伸びる / shape < 0: 先行して終盤に鈍る
  const style = shape + (rng() - 0.5) * 0.4;
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

// ---- 馬券の種類と倍率 ----

export const BET_TYPES = ['win', 'place', 'quinella', 'trifecta'] as const;
export type BetType = (typeof BET_TYPES)[number];

/** 馬券の種類ごとに選ぶ頭数 */
export const BET_HORSES: Record<BetType, number> = { win: 1, place: 1, quinella: 2, trifecta: 3 };

export const MAX_ODDS = 999.9;
export const MAX_TICKETS = 10;

/** 単勝以外の倍率表。単勝は Horse.odds。 */
export type OddsTable = {
  /** place[馬番-1] */
  place: number[];
  /** キーは "小さい馬番-大きい馬番" */
  quinella: Record<string, number>;
  /** キーは "1着-2着-3着" */
  trifecta: Record<string, number>;
};

function oddsForCombo(prob: number): number {
  return Math.min(MAX_ODDS, oddsFor(prob));
}

/** 倍率表を引くためのキー。馬連は順不同なので馬番の小さい順に並べる。 */
export function comboKey(type: BetType, horses: number[]): string {
  return (type === 'quinella' ? [...horses].sort((a, b) => a - b) : horses).join('-');
}

/**
 * 複勝・馬連・3連単の倍率表を作る。
 * 着順は「残った馬の中で、実力(調子を含まない勝率)に比例して決まる」と仮定して的中確率を求める。
 */
export function makeOddsTable(horses: Horse[]): OddsTable {
  const n = horses.length;
  // 以前の形式で保存された馬には baseProb が無いので、その場合は prob を使う
  const p = horses.map((h) => h.baseProb ?? h.prob);
  const placeProb = new Array(n).fill(0);
  const quinellaProb: Record<string, number> = {};
  const trifecta: Record<string, number> = {};
  for (let a = 0; a < n; a++) {
    for (let b = 0; b < n; b++) {
      if (b === a) continue;
      const pab = p[a] * (p[b] / (1 - p[a]));
      const qk = comboKey('quinella', [horses[a].no, horses[b].no]);
      quinellaProb[qk] = (quinellaProb[qk] ?? 0) + pab;
      for (let c = 0; c < n; c++) {
        if (c === a || c === b) continue;
        const pabc = pab * (p[c] / (1 - p[a] - p[b]));
        trifecta[comboKey('trifecta', [horses[a].no, horses[b].no, horses[c].no])] = oddsForCombo(pabc);
        placeProb[a] += pabc;
        placeProb[b] += pabc;
        placeProb[c] += pabc;
      }
    }
  }
  const quinella: Record<string, number> = {};
  for (const [k, v] of Object.entries(quinellaProb)) quinella[k] = oddsForCombo(v);
  return { place: placeProb.map(oddsForCombo), quinella, trifecta };
}

/** 馬券が当たったか。order は着順(馬番の並び)。 */
export function ticketWins(type: BetType, horses: number[], order: number[]): boolean {
  switch (type) {
    case 'win':
      return order[0] === horses[0];
    case 'place':
      return order.slice(0, 3).includes(horses[0]);
    case 'quinella':
      return horses.length === 2 && horses.includes(order[0]) && horses.includes(order[1]);
    case 'trifecta':
      return horses.length === 3 && horses.every((h, i) => order[i] === h);
  }
}

// ---- 予想屋 ----

/** 予想屋。noise は読み違いの大きさ(勝率の対数に足す誤差の標準偏差)。小さいほど当たる。 */
export const TIPSTERS = [
  { id: 'paper', name: '競馬新聞', price: 30, stars: 1, noise: 1.5 },
  { id: 'veteran', name: 'ベテラン予想屋', price: 80, stars: 2, noise: 0.7 },
  { id: 'master', name: '伝説の予想屋', price: 150, stars: 3, noise: 0.1 },
] as const;
export type TipsterId = (typeof TIPSTERS)[number]['id'];

/** 予想: marks は ◎本命・○対抗・▲単穴 の馬番 */
export type Tip = { marks: number[]; comment: string };

const TIP_COMMENTS = [
  '今日はこの馬で決まり!',
  '◎は仕上がりがいい。○との勝負だ。',
  '人気より中身。◎を信じなさい。',
  '▲の一発にも注意だよ。',
  '◎○▲の 3 頭でまず間違いない。',
  'パドックの気配は◎がいちばん。',
  '迷ったら◎から買うことだね。',
  '今日の◎は自信があるよ。',
];

/**
 * 予想屋は「勝ちやすい馬」だけでなく「倍率のわりに勝ちやすい馬(調子の良い馬)」を重く見る。
 * この重みが大きいほど、調子の良さを重視した予想になる。
 */
const TIP_VALUE_WEIGHT = 3;

/** 標準正規分布の乱数(Box–Muller) */
function gaussian(rng: Rng): number {
  const u = Math.max(rng(), 1e-12);
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * rng());
}

/**
 * 各予想屋の予想を作る。その日の調子も含めた実際の勝率を、予想屋ごとの誤差つきで見て、上位 3 頭を選ぶ。
 * 1 レースにつき予想屋ごとに 1 つ(誰が買っても同じ内容)。
 */
export function makeTips(horses: Horse[], rng: Rng): Record<TipsterId, Tip> {
  const out = {} as Record<TipsterId, Tip>;
  for (const t of TIPSTERS) {
    const scored = horses
      .map((h) => ({ no: h.no, score: Math.log(h.prob) + TIP_VALUE_WEIGHT * Math.log(h.prob / (h.baseProb ?? h.prob)) + gaussian(rng) * t.noise }))
      .sort((a, b) => b.score - a.score || a.no - b.no);
    out[t.id] = {
      marks: scored.slice(0, 3).map((x) => x.no),
      comment: TIP_COMMENTS[Math.floor(rng() * TIP_COMMENTS.length)],
    };
  }
  return out;
}
