// 擬似クライアントによる通し確認。
//   node scripts/sim.mjs                       先生役+生徒 40 人で 1 試合を通し、動作を検証する
//   node scripts/sim.mjs --no-admin --players 10
//                                              生徒役だけ。管理ページの操作に合わせて賭け続ける(Ctrl+C で終了)
// オプション: --url ws://127.0.0.1:8787/ws  --key dev  --players 40

const args = process.argv.slice(2);
const opt = (name, def) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 && args[i + 1] !== undefined ? args[i + 1] : def;
};
const URL_ = opt('url', 'ws://127.0.0.1:8787/ws');
const KEY = opt('key', 'dev');
const N = Number(opt('players', '40'));
const NO_ADMIN = args.includes('--no-admin');
const RUN = Math.random().toString(36).slice(2, 8);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let checks = 0;
function check(cond, what) {
  checks++;
  if (!cond) {
    console.error(`NG: ${what}`);
    process.exit(1);
  }
}

class Client {
  constructor(label) {
    this.label = label;
    this.state = null;
    this.errors = [];
    this.closeCode = null;
    this.waiters = [];
    this.onState = null;
  }
  open() {
    return new Promise((resolve, reject) => {
      this.ws = new WebSocket(URL_);
      this.ws.addEventListener('open', () => resolve(this));
      this.ws.addEventListener('error', () => reject(new Error(`${this.label}: 接続できません (${URL_})`)));
      this.ws.addEventListener('close', (e) => {
        this.closeCode = e.code;
        this.notify();
      });
      this.ws.addEventListener('message', (e) => {
        const m = JSON.parse(e.data);
        if (m.t === 'state') {
          this.state = m;
          this.onState?.(m);
        } else if (m.t === 'odds') this.odds = m;
        else if (m.t === 'error') this.errors.push(m.code);
        this.notify();
      });
    });
  }
  notify() {
    this.waiters = this.waiters.filter((w) => !w());
  }
  send(o) {
    this.ws.send(typeof o === 'string' ? o : JSON.stringify(o));
  }
  /** pred(this) が真になるまで待つ */
  wait(pred, what, timeoutMs = 5000) {
    return new Promise((resolve) => {
      let timer;
      const tryNow = () => {
        if (!pred(this)) return false;
        clearTimeout(timer);
        resolve();
        return true;
      };
      if (tryNow()) return;
      timer = setTimeout(() => check(false, `${this.label}: 待機がタイムアウト: ${what}`), timeoutMs);
      this.waiters.push(tryNow);
    });
  }
  waitPhase(phase, raceNo, timeoutMs) {
    return this.wait((c) => c.state?.phase === phase && (raceNo === undefined || c.state.raceNo === raceNo),
      `phase=${phase} race=${raceNo}`, timeoutMs);
  }
  async expectError(code, what) {
    const before = this.errors.length;
    await this.wait((c) => c.errors.length > before, `${what} → error`);
    check(this.errors[this.errors.length - 1] === code, `${what} → ${code}(実際: ${this.errors[this.errors.length - 1]})`);
  }
  close() {
    this.ws.close();
  }
}

const expectedPayout = (amount, odds) => Math.floor((amount * Math.round(odds * 10)) / 10);
const playerName = (i) => `生徒${String(i + 1).padStart(2, '0')}`;
const playerId = (i) => `sim-${RUN}-${i}`;

async function joinPlayer(i) {
  const c = await new Client(playerName(i)).open();
  c.send({ t: 'join', id: playerId(i), name: playerName(i) });
  await c.wait((x) => x.state?.me?.name === playerName(i), 'join');
  return c;
}

function randomBet(state) {
  const coins = state.me.coins;
  if (coins < 10 || Math.random() < 0.1) return null;
  const max = Math.min(coins, 300);
  return { horse: 1 + Math.floor(Math.random() * 8), amount: 10 * (1 + Math.floor(Math.random() * Math.floor(max / 10))) };
}

const TYPES = { win: 1, place: 1, quinella: 2, trifecta: 3 };
const pickHorses = (n) => [1, 2, 3, 4, 5, 6, 7, 8].sort(() => Math.random() - 0.5).slice(0, n);
const comboKey = (type, horses) => (type === 'quinella' ? [...horses].sort((a, b) => a - b) : horses).join('-');

/** 1〜4 点の馬券をランダムに選ぶ(合計は所持金と 400 コインの小さい方まで)。1 割は見送り。 */
function randomTickets(state) {
  let budget = Math.min(state.me.coins, 400);
  if (budget < 10 || Math.random() < 0.1) return [];
  const tickets = [];
  const count = 1 + Math.floor(Math.random() * 4);
  for (let i = 0; i < count && budget >= 10; i++) {
    const type = Object.keys(TYPES)[Math.floor(Math.random() * 4)];
    const horses = pickHorses(TYPES[type]);
    if (tickets.some((t) => t.type === type && comboKey(type, t.horses) === comboKey(type, horses))) continue;
    const amount = 10 * (1 + Math.floor(Math.random() * Math.min(10, Math.floor(budget / 10))));
    budget -= amount;
    tickets.push({ type, horses, amount });
  }
  return tickets;
}

/** 倍率表から馬券の倍率を引く(端末側の計算) */
function oddsOf(client, t) {
  if (t.type === 'win') return client.state.horses.find((h) => h.no === t.horses[0]).odds;
  if (t.type === 'place') return client.odds.place[t.horses[0] - 1];
  return client.odds[t.type][comboKey(t.type, t.horses)];
}

function wins(t, order) {
  if (t.type === 'win') return order[0] === t.horses[0];
  if (t.type === 'place') return order.slice(0, 3).includes(t.horses[0]);
  if (t.type === 'quinella') return t.horses.includes(order[0]) && t.horses.includes(order[1]);
  return t.horses.every((h, i) => order[i] === h);
}

// ---- 生徒役だけのモード ----
async function runPlayersOnly() {
  const players = [];
  for (let i = 0; i < N; i++) players.push(await joinPlayer(i));
  console.log(`${N} 人が参加しました。管理ページで進行してください(Ctrl+C で終了)。`);
  for (const p of players) {
    let betFor = -1;
    const act = (s) => {
      if (s.phase === 'betting' && s.me && !s.me.bet && betFor !== s.raceNo) {
        betFor = s.raceNo;
        randomTickets(s).forEach((t, i) =>
          setTimeout(() => p.ws.readyState === 1 && p.send({ t: 'bet', ...t }), 500 + Math.random() * 5000 + i * 300));
      }
    };
    p.onState = act;
    if (p.state) act(p.state);
  }
  await new Promise(() => {});
}

/** 先生役の進行操作。見ている場面(phase と raceNo)を添えて送る。 */
function advance(admin, action) {
  admin.send({ t: 'adminAction', action, phase: admin.state.phase, raceNo: admin.state.raceNo });
}

// ---- 通し確認 ----
async function runFull() {
  // 先生の認証
  const wrong = await new Client('wrong-key').open();
  wrong.send({ t: 'admin', key: 'definitely-wrong' });
  await wrong.expectError('bad_key', '間違ったパスワード');
  wrong.send({ t: 'adminAction', action: 'start' });
  await wrong.expectError('not_allowed', '未認証の進行操作');
  wrong.close();

  const admin = await new Client('admin').open();
  admin.send({ t: 'admin', key: KEY });
  await admin.wait((c) => c.state?.isAdmin === true, 'admin 認証');
  admin.send({ t: 'adminAction', action: 'kickAll' });
  await admin.wait((c) => c.state.players.length === 0 && c.state.phase === 'lobby', '部屋を空にする');

  // 壊れたメッセージ(Review Focus 3)
  const raw = await new Client('raw').open();
  raw.send('not json');
  await raw.expectError('bad_message', 'JSON でない');
  raw.send('x'.repeat(3000));
  await raw.expectError('bad_message', '3000 文字');
  raw.send('[1,2]');
  await raw.expectError('bad_message', '配列');
  raw.send({ t: 'unknown' });
  await raw.expectError('bad_message', '不明な種類');
  raw.send({ t: 'bet', horse: 1, amount: 100 });
  await raw.expectError('not_allowed', '未参加の賭け');
  raw.send({ t: 'join', id: 'raw', name: '   ' });
  await raw.expectError('bad_name', '空白だけの名前');
  raw.close();

  // 参加
  const players = await Promise.all(Array.from({ length: N }, (_, i) => joinPlayer(i)));
  await admin.wait((c) => c.state.players.length === N && c.state.onlineCount === N, `${N} 人参加`);
  console.log(`${N} 人が参加`);

  const dup = await new Client('dup').open();
  dup.send({ t: 'join', id: 'someone-else', name: playerName(0) });
  await dup.expectError('name_taken', '接続中の人と同じ名前');
  dup.close();

  players[2].send({ t: 'adminAction', action: 'start' });
  await players[2].expectError('not_allowed', '生徒からの進行操作');
  players[2].send({ t: 'bet', horse: 1, amount: 100 });
  await players[2].expectError('not_allowed', 'lobby での賭け');

  admin.send({ t: 'adminAction', action: 'start' });
  await admin.expectError('not_allowed', '場面を添えない進行操作');
  // 「試合開始」の二重クリック: 2回目も lobby を見て押されたものなので、レースを始めてはいけない
  advance(admin, 'start');
  admin.send({ t: 'adminAction', action: 'closeAndRace', phase: 'lobby', raceNo: 0 });
  await admin.expectError('not_allowed', '「試合開始」の二重クリック');
  const totalRaces = 5;

  for (let race = 1; race <= totalRaces; race++) {
    await Promise.all(players.map((p) => p.waitPhase('betting', race)));
    await admin.waitPhase('betting', race);
    for (const p of players) {
      check(p.state.race === null && p.state.bets.length === 0, '賭け受付中に結果が見えない');
      check(p.state.horses.length === 8, '出走馬 8 頭');
      check(p.state.horses.every((h) => !('prob' in h) && !('baseProb' in h) && !('trueCond' in h)), '勝率と本当の調子は送られない');
      check(p.state.horses.every((h) => h.cond >= 1 && h.cond <= 5 && typeof h.mood === 'string' && h.recent.length === 3), '出走表の項目がそろっている');
      check(p.state.course && p.state.course.distance >= 1200, '距離と馬場が届く');
      await p.wait((c) => c.odds?.raceKey === c.state.raceKey, '倍率表が届く');
      check(p.odds.place.length === 8 && Object.keys(p.odds.quinella).length === 28 && Object.keys(p.odds.trifecta).length === 336, '倍率表の大きさ');
    }

    if (race === 1) {
      // 不正な賭け(Review Focus 3)
      players[3].send({ t: 'bet', horse: 99, amount: -5 });
      await players[3].expectError('bad_bet', '馬番 99・金額 -5');
      players[3].send({ t: 'bet', horse: 1, amount: 15 });
      await players[3].expectError('bad_bet', '10 の倍数でない');
      players[3].send({ t: 'bet', horse: 1, amount: 999990 });
      await players[3].expectError('bad_bet', '所持金を超える');
      players[3].send({ t: 'bet', type: 'exacta', horses: [1, 2], amount: 10 });
      await players[3].expectError('bad_bet', '存在しない種類の馬券');
      players[3].send({ t: 'bet', type: 'trifecta', horses: [1, 1, 2], amount: 10 });
      await players[3].expectError('bad_bet', '同じ馬を 2 回選んだ 3連単');
      players[3].send({ t: 'bet', type: 'quinella', horses: [1], amount: 10 });
      await players[3].expectError('bad_bet', '頭数の足りない馬連');
      players[3].send({ t: 'cancelBet', id: 'nope' });
      await players[3].expectError('bad_bet', '存在しない馬券の取り消し');
      // 買ってから 1 点だけ取り消す
      players[3].send({ t: 'bet', type: 'place', horses: [1], amount: 10 });
      players[3].send({ t: 'bet', type: 'win', horses: [2], amount: 10 });
      await players[3].wait((c) => c.state.me.tickets.length === 2, '2 点買う');
      players[3].send({ t: 'cancelBet', id: players[3].state.me.tickets[0].id });
      await players[3].wait((c) => c.state.me.tickets.length === 1 && c.state.me.tickets[0].type === 'win', '1 点だけ取り消す');
      players[3].send({ t: 'cancelBet' });
      await players[3].wait((c) => c.state.me.tickets.length === 0, '全部取り消す');
    }

    if (race === 2) {
      // 同じ生徒の二重接続(Review Focus 2)
      const old = players[1];
      const coinsBefore = old.state.me.coins;
      const fresh = await new Client(playerName(1) + '(2本目)').open();
      fresh.send({ t: 'join', id: playerId(1), name: playerName(1) });
      await fresh.wait((c) => c.state?.me?.name === playerName(1), '2本目で参加');
      await old.wait((c) => c.closeCode !== null, '1本目が閉じられる');
      check(old.closeCode === 4000, `1本目の close code が 4000(実際: ${old.closeCode})`);
      check(fresh.state.players.length === N, '二重接続で参加者が増えない');
      check(fresh.state.me.coins === coinsBefore, '二重接続で所持金が変わらない');
      await sleep(300);
      check(admin.state.players.find((x) => x.name === playerName(1)).online === true, '二重接続後も接続中');
      players[1] = fresh;
    }

    // 賭ける。players[6] は古いアプリの形式(単勝 1 点)で送る。
    const plans = players.map((p, i) => {
      const before = p.state.me.coins;
      if (i === 6) {
        const b = randomBet(p.state);
        return { p, before, legacy: true, tickets: b ? [{ type: 'win', horses: [b.horse], amount: b.amount }] : [] };
      }
      return { p, before, legacy: false, tickets: randomTickets(p.state) };
    });
    for (const plan of plans) {
      plan.total = plan.tickets.reduce((a, t) => a + t.amount, 0);
      for (const t of plan.tickets) {
        t.odds = oddsOf(plan.p, t);
        plan.p.send(plan.legacy ? { t: 'bet', horse: t.horses[0], amount: t.amount } : { t: 'bet', ...t });
      }
    }
    await Promise.all(plans.map(({ p, tickets }) => p.wait((c) => c.state.me.tickets.length === tickets.length, '馬券の反映')));
    for (const { p, tickets, legacy } of plans) {
      tickets.forEach((t) => {
        const got = p.state.me.tickets.find((x) => x.type === t.type && comboKey(t.type, x.horses) === comboKey(t.type, t.horses));
        check(got && got.amount === t.amount && got.odds === t.odds, `${p.label}: 馬券 ${t.type} ${t.horses} の金額と倍率が一致`);
      });
      if (legacy && tickets.length) check(p.state.me.bet.horse === tickets[0].horses[0] && p.state.me.bet.amount === tickets[0].amount, '古い形式の bet も届く');
    }
    const betCount = plans.filter((x) => x.tickets.length > 0).length;
    await admin.wait((c) => c.state.betCount === betCount, `賭け済み ${betCount} 人`);
    check(admin.state.players.filter((x) => x.hasBet).length === betCount, '先生には賭け済みの印が見える');
    check(players[0].state.players.every((x) => x.hasBet === false), '生徒には他人の賭け済みが見えない');
    check(!JSON.stringify(players[0].state.players).includes('tickets'), '受付中は他人の馬券が見えない');

    // 締め切り(連打: Review Focus 1)
    const t0 = Date.now();
    advance(admin, 'closeAndRace');
    advance(admin, 'closeAndRace');
    await admin.expectError('not_allowed', '締め切りの連打');
    await Promise.all(players.map((p) => p.waitPhase('racing', race)));
    const startedAt = players[0].state.race.startedAt;
    for (const { p, before, total } of plans) {
      check(p.state.me.coins === before - total, '締め切りで賭け金の合計が引かれる');
      check(p.state.race.startedAt === startedAt && p.state.race.times.length === 8, 'レース映像データが同じ');
    }
    players[4].send({ t: 'bet', horse: 1, amount: 10 });
    await players[4].expectError('not_allowed', 'レース中の賭け');

    if (race === 1) {
      // レース中の復帰(Review Focus 4)
      await sleep(8000);
      players[0].close();
      await admin.wait((c) => c.state.players.find((x) => x.name === playerName(0)).online === false, '切断が反映される');
      const back = await joinPlayer(0);
      check(back.state.phase === 'racing' && back.state.race.startedAt === startedAt, '復帰後も同じレース');
      const elapsed = back.state.serverNow - back.state.race.startedAt;
      check(elapsed >= 7000 && elapsed <= 10000, `復帰時の経過時間が 7〜10 秒(実際: ${elapsed}ms)`);
      check(back.state.me.coins === plans[0].before - plans[0].total, '復帰後も所持金が同じ');
      check(back.state.me.tickets.length === plans[0].tickets.length, '復帰後も馬券が残っている');
      players[0] = back;
      plans[0].p = back;
    }

    // 結果(自動で進む)
    const durationMs = players[0].state.race.durationMs;
    check(durationMs >= 22000 && durationMs <= 35000, `レースの長さは 22〜35 秒(実際: ${durationMs}ms)`);
    await Promise.all(players.map((p) => p.waitPhase('result', race, 45000)));
    const took = Date.now() - t0;
    check(took >= durationMs - 500 && took <= durationMs + 3000, `レースは予定の時間で終わる(予定 ${durationMs}ms、実際 ${took}ms)`);
    const s0 = players[0].state;
    const winner = s0.race.order[0];
    const odds = s0.horses.find((h) => h.no === winner).odds;
    const finish = s0.race.times.map((t) => t[10]);
    check([...s0.race.order].sort((a, b) => finish[a - 1] - finish[b - 1]).join() === s0.race.order.join(), '映像のゴール順が着順と一致');
    let hits = 0;
    for (const { p, before, tickets, total, legacy } of plans) {
      const me = p.state.me;
      if (tickets.length === 0) {
        check(me.coins === before && me.results === null && me.lastResult === null, '見送りは所持金不変');
        continue;
      }
      // 馬券ごとに、端末側で計算した払い戻しと一致するか
      let back = 0;
      for (const t of tickets) {
        const won = wins(t, s0.race.order);
        const pay = won ? expectedPayout(t.amount, t.odds) : 0;
        back += pay;
        if (won) hits++;
        const got = me.results.tickets.find((x) => x.type === t.type && comboKey(t.type, x.horses) === comboKey(t.type, t.horses));
        check(got && got.won === won && got.payout === pay, `${p.label}: ${t.type} ${t.horses} の当たり外れと払い戻し`);
      }
      check(me.coins === before - total + back, `${p.label}: 所持金 ${me.coins} が計算 ${before - total + back} と一致`);
      check(me.results.staked === total && me.results.delta === back - total, '結果の合計が一致');
      check(me.lastResult.delta === back - total && me.lastResult.amount === total, '古い形式の結果も一致');
      if (legacy) check(me.lastResult.horse === tickets[0].horses[0], '古い形式の結果の馬番');
    }
    check(s0.bets.every((b) => Array.isArray(b.tickets) && b.tickets.length > 0), '結果画面で全員の馬券の内容が公開される');
    check(s0.bets.length === betCount, '結果画面で全員の賭けが公開される');
    console.log(`第${race}レース: 1着 ${winner}番(${odds}倍)、${betCount} 人が賭け、的中 ${hits} 点、${took}ms`);

    // 次へ(連打: Review Focus 1)
    // 「次のレースへ」の二重クリック: 2回目は結果画面を見て押されたもの。
    // 次の場面のボタン(締め切り・新しい試合)として働いてはいけない。
    await admin.waitPhase('result', race);
    const seen = { phase: admin.state.phase, raceNo: admin.state.raceNo };
    advance(admin, 'next');
    admin.send({ t: 'adminAction', action: race === totalRaces ? 'newGame' : 'closeAndRace', ...seen });
    await admin.expectError('not_allowed', '「次へ」の二重クリック');
    await sleep(300);
    check(admin.state.phase === (race === totalRaces ? 'final' : 'betting'), '二重クリックでレースや最終結果が飛ばない');
    for (const p of players) {
      const others = p.state.players.filter((x) => x.name !== p.state.me.name);
      check(others.every((x) => !x.id.startsWith('sim-')), '他人の本当の id は届かない');
    }
  }

  await Promise.all(players.map((p) => p.waitPhase('final', totalRaces)));
  const board = players[0].state.players;
  check(board.length === N, '最終結果に全員いる');
  for (let i = 1; i < board.length; i++) {
    check(board[i - 1].coins >= board[i].coins && board[i - 1].rank <= board[i].rank, '最終順位は所持金順');
  }
  console.log(`最終結果: 1位 ${board[0].name} ${board[0].coins} コイン`);

  // 個別の退出と全員の退出
  admin.send({ t: 'adminAction', action: 'kick', playerId: players[5].state.me.id });
  await players[5].wait((c) => c.closeCode !== null, '退出させられた接続が閉じる');
  check(players[5].errors.includes('kicked') && players[5].closeCode === 4001, '退出の通知');
  await admin.wait((c) => c.state.players.length === N - 1, '退出で 1 人減る');
  admin.send({ t: 'adminAction', action: 'kickAll' });
  await admin.wait((c) => c.state.players.length === 0 && c.state.phase === 'lobby', '全員退出');
  await Promise.all(players.map((p) => p.wait((c) => c.closeCode !== null, '全員の接続が閉じる')));
  admin.close();
  console.log(`ALL OK(${checks} 項目)`);
  process.exit(0);
}

(NO_ADMIN ? runPlayersOnly() : runFull()).catch((e) => {
  console.error(e.message ?? e);
  process.exit(1);
});
