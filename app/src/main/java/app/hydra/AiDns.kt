package app.hydra

import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.util.Log
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.Callable
import java.util.concurrent.Future

/**
 * Обход ИИ через DNS, который подменяет имена на IP «прокси».
 *
 * Рабочий путь (как у системного «Частный DNS»):
 *   private_dns_mode=hostname + private_dns_specifier=<хост DoT>
 * Без root — открываем системный экран и копируем hostname.
 * С root / WRITE_SECURE_SETTINGS — пишем сами.
 *
 * Дополнительно: проверка провайдеров (живой DoH? что открывает?).
 */
object AiDns {
    private const val TAG = "HydraAiDns"
    private val io = Executors.newCachedThreadPool()

    data class Provider(
        val id: String,
        val title: String,
        /** Hostname для Android Private DNS (DoT). */
        val hostname: String,
        /** DoH JSON endpoint для проверок. */
        val dohUrl: String,
        val note: String = ""
    )

    data class Service(
        val id: String,
        val title: String,
        /** Главное имя для пробы (достаточно одного «репрезентативного»). */
        val probeDomain: String,
        val domains: List<String>
    )

    data class ResolveHit(
        val domain: String,
        val ip: String,
        val isProxyGuess: Boolean
    )

    /** Результат проверки одного провайдера. */
    data class ProviderProbe(
        val providerId: String,
        val alive: Boolean,
        val latencyMs: Long,
        /** serviceId → открывает ли (подмена относительно Cloudflare). */
        val bypass: Map<String, Boolean>,
        val detail: String
    )

    val providers = listOf(
        Provider("geodema", "Geodema Smart DNS", "dns.geodema.love", "https://dns.geodema.love/dns-query"),
        Provider("keyoneday", "Keyoneday DNS", "dns.keyoneday.ru", "https://dns.keyoneday.ru/dns-query"),
        Provider("wlrus", "WLRus DNS", "dns.wlrus.cfd", "https://dns.wlrus.cfd/dns-query"),
        Provider("geohide", "GeoHide RU", "geohide.ru", "https://geohide.ru/dns-query"),
        Provider("dnsai", "DNS-AI.RU", "dns.dns-ai.ru", "https://dns.dns-ai.ru/dns-query"),
        Provider("magic", "MagicDNS", "magicdns.ru", "https://magicdns.ru/dns-query", "если отвечает"),
        Provider("cloudflare", "Cloudflare (контроль)", "one.one.one.one", "https://cloudflare-dns.com/dns-query", "без подмены"),
    )

    val services = listOf(
        Service("chatgpt", "ChatGPT", "chatgpt.com", listOf(
            "chatgpt.com", "www.chatgpt.com", "chat.openai.com", "api.openai.com",
            "ab.chatgpt.com", "cdn.oaistatic.com"
        )),
        Service("claude", "Claude", "claude.ai", listOf(
            "claude.ai", "www.claude.ai", "api.anthropic.com"
        )),
        Service("grok", "Grok", "grok.com", listOf(
            "grok.com", "www.grok.com", "x.ai", "api.x.ai"
        )),
        Service("gemini", "Gemini", "gemini.google.com", listOf(
            "gemini.google.com", "aistudio.google.com"
        )),
        Service("copilot", "Copilot", "copilot.microsoft.com", listOf(
            "copilot.microsoft.com"
        )),
        Service("perplexity", "Perplexity", "www.perplexity.ai", listOf(
            "www.perplexity.ai", "perplexity.ai"
        )),
    )

    fun provider(id: String) = providers.find { it.id == id } ?: providers.first()

    // ─── DoH resolve ───────────────────────────────────────────

    fun dohA(dohUrl: String, name: String, timeoutMs: Int = 8000): List<String> {
        val url = dohUrl.trimEnd('?') +
            (if (dohUrl.contains('?')) "&" else "?") +
            "name=" + URLEncoder.encode(name, "UTF-8") + "&type=A"
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = timeoutMs
            readTimeout = timeoutMs
            setRequestProperty("Accept", "application/dns-json")
            instanceFollowRedirects = true
        }
        return try {
            val code = conn.responseCode
            if (code !in 200..299) return emptyList()
            val body = conn.inputStream.bufferedReader().readText()
            val json = JSONObject(body)
            val ans = json.optJSONArray("Answer") ?: return emptyList()
            buildList {
                for (i in 0 until ans.length()) {
                    val o = ans.getJSONObject(i)
                    if (o.optInt("type") == 1) {
                        val data = o.optString("data")
                        if (data.matches(Regex("""\d{1,3}(\.\d{1,3}){3}"""))) add(data)
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "dohA $name via $dohUrl: ${e.message}")
            emptyList()
        } finally {
            conn.disconnect()
        }
    }

    private fun looksLikeProxy(ip: String, baseline: Set<String>): Boolean {
        if (ip in baseline) return false
        // RFC1918 / CGNAT / link-local — не прокси для ИИ
        if (ip.startsWith("10.") || ip.startsWith("192.168.") || ip.startsWith("127.")) return false
        if (ip.startsWith("172.")) {
            val second = ip.split(".").getOrNull(1)?.toIntOrNull() ?: 0
            if (second in 16..31) return false
        }
        return true
    }

    private fun tcpReachable(ip: String, port: Int = 443, timeoutMs: Int = 2500): Boolean {
        return try {
            Socket().use { s ->
                s.connect(InetSocketAddress(ip, port), timeoutMs)
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    // ─── Probe providers ───────────────────────────────────────

    /**
     * Проверяет все (или выбранные) провайдеры:
     * - отвечает ли DoH
     * - для каждого ИИ-сервиса: IP отличается от Cloudflare и (желательно) :443 жив
     */
    fun probeProviders(
        providerIds: List<String> = providers.map { it.id },
        serviceIds: List<String> = services.map { it.id },
        onDone: (List<ProviderProbe>) -> Unit
    ) {
        io.execute {
            val baseline = mutableMapOf<String, Set<String>>()
            val cf = provider("cloudflare")
            for (svc in services.filter { it.id in serviceIds }) {
                baseline[svc.id] = dohA(cf.dohUrl, svc.probeDomain).toSet()
            }
            val jobs = providerIds.map { pid ->
                io.submit(Callable {
                    val p = provider(pid)
                    val t0 = System.currentTimeMillis()
                    val testIps = dohA(p.dohUrl, "example.com")
                    val alive = testIps.isNotEmpty() || dohA(p.dohUrl, "cloudflare.com").isNotEmpty()
                    val latency = System.currentTimeMillis() - t0
                    if (!alive) {
                        return@Callable ProviderProbe(pid, false, latency, emptyMap(), "DoH не отвечает")
                    }
                    val bypass = linkedMapOf<String, Boolean>()
                    val notes = mutableListOf<String>()
                    for (svc in services.filter { it.id in serviceIds }) {
                        val ips = dohA(p.dohUrl, svc.probeDomain)
                        val base = baseline[svc.id] ?: emptySet()
                        if (ips.isEmpty()) {
                            bypass[svc.id] = false
                            notes.add("${svc.title}: нет A")
                            continue
                        }
                        val proxy = ips.any { looksLikeProxy(it, base) }
                        val reach = if (proxy) ips.any { tcpReachable(it) } else false
                        // считаем «обходит», если IP не как у CF (подмена). TCP — бонус в detail
                        bypass[svc.id] = proxy
                        val mark = when {
                            proxy && reach -> "✔"
                            proxy -> "△" // подмена есть, :443 с телефона не ответил (часто норма)
                            else -> "✘"
                        }
                        notes.add("${svc.title}: $mark ${ips.first()}")
                    }
                    val open = bypass.filter { it.value }.keys
                    val detail = if (open.isEmpty()) {
                        "живой, но подмены ИИ нет · " + notes.joinToString("; ")
                    } else {
                        "обходит: " + open.joinToString { id -> services.find { it.id == id }?.title ?: id } +
                            " · " + notes.joinToString("; ")
                    }
                    ProviderProbe(pid, true, latency, bypass, detail)
                })
            }
            val results = jobs.mapNotNull { f ->
                try {
                    f.get(60, TimeUnit.SECONDS)
                } catch (e: Exception) {
                    Log.e(TAG, "probe", e)
                    null
                }
            }
            onDone(results)
        }
    }

    fun pickBest(probes: List<ProviderProbe>, preferService: String = "chatgpt"): Provider? {
        val scored = probes.filter { it.alive && it.providerId != "cloudflare" }.map { pr ->
            val score = pr.bypass.values.count { it } * 10 +
                (if (pr.bypass[preferService] == true) 5 else 0) -
                (pr.latencyMs / 100).toInt()
            pr to score
        }.sortedByDescending { it.second }
        return scored.firstOrNull()?.let { provider(it.first.providerId) }
    }

    // ─── Private DNS apply ─────────────────────────────────────

    data class ApplyResult(val ok: Boolean, val method: String, val message: String)

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
                    baseline[svc.probeDomain] = dohA(cf.dohUrl, svc.probeDomain).toSet()
                }
                val all = mutableListOf<ResolveHit>()
                for (svc in services.filter { it.id in serviceIds }) {
                    for (d in svc.domains) {
                        val ips = dohA(p.dohUrl, d)
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
