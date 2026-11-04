package app.hydra

import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Handler
import android.os.Looper
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
    }

    private val handler = Handler(Looper.getMainLooper())
    private var netCallback: ConnectivityManager.NetworkCallback? = null
    private var cellCallback: ConnectivityManager.NetworkCallback? = null
    private var forceCell = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return if (intent?.action == ACTION_STOP) {
            stopVpn()
            START_NOT_STICKY
        } else {
            startVpn()
            START_STICKY
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
            .addDnsServer("1.1.1.1")
            .addDnsServer("1.0.0.1")
        if (v6.isNotEmpty()) {
            b.addAddress(v6, 128)
            b.addRoute("::", 0)
            b.addDnsServer("2606:4700:4700::1111")
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
    }

    /** Ключ сети: "cell" при принудительном канале, иначе "wifi"/"cell"/"default" (сам VPN не считается). */
    private fun currentNetKey(): String {
        if (forceCell) return "cell"
        return try {
            var wifi = false
            var cell = false
            for (n in cm().allNetworks) {
                val c = cm().getNetworkCapabilities(n) ?: continue
                if (c.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
                if (c.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) wifi = true
                if (c.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) cell = true
            }
            when {
                wifi -> "wifi"
                cell -> "cell"
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
            override fun onAvailable(network: Network) = push()
            override fun onLost(network: Network) = push()
        }
        netCallback = cb
        try {
            cm().registerNetworkCallback(req, cb)
        } catch (t: Throwable) {
            Log.e(TAG, "слежение за сетью: " + t.message)
        }
    }

    private fun stopVpn() {
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
        stopVpn()
        super.onRevoke()
    }

    override fun onDestroy() {
        try { netCallback?.let { cm().unregisterNetworkCallback(it) } } catch (t: Throwable) { }
        try { cellCallback?.let { cm().unregisterNetworkCallback(it) } } catch (t: Throwable) { }
        try { cm().bindProcessToNetwork(null) } catch (t: Throwable) { }
        try { mobile.Mobile.stopTunnel() } catch (t: Throwable) { }
        super.onDestroy()
    }
}
