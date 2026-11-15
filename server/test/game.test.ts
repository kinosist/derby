import { describe, expect, test } from 'vitest';
import {
  adminCloseAndRace, adminNewGame, adminNext, adminReset, adminStart, cancelBet, finishRace,
  join, kick, kickAll, newGame, normalizeName, placeBet, setOnline, viewFor,
  type GameState,
} from '../src/game';
import { payout, seededRng, START_COINS, TOTAL_RACES } from '../src/rules';

let idCounter = 0;
const newId = () => `gen-${++idCounter}`;
const idOf = (name: string) => `id-${name}`;

function setup(names: string[]): GameState {
  let s = newGame();
  for (const n of names) {
    const r = join(s, idOf(n), n, newId);
    expect(r.error).toBeUndefined();
    s = r.state;
  }
  return s;
}
const ok = (r: { state: GameState; error?: string }): GameState => {
  expect(r.error).toBeUndefined();
  return r.state;
};
const coins = (s: GameState, name: string) => s.players.find((p) => p.name === name)!.coins;
const withCoins = (s: GameState, name: string, c: number): GameState => ({
  ...s,
  players: s.players.map((p) => (p.name === name ? { ...p, coins: c } : p)),
});

/** 第1レースの betting まで進め、指定の馬が1着になる乱数の種を探す */
function raceWhereHorseWins(s: GameState, horse: number): GameState {
  for (let seed = 1; seed < 500; seed++) {
    const r = ok(adminCloseAndRace(s, seededRng(seed), 1000));
    if (r.race!.order[0] === horse) return r;
  }
  throw new Error('no seed found');
}

describe('試合の流れ', () => {
  test('1試合を通すと final になり、所持金の増減は配当どおり', () => {
    let s = setup(['a', 'b', 'c']);
    const rng = seededRng(42);
    s = ok(adminStart(s, rng));
    for (let race = 1; race <= TOTAL_RACES; race++) {
      expect(s.phase).toBe('betting');
      expect(s.raceNo).toBe(race);
      expect(s.horses.length).toBe(8);
      const before = s.players.reduce((a, p) => a + p.coins, 0);
      const bets: Record<string, { horse: number; amount: number }> = {};
      s.players.forEach((p, i) => {
        if (p.coins >= 10) {
          bets[p.id] = { horse: ((race + i) % 8) + 1, amount: Math.min(100, p.coins - (p.coins % 10)) };
          s = ok(placeBet(s, p.id, bets[p.id].horse, bets[p.id].amount));
        }
      });
      s = ok(adminCloseAndRace(s, rng, 1000 * race));
      expect(s.phase).toBe('racing');
      const winner = s.race!.order[0];
      const odds = s.horses.find((h) => h.no === winner)!.odds;
      s = finishRace(s);
      expect(s.phase).toBe('result');
      let expected = before;
      for (const b of Object.values(bets)) {
        expected += b.horse === winner ? payout(b.amount, odds) - b.amount : -b.amount;
      }
      expect(s.players.reduce((a, p) => a + p.coins, 0)).toBe(expected);
      s = ok(adminNext(s, rng));
    }
    expect(s.phase).toBe('final');
    expect(s.raceNo).toBe(TOTAL_RACES);
  });

  test('精算: 的中は賭け金込みの払い戻し、外れは賭け金を失い、見送りは不変', () => {
    let s = ok(adminStart(setup(['win', 'lose', 'skip']), seededRng(1)));
    s = ok(placeBet(s, idOf('win'), 1, 300));
    s = ok(placeBet(s, idOf('lose'), 2, 200));
    s = raceWhereHorseWins(s, 1);
    const odds = s.horses[0].odds;
    s = finishRace(s);
    const p = (n: string) => s.players.find((x) => x.name === n)!;
    expect(p('win').coins).toBe(1000 - 300 + payout(300, odds));
    expect(p('win').lastResult).toEqual({ horse: 1, amount: 300, won: true, delta: payout(300, odds) - 300 });
    expect(p('lose').coins).toBe(800);
    expect(p('lose').lastResult).toEqual({ horse: 2, amount: 200, won: false, delta: -200 });
    expect(p('skip').coins).toBe(1000);
    expect(p('skip').lastResult).toBeNull();
  });

  test('締め切りで賭け金が引かれる', () => {
    let s = ok(adminStart(setup(['a']), seededRng(1)));
    s = ok(placeBet(s, idOf('a'), 3, 250));
    expect(viewFor(s, idOf('a'), false, 0).me!.coins).toBe(1000);
    s = ok(adminCloseAndRace(s, seededRng(2), 5000));
    expect(viewFor(s, idOf('a'), false, 6000).me!.coins).toBe(750);
    expect(s.race!.startedAt).toBe(5000);
  });

  test('途中参加は 1000 コインで、次の賭け受付から賭けられる', () => {
    let s = ok(adminStart(setup(['a']), seededRng(1)));
    s = finishRace(ok(adminCloseAndRace(s, seededRng(2), 0)));
    s = ok(join(s, idOf('late'), 'late', newId));
    expect(coins(s, 'late')).toBe(START_COINS);
    s = ok(adminNext(s, seededRng(3)));
    s = ok(placeBet(s, idOf('late'), 1, 100));
    expect(s.players.find((p) => p.name === 'late')!.bet).toEqual({ horse: 1, amount: 100 });
  });
});

describe('賭けの検証', () => {
  test('不正な金額・馬番は bad_bet で state は不変', () => {
    const s = ok(adminStart(setup(['a']), seededRng(1)));
    for (const amount of [5, 15, 0, -10, 10.5, '100', 1010, null, NaN, Infinity]) {
      const r = placeBet(s, idOf('a'), 1, amount);
      expect(r.error, String(amount)).toBe('bad_bet');
      expect(r.state).toBe(s);
    }
    for (const horse of [0, 9, 1.5, '1', null]) {
      const r = placeBet(s, idOf('a'), horse, 100);
      expect(r.error, String(horse)).toBe('bad_bet');
      expect(r.state).toBe(s);
    }
  });

  test('全額は賭けられる', () => {
    const s = ok(adminStart(setup(['a']), seededRng(1)));
    expect(placeBet(s, idOf('a'), 8, 1000).error).toBeUndefined();
  });

  test('未参加は not_allowed', () => {
    const s = ok(adminStart(setup(['a']), seededRng(1)));
    expect(placeBet(s, 'nobody', 1, 100).error).toBe('not_allowed');
    expect(cancelBet(s, 'nobody').error).toBe('not_allowed');
  });

  test('賭け受付中以外は not_allowed', () => {
    const lobby = setup(['a']);
    expect(placeBet(lobby, idOf('a'), 1, 100).error).toBe('not_allowed');
    const racing = ok(adminCloseAndRace(ok(adminStart(lobby, seededRng(1))), seededRng(2), 0));
    expect(placeBet(racing, idOf('a'), 1, 100).error).toBe('not_allowed');
    expect(cancelBet(racing, idOf('a')).error).toBe('not_allowed');
  });

  test('上書きと取り消し', () => {
    let s = ok(adminStart(setup(['a']), seededRng(1)));
    s = ok(placeBet(s, idOf('a'), 1, 100));
    s = ok(placeBet(s, idOf('a'), 4, 500));
    expect(s.players[0].bet).toEqual({ horse: 4, amount: 500 });
    s = ok(cancelBet(s, idOf('a')));
    expect(s.players[0].bet).toBeNull();
  });
});

describe('救済', () => {
  test('賭け受付の開始時に 10 コイン未満の人は 100 コインになる', () => {
    let s = ok(adminStart(setup(['zero', 'nine', 'ten']), seededRng(1)));
    s = finishRace(ok(adminCloseAndRace(s, seededRng(2), 0)));
    s = withCoins(withCoins(withCoins(s, 'zero', 0), 'nine', 9), 'ten', 10);
    s = ok(adminNext(s, seededRng(3)));
    expect(coins(s, 'zero')).toBe(100);
    expect(coins(s, 'nine')).toBe(100);
    expect(coins(s, 'ten')).toBe(10);
  });
});

describe('先生の操作の連打(フェーズに合わない操作)', () => {
  test('締め切りの2回目は無視される', () => {
    const s1 = ok(adminCloseAndRace(ok(adminStart(setup(['a']), seededRng(1))), seededRng(2), 1000));
    const r = adminCloseAndRace(s1, seededRng(3), 9999);
    expect(r.error).toBe('not_allowed');
    expect(r.state).toBe(s1);
    expect(r.state.race!.startedAt).toBe(1000);
  });

  test('「次へ」の2回目は無視され、レースは1つだけ進む', () => {
    let s = ok(adminStart(setup(['a']), seededRng(1)));
    s = finishRace(ok(adminCloseAndRace(s, seededRng(2), 0)));
    s = ok(adminNext(s, seededRng(3)));
    const r = adminNext(s, seededRng(4));
    expect(r.error).toBe('not_allowed');
    expect(r.state.raceNo).toBe(2);
  });

  test('finishRace の2回目は二重に精算しない', () => {
    let s = ok(adminStart(setup(['a']), seededRng(1)));
    s = ok(placeBet(s, idOf('a'), 1, 300));
    s = finishRace(raceWhereHorseWins(s, 1));
    const after = coins(s, 'a');
    expect(finishRace(s)).toBe(s);
    expect(coins(finishRace(s), 'a')).toBe(after);
  });

  test('フェーズ違いの操作は not_allowed', () => {
    const lobby = setup(['a']);
    expect(adminNext(lobby, seededRng(1)).error).toBe('not_allowed');
    expect(adminCloseAndRace(lobby, seededRng(1), 0).error).toBe('not_allowed');
    expect(adminNewGame(lobby).error).toBe('not_allowed');
    const betting = ok(adminStart(lobby, seededRng(1)));
    expect(adminStart(betting, seededRng(1)).error).toBe('not_allowed');
    expect(adminNext(betting, seededRng(1)).error).toBe('not_allowed');
    expect(finishRace(lobby)).toBe(lobby);
  });

  test('参加者 0 人でも進行できる', () => {
    let s = ok(adminStart(newGame(), seededRng(1)));
    s = finishRace(ok(adminCloseAndRace(s, seededRng(2), 0)));
    expect(s.phase).toBe('result');
  });
});

describe('参加の決まり', () => {
  test('normalizeName', () => {
    expect(normalizeName('  たろう  ')).toBe('たろう');
    expect(normalizeName('')).toBeNull();
    expect(normalizeName('   ')).toBeNull();
    expect(normalizeName(' 　 ')).toBeNull();
    expect(normalizeName('あ'.repeat(13))).toBeNull();
    expect(normalizeName('あ'.repeat(12))).toBe('あ'.repeat(12));
    expect(normalizeName(123)).toBeNull();
    expect(normalizeName(null)).toBeNull();
    expect(normalizeName('🐎'.repeat(12))).toBe('🐎'.repeat(12));
    expect(normalizeName('🐎'.repeat(13))).toBeNull();
    expect(normalizeName('a\nb')).toBe('a b');
  });

  test('不正な名前は bad_name', () => {
    expect(join(newGame(), 'x', '   ', newId).error).toBe('bad_name');
  });

  test('同名が接続中で id が違えば name_taken(前後の空白違いも同名)', () => {
    const s = setup(['たろう']);
    expect(join(s, 'other', 'たろう', newId).error).toBe('name_taken');
    expect(join(s, 'other', ' たろう ', newId).error).toBe('name_taken');
  });

  test('同名が接続中で id も同じなら復帰し、古い接続を閉じる対象が返る', () => {
    const s = withCoins(setup(['たろう']), 'たろう', 777);
    const r = join(s, idOf('たろう'), 'たろう', newId);
    expect(r.error).toBeUndefined();
    expect(r.playerId).toBe(idOf('たろう'));
    expect(r.replacedId).toBe(idOf('たろう'));
    expect(r.state.players.length).toBe(1);
    expect(coins(r.state, 'たろう')).toBe(777);
  });

  test('同名が切断中なら別の id でも所持金を引き継いで復帰する', () => {
    let s = withCoins(setup(['たろう', 'はなこ']), 'たろう', 777);
    s = setOnline(s, idOf('たろう'), false);
    const r = join(s, 'fresh-id', 'たろう', newId);
    expect(r.error).toBeUndefined();
    expect(r.playerId).toBe('fresh-id');
    expect(r.state.players.length).toBe(2);
    const p = r.state.players.find((x) => x.name === 'たろう')!;
    expect(p).toMatchObject({ id: 'fresh-id', coins: 777, online: true });
  });

  test('別名で既存の id と重なったら新しい id で別人になる', () => {
    const s = setup(['たろう']);
    const r = join(s, idOf('たろう'), 'じろう', newId);
    expect(r.error).toBeUndefined();
    expect(r.playerId).toMatch(/^gen-/);
    expect(r.state.players.length).toBe(2);
    expect(new Set(r.state.players.map((p) => p.id)).size).toBe(2);
  });

  test('切断中の同名に復帰するとき、id が他人と重なるなら新しい id を使う', () => {
    let s = setup(['たろう', 'はなこ']);
    s = setOnline(s, idOf('たろう'), false);
    const r = join(s, idOf('はなこ'), 'たろう', newId);
    expect(r.error).toBeUndefined();
    expect(r.playerId).toMatch(/^gen-/);
    expect(new Set(r.state.players.map((p) => p.id)).size).toBe(2);
  });

  test('61 人目は room_full', () => {
    const s = setup(Array.from({ length: 60 }, (_, i) => `p${i}`));
    expect(join(s, 'x', 'p60', newId).error).toBe('room_full');
  });
});

describe('viewFor', () => {
  test('順位は同額同順位、所持金の多い順', () => {
    let s = setup(['a', 'b', 'c']);
    s = withCoins(s, 'c', 500);
    const v = viewFor(s, idOf('c'), false, 123);
    expect(v.players.map((p) => [p.name, p.rank])).toEqual([['a', 1], ['b', 1], ['c', 3]]);
    expect(v.me).toMatchObject({ id: idOf('c'), name: 'c', coins: 500, rank: 3, bet: null, lastResult: null });
    expect(v.serverNow).toBe(123);
    expect(v.totalRaces).toBe(5);
    expect(v.isAdmin).toBe(false);
  });

  test('賭け受付中は結果も他人の賭けも見えない', () => {
    let s = ok(adminStart(setup(['a', 'b']), seededRng(1)));
    s = ok(placeBet(s, idOf('a'), 1, 100));
    const v = viewFor(s, idOf('b'), false, 0);
    expect(v.race).toBeNull();
    expect(v.bets).toEqual([]);
    expect(v.players.every((p) => p.hasBet === false)).toBe(true);
    expect(v.betCount).toBe(1);
    expect(v.onlineCount).toBe(2);
    v.horses.forEach((h) => expect(Object.keys(h).sort()).toEqual(['name', 'no', 'odds']));
    const admin = viewFor(s, null, true, 0);
    expect(admin.me).toBeNull();
    expect(admin.isAdmin).toBe(true);
    expect(admin.players.find((p) => p.name === 'a')!.hasBet).toBe(true);
    expect(admin.players.find((p) => p.name === 'b')!.hasBet).toBe(false);
  });

  test('切断中の人は賭け済み人数・接続人数に数えない', () => {
    let s = ok(adminStart(setup(['a', 'b']), seededRng(1)));
    s = ok(placeBet(s, idOf('a'), 1, 100));
    s = setOnline(s, idOf('a'), false);
    const v = viewFor(s, null, true, 0);
    expect(v.betCount).toBe(0);
    expect(v.onlineCount).toBe(1);
    expect(v.players.find((p) => p.name === 'a')!.online).toBe(false);
  });

  test('レース中は race が見え、結果画面で全員の賭けが公開される', () => {
    let s = ok(adminStart(setup(['a', 'b']), seededRng(1)));
    s = ok(placeBet(s, idOf('a'), 1, 100));
    s = ok(adminCloseAndRace(s, seededRng(2), 0));
    const racing = viewFor(s, idOf('b'), false, 0);
    expect(racing.race!.order.length).toBe(8);
    expect(racing.race!.durationMs).toBe(20000);
    expect(racing.bets).toEqual([]);
    s = finishRace(s);
    const result = viewFor(s, idOf('b'), false, 0);
    expect(result.bets.length).toBe(1);
    expect(result.bets[0]).toMatchObject({ playerId: idOf('a'), horse: 1, amount: 100 });
    expect(typeof result.bets[0].delta).toBe('number');
    expect(result.race).not.toBeNull();
  });

  test('lobby と final では horses が空', () => {
    expect(viewFor(setup(['a']), null, false, 0).horses).toEqual([]);
  });

  test('存在しない id の me は null', () => {
    expect(viewFor(setup(['a']), 'ghost', false, 0).me).toBeNull();
  });
});

describe('退出・リセット', () => {
  test('kick で参加者が消える', () => {
    const r = kick(setup(['a', 'b']), idOf('a'));
    expect(r.error).toBeUndefined();
    expect(r.state.players.map((p) => p.name)).toEqual(['b']);
  });

  test('kickAll で 0 人・lobby', () => {
    const s = ok(adminStart(setup(['a', 'b']), seededRng(1)));
    const r = ok(kickAll(s));
    expect(r.players).toEqual([]);
    expect(r.phase).toBe('lobby');
    expect(r.raceNo).toBe(0);
  });

  test('adminReset はレース中でも lobby に戻し、参加者は残して全員 1000', () => {
    let s = ok(adminStart(setup(['a', 'b']), seededRng(1)));
    s = ok(placeBet(s, idOf('a'), 1, 500));
    s = ok(adminCloseAndRace(s, seededRng(2), 0));
    const r = ok(adminReset(s));
    expect(r.phase).toBe('lobby');
    expect(r.race).toBeNull();
    expect(r.horses).toEqual([]);
    expect(r.players.map((p) => [p.coins, p.bet, p.lastResult])).toEqual([[1000, null, null], [1000, null, null]]);
  });

  test('adminNewGame は final から lobby に戻す', () => {
    let s = ok(adminStart(setup(['a']), seededRng(1)));
    for (let i = 0; i < TOTAL_RACES; i++) {
      s = ok(adminNext(finishRace(ok(adminCloseAndRace(s, seededRng(i), 0))), seededRng(i + 10)));
    }
    expect(s.phase).toBe('final');
    const r = ok(adminNewGame(withCoins(s, 'a', 5)));
    expect(r.phase).toBe('lobby');
    expect(r.raceNo).toBe(0);
    expect(coins(r, 'a')).toBe(1000);
  });
});
