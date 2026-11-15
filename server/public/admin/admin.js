// 先生用の管理ページ。サーバーの状態スナップショットを受け取って表示し、進行操作を送る。
'use strict';

const KEY_STORAGE = 'derby.teacherKey';
const HORSE_COLORS = ['#ffffff', '#1b1b1b', '#d6282b', '#1f5fd1', '#f2cf1d', '#1f9a4a', '#f08a1c', '#f29ac0'];
const HORSE_TEXT = ['#111', '#fff', '#fff', '#fff', '#111', '#fff', '#fff', '#111'];
const COND_LABELS = { 5: ['↑', '絶好調'], 4: ['↗', '好調'], 3: ['→', '普通'], 2: ['↘', '不調'], 1: ['↓', '絶不調'] };
const MOOD_LABELS = { fired: '気合十分', happy: 'ごきげん', calm: '落ち着き', restless: 'そわそわ', sleepy: '眠そう' };
const COAT_COLORS = ['#7a4a2a', '#3b2a22', '#a0612f', '#8d8d8d', '#5a3a26', '#b5793f', '#2b2b2f', '#946037'];
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
let sceneChangedAt = 0; // 場面が変わった直後は、主ボタンをしばらく押せなくする(二重クリック対策)
const BUTTON_HOLD_MS = 1000;

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
  // 見ていた場面を添える。サーバーは、場面が変わった後に届いた操作(二重クリックの2回目など)を受け付けない。
  send({ t: 'adminAction', action: name, phase: view.phase, raceNo: view.raceNo, ...extra });
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
  // 場面が変わったら、主ボタンをしばらく押せなくする(ボタンの表示を更新する前に記録する)
  const key = `${v.phase}:${v.raceNo}`;
  const sceneChanged = key !== stageKey;
  if (sceneChanged) {
    sceneChangedAt = Date.now();
    setTimeout(renderControls, BUTTON_HOLD_MS + 20);
  }
  renderControls();
  renderBoard();

  // レース映像を描き直さないよう、場面が変わったときだけ中央を作り直す
  if (sceneChanged) {
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
  btn.disabled = waitingForState || Date.now() - sceneChangedAt < BUTTON_HOLD_MS;
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
      const c = v.course;
      stage.append(el('h2', '', c ? `出走表  芝 ${c.distance}m  馬場: ${c.going}` : '出走表'));
      stage.append(el('p', 'hint', '1着になる馬を当てます。倍率は実力で決まります。今日の「調子」と「表情」が良い馬は、倍率より勝ちやすくなります(どちらも、たまに当てになりません)。'));
      const table = el('div', 'field');
      const head = el('div', 'row head');
      for (const t of ['', '', '馬名', '性齢', '馬体重', '脚質', '近走', '調子', '表情', '倍率', '人気']) head.append(el('span', '', t));
      table.append(head);
      for (const h of v.horses) {
        const row = el('div', 'row');
        const face = el('canvas', 'face');
        face.width = 112;
        face.height = 112;
        if (h.mood) drawFace(face.getContext('2d'), 112, h.no, h.mood);
        const cond = COND_LABELS[h.cond];
        const condEl = el('span', `cond c${h.cond ?? 3}`, cond ? `${cond[0]} ${cond[1]}` : '');
        const diff = h.weightDiff > 0 ? `+${h.weightDiff}` : h.weightDiff === 0 ? '±0' : `${h.weightDiff}`;
        const odds = el('span', 'odds', h.odds.toFixed(1));
        odds.append(el('small', '', ' 倍'));
        row.append(
          face,
          horseBadge(h.no),
          el('span', 'hname', h.name),
          el('span', '', h.sex ? `${h.sex}${h.age}` : ''),
          el('span', '', h.weight ? `${h.weight}kg(${diff})` : ''),
          el('span', '', h.style ?? ''),
          el('span', 'recent', h.recent ? h.recent.join('-') : ''),
          condEl,
          el('span', 'mood', MOOD_LABELS[h.mood] ?? ''),
          odds,
          el('span', 'pop', h.pop ? `${h.pop}番人気` : ''),
        );
        table.append(row);
      }
      stage.append(table);
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
      // 全員の賭けを公開する(的中した人を上に、増減の大きい順)
      const all = [...v.bets].sort((a, b) => b.delta - a.delta);
      const winners = all.filter((b) => b.delta > 0).length;
      right.append(el('h2', '', `的中 ${winners} 人 / はずれ ${all.length - winners} 人`));
      const list = el('ul', 'winners');
      const nameOf = (id) => v.players.find((p) => p.id === id)?.name ?? '(退出)';
      if (all.length === 0) list.append(el('li', '', '賭けた人はいませんでした'));
      for (const b of all) {
        const li = el('li');
        const won = b.delta > 0;
        li.append(
          el('span', 'name', nameOf(b.playerId)), horseBadge(b.horse), el('span', '', `に ${fmt(b.amount)}`),
          el('span', won ? 'plus' : 'minus', won ? `+${fmt(b.delta)}` : `−${fmt(-b.delta)}`),
        );
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
  if (n < 1 || elapsed <= 0) return 0;
  if (elapsed >= times[n]) return 1;
  let i = 0;
  while (times[i + 1] <= elapsed) i++;
  return (i + (elapsed - times[i]) / (times[i + 1] - times[i])) / n;
}

/** コースの長さ(画面幅の何倍か)。距離が長いほど長い。 */
function trackScale(distance) {
  return 3 + (Math.min(2400, Math.max(1200, distance)) - 1200) / 600;
}

/** カメラの左端の位置。先頭の馬を画面の右寄りに置き、コースの両端では止める。 */
function cameraX(leaderX, viewW, worldW) {
  return Math.min(Math.max(leaderX - viewW * 0.7, 0), Math.max(worldW - viewW, 0));
}

function startRace(canvas, v) {
  const ctx = canvas.getContext('2d');
  const race = v.race;
  const horses = v.horses;
  const distance = v.course?.distance ?? 1600;
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
    drawTrack(ctx, w, h, horses, progress, elapsed, distance);

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

function drawTrack(ctx, w, h, horses, progress, elapsed, distance) {
  const mapH = 34; // 上部の全体図
  const trackH = h - mapH;
  const lanes = horses.length;
  const laneH = trackH / lanes;
  const size = Math.min(laneH * 0.78, 90);
  const startX = size + 20;
  const worldW = w * trackScale(distance);
  const goalX = worldW - Math.max(70, w * 0.06);
  const xOf = (p) => startX + (goalX - startX) * p;
  const lead = Math.max(0, ...progress);
  const cam = cameraX(xOf(lead), w, worldW);

  // ---- コース(カメラに合わせて流れる) ----
  ctx.save();
  ctx.beginPath();
  ctx.rect(0, mapH, w, trackH);
  ctx.clip();
  ctx.translate(-cam, mapH);
  for (let i = 0; i < lanes; i++) {
    ctx.fillStyle = i % 2 === 0 ? '#2f8f4a' : '#2a8444';
    ctx.fillRect(cam, i * laneH, w, laneH);
  }
  // 芝の刈り目(流れて見えるように、コースに固定した縦じま)
  const stripe = 160;
  ctx.fillStyle = 'rgba(255,255,255,0.045)';
  for (let x = Math.floor(cam / (stripe * 2)) * stripe * 2; x < cam + w; x += stripe * 2) ctx.fillRect(x, 0, stripe, trackH);
  ctx.strokeStyle = 'rgba(255,255,255,0.35)';
  ctx.lineWidth = 1;
  for (let i = 1; i < lanes; i++) {
    ctx.beginPath();
    ctx.moveTo(cam, i * laneH);
    ctx.lineTo(cam + w, i * laneH);
    ctx.stroke();
  }
  // スタート線
  ctx.strokeStyle = 'rgba(255,255,255,0.6)';
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(startX, 0);
  ctx.lineTo(startX, trackH);
  ctx.stroke();
  // 200m ごとの標識(残り距離)
  ctx.font = '700 16px sans-serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'top';
  for (let remain = 200; remain < distance; remain += 200) {
    const x = xOf(1 - remain / distance);
    if (x < cam - 80 || x > cam + w + 80) continue;
    ctx.strokeStyle = 'rgba(255,255,255,0.28)';
    ctx.setLineDash([8, 8]);
    ctx.beginPath();
    ctx.moveTo(x, 0);
    ctx.lineTo(x, trackH);
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.fillStyle = 'rgba(255,255,255,0.85)';
    ctx.fillText(`残り${remain}m`, x, 4);
  }
  // ゴール線(市松模様)
  const sq = Math.max(6, laneH / 6);
  for (let y = 0, r = 0; y < trackH; y += sq, r++) {
    for (let c = 0; c < 2; c++) {
      ctx.fillStyle = (r + c) % 2 === 0 ? '#fff' : '#111';
      ctx.fillRect(goalX + c * sq, y, sq, sq);
    }
  }
  horses.forEach((horse, i) => {
    const p = progress[i];
    drawHorse(ctx, xOf(p), i * laneH + laneH / 2, size, horse.no, p > 0 && p < 1 ? elapsed : 0);
  });
  ctx.restore();

  // 馬名(画面に固定。レーンの左上)
  ctx.fillStyle = 'rgba(255,255,255,0.9)';
  ctx.font = `600 ${Math.max(12, Math.min(18, laneH * 0.24))}px sans-serif`;
  ctx.textAlign = 'left';
  ctx.textBaseline = 'top';
  horses.forEach((horse, i) => ctx.fillText(`${horse.no} ${horse.name}`, 8, mapH + i * laneH + 4));

  // ---- 全体図(画面に固定): 全馬の位置と残り距離 ----
  ctx.fillStyle = '#14562a';
  ctx.fillRect(0, 0, w, mapH);
  const mapL = 150;
  const mapR = w - 40;
  ctx.fillStyle = '#fff';
  ctx.font = '700 18px sans-serif';
  ctx.textAlign = 'left';
  ctx.textBaseline = 'middle';
  const remain = Math.max(0, Math.round((distance * (1 - lead)) / 10) * 10);
  ctx.fillText(lead >= 1 ? 'ゴール!' : `残り ${remain}m`, 12, mapH / 2);
  ctx.strokeStyle = 'rgba(255,255,255,0.5)';
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(mapL, mapH / 2);
  ctx.lineTo(mapR, mapH / 2);
  ctx.stroke();
  ctx.fillStyle = '#fff';
  ctx.fillRect(mapR, 6, 3, mapH - 12);
  // 遅い馬を先に描き、先頭の馬が上に来るようにする
  [...horses].sort((a, b) => progress[a.no - 1] - progress[b.no - 1]).forEach((horse) => {
    const x = mapL + (mapR - mapL) * progress[horse.no - 1];
    ctx.beginPath();
    ctx.arc(x, mapH / 2, 8, 0, Math.PI * 2);
    ctx.fillStyle = HORSE_COLORS[horse.no - 1];
    ctx.fill();
    ctx.strokeStyle = '#111';
    ctx.lineWidth = 1.5;
    ctx.stroke();
  });
}

/**
 * 正面から見た馬の顔。表情(mood)で目・耳・口と小物を変える。size は一辺の長さ。
 * アプリ(lib/src/widgets/horse_face.dart)と同じ形。
 */
function drawFace(ctx, size, no, mood) {
  const s = size / 60;
  ctx.save();
  ctx.scale(s, s);
  const coat = COAT_COLORS[(no - 1) % COAT_COLORS.length];
  const dark = '#241812';
  // 耳(表情で向きが変わる)
  const ear = { fired: [0, -1], happy: [-1, -1], calm: [-1, -1], restless: [-5, 2], sleepy: [-7, 5] }[mood] ?? [-1, -1];
  ctx.fillStyle = coat;
  for (const side of [-1, 1]) {
    ctx.beginPath();
    ctx.moveTo(30 + side * 8, 14);
    ctx.lineTo(30 + side * (14 - ear[0]), 2 + ear[1]);
    ctx.lineTo(30 + side * 16, 16);
    ctx.closePath();
    ctx.fill();
  }
  // 頭と鼻づら
  ctx.beginPath();
  ctx.ellipse(30, 26, 15, 17, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.beginPath();
  ctx.ellipse(30, 43, 12, 12, 0, 0, Math.PI * 2);
  ctx.fill();
  // たてがみ(前髪)
  ctx.fillStyle = dark;
  ctx.beginPath();
  ctx.moveTo(24, 10);
  ctx.quadraticCurveTo(30, 4, 36, 10);
  ctx.quadraticCurveTo(32, 18, 30, 20);
  ctx.quadraticCurveTo(27, 16, 24, 10);
  ctx.fill();
  // 鼻づらの色と鼻の穴
  ctx.fillStyle = 'rgba(255,235,215,0.35)';
  ctx.beginPath();
  ctx.ellipse(30, 45, 10, 9, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = dark;
  for (const side of [-1, 1]) {
    ctx.beginPath();
    ctx.ellipse(30 + side * 5, 44, 1.8, 2.6, 0, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.strokeStyle = dark;
  ctx.lineCap = 'round';
  ctx.lineWidth = 2;
  const eyeY = 27;
  for (const side of [-1, 1]) {
    const ex = 30 + side * 9;
    if (mood === 'happy') {
      // にっこり閉じた目
      ctx.beginPath();
      ctx.arc(ex, eyeY + 1, 3.2, Math.PI * 1.1, Math.PI * 1.9);
      ctx.stroke();
    } else if (mood === 'sleepy') {
      // 半分閉じた目
      ctx.beginPath();
      ctx.moveTo(ex - 3.2, eyeY + 1);
      ctx.lineTo(ex + 3.2, eyeY + 1);
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(ex, eyeY + 1, 3.2, 0.15 * Math.PI, 0.85 * Math.PI);
      ctx.stroke();
    } else if (mood === 'restless') {
      // 見開いて横目
      ctx.fillStyle = '#fff';
      ctx.beginPath();
      ctx.arc(ex, eyeY, 4, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = dark;
      ctx.beginPath();
      ctx.arc(ex + 1.8, eyeY + 0.5, 1.6, 0, Math.PI * 2);
      ctx.fill();
    } else {
      ctx.fillStyle = dark;
      ctx.beginPath();
      ctx.arc(ex, eyeY, mood === 'fired' ? 2.8 : 2.4, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = '#fff';
      ctx.beginPath();
      ctx.arc(ex + 0.9, eyeY - 0.9, 0.8, 0, Math.PI * 2);
      ctx.fill();
      if (mood === 'fired') {
        // つり上がった眉
        ctx.lineWidth = 2.4;
        ctx.beginPath();
        ctx.moveTo(ex + side * 5, eyeY - 7.5);
        ctx.lineTo(ex - side * 4, eyeY - 4);
        ctx.stroke();
        ctx.lineWidth = 2;
      }
    }
  }
  // 口
  ctx.beginPath();
  if (mood === 'happy') ctx.arc(30, 49, 4.5, 0.15 * Math.PI, 0.85 * Math.PI);
  else if (mood === 'fired') { ctx.moveTo(25, 51.5); ctx.lineTo(35, 51.5); }
  else if (mood === 'restless') { ctx.moveTo(25, 51); ctx.quadraticCurveTo(27.5, 49, 30, 51); ctx.quadraticCurveTo(32.5, 53, 35, 51); }
  else if (mood === 'sleepy') ctx.arc(30, 51, 1.6, 0, Math.PI * 2);
  else { ctx.moveTo(26.5, 51); ctx.lineTo(33.5, 51); }
  ctx.stroke();
  // 小物
  if (mood === 'fired') {
    // 鼻息
    ctx.fillStyle = 'rgba(255,255,255,0.92)';
    for (const side of [-1, 1]) {
      for (const [dx, dy, r] of [[12, 3, 3.4], [16, 1, 2.6], [19.5, 3.5, 2]]) {
        ctx.beginPath();
        ctx.arc(30 + side * dx, 44 + dy, r, 0, Math.PI * 2);
        ctx.fill();
      }
    }
  } else if (mood === 'restless') {
    // 汗
    ctx.fillStyle = '#6ec6ff';
    ctx.beginPath();
    ctx.moveTo(49, 14);
    ctx.quadraticCurveTo(53.5, 21, 49, 23);
    ctx.quadraticCurveTo(44.5, 21, 49, 14);
    ctx.fill();
  } else if (mood === 'sleepy') {
    ctx.fillStyle = '#dfe9ff';
    ctx.font = '800 11px sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('z', 49, 13);
    ctx.font = '800 8px sans-serif';
    ctx.fillText('z', 55, 6);
  } else if (mood === 'happy') {
    // ほっぺ
    ctx.fillStyle = 'rgba(255,120,120,0.45)';
    for (const side of [-1, 1]) {
      ctx.beginPath();
      ctx.ellipse(30 + side * 11.5, 33, 3, 2, 0, 0, Math.PI * 2);
      ctx.fill();
    }
  }
  ctx.restore();
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
