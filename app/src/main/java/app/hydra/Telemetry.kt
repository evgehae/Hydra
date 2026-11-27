package app.hydra

import android.content.Context
import android.os.Build
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

/**
 * Анонимный обмен опытом (только по согласию пользователя). Раз в сутки Гидра отправляет сборщику технические данные:
 * какие стратегии/порты/дата-центры работали в сети данного типа, какие DNS-серверы открывали ИИ и игры.
 * НЕ отправляется: IP-адрес пользователя, название Wi-Fi, список приложений, содержимое трафика, номер телефона.
 * Идентификатор установки — случайный UUID, не связанный с устройством; нужен только чтобы не принимать дубли за сутки.
 */
object Telemetry {
    /** Адрес сборщика (Cloudflare Worker из папки collector/). После развёртывания впиши сюда свой адрес. */
    private const val DEFAULT_URL = "https://hydra-collect.example.workers.dev/v1/submit"

    @Volatile private var lastCheck = 0L

    fun url(ctx: Context): String = Ext.str(ctx, "collect_url").ifBlank { DEFAULT_URL }
    fun enabled(ctx: Context) = Ext.bool(ctx, "share_auto", false)
    fun setEnabled(ctx: Context, v: Boolean) { Ext.setBool(ctx, "share_auto", v); Ext.setBool(ctx, "share_asked", true) }
    fun needAsk(ctx: Context) = !Ext.bool(ctx, "share_asked", false)
    fun markAsked(ctx: Context) = Ext.setBool(ctx, "share_asked", true)
    fun lastSent(ctx: Context): Long = Ext.long(ctx, "share_last")

    private fun installId(ctx: Context): String {
        var id = Ext.str(ctx, "install_id")
        if (id.isBlank()) { id = UUID.randomUUID().toString(); Ext.setStr(ctx, "install_id", id) }
        return id
    }

    /** Ровно то, что уходит на сервер: пользователь может посмотреть это в настройках. */
    fun buildPayload(ctx: Context): String {
        val prefs = Prefs(ctx)
        val o = JSONObject()
        o.put("v", 1)
        o.put("id", installId(ctx))
        o.put("ts", System.currentTimeMillis() / 1000)
        o.put("app", try { ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName ?: "" } catch (_: Throwable) { "" })
        o.put("android", Build.VERSION.SDK_INT)
        o.put("vendor", Build.MANUFACTURER ?: "")
        o.put("tv", ctx.packageManager.hasSystemFeature("android.software.leanback"))
        o.put("settings", JSONObject()
            .put("protocol", prefs.protocol).put("channel", prefs.channel).put("parallel", prefs.parallel)
            .put("blockedColos", prefs.blockedColos).put("allowColos", prefs.allowColos).put("ipv6", prefs.ipv6)
            .put("tgGate", prefs.tgGate).put("ytGate", prefs.ytGate))
        o.put("priors", try { JSONObject(Priors.export()) } catch (_: Throwable) { JSONObject() })
        // DNS-серверы для ИИ и игр: какой сервер какой сервис открывал (публичные адреса серверов, не пользователя)
        val ai = JSONObject()
        try {
            for (pr in AiDns.loadProbes(ctx)) {
                ai.put(pr.providerId, JSONObject().put("alive", pr.alive).put("ms", pr.latencyMs)
                    .put("marks", JSONObject(pr.marks as Map<*, *>)))
            }
        } catch (_: Throwable) {}
        o.put("ai", ai)
        return o.toString()
    }

    fun sendNow(ctx: Context, onDone: (String) -> Unit = {}) {
        val app = ctx.applicationContext
        Thread {
            val msg = try {
                val body = buildPayload(app).toByteArray(Charsets.UTF_8)
                val c = (URL(url(app)).openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"; doOutput = true
                    connectTimeout = 10000; readTimeout = 15000
                    setRequestProperty("Content-Type", "application/json")
                }
                try {
                    c.outputStream.use { it.write(body) }
                    if (c.responseCode in 200..299) {
                        Ext.setLong(app, "share_last", System.currentTimeMillis())
                        "Опыт отправлен, спасибо!"
                    } else "Сервер ответил ${c.responseCode}"
                } finally { c.disconnect() }
            } catch (t: Throwable) { "Не отправлено: ${t.message}" }
            android.os.Handler(android.os.Looper.getMainLooper()).post { onDone(msg) }   // ответ — в главном потоке (для Toast)
        }.start()
    }

    /** Раз в сутки (если включено и есть сеть). Дешёвая проверка — можно вызывать часто. */
    fun maybeSend(ctx: Context) {
        val now = System.currentTimeMillis()
        if (now - lastCheck < 10 * 60_000L) return
        lastCheck = now
        if (!enabled(ctx)) return
        if (now - lastSent(ctx) < 24 * 3600_000L) return
        sendNow(ctx)
    }
}
