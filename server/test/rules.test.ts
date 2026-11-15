import { expect, test } from 'vitest';
import {
  COND_FACTORS, MOODS, STYLES, drawOrder, makeCourse, makeField, makeTimes, oddsFor, payout, raceDuration, seededRng,
  type Course,
} from '../src/rules';

const course: Course = { distance: 1600, going: '良' };

test('oddsFor', () => {
  expect(oddsFor(0.5)).toBe(2.0);
  expect(oddsFor(0.196)).toBe(5.1);
  expect(oddsFor(0.99)).toBe(1.1);
  expect(oddsFor(1 / 12)).toBe(12.0);
});

test('payout は切り捨て・賭け金込み', () => {
  expect(payout(300, 5.1)).toBe(1530);
  expect(payout(10, 1.1)).toBe(11);
  expect(payout(70, 2.4)).toBe(168);
});

test('makeField: オッズは実力から決まり、200 回分の性質を満たす', () => {
  for (let seed = 1; seed <= 200; seed++) {
    const f = makeField(seededRng(seed));
    expect(f.map((h) => h.no)).toEqual([1, 2, 3, 4, 5, 6, 7, 8]);
    expect(new Set(f.map((h) => h.name)).size).toBe(8);
    expect(f.reduce((a, h) => a + h.baseProb, 0)).toBeCloseTo(1, 6);
    expect(f.reduce((a, h) => a + h.prob, 0)).toBeCloseTo(1, 6);
    const odds = f.map((h) => h.odds);
    expect(Math.min(...odds)).toBeGreaterThanOrEqual(1.5);
    expect(Math.min(...odds)).toBeLessThanOrEqual(4.0); // 本命がいる
    expect(Math.max(...odds)).toBeGreaterThanOrEqual(8.0); // 穴馬がいる
    expect(Math.max(...odds)).toBeLessThanOrEqual(30.0);
    f.forEach((h) => expect(h.odds).toBe(oddsFor(h.baseProb)));
  }
});

test('makeField: 実際の勝率は「実力 × 調子の倍率」を正規化したもの', () => {
  expect(COND_FACTORS).toEqual([0.55, 0.8, 1.0, 1.3, 1.7]);
  const f = makeField(seededRng(3));
  const raw = f.map((h) => h.baseProb * COND_FACTORS[h.trueCond - 1]);
  const total = raw.reduce((a, b) => a + b, 0);
  f.forEach((h, i) => expect(h.prob).toBeCloseTo(raw[i] / total, 9));
});

test('makeField: 表示用のパラメータが妥当な範囲にある', () => {
  for (let seed = 1; seed <= 100; seed++) {
    const f = makeField(seededRng(seed));
    for (const h of f) {
      expect(['牡', '牝', 'セ']).toContain(h.sex);
      expect(h.age).toBeGreaterThanOrEqual(3);
      expect(h.age).toBeLessThanOrEqual(7);
      expect(h.weight).toBeGreaterThanOrEqual(420);
      expect(h.weight).toBeLessThanOrEqual(520);
      expect(h.weight % 2).toBe(0);
      expect(Math.abs(h.weightDiff)).toBeLessThanOrEqual(12);
      expect(h.weightDiff % 2 === 0).toBe(true);
      expect(STYLES).toContain(h.style);
      expect(h.recent.length).toBe(3);
      h.recent.forEach((r) => { expect(Number.isInteger(r)).toBe(true); expect(r).toBeGreaterThanOrEqual(1); expect(r).toBeLessThanOrEqual(12); });
      expect([1, 2, 3, 4, 5]).toContain(h.trueCond);
      expect([1, 2, 3, 4, 5]).toContain(h.cond);
      expect(MOODS).toContain(h.mood);
    }
    // 人気順はオッズの低い順(同じなら馬番順)で 1〜8
    const byOdds = [...f].sort((a, b) => a.odds - b.odds || a.no - b.no);
    byOdds.forEach((h, i) => expect(h.pop).toBe(i + 1));
    // 脚質が全員同じにはならない
    expect(new Set(f.map((h) => h.style)).size).toBeGreaterThanOrEqual(2);
  }
});

test('makeField: 近走の着順は、実力の高い馬ほど良い', () => {
  let fav = 0, long = 0, n = 0;
  for (let seed = 1; seed <= 300; seed++) {
    const f = makeField(seededRng(seed));
    const sorted = [...f].sort((a, b) => b.baseProb - a.baseProb);
    fav += sorted[0].recent.reduce((a, b) => a + b, 0) / 3;
    long += sorted[7].recent.reduce((a, b) => a + b, 0) / 3;
    n++;
  }
  expect(fav / n).toBeLessThan(3.5);
  expect(long / n).toBeGreaterThan(5.5);
});

test('makeField: 調子と表情の手がかりは約 80% で当たり、外れても 1 段階', () => {
  let condHit = 0, moodHit = 0, n = 0;
  const seenCond = new Set<number>();
  for (let seed = 1; seed <= 600; seed++) {
    for (const h of makeField(seededRng(seed))) {
      n++;
      seenCond.add(h.trueCond);
      expect(Math.abs(h.cond - h.trueCond)).toBeLessThanOrEqual(1);
      const moodLevel = MOODS.indexOf(h.mood) + 1;
      expect(Math.abs(moodLevel - h.trueCond)).toBeLessThanOrEqual(1);
      if (h.cond === h.trueCond) condHit++;
      if (moodLevel === h.trueCond) moodHit++;
    }
  }
  expect(MOODS).toEqual(['sleepy', 'restless', 'calm', 'happy', 'fired']);
  expect(seenCond.size).toBe(5);
  expect(condHit / n).toBeGreaterThan(0.76);
  expect(condHit / n).toBeLessThan(0.86);
  expect(moodHit / n).toBeGreaterThan(0.76);
  expect(moodHit / n).toBeLessThan(0.86);
});

test('調子の良い馬はオッズより勝ち、悪い馬はオッズより負ける', () => {
  let goodWins = 0, goodExpected = 0, badWins = 0, badExpected = 0;
  const rng = seededRng(2024);
  for (let i = 0; i < 6000; i++) {
    const f = makeField(rng);
    const winner = drawOrder(f, rng)[0];
    for (const h of f) {
      if (h.trueCond >= 4) { goodExpected += h.baseProb; if (h.no === winner) goodWins++; }
      if (h.trueCond <= 2) { badExpected += h.baseProb; if (h.no === winner) badWins++; }
    }
  }
  expect(goodWins / goodExpected).toBeGreaterThan(1.15);
  expect(badWins / badExpected).toBeLessThan(0.85);
});

test('表示された調子が良い馬に賭けると得になる(手がかりに意味がある)', () => {
  // 表示が「好調」以上の馬に 1 ずつ賭け続けたときの回収率
  let staked = 0, returned = 0;
  const rng = seededRng(77);
  for (let i = 0; i < 6000; i++) {
    const f = makeField(rng);
    const winner = drawOrder(f, rng)[0];
    for (const h of f) {
      if (h.cond >= 4 && MOODS.indexOf(h.mood) + 1 >= 4) { staked += 1; if (h.no === winner) returned += h.odds; }
    }
  }
  expect(returned / staked).toBeGreaterThan(1.1);
});

test('drawOrder: 順列であり、実際の勝率どおりに勝つ', () => {
  const f = makeField(seededRng(7));
  const rng = seededRng(99);
  const wins = new Array(9).fill(0);
  for (let i = 0; i < 20000; i++) {
    const o = drawOrder(f, rng);
    wins[o[0]]++;
    if (i === 0) expect([...o].sort()).toEqual([1, 2, 3, 4, 5, 6, 7, 8]);
  }
  f.forEach((h) => expect(wins[h.no] / 20000).toBeCloseTo(h.prob, 1.5));
});

test('makeCourse: 距離と馬場', () => {
  const distances = new Set<number>(), goings = new Set<string>();
  const rng = seededRng(5);
  for (let i = 0; i < 400; i++) { const c = makeCourse(rng); distances.add(c.distance); goings.add(c.going); }
  expect([...distances].sort((a, b) => a - b)).toEqual([1200, 1400, 1600, 1800, 2000, 2400]);
  expect([...goings].sort()).toEqual(['不良', '稍重', '良', '重'].sort());
});

test('makeTimes: 着順と矛盾せず、時間は距離と馬場に応じる', () => {
  for (let seed = 1; seed <= 150; seed++) {
    const f = makeField(seededRng(seed));
    const order = drawOrder(f, seededRng(seed + 1));
    const c = makeCourse(seededRng(seed + 3));
    const t = makeTimes(order, f, c, seededRng(seed + 2));
    expect(t.length).toBe(8);
    t.forEach((a) => {
      expect(a.length).toBe(11);
      expect(a[0]).toBe(0);
      for (let i = 1; i < 11; i++) expect(a[i]).toBeGreaterThan(a[i - 1]);
      expect(a[10]).toBeGreaterThanOrEqual(21000);
      expect(a[10]).toBeLessThanOrEqual(32500);
      a.forEach((v) => expect(Number.isInteger(v)).toBe(true));
    });
    const byFinish = [1, 2, 3, 4, 5, 6, 7, 8].sort((x, y) => t[x - 1][10] - t[y - 1][10]);
    expect(byFinish).toEqual(order);
    for (let i = 1; i < 8; i++) {
      expect(t[order[i] - 1][10] - t[order[i - 1] - 1][10]).toBeGreaterThanOrEqual(100);
    }
    expect(raceDuration(t)).toBe(Math.max(...t.map((a) => a[10])) + 1500);
  }
});

test('makeTimes: 長い距離・重い馬場ほど時間がかかる', () => {
  const f = makeField(seededRng(1));
  const order = [1, 2, 3, 4, 5, 6, 7, 8];
  const win = (c: Course) => makeTimes(order, f, c, seededRng(9))[0][10];
  expect(win({ distance: 2400, going: '良' })).toBeGreaterThan(win({ distance: 1200, going: '良' }) + 4000);
  expect(win({ distance: 1600, going: '不良' })).toBeGreaterThan(win({ distance: 1600, going: '良' }));
});

test('makeTimes: 逃げ馬は序盤に前へ出て、追込馬は終盤に伸びる', () => {
  let nige = 0, oikomi = 0, nNige = 0, nOikomi = 0;
  for (let seed = 1; seed <= 300; seed++) {
    const f = makeField(seededRng(seed));
    const order = drawOrder(f, seededRng(seed + 1));
    const t = makeTimes(order, f, course, seededRng(seed + 2));
    for (const h of f) {
      // コースの前半 5 区間にかかった時間の割合(小さいほど前半が速い)
      const firstHalf = t[h.no - 1][5] / t[h.no - 1][10];
      if (h.style === '逃げ') { nige += firstHalf; nNige++; }
      if (h.style === '追込') { oikomi += firstHalf; nOikomi++; }
    }
  }
  expect(nNige).toBeGreaterThan(50);
  expect(nOikomi).toBeGreaterThan(50);
  expect(nige / nNige).toBeLessThan(0.485);
  expect(oikomi / nOikomi).toBeGreaterThan(0.515);
});
