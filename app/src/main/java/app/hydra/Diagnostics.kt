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
