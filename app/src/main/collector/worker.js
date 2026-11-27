// Сборщик опыта Гидры: Cloudflare Worker + KV. Хранит анонимные отчёты, IP отправителя НЕ сохраняется.
// Развёртывание: см. README.md в этой папке.
const ALLOWED = ['v', 'id', 'ts', 'app', 'android', 'vendor', 'tv', 'settings', 'priors', 'ai'];

export default {
  async fetch(req, env) {
    const url = new URL(req.url);

    if (req.method === 'POST' && url.pathname === '/v1/submit') {
      if ((+req.headers.get('content-length') || 0) > 262144) return new Response('too large', { status: 413 });
      let body;
      try { body = JSON.parse(await req.text()); } catch { return new Response('bad json', { status: 400 }); }
      if (body.v !== 1 || typeof body.id !== 'string' || body.id.length < 8 || body.id.length > 64) {
        return new Response('bad request', { status: 400 });
      }
      const day = new Date().toISOString().slice(0, 10);
      const key = `s:${day}:${body.id}`;
      if (await env.HYDRA_KV.get(key)) return new Response('ok (already today)');
      const clean = {};
      for (const k of ALLOWED) if (k in body) clean[k] = body[k];
      await env.HYDRA_KV.put(key, JSON.stringify(clean), { expirationTtl: 60 * 60 * 24 * 120 });
      return new Response('ok');
    }

    if (req.method === 'GET' && url.pathname === '/v1/export') {
      if (req.headers.get('authorization') !== 'Bearer ' + env.EXPORT_TOKEN) return new Response('forbidden', { status: 403 });
      const prefix = 's:' + (url.searchParams.get('day') || '');
      const out = [];
      let cursor;
      do {
        const l = await env.HYDRA_KV.list({ prefix, cursor });
        for (const k of l.keys) out.push(JSON.parse(await env.HYDRA_KV.get(k.name)));
        cursor = l.list_complete ? undefined : l.cursor;
      } while (cursor);
      return new Response(JSON.stringify(out), { headers: { 'content-type': 'application/json' } });
    }

    return new Response('hydra collector', { status: 404 });
  },
};
