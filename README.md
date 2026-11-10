# Гидра (Hydra) — «WARP CLAUDE»

VPN-клиент для Android поверх Cloudflare WARP (MASQUE и WireGuard), который сам подбирает рабочий путь и чинит себя.

## Как устроено
- `engine.go` — движок: TUN ↔ туннель, проверки (UDP, реальный TCP), политика дата-центров, смена сети, перебор стратегий.
- `strategies.go`, `custom.go`, `wg.go` — стратегии подключения (фейковые QUIC-пакеты, SNI, порты, HTTP/2, WireGuard).
- `memory.go` — память: что работало в какой сети (сохраняется сразу после результата).
- `register.go` — регистрация аккаунта WARP «гонкой маршрутов».
- `mobile/` — обвязка gomobile для Kotlin.
- `orchestrator.go`, `front.go`, `transport.go` — прототип гонки/горячего резерва (пока не подключён к движку).
- `app/` — Android-приложение (Compose): главный экран с ползунком; меню → «Дополнительно» и «Диагностика».

## Сборка
Через GitHub Actions: `bootstrap.sh` раскладывает файлы проекта, workflow собирает AAR и APK.
