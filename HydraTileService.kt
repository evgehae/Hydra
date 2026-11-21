package app.hydra

import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi

/**
 * Плитка в шторке быстрых настроек.
 * Одно нажатие — вкл/выкл VPN. Состояние: Connected / Connecting / Offline.
 */
@RequiresApi(Build.VERSION_CODES.N)
class HydraTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        refresh()
    }

    override fun onClick() {
        super.onClick()
        val prefs = Prefs(this)
        val want = !prefs.wantConnected
        prefs.wantConnected = want
        val intent = Intent(this, HydraVpnService::class.java).apply {
            action = if (want) HydraVpnService.ACTION_START else HydraVpnService.ACTION_STOP
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        // мгновенная визуальная обратная связь
        qsTile?.let { tile ->
            tile.state = if (want) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            tile.label = if (want) getString(R.string.tile_connecting) else getString(R.string.tile_off)
            tile.updateTile()
        }
    }

    private fun refresh() {
        val tile = qsTile ?: return
        val prefs = Prefs(this)
        val st = try {
            // лёгкий статус из shared prefs / последнего события
            prefs.lastVpnState
        } catch (_: Throwable) {
            if (prefs.wantConnected) "connecting" else "down"
        }
        // Крупная подпись на плитке (на Xiaomi subtitle почти не читается).
        when {
            st == "up" || st == "connected" -> {
                tile.state = Tile.STATE_ACTIVE
                val colo = prefs.lastColo
                val ping = prefs.lastPingMs
                tile.label = when {
                    colo.isNotEmpty() && ping > 0 -> "WARP $colo"
                    colo.isNotEmpty() -> "WARP $colo"
                    else -> "WARP ON"
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    tile.subtitle = if (ping > 0) "${ping} ms" else getString(R.string.tile_on)
                }
            }
            st == "connecting" || prefs.wantConnected -> {
                tile.state = Tile.STATE_ACTIVE
                tile.label = "WARP …"
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    tile.subtitle = getString(R.string.tile_connecting)
                }
            }
            else -> {
                tile.state = Tile.STATE_INACTIVE
                tile.label = "WARP"
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    tile.subtitle = getString(R.string.tile_off)
                }
            }
        }
        try {
            tile.icon = Icon.createWithResource(this, R.drawable.ic_warp_fg)
        } catch (_: Throwable) { }
        tile.updateTile()
    }

    companion object {
        /** Вызвать из VpnService при смене состояния, чтобы плитка обновилась. */
        fun requestUpdate(ctx: android.content.Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
            try {
                requestListeningState(
                    ctx,
                    android.content.ComponentName(ctx, HydraTileService::class.java)
                )
            } catch (_: Throwable) { }
        }
    }
}
