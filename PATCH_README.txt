Патч Hydra — самолечение / прологи / плитка / jmin-jmax

Как применить
=============
1. Распакуй этот архив.
2. Скопируй содержимое поверх своей папки Hydra-main (с заменой файлов).

Структура (все пути относительно корня Hydra-main):

  wg.go
  colo.go
  engine.go
  learn.go
  app/src/main/AndroidManifest.xml
  app/src/main/java/app/hydra/HydraTileService.kt   ← НОВЫЙ файл
  app/src/main/java/app/hydra/Prefs.kt
  app/src/main/java/app/hydra/AdvancedScreens.kt
  app/src/main/java/app/hydra/HydraVpnService.kt
  app/src/main/java/app/hydra/Diagnostics.kt
  app/src/main/res/values/strings.xml
  app/src/main/res/values-ru/strings.xml

Новый файл
----------
HydraTileService.kt — плитка в шторке. Его раньше не было, просто положи в папку.

После копирования
-----------------
Собери APK как обычно. После установки:
- добавь плитку WARP CLAUDE в шторку
- Дополнительно → Jc / Jmin / Jmax и таймаут рукопожатия
- подключи VPN и пришли новый отчёт
