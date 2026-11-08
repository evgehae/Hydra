package app.hydra

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.util.Log
import androidx.core.content.ContextCompat

/** После загрузки телефона (и после обновления приложения) сразу поднимает VPN. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val a = intent.action ?: return
        val ok = a == Intent.ACTION_BOOT_COMPLETED ||
            a == Intent.ACTION_MY_PACKAGE_REPLACED ||
            a == "android.intent.action.QUICKBOOT_POWERON" ||
            a == "com.htc.intent.action.QUICKBOOT_POWERON"
        if (!ok) return
        val prefs = Prefs(context)
        val replaced = a == Intent.ACTION_MY_PACKAGE_REPLACED
        if (!prefs.autoStart && !(replaced && prefs.wantConnected)) return
        if (VpnService.prepare(context) != null) {
            Log.w("Hydra", "автозапуск: нет разрешения на VPN — открой приложение один раз")
            return
        }
        prefs.wantConnected = true
        try {
            ContextCompat.startForegroundService(
                context,
                Intent(context, HydraVpnService::class.java).setAction(HydraVpnService.ACTION_START)
            )
        } catch (t: Throwable) {
            Log.e("Hydra", "автозапуск: " + t.message)
        }
    }
}
