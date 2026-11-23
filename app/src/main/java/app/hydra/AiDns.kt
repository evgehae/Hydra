package app.hydra

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.Executors

/**
 * AI-DNS: обход блокировок ИИ через DoH, который подменяет имена на IP прокси.
 * Без root: резолв + подсказки (split/VPN).
 * С root: запись рабочих пар domain→ip в /etc/hosts (через su).
 */
object AiDns {
    private const val TAG = "HydraAiDns"
    private val io = Executors.newSingleThreadExecutor()

    data class Provider(
        val id: String,
        val title: String,
        val dohUrl: String, // https://host/dns-query
        val note: String = ""
    )

    data class Service(
        val id: String,
        val title: String,
        val domains: List<String>
    )

    data class ResolveHit(
        val domain: String,
        val ip: String,
        val isProxyGuess: Boolean // не RFC1918 / не «очевидный» CDN origin — эвристика
    )

    val providers = listOf(
        Provider("geodema", "Geodema Smart DNS", "https://dns.geodema.love/dns-query"),
        Provider("keyoneday", "Keyoneday DNS", "https://dns.keyoneday.ru/dns-query"),
        Provider("wlrus", "WLRus DNS", "https://dns.wlrus.cfd/dns-query"),
        Provider("geohide", "GeoHide RU", "https://geohide.ru/dns-query"),
        Provider("dnsai", "DNS-AI.RU", "https://dns.dns-ai.ru/dns-query"),
        Provider("cloudflare", "Cloudflare (обычный)", "https://cloudflare-dns.com/dns-query", "без подмены — контроль"),
    )

    val services = listOf(
        Service("chatgpt", "ChatGPT, Sora", listOf(
            "chatgpt.com", "www.chatgpt.com", "chat.openai.com", "api.openai.com",
            "ab.chatgpt.com", "auth0.openai.com", "cdn.oaistatic.com", "ios.chat.openai.com"
        )),
        Service("claude", "Claude", listOf(
            "claude.ai", "www.claude.ai", "api.anthropic.com", "console.anthropic.com"
        )),
        Service("grok", "Grok", listOf(
            "grok.com", "www.grok.com", "x.ai", "api.x.ai", "grok.x.ai"
        )),
        Service("gemini", "Gemini, AI Studio", listOf(
            "gemini.google.com", "aistudio.google.com", "generativelanguage.googleapis.com"
        )),
        Service("copilot", "Copilot", listOf(
            "copilot.microsoft.com", "www.bing.com", "sydney.bing.com"
        )),
        Service("notion", "Notion AI", listOf("www.notion.so", "notion.so")),
        Service("deepl", "DeepL", listOf("www.deepl.com", "deepl.com", "api-free.deepl.com")),
        Service("meta", "Meta AI", listOf("www.meta.ai", "meta.ai")),
    )

    fun dohQuery(dohUrl: String, name: String, type: String = "A"): List<String> {
        val url = if (dohUrl.contains("?")) {
            "$dohUrl&name=${URLEncoder.encode(name, "UTF-8")}&type=$type"
        } else {
            "$dohUrl?name=${URLEncoder.encode(name, "UTF-8")}&type=$type"
        }
        val c = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 8000
            readTimeout = 10000
            setRequestProperty("Accept", "application/dns-json")
            setRequestProperty("User-Agent", "Hydra-AiDns")
        }
        try {
            if (c.responseCode !in 200..299) return emptyList()
            val body = c.inputStream.bufferedReader().readText()
            val j = JSONObject(body)
            val ans = j.optJSONArray("Answer") ?: return emptyList()
            val out = ArrayList<String>()
            for (i in 0 until ans.length()) {
                val a = ans.getJSONObject(i)
                if (a.optInt("type") == 1) { // A
                    val data = a.optString("data", "")
                    if (data.matches(Regex("""\d+\.\d+\.\d+\.\d+"""))) out.add(data)
                }
            }
            return out
        } finally {
            c.disconnect()
        }
    }

    /** Сравнить «обычный» CF DNS и выбранный DoH: если IP разные — скорее подмена. */
    fun resolveService(
        dohUrl: String,
        service: Service,
        onProgress: ((String) -> Unit)? = null
    ): List<ResolveHit> {
        val hits = ArrayList<ResolveHit>()
        for (d in service.domains) {
            onProgress?.invoke(d)
            val via = try { dohQuery(dohUrl, d) } catch (_: Throwable) { emptyList() }
            val plain = try { dohQuery("https://cloudflare-dns.com/dns-query", d) } catch (_: Throwable) { emptyList() }
            val ip = via.firstOrNull() ?: continue
            val guess = plain.isNotEmpty() && !plain.contains(ip)
            hits.add(ResolveHit(d, ip, guess))
        }
        return hits
    }

    fun resolveAll(
        ctx: Context,
        providerId: String,
        enabledServiceIds: Set<String>,
        onDone: (ok: Boolean, msg: String, hits: List<ResolveHit>) -> Unit
    ) {
        val prov = providers.find { it.id == providerId } ?: providers.first()
        io.execute {
            try {
                val all = ArrayList<ResolveHit>()
                for (s in services) {
                    if (s.id !in enabledServiceIds) continue
                    all.addAll(resolveService(prov.dohUrl, s))
                }
                val proxyish = all.count { it.isProxyGuess }
                val msg = "Имён: ${all.size}, похоже на прокси: $proxyish"
                // root hosts
                var hostsNote = ""
                if (all.isNotEmpty() && RootHelper.hasRoot()) {
                    val ok = writeHosts(all)
                    hostsNote = if (ok) " · hosts записан (root)" else " · hosts не записался"
                } else if (all.isNotEmpty()) {
                    hostsNote = " · без root hosts не пишем — держи AI-приложения в split VPN"
                }
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    onDone(true, msg + hostsNote, all)
                }
            } catch (e: Throwable) {
                Log.e(TAG, "resolveAll", e)
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    onDone(false, e.message ?: "ошибка", emptyList())
                }
            }
        }
    }

    private fun writeHosts(hits: List<ResolveHit>): Boolean {
        // Маркерный блок между # HYDRA-AI-DNS-BEGIN / END
        val block = buildString {
            appendLine("# HYDRA-AI-DNS-BEGIN")
            for (h in hits.distinctBy { it.domain }) {
                appendLine("${h.ip} ${h.domain}")
            }
            appendLine("# HYDRA-AI-DNS-END")
        }
        val script = """
            H=/etc/hosts
            if [ ! -f ${'$'}H ]; then exit 1; fi
            grep -v 'HYDRA-AI-DNS' ${'$'}H > /data/local/tmp/hosts.hydra 2>/dev/null || cp ${'$'}H /data/local/tmp/hosts.hydra
            sed -i '/HYDRA-AI-DNS-BEGIN/,/HYDRA-AI-DNS-END/d' /data/local/tmp/hosts.hydra 2>/dev/null || true
            cat >> /data/local/tmp/hosts.hydra << 'EOF'
            $block
            EOF
            mount -o rw,remount /system 2>/dev/null || true
            cp /data/local/tmp/hosts.hydra ${'$'}H
            chmod 644 ${'$'}H
        """.trimIndent()
        val (code, out) = RootHelper.su(listOf(script))
        Log.i(TAG, "writeHosts code=$code out=$out")
        return code == 0
    }

    fun clearHosts(): Boolean {
        if (!RootHelper.hasRoot()) return false
        val script = """
            H=/etc/hosts
            sed -i '/HYDRA-AI-DNS-BEGIN/,/HYDRA-AI-DNS-END/d' ${'$'}H 2>/dev/null || true
        """.trimIndent()
        return RootHelper.su(listOf(script)).first == 0
    }
}
