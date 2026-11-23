package app.hydra

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.content.FileProvider
import android.os.Build
import android.provider.Settings
import org.json.JSONObject
import java.io.BufferedInputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Проверка обновлений через GitHub Releases.
 * CI после успешной сборки публикует APK в Release; приложение раз в сутки
 * (и при старте) спрашивает latest и предлагает установить.
 *
 * Репозиторий по умолчанию: DEFAULT_REPO = "evgehae/Hydra".
 * Пункт в настройках убран — обновления работают сами.
 */
object UpdateChecker {
    /** GitHub owner/repo. Зашито; пункт в настройках скрыт. */
    const val DEFAULT_REPO = "evgehae/Hydra"

    data class Info(
        val tag: String,
        val versionCode: Int,
        val name: String,
        val apkUrl: String,
        val body: String
    ) {
        /** Для UI: WARP CLAUDE 3.194 */
        fun marketingLabel(): String = "WARP CLAUDE 3.$versionCode"
    }

    private val io = Executors.newSingleThreadExecutor()

    fun currentVersionCode(ctx: Context): Int =
        try {
            val pi = if (Build.VERSION.SDK_INT >= 33)
                ctx.packageManager.getPackageInfo(ctx.packageName, PackageManager.PackageInfoFlags.of(0))
            else
                @Suppress("DEPRECATION") ctx.packageManager.getPackageInfo(ctx.packageName, 0)
            pi.longVersionCode.toInt()
        } catch (_: Throwable) {
            0
        }

    fun repo(ctx: Context): String {
        // Репозиторий зашит. Prefs.updateRepo больше не показывается в UI
        // и используется только если вдруг задан вручную (для тестов).
        val p = Prefs(ctx).updateRepo.trim()
        return if (p.contains('/')) p else DEFAULT_REPO
    }

    /**
     * @param force игнорировать «уже спрашивали сегодня»
     * @param onResult в UI-потоке: null если обновлений нет / ошибка сети без UI
     */
    fun check(ctx: Context, force: Boolean = false, onResult: (Info?) -> Unit) {
        val repo = repo(ctx)
        if (repo.isEmpty() || !repo.contains('/')) {
            onResult(null)
            return
        }
        val prefs = Prefs(ctx)
        val now = System.currentTimeMillis()
        if (!force && now - prefs.lastUpdateCheckAt < 12 * 60 * 60 * 1000L) {
            onResult(null)
            return
        }
        io.execute {
            val info = try {
                prefs.lastUpdateCheckAt = now
                fetchLatest(repo)
            } catch (_: Throwable) {
                null
            }
            val cur = currentVersionCode(ctx)
            val newer = info != null && info.versionCode > cur && info.apkUrl.isNotEmpty()
            // на главный поток
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                onResult(if (newer) info else null)
            }
        }
    }

    private fun fetchLatest(repo: String): Info? {
        val url = URL("https://api.github.com/repos/$repo/releases/latest")
        val c = (url.openConnection() as HttpURLConnection).apply {
            connectTimeout = 12000
            readTimeout = 15000
            setRequestProperty("Accept", "application/vnd.github+json")
            setRequestProperty("User-Agent", "Hydra-UpdateChecker")
        }
        try {
            if (c.responseCode !in 200..299) return null
            val body = c.inputStream.bufferedReader().readText()
            val j = JSONObject(body)
            val tag = j.optString("tag_name", "")
            val name = j.optString("name", tag)
            val notes = j.optString("body", "")
            // versionCode из tag: v123 или 123 или 1.0.123
            val code = Regex("(\\d{1,9})(?:\\D*)$").find(tag.replace(".", ""))
                ?.groupValues?.getOrNull(1)?.toIntOrNull()
                ?: Regex("(\\d+)").findAll(tag).lastOrNull()?.value?.toIntOrNull()
                ?: 0
            val assets = j.optJSONArray("assets") ?: return null
            var apkUrl = ""
            for (i in 0 until assets.length()) {
                val a = assets.getJSONObject(i)
                val n = a.optString("name", "")
                if (n.endsWith(".apk", true)) {
                    apkUrl = a.optString("browser_download_url", "")
                    if (apkUrl.isNotEmpty()) break
                }
            }
            if (apkUrl.isEmpty()) return null
            return Info(tag, code, name, apkUrl, notes)
        } finally {
            c.disconnect()
        }
    }

    /** Скачать APK во внутренний файл. */
    fun downloadApk(ctx: Context, url: String, onProgress: ((Int) -> Unit)? = null): java.io.File {
        val out = java.io.File(ctx.cacheDir, "hydra-update.apk")
        if (out.exists()) out.delete()
        var current = url
        var redirects = 0
        while (redirects < 8) {
            val c = (URL(current).openConnection() as HttpURLConnection).apply {
                connectTimeout = 20000
                readTimeout = 180000
                instanceFollowRedirects = false
                setRequestProperty("User-Agent", "Hydra-UpdateChecker")
                setRequestProperty("Accept", "application/octet-stream,*/*")
            }
            try {
                val code = c.responseCode
                if (code in 301..308) {
                    val loc = c.getHeaderField("Location") ?: break
                    current = if (loc.startsWith("http")) loc else URL(URL(current), loc).toString()
                    redirects++
                    continue
                }
                if (code !in 200..299) {
                    val err = try { c.errorStream?.bufferedReader()?.readText()?.take(200) } catch (_: Throwable) { null }
                    throw IllegalStateException("HTTP $code при скачивании APK" + (err?.let { ": $it" } ?: ""))
                }
                val len = c.contentLengthLong
                BufferedInputStream(c.inputStream).use { input ->
                    out.outputStream().use { output ->
                        val buf = ByteArray(8192)
                        var read = 0L
                        while (true) {
                            val n = input.read(buf)
                            if (n <= 0) break
                            output.write(buf, 0, n)
                            read += n
                            if (len > 0) onProgress?.invoke(((read * 100) / len).toInt().coerceIn(0, 100))
                        }
                    }
                }
                if (out.length() < 1000L) throw IllegalStateException("Скачан слишком маленький файл")
                return out
            } finally {
                c.disconnect()
            }
        }
        throw IllegalStateException("Слишком много редиректов")
    }

    fun canRequestInstall(ctx: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= 26)
            ctx.packageManager.canRequestPackageInstalls()
        else true
    }

    fun openUnknownSourcesSettings(ctx: Context) {
        val i = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${ctx.packageName}")
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ctx.startActivity(i)
    }

    /**
     * Установка через системный установщик (FileProvider + ACTION_VIEW).
     * Надёжнее PackageInstaller без Activity-callback на Xiaomi/TV.
     */
    fun installApk(ctx: Context, apk: java.io.File) {
        if (!apk.exists() || apk.length() < 1000L) {
            throw IllegalStateException("APK не скачался (файл пустой)")
        }
        val uri = try {
            androidx.core.content.FileProvider.getUriForFile(ctx, ctx.packageName + ".fileprovider", apk)
        } catch (e: Throwable) {
            // запасной путь: скопировать во внешний cache
            val ext = java.io.File(ctx.externalCacheDir ?: ctx.cacheDir, "hydra-update.apk")
            apk.copyTo(ext, overwrite = true)
            androidx.core.content.FileProvider.getUriForFile(ctx, ctx.packageName + ".fileprovider", ext)
        }
        val i = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        ctx.startActivity(i)
    }
}
