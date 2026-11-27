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
        get() {
            val v = sp.getString("colo_block", null)
            return when {
                v == null || v.isBlank() -> if (isTv) "" else defaultBlockedColos()   // не задано: Москва закрыта; на ТВ DME хватает для YouTube — ничего не блокируем
                v == "NONE" -> ""                                    // пользователь явно разрешил все дата-центры
                else -> v
            }
        }
        set(v) { sp.edit().putString("colo_block", if (v.isBlank()) "NONE" else v).apply() }

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
    private val isTv: Boolean = ctx.packageManager.hasSystemFeature("android.software.leanback")

    var tgGate: Boolean
        get() = sp.getBoolean("tg_gate", !isTv)   // на ТВ Telegram нет — проверка по умолчанию выключена
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

    fun clearCellWifi(print: String) {
        val cur = (sp.getString("cell_wifi", "") ?: "").split(";").filter { it.isNotEmpty() && !it.startsWith("$print@") }
        sp.edit().putString("cell_wifi", cur.joinToString(";")).apply()
    }

    fun clearAllCellWifi() {
        sp.edit().remove("cell_wifi").apply()
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

    /** Проверка YouTube после подключения: для ТВ включена по умолчанию (там нет Telegram). */
    var ytGate: Boolean
        get() = sp.getBoolean("yt_gate", isTv)
        set(v) { sp.edit().putBoolean("yt_gate", v).apply() }

    /** Протокол по типу сети (применяется, когда общий выбор «Авто»): wifi / eth (проводной, ТВ) / cell. Для ТВ по умолчанию WireGuard:
     *  MASQUE через 162.159.198.x у проводных провайдеров часто уходит в Москву (DME). */
    fun protocolFor(kind: String): String = sp.getString("proto_$kind", if (kind == "eth") "wg" else "auto") ?: "auto"
    fun setProtocolFor(kind: String, v: String) { sp.edit().putString("proto_$kind", v).apply() }

    /** Профиль ТВ: длиннее таймауты, меньше гонки, стабильность важнее скорости. */
    var tvProfile: Boolean
        get() = sp.getBoolean("tv_profile", false)
        set(v) { sp.edit().putBoolean("tv_profile", v).apply() }

    /** Периодическая проверка сервисов (минуты, 0 = только при подключении). */
    var serviceCheckEveryMin: Int
        get() = sp.getInt("svc_check_min", 3)
        set(v) { sp.edit().putInt("svc_check_min", v).apply() }

    /** Автолечение zombie-туннеля (up, но сервисы мертвы). По умолчанию включено. */
    var autoHeal: Boolean
        get() = sp.getBoolean("auto_heal", true)
        set(v) { sp.edit().putBoolean("auto_heal", v).apply() }

    /**
     * Усиленное лечение с root: после неудачи обычных уровней —
     * очистка cacheDir и при необходимости force-stop процесса.
     * Имеет смысл только при useRoot=true и наличии root.
     */
    var rootHealEnhanced: Boolean
        get() = sp.getBoolean("root_heal", false)
        set(v) { sp.edit().putBoolean("root_heal", v).apply() }

    /** Сколько плохих проверок подряд до начала лечения (1 или 2). */
    var healFailThreshold: Int
        get() = sp.getInt("heal_fail_thr", 2).coerceIn(1, 3)
        set(v) { sp.edit().putInt("heal_fail_thr", v.coerceIn(1, 3)).apply() }


    /** Явные Jc/Jmin/Jmax для WG-профиля (0 = авто из стратегии). */
    var wgJc: Int
        get() = sp.getInt("wg_jc", 0)
        set(v) { sp.edit().putInt("wg_jc", v).apply() }

    var wgJmin: Int
        get() = sp.getInt("wg_jmin", 40)
        set(v) { sp.edit().putInt("wg_jmin", v).apply() }

    var wgJmax: Int
        get() = sp.getInt("wg_jmax", 70)
        set(v) { sp.edit().putInt("wg_jmax", v).apply() }

    /** Последнее состояние VPN для плитки QS. */
    var lastVpnState: String
        get() = sp.getString("last_vpn_state", "down") ?: "down"
        set(v) { sp.edit().putString("last_vpn_state", v).apply() }

    var lastColo: String
        get() = sp.getString("last_colo", "") ?: ""
        set(v) { sp.edit().putString("last_colo", v).apply() }

    var lastPingMs: Int
        get() = sp.getInt("last_ping_ms", 0)
        set(v) { sp.edit().putInt("last_ping_ms", v).apply() }

    /** Жёсткий timeout handshake (мс). 0 = дефолт ядра (2000). */
    var handshakeTimeoutMs: Int
        get() = sp.getInt("hs_timeout_ms", 2000)
        set(v) { sp.edit().putInt("hs_timeout_ms", v).apply() }


    /** Однократная миграция: прежнее умолчание «DME,LED,SVX,…» заменяется на «DME». */
    fun migrate() {
        if (sp.getInt("defaults_ver", 0) < 2) {
            val cur = sp.getString("colo_block", null)
            if (cur != null && cur.replace(" ", "").startsWith("DME,LED")) sp.edit().remove("colo_block").apply()
            sp.edit().putInt("defaults_ver", 2).apply()
        }
    }

    /** GitHub "owner/repo" для проверки обновлений. Пусто = DEFAULT_REPO в UpdateChecker. */
    var updateRepo: String
        get() = sp.getString("update_repo", "") ?: ""
        set(v) { sp.edit().putString("update_repo", v.trim()).apply() }

    var lastUpdateCheckAt: Long
        get() = sp.getLong("upd_check_at", 0L)
        set(v) { sp.edit().putLong("upd_check_at", v).apply() }

    fun resetAll() { sp.edit().clear().apply() }

    companion object {
        const val DEFAULT_ROUTES =
            "10.0.0.0/8,100.64.0.0/10,169.254.0.0/16,172.16.0.0/12,192.0.0.0/24,192.168.0.0/16," +
            "224.0.0.0/24,240.0.0.0/4,239.255.255.250/32,255.255.255.255/32,17.249.0.0/16"
    }

    fun defaultBlockedColos(): String =
        try { mobile.Mobile.defaultBlockedColos() } catch (t: Throwable) { "DME" }

    var aiDnsEnabled: Boolean
        get() = sp.getBoolean("ai_dns_on", false)
        set(v) { sp.edit().putBoolean("ai_dns_on", v).apply() }
    var aiDnsProvider: String
        get() = sp.getString("ai_dns_prov", "geodema") ?: "geodema"
        set(v) { sp.edit().putString("ai_dns_prov", v).apply() }
    var aiDnsServices: String
        get() = sp.getString("ai_dns_svc", "chatgpt,claude,grok,gemini") ?: "chatgpt,claude,grok,gemini"
        set(v) { sp.edit().putString("ai_dns_svc", v).apply() }
    var aiDnsCache: String
        get() = sp.getString("ai_dns_cache", "") ?: ""
        set(v) { sp.edit().putString("ai_dns_cache", v).apply() }

}
