package app.hydra

import android.app.Application
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter

/**
 * Запоминает причину вылета приложения. На приставках Android TV нет ни отладки, ни привычных способов снять журнал,
 * поэтому текст ошибки пишется в файл: в отчёт («последний вылет приложения») и в папку приложения
 * Android/data/<пакет>/files/hydra_crash.txt, которую открывает любой файловый менеджер.
 */
class HydraApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // умное обслуживание: списки, приоритеты операторов, автопоиск обхода ИИ — сразу при запуске приложения
        Thread {
            try {
                AiDns.reload(this)
                Priors.load(this)
                AppPreset.ensure(this)
                AiDns.startAuto(this)
            } catch (_: Throwable) {}
        }.start()
        val old = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            try {
                val sw = StringWriter()
                e.printStackTrace(PrintWriter(sw))
                val text = "Hydra: вылет " + java.util.Date() + " (поток " + t.name + ")\n" +
                    "устройство: " + android.os.Build.MANUFACTURER + " " + android.os.Build.MODEL +
                    ", Android " + android.os.Build.VERSION.RELEASE + " (API " + android.os.Build.VERSION.SDK_INT + ")" +
                    ", ABI " + android.os.Build.SUPPORTED_ABIS.joinToString(",") + "\n\n" + sw.toString()
                File(filesDir, "last_crash.txt").writeText(text)
                getExternalFilesDir(null)?.let { File(it, "hydra_crash.txt").writeText(text) }
            } catch (x: Throwable) {
            }
            old?.uncaughtException(t, e)
        }
    }
}
