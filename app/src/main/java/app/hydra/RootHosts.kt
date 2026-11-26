package app.hydra

import android.content.Context
import java.io.File
import java.util.concurrent.Executors

/**
 * «Живой hosts» (root): свой hosts (системный без чужих блоков + карта Гидры) монтируется поверх /system/etc/hosts
 * без перезагрузки и без модуля Magisk. Файлу нужна метка SELinux system_file, иначе системная служба DNS его игнорирует.
 * Обновления пишутся в тот же файл (тот же inode), поэтому перемонтировать не нужно.
 * После применения Гидра сама читает /system/etc/hosts из СВОЕГО процесса: если блока там нет, приложения монтирование не видят.
 * Весь ход работы (какой su, есть ли nsenter, что смонтировано) возвращается подробным текстом — его видно в статусе и в журнале.
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

    private fun block(ctx: Context, empty: Boolean): String {
        val sb = StringBuilder("# HYDRA-LIVE-BEGIN\n")
        if (!empty) for (l in AiDns.overrideText(ctx).lines()) {
            val d = l.substringBefore('=').trim()
            if (d.isEmpty() || d.startsWith("*") || !d.contains('.')) continue
            val ips = l.substringAfter('=', "").split(',').map { it.trim() }.filter { it.matches(ipRe) }
            for (ip in ips.take(2)) sb.append(ip).append(' ').append(d).append('\n')
        }
        sb.append("# HYDRA-LIVE-END\n")
        return sb.toString()
    }

    /** § в тексте скрипта = знак доллара (чтобы не путаться с шаблонами Kotlin). */
    private fun script(blkPath: String): String = """
F=$F
B=$B
BLK=$blkPath
echo "su uid: §(id -u)"
MY=§(readlink /proc/self/ns/mnt); INIT=§(readlink /proc/1/ns/mnt)
echo "пространство имён: su=§MY init=§INIT"
if command -v nsenter >/dev/null 2>&1; then NS="nsenter --mount=/proc/1/ns/mnt --"; echo "nsenter: есть"; else NS=""; echo "nsenter: нет — монтирую напрямую"; fi
MNT=§(§NS grep -cF hydra.hosts /proc/self/mountinfo 2>/dev/null); [ -z "§MNT" ] && MNT=0
echo "наших монтирований до: §MNT"
sed -i '/HYDRA-AI-DNS-BEGIN/,/HYDRA-AI-DNS-END/d' /data/adb/modules/hosts/system/etc/hosts 2>/dev/null
if [ "§MNT" = "0" ]; then
  cp /system/etc/hosts §B 2>/dev/null
  [ -s §B ] || printf '127.0.0.1 localhost\n::1 ip6-localhost\n' > §B
  sed -i '/HYDRA-AI-DNS-BEGIN/,/HYDRA-AI-DNS-END/d;/HYDRA-LIVE-BEGIN/,/HYDRA-LIVE-END/d' §B
fi
cat §B §BLK > §F.tmp
if [ "§MNT" = "0" ]; then
  cp §F.tmp §F; chmod 644 §F; chcon u:object_r:system_file:s0 §F 2>&1
  §NS mount --bind §F /system/etc/hosts 2>&1
else
  cat §F.tmp > §F
fi
echo "наших монтирований после: §(§NS grep -cF hydra.hosts /proc/self/mountinfo 2>/dev/null)"
echo "блок в hosts (глазами init): §(§NS grep -c HYDRA-LIVE-BEGIN /system/etc/hosts 2>/dev/null)"
echo "метка: §(ls -Z /system/etc/hosts 2>&1 | head -1) selinux=§(getenforce 2>&1)"
echo END
""".trim().replace('§', '$')

    private fun appSees(): Boolean = try { File("/system/etc/hosts").readText().contains("HYDRA-LIVE-BEGIN") } catch (_: Throwable) { false }

    private fun run(ctx: Context, empty: Boolean): Pair<Boolean, String> {
        if (!RootHelper.hasRoot()) return false to "root недоступен"
        val blkFile = File(ctx.filesDir, "hydra.hosts.blk")
        val blk = block(ctx, empty)
        blkFile.writeText(blk)
        val (code, out) = RootHelper.su(listOf(script(blkFile.absolutePath)), timeoutMs = 20000)
        val inInit = Regex("""глазами init\): (\d+)""").find(out)?.groupValues?.get(1)?.toIntOrNull() ?: 0
        val visible = appSees()
        val ok = code == 0 && inInit >= 1
        val records = blk.lines().count { it.isNotBlank() && !it.startsWith("#") }
        val head = when {
            ok && visible -> "Живой hosts включён: $records записей, приложения его видят"
            ok -> "Смонтировано, но приложения hosts НЕ видят (прошивка изолирует монтирование). Подробности ниже"
            else -> "Живой hosts не встал. Подробности ниже"
        }
        lastOk = ok && visible
        return lastOk to head + "\n" + out.lines().filter { it != "END" }.joinToString("\n")
    }

    /** Применить (или проверить) живой hosts. force — игнорировать «ничего не менялось». */
    fun syncAsync(ctx: Context, force: Boolean = false, onDone: (String) -> Unit = {}) {
        if (!enabled(ctx)) return
        val app = ctx.applicationContext
        ex.execute {
            try {
                val h = block(app, false).hashCode()
                if (!force && h == lastHash && lastOk) { onDone(lastMessage); return@execute }
                val (ok, msg) = run(app, false)
                if (ok) lastHash = h
                lastMessage = msg
                try { mobile.Mobile.logLine("🧷 " + msg.replace("\n", " | ")) } catch (_: Throwable) {}
                onDone(msg)
            } catch (t: Throwable) { lastMessage = "Живой hosts: ${t.message}"; onDone(lastMessage) }
        }
    }

    /** Убрать из hosts всё старое от Гидры (в т.ч. блок «Только домены ИИ»), независимо от переключателя; остаётся чистый hosts. */
    fun cleanNow(ctx: Context, onDone: (String) -> Unit = {}) {
        val app = ctx.applicationContext
        ex.execute {
            try {
                val (_, msg) = run(app, true)
                try { mobile.Mobile.logLine("🧹 " + msg.replace("\n", " | ")) } catch (_: Throwable) {}
                onDone(msg)
            } catch (t: Throwable) { onDone("hosts: ${t.message}") }
        }
    }

    fun removeAsync(onDone: (String) -> Unit = {}) {
        ex.execute {
            try {
                if (!RootHelper.hasRoot()) { onDone("нет root"); return@execute }
                val s = """
if command -v nsenter >/dev/null 2>&1; then NS="nsenter --mount=/proc/1/ns/mnt --"; else NS=""; fi
for i in 1 2 3; do C=§(§NS grep -cF hydra.hosts /proc/self/mountinfo 2>/dev/null); [ -z "§C" -o "§C" = "0" ] && break; §NS umount /system/etc/hosts; done
rm -f $F $F.tmp $B
echo REMOVED
""".trim().replace('§', '$')
                val (_, out) = RootHelper.su(listOf(s), timeoutMs = 15000)
                lastHash = 0; lastOk = false
                lastMessage = if (out.contains("REMOVED")) "Живой hosts выключен" else "Не удалось снять: " + out.trim().take(160)
                onDone(lastMessage)
            } catch (t: Throwable) { onDone("hosts: ${t.message}") }
        }
    }
}
