package app.hydra

import android.content.Context
import android.os.Environment
import java.io.File

/**
 * Экспорт/импорт через файл — на Android TV буфер обмена часто недоступен.
 * Пишем в два места: app-external (всегда можно) и Download (удобно с USB).
 */
object BackupIO {
    const val FILE_FULL = "hydra-backup.txt"
    const val FILE_ACCOUNT = "hydra-account.txt"

    /** Каталог, куда точно можно писать без разрешений. */
    fun appDir(ctx: Context): File {
        val d = ctx.getExternalFilesDir(null) ?: ctx.filesDir
        if (!d.exists()) d.mkdirs()
        return d
    }

    /** Публичный Download, если доступен (телефон / USB на ТВ). */
    fun downloadDir(): File? {
        return try {
            val d = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            if (d != null && (d.exists() || d.mkdirs()) && d.canWrite()) d else null
        } catch (_: Throwable) {
            null
        }
    }

    fun write(ctx: Context, name: String, text: String): String {
        val targets = mutableListOf<File>()
        targets += File(appDir(ctx), name)
        downloadDir()?.let { targets += File(it, name) }
        val ok = mutableListOf<String>()
        val err = mutableListOf<String>()
        for (f in targets) {
            try {
                f.parentFile?.mkdirs()
                f.writeText(text, Charsets.UTF_8)
                ok += f.absolutePath
            } catch (t: Throwable) {
                err += "${f.absolutePath}: ${t.message}"
            }
        }
        return buildString {
            if (ok.isNotEmpty()) {
                append("OK\n")
                ok.forEach { append("• $it\n") }
            } else {
                append("FAIL\n")
            }
            err.forEach { append("! $it\n") }
        }.trim()
    }

    fun read(ctx: Context, name: String): Pair<String?, String> {
        val candidates = mutableListOf<File>()
        downloadDir()?.let { candidates += File(it, name) }
        candidates += File(appDir(ctx), name)
        // иногда кладут рядом с APK / на корень USB
        try {
            candidates += File("/sdcard/Download", name)
            candidates += File("/storage/emulated/0/Download", name)
        } catch (_: Throwable) { }
        val tried = mutableListOf<String>()
        for (f in candidates) {
            tried += f.absolutePath
            try {
                if (f.isFile && f.canRead()) {
                    val t = f.readText(Charsets.UTF_8).trim()
                    if (t.isNotEmpty()) return t to "прочитано: ${f.absolutePath}"
                }
            } catch (_: Throwable) { }
        }
        return null to "файл не найден. Искал:\n" + tried.joinToString("\n") { "• $it" }
    }
}
