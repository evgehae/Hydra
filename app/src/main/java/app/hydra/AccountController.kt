package app.hydra

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** DNS-серверы текущих сетей телефона: Go на Android сам их найти не может. */
fun systemDns(ctx: Context): String {
    return try {
        val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val nets = cm.allNetworks.toMutableList()
        cm.activeNetwork?.let { nets.add(0, it) }
        val list = mutableListOf<String>()
        for (n in nets) {
            cm.getLinkProperties(n)?.dnsServers?.forEach { a ->
                a.hostAddress?.let { list.add(it) }
            }
        }
        list.distinct().joinToString(",")
    } catch (t: Throwable) {
        ""
    }
}

/** Состояние аккаунта WARP, общее для экранов; регистрация идёт в Go-ядре. */
class AccountController(
    private val ctx: Context,
    private val dir: String,
    private val scope: CoroutineScope,
    private val dnsProvider: () -> String
) {

    var id by mutableStateOf(readId())
        private set
    var busy by mutableStateOf(false)
        private set
    var report by mutableStateOf("")
        private set

    private fun readId(): String =
        try { mobile.Mobile.accountID(dir) } catch (t: Throwable) { "" }

    /** "" если ошибки нет, иначе вид: rate_limited | blocked | dns | api | storage | internal. */
    val failKind: String
        get() = if (report.startsWith("FAIL")) {
            report.lineSequence().first().removePrefix("FAIL").trim()
        } else {
            ""
        }

    private fun runRegister(): String =
        try {
            mobile.Mobile.setDNS(dnsProvider())
            mobile.Mobile.registerReport(dir)
        } catch (t: Throwable) {
            "FAIL internal\n" + t.message
        }

    fun register() {
        if (busy) return
        busy = true
        report = ""
        scope.launch {
            report = withContext(Dispatchers.IO) { runRegister() }
            id = readId()
            busy = false
        }
    }

    /** Регистрация через мобильную сеть — если домашний Wi-Fi режет api.cloudflareclient.com. */
    fun registerViaCellular() {
        if (busy) return
        busy = true
        report = ""
        val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val req = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        var finished = false
        lateinit var cb: ConnectivityManager.NetworkCallback
        fun finish(text: String?) {
            if (finished) return
            finished = true
            try { cm.bindProcessToNetwork(null) } catch (t: Throwable) { }
            try { cm.unregisterNetworkCallback(cb) } catch (t: Throwable) { }
            if (text != null) report = text
            id = readId()
            busy = false
        }
        cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                if (finished) return
                try { cm.bindProcessToNetwork(network) } catch (t: Throwable) { }
                scope.launch {
                    val r = withContext(Dispatchers.IO) { runRegister() }
                    finish(r)
                }
            }
        }
        try {
            cm.requestNetwork(req, cb)
        } catch (t: Throwable) {
            finish("FAIL cellular\n" + t.message)
            return
        }
        scope.launch {
            delay(12000)
            if (!finished && report.isEmpty() && busy) finish("FAIL cellular\nмобильная сеть недоступна")
        }
    }

    fun export(): String =
        try { mobile.Mobile.exportAccount(dir) } catch (t: Throwable) { "" }

    /** Пустая строка — успех, иначе текст ошибки. */
    fun importFrom(text: String): String {
        val err = try {
            mobile.Mobile.importAccount(dir, text)
        } catch (t: Throwable) {
            t.message ?: "error"
        }
        id = readId()
        return err
    }
}
