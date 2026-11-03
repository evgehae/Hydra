package app.hydra

import android.content.Context
import android.content.Intent
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
class VpnController(private val ctx: Context, scope: CoroutineScope) {

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

    val active: Boolean get() = state != "off"

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
    }

    fun start() {
        ctx.startService(Intent(ctx, HydraVpnService::class.java).setAction(HydraVpnService.ACTION_START))
    }

    fun stop() {
        ctx.startService(Intent(ctx, HydraVpnService::class.java).setAction(HydraVpnService.ACTION_STOP))
    }
}

/** "h3/162.159.198.1/std" -> "H3 · std" */
fun routeLabel(strategy: String): String {
    val p = strategy.split("/")
    return if (p.size == 3) p[0].uppercase() + " · " + p[2] else "—"
}
