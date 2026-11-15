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
        } else if (m.t === 'error') this.errors.push(m.code);
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
        const b = randomBet(s);
        if (b) setTimeout(() => p.ws.readyState === 1 && p.send({ t: 'bet', ...b }), 500 + Math.random() * 6000);
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
      check(p.state.horses.every((h) => !('prob' in h)), '勝率は送られない');
    }

    if (race === 1) {
      // 不正な賭け(Review Focus 3)
      players[3].send({ t: 'bet', horse: 99, amount: -5 });
      await players[3].expectError('bad_bet', '馬番 99・金額 -5');
      players[3].send({ t: 'bet', horse: 1, amount: 15 });
      await players[3].expectError('bad_bet', '10 の倍数でない');
      players[3].send({ t: 'bet', horse: 1, amount: 999990 });
      await players[3].expectError('bad_bet', '所持金を超える');
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

    // 賭ける
    const plans = players.map((p) => ({ p, before: p.state.me.coins, bet: randomBet(p.state) }));
    for (const { p, bet } of plans) if (bet) p.send({ t: 'bet', ...bet });
    await Promise.all(plans.map(({ p, bet }) =>
      bet ? p.wait((c) => c.state.me.bet?.horse === bet.horse && c.state.me.bet?.amount === bet.amount, '賭けの反映') : null));
    const betCount = plans.filter((x) => x.bet).length;
    await admin.wait((c) => c.state.betCount === betCount, `賭け済み ${betCount} 人`);
    check(admin.state.players.filter((x) => x.hasBet).length === betCount, '先生には賭け済みの印が見える');
    check(players[0].state.players.every((x) => x.hasBet === false), '生徒には他人の賭け済みが見えない');

    // 締め切り(連打: Review Focus 1)
    const t0 = Date.now();
    advance(admin, 'closeAndRace');
    advance(admin, 'closeAndRace');
    await admin.expectError('not_allowed', '締め切りの連打');
    await Promise.all(players.map((p) => p.waitPhase('racing', race)));
    const startedAt = players[0].state.race.startedAt;
    for (const { p, before, bet } of plans) {
      check(p.state.me.coins === before - (bet?.amount ?? 0), '締め切りで賭け金が引かれる');
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
      check(back.state.me.coins === plans[0].before - (plans[0].bet?.amount ?? 0), '復帰後も所持金が同じ');
      players[0] = back;
      plans[0].p = back;
    }

    // 結果(自動で進む)
    await Promise.all(players.map((p) => p.waitPhase('result', race, 25000)));
    const took = Date.now() - t0;
    check(took >= 19000 && took <= 23000, `レースは約 20 秒(実際: ${took}ms)`);
    const s0 = players[0].state;
    const winner = s0.race.order[0];
    const odds = s0.horses.find((h) => h.no === winner).odds;
    const finish = s0.race.times.map((t) => t[10]);
    check([...s0.race.order].sort((a, b) => finish[a - 1] - finish[b - 1]).join() === s0.race.order.join(), '映像のゴール順が着順と一致');
    for (const { p, before, bet } of plans) {
      const me = p.state.me;
      if (!bet) {
        check(me.coins === before && me.lastResult === null, '見送りは所持金不変');
        continue;
      }
      const won = bet.horse === winner;
      const expected = before - bet.amount + (won ? expectedPayout(bet.amount, odds) : 0);
      check(me.coins === expected, `${p.label}: 所持金 ${me.coins} が計算 ${expected} と一致`);
      check(me.lastResult.won === won && me.lastResult.delta === expected - before, '結果の増減が一致');
    }
    check(s0.bets.length === betCount, '結果画面で全員の賭けが公開される');
    console.log(`第${race}レース: 1着 ${winner}番(${odds}倍)、${betCount} 人が賭け、${took}ms`);

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
