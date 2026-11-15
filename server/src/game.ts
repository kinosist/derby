// ゲームの状態と状態遷移(純粋関数)。引数の state は変更せず、新しい state を返す。

import {
  comboKey, drawOrder, makeCourse, makeField, makeOddsTable, makeTimes, makeTips, payout, raceDuration, ticketWins,
  BET_HORSES, BET_TYPES, HORSES, MAX_PLAYERS, MAX_TICKETS, MIN_BET, NAME_MAX, RESCUE_COINS, START_COINS, TIPSTERS,
  TOTAL_RACES,
  type BetType, type Course, type Horse, type OddsTable, type Rng, type Tip, type TipsterId,
} from './rules';

export type Phase = 'lobby' | 'betting' | 'racing' | 'result' | 'final';

export type ErrorCode =
  | 'bad_message' | 'bad_name' | 'name_taken' | 'room_full'
  | 'bad_key' | 'bad_bet' | 'not_allowed' | 'kicked';

/** 馬券 1 点。odds は買った時点の倍率。 */
export type Ticket = { id: string; type: BetType; horses: number[]; amount: number; odds: number };
export type TicketResult = Ticket & { won: boolean; payout: number };
/** 1 レースの結果: 賭けた合計、差し引きの増減、馬券ごとの当たり外れ */
export type Results = { staked: number; delta: number; tickets: TicketResult[] };

/** 古いアプリ向けの形(単勝 1 点だけだった頃の形式) */
export type LegacyBet = { horse: number; amount: number };
export type LegacyResult = { horse: number; amount: number; won: boolean; delta: number };

export type Player = {
  /** 本人だけが知る id(入り直しの確認に使う)。本人と先生以外には送らない。 */
  id: string;
  /** 公開用の id。ほかの生徒に見せる順位表や賭けの一覧ではこちらを使う。 */
  pub: string;
  name: string;
  coins: number;
  online: boolean;
  tickets: Ticket[];
  results: Results | null;
  /** このレースで買った予想屋の id */
  tips: string[];
};

export type Race = { startedAt: number; durationMs: number; order: number[]; times: number[][] };

export type GameState = {
  phase: Phase;
  raceNo: number;
  horses: Horse[];
  /** 距離と馬場。以前の形式で保存された状態には無いことがある。 */
  course?: Course | null;
  /** 単勝以外の倍率表(賭け受付の開始時に作る) */
  oddsTable?: OddsTable | null;
  /** レースごとに変わる識別子。端末が倍率表と状態を対応させるのに使う。 */
  raceKey?: string;
  /** 予想屋ごとの、このレースの予想(賭け受付の開始時に作る) */
  tips?: Record<TipsterId, Tip> | null;
  players: Player[];
  race: Race | null;
};

/** 出走表に出す馬の情報(勝率と本当の調子は含めない) */
export type PublicHorse = Pick<
  Horse,
  'no' | 'name' | 'odds' | 'sex' | 'age' | 'weight' | 'weightDiff' | 'style' | 'recent' | 'pop' | 'cond' | 'mood'
>;

export type R = { state: GameState; error?: ErrorCode };

export type View = {
  phase: Phase;
  raceNo: number;
  totalRaces: number;
  serverNow: number;
  raceKey: string | null;
  horses: PublicHorse[];
  course: Course | null;
  /** 予想屋の一覧(賭け受付中のみ) */
  tipsters: { id: string; name: string; price: number; stars: number }[];
  /** 結果画面で公開する、全予想屋の予想と ◎ が 1 着だったか */
  tipResults: { id: string; name: string; marks: number[]; hit: boolean }[];
  players: { id: string; name: string; coins: number; online: boolean; rank: number; hasBet: boolean }[];
  betCount: number;
  onlineCount: number;
  me: {
    id: string; name: string; coins: number; rank: number;
    tickets: Ticket[];
    results: Results | null;
    /** 買った予想(本人にだけ届く) */
    tips: { id: string; marks: number[]; comment: string }[];
    /** 古いアプリ向け */
    bet: LegacyBet | null;
    lastResult: LegacyResult | null;
  } | null;
  race: Race | null;
  /** 結果画面で公開する全員の賭け。horse / amount / delta は古いアプリ向けの要約。 */
  bets: {
    playerId: string; horse: number; amount: number; delta: number;
    tickets: Pick<TicketResult, 'type' | 'horses' | 'amount' | 'odds' | 'won' | 'payout'>[];
  }[];
  isAdmin: boolean;
};

export type OddsMessage = { t: 'odds'; raceKey: string } & OddsTable;

export function newGame(): GameState {
  return { phase: 'lobby', raceNo: 0, horses: [], course: null, oddsTable: null, tips: null, players: [], race: null };
}

const PHASES: Phase[] = ['lobby', 'betting', 'racing', 'result', 'final'];

/**
 * 保存されていた状態を今の形に直す。以前の版は、参加者ごとに単勝 1 点(bet)と
 * その結果(lastResult)を持っていた。読めない値なら新しい試合にする。
 */
export function migrate(raw: unknown): GameState {
  try {
    return migrateState(raw);
  } catch {
    return newGame(); // 想定外の形。部屋が起動できなくなるより、新しい試合にする。
  }
}

function migrateState(raw: unknown): GameState {
  if (typeof raw !== 'object' || raw === null) return newGame();
  const s = raw as GameState;
  if (!PHASES.includes(s.phase) || !Array.isArray(s.players) || !Array.isArray(s.horses)) return newGame();
  const validPlayer = (p: unknown) =>
    typeof p === 'object' && p !== null &&
    typeof (p as Player).id === 'string' && typeof (p as Player).name === 'string' && typeof (p as Player).coins === 'number';
  if (!s.players.every(validPlayer)) return newGame();
  const oddsOf = (no: number) => s.horses.find((h) => h.no === no)?.odds ?? 0;
  let changed = false;
  const players = s.players.map((p, i) => {
    const old = p as Player & { bet?: LegacyBet | null; lastResult?: LegacyResult | null };
    if (Array.isArray(old.tickets) && typeof old.pub === 'string' && Array.isArray(old.tips) && !('bet' in old)) return p;
    changed = true;
    const { bet, lastResult, ...rest } = old;
    const tickets: Ticket[] = Array.isArray(old.tickets)
      ? old.tickets
      : bet ? [{ id: 'legacy', type: 'win', horses: [bet.horse], amount: bet.amount, odds: oddsOf(bet.horse) }] : [];
    const results: Results | null = old.results !== undefined
      ? old.results
      : lastResult
        ? {
            staked: lastResult.amount,
            delta: lastResult.delta,
            tickets: [{
              id: 'legacy', type: 'win', horses: [lastResult.horse], amount: lastResult.amount,
              odds: oddsOf(lastResult.horse), won: lastResult.won, payout: lastResult.amount + lastResult.delta,
            }],
          }
        : null;
    // 公開用の id は全員に送られる。本当の id から作ると乗っ取りに使えてしまうので、無関係な乱数にする。
    const pub = typeof old.pub === 'string' ? old.pub : `pub-${i}-${Math.random().toString(36).slice(2, 12)}`;
    return { ...rest, pub, tickets, results, tips: Array.isArray(old.tips) ? old.tips : [] };
  });
  // 予想屋の予想を持たない状態(以前の版で始まったレース)には、いま作って足す
  // (賭け受付中だけ。レース中・結果では、結果が決まった後に作った予想を見せても意味がない)
  const needsTips = !s.tips && s.horses.length > 0 && s.phase === 'betting';
  if (!changed && !needsTips) return s;
  return { ...s, players, tips: needsTips ? makeTips(s.horses, Math.random) : s.tips };
}

/** 前後の空白を除き、制御文字を空白に置き換える。1〜12 文字(コードポイント)でなければ null。 */
export function normalizeName(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const name = raw.replace(/[\u0000-\u001f\u007f]/g, ' ').trim();
  const length = [...name].length;
  if (length < 1 || length > NAME_MAX) return null;
  return name;
}

function usableId(s: GameState, id: unknown, except?: Player): id is string {
  return (
    typeof id === 'string' && id.length >= 1 && id.length <= 64 &&
    !s.players.some((p) => (p !== except && p.id === id) || p.pub === id)
  );
}

export function join(
  s: GameState, id: unknown, rawName: unknown, newId: () => string,
): R & { playerId?: string; replacedId?: string } {
  const name = normalizeName(rawName);
  if (name === null) return { state: s, error: 'bad_name' };

  const existing = s.players.find((p) => p.name === name);
  if (existing) {
    if (existing.online) {
      if (existing.id !== id) return { state: s, error: 'name_taken' };
      // 同じ端末からの入り直し。古い接続は呼び出し側が閉じる。
      return { state: s, playerId: existing.id, replacedId: existing.id };
    }
    // 切断中の同名の参加者として復帰する(所持金を引き継ぐ)
    const playerId = usableId(s, id, existing) ? id : newId();
    return {
      state: mapPlayer(s, existing.id, (p) => ({ ...p, id: playerId, online: true })),
      playerId,
    };
  }

  if (s.players.length >= MAX_PLAYERS) return { state: s, error: 'room_full' };
  const playerId = usableId(s, id) ? id : newId();
  const player: Player = {
    id: playerId, pub: newId(), name, coins: START_COINS, online: true, tickets: [], results: null, tips: [],
  };
  return { state: { ...s, players: [...s.players, player] }, playerId };
}

function mapPlayer(s: GameState, playerId: string, f: (p: Player) => Player): GameState {
  return { ...s, players: s.players.map((p) => (p.id === playerId ? f(p) : p)) };
}

export function setOnline(s: GameState, playerId: string, online: boolean): GameState {
  const p = s.players.find((x) => x.id === playerId);
  if (!p || p.online === online) return s;
  return mapPlayer(s, playerId, (x) => ({ ...x, online }));
}

const isHorseNo = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v) && v >= 1 && v <= HORSES;
const isAmount = (v: unknown): v is number =>
  typeof v === 'number' && Number.isInteger(v) && v >= MIN_BET && v % MIN_BET === 0;

function oddsTableOf(s: GameState): OddsTable {
  return s.oddsTable ?? makeOddsTable(s.horses);
}

/** 馬券の倍率。単勝は出走表の倍率、ほかは倍率表から引く。見つからなければ null。 */
function oddsOfTicket(s: GameState, type: BetType, horses: number[]): number | null {
  let odds: number | undefined;
  if (type === 'win') odds = s.horses.find((h) => h.no === horses[0])?.odds;
  else if (type === 'place') odds = oddsTableOf(s).place[horses[0] - 1];
  else if (type === 'quinella') odds = oddsTableOf(s).quinella[comboKey(type, horses)];
  else odds = oddsTableOf(s).trifecta[comboKey(type, horses)];
  return typeof odds === 'number' && odds > 0 ? odds : null;
}

/**
 * 馬券を 1 点買う。同じ種類・同じ馬の馬券がすでにあれば、金額を置き換える。
 * 全馬券の合計は所持金以下、点数は MAX_TICKETS 以下。
 */
export function placeTicket(
  s: GameState, playerId: string, type: unknown, rawHorses: unknown, amount: unknown, newId: () => string,
): R {
  const p = s.players.find((x) => x.id === playerId);
  if (!p || s.phase !== 'betting') return { state: s, error: 'not_allowed' };
  const bad: R = { state: s, error: 'bad_bet' };
  if (typeof type !== 'string' || !(BET_TYPES as readonly string[]).includes(type)) return bad;
  const betType = type as BetType;
  if (!Array.isArray(rawHorses) || rawHorses.length !== BET_HORSES[betType] || !rawHorses.every(isHorseNo)) return bad;
  if (new Set(rawHorses).size !== rawHorses.length) return bad;
  if (!isAmount(amount)) return bad;
  // 馬連は順不同なので、馬番の小さい順にそろえて記録する
  const horses: number[] = betType === 'quinella' ? [...rawHorses].sort((a, b) => a - b) : [...rawHorses];
  const odds = oddsOfTicket(s, betType, horses);
  if (odds === null) return bad;

  const key = `${betType}:${horses.join('-')}`;
  const existing = p.tickets.find((t) => `${t.type}:${t.horses.join('-')}` === key);
  const others = p.tickets.filter((t) => t !== existing);
  if (!existing && p.tickets.length >= MAX_TICKETS) return bad;
  if (others.reduce((a, t) => a + t.amount, 0) + amount > p.coins) return bad;

  const ticket: Ticket = { id: existing?.id ?? newId(), type: betType, horses, amount, odds };
  const tickets = existing ? p.tickets.map((t) => (t === existing ? ticket : t)) : [...p.tickets, ticket];
  return { state: mapPlayer(s, playerId, (x) => ({ ...x, tickets })) };
}

export function cancelTicket(s: GameState, playerId: string, ticketId: unknown): R {
  const p = s.players.find((x) => x.id === playerId);
  if (!p || s.phase !== 'betting') return { state: s, error: 'not_allowed' };
  if (typeof ticketId !== 'string' || !p.tickets.some((t) => t.id === ticketId)) return { state: s, error: 'bad_bet' };
  return { state: mapPlayer(s, playerId, (x) => ({ ...x, tickets: x.tickets.filter((t) => t.id !== ticketId) })) };
}

/** 古いアプリの「賭ける」: 単勝 1 点に買い直す(それまでの馬券はすべて置き換える)。 */
export function placeBet(s: GameState, playerId: string, horse: unknown, amount: unknown): R {
  const p = s.players.find((x) => x.id === playerId);
  if (!p || s.phase !== 'betting') return { state: s, error: 'not_allowed' };
  if (!isHorseNo(horse) || !isAmount(amount) || amount > p.coins) return { state: s, error: 'bad_bet' };
  const odds = oddsOfTicket(s, 'win', [horse]);
  if (odds === null) return { state: s, error: 'bad_bet' };
  const ticket: Ticket = { id: 'legacy', type: 'win', horses: [horse], amount, odds };
  return { state: mapPlayer(s, playerId, (x) => ({ ...x, tickets: [ticket] })) };
}

/** 古いアプリの「取り消し」: 馬券をすべて取り消す。 */
export function cancelBet(s: GameState, playerId: string): R {
  const p = s.players.find((x) => x.id === playerId);
  if (!p || s.phase !== 'betting') return { state: s, error: 'not_allowed' };
  return { state: mapPlayer(s, playerId, (x) => ({ ...x, tickets: [] })) };
}

const staked = (p: Player) => p.tickets.reduce((a, t) => a + t.amount, 0);

/**
 * 予想屋から予想を買う。料金はその場で引き、戻らない。1 レースにつき各予想屋 1 回。
 * 料金を払うと、買ってある馬券の合計が所持金を超えてしまうなら買えない。
 * 払ったあとに最低賭け金(10 コイン)が残らない場合も買えない: 10 コイン未満になると次のレースで
 * 救済の 100 コインがもらえるので、わざと使い切って得をすることができてしまう。
 */
export function buyTip(s: GameState, playerId: string, tipsterId: unknown): R {
  const p = s.players.find((x) => x.id === playerId);
  if (!p || s.phase !== 'betting') return { state: s, error: 'not_allowed' };
  const tipster = typeof tipsterId === 'string' ? TIPSTERS.find((t) => t.id === tipsterId) : undefined;
  if (!tipster || !s.tips?.[tipster.id] || p.tips.includes(tipster.id)) return { state: s, error: 'bad_bet' };
  if (p.coins - tipster.price < Math.max(staked(p), MIN_BET)) return { state: s, error: 'bad_bet' };
  return {
    state: mapPlayer(s, playerId, (x) => ({ ...x, coins: x.coins - tipster.price, tips: [...x.tips, tipster.id] })),
  };
}

/** 賭け受付を始める: 出走馬と倍率表を作り、前のレースの馬券と結果を消し、救済コインを配る。 */
function openBetting(s: GameState, raceNo: number, rng: Rng): GameState {
  const horses = makeField(rng);
  return {
    phase: 'betting',
    raceNo,
    horses,
    course: makeCourse(rng),
    oddsTable: makeOddsTable(horses),
    tips: makeTips(horses, rng),
    raceKey: `${raceNo}-${Math.floor(rng() * 0xffffffff).toString(36)}`,
    race: null,
    players: s.players.map((p) => ({
      ...p,
      tickets: [],
      results: null,
      tips: [],
      coins: p.coins < MIN_BET ? RESCUE_COINS : p.coins,
    })),
  };
}

export function adminStart(s: GameState, rng: Rng): R {
  if (s.phase !== 'lobby') return { state: s, error: 'not_allowed' };
  return { state: openBetting(s, 1, rng) };
}

export function adminCloseAndRace(s: GameState, rng: Rng, now: number): R {
  if (s.phase !== 'betting') return { state: s, error: 'not_allowed' };
  const order = drawOrder(s.horses, rng);
  const times = makeTimes(order, s.horses, s.course ?? { distance: 1600, going: '良' }, rng);
  return {
    state: {
      ...s,
      phase: 'racing',
      race: { startedAt: now, durationMs: raceDuration(times), order, times },
      players: s.players.map((p) => (p.tickets.length > 0 ? { ...p, coins: p.coins - staked(p) } : p)),
    },
  };
}

/** レースを精算して結果画面へ。racing 以外では何もしない(二重精算を防ぐ)。 */
export function finishRace(s: GameState): GameState {
  if (s.phase !== 'racing' || !s.race) return s;
  const order = s.race.order;
  return {
    ...s,
    phase: 'result',
    players: s.players.map((p) => {
      if (p.tickets.length === 0) return { ...p, results: null };
      const tickets: TicketResult[] = p.tickets.map((t) => {
        const won = ticketWins(t.type, t.horses, order);
        return { ...t, won, payout: won ? payout(t.amount, t.odds) : 0 };
      });
      const back = tickets.reduce((a, t) => a + t.payout, 0);
      const total = staked(p);
      return { ...p, coins: p.coins + back, results: { staked: total, delta: back - total, tickets } };
    }),
  };
}

export function adminNext(s: GameState, rng: Rng): R {
  if (s.phase !== 'result') return { state: s, error: 'not_allowed' };
  if (s.raceNo >= TOTAL_RACES) return { state: { ...s, phase: 'final' } };
  return { state: openBetting(s, s.raceNo + 1, rng) };
}

function backToLobby(s: GameState): GameState {
  return {
    phase: 'lobby',
    raceNo: 0,
    horses: [],
    course: null,
    oddsTable: null,
    tips: null,
    race: null,
    players: s.players.map((p) => ({ ...p, coins: START_COINS, tickets: [], results: null, tips: [] })),
  };
}

export function adminNewGame(s: GameState): R {
  if (s.phase !== 'final') return { state: s, error: 'not_allowed' };
  return { state: backToLobby(s) };
}

export function adminReset(s: GameState): R {
  return { state: backToLobby(s) };
}

export function kick(s: GameState, playerId: string): R {
  if (!s.players.some((p) => p.id === playerId)) return { state: s, error: 'not_allowed' };
  return { state: { ...s, players: s.players.filter((p) => p.id !== playerId) } };
}

export function kickAll(_s: GameState): R {
  return { state: newGame() };
}

/**
 * 先生の進行操作が、先生が見ていた場面に対するものかを確かめる。
 * 二重クリックの2回目は、1回目で場面が変わった後に届くので、ここで弾かれる。
 */
export function sameScene(s: GameState, phase: unknown, raceNo: unknown): boolean {
  return phase === s.phase && raceNo === s.raceNo;
}

/**
 * 単勝以外の倍率表を送るメッセージ。賭け受付中だけ作る。
 * 3連単が 336 通りあるので、状態の更新のたびではなく、受付の開始時と参加時に 1 回だけ送る。
 */
export function oddsMessage(s: GameState): OddsMessage | null {
  if (s.phase !== 'betting' || !s.raceKey) return null;
  return { t: 'odds', raceKey: s.raceKey, ...oddsTableOf(s) };
}

export function viewFor(s: GameState, playerId: string | null, isAdmin: boolean, now: number): View {
  // 他人の本当の id を知ると、その人になりすまして入り直せてしまう。本人と先生以外には公開用の id を送る。
  const shownId = (p: Player) => (isAdmin || p.id === playerId ? p.id : p.pub);
  const rankOf = (p: Player) => 1 + s.players.filter((q) => q.coins > p.coins).length;
  const sorted = [...s.players].sort(
    (a, b) => b.coins - a.coins || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0),
  );
  const me = playerId === null ? undefined : s.players.find((p) => p.id === playerId);
  const showHorses = s.phase === 'betting' || s.phase === 'racing' || s.phase === 'result';
  const showRace = s.phase === 'racing' || s.phase === 'result';
  const online = s.players.filter((p) => p.online);
  return {
    phase: s.phase,
    raceNo: s.raceNo,
    totalRaces: TOTAL_RACES,
    serverNow: now,
    raceKey: showHorses ? (s.raceKey ?? null) : null,
    horses: showHorses ? s.horses.map(publicHorse) : [],
    course: showHorses ? (s.course ?? null) : null,
    // 予想を持っている予想屋だけを扱う(保存された状態に、一部の予想屋の予想しかない場合がある)
    tipsters: s.phase === 'betting'
      ? TIPSTERS.filter((t) => s.tips?.[t.id]).map((t) => ({ id: t.id, name: t.name, price: t.price, stars: t.stars }))
      : [],
    tipResults: s.phase === 'result' && s.race
      ? TIPSTERS.filter((t) => s.tips?.[t.id]).map((t) => ({
          id: t.id, name: t.name, marks: s.tips![t.id].marks, hit: s.tips![t.id].marks[0] === s.race!.order[0],
        }))
      : [],
    players: sorted.map((p) => ({
      id: shownId(p),
      name: p.name,
      coins: p.coins,
      online: p.online,
      rank: rankOf(p),
      hasBet: isAdmin && p.tickets.length > 0,
    })),
    betCount: online.filter((p) => p.tickets.length > 0).length,
    onlineCount: online.length,
    me: me
      ? {
          id: me.id, name: me.name, coins: me.coins, rank: rankOf(me),
          tickets: me.tickets,
          results: me.results,
          // 買った予想屋の分だけ、予想の中身を送る
          tips: s.tips && showHorses
            ? TIPSTERS.filter((t) => me.tips.includes(t.id) && s.tips?.[t.id]).map((t) => ({
                id: t.id, marks: s.tips![t.id].marks, comment: s.tips![t.id].comment,
              }))
            : [],
          bet: legacyBet(me),
          lastResult: legacyResult(me),
        }
      : null,
    race: showRace ? s.race : null,
    bets:
      s.phase === 'result'
        ? s.players
            .filter((p) => p.results !== null)
            .map((p) => ({
              playerId: shownId(p),
              horse: legacyResult(p)?.horse ?? 0,
              amount: p.results!.staked,
              delta: p.results!.delta,
              tickets: p.results!.tickets.map((t) => ({
                type: t.type, horses: t.horses, amount: t.amount, odds: t.odds, won: t.won, payout: t.payout,
              })),
            }))
        : [],
    isAdmin,
  };
}

/** 古いアプリは単勝 1 点しか表示できない。最初の単勝を見せる(単勝がなければ「賭けていない」)。 */
function legacyBet(p: Player): LegacyBet | null {
  const win = p.tickets.find((t) => t.type === 'win');
  return win ? { horse: win.horses[0], amount: win.amount } : null;
}

function legacyResult(p: Player): LegacyResult | null {
  const r = p.results;
  if (!r || r.tickets.length === 0) return null;
  const shown = r.tickets.find((t) => t.type === 'win') ?? r.tickets[0];
  return { horse: shown.horses[0], amount: r.staked, won: r.delta > 0, delta: r.delta };
}

function publicHorse(h: Horse): PublicHorse {
  return {
    no: h.no, name: h.name, odds: h.odds,
    sex: h.sex, age: h.age, weight: h.weight, weightDiff: h.weightDiff,
    style: h.style, recent: h.recent, pop: h.pop, cond: h.cond, mood: h.mood,
  };
}
