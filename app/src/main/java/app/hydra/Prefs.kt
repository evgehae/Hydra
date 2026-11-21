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
        get() = sp.getBoolean("auto_start", true)
        set(v) { sp.edit().putBoolean("auto_start", v).apply() }

    var killSwitch: Boolean
        get() = sp.getBoolean("kill_switch", false)
        set(v) { sp.edit().putBoolean("kill_switch", v).apply() }

    /** Запрещённые дата-центры Cloudflare, коды через запятую. */
    var blockedColos: String
        get() = sp.getString("colo_block", null) ?: defaultBlockedColos()
        set(v) { sp.edit().putString("colo_block", v).apply() }

    /** Если не пусто — разрешены только эти дата-центры. */
    var allowColos: String
        get() = sp.getString("colo_allow", "") ?: ""
        set(v) { sp.edit().putString("colo_allow", v).apply() }

    /** Канал связи с Cloudflare: "auto" или "cell" (принудительно мобильная сеть). */
    var channel: String
        get() = sp.getString("channel", "auto") ?: "auto"
        set(v) { sp.edit().putString("channel", v).apply() }

    /** Если все адреса ведут в запрещённый дата-центр — подключиться всё равно. */
    var fallbackAny: Boolean
        get() = sp.getBoolean("fallback_any", false)
        set(v) { sp.edit().putBoolean("fallback_any", v).apply() }

    /** Пользователь нажал «подключить» и не отключал: держим VPN, пока он сам не выключит. */
    var wantConnected: Boolean
        get() = sp.getBoolean("want_connected", false)
        set(v) { sp.edit().putBoolean("want_connected", v).apply() }

    /** Протокол: "auto" (оба, запасной подхватывает), "masque" или "wg". */
    var protocol: String
        get() = sp.getString("protocol", "auto") ?: "auto"
        set(v) { sp.edit().putString("protocol", v).apply() }

    /** Свой SNI для туннеля MASQUE ("" — по умолчанию). */
    var customSni: String
        get() = sp.getString("custom_sni", "") ?: ""
        set(v) { sp.edit().putString("custom_sni", v).apply() }

    /** Свой адрес сервера MASQUE: "IP" или "IP:порт". */
    var customEndpoint: String
        get() = sp.getString("custom_endpoint", "") ?: ""
        set(v) { sp.edit().putString("custom_endpoint", v).apply() }

    /** Свой DNS внутри туннеля: IP-адреса через запятую. */
    var customDns: String
        get() = sp.getString("custom_dns", "") ?: ""
        set(v) { sp.edit().putString("custom_dns", v).apply() }

    var customDnsOn: Boolean
        get() = sp.getBoolean("custom_dns_on", false)
        set(v) { sp.edit().putBoolean("custom_dns_on", v).apply() }

    /** Подсети, которые идут напрямую, мимо VPN (Android 13+). */
    var excludedRoutes: String
        get() = sp.getString("excl_routes", null) ?: DEFAULT_ROUTES
        set(v) { sp.edit().putString("excl_routes", v).apply() }

    /** IPv6 через туннель (по умолчанию выключен: приложения сразу идут по IPv4). */
    var ipv6: Boolean
        get() = sp.getBoolean("ipv6", false)
        set(v) { sp.edit().putBoolean("ipv6", v).apply() }

    /** После подключения проверять Telegram; негодные дата-центры обходятся. */
    var tgGate: Boolean
        get() = sp.getBoolean("tg_gate", true)
        set(v) { sp.edit().putBoolean("tg_gate", v).apply() }

    /** Wi-Fi, который ведёт в запрещённый дата-центр: туннель идёт через мобильную сеть (12 часов). */
    fun cellWifiActive(print: String): Boolean {
        if (print.isEmpty()) return false
        val now = System.currentTimeMillis()
        return (sp.getString("cell_wifi", "") ?: "").split(";").any {
            val p = it.split("@")
            p.size == 2 && p[0] == print && now - (p[1].toLongOrNull() ?: 0L) < 12L * 3600_000L
        }
    }

    fun addCellWifi(print: String) {
        val cur = (sp.getString("cell_wifi", "") ?: "").split(";").filter { it.isNotEmpty() && !it.startsWith("$print@") }
        sp.edit().putString("cell_wifi", (cur + "$print@${System.currentTimeMillis()}").joinToString(";")).apply()
    }

    /** Параллельная гонка стратегий и горячий резерв. */
    var parallel: Boolean
        get() = sp.getBoolean("parallel", true)
        set(v) { sp.edit().putBoolean("parallel", v).apply() }


    /** Уведомление при смене стратегии. */
    var notifyStrategy: Boolean
        get() = sp.getBoolean("notify_strategy", true)
        set(v) { sp.edit().putBoolean("notify_strategy", v).apply() }

    /** Уведомление при ошибках / reconnect. */
    var notifyErrors: Boolean
        get() = sp.getBoolean("notify_errors", true)
        set(v) { sp.edit().putBoolean("notify_errors", v).apply() }

    /** Показывать постоянную плитку статуса (ongoing). */
    var notifyStatus: Boolean
        get() = sp.getBoolean("notify_status", true)
        set(v) { sp.edit().putBoolean("notify_status", v).apply() }

    /** Уже показывали запрос на исключение из оптимизации батареи. */
    var batteryAsked: Boolean
        get() = sp.getBoolean("battery_asked", false)
        set(v) { sp.edit().putBoolean("battery_asked", v).apply() }

    /** Использовать root (iptables/nftables) для жёсткого kill-switch. */
    var useRoot: Boolean
        get() = sp.getBoolean("use_root", false)
        set(v) { sp.edit().putBoolean("use_root", v).apply() }

    /** Режим максимальной стабильности (меньше параллелизма, приоритет WG + EU ДЦ). */
    var stabilityMode: Boolean
        get() = sp.getBoolean("stability_mode", false)
        set(v) { sp.edit().putBoolean("stability_mode", v).apply() }

    /** Профиль ТВ: длиннее таймауты, меньше гонки, стабильность важнее скорости. */
    var tvProfile: Boolean
        get() = sp.getBoolean("tv_profile", false)
        set(v) { sp.edit().putBoolean("tv_profile", v).apply() }

    /** Периодическая проверка сервисов (минуты, 0 = только при подключении). */
    var serviceCheckEveryMin: Int
        get() = sp.getInt("svc_check_min", 3)
        set(v) { sp.edit().putInt("svc_check_min", v).apply() }

    /** Однократная миграция: прежнее умолчание «DME,LED,SVX,…» заменяется на «DME». */
    fun migrate() {
        if (sp.getInt("defaults_ver", 0) < 2) {
            val cur = sp.getString("colo_block", null)
            if (cur != null && cur.replace(" ", "").startsWith("DME,LED")) sp.edit().remove("colo_block").apply()
            sp.edit().putInt("defaults_ver", 2).apply()
        }
    }

    fun resetAll() { sp.edit().clear().apply() }

    companion object {
        const val DEFAULT_ROUTES =
            "10.0.0.0/8,100.64.0.0/10,169.254.0.0/16,172.16.0.0/12,192.0.0.0/24,192.168.0.0/16," +
            "224.0.0.0/24,240.0.0.0/4,239.255.255.250/32,255.255.255.255/32,17.249.0.0/16"
    }

    fun defaultBlockedColos(): String =
        try { mobile.Mobile.defaultBlockedColos() } catch (t: Throwable) { "DME" }
}
