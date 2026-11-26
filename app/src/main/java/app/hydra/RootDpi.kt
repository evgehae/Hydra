package app.hydra

import android.content.Context

/**
 * Root-управление модулем nfqws2-android-ext (zapret2, обход DPI на уровне ядра, NFQUEUE) — для 4PDA и всего, что режется по SNI.
 * Модуль ставится отдельно через Magisk/KernelSU (MIT, github.com/SpectaCoolAre/nfqws2-android-ext); Гидра им управляет:
 * включает, держит рабочим при включённом VPN (по умолчанию модуль уходит на паузу, пока есть VPN), добавляет домены 4PDA
 * и выводит клиент 4PDA из туннеля Гидры — иначе его трафик шифруется туннелем, и до nfqws2 не доходит.
 */
object RootDpi {
    private val modules = listOf("nfqws2-android-ext", "nfqws2-android")
    const val PKG_4PDA = "ru.fourpda.client"
    private val domains4pda = listOf("4pda.to", "www.4pda.to", "4pda.ws", "4pda.ru", "s.4pda.to", "cdn.4pda.to", "appbk.4pda.to")

    data class Info(val rootOk: Boolean, val installed: Boolean, val ctl: String, val running: Boolean, val text: String)

    fun detect(): Info {
        if (!RootHelper.hasRoot()) return Info(false, false, "", false, "root не найден")
        for (m in modules) {
            val ctl = "/data/adb/modules/$m/bin/nfqws2-ctl"
            val (_, o) = RootHelper.suOne("[ -f $ctl ] && echo yes")
            if (o.contains("yes")) {
                val (_, r) = RootHelper.suOne("sh $ctl is-running >/dev/null 2>&1 && echo RUN || echo STOP")
                val run = r.contains("RUN")
                return Info(true, true, ctl, run, "модуль $m: " + if (run) "работает" else "остановлен")
            }
        }
        return Info(true, false, "", false, "модуль nfqws2-android-ext не найден — установи его через Magisk/KernelSU")
    }

    private fun ctl(ctl: String, args: String): String = RootHelper.suOne("sh $ctl $args").second

    /** Включить обход для 4PDA и работать вместе с VPN. */
    fun ensure4pda(ctx: Context): String {
        val i = detect()
        if (!i.installed) return i.text
        val sb = StringBuilder()
        ctl(i.ctl, "set VPN_PAUSE 0")            // не уходить на паузу, пока включён VPN Гидры
        for (d in domains4pda) ctl(i.ctl, "add-domain $d")
        if (!i.running) { ctl(i.ctl, "start"); sb.append("модуль запущен; ") }
        else ctl(i.ctl, "reload")
        sb.append("4PDA добавлен в список, пауза при VPN выключена")
        Ext.setLong(ctx, "root_ensure_ts", System.currentTimeMillis())
        return sb.toString()
    }

    fun start(): String { val i = detect(); return if (i.installed) ctl(i.ctl, "start").ifBlank { "запущен" } else i.text }
    fun stop(): String { val i = detect(); return if (i.installed) ctl(i.ctl, "stop").ifBlank { "остановлен" } else i.text }

    /** Клиент 4PDA должен идти МИМО туннеля Гидры (трафик внутри туннеля nfqws2 не видит). */
    fun applyPolicy(ctx: Context) {
        if (!Ext.bool(ctx, "root4pda")) return
        try {
            val p = Prefs(ctx)
            val cur = p.splitApps
            if (p.splitOnlySelected) { if (PKG_4PDA in cur) p.splitApps = cur - PKG_4PDA }
            else if (PKG_4PDA !in cur) p.splitApps = cur + PKG_4PDA
        } catch (_: Throwable) {}
    }

    /** При старте VPN: если включено — проверить, что модуль жив и не на паузе (не чаще раза в 5 минут). */
    fun ensureAsync(ctx: Context) {
        if (!Ext.bool(ctx, "root4pda")) return
        if (System.currentTimeMillis() - Ext.long(ctx, "root_ensure_ts") < 5 * 60_000L) return
        Thread { try { ensure4pda(ctx.applicationContext) } catch (_: Throwable) {} }.start()
    }
}
