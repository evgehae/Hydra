ПАТЧ Hydra (распаковать поверх репозитория с сохранением путей, потом commit + push, дождаться Actions)

1. build.yml: gomobile bind -target=android/arm,android/arm64 — ядро для 32-бит ТВ (armeabi-v7a). Было только arm64.
2. race.go, engine.go: нижняя граница ожидания ответа туннеля для медленных сетей (профиль оператора или learned: лучший успех >= 400 мс) = 3,5 с. «Карантин» больше не режет до ~1,3 с.
3. wg.go: перебор подсетей теперь с q3, s3 (STUN) и h3-прологом, а не только q3; добавлен хост 162.159.192.6.
4. brain.go: сиды Билайна: wg-h3 на 162.159.192.6/.4/.3.
5. profiles.go (новый): профили операторов (UpFloor, предпочтительные дата-центры AMS/HEL/FRA — мягкий бонус в Rank), стартовые гены пролога WG по оператору, SlowNet, ForgetNet, пропуск IPv6 на 5 минут после «network is unreachable».
6. memory.go: бонус дата-центра в Rank. genes.go: стартовые гены по оператору. learn.go: фильтр v6. masque_runner.go/wg_runner.go: markV6Dead.
7. mobile/vpn_usque.go: ForgetCurrentNet(dir). AdvancedScreens.kt: строка «Забыть эту сеть», диапазон таймаута 1200–5000. HomeScreen.kt: на ТВ нет кнопки мобильной регистрации. strings: forget_net_*.

Не компилировалось локально (нет Go в среде): смотри go vet/go test в Actions. После установки в отчёте: core: hydra-core ... (не n/a на ТВ).
