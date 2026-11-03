package app.hydra

import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
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
 */
class HydraVpnService : VpnService() {

    companion object {
        const val ACTION_START = "app.hydra.action.START"
        const val ACTION_STOP = "app.hydra.action.STOP"
        private const val TAG = "Hydra"
    }

    private val handler = Handler(Looper.getMainLooper())
    private val netWatcher = object : Runnable {
        override fun run() {
            try { mobile.Mobile.setNetKey(currentNetKey()) } catch (t: Throwable) { }
            handler.postDelayed(this, 3000)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return if (intent?.action == ACTION_STOP) {
            stopVpn()
            START_NOT_STICKY
        } else {
            startVpn()
            START_STICKY
        }
    }

    private fun startVpn() {
        val dir = filesDir.absolutePath
        val prefs = Prefs(this)

        val running = try { !mobile.Mobile.engineStatus().startsWith("off") } catch (t: Throwable) { false }
        if (running) return

        val v4 = try { mobile.Mobile.accountAddr4(dir) } catch (t: Throwable) { "" }
        val v6 = try { mobile.Mobile.accountAddr6(dir) } catch (t: Throwable) { "" }
        if (v4.isEmpty()) {
            Log.e(TAG, "нет аккаунта WARP")
            stopSelf()
            return
        }

        try {
            mobile.Mobile.setColoPolicy(prefs.blockedColos, prefs.allowColos)
            mobile.Mobile.setNetKey(currentNetKey())
        } catch (t: Throwable) {
            Log.e(TAG, "настройки ядра: " + t.message)
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
                stopSelf()
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
            stopSelf()
            return
        }
        val err = try {
            mobile.Mobile.startTunnel(dir, pfd.detachFd().toLong())
        } catch (t: Throwable) {
            t.message ?: "ошибка ядра"
        }
        if (err.isNotEmpty()) {
            Log.e(TAG, err)
            stopSelf()
            return
        }
        handler.removeCallbacks(netWatcher)
        handler.postDelayed(netWatcher, 3000)
    }

    /** Ключ сети для памяти стратегий: "wifi", "cell" или "default" (сам VPN не считается). */
    private fun currentNetKey(): String {
        return try {
            val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
            var wifi = false
            var cell = false
            for (n in cm.allNetworks) {
                val c = cm.getNetworkCapabilities(n) ?: continue
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

    private fun stopVpn() {
        handler.removeCallbacks(netWatcher)
        try { mobile.Mobile.stopTunnel() } catch (t: Throwable) { }
        stopSelf()
    }

    override fun onRevoke() {
        stopVpn()
        super.onRevoke()
    }

    override fun onDestroy() {
        handler.removeCallbacks(netWatcher)
        try { mobile.Mobile.stopTunnel() } catch (t: Throwable) { }
        super.onDestroy()
    }
}
