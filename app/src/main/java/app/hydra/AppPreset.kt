package app.hydra

import android.content.Context

/**
 * Приложения, которым туннель нужен всегда (ИИ, мессенджеры, YouTube, root-инструменты и т.п.).
 * При первом запуске и после обновления набора Гидра сама добавляет установленные из них в список туннеля.
 * Если пользователь потом убрал приложение вручную, второй раз оно не возвращается.
 * Lucky Patcher, клоны ИИ и т.п. меняют имя пакета при установке, поэтому их ищем ещё и по подписи.
 */
object AppPreset {
    private const val VERSION = 1

    private val packages = listOf(
        // ИИ
        "com.openai.chatgpt", "com.anthropic.claude", "ai.x.grok", "ai.x.grom", "ai.x.grol",
        "com.google.android.apps.bard", "com.deepseek.chat", "com.microsoft.copilot", "ai.perplexity.app.android",
        // мессенджеры, видео
        "org.telegram.messenger", "org.telegram.messenger.web", "org.telegram.plus", "org.thunderdog.challegram",
        "com.whatsapp", "com.whatsapp.w4b",
        "com.google.android.youtube", "app.revanced.android.youtube", "com.vanced.android.youtube",
        // YouTube на ТВ и его клиенты (SmartTube, YouTube Next и др.), плеер ottplay
        "com.google.android.youtube.tv", "org.smarttube.alex", "com.liskovsoft.smarttubetv", "com.liskovsoft.smarttubetv.beta",
        "com.teamsmart.videomanager.tv", "com.ottplay.ottplay",
        // сайты, которым нужен туннель
        "com.nkl.xnxx.nativeapp", "ru.fourpda.client",
        // root-инструменты
        "com.topjohnwu.magisk", "io.github.vvb2060.magisk", "io.github.a13e300.ksuwebui", "org.matrix.vector.manager",
        "org.lsposed.manager", "ru.dcghtvus.whpxteczs",
        // игры Supercell
        "com.supercell.clashofclans", "com.supercell.brawlstars", "com.supercell.clashroyale", "com.supercell.squadbusters"
    )

    /** Подписи (в нижнем регистре): приложение берём, если в подписи есть ВСЕ слова из группы. */
    private val labelGroups = listOf(
        listOf("lucky", "patcher"), listOf("grok"), listOf("magisk"), listOf("lsposed"), listOf("xnxx"),
        listOf("smarttube"), listOf("youtube"), listOf("ottplay")
    )

    private fun installed(ctx: Context, pkg: String): Boolean =
        try { ctx.packageManager.getPackageInfo(pkg, 0); true } catch (_: Exception) { false }

    /** Пакеты установленных приложений, в подписи которых есть все слова хотя бы из одной группы. */
    fun findByLabel(ctx: Context, groups: List<String>): List<String> {
        if (groups.isEmpty()) return emptyList()
        return scan(ctx, groups.map { listOf(it) })
    }

    private fun scan(ctx: Context, groups: List<List<String>>): List<String> {
        val res = ArrayList<String>()
        try {
            val pm = ctx.packageManager
            for (ai in pm.getInstalledApplications(0)) {
                if (ai.packageName == ctx.packageName) continue
                val label = try { pm.getApplicationLabel(ai).toString().lowercase() } catch (_: Exception) { continue }
                if (groups.any { g -> g.all { label.contains(it) } }) res.add(ai.packageName)
            }
        } catch (_: Throwable) {}
        return res
    }

    /** Добавить в туннель всё из набора, что установлено и ещё не предлагалось. Возвращает добавленные пакеты. */
    fun ensure(ctx: Context): List<String> {
        val prefs = Prefs(ctx)
        val offered = Ext.str(ctx, "preset_done").split(',').filter { it.isNotBlank() }.toMutableSet()
        val wanted = (packages.filter { installed(ctx, it) } + scan(ctx, labelGroups)).distinct()
        val fresh = wanted.filter { it !in offered }
        if (fresh.isEmpty()) return emptyList()
        val cur = prefs.splitApps
        if (prefs.splitOnlySelected) {
            val add = fresh.filter { it !in cur }
            if (add.isNotEmpty()) prefs.splitApps = cur + add
        } else {
            val del = fresh.filter { it in cur }
            if (del.isNotEmpty()) prefs.splitApps = cur - del.toSet()
        }
        offered.addAll(fresh)
        Ext.setStr(ctx, "preset_done", offered.joinToString(","))
        Ext.setLong(ctx, "preset_v", VERSION.toLong())
        return fresh
    }
}
