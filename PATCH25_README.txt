ПАТЧ 25 — Добиваем стабильность (зал славы, ТВ parallel, wake+root, priors, тихая смерть)
========================================================================================
Ставить ПОВЕРХ патчей 23 (self-heal) и 24 (жизнь потока).
Kotlin + Go + priors. Сборка: GitHub Actions.

Это оставшиеся пункты из плана «пять улучшений», кроме уже сделанных 23/24.

ЧТО СДЕЛАНО
-----------
1) Зал славы сильнее влияет на выбор пути (hall.go)
   • Реальный успех: бонус 0.75 (было 0.45), при N≥3 → 0.95
   • После обрыва/heal Rank чаще поднимает уже проверенные стратегии
   • Лог по-прежнему: «🏆 зал славы …»

2) ТВ / leanback: всегда горячий резерв (HydraVpnService.kt)
   • На приставках parallel принудительно ≥ 2
   • Убирает D21 «параллельный режим выкл» и паузу без резерва при обрыве
   • Prefs.isLeanback() для проверки

3) После пробуждения + root (HydraVpnService.kt)
   • WAKE_EVENT → если useRoot: protectProcess + boostTun
   • Затем внеочередной HEALTH_CHECK (как в патче 23)
   • В журнале: WAKE_ROOT: protect=… / boostTun done

4) Priors (priors.json + assets/priors.json)
   • cell:25002 (МегаФон): семена WG s3/v4/q3r + HEL-порты h3
   • cell:25001 (МТС): в начало добавлены рабочие HEL :4443/:4500/:1701

5) «Тихая смерть» пути (race.go)
   • Если пробы падают и трафика приложений почти нет — failover быстрее (limit 2)
   • Меньше ситуаций «status=up, а пусто» до self-heal

Связка с 23/24:
  23 — zombie после сна (Kotlin service check + лестница)
  24 — не ротировать живой путь каждые ~20 с (FlowTTL ≥ 10 мин)
  25 — быстрее выбирать проверенное, ТВ с резервом, root после wake, priors

ФАЙЛЫ
-----
  hall.go
  race.go
  profiles.go          (если ещё нет патча 24 — он внутри)
  profiles_test.go     (патч 24)
  priors.json
  app/src/main/assets/priors.json
  app/src/main/java/app/hydra/HydraVpnService.kt
  app/src/main/java/app/hydra/Prefs.kt

  (+ из патча 23, если ещё не влиты:)
  RootHelper.kt, VpnController.kt, DiagnosticsScreen.kt, AdvancedScreens.kt
  values/strings.xml, values-ru/strings.xml

ШАГИ
----
1. Скопируй файлы поверх клона (пути сохранить).
2. Если патч 23/24 ещё не в main — возьми их из hydra-selfheal-patch.zip и hydra-patch24.zip.
3. git add … && commit && push → Actions → APK.
4. Проверка:
   • Телефон: сон → WAKE_EVENT (+ WAKE_ROOT если root) → HEALTH_* / RECOVERY_*
   • МегаФон Wi-Fi: меньше «плановая ротация ~20s», дольше up
   • ТВ: в отчёте parallel не «выкл», есть резерв
   • Журнал: зал славы и быстрый failover при «проба без ответа»

НЕ СДЕЛАНО (осознанно)
----------------------
  • Keepalive-пакеты в глубоком Doze (нужен отдельный wake lock — батарея)
  • Смена системного parallel default у уже установленных ТВ без обновления
    (после установки APK с 25 при старте VPN par≥2 на leanback сам)
