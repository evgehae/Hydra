ПАТЧ 23 — Self-Heal: автолечение zombie-туннеля (после сна / «up, а интернета нет»)
====================================================================================
Ставить ПОВЕРХ текущего main. Только Kotlin + strings (ядро Go не трогали).
Не компилировалось локально (нет Android SDK): смотри GitHub Actions.

ПРОБЛЕМА
--------
Симптом (два телефона, MTS и Beeline):
  • Статус «подключено · HEL · хороший пинг»
  • YouTube / Telegram / WhatsApp не грузятся
  • После сна особенно часто
  • Помогает: остановка приложения + очистка кеша + запуск

Суть: HEL/проба живы, а пользовательский путь через TUN мёртв (zombie).
Очистка кеша лечила в основном полным перезапуском процесса/TUN, а не «магией cache/».

ЧТО ДАЁТ ПАТЧ
-------------
1) Автоматическое самолечение без участия пользователя (по умолчанию ВКЛ).
2) Лестница: soft → full → hard → (опционально root).
3) Внеочередная проверка при включении экрана / USER_PRESENT.
4) Подробный журнал всех зависаний и лечений (теги ниже).
5) Ручной «Сбросить туннель» в Диагностике с выбором силы.
6) Настройки в Дополнительно → «Автолечение туннеля».

ФАЙЛЫ (копировать с сохранением путей)
--------------------------------------
  app/src/main/java/app/hydra/HydraVpnService.kt
  app/src/main/java/app/hydra/Prefs.kt
  app/src/main/java/app/hydra/RootHelper.kt
  app/src/main/java/app/hydra/VpnController.kt
  app/src/main/java/app/hydra/DiagnosticsScreen.kt
  app/src/main/java/app/hydra/AdvancedScreens.kt
  app/src/main/res/values/strings.xml
  app/src/main/res/values-ru/strings.xml

Готовый zip патча (те же файлы):
  artifacts/hydra-selfheal-patch.zip
  внутри: hydra-selfheal/*.kt + values*/strings.xml

ШАГИ УСТАНОВКИ В РЕПО
---------------------
1. Распакуй zip патча или скопируй файлы поверх клона:
     unzip hydra-selfheal-patch.zip
     # Kotlin:
     cp hydra-selfheal/HydraVpnService.kt   app/src/main/java/app/hydra/
     cp hydra-selfheal/Prefs.kt             app/src/main/java/app/hydra/
     cp hydra-selfheal/RootHelper.kt        app/src/main/java/app/hydra/
     cp hydra-selfheal/VpnController.kt     app/src/main/java/app/hydra/
     cp hydra-selfheal/DiagnosticsScreen.kt app/src/main/java/app/hydra/
     cp hydra-selfheal/AdvancedScreens.kt   app/src/main/java/app/hydra/
     # Strings:
     cp hydra-selfheal/values/strings.xml    app/src/main/res/values/
     cp hydra-selfheal/values-ru/strings.xml app/src/main/res/values-ru/
2. НЕ нужно трогать bootstrap.sh / Go / AAR — только Kotlin UI/служба.
3. git add перечисленные файлы && commit && push
4. Дождись зелёного Actions (APK).
5. Поставь APK. В отчёте/журнале ищи теги HEALTH_ / TUNNEL_ / RECOVERY_ / WAKE_.

НАСТРОЙКИ (Prefs)
-----------------
  autoHeal            Boolean  default true
      Автолечение zombie (up + мёртвые сервисы).

  rootHealEnhanced    Boolean  default false
      После неудачи обычных уровней: root clearAppCache, при повторе force-stop.
      Имеет смысл только при useRoot=true и реальном root.

  healFailThreshold   Int 1..3  default 2
      Сколько плохих проверок подряд до лечения (после WAKE достаточно 1).

  serviceCheckEveryMin  (уже было)  default 3
      Базовый интервал; автолечение не реже раз в 30 с.

UI
--
  Дополнительно → «Автолечение туннеля»
    • Автолечение zombie-туннеля (вкл/выкл)
    • Усиленное лечение (root) — только если root обнаружен

  Диагностика → «Сбросить туннель»
    • Мягкий  (soft)
    • Полный  (full)
    • Жёсткий (hard)
    • Root    (если useRoot)

ЛЕСТНИЦА ЛЕЧЕНИЯ (performHeal)
-----------------------------
  soft  — stopTunnel → startVpn, TUN не закрываем (новая стратегия)
  full  — stopTunnel → closeTun → startVpn (новый TUN + гонка)
  hard  — full + prefs.aiDnsCache="" + удаление временных файлов в cacheDir
          (reports/, hydra*, обычные файлы cache)
  root  — hard + RootHelper.clearAppCache(pkg)
          если в окне уже много попыток → RootHelper.forceStopPackage(pkg)
          (START_STICKY / автозапуск поднимут службу снова при wantConnected)

Автоматика поднимает уровень: soft → full → hard → root (root только если
rootHealEnhanced && useRoot && hasRoot). После успешной проверки сервисов
уровень сбрасывается в 0.

Защита от циклов:
  • кулдаун 45 с между лечениями
  • не больше 4 лечений за 15 минут (RECOVERY_BACKOFF)

ДЕТЕКЦИЯ ZOMBIE
---------------
  maybeServiceCheck() вызывает mobile.Mobile.serviceCheck().
  Критично, если:
    • «Доступно X из Y» при Y≥6 и X≤4  (mostlyDead), или
    • DNS через туннель мёртв И базовые Google/Cloudflare/SYN-ACK мертвы, или
    • X==0 при Y≥3
  Один упавший YouTube при живом остальном путь НЕ рвёт.

  Периодически (statusUpdater, state=up) и принудительно:
    • после WAKE (SCREEN_ON / USER_PRESENT) через ~2.5 с
    • после каждого уровня лечения через 12–14 с

ТЕГИ ЖУРНАЛА (искать в отчёте / Диагностика → Журнал)
-----------------------------------------------------
  HEALTH_CHECK_OK          — сервисы через туннель в порядке
  HEALTH_CHECK_FAILED      — текст проверки (укороченный)
  HEALTH_CHECK_RECOVERED   — снова ок после серии сбоев
  HEALTH_CHECK_ERROR       — исключение при проверке
  TUNNEL_DEGRADED          — up, но путь плохой (streak, ok/total, dns/base)
  RECOVERY_STARTED         — level=… manual=… reason=…
  RECOVERY_SOFT / _DONE
  TUN_RECREATED
  RECOVERY_FULL_DONE
  CACHE_CLEARED            — свой кеш / root cache
  RECOVERY_HARD_DONE
  RECOVERY_ROOT / _DONE
  RECOVERY_COOLDOWN        — ещё рано после прошлого лечения
  RECOVERY_BACKOFF         — лимит попыток в окне
  RECOVERY_FAILED          — исключение в performHeal
  WAKE_EVENT               — экран/user present → внеочередная проверка

Intent API службы
-----------------
  ACTION_START  app.hydra.action.START
  ACTION_STOP   app.hydra.action.STOP   extra src=
  ACTION_RESET  app.hydra.action.RESET  extra level=soft|full|hard|root
                                        extra src=…

  VpnController.resetTunnel(level, src) шлёт ACTION_RESET, wantConnected=true.

RootHelper (новые методы)
-------------------------
  clearAppCache(pkg)     — su: rm -rf /data/data/$pkg/cache/* и code_cache/*
  forceStopPackage(pkg)  — su: am force-stop $pkg

КАК ПРОВЕРИТЬ
-------------
1. Поставить APK с патчем 23.
2. Подключить VPN, убедиться что сервисы ✔.
3. Усыпить телефон надолго (или вручную: Диагностика → Сбросить туннель → полный).
4. После пробуждения: если путь zombie — в журнале WAKE_EVENT → HEALTH_CHECK_FAILED /
   TUNNEL_DEGRADED → RECOVERY_* → снова HEALTH_CHECK_OK.
5. На root-телефоне: включить «Усиленное лечение (root)» и при необходимости
   проверить hard/root уровни вручную из Диагностики.

ЧЕГО НЕТ В ЭТОМ ПАТЧЕ
---------------------
  • Go-ядро (engine/gate/services) не менялось — serviceCheck тот же.
  • Системный «Очистить кеш» без root по-прежнему недоступен (это нормально).
  • Не чистим память стратегий по всем сетям — только временное + AI-DNS cache
    на hard; root чистит cacheDir приложения.

СВЯЗЬ С ДИАГНОЗОМ D26 / D40 / D45
---------------------------------
  D26 (батарея) — по-прежнему нужно «без ограничений»; self-heal не заменяет это.
  D40 (проверка сервисов) — теперь идёт автоматически и лечит.
  D45 (split) — не меняли; для отладки стабильности split лучше временно выключить.
