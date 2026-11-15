import { expect, test } from 'vitest';
import { drawOrder, makeField, makeTimes, oddsFor, payout, seededRng } from '../src/rules';

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

test('makeField: 200 回分の性質', () => {
  for (let seed = 1; seed <= 200; seed++) {
    const f = makeField(seededRng(seed));
    expect(f.map((h) => h.no)).toEqual([1, 2, 3, 4, 5, 6, 7, 8]);
    expect(new Set(f.map((h) => h.name)).size).toBe(8);
    expect(f.reduce((a, h) => a + h.prob, 0)).toBeCloseTo(1, 6);
    const odds = f.map((h) => h.odds);
    expect(Math.min(...odds)).toBeGreaterThanOrEqual(1.5);
    expect(Math.min(...odds)).toBeLessThanOrEqual(4.0); // 本命がいる
    expect(Math.max(...odds)).toBeGreaterThanOrEqual(8.0); // 穴馬がいる
    expect(Math.max(...odds)).toBeLessThanOrEqual(30.0);
    f.forEach((h) => expect(h.odds).toBe(oddsFor(h.prob)));
  }
});

test('drawOrder: 順列であり、勝率どおりに勝つ', () => {
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

test('makeTimes: 着順と矛盾しない', () => {
  for (let seed = 1; seed <= 100; seed++) {
    const order = drawOrder(makeField(seededRng(seed)), seededRng(seed + 1));
    const t = makeTimes(order, seededRng(seed + 2));
    expect(t.length).toBe(8);
    t.forEach((a) => {
      expect(a.length).toBe(11);
      expect(a[0]).toBe(0);
      for (let i = 1; i < 11; i++) expect(a[i]).toBeGreaterThan(a[i - 1]);
      expect(a[10]).toBeGreaterThanOrEqual(15000);
      expect(a[10]).toBeLessThanOrEqual(19000);
      a.forEach((v) => expect(Number.isInteger(v)).toBe(true));
    });
    const byFinish = [1, 2, 3, 4, 5, 6, 7, 8].sort((x, y) => t[x - 1][10] - t[y - 1][10]);
    expect(byFinish).toEqual(order);
    for (let i = 1; i < 8; i++) {
      expect(t[order[i] - 1][10] - t[order[i - 1] - 1][10]).toBeGreaterThanOrEqual(100);
    }
  }
});
