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
        val pi = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Builder(this, CHANNEL)
            .setContentTitle("Hydra")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
    }

    /** Постоянное уведомление держит сервис на переднем плане: система его не убивает. */
    private fun goForeground(text: String) {
        try {
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Hydra", NotificationManager.IMPORTANCE_LOW)
            )
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
                val text = when (p.getOrElse(0) { "off" }) {
                    "up" -> getString(R.string.notif_up, p.getOrElse(2) { "" }, p.getOrElse(3) { "0" }.toIntOrNull() ?: 0)
                    "reconnecting" -> getString(R.string.notif_reconnecting)
                    "failed" -> getString(R.string.notif_failed)
                    else -> getString(R.string.notif_connecting)
                }
                getSystemService(NotificationManager::class.java).notify(NOTIF_ID, buildNotification(text))
                if (raw.startsWith("off") && Prefs(this@HydraVpnService).wantConnected) {
                    Log.w(TAG, "ядро остановилось — поднимаю заново")
                    startVpn()
                }
            } catch (t: Throwable) {
            }
            handler.postDelayed(this, 3000)
        }
    }

    private fun cm() = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager

    private fun startVpn() {
        val running = try { !mobile.Mobile.engineStatus().startsWith("off") } catch (t: Throwable) { false }
        if (running) return

        val prefs = Prefs(this)
        forceCell = prefs.channel == "cell"
        try {
            mobile.Mobile.setColoPolicy(prefs.blockedColos, prefs.allowColos)
            mobile.Mobile.setFallback(prefs.fallbackAny)
            mobile.Mobile.setProtocol(prefs.protocol)
            mobile.Mobile.setCustomSNI(prefs.customSni)
            mobile.Mobile.setParallel(if (prefs.parallel) 3L else 1L)
            jlog("настройки: протокол=${prefs.protocol}, канал=${prefs.channel}, параллельно=${prefs.parallel}, свой DNS=${if (prefs.customDnsOn) prefs.customDns else "нет"}")
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
            Log.e(TAG, "нет аккаунта WARP")
            stopVpn()
            return
        }

        val b = Builder()
            .setSession("Hydra")
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
        if (v6.isNotEmpty()) {
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

        val pfd = try { b.establish() } catch (e: Exception) { null }
        if (pfd == null) {
            Log.e(TAG, "не удалось создать TUN")
            stopVpn()
            return
        }
        val err = try {
            mobile.Mobile.startTunnel(dir, pfd.detachFd().toLong())
        } catch (t: Throwable) {
            t.message ?: "ошибка ядра"
        }
        if (err.isNotEmpty()) {
            Log.e(TAG, err)
            stopVpn()
            return
        }
        watchNetwork()
        handler.removeCallbacks(statusUpdater)
        handler.postDelayed(statusUpdater, 3000)
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

    private fun stopVpn() {
        jlog("служба: остановка")
        Prefs(this).wantConnected = false
        try { stopForeground(STOP_FOREGROUND_REMOVE) } catch (t: Throwable) { }
        try { netCallback?.let { cm().unregisterNetworkCallback(it) } } catch (t: Throwable) { }
        netCallback = null
        try { cellCallback?.let { cm().unregisterNetworkCallback(it) } } catch (t: Throwable) { }
        cellCallback = null
        try { cm().bindProcessToNetwork(null) } catch (t: Throwable) { }
        handler.removeCallbacksAndMessages(null)
        try { mobile.Mobile.stopTunnel() } catch (t: Throwable) { }
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
        super.onDestroy()
    }
}
