// ゲームの状態と状態遷移(純粋関数)。引数の state は変更せず、新しい state を返す。

import {
  drawOrder, makeField, makeTimes, payout,
  HORSES, MAX_PLAYERS, MIN_BET, NAME_MAX, RACE_DURATION_MS, RESCUE_COINS, START_COINS, TOTAL_RACES,
  type Horse, type Rng,
} from './rules';

export type Phase = 'lobby' | 'betting' | 'racing' | 'result' | 'final';

export type ErrorCode =
  | 'bad_message' | 'bad_name' | 'name_taken' | 'room_full'
  | 'bad_key' | 'bad_bet' | 'not_allowed' | 'kicked';

export type Bet = { horse: number; amount: number };
export type LastResult = { horse: number; amount: number; won: boolean; delta: number };

export type Player = {
  /** 本人だけが知る id(入り直しの確認に使う)。本人と先生以外には送らない。 */
  id: string;
  /** 公開用の id。ほかの生徒に見せる順位表や賭けの一覧ではこちらを使う。 */
  pub: string;
  name: string;
  coins: number;
  online: boolean;
  bet: Bet | null;
  lastResult: LastResult | null;
};

export type Race = { startedAt: number; durationMs: number; order: number[]; times: number[][] };

export type GameState = {
  phase: Phase;
  raceNo: number;
  horses: Horse[];
  players: Player[];
  race: Race | null;
};

export type R = { state: GameState; error?: ErrorCode };

export type View = {
  phase: Phase;
  raceNo: number;
  totalRaces: number;
  serverNow: number;
  horses: { no: number; name: string; odds: number }[];
  players: { id: string; name: string; coins: number; online: boolean; rank: number; hasBet: boolean }[];
  betCount: number;
  onlineCount: number;
  me: { id: string; name: string; coins: number; rank: number; bet: Bet | null; lastResult: LastResult | null } | null;
  race: Race | null;
  bets: { playerId: string; horse: number; amount: number; delta: number }[];
  isAdmin: boolean;
};

export function newGame(): GameState {
  return { phase: 'lobby', raceNo: 0, horses: [], players: [], race: null };
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
    id: playerId, pub: newId(), name, coins: START_COINS, online: true, bet: null, lastResult: null,
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

export function placeBet(s: GameState, playerId: string, horse: unknown, amount: unknown): R {
  const p = s.players.find((x) => x.id === playerId);
  if (!p || s.phase !== 'betting') return { state: s, error: 'not_allowed' };
  if (typeof horse !== 'number' || !Number.isInteger(horse) || horse < 1 || horse > HORSES) {
    return { state: s, error: 'bad_bet' };
  }
  if (
    typeof amount !== 'number' || !Number.isInteger(amount) ||
    amount < MIN_BET || amount % MIN_BET !== 0 || amount > p.coins
  ) {
    return { state: s, error: 'bad_bet' };
  }
  return { state: mapPlayer(s, playerId, (x) => ({ ...x, bet: { horse, amount } })) };
}

export function cancelBet(s: GameState, playerId: string): R {
  const p = s.players.find((x) => x.id === playerId);
  if (!p || s.phase !== 'betting') return { state: s, error: 'not_allowed' };
  return { state: mapPlayer(s, playerId, (x) => ({ ...x, bet: null })) };
}

/** 賭け受付を始める: 出走馬を作り、前のレースの賭けと結果を消し、救済コインを配る。 */
function openBetting(s: GameState, raceNo: number, rng: Rng): GameState {
  return {
    phase: 'betting',
    raceNo,
    horses: makeField(rng),
    race: null,
    players: s.players.map((p) => ({
      ...p,
      bet: null,
      lastResult: null,
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
  return {
    state: {
      ...s,
      phase: 'racing',
      race: { startedAt: now, durationMs: RACE_DURATION_MS, order, times: makeTimes(order, rng) },
      players: s.players.map((p) => (p.bet ? { ...p, coins: p.coins - p.bet.amount } : p)),
    },
  };
}

/** レースを精算して結果画面へ。racing 以外では何もしない(二重精算を防ぐ)。 */
export function finishRace(s: GameState): GameState {
  if (s.phase !== 'racing' || !s.race) return s;
  const winner = s.race.order[0];
  const odds = s.horses.find((h) => h.no === winner)!.odds;
  return {
    ...s,
    phase: 'result',
    players: s.players.map((p) => {
      if (!p.bet) return { ...p, lastResult: null };
      const won = p.bet.horse === winner;
      const back = won ? payout(p.bet.amount, odds) : 0;
      return {
        ...p,
        coins: p.coins + back,
        lastResult: { horse: p.bet.horse, amount: p.bet.amount, won, delta: back - p.bet.amount },
      };
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
    race: null,
    players: s.players.map((p) => ({ ...p, coins: START_COINS, bet: null, lastResult: null })),
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
    horses: showHorses ? s.horses.map((h) => ({ no: h.no, name: h.name, odds: h.odds })) : [],
    players: sorted.map((p) => ({
      id: shownId(p),
      name: p.name,
      coins: p.coins,
      online: p.online,
      rank: rankOf(p),
      hasBet: isAdmin && p.bet !== null,
    })),
    betCount: online.filter((p) => p.bet !== null).length,
    onlineCount: online.length,
    me: me
      ? { id: me.id, name: me.name, coins: me.coins, rank: rankOf(me), bet: me.bet, lastResult: me.lastResult }
      : null,
    race: showRace ? s.race : null,
    bets:
      s.phase === 'result'
        ? s.players
            .filter((p) => p.bet && p.lastResult)
            .map((p) => ({ playerId: shownId(p), horse: p.bet!.horse, amount: p.bet!.amount, delta: p.lastResult!.delta }))
        : [],
    isAdmin,
  };
}
