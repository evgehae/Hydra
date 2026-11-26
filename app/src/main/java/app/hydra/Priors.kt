package app.hydra

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Общая база опыта («priors»): что работает у разных операторов и в Wi-Fi.
 * Зашита в сборку (assets/priors.json), поверх неё раз в сутки подтягивается свежий priors.json из репозитория Гидры.
 * Новый пользователь с Билайном/МТС получает уже готовые подсказки с первого запуска; личный опыт сети всегда важнее.
 */
object Priors {
    private const val URL_API = "https://api.github.com/repos/evgehae/Hydra/contents/priors.json"

    fun load(ctx: Context) {
        try {
            val f = File(ctx.filesDir, "priors.json")
            val text = if (f.exists() && f.length() > 10) f.readText()
            else ctx.assets.open("priors.json").bufferedReader().readText()
            if (text.isNotBlank()) mobile.Mobile.setPriors(text)
        } catch (_: Throwable) {}
    }

    /** Раз в сутки: скачать свежий priors.json. Возвращает текст-итог или пусто, если рано. */
    fun maybeSync(ctx: Context, force: Boolean = false): String {
        val now = System.currentTimeMillis()
        if (!force && now - Ext.long(ctx, "priors_ts") < 24 * 3600_000L) return ""
        return try {
            val c = (URL(URL_API).openConnection() as HttpURLConnection).apply {
                connectTimeout = 8000; readTimeout = 12000
                setRequestProperty("Accept", "application/vnd.github.raw+json")
                setRequestProperty("User-Agent", "Hydra-Priors/1")
            }
            try {
                if (c.responseCode !in 200..299) return "priors: код ${c.responseCode}"
                val body = c.inputStream.bufferedReader().readText()
                if (body.length > 256 * 1024) return "priors: файл слишком большой"
                val o = JSONObject(body)
                if (o.length() == 0) return "priors: пусто"
                File(ctx.filesDir, "priors.json").writeText(body)
                Ext.setLong(ctx, "priors_ts", now)
                load(ctx)
                "priors обновлены: ${o.length()} сетей"
            } finally { c.disconnect() }
        } catch (e: Exception) { "priors: ${e.message}" }
    }

    /** Накопленный опыт этого телефона в формате priors.json — можно отправить автору, чтобы он попал в общую базу. */
    fun export(): String = try { mobile.Mobile.exportPriors() } catch (t: Throwable) { "{}" }
}
