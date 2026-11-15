// 先生用の管理ページ。サーバーの状態スナップショットを受け取って表示し、進行操作を送る。
'use strict';

const KEY_STORAGE = 'derby.teacherKey';
const HORSE_COLORS = ['#ffffff', '#1b1b1b', '#d6282b', '#1f5fd1', '#f2cf1d', '#1f9a4a', '#f08a1c', '#f29ac0'];
const HORSE_TEXT = ['#111', '#fff', '#fff', '#fff', '#111', '#fff', '#fff', '#111'];
const PHASE_LABELS = { lobby: '参加受付中', betting: '賭け受付中', racing: 'レース中', result: '結果', final: '最終結果' };

const $ = (id) => document.getElementById(id);
const fmt = (n) => n.toLocaleString('ja-JP');

/** 要素を作る。文字は必ず textContent で入れる(生徒の名前をそのまま HTML にしない)。 */
function el(tag, className, text) {
  const e = document.createElement(tag);
  if (className) e.className = className;
  if (text !== undefined) e.textContent = text;
  return e;
}

function horseBadge(no) {
  const b = el('span', 'no', String(no));
  b.style.background = HORSE_COLORS[no - 1];
  b.style.color = HORSE_TEXT[no - 1];
  return b;
}

// ---- 接続 ----
let ws = null;
let view = null;
let clockOffset = 0; // サーバー時刻 − このPCの時刻
let retryMs = 1000;
let teacherKey = readKey();
let waitingForState = false;

function readKey() {
  try { return localStorage.getItem(KEY_STORAGE); } catch { return null; }
}
function storeKey(k) {
  try { k === null ? localStorage.removeItem(KEY_STORAGE) : localStorage.setItem(KEY_STORAGE, k); } catch { /* 保存できなくても動く */ }
}

function connect() {
  const scheme = location.protocol === 'https:' ? 'wss' : 'ws';
  ws = new WebSocket(`${scheme}://${location.host}/ws`);
  ws.addEventListener('open', () => {
    retryMs = 1000;
    $('banner').hidden = true;
    if (teacherKey) send({ t: 'admin', key: teacherKey });
  });
  ws.addEventListener('message', (e) => {
    let m;
    try { m = JSON.parse(e.data); } catch { return; }
    if (m.t === 'state' && m.isAdmin) {
      storeKey(teacherKey);
      view = m;
      clockOffset = m.serverNow - Date.now();
      waitingForState = false;
      showApp();
      render();
    } else if (m.t === 'error') {
      waitingForState = false;
      if (m.code === 'bad_key') {
        teacherKey = null;
        storeKey(null);
        showLogin(m.message);
      } else {
        toast(m.message);
        if (view) renderControls();
      }
    }
  });
  ws.addEventListener('close', () => {
    $('banner').hidden = false;
    setTimeout(connect, retryMs);
    retryMs = Math.min(retryMs * 2, 5000);
  });
}

function send(o) {
  if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(o));
}

function action(name, extra) {
  waitingForState = true;
  renderControls();
  send({ t: 'adminAction', action: name, ...extra });
}

// ---- ログイン ----
function showLogin(error) {
  $('app').hidden = true;
  $('login').hidden = false;
  $('loginError').textContent = error ?? '';
  $('key').value = '';
  $('key').focus();
}
function showApp() {
  $('login').hidden = true;
  $('app').hidden = false;
}
$('login').addEventListener('submit', (e) => {
  e.preventDefault();
  const k = $('key').value;
  if (!k) return;
  teacherKey = k;
  $('loginError').textContent = '';
  send({ t: 'admin', key: k });
});

// ---- 操作ボタン ----
const MAIN_ACTIONS = {
  lobby: () => ['試合開始', 'start'],
  betting: () => ['締め切ってレース開始', 'closeAndRace'],
  racing: () => null,
  result: (v) => [v.raceNo >= v.totalRaces ? '最終結果へ' : '次のレースへ', 'next'],
  final: () => ['新しい試合', 'newGame'],
};

$('mainBtn').addEventListener('click', () => {
  const a = view && MAIN_ACTIONS[view.phase](view);
  if (a) action(a[1]);
});
$('resetBtn').addEventListener('click', () => {
  if (confirm('試合をリセットしますか?\n参加者は残したまま、全員の所持金を最初に戻して受付に戻ります。')) action('reset');
});
$('kickAllBtn').addEventListener('click', () => {
  if (confirm('全員を退出させますか?\n部屋が空になります(別のクラスで使う前に押します)。')) action('kickAll');
});

let toastTimer = 0;
function toast(text) {
  $('toast').textContent = text;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { $('toast').textContent = ''; }, 4000);
}

// ---- 表示 ----
let stageKey = '';

function render() {
  const v = view;
  $('raceLabel').textContent = v.raceNo > 0 ? `第 ${v.raceNo} レース / 全 ${v.totalRaces} レース` : 'derby';
  $('phaseLabel').textContent = PHASE_LABELS[v.phase];
  $('countLabel').textContent =
    v.phase === 'betting' ? `賭け済み ${v.betCount} / ${v.onlineCount} 人` : `接続中 ${v.onlineCount} 人`;
  renderControls();
  renderBoard();

  // レース映像を描き直さないよう、場面が変わったときだけ中央を作り直す
  const key = `${v.phase}:${v.raceNo}`;
  if (key !== stageKey) {
    stageKey = key;
    stopRace();
    $('stage').replaceChildren();
    STAGES[v.phase].build(v);
  }
  STAGES[v.phase].update?.(v);
}

function renderControls() {
  const a = MAIN_ACTIONS[view.phase](view);
  const btn = $('mainBtn');
  btn.hidden = !a;
  if (a) btn.textContent = a[0];
  btn.disabled = waitingForState;
}

function renderBoard() {
  const v = view;
  $('playerCount').textContent = `(${v.players.length} 人)`;
  const items = v.players.map((p) => {
    const li = el('li', p.online ? '' : 'offline');
    li.append(el('span', 'rank', `${p.rank}位`));
    const name = el('span', 'name', p.name);
    if (!p.online) name.append(el('span', 'mark', '切断中'));
    else if (v.phase === 'betting' && p.hasBet) name.append(el('span', 'mark bet', '賭け済み'));
    li.append(name, el('span', 'coins', fmt(p.coins)));
    const kick = el('button', 'kick', '退出');
    kick.addEventListener('click', () => {
      if (confirm(`「${p.name}」を退出させますか?`)) action('kick', { playerId: p.id });
    });
    li.append(kick);
    return li;
  });
  const board = $('board');
  const scroll = board.scrollTop;
  board.replaceChildren(...items);
  board.scrollTop = scroll;
}

const STAGES = {
  lobby: {
    build() {
      const stage = $('stage');
      stage.append(el('h2', '', '参加者を待っています'));
      stage.append(el('p', 'hint', '生徒がアプリで名前を入れると、ここに表示されます。全員そろったら「試合開始」を押します。'));
      const count = el('p', 'lobby-count');
      count.id = 'lobbyCount';
      const chips = el('div', 'chips');
      chips.id = 'lobbyChips';
      stage.append(count, chips);
    },
    update(v) {
      $('lobbyCount').textContent = `${v.players.length} 人`;
      const byJoinName = [...v.players].sort((a, b) => a.name.localeCompare(b.name, 'ja'));
      $('lobbyChips').replaceChildren(...byJoinName.map((p) => el('span', p.online ? 'chip' : 'chip offline', p.name)));
    },
  },

  betting: {
    build(v) {
      const stage = $('stage');
      stage.append(el('h2', '', '出走表'));
      stage.append(el('p', 'hint', '1着になる馬を当てます。倍率が高い馬ほど勝ちにくく、当たれば大きく増えます。'));
      const field = el('div', 'field');
      for (const h of v.horses) {
        const row = el('div', 'row');
        const odds = el('span', 'odds', h.odds.toFixed(1));
        odds.append(el('small', '', ' 倍'));
        row.append(horseBadge(h.no), el('span', 'hname', h.name), odds);
        field.append(row);
      }
      stage.append(field);
    },
  },

  racing: {
    build(v) {
      const stage = $('stage');
      const wrap = el('div', 'track-wrap');
      const canvas = el('canvas');
      wrap.append(canvas);
      const live = el('div', 'live');
      live.id = 'live';
      stage.append(wrap, live);
      startRace(canvas, v);
    },
  },

  result: {
    build(v) {
      const stage = $('stage');
      const grid = el('div', 'result');

      const left = el('div', 'col');
      left.append(el('h2', '', '着順'));
      const order = el('ol', 'order');
      v.race.order.forEach((no, i) => {
        const h = v.horses.find((x) => x.no === no);
        const li = el('li');
        li.append(el('span', 'place', `${i + 1}着`), horseBadge(no), el('span', 'hname', h.name));
        if (i === 0) li.append(el('span', '', `${h.odds.toFixed(1)}倍`));
        order.append(li);
      });
      left.append(order);

      const right = el('div', 'col');
      const winners = v.bets.filter((b) => b.delta > 0).sort((a, b) => b.delta - a.delta);
      const losers = v.bets.length - winners.length;
      right.append(el('h2', '', `的中 ${winners.length} 人 / はずれ ${losers} 人`));
      const list = el('ul', 'winners');
      const nameOf = (id) => v.players.find((p) => p.id === id)?.name ?? '(退出)';
      if (winners.length === 0) list.append(el('li', '', '的中した人はいませんでした'));
      for (const b of winners) {
        const li = el('li');
        li.append(el('span', 'name', nameOf(b.playerId)), el('span', '', `${fmt(b.amount)} を賭けて`), el('span', 'plus', `+${fmt(b.delta)}`));
        list.append(li);
      }
      right.append(list);

      grid.append(left, right);
      stage.append(grid);
    },
  },

  final: {
    build() {
      const stage = $('stage');
      stage.append(el('h2', '', '最終結果'));
      const podium = el('div', 'podium');
      podium.id = 'podium';
      stage.append(podium);
    },
    update(v) {
      // 表彰台は 2位・1位・3位 の順に並べる。同順位が多いときは所持金順の上位3人。
      const top = v.players.slice(0, 3);
      const slots = [top[1], top[0], top[2]];
      $('podium').replaceChildren(...slots.map((p, i) => {
        const step = el('div', i === 1 ? 'step first' : 'step');
        if (!p) { step.style.visibility = 'hidden'; return step; }
        step.append(el('div', 'place', `${p.rank}位`), el('div', 'pname', p.name), el('div', 'pcoins', `${fmt(p.coins)} コイン`));
        return step;
      }));
    },
  },
};

// ---- レース映像 ----
let raf = 0;

function stopRace() {
  cancelAnimationFrame(raf);
  raf = 0;
}

/** 通過時刻の列から、その時点の進み具合(0〜1)を求める。区間内は線形補間。 */
function horseProgress(times, elapsed) {
  const n = times.length - 1;
  if (elapsed <= 0) return 0;
  if (elapsed >= times[n]) return 1;
  let i = 0;
  while (times[i + 1] <= elapsed) i++;
  return (i + (elapsed - times[i]) / (times[i + 1] - times[i])) / n;
}

function startRace(canvas, v) {
  const ctx = canvas.getContext('2d');
  const race = v.race;
  const horses = v.horses;
  let lastOrderKey = '';

  const frame = () => {
    const dpr = window.devicePixelRatio || 1;
    const w = canvas.clientWidth;
    const h = canvas.clientHeight;
    if (canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(h * dpr)) {
      canvas.width = Math.round(w * dpr);
      canvas.height = Math.round(h * dpr);
    }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    const elapsed = Date.now() + clockOffset - race.startedAt;
    const progress = race.times.map((t) => horseProgress(t, elapsed));
    drawTrack(ctx, w, h, horses, progress, elapsed);

    // その時点の順位
    const order = horses.map((x) => x.no).sort((a, b) => progress[b - 1] - progress[a - 1] || a - b);
    const allIn = progress.every((p) => p >= 1);
    const shown = allIn ? race.order : order;
    const key = shown.join() + allIn;
    if (key !== lastOrderKey) {
      lastOrderKey = key;
      const live = $('live');
      if (live) {
        live.replaceChildren(el('span', 'label', allIn ? '全馬ゴール' : '現在の順位'), ...shown.map(horseBadge));
      }
    }
    raf = requestAnimationFrame(frame);
  };
  raf = requestAnimationFrame(frame);
}

function drawTrack(ctx, w, h, horses, progress, elapsed) {
  const lanes = horses.length;
  const laneH = h / lanes;
  const startX = Math.max(70, w * 0.07);
  const goalX = w - Math.max(60, w * 0.05);

  for (let i = 0; i < lanes; i++) {
    ctx.fillStyle = i % 2 === 0 ? '#2f8f4a' : '#2a8444';
    ctx.fillRect(0, i * laneH, w, laneH);
  }
  ctx.strokeStyle = 'rgba(255,255,255,0.35)';
  ctx.lineWidth = 1;
  for (let i = 1; i < lanes; i++) {
    ctx.beginPath();
    ctx.moveTo(0, i * laneH);
    ctx.lineTo(w, i * laneH);
    ctx.stroke();
  }
  // スタート線
  ctx.strokeStyle = 'rgba(255,255,255,0.6)';
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(startX, 0);
  ctx.lineTo(startX, h);
  ctx.stroke();
  // ゴール線(市松模様)
  const sq = Math.max(6, laneH / 6);
  for (let y = 0, r = 0; y < h; y += sq, r++) {
    for (let c = 0; c < 2; c++) {
      ctx.fillStyle = (r + c) % 2 === 0 ? '#fff' : '#111';
      ctx.fillRect(goalX + c * sq, y, sq, sq);
    }
  }

  const size = Math.min(laneH * 0.78, 90);
  horses.forEach((horse, i) => {
    const p = progress[i];
    const x = startX + (goalX - startX) * p;
    const y = i * laneH + laneH / 2;
    drawHorse(ctx, x, y, size, horse.no, p > 0 && p < 1 ? elapsed : 0);
    // 馬名(レーンの左端)
    ctx.fillStyle = 'rgba(255,255,255,0.9)';
    ctx.font = `600 ${Math.max(12, Math.min(18, laneH * 0.26))}px sans-serif`;
    ctx.textBaseline = 'top';
    ctx.textAlign = 'left';
    ctx.fillText(horse.name, 8, i * laneH + 4);
  });
}

/** 右向きの馬。鼻先が x に来るように描く。 */
function drawHorse(ctx, x, y, size, no, runMs) {
  const s = size / 60;
  const phase = runMs / 110 + no; // 馬ごとに少しずらす
  const bob = runMs ? Math.sin(phase) * 2.2 : 0;
  ctx.save();
  ctx.translate(x - 58 * s, y + bob * s);
  ctx.scale(s, s);
  const body = '#6b4426';
  const dark = '#3f2613';

  // 脚
  ctx.strokeStyle = dark;
  ctx.lineWidth = 4;
  ctx.lineCap = 'round';
  const swing = (offset) => (runMs ? Math.sin(phase + offset) * 9 : 0);
  [[12, 0], [18, Math.PI], [38, Math.PI / 2], [44, -Math.PI / 2]].forEach(([lx, off]) => {
    ctx.beginPath();
    ctx.moveTo(lx, 8);
    ctx.lineTo(lx + swing(off), 24);
    ctx.stroke();
  });
  // しっぽ
  ctx.beginPath();
  ctx.moveTo(6, -4);
  ctx.quadraticCurveTo(-6, -2 + (runMs ? Math.sin(phase) * 3 : 4), -4, 10);
  ctx.stroke();
  // 胴
  ctx.fillStyle = body;
  ctx.beginPath();
  ctx.ellipse(28, 0, 23, 11, 0, 0, Math.PI * 2);
  ctx.fill();
  // 首と頭
  ctx.beginPath();
  ctx.moveTo(40, -6);
  ctx.lineTo(50, -20);
  ctx.lineTo(60, -14);
  ctx.lineTo(58, -8);
  ctx.lineTo(50, -6);
  ctx.lineTo(48, 4);
  ctx.closePath();
  ctx.fill();
  // たてがみ・耳
  ctx.fillStyle = dark;
  ctx.beginPath();
  ctx.moveTo(41, -8);
  ctx.lineTo(49, -21);
  ctx.lineTo(51, -24);
  ctx.lineTo(52, -19);
  ctx.lineTo(44, -6);
  ctx.closePath();
  ctx.fill();
  // ゼッケン
  ctx.fillStyle = HORSE_COLORS[no - 1];
  ctx.strokeStyle = '#111';
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.roundRect(17, -11, 20, 18, 3);
  ctx.fill();
  ctx.stroke();
  ctx.fillStyle = HORSE_TEXT[no - 1];
  ctx.font = '800 14px sans-serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(String(no), 27, -1.5);
  ctx.restore();
}

// ---- 開始 ----
if (!teacherKey) showLogin();
connect();
