package app.hydra

import android.app.ActivityManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import android.telephony.TelephonyManager
import androidx.core.app.NotificationManagerCompat
import java.util.Locale
import java.util.TimeZone

private fun safe(f: () -> String): String = try { f() } catch (t: Throwable) { "н/д" }

/** Всё, что в системе влияет на работу VPN: сети, батарея, режимы Android, DNS, оператор. */
fun systemReport(ctx: Context): String {
    val sb = StringBuilder()
    fun line(k: String, v: String) { sb.append(k).append(": ").append(v).append('\n') }

    line("приложение", safe { ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName ?: "?" })
    line("устройство", "${Build.MANUFACTURER} ${Build.MODEL} (${Build.DEVICE}), ${Build.HARDWARE}")
    line("система", "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT}), патч ${Build.VERSION.SECURITY_PATCH}, сборка ${Build.DISPLAY}")
    line("язык / часовой пояс", Locale.getDefault().toString() + " / " + TimeZone.getDefault().id)
    line("время на телефоне", java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss Z", Locale.US).format(java.util.Date()))
    line("телефон включён", (SystemClock.elapsedRealtime() / 60000).toString() + " мин")

    // питание и фон: частая причина того, что систему «убивает» VPN
    line("экономия батареи Android", safe { (ctx.getSystemService(Context.POWER_SERVICE) as PowerManager).isPowerSaveMode.toString() })
    line("режим Doze", safe { (ctx.getSystemService(Context.POWER_SERVICE) as PowerManager).isDeviceIdleMode.toString() })
    line("вне оптимизации батареи", safe { (ctx.getSystemService(Context.POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(ctx.packageName).toString() })
    line("фон ограничен системой", safe { (ctx.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).isBackgroundRestricted.toString() })
    line("группа ожидания (10 активно … 45 ограничено)", safe { (ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager).appStandbyBucket.toString() })
    line("уведомления разрешены", safe { NotificationManagerCompat.from(ctx).areNotificationsEnabled().toString() })
    val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    line("экономия трафика (1 выкл, 2 исключение, 3 вкл)", safe { cm.restrictBackgroundStatus.toString() })
    line("постоянный VPN (приложение)", safe { Settings.Secure.getString(ctx.contentResolver, "always_on_vpn_app") ?: "нет" })
    line("блокировка без VPN", safe { Settings.Secure.getInt(ctx.contentResolver, "always_on_vpn_lockdown", 0).toString() })
    line("частный DNS Android", safe {
        (Settings.Global.getString(ctx.contentResolver, "private_dns_mode") ?: "н/д") + " " +
            (Settings.Global.getString(ctx.contentResolver, "private_dns_specifier") ?: "")
    })
    line("режим «в самолёте»", safe { Settings.Global.getInt(ctx.contentResolver, Settings.Global.AIRPLANE_MODE_ON, 0).toString() })

    // оператор
    safe {
        val tm = ctx.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        line("оператор сети", "${tm.networkOperatorName} (${tm.networkOperator}), SIM ${tm.simOperator}, роуминг ${tm.isNetworkRoaming}")
        ""
    }

    // сети
    val active = safe { cm.activeNetwork.toString() }
    sb.append("\nсети (активная: ").append(active).append("):\n")
    try {
        for (n in cm.allNetworks) {
            val c = cm.getNetworkCapabilities(n)
            val lp = cm.getLinkProperties(n)
            val tr = listOf(
                NetworkCapabilities.TRANSPORT_WIFI to "Wi-Fi",
                NetworkCapabilities.TRANSPORT_CELLULAR to "сотовая",
                NetworkCapabilities.TRANSPORT_VPN to "VPN",
                NetworkCapabilities.TRANSPORT_ETHERNET to "Ethernet"
            ).filter { c?.hasTransport(it.first) == true }.joinToString("+") { it.second }
            val caps = listOf(
                NetworkCapabilities.NET_CAPABILITY_INTERNET to "интернет",
                NetworkCapabilities.NET_CAPABILITY_VALIDATED to "проверена",
                NetworkCapabilities.NET_CAPABILITY_NOT_METERED to "безлимит",
                NetworkCapabilities.NET_CAPABILITY_NOT_VPN to "не VPN"
            ).filter { c?.hasCapability(it.first) == true }.joinToString(",") { it.second }
            sb.append(" - ").append(n.toString()).append(' ').append(tr.ifEmpty { "?" }).append(" [").append(caps).append("]")
            sb.append(" вниз ").append(c?.linkDownstreamBandwidthKbps ?: 0).append(" кбит/с")
            sb.append(" if=").append(lp?.interfaceName ?: "?")
            sb.append(" адреса=").append(lp?.linkAddresses?.joinToString(",") { it.address.hostAddress ?: "" } ?: "")
            sb.append(" шлюз=").append(lp?.routes?.firstOrNull { it.isDefaultRoute }?.gateway?.hostAddress ?: "")
            sb.append(" DNS=").append(lp?.dnsServers?.joinToString(",") { it.hostAddress ?: "" } ?: "")
            if (Build.VERSION.SDK_INT >= 29) sb.append(" MTU=").append(lp?.mtu ?: 0)
            if (lp?.isPrivateDnsActive == true) sb.append(" частный DNS=").append(lp?.privateDnsServerName ?: "авто")
            sb.append('\n')
        }
    } catch (t: Throwable) {
        sb.append("  не удалось прочитать: ").append(t.message).append('\n')
    }
    return sb.toString()
}
