Патч #2 — ложный «up», плитка WARP, jmin/jmax → ядро, root-защита

ЧТО ИСПРАВЛЕНО
1. serviceGate жёстче (gate.go):
   - проверка через 0.8 с, не 2.5 с
   - нет ответа до 1.1.1.1 → смена пути
   - Telegram недоступен → смена пути
   - YouTube+WhatsApp оба недоступны → смена пути
2. Плитка: подпись только «WARP», состояние в subtitle (colo · ms)
3. Jc/Jmin/Jmax и timeout из UI реально уходят в ядро (SetWGJunk / SetUpTimeoutMs)
4. Root: protectProcess (oom -1000, battery whitelist, appops) + boostTun

КАК ПРИМЕНИТЬ
Скопировать поверх Hydra-main с заменой. Пересобрать Go-ядро (AAR) И APK.
Без пересборки AAR новые прологи/gate/timeout в рантайме не появятся.

ВАЖНО (Xiaomi)
Дополнительно → разрешить работу в фоне + автозапуск.
С root и включённым «Использовать root» protectProcess сделает часть сам.
