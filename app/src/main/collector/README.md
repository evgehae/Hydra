# Сборщик опыта Гидры

1. Cloudflare → Workers & Pages → KV → Create namespace `hydra-collect`. Скопируй его ID в `wrangler.toml`.
2. `npm i -g wrangler && wrangler login && wrangler secret put EXPORT_TOKEN` (придумай длинный пароль) → `wrangler deploy`.
3. Адрес воркера (`https://hydra-collect.<твой>.workers.dev`) впиши в `Telemetry.kt` (`DEFAULT_URL`, оканчивается на `/v1/submit`) и пересобери приложение.
4. Забрать отчёты: `curl -H "Authorization: Bearer ТОКЕН" "https://…workers.dev/v1/export?day=2026-11-28" > export.json` — файл отправь Claude.
5. Обновить priors: `python3 aggregate.py export.json ../priors.json`.
