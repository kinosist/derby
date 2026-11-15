// Worker の入口。/ws の WebSocket を、固定名の Durable Object「Room」1個に渡す。
// /admin 以下の管理ページは wrangler.jsonc の assets 設定で配信される。

import type { Env } from './room';

export { Room } from './room';

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === '/ws') {
      if (request.headers.get('Upgrade') !== 'websocket') {
        return new Response('Expected WebSocket', { status: 426 });
      }
      return env.ROOM.get(env.ROOM.idFromName('main')).fetch(request);
    }
    if (url.pathname === '/') return new Response('ok');
    return new Response('Not found', { status: 404 });
  },
};
