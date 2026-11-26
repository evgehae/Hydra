package app.hydra

import android.content.Context
import java.util.concurrent.Executors

/**
 * «Живой hosts» (root): Гидра собирает свой hosts (системный без чужих блоков + текущая карта адресов) и монтирует его
 * поверх /system/etc/hosts в общем пространстве имён (nsenter в init). Без перезагрузки и без модуля Magisk.
 * Ключевое: файлу нужна метка SELinux system_file, иначе системная служба DNS его молча игнорирует.
 * Обновление идёт ЗАПИСЬЮ В ТОТ ЖЕ ФАЙЛ (тот же inode), поэтому перемонтировать не нужно — изменения видны сразу.
 * Монитор: проверка при каждом обновлении карты и каждые 5 минут (после перезагрузки монтирование пропадает — ставим заново).
 */
object RootHosts {
    private const val F = "/data/local/tmp/hydra.hosts"
    private const val B = "/data/local/tmp/hydra.hosts.base"
    private const val KEY = "live_hosts"
    private val ex = Executors.newSingleThreadExecutor()
    @Volatile private var lastHash = 0
    @Volatile private var lastOk = false
    @Volatile var lastMessage = ""
        private set

    fun enabled(ctx: Context) = Ext.bool(ctx, KEY, false)

    fun setEnabled(ctx: Context, v: Boolean, onDone: (String) -> Unit = {}) {
        Ext.setBool(ctx, KEY, v)
        if (v) syncAsync(ctx, force = true, onDone = onDone) else removeAsync(onDone)
    }

    private val ipRe = Regex("""\d{1,3}(\.\d{1,3}){3}""")

    /** Блок hosts из карты Гидры: «домен=ip1,ip2» → «ip домен» (подстановочные *.домен в hosts невозможны, пропускаем). */
    private fun block(ctx: Context): String {
        val sb = StringBuilder("# HYDRA-LIVE-BEGIN\n")
        for (l in AiDns.overrideText(ctx).lines()) {
            val d = l.substringBefore('=').trim()
            if (d.isEmpty() || d.startsWith("*") || !d.contains('.')) continue
            val ips = l.substringAfter('=', "").split(',').map { it.trim() }.filter { it.matches(ipRe) }
            for (ip in ips.take(2)) sb.append(ip).append(' ').append(d).append('\n')
        }
        sb.append("# HYDRA-LIVE-END\n")
        return sb.toString()
    }

    private fun applyScript(blk: String): String {
        val d = "$"
        val L = ArrayList<String>()
        L += "F=$F"
        L += "B=$B"
        L += "NS=\"nsenter --mount=/proc/1/ns/mnt --\""
        L += "MNT=${d}(${d}NS grep -cF hydra.hosts /proc/self/mountinfo 2>/dev/null)"
        L += "[ -z \"${d}MNT\" ] && MNT=0"
        L += "if [ \"${d}MNT\" = \"0\" ]; then"
        L += "  cp /system/etc/hosts ${d}B 2>/dev/null"
        L += "  sed -i '/HYDRA-AI-DNS-BEGIN/,/HYDRA-AI-DNS-END/d;/HYDRA-LIVE-BEGIN/,/HYDRA-LIVE-END/d' ${d}B"
        L += "fi"
        L += "cat > ${d}F.blk <<'HYDRAEOF'"
        L += blk.trimEnd('\n')
        L += "HYDRAEOF"
        L += "cat ${d}B ${d}F.blk > ${d}F.tmp"
        L += "if [ \"${d}MNT\" = \"0\" ]; then"
        L += "  cp ${d}F.tmp ${d}F"
        L += "  chmod 644 ${d}F"
        L += "  chcon u:object_r:system_file:s0 ${d}F"
        L += "  ${d}NS mount --bind ${d}F /system/etc/hosts"
        L += "else"
        L += "  cat ${d}F.tmp > ${d}F"
        L += "fi"
        L += "N=${d}(${d}NS grep -c HYDRA-LIVE-BEGIN /system/etc/hosts 2>/dev/null)"
        L += "echo \"LIVE:${d}N\""
        return L.joinToString("\n")
    }

    /** Применить (или проверить) живой hosts. force — игнорировать «ничего не менялось». */
    fun syncAsync(ctx: Context, force: Boolean = false, onDone: (String) -> Unit = {}) {
        if (!enabled(ctx)) { return }
        val app = ctx.applicationContext
        ex.execute {
            try {
                if (!RootHelper.hasRoot()) { lastMessage = "нет root"; onDone(lastMessage); return@execute }
                val blk = block(app)
                val h = blk.hashCode()
                if (!force && h == lastHash && lastOk) { onDone(lastMessage); return@execute }
                val (code, out) = RootHelper.su(listOf(applyScript(blk)), timeoutMs = 15000)
                lastOk = code == 0 && out.contains("LIVE:1")
                if (lastOk) lastHash = h
                lastMessage = if (lastOk) "Живой hosts включён: ${blk.lines().count { it.isNotBlank() && !it.startsWith("#") }} записей"
                    else "Живой hosts не встал: " + out.trim().take(200)
                try { mobile.Mobile.logLine("🧷 $lastMessage") } catch (_: Throwable) {}
                onDone(lastMessage)
            } catch (t: Throwable) { lastMessage = "Живой hosts: ${t.message}"; onDone(lastMessage) }
        }
    }

    fun removeAsync(onDone: (String) -> Unit = {}) {
        ex.execute {
            try {
                if (!RootHelper.hasRoot()) { onDone("нет root"); return@execute }
                val d = "$"
                val s = listOf(
                    "NS=\"nsenter --mount=/proc/1/ns/mnt --\"",
                    "for i in 1 2 3; do C=${d}(${d}NS grep -cF hydra.hosts /proc/self/mountinfo 2>/dev/null); [ -z \"${d}C\" -o \"${d}C\" = \"0\" ] && break; ${d}NS umount /system/etc/hosts; done",
                    "rm -f $F $F.tmp $F.blk $B",
                    "echo REMOVED"
                ).joinToString("\n")
                val (_, out) = RootHelper.su(listOf(s), timeoutMs = 15000)
                lastHash = 0; lastOk = false
                lastMessage = if (out.contains("REMOVED")) "Живой hosts выключен" else "Не удалось снять: " + out.trim().take(120)
                onDone(lastMessage)
            } catch (t: Throwable) { onDone("Живой hosts: ${t.message}") }
        }
    }
}
