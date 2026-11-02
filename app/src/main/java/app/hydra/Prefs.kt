package app.hydra

import android.content.Context

class Prefs(ctx: Context) {
    private val sp = ctx.getSharedPreferences("hydra", Context.MODE_PRIVATE)

    var lang: String
        get() = sp.getString("lang", "system") ?: "system"
        set(v) { sp.edit().putString("lang", v).apply() }

    var splitOnlySelected: Boolean
        get() = sp.getBoolean("split_only", true)
        set(v) { sp.edit().putBoolean("split_only", v).apply() }

    var splitApps: Set<String>
        get() = sp.getStringSet("split_apps", emptySet())?.toSet() ?: emptySet()
        set(v) { sp.edit().putStringSet("split_apps", v.toSet()).apply() }

    var autoStart: Boolean
        get() = sp.getBoolean("auto_start", false)
        set(v) { sp.edit().putBoolean("auto_start", v).apply() }

    var killSwitch: Boolean
        get() = sp.getBoolean("kill_switch", false)
        set(v) { sp.edit().putBoolean("kill_switch", v).apply() }
}
