package app.hydra

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.net.ConnectivityManager
import android.net.Network
import android.os.ParcelFileDescriptor
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import android.telephony.TelephonyManager
import android.util.Log

/**
 * Системный VPN-сервис: создаёт TUN-интерфейс и отдаёт его Go-ядру, которое
 * гонит пакеты через туннель WARP. Раздельное туннелирование — средствами Android:
 * в списке приложений либо «только эти», либо «все, кроме этих».
 * Само приложение всегда исключено из VPN, иначе его собственное QUIC-соединение
 * с Cloudflare пошло бы внутрь туннеля.
 * Сеть (Wi-Fi/мобильная) отслеживается через системные уведомления: при смене
 * ядро узнаёт об этом сразу и переподключается.
 */
class HydraVpnService : VpnService() {

    companion object {
        const val ACTION_START = "app.hydra.action.START"
        const val ACTION_STOP = "app.hydra.action.STOP"
        private const val TAG = "Hydra"
        private const val CHANNEL = "hydra_status"
        private const val NOTIF_ID = 1
    }

    private val handler = Handler(Looper.getMainLooper())
    private var netCallback: ConnectivityManager.NetworkCallback? = null
    private var cellCallback: ConnectivityManager.NetworkCallback? = null
    private var forceCell = false

    /** TUN живёт в службе: при перезапуске ядра интерфейс не пропадает, и трафик не уходит мимо VPN. */
    private var tunPfd: ParcelFileDescriptor? = null
    private var restartFails = 0
    private var nextRestartAt = 0L
    private var lastNotifiedStrategy = ""

    private fun closeTun() {
        try { tunPfd?.close() } catch (t: Throwable) { }
        tunPfd = null
    }

    private fun jlog(s: String) { try { mobile.Mobile.logLine(s) } catch (t: Throwable) { } }

    private fun describeNet(n: Network): String = try {
        val c = cm().getNetworkCapabilities(n)
        val t = when {
            c == null -> "?"
            c.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi"
            c.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "сотовая"
            c.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "Ethernet"
            else -> "другая"
        }
        t + (if (c?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true) ", проверена" else ", не проверена")
    } catch (t: Throwable) { "?" }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        jlog("служба: команда " + (intent?.action ?: "перезапуск системой / запуск"))
        goForeground(getString(R.string.notif_connecting))
        val prefs = Prefs(this)
        if (intent?.action == ACTION_STOP) {
            stopVpn()
            return START_NOT_STICKY
        }
        // перезапуск системой (intent == null) — только если пользователь хотел VPN
        if (intent == null && !(prefs.wantConnected || prefs.autoStart)) {
            stopVpn()
            return START_NOT_STICKY
        }
        startVpn()
        return START_STICKY
    }

    private fun buildNotification(text: String): Notification {
        val openPi = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val stopPi = PendingIntent.getService(
            this, 1,
            Intent(this, HydraVpnService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val big = Notification.BigTextStyle()
            .setBigContentTitle(getString(R.string.app_name))
            .bigText(text)
        val b = Notification.Builder(this, CHANNEL)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(text)
            .setStyle(big)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(openPi)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, getString(R.string.notif_disconnect), stopPi)
            .addAction(android.R.drawable.ic_menu_view, getString(R.string.notif_open), openPi)
        if (Build.VERSION.SDK_INT >= 31) {
            b.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return b.build()
    }

    /** Постоянное уведомление держит сервис на переднем плане: система его не убивает. */
    private fun goForeground(text: String) {
        try {
            val nm = getSystemService(NotificationManager::class.java)
            val ch = NotificationChannel(
                CHANNEL,
                getString(R.string.app_name),
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Статус VPN · WARP CLAUDE"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            nm.createNotificationChannel(ch)
            val n = buildNotification(text)
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(NOTIF_ID, n)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "передний план: " + t.message)
        }
    }

    /** Раз в 3 секунды: обновляет уведомление и, если ядро остановилось, а VPN нужен, поднимает заново. */
    private val statusUpdater = object : Runnable {
        override fun run() {
            try {
                val raw = mobile.Mobile.engineStatus()
                val p = raw.split("|")
                val prefsNow = Prefs(this@HydraVpnService)
                val state = p.getOrElse(0) { "off" }
                val strategy = p.getOrElse(1) { "" }
                val colo = p.getOrElse(2) { "" }
                val rtt = p.getOrElse(3) { "0" }.toIntOrNull() ?: 0
                val text = when (state) {
                    "up" -> {
                        val base = getString(R.string.notif_up, colo.ifEmpty { strategy }, rtt)
                        if (strategy.isNotEmpty() && colo.isNotEmpty())
                            "$base\n$strategy"
                        else base
                    }
                    "reconnecting" -> getString(R.string.notif_reconnecting)
                    "failed" -> getString(R.string.notif_failed)
                    else -> getString(R.string.notif_connecting)
                }
                getSystemService(NotificationManager::class.java).notify(NOTIF_ID, buildNotification(text))
                // Обновляем состояние для плитки в шторке
                prefsNow.lastVpnState = when {
                    raw.startsWith("up") -> "up"
                    state == "reconnecting" || state == "failed" -> state
                    prefsNow.wantConnected -> "connecting"
                    else -> "down"
                }
                prefsNow.lastColo = colo
                prefsNow.lastPingMs = rtt
                try { HydraTileService.requestUpdate(this@HydraVpnService) } catch (_: Throwable) { }
                if (raw.startsWith("up")) {
                    restartFails = 0
                    maybeServiceCheck(prefsNow)
                    if (prefsNow.notifyStrategy && strategy.isNotEmpty() && strategy != lastNotifiedStrategy) {
                        if (lastNotifiedStrategy.isNotEmpty()) {
                            notifyEvent(
                                getString(R.string.app_name),
                                getString(R.string.notif_strategy_changed, strategy, colo)
                            )
                        }
                        lastNotifiedStrategy = strategy
                    }
                } else if (state == "reconnecting" || state == "failed") {
                    if (prefsNow.notifyErrors) {
                        notifyEvent(getString(R.string.app_name), text)
                    }
                }
                // Wi-Fi ведёт в запрещённый дата-центр: туннель автоматически идёт через мобильную сеть
                if (p.getOrElse(4) { "" }.startsWith("⛔") && prefsNow.channel == "auto" && !forceCell) {
                    val wp = curWifiPrint()
                    if (wp.isNotEmpty() && hasCellNet()) {
                        enableAutoCell(wp)
                        return
                    }
                }
                val now = System.currentTimeMillis()
                if (raw.startsWith("off") && Prefs(this@HydraVpnService).wantConnected && now >= nextRestartAt) {
                    restartFails++
                    nextRestartAt = now + minOf(60_000L, 3_000L shl minOf(restartFails, 5))
                    jlog("служба: ядро остановлено — поднимаю заново (попытка $restartFails)")
                    startVpn()
                }
            } catch (t: Throwable) {
            }
            handler.postDelayed(this, 3000)
        }
    }

    private fun cm() = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager

    /** Отпечаток текущего Wi-Fi или "" (если Wi-Fi нет). */
    private fun curWifiPrint(): String = try {
        var r = ""
        for (n in cm().allNetworks) {
            val c = cm().getNetworkCapabilities(n) ?: continue
            if (c.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
            if (c.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) r = wifiPrint(n)
        }
        r
    } catch (t: Throwable) { "" }

    private fun hasCellNet(): Boolean = try {
        cm().allNetworks.any {
            val c = cm().getNetworkCapabilities(it)
            c != null && !c.hasTransport(NetworkCapabilities.TRANSPORT_VPN) && c.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)
        }
    } catch (t: Throwable) { false }

    private fun enableAutoCell(wp: String) {
        Prefs(this).addCellWifi(wp)
        jlog("📡 Этот Wi-Fi ведёт в запрещённый дата-центр: туннель переключается на мобильную сеть (на 12 часов для этого Wi-Fi)")
        handler.removeCallbacks(statusUpdater)
        try { mobile.Mobile.stopTunnel() } catch (t: Throwable) { }
        closeTun()
        handler.postDelayed({ startVpn() }, 1200)
    }

    private fun startVpn() {
        val running = try { !mobile.Mobile.engineStatus().startsWith("off") } catch (t: Throwable) { false }
        if (running) return

        handler.removeCallbacks(statusUpdater)
        handler.postDelayed(statusUpdater, 3000)
        val prefs = Prefs(this)
        prefs.migrate()
        forceCell = prefs.channel == "cell" || (prefs.channel == "auto" && prefs.cellWifiActive(curWifiPrint()))
        try {
            mobile.Mobile.setColoPolicy(prefs.blockedColos, prefs.allowColos)
            mobile.Mobile.setFallback(prefs.fallbackAny)
            mobile.Mobile.setProtocol(prefs.protocol)
            mobile.Mobile.setCustomSNI(prefs.customSni)
            val par = when {
                prefs.tvProfile || prefs.stabilityMode -> 2L
                prefs.parallel -> 3L
                else -> 1L
            }
            mobile.Mobile.setParallel(par)
            mobile.Mobile.setIPv6(prefs.ipv6)
            mobile.Mobile.setServiceGate(prefs.tgGate)
            try { mobile.Mobile.setWGJunk(prefs.wgJc.toLong(), prefs.wgJmin.toLong(), prefs.wgJmax.toLong()) } catch (t: Throwable) { }
            try { mobile.Mobile.setUpTimeoutMs(prefs.handshakeTimeoutMs.toLong()) } catch (t: Throwable) { }
            try { mobile.Mobile.setStabilityMode(prefs.stabilityMode || prefs.tvProfile) } catch (t: Throwable) { }
            try { mobile.Mobile.setTVProfile(prefs.tvProfile) } catch (t: Throwable) { }
            jlog("настройки: протокол=${prefs.protocol}, канал=${prefs.channel}, параллельно=$par, root=${prefs.useRoot}, stability=${prefs.stabilityMode}, tv=${prefs.tvProfile}")
            mobile.Mobile.setCustomEndpoint(prefs.customEndpoint)
            mobile.Mobile.setDNS(systemDns(this))
            mobile.Mobile.setNetKey(currentNetKey())
        } catch (t: Throwable) {
            Log.e(TAG, "настройки ядра: " + t.message)
        }

        if (forceCell) {
            // «Мобильная сеть»: привязываем процесс к мобильной сети — сокеты Гидры
            // (она сама исключена из VPN) пойдут через неё, даже если подключён Wi-Fi.
            val req = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()
            var started = false
            val cb = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    handler.post {
                        if (started) return@post
                        started = true
                        try { cm().bindProcessToNetwork(network) } catch (t: Throwable) { }
                        establishAndRun()
                    }
                }
            }
            cellCallback = cb
            try {
                cm().requestNetwork(req, cb)
            } catch (t: Throwable) {
                Log.e(TAG, "мобильная сеть: " + t.message)
                stopSelf()
                return
            }
            handler.postDelayed({
                if (!started) {
                    Log.e(TAG, "мобильная сеть недоступна")
                    stopVpn()
                }
            }, 10000)
        } else {
            establishAndRun()
        }
    }

    private fun establishAndRun() {
        val dir = filesDir.absolutePath
        val prefs = Prefs(this)

        val v4 = try { mobile.Mobile.accountAddr4(dir) } catch (t: Throwable) { "" }
        val v6 = try { mobile.Mobile.accountAddr6(dir) } catch (t: Throwable) { "" }
        if (v4.isEmpty()) {
            // аккаунта ещё нет (приложение само пробует зарегистрироваться): ждём и повторяем, VPN не бросаем
            jlog("служба: нет аккаунта WARP — повторю позже")
            return
        }

        val b = Builder()
            .setSession("WARP CLAUDE")
            .setMtu(1280)
            .addAddress(v4, 32)
            .addRoute("0.0.0.0", 0)

        // свой DNS (внутри туннеля) или по умолчанию Cloudflare
        var dnsAdded = 0
        if (prefs.customDnsOn) {
            for (raw in prefs.customDns.split(',', ';', ' ', '\n').map { it.trim() }.filter { it.isNotEmpty() }) {
                // принимаем IP, имя хоста, tls://host и https://host/path: имя превращаем в IP-адреса
                val host = raw.substringAfter("://").substringBefore("/").substringBefore(":")
                val ips = if (host.matches(Regex("[0-9a-fA-F:.]+"))) listOf(raw.substringAfter("://").substringBefore("/"))
                          else resolveHost(host)
                for (d in ips.take(2)) {
                    try { b.addDnsServer(d); dnsAdded++ } catch (e: Exception) { }
                }
            }
        }
        if (dnsAdded == 0) {
            b.addDnsServer("1.1.1.1")
            b.addDnsServer("1.0.0.1")
        }

        // подсети, которые идут напрямую, мимо VPN (Android 13+)
        if (Build.VERSION.SDK_INT >= 33) {
            for (r in prefs.excludedRoutes.split(',', ';', ' ', '\n').map { it.trim() }.filter { it.isNotEmpty() }) {
                try {
                    val parts = r.split("/")
                    if (!parts[0].matches(Regex("[0-9a-fA-F:.]+"))) continue
                    val len = parts.getOrNull(1)?.toIntOrNull() ?: if (parts[0].contains(":")) 128 else 32
                    b.excludeRoute(android.net.IpPrefix(java.net.InetAddress.getByName(parts[0]), len))
                } catch (e: Exception) { }
            }
        }
        if (v6.isNotEmpty() && prefs.ipv6) {
            b.addAddress(v6, 128)
            b.addRoute("::", 0)
            b.addDnsServer("2606:4700:4700::1111")
        } else {
            // IPv6 в аккаунте нет: всё равно забираем ::/0 в TUN, ядро его отбросит —
            // иначе IPv6-трафик пошёл бы мимо VPN
            b.addAddress("fd00:7a7a::2", 128)
            b.addRoute("::", 0)
        }

        val apps = prefs.splitApps
        if (prefs.splitOnlySelected) {
            var any = false
            for (p in apps) {
                try {
                    b.addAllowedApplication(p)
                    any = true
                } catch (e: Exception) {
                }
            }
            if (!any) {
                stopVpn()
                return
            }
        } else {
            for (p in apps) {
                try {
                    b.addDisallowedApplication(p)
                } catch (e: Exception) {
                }
            }
            try {
                b.addDisallowedApplication(packageName)
            } catch (e: Exception) {
            }
        }

        val pfd = tunPfd ?: (try { b.establish() } catch (e: Exception) { null })
        if (pfd == null) {
            Log.e(TAG, "не удалось создать TUN")
            jlog("служба: не удалось создать TUN (нет разрешения VPN?) — остановка")
            stopVpn()
            return
        }
        tunPfd = pfd
        // ядру отдаём копию дескриптора: когда оно закроет её, сам интерфейс остаётся у службы
        val coreFd = try { ParcelFileDescriptor.dup(pfd.fileDescriptor) } catch (e: Exception) { null }
        if (coreFd == null) {
            jlog("служба: не удалось продублировать TUN — пересоздаю")
            closeTun()
            return
        }
        val err = try {
            mobile.Mobile.startTunnel(dir, coreFd.detachFd().toLong())
        } catch (t: Throwable) {
            t.message ?: "ошибка ядра"
        }
        if (err.isNotEmpty()) {
            Log.e(TAG, err)
            jlog("служба: ядро не запустилось: $err — повторю")
            return
        }
        // Root: kill-switch + защита от убийства процесса + boost tun.
        if (prefs.useRoot && RootHelper.hasRoot()) {
            val ok = RootHelper.enableKillSwitch("tun0")
            jlog("root kill-switch: " + if (ok) "включён (" + RootHelper.firewallBackend() + ")" else "не удалось")
            jlog("root protect: " + RootHelper.protectProcess(packageName))
            RootHelper.boostTun("tun0")
        }
        watchNetwork()
        lastServiceCheckAt = 0L // сразу проверить сервисы, не ждать 30 с
        serviceFailStreak = 0
        handler.removeCallbacks(statusUpdater)
        handler.postDelayed(statusUpdater, 2000)
    }

    /** Имя хоста в IP-адреса (в отдельном потоке с таймаутом: на главном потоке сеть запрещена). */
    private fun resolveHost(host: String): List<String> {
        var res: List<String> = emptyList()
        val t = Thread {
            res = try {
                java.net.InetAddress.getAllByName(host).mapNotNull { it.hostAddress }.filter { !it.contains("%") }
            } catch (e: Exception) { emptyList() }
        }
        t.start()
        t.join(4000)
        return res
    }

    /** Оператор сотовой сети (MCC+MNC, без разрешений): у разных операторов разный DPI. */
    private fun cellOperator(): String = try {
        (getSystemService(TELEPHONY_SERVICE) as TelephonyManager).networkOperator.orEmpty()
    } catch (t: Throwable) { "" }

    /** Отпечаток Wi-Fi: шлюз + DNS (SSID без разрешения на геолокацию недоступен). */
    private fun wifiPrint(n: Network): String = try {
        val lp = cm().getLinkProperties(n)
        val gw = lp?.routes?.firstOrNull { it.isDefaultRoute }?.gateway?.hostAddress.orEmpty()
        val dns = lp?.dnsServers?.joinToString(",") { it.hostAddress.orEmpty() }.orEmpty()
        Integer.toHexString((gw + "|" + dns).hashCode())
    } catch (t: Throwable) { "" }

    /**
     * Ключ сети для памяти стратегий: "wifi:<отпечаток>", "cell:<MCC+MNC>" или "default".
     * Сам VPN не считается. При принудительном канале — всегда сотовая.
     */
    private fun currentNetKey(): String {
        val op = cellOperator()
        if (forceCell) return "cell:$op"
        return try {
            var wifi: String? = null
            var cell = false
            for (n in cm().allNetworks) {
                val c = cm().getNetworkCapabilities(n) ?: continue
                if (c.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
                if (c.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) wifi = wifiPrint(n)
                if (c.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) cell = true
            }
            when {
                wifi != null -> "wifi:$wifi"
                cell -> "cell:$op"
                else -> "default"
            }
        } catch (t: Throwable) {
            "default"
        }
    }

    /** Системные уведомления о сетях: смена Wi-Fi ↔ мобильная доходит до ядра сразу. */
    private fun watchNetwork() {
        if (netCallback != null) return
        val req = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        val cb = object : ConnectivityManager.NetworkCallback() {
            private fun push() {
                handler.postDelayed({
                    try { mobile.Mobile.setNetKey(currentNetKey()) } catch (t: Throwable) { }
                }, 300)
            }
            override fun onAvailable(network: Network) { jlog("📶 сеть появилась: " + describeNet(network)); push() }
            override fun onLost(network: Network) { jlog("📶 сеть пропала"); push() }
        }
        netCallback = cb
        try {
            cm().registerNetworkCallback(req, cb)
        } catch (t: Throwable) {
            Log.e(TAG, "слежение за сетью: " + t.message)
        }
    }



    private var lastServiceCheckAt = 0L
    private var serviceFailStreak = 0
    private var lastForceRestartAt = 0L

    /** Проверка сервисов чаще (30 с). Если DNS/YouTube/Google мертвы при state=up — переподключаемся. */
    private fun maybeServiceCheck(prefs: Prefs) {
        val now = System.currentTimeMillis()
        // не реже 30 с, даже если в настройках 0/3 мин
        val intervalMs = maxOf(30_000L, prefs.serviceCheckEveryMin.coerceAtLeast(0) * 60_000L / 2)
        if (now - lastServiceCheckAt < intervalMs) return
        lastServiceCheckAt = now
        Thread {
            try {
                val res = mobile.Mobile.serviceCheck()
                if (res.isNotBlank()) jlog("ServiceCheck:\n" + res.take(800))
                val deadDns = res.contains("DNS через туннель не ответил") ||
                    res.contains("DNS through the tunnel")
                val deadYt = res.contains("✘ YouTube") || res.contains("✗ YouTube")
                val deadBase = res.contains("✘ Google") || res.contains("✘ Cloudflare") ||
                    res.contains("нет SYN-ACK")
                val available = Regex("""Доступно\s+(\d+)\s+из\s+(\d+)""").find(res)
                    ?: Regex("""Available\s+(\d+)\s+of\s+(\d+)""").find(res)
                val okCount = available?.groupValues?.getOrNull(1)?.toIntOrNull()
                val total = available?.groupValues?.getOrNull(2)?.toIntOrNull()
                val mostlyDead = okCount != null && total != null && total >= 6 && okCount <= 4

                // YouTube DNS fail или массовый падёж — сразу переподключаемся (не ждём 2 раза).
                val critical = deadDns || deadYt || mostlyDead
                if (critical) {
                    serviceFailStreak++
                    jlog("служба: туннель «up», но сервисы мертвы (streak=$serviceFailStreak) — DNS/YouTube/base")
                    if (now - lastForceRestartAt > 20_000L) {
                        lastForceRestartAt = now
                        serviceFailStreak = 0
                        jlog("служба: принудительное переподключение из-за мёртвых сервисов")
                        handler.post {
                            try {
                                mobile.Mobile.stopTunnel()
                            } catch (_: Throwable) { }
                            handler.postDelayed({ startVpn() }, 600)
                        }
                    }
                } else {
                    serviceFailStreak = 0
                }
            } catch (t: Throwable) {
                jlog("ServiceCheck error: " + (t.message ?: "?"))
            }
        }.start()
    }

    private fun notifyEvent(title: String, body: String) {
        try {
            val nm = getSystemService(NotificationManager::class.java)
            val chId = "hydra_events"
            nm.createNotificationChannel(
                NotificationChannel(chId, "WARP CLAUDE · события", NotificationManager.IMPORTANCE_DEFAULT)
            )
            val openPi = PendingIntent.getActivity(
                this, 2,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val n = Notification.Builder(this, chId)
                .setContentTitle(title)
                .setContentText(body)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentIntent(openPi)
                .setAutoCancel(true)
                .build()
            nm.notify((System.currentTimeMillis() % 100000).toInt() + 2000, n)
        } catch (t: Throwable) { }
    }

    private fun stopVpn() {
        jlog("служба: остановка")
        Prefs(this).wantConnected = false
        try {
            if (Prefs(this).useRoot) RootHelper.disableKillSwitch()
        } catch (t: Throwable) { }
        try { stopForeground(STOP_FOREGROUND_REMOVE) } catch (t: Throwable) { }
        try { netCallback?.let { cm().unregisterNetworkCallback(it) } } catch (t: Throwable) { }
        netCallback = null
        try { cellCallback?.let { cm().unregisterNetworkCallback(it) } } catch (t: Throwable) { }
        cellCallback = null
        try { cm().bindProcessToNetwork(null) } catch (t: Throwable) { }
        handler.removeCallbacksAndMessages(null)
        try { mobile.Mobile.stopTunnel() } catch (t: Throwable) { }
        closeTun()
        stopSelf()
    }

    override fun onRevoke() {
        jlog("система отозвала VPN (включён другой VPN или VPN выключен в настройках)")
        stopVpn()
        super.onRevoke()
    }

    override fun onDestroy() {
        jlog("служба: уничтожена")
        handler.removeCallbacksAndMessages(null)
        try { netCallback?.let { cm().unregisterNetworkCallback(it) } } catch (t: Throwable) { }
        try { cellCallback?.let { cm().unregisterNetworkCallback(it) } } catch (t: Throwable) { }
        try { cm().bindProcessToNetwork(null) } catch (t: Throwable) { }
        try { mobile.Mobile.stopTunnel() } catch (t: Throwable) { }
        closeTun()
        super.onDestroy()
    }
}
