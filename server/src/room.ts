// 部屋(Durable Object)。WebSocket・保存・アラームだけを受け持ち、ルールは game.ts に任せる。

import { DurableObject } from 'cloudflare:workers';
import {
  adminCloseAndRace, adminNewGame, adminNext, adminReset, adminStart, cancelBet, finishRace,
  join, kick, kickAll, newGame, placeBet, sameScene, setOnline, viewFor,
  type ErrorCode, type GameState, type R,
} from './game';
import { cryptoRng } from './rules';

export interface Env {
  ROOM: DurableObjectNamespace<Room>;
  TEACHER_KEY?: string;
}

type Attachment = { role: 'none' | 'player' | 'admin'; playerId?: string; badKeys?: number };

const MAX_MESSAGE_CHARS = 2048;
const MAX_BAD_KEYS = 5;

const ERROR_MESSAGES: Record<ErrorCode, string> = {
  bad_message: '送信内容が正しくありません',
  bad_name: '名前は1〜12文字で入力してください',
  name_taken: 'その名前は使われています',
  room_full: '部屋が満員です',
  bad_key: 'パスワードが違います',
  bad_bet: 'その賭けはできません',
  not_allowed: '今はその操作はできません',
  kicked: '先生が退出させました',
};

export class Room extends DurableObject<Env> {
  private state: GameState = newGame();
  private rng = cryptoRng();

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      this.state = (await ctx.storage.get<GameState>('state')) ?? newGame();
      // 休止・再起動をまたいで残っている接続と、参加者の接続状態を突き合わせる
      const connected = new Set<string>();
      for (const ws of ctx.getWebSockets()) {
        const att = attachmentOf(ws);
        if (att.role === 'player' && att.playerId) connected.add(att.playerId);
      }
      let s = this.state;
      for (const p of s.players) s = setOnline(s, p.id, connected.has(p.id));
      // レース中に止まっていた場合: 時間が過ぎていれば精算し、まだならアラームを張り直す
      if (s.phase === 'racing' && s.race) {
        const end = s.race.startedAt + s.race.durationMs;
        if (Date.now() >= end) s = finishRace(s);
        else await ctx.storage.setAlarm(end);
      }
      if (s !== this.state) {
        this.state = s;
        await ctx.storage.put('state', s);
      }
    });
  }

  async fetch(_request: Request): Promise<Response> {
    const pair = new WebSocketPair();
    this.ctx.acceptWebSocket(pair[1]);
    pair[1].serializeAttachment({ role: 'none' } satisfies Attachment);
    return new Response(null, { status: 101, webSocket: pair[0] });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    try {
      if (typeof message !== 'string' || message.length > MAX_MESSAGE_CHARS) {
        return this.sendError(ws, 'bad_message');
      }
      let msg: unknown;
      try {
        msg = JSON.parse(message);
      } catch {
        return this.sendError(ws, 'bad_message');
      }
      if (typeof msg !== 'object' || msg === null || Array.isArray(msg)) {
        return this.sendError(ws, 'bad_message');
      }
      await this.handle(ws, msg as Record<string, unknown>);
    } catch (e) {
      console.error('message handling failed', e);
      this.sendError(ws, 'bad_message');
    }
  }

  private async handle(ws: WebSocket, msg: Record<string, unknown>): Promise<void> {
    const att = attachmentOf(ws);
    switch (msg.t) {
      case 'join': {
        if (att.role === 'admin') return this.sendError(ws, 'not_allowed');
        const r = join(this.state, msg.id, msg.name, () => crypto.randomUUID());
        if (r.error || !r.playerId) return this.sendError(ws, r.error ?? 'bad_message');
        let s = r.state;
        // 同じ参加者の古い接続を閉じる
        if (r.replacedId) this.dropSockets(r.replacedId, ws, 4000, 'replaced');
        // この接続が別の参加者として入っていた場合、その人は切断扱いにする
        if (att.role === 'player' && att.playerId && att.playerId !== r.playerId) {
          if (!this.hasOtherSocket(att.playerId, ws)) s = setOnline(s, att.playerId, false);
        }
        ws.serializeAttachment({ role: 'player', playerId: r.playerId } satisfies Attachment);
        return this.commit(s);
      }
      case 'admin': {
        const key = this.env.TEACHER_KEY;
        if (!key || typeof msg.key !== 'string' || msg.key !== key) {
          const badKeys = (att.badKeys ?? 0) + 1;
          ws.serializeAttachment({ ...att, badKeys } satisfies Attachment);
          this.sendError(ws, 'bad_key');
          if (badKeys >= MAX_BAD_KEYS) ws.close(4003, 'too many attempts');
          return;
        }
        let s = this.state;
        if (att.role === 'player' && att.playerId && !this.hasOtherSocket(att.playerId, ws)) {
          s = setOnline(s, att.playerId, false);
        }
        ws.serializeAttachment({ role: 'admin' } satisfies Attachment);
        return this.commit(s);
      }
      case 'bet': {
        if (att.role !== 'player' || !att.playerId) return this.sendError(ws, 'not_allowed');
        return this.apply(ws, placeBet(this.state, att.playerId, msg.horse, msg.amount));
      }
      case 'cancelBet': {
        if (att.role !== 'player' || !att.playerId) return this.sendError(ws, 'not_allowed');
        return this.apply(ws, cancelBet(this.state, att.playerId));
      }
      case 'adminAction': {
        if (att.role !== 'admin') return this.sendError(ws, 'not_allowed');
        return this.adminAction(ws, msg);
      }
      default:
        return this.sendError(ws, 'bad_message');
    }
  }

  private async adminAction(ws: WebSocket, msg: Record<string, unknown>): Promise<void> {
    // 進行を進める操作は、先生が見ていた場面(phase と raceNo)を添えて送る。
    // 今の場面と違えば、二重クリックなどの古い操作なので受け付けない。
    const advances = msg.action === 'start' || msg.action === 'closeAndRace' || msg.action === 'next' || msg.action === 'newGame';
    if (advances && !sameScene(this.state, msg.phase, msg.raceNo)) return this.sendError(ws, 'not_allowed');
    switch (msg.action) {
      case 'start':
        return this.apply(ws, adminStart(this.state, this.rng));
      case 'closeAndRace': {
        const r = adminCloseAndRace(this.state, this.rng, Date.now());
        if (!r.error && r.state.race) {
          await this.ctx.storage.setAlarm(r.state.race.startedAt + r.state.race.durationMs);
        }
        return this.apply(ws, r);
      }
      case 'next':
        return this.apply(ws, adminNext(this.state, this.rng));
      case 'newGame':
        return this.apply(ws, adminNewGame(this.state));
      case 'reset':
        await this.ctx.storage.deleteAlarm();
        return this.apply(ws, adminReset(this.state));
      case 'kick': {
        if (typeof msg.playerId !== 'string') return this.sendError(ws, 'bad_message');
        const r = kick(this.state, msg.playerId);
        if (!r.error) this.dropSockets(msg.playerId, null, 4001, 'kicked', 'kicked');
        return this.apply(ws, r);
      }
      case 'kickAll': {
        await this.ctx.storage.deleteAlarm();
        for (const p of this.state.players) this.dropSockets(p.id, null, 4001, 'kicked', 'kicked');
        return this.apply(ws, kickAll(this.state));
      }
      default:
        return this.sendError(ws, 'bad_message');
    }
  }

  async alarm(): Promise<void> {
    await this.commit(finishRace(this.state));
  }

  async webSocketClose(ws: WebSocket, code: number, _reason: string, _wasClean: boolean): Promise<void> {
    try {
      ws.close(code === 1005 || code === 1006 ? 1000 : code);
    } catch {
      // すでに閉じている
    }
    await this.disconnected(ws);
  }

  async webSocketError(ws: WebSocket, _error: unknown): Promise<void> {
    await this.disconnected(ws);
  }

  private async disconnected(ws: WebSocket): Promise<void> {
    const att = attachmentOf(ws);
    if (att.role !== 'player' || !att.playerId) return;
    if (this.hasOtherSocket(att.playerId, ws)) return;
    await this.commit(setOnline(this.state, att.playerId, false));
  }

  /** 結果を反映する。エラーなら送信元にだけ返す。 */
  private async apply(ws: WebSocket, r: R): Promise<void> {
    if (r.error) return this.sendError(ws, r.error);
    await this.commit(r.state);
  }

  /** 状態を保存し、全員にその人向けのスナップショットを送る。 */
  private async commit(s: GameState): Promise<void> {
    if (s !== this.state) {
      this.state = s;
      await this.ctx.storage.put('state', s);
    }
    const now = Date.now();
    for (const ws of this.ctx.getWebSockets()) {
      const att = attachmentOf(ws);
      if (att.role === 'none') continue;
      const view = viewFor(s, att.playerId ?? null, att.role === 'admin', now);
      this.send(ws, { t: 'state', ...view });
    }
  }

  private hasOtherSocket(playerId: string, except: WebSocket): boolean {
    return this.ctx.getWebSockets().some((w) => {
      if (w === except) return false;
      const a = attachmentOf(w);
      return a.role === 'player' && a.playerId === playerId;
    });
  }

  /** ある参加者の接続を(except 以外)すべて閉じる。閉じた接続は参加者と無関係な扱いにする。 */
  private dropSockets(
    playerId: string, except: WebSocket | null, code: number, reason: string, error?: ErrorCode,
  ): void {
    for (const w of this.ctx.getWebSockets()) {
      if (w === except) continue;
      const a = attachmentOf(w);
      if (a.role !== 'player' || a.playerId !== playerId) continue;
      w.serializeAttachment({ role: 'none' } satisfies Attachment);
      if (error) this.sendError(w, error);
      try {
        w.close(code, reason);
      } catch {
        // すでに閉じている
      }
    }
  }

  private sendError(ws: WebSocket, code: ErrorCode): void {
    this.send(ws, { t: 'error', code, message: ERROR_MESSAGES[code] });
  }

  private send(ws: WebSocket, data: unknown): void {
    try {
      ws.send(JSON.stringify(data));
    } catch {
      // 閉じかけの接続。切断処理は webSocketClose に任せる。
    }
  }
}

function attachmentOf(ws: WebSocket): Attachment {
  return (ws.deserializeAttachment() as Attachment | null) ?? { role: 'none' };
}
