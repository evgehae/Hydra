ЯДРО Hydra — только эти файлы (аккуратное обновление)
====================================================

После установки APK в отчёте ОБЯЗАТЕЛЬНО:
  core: hydra-core 1.0.1-gate (probe 4s, up 2s)

Если всё ещё "probe 5s" или нет "1.0.1-gate" — AAR старый.

ФАЙЛЫ (копировать с сохранением путей)
--------------------------------------
  engine.go
  gate.go
  wg.go
  colo.go
  learn.go
  services.go
  mobile/mobile.go

Опционально:
  app/src/main/java/app/hydra/HydraVpnService.kt
  (force reconnect при мёртвых DNS/YouTube)

ШАГИ
----
1. Распакуй zip поверх клона репозитория.
2. НЕ запускай bootstrap.sh после замены.
3. git add перечисленные файлы && commit && push
4. Дождись зелёного Actions (gomobile bind + APK)
5. Поставь APK из Artifacts/Release
6. Новый отчёт → строка core с 1.0.1-gate (probe 4s, up 2s)

ЧТО ДАЁТ ЯДРО
-------------
- UpTimeout 2s (быстрый отказ мёртвой стратегии)
- serviceGate: DNS fail → смена пути (не «up без YouTube»)
- прологи WG: dns / sip / h3
- TraceInfo для cdn-cgi/trace
