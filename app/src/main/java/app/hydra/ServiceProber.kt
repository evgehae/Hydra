package app.hydra

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import java.net.HttpURLConnection
import java.net.URL

/**
 * «Живая» проверка: настоящие HTTPS-запросы к YouTube и WhatsApp прямо через туннель и замер скорости.
 * В отличие от проверки по адресам (SYN-ACK) она видит и подмену DNS, и обрыв TLS, и медленный туннель.
 * Запросы идут через сеть VPN с её DNS, поэтому ответ DNS провайдера ни на что не влияет.
 * Результат уходит в ядро: оно запоминает его по сети и стратегии и при мёртвом сервисе меняет путь.
 *
 * Защита от ложных срабатываний: перед проверкой контрольный запрос к Cloudflare должен показать warp=on.
 * Если приложение не может ходить через свой туннель, проверка честно пишет «недоступна» и ничего не меняет.
 */
object ServiceProber {
    private class Target(val name: String, val url: String)

    private val targets = listOf(
        Target("YouTube", "https://www.youtube.com/generate_204"),
        Target("YouTube-видео", "https://redirector.googlevideo.com/generate_204"),
        Target("WhatsApp", "https://web.whatsapp.com/")
    )

    private const val UA = "Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 Chrome/124.0 Mobile Safari/537.36"
    private const val PERIOD_MS = 5 * 60_000L

    @Volatile private var running = false
    private var lastKey = ""
    private var lastAt = 0L

    /** Вызывать из цикла службы, пока туннель поднят. key = стратегия@дата-центр. */
    fun tick(ctx: Context, key: String) {
        val now = System.currentTimeMillis()
        if (running) return
        if (key == lastKey && now - lastAt < PERIOD_MS) return
        lastKey = key
        lastAt = now
        running = true
        val app = ctx.applicationContext
        Thread {
            try {
                Thread.sleep(7000) // дать туннелю прогреться
                if (mobile.Mobile.engineStatus().startsWith("up")) runProbe(app)
            } catch (t: Throwable) {
            } finally {
                running = false
            }
        }.start()
    }

    /** Туннель не поднят: следующая проверка пройдёт сразу после подключения. */
    fun reset() {
        lastKey = ""
    }

    private fun log(s: String) {
        try { mobile.Mobile.logLine(s) } catch (t: Throwable) { }
    }

    private fun vpnNetwork(ctx: Context): Network? {
        val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        for (n in cm.allNetworks) {
            val c = cm.getNetworkCapabilities(n) ?: continue
            if (c.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return n
        }
        return null
    }

    /** Контроль: запрос к Cloudflare через туннель должен вернуть warp=on. */
    private fun control(net: Network): Pair<Boolean, String> = try {
        val c = net.openConnection(URL("https://cloudflare.com/cdn-cgi/trace")) as HttpURLConnection
        c.connectTimeout = 6000
        c.readTimeout = 6000
        val body = c.inputStream.bufferedReader().use { it.readText() }
        c.disconnect()
        val warp = body.lines().firstOrNull { it.startsWith("warp=") }?.substringAfter("=") ?: "нет"
        Pair(warp == "on" || warp == "plus", "warp=$warp")
    } catch (e: Exception) {
        Pair(false, e.javaClass.simpleName + (e.message?.let { ": " + it.take(60) } ?: ""))
    }

    private class Res(val ok: Boolean, val ms: Long, val note: String)

    /** Любой ответ HTTP (даже 404) значит: имя нашлось, TLS прошёл, сервис отвечает. */
    private fun probe(net: Network, url: String): Res {
        val t = System.currentTimeMillis()
        return try {
            val c = net.openConnection(URL(url)) as HttpURLConnection
            c.connectTimeout = 5000
            c.readTimeout = 6000
            c.instanceFollowRedirects = false
            c.setRequestProperty("User-Agent", UA)
            val code = c.responseCode
            c.disconnect()
            Res(true, System.currentTimeMillis() - t, "HTTP $code")
        } catch (e: Exception) {
            Res(false, System.currentTimeMillis() - t, e.javaClass.simpleName + (e.message?.let { ": " + it.take(60) } ?: ""))
        }
    }

    /** Скорость скачивания через туннель, кбит/с (до 4 секунд); -1 — не измерена. */
    private fun speedKbps(net: Network): Long = try {
        val c = net.openConnection(URL("https://speed.cloudflare.com/__down?bytes=1500000")) as HttpURLConnection
        c.connectTimeout = 5000
        c.readTimeout = 5000
        val t = System.currentTimeMillis()
        var total = 0L
        c.inputStream.use { ins ->
            val buf = ByteArray(16384)
            while (System.currentTimeMillis() - t < 4000) {
                val n = ins.read(buf)
                if (n < 0) break
                total += n
            }
        }
        c.disconnect()
        val ms = maxOf(1L, System.currentTimeMillis() - t)
        total * 8 / ms
    } catch (e: Exception) {
        -1L
    }

    private fun runProbe(ctx: Context) {
        val net = vpnNetwork(ctx)
        if (net == null) {
            log("🌐 живая проверка недоступна: сеть VPN не видна приложению")
            return
        }
        val ctl = control(net)
        if (!ctl.first) {
            log("🌐 живая проверка недоступна: контрольный запрос не идёт через туннель (" + ctl.second + ")")
            return
        }
        val parts = mutableListOf<String>()
        for (t in targets) {
            var r = probe(net, t.url)
            if (!r.ok) {
                Thread.sleep(2000)
                r = probe(net, t.url) // второй шанс: одиночный сбой сервис не хоронит
            }
            parts.add(t.name + (if (r.ok) " ✔ " + r.ms + " мс" else " ✘ " + r.note))
            try { mobile.Mobile.reportService(t.name, if (r.ok) "ok" else "dead", r.note) } catch (e: Throwable) { }
        }
        val sp = speedKbps(net)
        parts.add("скорость " + (if (sp >= 0) "~" + sp + " кбит/с" else "не измерена"))
        if (sp >= 0) {
            try { mobile.Mobile.reportSpeed(sp) } catch (e: Throwable) { }
        }
        log("🌐 живая проверка через туннель: " + parts.joinToString("; "))
    }
}
