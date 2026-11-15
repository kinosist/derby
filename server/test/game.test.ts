import { describe, expect, test } from 'vitest';
import {
  adminCloseAndRace, adminNewGame, adminNext, adminReset, adminStart, buyTip, cancelBet, finishRace,
  cancelTicket, join, kick, kickAll, migrate, newGame, normalizeName, oddsMessage, placeBet, placeTicket,
  sameScene, setOnline, viewFor,
  type GameState,
} from '../src/game';
import { comboKey, makeOddsTable, payout, seededRng, START_COINS, TOTAL_RACES } from '../src/rules';

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
    expect(p('win').results).toMatchObject({ staked: 300, delta: payout(300, odds) - 300 });
    expect(p('win').results!.tickets).toMatchObject([{ type: 'win', horses: [1], amount: 300, odds, won: true, payout: payout(300, odds) }]);
    expect(p('lose').coins).toBe(800);
    expect(p('lose').results).toMatchObject({ staked: 200, delta: -200, tickets: [{ won: false, payout: 0 }] });
    expect(p('skip').coins).toBe(1000);
    expect(p('skip').results).toBeNull();
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
    expect(s.players.find((p) => p.name === 'late')!.tickets).toMatchObject([{ type: 'win', horses: [1], amount: 100 }]);
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
    expect(s.players[0].tickets).toMatchObject([{ type: 'win', horses: [4], amount: 500 }]);
    expect(s.players[0].tickets.length).toBe(1);
    s = ok(cancelBet(s, idOf('a')));
    expect(s.players[0].tickets).toEqual([]);
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
    v.horses.forEach((h) =>
      expect(Object.keys(h).sort()).toEqual(
        ['age', 'cond', 'mood', 'name', 'no', 'odds', 'pop', 'recent', 'sex', 'style', 'weight', 'weightDiff'],
      ),
    );
    // 本当の調子と勝率は、先生にも生徒にも送らない
    for (const view of [v, viewFor(s, null, true, 0)]) {
      const text = JSON.stringify(view);
      expect(text).not.toContain('trueCond');
      expect(text).not.toContain('rob"'); // prob / baseProb
    }
    expect([1200, 1400, 1600, 1800, 2000, 2400]).toContain(v.course!.distance);
    expect(['良', '稍重', '重', '不良']).toContain(v.course!.going);
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
    expect(racing.race!.durationMs).toBe(Math.max(...racing.race!.times.map((t) => t[10])) + 1500);
    expect(racing.course).not.toBeNull();
    expect(racing.bets).toEqual([]);
    s = finishRace(s);
    const result = viewFor(s, idOf('b'), false, 0);
    expect(result.bets.length).toBe(1);
    // 他人の賭けは、順位表のその人の行と同じ(公開用の)id で届く
    expect(result.bets[0]).toMatchObject({
      playerId: result.players.find((p) => p.name === 'a')!.id, horse: 1, amount: 100,
    });
    expect(typeof result.bets[0].delta).toBe('number');
    expect(result.race).not.toBeNull();
  });

  test('lobby と final では horses が空', () => {
    expect(viewFor(setup(['a']), null, false, 0).horses).toEqual([]);
    expect(viewFor(setup(['a']), null, false, 0).course).toBeNull();
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
    expect(r.players.map((p) => [p.coins, p.tickets, p.results])).toEqual([[1000, [], null], [1000, [], null]]);
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

describe('最終レビューの指摘', () => {
  test('進行操作は、先生が見ていた場面と今の場面が一致するときだけ通る(二重クリック対策)', () => {
    const lobby = setup(['a']);
    expect(sameScene(lobby, 'lobby', 0)).toBe(true);
    const betting = ok(adminStart(lobby, seededRng(1)));
    // 「試合開始」の二重クリック: 2回目は lobby を見て押されたもの
    expect(sameScene(betting, 'lobby', 0)).toBe(false);
    expect(sameScene(betting, 'betting', 1)).toBe(true);
    expect(sameScene(betting, 'betting', 2)).toBe(false);
    expect(sameScene(betting, undefined, undefined)).toBe(false);
    expect(sameScene(betting, 'betting', '1')).toBe(false);
  });

  test('生徒には他人の本当の id を見せない(なりすまし対策)', () => {
    let s = ok(adminStart(setup(['a', 'b']), seededRng(1)));
    s = ok(placeBet(s, idOf('a'), 1, 100));
    s = finishRace(ok(adminCloseAndRace(s, seededRng(2), 0)));
    const v = viewFor(s, idOf('b'), false, 0);
    const text = JSON.stringify(v);
    expect(text).not.toContain(idOf('a'));
    expect(v.me!.id).toBe(idOf('b'));
    // 自分の行は自分の id のまま(アプリが「自分の行」を見分けるため)
    expect(v.players.find((p) => p.name === 'b')!.id).toBe(idOf('b'));
    // 他人の行と、その人の賭けは、同じ公開用の id で結び付く
    const aRow = v.players.find((p) => p.name === 'a')!;
    expect(v.bets.map((x) => x.playerId)).toEqual([aRow.id]);
    // 公開用の id では参加(乗っ取り)できない
    expect(join(s, aRow.id, 'a', newId).error).toBe('name_taken');
    // 自分の賭けは自分の id で届く
    expect(viewFor(s, idOf('a'), false, 0).bets[0].playerId).toBe(idOf('a'));
    // 先生には本当の id が届く(個別の退出に使う)
    expect(viewFor(s, null, true, 0).players.map((p) => p.id).sort()).toEqual([idOf('a'), idOf('b')]);
  });

  test('公開用の id は入り直しても変わらず、参加者ごとに違う', () => {
    let s = setup(['a', 'b']);
    const before = viewFor(s, idOf('b'), false, 0).players.find((p) => p.name === 'a')!.id;
    s = setOnline(s, idOf('a'), false);
    s = ok(join(s, 'another-device', 'a', newId));
    const after = viewFor(s, idOf('b'), false, 0).players.find((p) => p.name === 'a')!.id;
    expect(after).toBe(before);
    expect(after).not.toBe('another-device');
    const mine = viewFor(s, 'another-device', false, 0).players.find((p) => p.name === 'b')!.id;
    expect(mine).not.toBe(after);
  });
});

describe('以前の形式で保存された状態', () => {
  test('course を持たない保存済みの状態でも view を作れる', () => {
    const old = { ...setup(['a']) } as Record<string, unknown>;
    delete old.course;
    const v = viewFor(old as unknown as GameState, idOf('a'), false, 0);
    expect(v.course).toBeNull();
    expect(v.phase).toBe('lobby');
  });
});

describe('馬券の種類と複数購入', () => {
  let n = 0;
  const tid = () => `t${++n}`;
  const betting = (names = ['a']) => ok(adminStart(setup(names), seededRng(1)));
  const me = (s: GameState) => s.players[0];

  test('4 種類の馬券を買える。倍率は倍率表のものが記録される', () => {
    let s = betting();
    const table = makeOddsTable(s.horses);
    s = ok(placeTicket(s, idOf('a'), 'win', [1], 100, tid));
    s = ok(placeTicket(s, idOf('a'), 'place', [2], 100, tid));
    s = ok(placeTicket(s, idOf('a'), 'quinella', [5, 3], 100, tid));
    s = ok(placeTicket(s, idOf('a'), 'trifecta', [4, 1, 2], 100, tid));
    expect(me(s).tickets.map((t) => [t.type, t.horses, t.amount, t.odds])).toEqual([
      ['win', [1], 100, s.horses[0].odds],
      ['place', [2], 100, table.place[1]],
      ['quinella', [3, 5], 100, table.quinella['3-5']], // 馬連は馬番の小さい順にそろえる
      ['trifecta', [4, 1, 2], 100, table.trifecta['4-1-2']],
    ]);
    expect(new Set(me(s).tickets.map((t) => t.id)).size).toBe(4);
    expect(me(s).coins).toBe(1000); // 引かれるのは締め切り時
  });

  test('同じ種類・同じ馬の馬券は金額を置き換える(馬連は順不同で同じ)', () => {
    let s = betting();
    s = ok(placeTicket(s, idOf('a'), 'quinella', [5, 3], 100, tid));
    const id = me(s).tickets[0].id;
    s = ok(placeTicket(s, idOf('a'), 'quinella', [3, 5], 400, tid));
    expect(me(s).tickets.length).toBe(1);
    expect(me(s).tickets[0]).toMatchObject({ id, amount: 400 });
    // 3連単は順番が違えば別の馬券
    s = ok(placeTicket(s, idOf('a'), 'trifecta', [1, 2, 3], 10, tid));
    s = ok(placeTicket(s, idOf('a'), 'trifecta', [3, 2, 1], 10, tid));
    expect(me(s).tickets.length).toBe(3);
  });

  test('合計が所持金を超える買い方はできない(置き換えは差し引きで判定)', () => {
    let s = betting();
    s = ok(placeTicket(s, idOf('a'), 'win', [1], 600, tid));
    expect(placeTicket(s, idOf('a'), 'place', [1], 410, tid).error).toBe('bad_bet');
    s = ok(placeTicket(s, idOf('a'), 'place', [1], 400, tid));
    expect(placeTicket(s, idOf('a'), 'win', [2], 10, tid).error).toBe('bad_bet');
    // 600 の馬券を 500 に置き換えるのは可、700 は不可
    expect(placeTicket(s, idOf('a'), 'win', [1], 700, tid).error).toBe('bad_bet');
    s = ok(placeTicket(s, idOf('a'), 'win', [1], 500, tid));
    expect(me(s).tickets.reduce((a, t) => a + t.amount, 0)).toBe(900);
  });

  test('1 レースに 10 点まで。11 点目は買えないが、置き換えはできる', () => {
    let s = betting();
    for (let h = 1; h <= 8; h++) s = ok(placeTicket(s, idOf('a'), 'win', [h], 10, tid));
    s = ok(placeTicket(s, idOf('a'), 'place', [1], 10, tid));
    s = ok(placeTicket(s, idOf('a'), 'place', [2], 10, tid));
    expect(me(s).tickets.length).toBe(10);
    expect(placeTicket(s, idOf('a'), 'place', [3], 10, tid).error).toBe('bad_bet');
    expect(placeTicket(s, idOf('a'), 'place', [2], 50, tid).error).toBeUndefined();
  });

  test('不正な馬券は bad_bet で state は不変', () => {
    const s = betting();
    const bad: [unknown, unknown, unknown][] = [
      ['exacta', [1, 2], 100], [null, [1], 100], ['win', [1, 2], 100], ['win', [], 100], ['win', 1, 100],
      ['quinella', [1], 100], ['quinella', [1, 1], 100], ['quinella', [1, 9], 100], ['quinella', [1, 2, 3], 100],
      ['trifecta', [1, 2], 100], ['trifecta', [1, 2, 2], 100], ['trifecta', [1, 2, 0], 100], ['trifecta', [1, 2, 3.5], 100],
      ['trifecta', ['1', 2, 3], 100], ['place', [1], 5], ['place', [1], 1010], ['place', [1], '100'], ['place', [1], -10],
      ['win', '__proto__', 100], ['__proto__', [1], 100], ['constructor', [1], 100],
    ];
    for (const [type, horses, amount] of bad) {
      const r = placeTicket(s, idOf('a'), type, horses, amount, tid);
      expect(r.error, JSON.stringify([type, horses, amount])).toBe('bad_bet');
      expect(r.state).toBe(s);
    }
    expect(placeTicket(s, 'nobody', 'win', [1], 100, tid).error).toBe('not_allowed');
    expect(placeTicket(setup(['a']), idOf('a'), 'win', [1], 100, tid).error).toBe('not_allowed');
  });

  test('1 点ずつ取り消せる。存在しない id は bad_bet', () => {
    let s = betting();
    s = ok(placeTicket(s, idOf('a'), 'win', [1], 100, tid));
    s = ok(placeTicket(s, idOf('a'), 'place', [2], 100, tid));
    const [first, second] = me(s).tickets;
    s = ok(cancelTicket(s, idOf('a'), first.id));
    expect(me(s).tickets).toEqual([second]);
    expect(cancelTicket(s, idOf('a'), 'nope').error).toBe('bad_bet');
    expect(cancelTicket(s, idOf('a'), 123).error).toBe('bad_bet');
    const racing = ok(adminCloseAndRace(s, seededRng(2), 0));
    expect(cancelTicket(racing, idOf('a'), second.id).error).toBe('not_allowed');
  });

  test('精算: 馬券ごとに当たり外れを判定し、払い戻しを合計する', () => {
    let s = betting(['a', 'b']);
    s = ok(placeTicket(s, idOf('a'), 'win', [1], 100, tid));
    s = ok(placeTicket(s, idOf('a'), 'place', [2], 100, tid));
    s = ok(placeTicket(s, idOf('a'), 'quinella', [1, 2], 100, tid));
    s = ok(placeTicket(s, idOf('a'), 'trifecta', [1, 2, 3], 100, tid));
    s = ok(placeTicket(s, idOf('a'), 'trifecta', [2, 1, 3], 100, tid));
    s = ok(placeTicket(s, idOf('a'), 'win', [8], 100, tid));
    // 着順が 1→2→3 で始まる乱数の種を探す
    let racing: GameState | undefined;
    for (let seed = 1; seed < 20000 && !racing; seed++) {
      const r = ok(adminCloseAndRace(s, seededRng(seed), 0));
      if (r.race!.order.slice(0, 3).join() === '1,2,3') racing = r;
    }
    expect(racing).toBeDefined();
    expect(racing!.players[0].coins).toBe(400); // 600 が引かれる
    const done = finishRace(racing!);
    const r = done.players[0].results!;
    expect(r.staked).toBe(600);
    expect(r.tickets.map((t) => t.won)).toEqual([true, true, true, true, false, false]);
    const expected = r.tickets.slice(0, 4).reduce((a, t) => a + payout(t.amount, t.odds), 0);
    expect(r.tickets.reduce((a, t) => a + t.payout, 0)).toBe(expected);
    expect(r.delta).toBe(expected - 600);
    expect(done.players[0].coins).toBe(400 + expected);
    expect(done.players[1].results).toBeNull();
    expect(finishRace(done)).toBe(done); // 二重に精算しない
  });

  test('次のレースで馬券と結果が消える', () => {
    let s = betting();
    s = ok(placeTicket(s, idOf('a'), 'place', [2], 100, tid));
    s = finishRace(ok(adminCloseAndRace(s, seededRng(2), 0)));
    s = ok(adminNext(s, seededRng(3)));
    expect(me(s).tickets).toEqual([]);
    expect(me(s).results).toBeNull();
  });

  test('view: 自分の馬券と結果が届き、ほかの人の馬券は結果画面で公開される', () => {
    let s = betting(['a', 'b']);
    s = ok(placeTicket(s, idOf('a'), 'place', [2], 100, tid));
    s = ok(placeTicket(s, idOf('a'), 'quinella', [1, 2], 200, tid));
    const mine = viewFor(s, idOf('a'), false, 0);
    expect(mine.me!.tickets.map((t) => [t.type, t.horses, t.amount])).toEqual([['place', [2], 100], ['quinella', [1, 2], 200]]);
    expect(mine.me!.results).toBeNull();
    expect(mine.raceKey).toBe(s.raceKey);
    const other = viewFor(s, idOf('b'), false, 0);
    expect(JSON.stringify(other)).not.toContain('quinella'); // 受付中は他人の馬券は見えない
    expect(other.betCount).toBe(1);
    expect(viewFor(s, null, true, 0).players.find((p) => p.name === 'a')!.hasBet).toBe(true);

    s = finishRace(ok(adminCloseAndRace(s, seededRng(2), 0)));
    const result = viewFor(s, idOf('b'), false, 0);
    expect(result.bets.length).toBe(1);
    expect(result.bets[0].amount).toBe(300);
    expect(result.bets[0].tickets.map((t) => [t.type, t.horses, t.amount])).toEqual([['place', [2], 100], ['quinella', [1, 2], 200]]);
    expect(result.bets[0].tickets.every((t) => typeof t.won === 'boolean' && typeof t.payout === 'number')).toBe(true);
    const myResult = viewFor(s, idOf('a'), false, 0).me!;
    expect(myResult.results!.staked).toBe(300);
    expect(myResult.results!.tickets.length).toBe(2);
  });

  test('古いアプリ向け: 従来の bet / lastResult の形でも届く', () => {
    let s = betting();
    s = ok(placeBet(s, idOf('a'), 3, 250)); // 従来の「単勝 1 点」
    let v = viewFor(s, idOf('a'), false, 0);
    expect(v.me!.bet).toEqual({ horse: 3, amount: 250 });
    expect(v.me!.tickets).toMatchObject([{ type: 'win', horses: [3], amount: 250 }]);
    // 従来の bet は「買い直し」: 既存の馬券を全部置き換える
    s = ok(placeTicket(s, idOf('a'), 'place', [1], 100, tid));
    s = ok(placeBet(s, idOf('a'), 4, 500));
    expect(me(s).tickets).toMatchObject([{ type: 'win', horses: [4], amount: 500 }]);
    expect(me(s).tickets.length).toBe(1);
    s = finishRace(ok(adminCloseAndRace(s, seededRng(2), 0)));
    v = viewFor(s, idOf('a'), false, 0);
    const r = me(s).results!;
    expect(v.me!.lastResult).toEqual({ horse: 4, amount: 500, won: r.delta > 0, delta: r.delta });
    expect(v.bets[0]).toMatchObject({ horse: 4, amount: 500, delta: r.delta });
    // 単勝を持たない人は、古いアプリには「賭けていない」と見える(表示できないため)
    let t = betting();
    t = ok(placeTicket(t, idOf('a'), 'place', [1], 100, tid));
    expect(viewFor(t, idOf('a'), false, 0).me!.bet).toBeNull();
  });

  test('倍率表のメッセージ: 賭け受付中だけ作られ、raceKey が状態と一致する', () => {
    expect(oddsMessage(setup(['a']))).toBeNull();
    const s = betting();
    const m = oddsMessage(s)!;
    expect(m.t).toBe('odds');
    expect(m.raceKey).toBe(s.raceKey);
    expect(m.place.length).toBe(8);
    expect(Object.keys(m.quinella).length).toBe(28);
    expect(Object.keys(m.trifecta).length).toBe(336);
    expect(m.quinella[comboKey('quinella', [2, 1])]).toBe(makeOddsTable(s.horses).quinella['1-2']);
    expect(oddsMessage(ok(adminCloseAndRace(s, seededRng(2), 0)))).toBeNull();
    // レースごとに raceKey が変わる
    const next = ok(adminNext(finishRace(ok(adminCloseAndRace(s, seededRng(2), 0))), seededRng(3)));
    expect(next.raceKey).not.toBe(s.raceKey);
    expect(typeof next.raceKey).toBe('string');
  });

  test('migrate: 以前の形式(bet / lastResult)で保存された状態を新しい形に直す', () => {
    const oldState = {
      phase: 'result', raceNo: 1,
      horses: [1, 2, 3, 4, 5, 6, 7, 8].map((no) => ({ no, name: `馬${no}`, prob: 0.125, odds: 8 })),
      race: { startedAt: 0, durationMs: 20000, order: [2, 1, 3, 4, 5, 6, 7, 8], times: [] },
      players: [
        { id: 'x', pub: 'px', name: 'Test', coins: 900, online: false, bet: { horse: 1, amount: 100 }, lastResult: { horse: 1, amount: 100, won: false, delta: -100 } },
        { id: 'y', pub: 'py', name: 'Skip', coins: 1000, online: false, bet: null, lastResult: null },
        { id: 'z', name: 'NoPub', coins: 1000, online: false, bet: null, lastResult: null },
      ],
    };
    const s = migrate(oldState);
    expect(s.players[0].tickets).toMatchObject([{ type: 'win', horses: [1], amount: 100, odds: 8 }]);
    expect(s.players[0].results).toMatchObject({ staked: 100, delta: -100, tickets: [{ won: false, payout: 0 }] });
    expect(s.players[1].tickets).toEqual([]);
    expect(s.players[1].results).toBeNull();
    expect(typeof s.players[2].pub).toBe('string');
    expect(s.players[2].pub.length).toBeGreaterThan(0);
    expect('bet' in s.players[0]).toBe(false);
    // 直した状態から view を作れ、次のレースにも進める
    const v = viewFor(s, 'x', false, 0);
    expect(v.me!.lastResult).toEqual({ horse: 1, amount: 100, won: false, delta: -100 });
    expect(ok(adminNext(s, seededRng(1))).phase).toBe('betting');
    // 新しい形の状態はそのまま
    const fresh = betting();
    expect(migrate(fresh)).toEqual(fresh);
    // 壊れた値は新しい試合にする
    expect(migrate(null).phase).toBe('lobby');
    expect(migrate({ phase: 'weird' }).phase).toBe('lobby');
  });

  test('migrate: 公開用の id を持たない参加者には、本当の id と無関係な値を振る', () => {
    const s = migrate({
      phase: 'lobby', raceNo: 0, horses: [], race: null,
      players: [{ id: 'secret-id-123', name: 'A', coins: 1000, online: false, bet: null, lastResult: null }],
    });
    expect(s.players[0].pub).not.toContain('secret-id-123');
    expect(s.players[0].pub.length).toBeGreaterThanOrEqual(8);
    expect(JSON.stringify(viewFor(s, null, false, 0))).not.toContain('secret-id-123');
  });

  test('migrate: 参加者の一覧が壊れていても落ちず、新しい試合にする', () => {
    for (const players of [[null], ['x'], [42], [{ id: 1 }], [{ id: 'a', name: 'A', coins: 'many' }]]) {
      const s = migrate({ phase: 'lobby', raceNo: 0, horses: [], race: null, players });
      expect(s.phase).toBe('lobby');
      expect(s.players).toEqual([]);
    }
  });
});

describe('予想屋', () => {
  let n = 0;
  const tid = () => `x${++n}`;
  const betting = (names = ['a', 'b']) => ok(adminStart(setup(names), seededRng(1)));
  const player = (s: GameState, name: string) => s.players.find((p) => p.name === name)!;

  test('賭け受付中は予想屋の一覧が届く。それ以外では届かない', () => {
    const s = betting();
    const v = viewFor(s, idOf('a'), false, 0);
    expect(v.tipsters).toEqual([
      { id: 'paper', name: '競馬新聞', price: 30, stars: 1 },
      { id: 'veteran', name: 'ベテラン予想屋', price: 80, stars: 2 },
      { id: 'master', name: '伝説の予想屋', price: 150, stars: 3 },
    ]);
    expect(v.me!.tips).toEqual([]);
    expect(v.tipResults).toEqual([]);
    expect(viewFor(setup(['a']), idOf('a'), false, 0).tipsters).toEqual([]);
    expect(viewFor(ok(adminCloseAndRace(s, seededRng(2), 0)), idOf('a'), false, 0).tipsters).toEqual([]);
  });

  test('料金を払うと予想(◎○▲)が本人にだけ届き、所持金がその場で減る', () => {
    let s = betting();
    s = ok(buyTip(s, idOf('a'), 'veteran'));
    expect(player(s, 'a').coins).toBe(920);
    const mine = viewFor(s, idOf('a'), false, 0);
    expect(mine.me!.coins).toBe(920);
    expect(mine.me!.tips.length).toBe(1);
    expect(mine.me!.tips[0].id).toBe('veteran');
    expect(mine.me!.tips[0].marks).toEqual(s.tips!.veteran.marks);
    expect(mine.me!.tips[0].marks.length).toBe(3);
    expect(typeof mine.me!.tips[0].comment).toBe('string');
    // 買っていない人と先生には、予想の中身は届かない
    for (const other of [viewFor(s, idOf('b'), false, 0), viewFor(s, null, true, 0)]) {
      const text = JSON.stringify(other);
      expect(text).not.toContain('marks');
      expect(text).not.toContain('comment');
    }
    // 2 人目も同じ内容を受け取る(予想屋ごとに 1 レース 1 つ)
    s = ok(buyTip(s, idOf('b'), 'veteran'));
    expect(viewFor(s, idOf('b'), false, 0).me!.tips[0].marks).toEqual(mine.me!.tips[0].marks);
  });

  test('3 人とも買える。同じ予想屋は 1 レースに 1 回だけ', () => {
    let s = betting();
    s = ok(buyTip(s, idOf('a'), 'paper'));
    s = ok(buyTip(s, idOf('a'), 'master'));
    s = ok(buyTip(s, idOf('a'), 'veteran'));
    expect(player(s, 'a').coins).toBe(1000 - 30 - 150 - 80);
    expect(viewFor(s, idOf('a'), false, 0).me!.tips.map((t) => t.id)).toEqual(['paper', 'veteran', 'master']); // 一覧の順
    const again = buyTip(s, idOf('a'), 'paper');
    expect(again.error).toBe('bad_bet');
    expect(again.state).toBe(s);
  });

  test('買えない場合: 知らない予想屋、受付中でない、未参加、コイン不足', () => {
    const s = betting();
    for (const id of ['nobody', '', null, 42, '__proto__', 'constructor', ['paper']]) {
      const r = buyTip(s, idOf('a'), id);
      expect(r.error, String(id)).toBe('bad_bet');
      expect(r.state).toBe(s);
    }
    expect(buyTip(s, 'ghost', 'paper').error).toBe('not_allowed');
    expect(buyTip(setup(['a']), idOf('a'), 'paper').error).toBe('not_allowed');
    expect(buyTip(ok(adminCloseAndRace(s, seededRng(2), 0)), idOf('a'), 'paper').error).toBe('not_allowed');
    // 所持金 100 では 150 コインの予想屋は買えない
    const poor = { ...s, players: s.players.map((p) => (p.name === 'a' ? { ...p, coins: 100 } : p)) };
    expect(buyTip(poor, idOf('a'), 'master').error).toBe('bad_bet');
    expect(buyTip(poor, idOf('a'), 'veteran').error).toBeUndefined();
  });

  test('料金を払うと馬券の合計が所持金を超えるなら買えない。払ったあとは残りの範囲でしか賭けられない', () => {
    let s = betting();
    s = ok(placeTicket(s, idOf('a'), 'win', [1], 900, tid));
    expect(buyTip(s, idOf('a'), 'master').error).toBe('bad_bet'); // 1000 - 150 < 900
    s = ok(buyTip(s, idOf('a'), 'veteran')); // 1000 - 80 = 920 >= 900
    expect(player(s, 'a').coins).toBe(920);
    expect(placeTicket(s, idOf('a'), 'place', [2], 30, tid).error).toBe('bad_bet'); // 900 + 30 > 920
    s = ok(placeTicket(s, idOf('a'), 'place', [2], 20, tid));
    // 締め切り: 920 - 920 = 0
    s = ok(adminCloseAndRace(s, seededRng(2), 0));
    expect(player(s, 'a').coins).toBe(0);
  });

  test('レース中・結果画面でも自分の買った予想は見える。次のレースで消え、予想も作り直される', () => {
    let s = betting();
    s = ok(buyTip(s, idOf('a'), 'paper'));
    const first = s.tips!;
    s = ok(adminCloseAndRace(s, seededRng(2), 0));
    expect(viewFor(s, idOf('a'), false, 0).me!.tips.length).toBe(1);
    s = finishRace(s);
    expect(viewFor(s, idOf('a'), false, 0).me!.tips.length).toBe(1);
    s = ok(adminNext(s, seededRng(3)));
    expect(viewFor(s, idOf('a'), false, 0).me!.tips).toEqual([]);
    expect(player(s, 'a').tips).toEqual([]);
    expect(s.tips).not.toBe(first);
    expect(Object.keys(s.tips!).sort()).toEqual(['master', 'paper', 'veteran']);
  });

  test('結果画面では、3 人の予想と ◎ が 1 着だったかを全員に公開する', () => {
    let s = betting();
    s = finishRace(ok(adminCloseAndRace(s, seededRng(2), 0)));
    const winner = s.race!.order[0];
    for (const v of [viewFor(s, idOf('b'), false, 0), viewFor(s, null, true, 0)]) {
      expect(v.tipResults.map((t) => [t.id, t.name])).toEqual([['paper', '競馬新聞'], ['veteran', 'ベテラン予想屋'], ['master', '伝説の予想屋']]);
      for (const t of v.tipResults) {
        expect(t.marks).toEqual(s.tips![t.id as 'paper'].marks);
        expect(t.hit).toBe(t.marks[0] === winner);
      }
    }
  });

  test('リセットと新しい試合で、買った予想は消える。料金は戻らないが所持金は 1,000 に戻る', () => {
    let s = betting();
    s = ok(buyTip(s, idOf('a'), 'master'));
    const r = ok(adminReset(s));
    expect(player(r, 'a').tips).toEqual([]);
    expect(player(r, 'a').coins).toBe(1000);
    expect(r.tips ?? null).toBeNull();
  });

  test('以前の形式で保存された状態(予想屋なし)でも、view を作れて予想屋を買える', () => {
    const s = betting();
    const old = { ...s, players: s.players.map(({ tips: _tips, ...p }) => p) } as unknown as GameState;
    delete (old as { tips?: unknown }).tips;
    const m = migrate(old);
    const v = viewFor(m, idOf('a'), false, 0);
    expect(v.me!.tips).toEqual([]);
    expect(v.tipsters.length).toBe(3);
    const bought = ok(buyTip(m, idOf('a'), 'paper'));
    expect(viewFor(bought, idOf('a'), false, 0).me!.tips[0].marks.length).toBe(3);
    // 予想を持たない古い状態のまま結果まで進んでも落ちない
    const done = finishRace(ok(adminCloseAndRace(m, seededRng(2), 0)));
    expect(viewFor(done, idOf('a'), false, 0).tipResults.length).toBe(3);
  });

  test('料金を払って所持金を 10 コイン未満にすることはできない(救済の 100 コインで得をさせない)', () => {
    const s = betting();
    const withCoinsA = (c: number) => ({ ...s, players: s.players.map((p) => (p.name === 'a' ? { ...p, coins: c } : p)) });
    for (const c of [30, 35, 39]) expect(buyTip(withCoinsA(c), idOf('a'), 'paper').error, `所持金 ${c}`).toBe('bad_bet');
    const ok40 = ok(buyTip(withCoinsA(40), idOf('a'), 'paper'));
    expect(player(ok40, 'a').coins).toBe(10);
    expect(buyTip(withCoinsA(89), idOf('a'), 'veteran').error).toBe('bad_bet');
    expect(buyTip(withCoinsA(90), idOf('a'), 'veteran').error).toBeUndefined();
  });

  test('予想の一部が欠けた状態でも view を作れる(予想屋が増えた場合など)', () => {
    let s = betting();
    s = ok(buyTip(s, idOf('a'), 'paper'));
    s = ok(buyTip(s, idOf('a'), 'master'));
    const partial = { ...s, tips: { paper: s.tips!.paper } } as unknown as GameState;
    const v = viewFor(partial, idOf('a'), false, 0);
    expect(v.me!.tips.map((t) => t.id)).toEqual(['paper']);
    const done = finishRace(ok(adminCloseAndRace(partial, seededRng(2), 0)));
    expect(viewFor(done, idOf('a'), false, 0).tipResults.map((t) => t.id)).toEqual(['paper']);
    // 欠けている予想屋は買えない
    expect(buyTip(partial, idOf('b'), 'veteran').error).toBe('bad_bet');
  });

  test('migrate: レース中・結果の状態には、あとから予想を作らない(結果が決まった後の予想は意味がない)', () => {
    const s = betting();
    const strip = (x: GameState) => {
      const o = { ...x, players: x.players.map(({ tips: _t, ...p }) => p) } as unknown as GameState;
      delete (o as { tips?: unknown }).tips;
      return o;
    };
    const racing = ok(adminCloseAndRace(s, seededRng(2), 0));
    for (const old of [strip(racing), strip(finishRace(racing))]) {
      const m = migrate(old);
      expect(m.tips ?? null).toBeNull();
      expect(viewFor(m, idOf('a'), false, 0).tipResults).toEqual([]);
      expect(m.players.every((p) => Array.isArray(p.tips))).toBe(true);
    }
    // 賭け受付中の状態には作る(そのレースから予想屋を使える)
    expect(Object.keys(migrate(strip(s)).tips!).length).toBe(3);
  });
});
