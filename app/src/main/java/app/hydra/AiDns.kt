package app.hydra

import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.ScheduledThreadPoolExecutor
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

/**
 * Обход ИИ через Smart DNS (ChatGPT / Claude / Grok / Gemini…).
 *
 * Как это работает теперь (один способ, VPN выключать НЕ нужно):
 *  1. Приложение само (его трафик идёт мимо туннеля) спрашивает у каждого Smart DNS адреса сервисов ИИ:
 *     обычным UDP:53, а если не вышло — DoH (формат RFC 8484) и DoT.
 *  2. Настоящая проверка: подключается к выданному адресу по TLS с нужным SNI и смотрит ответ
 *     (открывается / «недоступно в вашей стране» / капча / не подключилось).
 *  3. Включение: DNS туннеля = адреса выбранного Smart DNS, а эти адреса и адреса прокси ИИ
 *     исключаются из туннеля (Android 13+). Остальной трафик идёт через WARP как обычно.
 *  Системный «Частный DNS» остаётся запасным путём (нужны root/WRITE_SECURE_SETTINGS).
 *
 * Список серверов: встроенный + файл dns-providers.json из репозитория (обновляется кнопкой) + свои.
 */
object AiDns {
    private const val TAG = "HydraAiDns"
    private const val REMOTE_URL = "https://api.github.com/repos/evgehae/Hydra/contents/dns-providers.json"
    private val io = Executors.newCachedThreadPool()

    data class Provider(
        val id: String,
        val title: String,
        /** Hostname для Android Private DNS (DoT). */
        val hostname: String,
        /** DoH endpoint. */
        val dohUrl: String,
        /** Известные обычные DNS-адреса (UDP:53) — для DNS внутри туннеля. */
        val plain: List<String> = emptyList(),
        val note: String = "",
        val custom: Boolean = false,
        /** Готовый список адресов (hosts GeoHide), DNS-запросов не требует. */
        val static: Boolean = false
    )

    data class Service(
        val id: String,
        val title: String,
        val probeDomain: String,
        val domains: List<String>,
        /** Корневые домены, которые отдаём прокси целиком вместе с поддоменами (*.root). */
        val roots: List<String> = emptyList(),
        /** Порты, по которым проверяем живость адреса (игры Supercell ходят на 9339). */
        val ports: List<Int> = listOf(443),
        /** false — у сервиса не HTTPS (игровой протокол): проверяем только TCP-подключение. */
        val tls: Boolean = true
    )

    data class ResolveHit(val domain: String, val ip: String, val isProxyGuess: Boolean)

    enum class Check { OPEN, BLOCKED, TLS_FAIL, NO_CONN }

    /** Результат проверки одного провайдера. */
    data class ProviderProbe(
        val providerId: String,
        val alive: Boolean,
        val latencyMs: Long,
        /** serviceId → реально открывается (подмена + TLS + нет блока страны). */
        val bypass: Map<String, Boolean>,
        val detail: String,
        /** serviceId → короткий статус для экрана («✔», «⛔ страна», «✘»…). */
        val marks: Map<String, String> = emptyMap(),
        /** Обычные DNS-адреса (UDP:53), которые ответили. Если пусто — можно только через DoH/DoT. */
        val dnsIps: List<String> = emptyList(),
        /** Адреса прокси ИИ, которые открылись (их исключаем из туннеля). */
        val proxyIps: List<String> = emptyList(),
        val via: String = "",
        /** UDP:53 перехватывается оператором (ответ по UDP не совпал с DoH): DNS отправляем внутрь туннеля, а не мимо него. */
        val udpHijacked: Boolean = false,
        /** serviceId → адреса прокси, которые ответил сервер на главный домен сервиса и которые реально открылись. */
        val svcIps: Map<String, List<String>> = emptyMap()
    )

    // ─── Список провайдеров ────────────────────────────────────

    /** Проверено по открытым источникам 14–23.11.2026; мёртвые убираются автоматически (проверка + файл из репозитория). */
    private val builtin = listOf(
        Provider("comss", "Comss.one", "dns.comss.one", "https://dns.comss.one/dns-query",
            listOf("212.109.221.20", "212.109.195.93", "94.250.253.55"), "ChatGPT, Claude, Gemini, Grok"),
        Provider("geohide_eu", "GeoHide EU", "eu.geohide.ru", "https://eu.geohide.ru/dns-query",
            listOf("5.175.161.3", "5.175.161.40", "45.13.237.213", "31.25.239.132", "143.20.64.192"), "ChatGPT, Claude, Gemini, Grok"),
        Provider("geohide_us", "GeoHide US", "us.geohide.ru", "https://us.geohide.ru/dns-query",
            listOf("192.255.159.240", "192.255.159.241", "192.3.233.253", "107.175.76.134")),
        Provider("geohide", "GeoHide RU", "geohide.ru", "https://geohide.ru/dns-query",
            listOf("159.194.200.33", "193.233.112.67", "193.233.112.68", "193.233.112.88", "37.230.192.51", "46.8.158.6"),
            "у части узлов проблемы"),
        Provider("magic", "MagicDNS", "api.magicdns.ru", "https://api.magicdns.ru/dns-query",
            listOf("109.120.177.170", "45.88.163.92", "109.120.132.43", "94.249.177.102")),
        Provider("zapret", "Zapret DNS", "dns.zapret.moe", "https://dns.zapret.moe/dns-query", emptyList(),
            "только DoH (с 03.11.2026) — работает через ядро Гидры"),
        Provider("dagami", "Dagami", "dns.dagami.ru", "https://dns.dagami.ru/dns-query", listOf("2.56.122.194", "48.102.213.179")),
        Provider("keyoneday", "KeyOneDay", "dns.keyoneday.ru", "https://dns.keyoneday.ru/dns-query", listOf("2.58.127.63")),
        Provider("pereval", "Перевал", "free.pereval.top", "https://free.pereval.top/dns-query"),
        Provider("malw", "Malw.link", "dns.malw.link", "https://dns.malw.link/dns-query",
            listOf("84.21.189.133", "193.23.209.189")),
        Provider("dnsai", "DNS-AI", "dns.dns-ai.ru", "https://dns.dns-ai.ru/dns-query",
            listOf("194.87.196.13", "45.151.102.219")),
        Provider("dnsai_cf", "DNS-AI (через CF)", "cf.dns-ai.ru", "https://cf.dns-ai.ru/dns-query", emptyList(),
            "только DoH — работает через ядро Гидры"),
        Provider("geodema", "Geodema", "dns.geodema.love", "https://dns.geodema.love/dns-query",
            listOf("179.236.130.10", "179.236.130.11")),
        Provider("wlrus", "WLRus", "dns.wlrus.cfd", "https://dns.wlrus.cfd/dns-query",
            listOf("95.85.240.254", "138.124.254.134")),
        Provider("bezmezhau", "Bezmezhau", "dns.bezmezhau.com", "https://dns.bezmezhau.com/dns-query",
            listOf("181.215.40.49", "31.58.216.201"), "нестабильный"),
        Provider("webshift", "WebShift", "d.webshiftvpn.ru", "https://d.webshiftvpn.ru/dns-query", emptyList(),
            "новый, проверен 16.10"),
        Provider("gh_eu", "GeoHide EU (список адресов)", "eu.geohide.ru", "", emptyList(), "готовый список, без DNS-запросов", static = true),
        Provider("gh_us", "GeoHide US (список адресов)", "us.geohide.ru", "", emptyList(), "готовый список, без DNS-запросов", static = true),
        Provider("gh_ru", "GeoHide RU (список адресов)", "geohide.ru", "", emptyList(), "готовый список, без DNS-запросов", static = true),
        Provider("cloudflare", "Cloudflare (контроль)", "one.one.one.one", "https://cloudflare-dns.com/dns-query",
            listOf("1.1.1.1", "1.0.0.1"), "без подмены ИИ")
    )

    /** xbox-dns.ru с 10.10.2026 на ИИ отвечает 0.0.0.0, Astracat не отвечает — убраны. */
    private val builtinDead = setOf("xbox", "astracat", "magic2", "keyoneday2", "geohide_old")

    @Volatile var providers: List<Provider> = builtin
        private set

    private fun sp(ctx: Context) = ctx.getSharedPreferences("hydra_aidns", Context.MODE_PRIVATE)

    private fun parseProviders(arr: JSONArray?, custom: Boolean): List<Provider> {
        if (arr == null) return emptyList()
        val res = ArrayList<Provider>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val host = o.optString("host").trim()
            val doh = o.optString("doh").trim()
            if (host.isEmpty() && doh.isEmpty()) continue
            val ips = ArrayList<String>()
            val ia = o.optJSONArray("ip")
            if (ia != null) for (k in 0 until ia.length()) {
                val s = ia.optString(k).trim()
                if (s.matches(Regex("""\d{1,3}(\.\d{1,3}){3}"""))) ips.add(s)
            }
            val h = host.ifEmpty { doh.substringAfter("://").substringBefore("/") }
            val id = o.optString("id").ifBlank { (if (custom) "c_" else "r_") + h }
            res.add(Provider(id, o.optString("title").ifBlank { h }, h,
                doh.ifEmpty { "https://$h/dns-query" }, ips, o.optString("note"), custom))
        }
        return res
    }

    /** Пересобрать список: встроенные + из репозитория + свои, минус мёртвые. */
    fun reload(ctx: Context) {
        val s = sp(ctx)
        val dead = HashSet<String>(builtinDead)
        val remote = ArrayList<Provider>()
        try {
            val txt = s.getString("remote", "") ?: ""
            if (txt.isNotBlank()) {
                val o = JSONObject(txt)
                remote.addAll(parseProviders(o.optJSONArray("providers"), false))
                val d = o.optJSONArray("dead")
                if (d != null) for (i in 0 until d.length()) dead.add(d.optString(i))
            }
        } catch (e: Exception) { Log.w(TAG, "remote json: ${e.message}") }
        val own = try { parseProviders(JSONArray(s.getString("custom", "[]") ?: "[]"), true) } catch (e: Exception) { emptyList() }
        val map = LinkedHashMap<String, Provider>()
        for (p in builtin + remote + own) if (p.id !in dead || p.custom) map[p.id] = p
        providers = map.values.toList()
        loadStatics(ctx)
    }

    /** Добавить свой сервер: hostname, IPv4 или https://…/dns-query. null = ок, иначе текст ошибки. */
    fun addCustom(ctx: Context, input: String): String? {
        val t = input.trim()
        if (t.isEmpty()) return "Пусто"
        val isIp = t.matches(Regex("""\d{1,3}(\.\d{1,3}){3}"""))
        val o = JSONObject()
        when {
            t.startsWith("https://") -> { o.put("doh", t); o.put("host", t.substringAfter("://").substringBefore("/").substringBefore(":")) }
            isIp -> { o.put("host", t); o.put("ip", JSONArray().put(t)); o.put("doh", "") }
            t.matches(Regex("""[A-Za-z0-9.-]+\.[A-Za-z]{2,}""")) -> o.put("host", t)
            else -> return "Нужен hostname, IPv4 или https://…/dns-query"
        }
        o.put("title", o.optString("host"))
        o.put("id", "c_" + o.optString("host"))
        val s = sp(ctx)
        val arr = try { JSONArray(s.getString("custom", "[]") ?: "[]") } catch (e: Exception) { JSONArray() }
        val out = JSONArray()
        for (i in 0 until arr.length()) if (arr.optJSONObject(i)?.optString("id") != o.optString("id")) out.put(arr.get(i))
        out.put(o)
        s.edit().putString("custom", out.toString()).apply()
        reload(ctx)
        return null
    }

    fun removeCustom(ctx: Context, id: String) {
        val s = sp(ctx)
        val arr = try { JSONArray(s.getString("custom", "[]") ?: "[]") } catch (e: Exception) { JSONArray() }
        val out = JSONArray()
        for (i in 0 until arr.length()) if (arr.optJSONObject(i)?.optString("id") != id) out.put(arr.get(i))
        s.edit().putString("custom", out.toString()).apply()
        reload(ctx)
    }

    /** Обновить список серверов из репозитория (api.github.com отдаёт файл и там, где raw.* закрыт). */
    fun syncRemote(ctx: Context, onDone: (Boolean, String) -> Unit) {
        io.execute {
            try {
                val c = (URL(REMOTE_URL).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 8000; readTimeout = 8000
                    setRequestProperty("Accept", "application/vnd.github.raw+json")
                    setRequestProperty("User-Agent", "Hydra-AiDns/2")
                }
                try {
                    if (c.responseCode !in 200..299) { onDone(false, "GitHub: код ${c.responseCode}"); return@execute }
                    val body = c.inputStream.bufferedReader().readText()
                    val before = providers.size
                    val o = JSONObject(body)
                    if (o.optJSONArray("providers") == null) { onDone(false, "В файле нет списка providers"); return@execute }
                    sp(ctx).edit().putString("remote", body).putLong("remote_ts", System.currentTimeMillis()).apply()
                    reload(ctx)
                    onDone(true, "Список обновлён: серверов ${providers.size} (было $before)")
                } finally { c.disconnect() }
            } catch (e: Exception) {
                onDone(false, "Не удалось обновить: ${e.message}")
            }
        }
    }

    val services = listOf(
        Service("chatgpt", "ChatGPT", "chatgpt.com", listOf(
            "chatgpt.com", "www.chatgpt.com", "chat.openai.com", "api.openai.com", "ab.chatgpt.com",
            "cdn.oaistatic.com", "auth.openai.com", "files.oaiusercontent.com", "sentinel.openai.com"
        ), listOf("chatgpt.com", "openai.com", "oaistatic.com", "oaiusercontent.com")),
        Service("claude", "Claude", "claude.ai", listOf(
            "claude.ai", "www.claude.ai", "api.claude.ai", "api.anthropic.com", "console.anthropic.com", "statsig.anthropic.com",
            "claude.com", "www.claude.com", "api.claude.com", "anthropic.com", "www.anthropic.com", "auth.anthropic.com",
            "claudeusercontent.com", "a-api.anthropic.com", "a-cdn.anthropic.com", "s-cdn.anthropic.com", "assets-proxy.anthropic.com",
            "platform.claude.com", "platform.claude.ai", "downloads.claude.ai"
        ), listOf("claude.ai", "anthropic.com", "claude.com")),
        Service("grok", "Grok", "grok.com", listOf(
            "grok.com", "www.grok.com", "assets.grok.com", "x.ai", "www.x.ai", "api.x.ai", "accounts.x.ai", "assets.x.ai", "grok.x.ai", "grok.x.com"
        ), listOf("grok.com", "x.ai")),
        Service("gemini", "Gemini", "gemini.google.com", listOf(
            "gemini.google.com", "gemini.google", "bard.google.com", "aistudio.google.com", "ai.google.dev",
            "notebooklm.google.com", "notebooklm.google", "notebook.google.com", "makersuite.google.com",
            "generativelanguage.googleapis.com", "alkalimakersuite-pa.clients6.google.com", "alkalicore-pa.clients6.google.com",
            "geminiweb-pa.clients6.google.com", "geminiweb-pa.clients.google.com", "webchannel-alkalimakersuite-pa.clients6.google.com",
            "people-pa.clients6.google.com", "waa-pa.clients6.google.com", "signaler-pa.clients6.google.com", "apis.google.com",
            "suggestqueries.google.com", "assistant-s3-pa.googleapis.com", "proactivebackend-pa.googleapis.com",
            "robinfrontend-pa.googleapis.com", "notebooklm-pa.googleapis.com", "notebook-pa.googleapis.com",
            "labs.google", "labs.google.com", "flow.google", "jules.google", "deepmind.google"
        )),
        Service("copilot", "Copilot", "copilot.microsoft.com", listOf("copilot.microsoft.com")),
        Service("perplexity", "Perplexity", "www.perplexity.ai", listOf("www.perplexity.ai", "perplexity.ai"), listOf("perplexity.ai")),
        Service("supercell", "Игры Supercell", "gamea.clashofclans.com", listOf(
            "gamea.clashofclans.com", "game.brawlstarsgame.com", "game.clashroyaleapp.com", "game.squadbustersgame.com",
            "game.boombeachgame.com", "game.mocogame.com", "accounts.supercell.com", "id.supercell.com", "cdn.id.supercell.com",
            "security.id.supercell.com", "store.supercell.com", "clashofclans.inbox.supercell.com", "service.supercell.net",
            "game-assets.clashofclans.com", "game-assets.brawlstarsgame.com", "game-assets.clashroyaleapp.com"
        ), emptyList(), listOf(443, 9339), false),
    )

    /** Какие разделы списка GeoHide относятся к сервису (по слову в названии раздела). */
    private val svcSection = mapOf("chatgpt" to "chatgpt", "claude" to "claude", "grok" to "grok",
        "gemini" to "gemini", "supercell" to "supercell", "copilot" to "copilot")

    /** Сервисы, включённые по умолчанию (4PDA — только для теста, включается вручную). */
    private val defaultServices = setOf("chatgpt", "claude", "grok", "gemini", "supercell")

    /** Включённые сервисы; один раз добавляет игры Supercell тем, у кого уже сохранён старый набор. */
    fun enabledServices(ctx: Context): Set<String> {
        val prefs = Prefs(ctx)
        var cur = prefs.aiDnsServices.split(',').map { it.trim() }.filter { it.isNotEmpty() }.toSet()
        if (cur.isEmpty()) cur = defaultServices
        if (!sp(ctx).getBoolean("svc_v8", false)) {
            cur = cur + "supercell"
            prefs.aiDnsServices = cur.joinToString(",")
            sp(ctx).edit().putBoolean("svc_v8", true).apply()
        }
        return cur
    }

    fun provider(id: String) = providers.find { it.id == id } ?: providers.first()

    // ─── DNS: формат пакетов ───────────────────────────────────

    fun buildQuery(name: String, type: Int = 1): ByteArray {
        val out = ByteArrayOutputStream()
        val id = (System.nanoTime() and 0xffff).toInt()
        out.write(id shr 8); out.write(id and 0xff)
        out.write(0x01); out.write(0x00)           // RD
        out.write(0); out.write(1)                 // QDCOUNT
        for (i in 0 until 6) out.write(0)          // AN/NS/AR
        for (label in name.trimEnd('.').split('.')) {
            val b = label.toByteArray(Charsets.US_ASCII)
            out.write(b.size); out.write(b, 0, b.size)
        }
        out.write(0)
        out.write(type shr 8); out.write(type and 0xff)
        out.write(0); out.write(1)                 // IN
        return out.toByteArray()
    }

    private fun u16(r: ByteArray, i: Int) = ((r[i].toInt() and 0xff) shl 8) or (r[i + 1].toInt() and 0xff)

    private fun skipName(r: ByteArray, start: Int): Int {
        var i = start
        while (i < r.size) {
            val l = r[i].toInt() and 0xff
            if (l == 0) return i + 1
            if ((l and 0xC0) == 0xC0) return i + 2
            i += 1 + l
        }
        return i
    }

    fun parseA(r: ByteArray): List<String> {
        if (r.size < 12) return emptyList()
        if ((r[3].toInt() and 0x0f) != 0) return emptyList()
        val qd = u16(r, 4)
        val an = u16(r, 6)
        var i = 12
        for (q in 0 until qd) { i = skipName(r, i) + 4 }
        val res = ArrayList<String>()
        for (a in 0 until an) {
            if (i >= r.size) break
            i = skipName(r, i)
            if (i + 10 > r.size) break
            val t = u16(r, i)
            val rd = u16(r, i + 8)
            i += 10
            if (t == 1 && rd == 4 && i + 4 <= r.size) {
                res.add("${r[i].toInt() and 0xff}.${r[i + 1].toInt() and 0xff}.${r[i + 2].toInt() and 0xff}.${r[i + 3].toInt() and 0xff}")
            }
            i += rd
        }
        return res
    }

    // ─── DNS: транспорты ───────────────────────────────────────

    fun udpA(server: String, name: String, timeoutMs: Int = 2500): List<String> {
        return try {
            DatagramSocket().use { s ->
                s.soTimeout = timeoutMs
                val q = buildQuery(name)
                s.send(DatagramPacket(q, q.size, InetAddress.getByName(server), 53))
                val buf = ByteArray(1500)
                val p = DatagramPacket(buf, buf.size)
                s.receive(p)
                parseA(buf.copyOf(p.length))
            }
        } catch (e: Exception) { emptyList() }
    }

    /** DoH в формате RFC 8484 (его понимают все; JSON-формат — нет, из-за него живые серверы казались «мёртвыми»). */
    fun dohWireA(dohUrl: String, name: String, timeoutMs: Int = 5000): List<String> {
        val q = Base64.encodeToString(buildQuery(name), Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
        val base = dohUrl.trim()
        val url = base + (if (base.contains('?')) "&" else "?") + "dns=" + q
        val conn = try { URL(url).openConnection() as HttpURLConnection } catch (e: Exception) { return emptyList() }
        return try {
            conn.connectTimeout = timeoutMs
            conn.readTimeout = timeoutMs
            conn.setRequestProperty("Accept", "application/dns-message")
            conn.setRequestProperty("User-Agent", "Hydra-AiDns/2")
            if (conn.responseCode !in 200..299) emptyList() else parseA(conn.inputStream.readBytes())
        } catch (e: Exception) { emptyList() } finally { conn.disconnect() }
    }

    /** DoH JSON (запасной, для нестандартных вроде api.magicinfo.art/rpc). */
    fun dohA(dohUrl: String, name: String, timeoutMs: Int = 8000): List<String> {
        val base = dohUrl.trim()
        val url = base.trimEnd('?') + (if (base.contains('?')) "&" else "?") +
            "name=" + URLEncoder.encode(name, "UTF-8") + "&type=A"
        val conn = try { URL(url).openConnection() as HttpURLConnection } catch (e: Exception) { return emptyList() }
        return try {
            conn.connectTimeout = timeoutMs
            conn.readTimeout = timeoutMs
            conn.setRequestProperty("Accept", "application/dns-json, application/json, */*")
            conn.setRequestProperty("User-Agent", "Hydra-AiDns/2")
            if (conn.responseCode !in 200..299) return emptyList()
            val ans = JSONObject(conn.inputStream.bufferedReader().readText()).optJSONArray("Answer") ?: return emptyList()
            val res = ArrayList<String>()
            for (i in 0 until ans.length()) {
                val o = ans.getJSONObject(i)
                if (o.optInt("type") == 1) {
                    val d = o.optString("data")
                    if (d.matches(Regex("""\d{1,3}(\.\d{1,3}){3}"""))) res.add(d)
                }
            }
            res
        } catch (e: Exception) { emptyList() } finally { conn.disconnect() }
    }

    fun dotA(host: String, name: String, timeoutMs: Int = 5000): List<String> {
        return try {
            val raw = Socket()
            raw.connect(InetSocketAddress(host, 853), timeoutMs)
            raw.soTimeout = timeoutMs
            val ssl = (SSLSocketFactory.getDefault() as SSLSocketFactory).createSocket(raw, host, 853, true) as SSLSocket
            ssl.use { s ->
                s.startHandshake()
                val q = buildQuery(name)
                val o = s.outputStream
                o.write(q.size shr 8); o.write(q.size and 0xff); o.write(q, 0, q.size); o.flush()
                val ins = DataInputStream(s.inputStream)
                val len = ins.readUnsignedShort()
                val b = ByteArray(len)
                ins.readFully(b)
                parseA(b)
            }
        } catch (e: Exception) { emptyList() }
    }

    data class Resolved(val ips: List<String>, val via: String, val ms: Long, val dnsIps: List<String> = emptyList())

    /** Кандидаты на обычный DNS: известные + адреса самого hostname. */
    private fun plainCandidates(p: Provider): List<String> {
        if (p.static) return emptyList()
        val res = LinkedHashSet<String>(p.plain)
        if (!p.hostname.matches(Regex("""\d{1,3}(\.\d{1,3}){3}"""))) {
            try {
                for (a in InetAddress.getAllByName(p.hostname)) {
                    val h = a.hostAddress ?: continue
                    if (h.matches(Regex("""\d{1,3}(\.\d{1,3}){3}"""))) res.add(h)
                }
            } catch (_: Exception) {}
        } else res.add(p.hostname)
        return res.toList()
    }

    /** Спросить все адреса одновременно: быстрые живые первыми, мёртвые не задерживают (раньше Geodema ждал 2,6 с из-за мёртвого адреса). */
    private fun udpRace(ips: List<String>, name: String): List<Pair<String, List<String>>> {
        val res = java.util.concurrent.CopyOnWriteArrayList<Pair<String, List<String>>>()
        if (ips.isEmpty()) return emptyList()
        val latch = java.util.concurrent.CountDownLatch(ips.size)
        ips.forEach { ip ->
            io.execute {
                try { val r = udpA(ip, name, 2500); if (r.isNotEmpty()) res.add(ip to r) } finally { latch.countDown() }
            }
        }
        try { latch.await(2800, TimeUnit.MILLISECONDS) } catch (_: InterruptedException) {}
        return res.toList()
    }

    /** Спросить имя у провайдера любым способом: UDP (гонка по всем адресам) → DoH(wire) → DoH(JSON) → DoT. */
    fun resolveAny(p: Provider, name: String, plain: List<String> = plainCandidates(p)): Resolved {
        val t0 = System.currentTimeMillis()
        val race = udpRace(plain.take(6), name)
        if (race.isNotEmpty()) {
            return Resolved(race[0].second, "UDP", System.currentTimeMillis() - t0, race.map { it.first }.take(2))
        }
        var r = dohWireA(p.dohUrl, name)
        if (r.isNotEmpty()) return Resolved(r, "DoH", System.currentTimeMillis() - t0)
        r = dohA(p.dohUrl, name)
        if (r.isNotEmpty()) return Resolved(r, "DoH", System.currentTimeMillis() - t0)
        r = dotA(p.hostname, name)
        if (r.isNotEmpty()) return Resolved(r, "DoT", System.currentTimeMillis() - t0)
        return Resolved(emptyList(), "", System.currentTimeMillis() - t0)
    }

    /** «Настоящие» адреса (без подмены): Cloudflare. */
    fun baselineA(name: String): List<String> {
        var r = udpA("1.1.1.1", name)
        if (r.isEmpty()) r = udpA("8.8.8.8", name)
        if (r.isEmpty()) r = dohWireA("https://cloudflare-dns.com/dns-query", name)
        return r
    }

    private fun looksLikeProxy(ip: String, baseline: Set<String>): Boolean {
        if (ip in baseline) return false
        if (ip.startsWith("10.") || ip.startsWith("192.168.") || ip.startsWith("127.") || ip == "0.0.0.0") return false
        if (ip.startsWith("172.")) {
            val second = ip.split(".").getOrNull(1)?.toIntOrNull() ?: 0
            if (second in 16..31) return false
        }
        return true
    }

    private val blockMarkers = listOf(
        "unsupported_country", "unsupported_location", "location=unsupported",
        "not available in your country", "isn't available in your country", "not available in your region",
        "unavailable in your region", "google.com/sorry", "недоступен в вашей стране"
    )

    /** Подключение к адресу с нужным SNI и взгляд на ответ: это и есть «открывается ли». Сертификат должен быть выписан на этот домен. */
    fun httpsCheck(ip: String, host: String, slow: Boolean = false): Check {
        val connectMs = if (slow) 9000 else 3500
        val readMs = if (slow) 12000 else 4500
        val raw = Socket()
        try {
            raw.connect(InetSocketAddress(ip, 443), connectMs)
            raw.soTimeout = readMs
        } catch (e: Exception) {
            try { raw.close() } catch (_: Exception) {}
            return Check.NO_CONN
        }
        return try {
            val ssl = (SSLSocketFactory.getDefault() as SSLSocketFactory).createSocket(raw, host, 443, true) as SSLSocket
            ssl.use { s ->
                try { s.startHandshake() } catch (e: Exception) { return@use Check.TLS_FAIL }
                val okName = try { HttpsURLConnection.getDefaultHostnameVerifier().verify(host, s.session) } catch (e: Exception) { false }
                if (!okName) return@use Check.TLS_FAIL
                val req = "GET / HTTP/1.1\r\nHost: $host\r\nUser-Agent: Mozilla/5.0 (Linux; Android 15)\r\n" +
                    "Accept: text/html\r\nConnection: close\r\n\r\n"
                s.outputStream.write(req.toByteArray()); s.outputStream.flush()
                val buf = ByteArray(6000)
                var n = 0
                try {
                    while (n < buf.size) {
                        val k = s.inputStream.read(buf, n, buf.size - n)
                        if (k <= 0) break
                        n += k
                    }
                } catch (_: Exception) {}
                if (n == 0) return@use Check.TLS_FAIL
                val txt = String(buf, 0, n, Charsets.ISO_8859_1).lowercase()
                if (!txt.startsWith("http/")) Check.TLS_FAIL
                else if (blockMarkers.any { txt.contains(it) }) Check.BLOCKED
                else Check.OPEN
            }
        } catch (e: Exception) {
            Check.TLS_FAIL
        }
    }

    // ─── Готовые списки адресов GeoHide (hosts) ────────────────

    @Volatile private var statics: Map<String, Map<String, List<String>>> = emptyMap()    // регион → домен → адреса
    @Volatile private var sections: Map<String, Map<String, List<String>>> = emptyMap()   // регион → раздел → домены

    private fun parseHosts(text: String): Triple<String, Map<String, List<String>>, Map<String, List<String>>> {
        var region = ""
        var sec = ""
        val map = LinkedHashMap<String, MutableList<String>>()
        val secs = LinkedHashMap<String, MutableList<String>>()
        val ipRe = Regex("""\d{1,3}(\.\d{1,3}){3}""")
        for (raw in text.lineSequence()) {
            val l = raw.trim()
            if (l.isEmpty()) continue
            if (l.startsWith("#")) {
                val t = l.trimStart('#').trim()
                if (t.startsWith("Регион серверов:")) region = t.substringAfter(":").trim().lowercase()
                else if (!t.matches(Regex("""[0-9a-fA-F:.]+""")) && !t.startsWith("Последнее") && !t.startsWith("Эти IP") &&
                    !t.startsWith("Остальные") && !t.contains("hosts file")) sec = t
                continue
            }
            val parts = l.split(Regex("\\s+"))
            if (parts.size < 2 || !parts[0].matches(ipRe)) continue
            for (d in parts.drop(1)) {
                val dd = d.lowercase()
                val lst = map.getOrPut(dd) { ArrayList() }
                if (parts[0] !in lst) lst.add(parts[0])
                if (sec.isNotEmpty()) {
                    val sl = secs.getOrPut(sec) { ArrayList() }
                    if (dd !in sl) sl.add(dd)
                }
            }
        }
        return Triple(region, map, secs)
    }

    /** Загрузить списки: свежие из памяти приложения, а если их нет — встроенные (от 14.10.2026). */
    fun loadStatics(ctx: Context) {
        val st = LinkedHashMap<String, Map<String, List<String>>>()
        val sc = LinkedHashMap<String, Map<String, List<String>>>()
        for (reg in listOf("eu", "us", "ru")) {
            val text = try {
                val f = java.io.File(ctx.filesDir, "gh_$reg.hosts")
                if (f.exists() && f.length() > 100) f.readText() else ctx.assets.open("gh_$reg.hosts").bufferedReader().readText()
            } catch (e: Exception) { "" }
            if (text.isBlank()) continue
            val (r, map, secs) = parseHosts(text)
            val key = r.ifBlank { reg }
            st[key] = map; sc[key] = secs
        }
        statics = st; sections = sc
    }

    /** Свежие списки GeoHide с GitHub (Internet-Helper/GeoHideDNS): api.github.com отдаёт и там, где raw закрыт. */
    fun syncGeoHide(ctx: Context): String {
        fun get(url: String): String? = try {
            val c = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = 8000; readTimeout = 15000
                setRequestProperty("User-Agent", "Hydra-AiDns/3")
            }
            try { if (c.responseCode in 200..299) c.inputStream.bufferedReader().readText() else null } finally { c.disconnect() }
        } catch (e: Exception) { null }
        val urls = ArrayList<String>()
        val listing = get("https://api.github.com/repos/Internet-Helper/GeoHideDNS/contents/hosts")
        if (listing != null) try {
            val arr = JSONArray(listing)
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                if (o.optString("type") == "file") urls.add(o.optString("download_url"))
            }
        } catch (_: Exception) {}
        if (urls.isEmpty()) urls.add("https://raw.githubusercontent.com/Internet-Helper/GeoHideDNS/main/hosts/hosts")
        var saved = 0
        for (u in urls.filter { it.isNotBlank() }.take(8)) {
            val text = get(u) ?: continue
            val (region, map, _) = parseHosts(text)
            if (map.size < 50 || region !in listOf("eu", "us", "ru")) continue
            try { java.io.File(ctx.filesDir, "gh_$region.hosts").writeText(text); saved++ } catch (_: Exception) {}
        }
        if (saved > 0) { sp(ctx).edit().putLong("gh_ts", System.currentTimeMillis()).apply(); loadStatics(ctx) }
        return if (saved > 0) "списки GeoHide: обновлено регионов $saved" else "списки GeoHide: не удалось скачать (остались прежние)"
    }

    /** Кнопка «Обновить список»: серверы из репозитория Гидры + свежие адреса GeoHide. */
    fun syncAll(ctx: Context, onDone: (String) -> Unit) {
        syncRemote(ctx) { ok, msg ->
            io.execute {
                val gh = try { syncGeoHide(ctx) } catch (t: Throwable) { "списки GeoHide: ошибка ${t.message}" }
                reload(ctx)
                onDone((if (ok) "$msg. " else "") + gh)
            }
        }
    }

    /** Домены сервиса: свои + все из соответствующих разделов GeoHide. */
    fun serviceDomains(svc: Service): List<String> {
        val extra = LinkedHashSet<String>()
        val kw = svcSection[svc.id]
        if (kw != null) for (regSecs in sections.values) for ((name, doms) in regSecs) if (name.contains(kw, true)) extra.addAll(doms)
        return (svc.domains + extra).distinct()
    }

    private val resPool = java.util.concurrent.Executors.newFixedThreadPool(10)

    fun tcpAlive(ip: String, ports: List<Int>): Boolean {
        for (port in ports) {
            val s = Socket()
            try { s.connect(InetSocketAddress(ip, port), 2500); return true } catch (_: Exception) { } finally { try { s.close() } catch (_: Exception) {} }
        }
        return false
    }

    /** Страна, в которой Cloudflare «видит» нас через этот адрес (loc= из /cdn-cgi/trace). Для ChatGPT и Claude. */
    fun traceLoc(ip: String, host: String): String? {
        return try {
            val raw = Socket()
            raw.connect(InetSocketAddress(ip, 443), 3500)
            raw.soTimeout = 4500
            val ssl = (SSLSocketFactory.getDefault() as SSLSocketFactory).createSocket(raw, host, 443, true) as SSLSocket
            ssl.use { s ->
                s.startHandshake()
                val req = "GET /cdn-cgi/trace HTTP/1.1\r\nHost: $host\r\nUser-Agent: Mozilla/5.0\r\nConnection: close\r\n\r\n"
                s.outputStream.write(req.toByteArray()); s.outputStream.flush()
                val buf = ByteArray(3000)
                var n = 0
                try {
                    while (n < buf.size) {
                        val k = s.inputStream.read(buf, n, buf.size - n)
                        if (k <= 0) break
                        n += k
                    }
                } catch (_: Exception) {}
                Regex("""(?m)^loc=([A-Z]{2})""").find(String(buf, 0, n, Charsets.ISO_8859_1))?.groupValues?.get(1)
            }
        } catch (e: Exception) { null }
    }

    private fun checkOpen(svc: Service, ip: String): Check =
        if (svc.tls) httpsCheck(ip, svc.probeDomain) else if (tcpAlive(ip, svc.ports)) Check.OPEN else Check.NO_CONN

    // ─── Проверка провайдеров ──────────────────────────────────

    private fun probeStatic(p: Provider, svcs: List<Service>): ProviderProbe {
        val reg = p.id.removePrefix("gh_")
        val map = statics[reg]
        if (map.isNullOrEmpty()) return ProviderProbe(p.id, false, 0, emptyMap(), "список не загружен — нажми «Обновить список»")
        val bypass = linkedMapOf<String, Boolean>()
        val marks = linkedMapOf<String, String>()
        val proxies = LinkedHashSet<String>()
        val svcIpsMap = LinkedHashMap<String, List<String>>()
        val t0 = System.currentTimeMillis()
        for (svc in svcs) {
            val ips = map[svc.probeDomain] ?: emptyList()
            if (ips.isEmpty()) { bypass[svc.id] = false; marks[svc.id] = "✘ нет в списке"; continue }
            val alive = ips.filter { tcpAlive(it, svc.ports) }
            if (alive.isEmpty()) { bypass[svc.id] = false; marks[svc.id] = "✘ прокси не отвечает"; continue }
            val chk = checkOpen(svc, alive.first())
            var loc: String? = null
            if (chk == Check.OPEN && (svc.id == "chatgpt" || svc.id == "claude")) loc = traceLoc(alive.first(), svc.probeDomain)
            val ok = chk == Check.OPEN && loc != "RU"
            bypass[svc.id] = ok
            marks[svc.id] = when {
                ok -> "✔" + (if (loc != null) " $loc" else "")
                loc == "RU" -> "⛔ видит РФ"
                chk == Check.BLOCKED -> "⛔ страна/капча"
                else -> "✘ TLS"
            }
            if (ok) { proxies.addAll(alive); svcIpsMap[svc.id] = alive.take(4) }
        }
        val open = bypass.filter { it.value }.keys
        val detail = (if (open.isEmpty()) "список есть, но ничего не открылось" else "открывает: " +
            open.joinToString { id -> svcs.find { it.id == id }?.title ?: id }) + " · список"
        return ProviderProbe(p.id, true, System.currentTimeMillis() - t0, bypass, detail, marks, emptyList(), proxies.toList(), "список", false, svcIpsMap)
    }

    private fun probeOne(p: Provider, svcs: List<Service>, baseline: Map<String, Set<String>>): ProviderProbe {
        if (p.static) return probeStatic(p, svcs)
        val plain = plainCandidates(p)
        val t0 = System.currentTimeMillis()
        var test = resolveAny(p, "example.com", plain)
        if (test.ips.isEmpty()) test = resolveAny(p, "cloudflare.com", plain)
        val latency = System.currentTimeMillis() - t0
        if (test.ips.isEmpty()) {
            return ProviderProbe(p.id, false, latency, emptyMap(), "не отвечает (UDP, DoH, DoT)")
        }
        val dnsIps = test.dnsIps
        // Оператор может подменять ответы UDP:53 (тогда «Comss без подмены», хотя по DoH всё работает).
        // Сравниваем один и тот же AI-домен по UDP и по DoH: если общих адресов нет — UDP перехвачен.
        var hijacked = false
        var useDoh = false
        if (dnsIps.isNotEmpty() && svcs.isNotEmpty()) {
            val probeDom = svcs.first().probeDomain
            val u = resolveAny(p, probeDom, dnsIps).ips
            val d = dohWireA(p.dohUrl, probeDom).ifEmpty { dotA(p.hostname, probeDom) }
            if (u.isNotEmpty() && d.isNotEmpty() && u.intersect(d.toSet()).isEmpty()) { hijacked = true; useDoh = true }
        }
        val bypass = linkedMapOf<String, Boolean>()
        val marks = linkedMapOf<String, String>()
        val proxies = LinkedHashSet<String>()
        val svcIpsMap = LinkedHashMap<String, List<String>>()
        var slowUsed = false
        for (svc in svcs) {
            val ips = if (useDoh) dohWireA(p.dohUrl, svc.probeDomain).ifEmpty { dotA(p.hostname, svc.probeDomain) }
                      else resolveAny(p, svc.probeDomain, if (dnsIps.isNotEmpty()) dnsIps else plain).ips
            val base = baseline[svc.id] ?: emptySet()
            if (ips.isEmpty()) { bypass[svc.id] = false; marks[svc.id] = "✘ нет ответа"; continue }
            val proxy = ips.any { looksLikeProxy(it, base) }
            val ip = ips.firstOrNull { looksLikeProxy(it, base) } ?: ips.first()
            var chk = checkOpen(svc, ip)
            if (proxy && !slowUsed && (chk == Check.NO_CONN || chk == Check.TLS_FAIL)) {
                slowUsed = true   // медленным прокси даём вторую попытку с большим таймаутом (один раз на провайдера)
                chk = httpsCheck(ip, svc.probeDomain, slow = true)
            }
            var loc: String? = null
            if (proxy && chk == Check.OPEN && (svc.id == "chatgpt" || svc.id == "claude")) loc = traceLoc(ip, svc.probeDomain)
            val ok = proxy && chk == Check.OPEN && loc != "RU"
            bypass[svc.id] = ok
            marks[svc.id] = when {
                ok -> "✔" + (if (loc != null) " $loc" else "")
                loc == "RU" -> "⛔ видит РФ"
                !proxy -> "✘ без подмены"
                chk == Check.BLOCKED -> "⛔ страна/капча"
                chk == Check.NO_CONN -> "✘ прокси не отвечает"
                else -> "✘ TLS"
            }
            if (ok) { for (x in ips) if (looksLikeProxy(x, base)) proxies.add(x); svcIpsMap[svc.id] = ips.filter { looksLikeProxy(it, base) }.take(4) }
        }
        val open = bypass.filter { it.value }.keys
        val tunnelOk = dnsIps.isNotEmpty()
        val detail = (if (open.isEmpty()) "живой, ИИ не открывает" else "открывает: " +
            open.joinToString { id -> svcs.find { it.id == id }?.title ?: id }) + " · ${test.via}" +
            (if (hijacked) " · UDP перехвачен" else "") + (if (!tunnelOk) " · только DoH/DoT" else "")
        return ProviderProbe(p.id, true, latency, bypass, detail, marks, dnsIps, proxies.toList(), test.via, hijacked, svcIpsMap)
    }

    /**
     * Проверить провайдеров (VPN выключать не нужно: трафик самого приложения идёт мимо туннеля).
     * onProgress(готово, всего) вызывается по мере проверки.
     */
    fun probeProviders(
        providerIds: List<String> = providers.map { it.id },
        serviceIds: List<String> = services.map { it.id },
        onProgress: (Int, Int) -> Unit = { _, _ -> },
        onDone: (List<ProviderProbe>) -> Unit
    ) {
        io.execute {
            val svcs = services.filter { it.id in serviceIds }.ifEmpty { services }
            val baseline = HashMap<String, Set<String>>()
            for (s in svcs) baseline[s.id] = baselineA(s.probeDomain).toSet()
            val total = providerIds.size
            var done = 0
            val jobs = providerIds.map { pid ->
                io.submit(Callable {
                    val r = try { probeOne(provider(pid), svcs, baseline) }
                    catch (e: Throwable) { ProviderProbe(pid, false, 0, emptyMap(), "ошибка: ${e.message}") }
                    synchronized(this) { done++; onProgress(done, total) }
                    r
                })
            }
            val results = jobs.mapNotNull { f ->
                try { f.get(120, TimeUnit.SECONDS) } catch (e: Exception) { Log.e(TAG, "probe", e); null }
            }
            onDone(results)
        }
    }

    /** Лучший: больше открытых сервисов, дальше — есть обычный DNS (работает без root), дальше — быстрее. */
    fun pickBest(probes: List<ProviderProbe>, preferService: String = "chatgpt"): Provider? {
        val scored = probes.filter { it.alive && it.providerId != "cloudflare" }.map { pr ->
            val score = pr.bypass.values.count { it } * 10 +
                (if (pr.bypass[preferService] == true) 5 else 0) +
                (if (pr.dnsIps.isNotEmpty()) 8 else 0) -
                (pr.latencyMs / 100).toInt()
            pr to score
        }.filter { it.first.bypass.values.any { v -> v } }.sortedByDescending { it.second }
        return scored.firstOrNull()?.let { provider(it.first.providerId) }
    }

    // ─── Память результатов проверки ───────────────────────────

    private fun probeToJson(p: ProviderProbe): JSONObject = JSONObject().apply {
        put("id", p.providerId); put("alive", p.alive); put("ms", p.latencyMs); put("detail", p.detail); put("via", p.via)
        put("hij", p.udpHijacked)
        put("bypass", JSONObject().also { o -> p.bypass.forEach { (k, v) -> o.put(k, v) } })
        put("marks", JSONObject().also { o -> p.marks.forEach { (k, v) -> o.put(k, v) } })
        put("dns", JSONArray(p.dnsIps)); put("proxy", JSONArray(p.proxyIps))
        put("svcips", JSONObject().also { o -> p.svcIps.forEach { (k, v) -> o.put(k, JSONArray(v)) } })
    }

    private fun probeFromJson(o: JSONObject): ProviderProbe {
        fun strs(a: JSONArray?): List<String> = if (a == null) emptyList() else (0 until a.length()).map { a.optString(it) }
        val b = LinkedHashMap<String, Boolean>(); val m = LinkedHashMap<String, String>(); val si = LinkedHashMap<String, List<String>>()
        o.optJSONObject("bypass")?.let { j -> j.keys().forEach { k -> b[k] = j.optBoolean(k) } }
        o.optJSONObject("marks")?.let { j -> j.keys().forEach { k -> m[k] = j.optString(k) } }
        o.optJSONObject("svcips")?.let { j -> j.keys().forEach { k -> si[k] = strs(j.optJSONArray(k)) } }
        return ProviderProbe(o.optString("id"), o.optBoolean("alive"), o.optLong("ms"), b, o.optString("detail"), m,
            strs(o.optJSONArray("dns")), strs(o.optJSONArray("proxy")), o.optString("via"), o.optBoolean("hij"), si)
    }

    /** Результаты последней проверки (лучшие сверху), переживают закрытие экрана и перезапуск приложения. */
    fun loadProbes(ctx: Context): List<ProviderProbe> = try {
        val arr = JSONArray(sp(ctx).getString("probes", "[]") ?: "[]")
        (0 until arr.length()).mapNotNull { arr.optJSONObject(it)?.let { o -> probeFromJson(o) } }
    } catch (e: Exception) { emptyList() }

    fun saveProbes(ctx: Context, list: List<ProviderProbe>) {
        val arr = JSONArray()
        sortedProbes(list).forEach { arr.put(probeToJson(it)) }
        sp(ctx).edit().putString("probes", arr.toString()).putLong("probe_ts", System.currentTimeMillis()).apply()
    }

    /**
     * Рейтинг для сортировки. Три яруса, чтобы все зелёные всегда были выше жёлтых, а жёлтые выше красных:
     * зелёные (открывают хоть один сервис) → жёлтые (живые) → красные (не отвечают).
     */
    fun score(pr: ProviderProbe?): Int {
        if (pr == null || !pr.alive) return -1000
        val open = pr.bypass.values.count { it }
        val tier = if (open > 0) 3000 else 1000
        return tier + open * 20 + (if (pr.dnsIps.isNotEmpty()) 5 else 0) - (pr.latencyMs / 100).toInt().coerceAtMost(40)
    }

    fun sortedProbes(list: List<ProviderProbe>): List<ProviderProbe> = list.sortedByDescending { score(it) }

    fun openCount(pr: ProviderProbe?) = pr?.bypass?.values?.count { it } ?: 0

    // ─── Карта «домен → адреса»: для каждого сервиса свой лучший сервер ──────────────

    data class OvResult(
        val text: String,
        val routes: List<String>,
        val info: Map<String, String>,     // serviceId → название сервера
        val sample: Map<String, String>,   // serviceId → адрес для проверки живости
        val bySvc: Map<String, List<String>>,
        val missing: List<String>          // сервисы, которые не открылись ни на одном сервере
    )

    private fun <T> parMap(items: List<String>, f: (String) -> T): List<T?> {
        val futs = items.map { x -> resPool.submit(Callable<T?> { try { f(x) } catch (e: Throwable) { null } }) }
        return futs.map { try { it.get(45, TimeUnit.SECONDS) } catch (e: Exception) { null } }
    }

    private fun resolveFor(p: Provider, pr: ProviderProbe, name: String): List<String> {
        if (p.static) return statics[p.id.removePrefix("gh_")]?.get(name.lowercase()) ?: emptyList()
        val viaDoh = pr.udpHijacked || pr.dnsIps.isEmpty()
        return if (!viaDoh) resolveAny(p, name, pr.dnsIps).ips
        else dohWireA(p.dohUrl, name).ifEmpty { dohA(p.dohUrl, name) }.ifEmpty { dotA(p.hostname, name) }
    }

    /**
     * Для каждого включённого сервиса берём лучший сервер, который его реально открывает
     * (закреплённый пользователем сервер — в приоритете), спрашиваем у него все домены сервиса.
     * Один сервер больше не должен уметь всё: Gemini может идти через Zapret, ChatGPT через Geodema.
     */
    fun buildOverrides(probes: List<ProviderProbe>, svcIds: Set<String>, pinned: String): OvResult {
        val lines = ArrayList<String>()
        val routes = LinkedHashSet<String>()
        val info = LinkedHashMap<String, String>()
        val sample = LinkedHashMap<String, String>()
        val bySvc = LinkedHashMap<String, List<String>>()
        val missing = ArrayList<String>()
        for (svc in services.filter { it.id in svcIds }) {
            val cands = probes.filter { it.alive && it.bypass[svc.id] == true }
                .sortedByDescending { (if (it.providerId == pinned) 100000 else 0) + score(it) }
            var done = false
            for (pr in cands.take(3)) {
                val p = provider(pr.providerId)
                val domains = serviceDomains(svc)
                val answers = parMap(domains) { d -> resolveFor(p, pr, d) }
                val raw = LinkedHashMap<String, List<String>>()
                domains.forEachIndexed { i, d -> val ips = answers[i]; if (!ips.isNullOrEmpty()) raw[d] = ips.take(6) }
                // оставляем только живые адреса (как делает AISprut: «рабочих 28 из 47»)
                val uniq = raw.values.flatten().distinct()
                val aliveRes = parMap(uniq) { ip -> tcpAlive(ip, svc.ports) }
                val alive = HashSet<String>()
                uniq.forEachIndexed { i, ip -> if (aliveRes[i] == true) alive.add(ip) }
                val map = LinkedHashMap<String, List<String>>()
                raw.forEach { (d, ips) -> val ok = ips.filter { it in alive }.take(4); if (ok.isNotEmpty()) map[d] = ok }
                val main = map[svc.probeDomain] ?: map.values.firstOrNull() ?: continue
                map.forEach { (d, ips) -> lines.add("$d=${ips.joinToString(",")}") }
                for (root in svc.roots) lines.add("*.$root=${(map[root] ?: main).joinToString(",")}")
                val all = LinkedHashSet<String>()
                map.values.forEach { all.addAll(it) }
                routes.addAll(all)
                bySvc[svc.id] = all.toList()
                info[svc.id] = p.title
                sample[svc.id] = main.first()
                done = true
                break
            }
            if (!done) missing.add(svc.id)
        }
        return OvResult(lines.joinToString("\n"), routes.toList().take(96), info, sample, bySvc, missing)
    }

    fun mappingText(ctx: Context): String {
        return try {
            val o = JSONObject(sp(ctx).getString("ov_info", "{}") ?: "{}")
            services.filter { o.has(it.id) }.joinToString(" · ") { it.title + " → " + o.optString(it.id) }
        } catch (e: Exception) { "" }
    }

    fun overrideText(ctx: Context): String = sp(ctx).getString("ov_text", "") ?: ""
    fun proxyRoutes(ctx: Context): List<String> =
        (sp(ctx).getString("ov_routes", "") ?: "").split(',').map { it.trim() }.filter { it.isNotEmpty() }
    fun vpnDnsIps(ctx: Context): List<String> = emptyList()   // совместимость: DNS-серверы больше не подменяются

    fun activeProviderId(ctx: Context): String = Prefs(ctx).aiDnsProvider
    fun activeProviderTitle(ctx: Context): String = mappingText(ctx)

    fun lastProbeAgeMin(ctx: Context): Long {
        val t = sp(ctx).getLong("probe_ts", 0L)
        return if (t == 0L) -1 else (System.currentTimeMillis() - t) / 60000
    }

    private fun storeOverrides(ctx: Context, ov: OvResult) {
        sp(ctx).edit()
            .putString("ov_text", ov.text)
            .putString("ov_routes", ov.routes.joinToString(","))
            .putString("ov_info", JSONObject(ov.info as Map<*, *>).toString())
            .putString("ov_sample", JSONObject(ov.sample as Map<*, *>).toString())
            .putLong("ov_ts", System.currentTimeMillis())
            .apply()
    }

    private fun pushToCore(text: String): Int = try { mobile.Mobile.setDnsOverrides(text).toInt() } catch (t: Throwable) { Log.w(TAG, "core: ${t.message}"); -1 }
    fun clearCoreOverrides() { pushToCore("") }

    fun autoOn(ctx: Context): Boolean = sp(ctx).getBoolean("auto", true)
    fun setAuto(ctx: Context, v: Boolean) {
        sp(ctx).edit().putBoolean("auto", v).apply()
        if (v) startAuto(ctx) else stopAuto()
    }

    // системные «Частные DNS» наших серверов ломали интернет в VPN: убираем их сами
    fun clearOurPrivateDns(ctx: Context): Boolean {
        return try {
            val (mode, host) = readPrivateDns(ctx)
            if (mode == "hostname" && host.isNotBlank() && providers.any { it.hostname.equals(host, true) }) {
                disablePrivateDns(ctx).ok
            } else false
        } catch (e: Throwable) { false }
    }

    private val serviceApps = mapOf(
        "chatgpt" to listOf("com.openai.chatgpt"),
        "claude" to listOf("com.anthropic.claude"),
        "grok" to listOf("ai.x.grok"),
        "gemini" to listOf("com.google.android.apps.bard", "com.google.android.apps.notebooklm"),
        "copilot" to listOf("com.microsoft.copilot"),
        "perplexity" to listOf("ai.perplexity.app.android"),
        "supercell" to listOf("com.supercell.clashofclans", "com.supercell.brawlstars", "com.supercell.clashroyale", "com.supercell.squadbusters")
    )

    /** Приложения включённых сервисов должны идти через туннель, иначе обход их не касается. */
    fun ensureAppsInTunnel(ctx: Context, svcIds: Set<String>): List<String> {
        val prefs = Prefs(ctx)
        val pm = ctx.packageManager
        val wanted = svcIds.flatMap { serviceApps[it] ?: emptyList() } + (if ("chatgpt" in svcIds) listOf("com.deepseek.chat") else emptyList())
        val installed = wanted.distinct().filter { pkg -> try { pm.getPackageInfo(pkg, 0); true } catch (e: Exception) { false } }
        if (installed.isEmpty()) return emptyList()
        val cur = prefs.splitApps
        return if (prefs.splitOnlySelected) {
            val add = installed.filter { it !in cur }
            if (add.isNotEmpty()) prefs.splitApps = cur + add
            add
        } else {
            val del = installed.filter { it in cur }
            if (del.isNotEmpty()) prefs.splitApps = cur - del.toSet()
            del
        }
    }

    data class ApplyOut(val ov: OvResult?, val needRestart: Boolean, val message: String)

    /** Построить карту из результатов проверки, сохранить, сразу отдать ядру. VPN перезапускать нужно, только если появились сервисы без исключённых адресов. */
    fun applyProbes(ctx: Context, probes: List<ProviderProbe>, svcIds: Set<String>, pinned: String): ApplyOut {
        val ov = buildOverrides(probes, svcIds, pinned)
        if (ov.text.isBlank()) return ApplyOut(null, false, "Ни один сервис сейчас не открывается ни на одном сервере.")
        val old = proxyRoutes(ctx).toSet()
        storeOverrides(ctx, ov)
        pushToCore(ov.text)
        val uncovered = ov.bySvc.any { (_, ips) -> ips.none { it in old } }
        val miss = if (ov.missing.isEmpty()) "" else " Не открылось: " + services.filter { it.id in ov.missing }.joinToString { it.title } + "."
        return ApplyOut(ov, uncovered, "Обход: " + services.filter { it.id in ov.info.keys }.joinToString(" · ") { it.title + " → " + ov.info[it.id] } + "." + miss)
    }

    data class ApplyResult(val ok: Boolean, val method: String, val message: String)

    /**
     * Включить обход. Если карта уже была построена — включаем сразу, без ожидания (проверка обновится в фоне).
     * Если карты нет — проверяем все серверы и строим её. Системный частный DNS не трогаем.
     */
    fun enable(ctx: Context, providerId: String, serviceIds: Set<String>, onDone: (ApplyResult) -> Unit) {
        if (statics.isEmpty()) loadStatics(ctx)
        val prefs = Prefs(ctx)
        prefs.aiDnsProvider = providerId
        val stored = overrideText(ctx)
        if (stored.isNotBlank()) {
            pushToCore(stored)
            prefs.aiDnsEnabled = true
            clearOurPrivateDns(ctx)
            val added = ensureAppsInTunnel(ctx, serviceIds)
            onDone(ApplyResult(true, "core", "Включён сразу. " + mappingText(ctx) +
                (if (added.isNotEmpty()) ". В туннель добавлены приложения: ${added.size}" else "")))
            io.execute {   // обновить в фоне
                probeAllAndSave(ctx, serviceIds) { sorted ->
                    val out = applyProbes(ctx, sorted, serviceIds, providerId)
                    if (out.ov != null && out.needRestart && prefs.wantConnected) restartTunnel(ctx, "авто: обновились адреса ИИ")
                }
            }
            return
        }
        probeAllAndSave(ctx, serviceIds) { sorted ->
            val out = applyProbes(ctx, sorted, serviceIds, providerId)
            if (out.ov == null) {
                onDone(ApplyResult(false, "none", out.message + " Попробую снова через 30 минут, можно добавить свой сервер."))
            } else {
                prefs.aiDnsEnabled = true
                clearOurPrivateDns(ctx)
                val added = ensureAppsInTunnel(ctx, serviceIds)
                onDone(ApplyResult(true, "core", out.message + (if (added.isNotEmpty()) " В туннель добавлены приложения: ${added.size}." else "")))
            }
        }
    }

    fun deactivate(ctx: Context) {
        sp(ctx).edit().putString("ov_text", "").putString("ov_routes", "").putString("ov_info", "{}").putString("ov_sample", "{}").apply()
        clearCoreOverrides()
        Prefs(ctx).aiDnsEnabled = false
    }

    fun disable(ctx: Context) = deactivate(ctx)

    /** Полная проверка всех серверов с сохранением; возвращает отсортированный результат. */
    fun probeAllAndSave(ctx: Context, serviceIds: Set<String>, onProgress: (Int, Int) -> Unit = { _, _ -> },
                        onDone: (List<ProviderProbe>) -> Unit) {
        probeProviders(providers.map { it.id }, serviceIds.toList(), onProgress) { list ->
            saveProbes(ctx, list)
            onDone(sortedProbes(list))
        }
    }

    // ─── Живой статус для главного экрана ──────────────────────

    data class Health(val state: Int, val text: String, val at: Long)   // 0 неизвестно, 1 работает, 2 частично, 3 мертво

    @Volatile var lastHealth: Health = Health(0, "проверяю…", 0L)

    fun quickHealth(ctx: Context): Health {
        val sample = try { JSONObject(sp(ctx).getString("ov_sample", "{}") ?: "{}") } catch (e: Exception) { JSONObject() }
        val ids = services.filter { sample.has(it.id) && it.id != "4pda" }.take(4)
        if (ids.isEmpty()) return Health(3, "карта адресов пуста — открой «DNS и обход ИИ»", System.currentTimeMillis()).also { lastHealth = it }
        val results = parMap(ids.map { it.id }) { id ->
            val svc = services.first { it.id == id }
            checkOpen(svc, sample.optString(id)) == Check.OPEN
        }
        var ok = 0
        val parts = ids.mapIndexed { i, s -> val g = results[i] == true; if (g) ok++; s.title + if (g) " ✔" else " ✘" }
        val h = when {
            ok == ids.size -> Health(1, parts.joinToString(" · "), System.currentTimeMillis())
            ok > 0 -> Health(2, parts.joinToString(" · "), System.currentTimeMillis())
            else -> Health(3, parts.joinToString(" · ") + " — не отвечает", System.currentTimeMillis())
        }
        lastHealth = h
        return h
    }

    // ─── DNS-снимок для отчёта (чтобы понять, кто и что отвечает именно в тот момент) ────────

    fun snapshotText(ctx: Context): String = sp(ctx).getString("snapshot", "") ?: ""

    fun makeSnapshot(ctx: Context) {
        try {
            val names = listOf("4pda.to", "gamea.clashofclans.com", "accounts.supercell.com", "chatgpt.com", "claude.ai", "gemini.google.com", "geminiweb-pa.clients6.google.com")
            val sb = StringBuilder()
            val stamp = java.text.SimpleDateFormat("HH:mm:ss").format(java.util.Date())
            sb.append("снимок в ").append(stamp).append('\n')
            val top = loadProbes(ctx).filter { it.alive && openCount(it) > 0 }.take(2).map { provider(it.providerId) }
            for (n in names) {
                val base = baselineA(n)
                val sys = try { InetAddress.getAllByName(n).mapNotNull { it.hostAddress }.filter { it.contains('.') } } catch (e: Exception) { emptyList() }
                sb.append(n).append(": 1.1.1.1=").append(base.joinToString(",").ifEmpty { "—" })
                sb.append(" система=").append(sys.joinToString(",").ifEmpty { "—" })
                for (p in top) {
                    val r = dohWireA(p.dohUrl, n).ifEmpty { resolveAny(p, n).ips }
                    sb.append(' ').append(p.title).append('=').append(r.joinToString(",").ifEmpty { "—" })
                }
                sb.append('\n')
            }
            sp(ctx).edit().putString("snapshot", sb.toString()).apply()
        } catch (t: Throwable) { Log.w(TAG, "snapshot: ${t.message}") }
    }

    // ─── Автопоиск: каждые 30 минут проверка, пересборка карты и переход на лучшие серверы ──

    private val sched = ScheduledThreadPoolExecutor(1)
    private var autoFuture: ScheduledFuture<*>? = null
    @Volatile private var lastFull = 0L
    @Volatile private var autoCtx: Context? = null
    @Volatile private var deadStreak = 0

    @Synchronized fun startAuto(ctx: Context) {
        if (statics.isEmpty()) loadStatics(ctx.applicationContext)
        if (!autoOn(ctx)) return
        autoCtx = ctx.applicationContext
        if (autoFuture?.isDone == false) return
        lastFull = sp(ctx).getLong("probe_ts", 0L)
        autoFuture = sched.scheduleWithFixedDelay({ try { autoTick() } catch (t: Throwable) { Log.w(TAG, "auto: ${t.message}") } },
            1, 5, TimeUnit.MINUTES)
    }

    @Synchronized fun stopAuto() { autoFuture?.cancel(false); autoFuture = null }

    private fun logLine(s: String) { try { mobile.Mobile.logLine(s) } catch (_: Throwable) {} }

    /** Фоновое обслуживание раз в сутки: свежие списки GeoHide, серверы из репозитория, общая база опыта. */
    fun maintenance(ctx: Context) {
        val now = System.currentTimeMillis()
        if (now - sp(ctx).getLong("gh_ts", 0L) > 24 * 3600_000L) {
            try { syncGeoHide(ctx) } catch (_: Throwable) {}
            try { syncRemote(ctx) { _, _ -> } } catch (_: Throwable) {}
            sp(ctx).edit().putLong("gh_ts", System.currentTimeMillis()).apply()
        }
        try { Priors.maybeSync(ctx) } catch (_: Throwable) {}
    }

    private fun autoTick() {
        val ctx = autoCtx ?: return
        maintenance(ctx)
        val prefs = Prefs(ctx)
        if (!prefs.aiDnsEnabled || !autoOn(ctx)) return
        val h = quickHealth(ctx)
        deadStreak = if (h.state == 3) deadStreak + 1 else 0
        val due = System.currentTimeMillis() - lastFull >= 30 * 60_000L
        if (!due && h.state != 3) return
        if (!due && deadStreak < 2) return
        lastFull = System.currentTimeMillis()
        val svc = enabledServices(ctx)
        logLine("🤖 обход ИИ: автопоиск (${if (due) "плановый, 30 мин" else "сервер не отвечает"})")
        probeAllAndSave(ctx, svc) { sorted ->
            val out = applyProbes(ctx, sorted, svc, prefs.aiDnsProvider)
            if (out.ov == null) {
                logLine("🤖 обход ИИ: ${out.message} Оставляю прежнюю карту.")
            } else {
                logLine("🤖 " + out.message)
                if (out.needRestart && prefs.wantConnected) restartTunnel(ctx, "авто: новые адреса ИИ-прокси")
            }
            makeSnapshot(ctx)
        }
    }

    private fun restartTunnel(ctx: Context, why: String) {
        if (!Prefs(ctx).wantConnected) return
        try {
            ctx.startService(android.content.Intent(ctx, HydraVpnService::class.java)
                .setAction(HydraVpnService.ACTION_STOP).putExtra("src", why))
            Thread.sleep(1500)
            Prefs(ctx).wantConnected = true
            androidx.core.content.ContextCompat.startForegroundService(ctx,
                android.content.Intent(ctx, HydraVpnService::class.java).setAction(HydraVpnService.ACTION_START))
        } catch (t: Throwable) { Log.w(TAG, "restart: ${t.message}") }
    }

    /**
     * Хук для HydraVpnService при сборке туннеля: отдать ядру карту «домен → адреса» и вывести адреса прокси из туннеля.
     * DNS-серверы НЕ подменяем: ядро отвечает на DNS-запросы ИИ-доменов само, остальное идёт как обычно.
     * Возвращает 0 (служба поставит обычный DNS).
     */
    fun applyToBuilder(ctx: Context, b: android.net.VpnService.Builder, log: (String) -> Unit): Int {
        if (statics.isEmpty()) loadStatics(ctx)
        val text = overrideText(ctx)
        if (text.isBlank()) {
            clearCoreOverrides()
            log("Обход ИИ включён, но карта адресов пуста — открой «DNS и обход ИИ» → «Найти лучший»")
            startAuto(ctx)
            return 0
        }
        if (clearOurPrivateDns(ctx)) log("Обход ИИ: сбросил системный частный DNS нашего сервера (он отключал интернет в VPN)")
        val n = pushToCore(text)
        var k = 0
        if (Build.VERSION.SDK_INT >= 33) {
            for (ip in proxyRoutes(ctx).distinct()) {
                try { b.excludeRoute(android.net.IpPrefix(InetAddress.getByName(ip), 32)); k++ } catch (_: Exception) {}
            }
        }
        log("Обход ИИ: ядро отвечает на $n имён (${mappingText(ctx)}), мимо туннеля адресов прокси: $k" +
            if (Build.VERSION.SDK_INT < 33) " (Android <13: прокси идут через туннель)" else "")
        startAuto(ctx)
        return 0
    }

    // ─── Private DNS apply ─────────────────────────────────────


    /** Текущий системный Private DNS (mode + specifier). */
    fun readPrivateDns(ctx: Context): Pair<String, String> {
        return try {
            val cr = ctx.contentResolver
            val mode = Settings.Global.getString(cr, "private_dns_mode") ?: "off"
            val host = Settings.Global.getString(cr, "private_dns_specifier") ?: ""
            mode to host
        } catch (_: Exception) {
            "?" to ""
        }
    }

    /**
     * Включить Private DNS = hostname провайдера.
     * 1) Settings.Global (нужен WRITE_SECURE_SETTINGS)
     * 2) root: settings put global …
     * 3) иначе — clipboard + экран настроек
     */
    fun applyPrivateDns(ctx: Context, providerId: String): ApplyResult {
        val p = provider(providerId)
        val host = p.hostname

        // 1. Secure settings
        try {
            Settings.Global.putString(ctx.contentResolver, "private_dns_mode", "hostname")
            Settings.Global.putString(ctx.contentResolver, "private_dns_specifier", host)
            val (mode, spec) = readPrivateDns(ctx)
            if (mode == "hostname" && spec == host) {
                return ApplyResult(true, "settings", "Частный DNS = $host")
            }
        } catch (e: SecurityException) {
            Log.i(TAG, "no WRITE_SECURE_SETTINGS: ${e.message}")
        } catch (e: Exception) {
            Log.w(TAG, "putString: ${e.message}")
        }

        // 2. Root
        if (RootHelper.hasRoot()) {
            val (code, out) = RootHelper.su(
                listOf(
                    "settings put global private_dns_mode hostname",
                    "settings put global private_dns_specifier $host",
                    "settings get global private_dns_mode",
                    "settings get global private_dns_specifier"
                ),
                timeoutMs = 10000
            )
            Log.i(TAG, "root private dns code=$code out=$out")
            if (code == 0 && out.contains(host)) {
                return ApplyResult(true, "root", "Частный DNS = $host (root)")
            }
        }

        // 3. Clipboard + settings screen
        try {
            val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
            cm.setPrimaryClip(android.content.ClipData.newPlainText("dns", host))
        } catch (_: Exception) {}
        openPrivateDnsSettings(ctx)
        return ApplyResult(
            false,
            "manual",
            "Скопировано: $host\nОткрой «Частный DNS» → «Имя хоста» → вставь → Сохранить"
        )
    }

    fun disablePrivateDns(ctx: Context): ApplyResult {
        try {
            Settings.Global.putString(ctx.contentResolver, "private_dns_mode", "off")
            return ApplyResult(true, "settings", "Частный DNS выключен")
        } catch (_: SecurityException) {}
        if (RootHelper.hasRoot()) {
            val (code, _) = RootHelper.su(listOf("settings put global private_dns_mode off"))
            if (code == 0) return ApplyResult(true, "root", "Частный DNS выключен (root)")
        }
        openPrivateDnsSettings(ctx)
        return ApplyResult(false, "manual", "Открой «Частный DNS» → Выкл")
    }

    fun openPrivateDnsSettings(ctx: Context) {
        val intents = listOf(
            Intent("android.settings.PRIVATE_DNS_SETTINGS"),
            Intent(Settings.ACTION_WIRELESS_SETTINGS),
            Intent(Settings.ACTION_SETTINGS)
        )
        for (i in intents) {
            try {
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                ctx.startActivity(i)
                return
            } catch (_: Exception) {}
        }
    }

    // ─── Legacy resolve (карта для локального DNS / hosts) ─────

    fun resolveAll(
        ctx: Context,
        providerId: String,
        serviceIds: Set<String>,
        onDone: (ok: Boolean, msg: String, hits: List<ResolveHit>) -> Unit
    ) {
        io.execute {
            try {
                val p = provider(providerId)
                val baseline = mutableMapOf<String, Set<String>>()
                val cf = provider("cloudflare")
                for (svc in services.filter { it.id in serviceIds }) {
                    baseline[svc.probeDomain] = baselineA(svc.probeDomain).toSet()
                }
                val all = mutableListOf<ResolveHit>()
                for (svc in services.filter { it.id in serviceIds }) {
                    for (d in svc.domains) {
                        val ips = resolveAny(p, d).ips
                        val ip = ips.firstOrNull() ?: continue
                        val base = baseline[svc.probeDomain] ?: emptySet()
                        all.add(ResolveHit(d, ip, looksLikeProxy(ip, base)))
                    }
                }
                LocalDnsServer.setMap(all)
                try {
                    Prefs(ctx).aiDnsCache =
                        all.joinToString("\n") { "${it.domain}|${it.ip}|${if (it.isProxyGuess) 1 else 0}" }
                } catch (_: Throwable) {}
                var hostsNote = ""
                if (all.isNotEmpty() && RootHelper.hasRoot()) {
                    val ok = writeHosts(all)
                    hostsNote = if (ok) " · hosts OK" else " · hosts fail"
                }
                val proxyish = all.count { it.isProxyGuess }
                val msg = "Имён: ${all.size}, подмена: $proxyish$hostsNote"
                onDone(all.isNotEmpty(), msg, all)
            } catch (e: Exception) {
                Log.e(TAG, "resolveAll", e)
                onDone(false, e.message ?: "error", emptyList())
            }
        }
    }

    private fun writeHosts(hits: List<ResolveHit>): Boolean {
        val block = buildString {
            appendLine("# HYDRA-AI-DNS-BEGIN")
            for (h in hits.distinctBy { it.domain }) {
                appendLine("${h.ip} ${h.domain}")
            }
            appendLine("# HYDRA-AI-DNS-END")
        }
        val script = buildString {
            appendLine("set -e")
            appendLine("BLOCK=/data/local/tmp/hydra-aidns-block.txt")
            appendLine("cat > \$BLOCK << 'ENDBLOCK'")
            append(block)
            appendLine("ENDBLOCK")
            appendLine("MOD=/data/adb/modules/hosts")
            appendLine("if [ -d /data/adb/modules ]; then")
            appendLine("  mkdir -p \$MOD/system/etc")
            appendLine("  printf 'id=hosts\\nname=Hydra AI-DNS\\nversion=1\\nversionCode=1\\nauthor=Hydra\\ndescription=AI DNS hosts\\n' > \$MOD/module.prop")
            appendLine("  BASE=/system/etc/hosts")
            appendLine("  [ -f \$BASE ] || BASE=/etc/hosts")
            appendLine("  if [ -f \$MOD/system/etc/hosts ]; then")
            appendLine("    sed -i '/HYDRA-AI-DNS-BEGIN/,/HYDRA-AI-DNS-END/d' \$MOD/system/etc/hosts 2>/dev/null || true")
            appendLine("  else")
            appendLine("    cp \$BASE \$MOD/system/etc/hosts 2>/dev/null || echo '127.0.0.1 localhost' > \$MOD/system/etc/hosts")
            appendLine("  fi")
            appendLine("  cat \$BLOCK >> \$MOD/system/etc/hosts")
            appendLine("  chmod 644 \$MOD/system/etc/hosts")
            appendLine("fi")
            appendLine("echo OK")
        }
        val (code, out) = RootHelper.su(listOf(script), timeoutMs = 15000)
        Log.i(TAG, "writeHosts code=$code out=$out")
        return code == 0 && out.contains("OK")
    }

    
    data class AiOnlyResult(
        val ok: Boolean,
        val message: String,
        val hits: Int,
        val hosts: Boolean,
        val localDns: Boolean,
        val redirect: Boolean
    )

    /**
     * Режим «только ИИ»:
     * 1) DoH-карта доменов
     * 2) hosts (root) — лучший узкий путь
     * 3) LocalDns + (root) iptables REDIRECT 53→local
     * Не трогает системный Private DNS.
     */
    fun activateAiOnly(
        ctx: Context,
        providerId: String,
        serviceIds: Set<String>,
        onDone: (AiOnlyResult) -> Unit
    ) {
        resolveAll(ctx, providerId, serviceIds) { ok, msg, hits ->
            if (!ok || hits.isEmpty()) {
                onDone(AiOnlyResult(false, "Нет карты: $msg", 0, false, false, false))
                return@resolveAll
            }
            LocalDnsServer.setMap(hits)
            var hosts = false
            var redir = false
            if (RootHelper.hasRoot()) {
                hosts = writeHosts(hits)
                // Local DNS + redirect, даже если hosts ок (на случай systemless delay)
                LocalDnsServer.start(null)
                try { Thread.sleep(300) } catch (_: Exception) {}
                val port = LocalDnsServer.boundPort.takeIf { it > 0 } ?: LocalDnsServer.FALLBACK_PORT
                redir = RootHelper.enableDnsRedirect(if (port == 53) 53 else LocalDnsServer.FALLBACK_PORT)
            } else {
                LocalDnsServer.start(null)
            }
            try { Thread.sleep(300) } catch (_: Exception) {}
            val local = LocalDnsServer.mapSize() > 0
            val parts = mutableListOf<String>()
            parts.add("имён ${hits.size}")
            if (hosts) parts.add("hosts")
            if (redir) parts.add("redirect :${LocalDnsServer.boundPort}")
            else if (local) parts.add("local DNS :${LocalDnsServer.boundPort} (нужен VPN или root redirect)")
            val needVpn = !hosts && !redir
            val hint = if (needVpn) " · включи/переподключи VPN" else " · Private DNS лучше выкл"
            onDone(
                AiOnlyResult(
                    true,
                    "Только ИИ: " + parts.joinToString(", ") + hint,
                    hits.size,
                    hosts,
                    local,
                    redir
                )
            )
        }
    }


    fun clearHosts(): Boolean {
        if (!RootHelper.hasRoot()) return false
        val script = """
            MOD=/data/adb/modules/hosts/system/etc/hosts
            for H in ${'$'}MOD /system/etc/hosts /etc/hosts; do
              [ -f "${'$'}H" ] || continue
              sed -i '/HYDRA-AI-DNS-BEGIN/,/HYDRA-AI-DNS-END/d' "${'$'}H" 2>/dev/null || true
            done
            echo OK
        """.trimIndent()
        return RootHelper.su(listOf(script)).first == 0
    }
}
