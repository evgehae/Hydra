package app.hydra

import android.content.Context

/** Дополнительные настройки патчей 10+ (отдельное хранилище, чтобы не трогать Prefs). */
object Ext {
    private fun sp(ctx: Context) = ctx.getSharedPreferences("hydra_ext", Context.MODE_PRIVATE)

    /** Семейство адресов: auto | v4 | v6 | both. */
    fun ipMode(ctx: Context): String = sp(ctx).getString("ip_mode", "auto") ?: "auto"
    fun setIpMode(ctx: Context, v: String) = sp(ctx).edit().putString("ip_mode", v).apply()

    /** Нужен ли IPv6 внутри туннеля (режимы «только IPv6» и «вместе»). */
    fun wantV6(ctx: Context): Boolean = ipMode(ctx).let { it == "v6" || it == "both" }

    fun bool(ctx: Context, key: String, def: Boolean = false): Boolean = sp(ctx).getBoolean(key, def)
    fun setBool(ctx: Context, key: String, v: Boolean) = sp(ctx).edit().putBoolean(key, v).apply()
    fun str(ctx: Context, key: String): String = sp(ctx).getString(key, "") ?: ""
    fun setStr(ctx: Context, key: String, v: String) = sp(ctx).edit().putString(key, v).apply()
    fun long(ctx: Context, key: String): Long = sp(ctx).getLong(key, 0L)
    fun setLong(ctx: Context, key: String, v: Long) = sp(ctx).edit().putLong(key, v).apply()

    fun ipModeTitle(m: String): String = when (m) {
        "v4" -> "только IPv4"
        "v6" -> "только IPv6"
        "both" -> "IPv4 + IPv6 (IPv6 первым)"
        else -> "авто"
    }
}
