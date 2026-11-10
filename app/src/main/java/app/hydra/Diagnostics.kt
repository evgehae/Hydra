package app.hydra

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.URL

data class DiagResult(
    val dnsOk: Boolean,
    val dnsMs: Long,
    val httpsOk: Boolean,
    val httpsMs: Long,
    val ip: String,
    val loc: String,
    val colo: String,
    val warp: String
)

/** DNS + HTTPS до Cloudflare; trace показывает дата-центр и идёт ли трафик через WARP. */
suspend fun runDiagnostics(): DiagResult = withContext(Dispatchers.IO) {
    var dnsOk = false
    var t = System.currentTimeMillis()
    try {
        InetAddress.getByName("cloudflare.com")
        dnsOk = true
    } catch (e: Exception) {
    }
    val dnsMs = System.currentTimeMillis() - t

    var httpsOk = false
    var kv: Map<String, String> = emptyMap()
    t = System.currentTimeMillis()
    try {
        val c = URL("https://cloudflare.com/cdn-cgi/trace").openConnection() as HttpURLConnection
        c.connectTimeout = 5000
        c.readTimeout = 5000
        val body = c.inputStream.bufferedReader().use { it.readText() }
        c.disconnect()
        kv = body.lines()
            .mapNotNull { l -> l.split("=", limit = 2).takeIf { it.size == 2 }?.let { it[0] to it[1] } }
            .toMap()
        httpsOk = true
    } catch (e: Exception) {
    }
    val httpsMs = System.currentTimeMillis() - t

    DiagResult(
        dnsOk, dnsMs, httpsOk, httpsMs,
        kv["ip"].orEmpty(), kv["loc"].orEmpty(),
        (kv["colo"] ?: "").uppercase(), kv["warp"].orEmpty()
    )
}

// ---------- Полная диагностика и отчёт ----------

data class DiagCheck(val name: String, val ok: Boolean, val detail: String)

private fun tcpCheck(host: String, port: Int): Pair<Boolean, String> {
    val t = System.currentTimeMillis()
    return try {
        java.net.Socket().use { s -> s.connect(java.net.InetSocketAddress(host, port), 4000) }
        true to ((System.currentTimeMillis() - t).toString() + " ms")
    } catch (e: Exception) {
        false to (e.message ?: e.javaClass.simpleName)
    }
}

/** Набор проверок «мимо VPN»: DNS, HTTPS, API регистрации, сервер MASQUE, IPv6, обычный сайт. */
suspend fun runFullDiagnostics(ctx: android.content.Context): List<DiagCheck> = withContext(Dispatchers.IO) {
    val out = mutableListOf<DiagCheck>()
    val base = runDiagnostics()
    out += DiagCheck(ctx.getString(R.string.chk_dns), base.dnsOk, if (base.dnsOk) "${base.dnsMs} ms" else ctx.getString(R.string.diag_fail))
    val httpsDetail = if (base.httpsOk) "${base.httpsMs} ms" + (if (base.colo.isNotEmpty()) " · ${base.colo}" else "") else ctx.getString(R.string.diag_fail)
    out += DiagCheck(ctx.getString(R.string.chk_https), base.httpsOk, httpsDetail)
    val api = tcpCheck("api.cloudflareclient.com", 443)
    out += DiagCheck(ctx.getString(R.string.chk_api), api.first, api.second)
    val ms = tcpCheck("162.159.198.2", 443)
    out += DiagCheck(ctx.getString(R.string.chk_masque), ms.first, ms.second)
    val v6 = tcpCheck("2606:4700:4700::1111", 443)
    out += DiagCheck(ctx.getString(R.string.chk_v6), v6.first, v6.second)
    val web = tcpCheck("www.google.com", 443)
    out += DiagCheck(ctx.getString(R.string.chk_web), web.first, web.second)
    out
}

/** Тип текущей сети (без самого VPN). */
fun networkType(ctx: android.content.Context): String = try {
    val cm = ctx.getSystemService(android.content.Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
    var wifi = false
    var cell = false
    for (n in cm.allNetworks) {
        val c = cm.getNetworkCapabilities(n) ?: continue
        if (c.hasTransport(android.net.NetworkCapabilities.TRANSPORT_VPN)) continue
        if (c.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI)) wifi = true
        if (c.hasTransport(android.net.NetworkCapabilities.TRANSPORT_CELLULAR)) cell = true
    }
    when {
        wifi -> ctx.getString(R.string.net_wifi)
        cell -> ctx.getString(R.string.net_cell)
        else -> "—"
    }
} catch (t: Throwable) {
    "—"
}

fun fmtBytes(n: Long): String {
    if (n < 1024) return "$n B"
    val u = arrayOf("KB", "MB", "GB", "TB")
    var v = n.toDouble()
    var i = -1
    while (v >= 1024 && i < u.size - 1) { v /= 1024; i++ }
    return String.format(java.util.Locale.US, "%.1f %s", v, u[i])
}

/** Строки журнала с ошибками и предупреждениями. */
fun journalErrors(): List<String> = try {
    mobile.Mobile.getJournal(0).lines().filter { it.contains("✘") || it.contains("⚠") || it.contains("⛔") || it.contains("ошибк", true) }
} catch (t: Throwable) { emptyList() }

/** Текст отчёта для разработчика: версия, устройство, состояние, проверки, журнал. Ключи и токены не включаются. */
fun buildReport(ctx: android.content.Context, prefs: Prefs, vpn: VpnController, account: AccountController, checks: List<DiagCheck>): String {
    val sb = StringBuilder()
    sb.append("Hydra report ").append(java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US).format(java.util.Date())).append('\n')
    sb.append("device: ").append(android.os.Build.MANUFACTURER).append(' ').append(android.os.Build.MODEL)
        .append(", Android ").append(android.os.Build.VERSION.RELEASE).append(" (API ").append(android.os.Build.VERSION.SDK_INT).append(")\n")
    sb.append("core: ").append(try { mobile.Mobile.version() } catch (t: Throwable) { "n/a" }).append('\n')
    sb.append("state: ").append(vpn.state).append(", strategy: ").append(vpn.strategy).append(", colo: ").append(vpn.colo)
        .append(", rtt: ").append(vpn.rttMs).append(" ms, rx/tx: ").append(fmtBytes(vpn.rxBytes)).append(" / ").append(fmtBytes(vpn.txBytes)).append('\n')
    if (vpn.message.isNotEmpty()) sb.append("message: ").append(vpn.message).append('\n')
    sb.append("network: ").append(networkType(ctx)).append('\n')
    sb.append("account: masque=").append(account.id.take(8)).append(" wg=").append(account.wgId.take(8)).append('\n')
    sb.append("settings: protocol=").append(prefs.protocol).append(", channel=").append(prefs.channel)
        .append(", blockedColos=").append(prefs.blockedColos).append(", allowColos=").append(prefs.allowColos)
        .append(", fallbackAny=").append(prefs.fallbackAny).append(", customSni=").append(prefs.customSni)
        .append(", customEndpoint=").append(prefs.customEndpoint).append(", customDns=").append(if (prefs.customDnsOn) prefs.customDns else "off").append('\n')
    if (checks.isNotEmpty()) {
        sb.append("\n--- checks ---\n")
        checks.forEach { sb.append(if (it.ok) "OK   " else "FAIL ").append(it.name).append(": ").append(it.detail).append('\n') }
    }
    sb.append("\n--- journal ---\n")
    sb.append(try { mobile.Mobile.getJournal(600) } catch (t: Throwable) { "" })
    return sb.toString()
}
