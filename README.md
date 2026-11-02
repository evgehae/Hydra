# Гидра (Hydra)

VPN-клиент, у которого отрастают новые головы: ломается один путь — тут же работает другой.

## Идея
- **Память по сети** — что работало в этой сети (Wi-Fi/оператор), пробуется первым (`memory.go`).
- **Гонка стратегий** — топ кандидатов стартуют со сдвигом, побеждает первый рабочий (`orchestrator.go: race`).
- **Горячий резерв** — второй туннель на другой стратегии всегда прогрет (`warm`).
- **Самолечение** — деградация качества или смерть туннеля → мгновенный переход на резерв (`session`).
- **Причина сбоя** — DNS / DPI / сервер / сеть, показывается человеку (`events.go`).

## Структура
core/transport.go      интерфейсы Transport / Tunnel / Strategy
core/memory.go         память стратегий по сетям
core/orchestrator.go   гонка, резерв, наблюдение, Run
core/events.go         события и диагностика
core/orchestrator_test.go  тесты на фейковых транспортах

## Тесты
cd core && go test ./...

## Дальше
1. Transport «WARP/MASQUE» (usque + quic-go) + стратегии из zapret2.
2. Transport «AmneziaWG» (amneziawg-go).
3. Реальный Diagnoser (DNS-проба, проба без обхода, проба endpoint).
4. gomobile bind → Kotlin: VpnService + hev-socks5-tunnel, ключ сети из ConnectivityManager.
5. UI со статусом по событиям.
