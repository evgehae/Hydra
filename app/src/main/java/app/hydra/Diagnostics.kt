package app.hydra

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.URL

/** Простая проверка сети: DNS и HTTPS до Cloudflare (+ покажет, идёт ли трафик через WARP). */
suspend fun runDiagnostics(): String = withContext(Dispatchers.IO) {
    val sb = StringBuilder()

    var t = System.currentTimeMillis()
    try {
        val ip = InetAddress.getByName("cloudflare.com").hostAddress
        sb.append("DNS: OK ($ip, ${System.currentTimeMillis() - t} ms)\n")
    } catch (e: Exception) {
        sb.append("DNS: FAIL (${e.javaClass.simpleName})\n")
    }

    t = System.currentTimeMillis()
    try {
        val c = URL("https://cloudflare.com/cdn-cgi/trace").openConnection() as HttpURLConnection
        c.connectTimeout = 5000
        c.readTimeout = 5000
        val body = c.inputStream.bufferedReader().use { it.readText() }
        c.disconnect()
        val kv = body.lines()
            .mapNotNull { l -> l.split("=", limit = 2).takeIf { it.size == 2 }?.let { it[0] to it[1] } }
            .toMap()
        sb.append("HTTPS: OK (${System.currentTimeMillis() - t} ms)\n")
        sb.append("IP: ${kv["ip"]}\n")
        sb.append("Loc: ${kv["loc"]}\n")
        sb.append("Colo: ${kv["colo"]}\n")
        sb.append("WARP: ${kv["warp"]}\n")
    } catch (e: Exception) {
        sb.append("HTTPS: FAIL (${e.javaClass.simpleName})\n")
    }

    sb.toString()
}
