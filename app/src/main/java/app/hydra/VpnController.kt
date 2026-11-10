package app.hydra

import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Состояние VPN для интерфейса: раз в секунду спрашивает у Go-ядра, как дела. */
class VpnController(private val ctx: Context, private val scope: CoroutineScope) {

    var state by mutableStateOf("off")
        private set
    var strategy by mutableStateOf("")
        private set
    var colo by mutableStateOf("")
        private set
    var rttMs by mutableStateOf(0)
        private set
    var message by mutableStateOf("")
        private set

    var rxBytes by mutableStateOf(0L)
        private set
    var txBytes by mutableStateOf(0L)
        private set

    val active: Boolean get() = state != "off"

    /** Применить изменённые настройки: если VPN включён — переподключить. */
    fun restartIfActive() {
        if (!active) return
        scope.launch {
            stop()
            delay(1200)
            start()
        }
    }

    init {
        scope.launch {
            while (isActive) {
                refresh()
                delay(1000)
            }
        }
    }

    private suspend fun refresh() {
        val raw = withContext(Dispatchers.IO) {
            try {
                mobile.Mobile.engineStatus()
            } catch (t: Throwable) {
                "off||||"
            }
        }
        val p = raw.split("|")
        state = p.getOrElse(0) { "off" }
        strategy = p.getOrElse(1) { "" }
        colo = p.getOrElse(2) { "" }
        rttMs = p.getOrElse(3) { "0" }.toIntOrNull() ?: 0
        message = p.getOrElse(4) { "" }
        rxBytes = p.getOrElse(5) { "0" }.toLongOrNull() ?: 0L
        txBytes = p.getOrElse(6) { "0" }.toLongOrNull() ?: 0L
    }

    fun start() {
        Prefs(ctx).wantConnected = true
        ContextCompat.startForegroundService(
            ctx, Intent(ctx, HydraVpnService::class.java).setAction(HydraVpnService.ACTION_START)
        )
    }

    fun stop() {
        Prefs(ctx).wantConnected = false
        ctx.startService(Intent(ctx, HydraVpnService::class.java).setAction(HydraVpnService.ACTION_STOP))
    }
}

/** "wg/162.159.192.3:2408/q3" -> "WireGuard", "h3/..." -> "MASQUE·H3". */
fun routeLabel(strategy: String): String = when (strategy.substringBefore("/")) {
    "wg" -> "WireGuard"
    "h2" -> "MASQUE·H2"
    "h3" -> "MASQUE·H3"
    else -> "—"
}

fun protoRes(strategy: String): Int = when (strategy.substringBefore("/")) {
    "wg" -> R.string.proto_wg
    "h2" -> R.string.proto_masque2
    "h3" -> R.string.proto_masque
    else -> R.string.proto_unknown
}
