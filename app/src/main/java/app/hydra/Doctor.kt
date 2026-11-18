package app.hydra

import android.content.Context
import android.os.PowerManager
import android.provider.Settings

/** Одна найденная проблема: что видно, почему так, что сделать человеку и что чинить в коде. */
data class Finding(
    val id: String,
    val level: Int, // 3 — критично, 2 — важно, 1 — замечание
    val title: String,
    val seen: String,
    val why: String,
    val fix: String,
    val dev: String
)

private fun validEndpoint(s: String): Boolean {
    val t = s.trim()
    if (t.startsWith("[")) return true
    val parts = t.split(":")
    if (parts.size > 2) return t.contains("::")
    val ip = parts[0].split(".")
    if (ip.size != 4) return false
    for (o in ip) {
        val n = o.toIntOrNull() ?: return false
        if (n !in 0..255) return false
    }
    if (parts.size == 2) {
        val p = parts[1].toIntOrNull() ?: return false
        if (p !in 1..65535) return false
    }
    return true
}

/** Строки с ✘ из последней проверки сервисов через туннель (если её запускали). */
private fun lastServiceFailures(journal: String): List<String>? {
    val i = journal.lastIndexOf("проверка сервисов через туннель")
    if (i < 0) return null
    val block = journal.substring(i).lines().take(30)
    val end = block.indexOfFirst { it.contains("Доступно") }
    val part = if (end >= 0) block.take(end) else block.take(15)
    return part.filter { it.contains("✘") }.map { it.trim() }
}

private fun operatorName(code: String): String = when (code) {
    "25001" -> "МТС"
    "25002" -> "МегаФон"
    "25020" -> "Tele2"
    "25099" -> "Билайн"
    "25011" -> "Yota"
    "25035" -> "МОТИВ"
    "" -> "нет данных"
    else -> "оператор $code"
}

/** Раздел «профиль сети»: какая сеть сейчас, кто оператор и что Гидра успела о ней узнать. */
private fun networkProfile(ctx: Context, checks: List<DiagCheck>, engine: String): String {
    val sb = StringBuilder()
    sb.append("\n--- профиль сети ---\n")
    sb.append("Тип сети сейчас: ").append(networkType(ctx)).append('\n')
    try {
        val tm = ctx.getSystemService(Context.TELEPHONY_SERVICE) as android.telephony.TelephonyManager
        val net = tm.networkOperator.orEmpty()
        val sim = tm.simOperator.orEmpty()
        sb.append("Оператор сети: ").append(operatorName(net)).append(" (").append(net).append(")\n")
        sb.append("Оператор SIM: ").append(operatorName(sim)).append(" (").append(sim).append(")\n")
    } catch (t: Throwable) {
        sb.append("Оператор: не определён\n")
    }
    val prov = checks.lastOrNull { it.name.startsWith("Провайдер сети") }
    if (prov != null) sb.append("Провайдер по публичному IP: ").append(prov.detail).append('\n')
    val brain = engine.substringAfter("🧠 что Гидра знает", "")
    if (brain.isNotEmpty()) {
        sb.append("Что Гидра знает об этой сети (сервисы по стратегиям, плохие дата-центры):\n")
        sb.append("🧠 что Гидра знает").append(brain)
        if (!brain.endsWith("\n")) sb.append('\n')
    } else {
        sb.append("Что Гидра знает об этой сети: данных пока нет (нужно подключение и несколько секунд).\n")
    }
    return sb.toString()
}

fun diagnose(
    ctx: Context, prefs: Prefs, vpn: VpnController,
    checks: List<DiagCheck>, engine: String, journal: String
): List<Finding> {
    val out = mutableListOf<Finding>()
    fun add(id: String, level: Int, title: String, seen: String, why: String, fix: String, dev: String) {
        out += Finding(id, level, title, seen, why, fix, dev)
    }

    // ---- проверки мимо VPN ----
    val dns = checks.getOrNull(0)
    val https = checks.getOrNull(1)
    val api = checks.getOrNull(2)
    val web = checks.getOrNull(5)
    if (dns != null && !dns.ok) {
        add("D01", 3, "Не работает DNS",
            "проверка DNS: ${dns.detail}",
            "Телефон не может превратить имя сайта в адрес. Сети нет, либо DNS провайдера не отвечает.",
            "1) Выключи и включи Wi-Fi или мобильную сеть. 2) Попробуй другую сеть. 3) Нажми «Диагностика» ещё раз.",
            "Diagnostics.kt: runDiagnostics (InetAddress.getByName); dns.go: SetSystemDNS")
    } else if (https != null && !https.ok) {
        add("D02", 3, "Нет HTTPS до Cloudflare",
            "DNS работает, а HTTPS к cloudflare.com не проходит: ${https.detail}",
            "Провайдер или сеть режут соединения к Cloudflare. Это бывает при «белых списках».",
            "Подключись к другой сети (Wi-Fi вместо мобильной или наоборот) и повтори диагностику.",
            "mobile/netalive.go: realNetState/classify; learn.go: sniPool (российские имена)")
    }
    if (api != null && !api.ok) {
        add("D03", 2, "Не открывается сервер регистрации WARP",
            "api.cloudflareclient.com:443: ${api.detail}",
            "Без него нельзя получить или обновить ключи WARP. Уже подключённый туннель при этом может работать.",
            "Если ключей ещё нет: подключись по другой сети, зарегистрируйся, потом возвращайся. Если есть, ничего делать не нужно.",
            "register.go: гонка маршрутов регистрации (api.devices.cloudflare.com запасной)")
    }
    if (web != null && !web.ok && dns?.ok == true && https?.ok == true) {
        add("D04", 1, "Обычный сайт (google.com) не открывается напрямую",
            "tcp www.google.com:443: ${web.detail}",
            "Прямой доступ к Google закрыт у этой сети. Для VPN это нормально, важно, что он открывается через туннель.",
            "Ничего, если через включённый VPN сайты открываются.",
            "Diagnostics.kt: runFullDiagnostics")
    }

    // ---- состояние туннеля ----
    val st = vpn.state
    if (st == "failed") {
        add("D10", 3, "Туннель не поднимается",
            "состояние: failed. ${vpn.message}",
            "Все стратегии из списка не сработали в этой сети.",
            "1) Подожди 1–2 минуты: Гидра пробует новые варианты сама. 2) Если не помогло, смени сеть. 3) Отправь этот отчёт целиком.",
            "engine.go: Run/runStrategy; learn.go: мутации; memory.go: Rank")
    } else if (st == "reconnecting") {
        add("D11", 2, "Туннель переподключается",
            "состояние: reconnecting. ${vpn.message}",
            "Связь пропала, Гидра ищет другой путь.",
            "Подожди минуту. Если так повторяется часто, отправь отчёт.",
            "engine.go: noteLoss; race.go: горячий резерв")
    }
    if (st == "up" && vpn.rttMs > 700) {
        add("D12", 2, "Очень большая задержка",
            "задержка ${vpn.rttMs} мс (норма до 400)",
            "Путь до дата-центра плохой или канал перегружен.",
            "Попробуй другой дата-центр: Дополнительно → Дата-центры → разрешить HEL, FRA, AMS.",
            "colo.go; engine.go: политика дата-центров")
    }
    val blocked = prefs.blockedColos.split(",").map { it.trim().uppercase() }.filter { it.isNotEmpty() }
    if (st == "up" && vpn.colo.isNotEmpty() && blocked.contains(vpn.colo.uppercase())) {
        add("D13", 2, "Подключились к запрещённому дата-центру",
            "дата-центр ${vpn.colo} есть в списке запрещённых",
            "Включена настройка «всё равно подключаться», когда других нет.",
            "Если нужно строго без этого дата-центра: Дополнительно → отключи «подключаться к любому».",
            "mobile/policy.go: SetFallback; gate.go: coloAllowed")
    }

    // ---- настройки, которые ломают работу ----
    if (prefs.splitOnlySelected && prefs.splitApps.isEmpty()) {
        add("D20", 3, "VPN включён, но ни одно приложение не пускается в туннель",
            "режим «только выбранные приложения», выбрано 0",
            "Весь трафик идёт мимо VPN, поэтому кажется, что VPN «не работает».",
            "Меню → Приложения: отметь нужные (Telegram, YouTube, WhatsApp) или выключи режим «только выбранные».",
            "AppsScreen.kt; HydraVpnService.kt (addAllowedApplication)")
    }
    if (!prefs.parallel) {
        add("D21", 2, "Выключен горячий резерв и гонка стратегий",
            "параллельный режим: выкл",
            "Стратегии пробуются по одной, а при обрыве связь пропадает на время переподключения.",
            "Включи параллельный режим в «Дополнительно».",
            "mobile/policy.go: SetParallel; race.go")
    }
    if (!prefs.autoStart) {
        add("D22", 1, "Нет автозапуска после перезагрузки",
            "автозапуск: выкл",
            "После перезагрузки телефона VPN сам не включится («включил и забыл» не работает).",
            "Дополнительно → Постоянная работа → включи автозапуск.",
            "BootReceiver.kt")
    }
    if (prefs.customEndpoint.isNotBlank() && !validEndpoint(prefs.customEndpoint)) {
        add("D23", 2, "Свой адрес сервера записан неверно",
            "значение: «${prefs.customEndpoint}»",
            "Нужен IP или IP:порт, например 162.159.198.2 или 162.159.198.2:443. Имя сайта не подойдёт.",
            "Дополнительно → Свой адрес сервера → введи IP или нажми «Сбросить».",
            "mobile/vpn_usque.go (currentCustom); custom.go: CustomEndpointStrategies")
    }
    if (prefs.customDnsOn && prefs.customDns.isBlank()) {
        add("D24", 1, "Свой DNS включён, но сервер не указан",
            "customDnsOn=true, customDns пусто",
            "Используется DNS по умолчанию, настройка ничего не меняет.",
            "Параметры DNS → укажи сервер (например 1.1.1.1) или выключи переключатель.",
            "AdvancedScreens.kt: DnsScreen; AccountController.kt: dnsProvider")
    }
    try {
        val mode = Settings.Global.getString(ctx.contentResolver, "private_dns_mode")
        if (mode == "hostname") {
            add("D25", 2, "В Android включён строгий частный DNS",
                "private_dns_mode=hostname (${Settings.Global.getString(ctx.contentResolver, "private_dns_specifier") ?: ""})",
                "Строгий частный DNS (DoT) часто не работает через VPN: сайты и Telegram не открываются.",
                "Настройки Android → Подключение → Частный DNS → «Автоматически» или «Отключено».",
                "HomeScreen.kt (предупреждение); HydraVpnService.kt")
        }
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!pm.isIgnoringBatteryOptimizations(ctx.packageName)) {
            add("D26", 2, "Система может убить VPN в фоне",
                "приложение не исключено из оптимизации батареи",
                "Xiaomi/HyperOS агрессивно закрывает фоновые приложения, и VPN отваливается.",
                "Дополнительно → «Разрешить работу в фоне», затем «Автозапуск (Xiaomi)».",
                "SystemInfo.kt; BootReceiver.kt")
        }
    } catch (t: Throwable) { }

    // ---- по журналу и движку ----
    val lost = Regex("потерь без резерва: (\\d+)").find(engine)?.groupValues?.get(1)?.toIntOrNull() ?: 0
    if (lost > 0) {
        add("D30", 2, "Были обрывы без резерва",
            "потерь без резерва: $lost",
            "В момент обрыва не было готового запасного туннеля.",
            "Включи параллельный режим и протокол «Авто». Если уже включены, отправь отчёт.",
            "engine.go: noteLoss; race.go: горячий резерв")
    }
    if (engine.contains("состояние сети: whitelist")) {
        add("D31", 3, "Сеть в режиме «белых списков»",
            "доступны только российские адреса, зарубежные закрыты",
            "Оператор ограничил интернет списком разрешённых сайтов. Обычный WARP в этом режиме недоступен.",
            "Переключись на Wi-Fi или подожди: Гидра сама пробует имена из белых списков (SNI) и вернётся, когда режим снимут.",
            "mobile/netalive.go: realWLScan/WhitelistCheck; learn.go: sniPool")
    } else if (engine.contains("состояние сети: dead")) {
        add("D32", 3, "Нет интернета вообще",
            "ни зарубежные, ни российские адреса не отвечают",
            "Нет сигнала сети, режим «в самолёте» или сеть отключена.",
            "Проверь сигнал и режим «в самолёте», переключи сеть.",
            "mobile/netalive.go: classify")
    }
    if (journal.contains("Telegram не доходит")) {
        add("D33", 2, "Telegram не доходит через выбранный дата-центр",
            "в журнале: «Telegram не доходит через дата-центр …»",
            "Интернет работает, а сервера Telegram режутся на этом маршруте.",
            "Гидра ищет другой дата-центр сама. Можно ускорить: Дополнительно → Дата-центры → разрешить только HEL, FRA, AMS.",
            "gate.go: serviceGate/noteBadColo")
    }
    val hs = journal.lines().takeLast(400).count { it.contains("TLS handshake failure") }
    if (hs >= 5) {
        add("D34", 1, "Много отказов TLS при рукопожатии",
            "$hs строк «TLS handshake failure» в свежем журнале",
            "Пробуются адреса, которые не являются серверами MASQUE (адреса WireGuard).",
            "Ничего делать не нужно, если туннель в итоге поднялся. Иначе отправь отчёт.",
            "strategies.go: MasqueStrategies (список адресов); learn.go: генерация адресов")
    }
    val svc = lastServiceFailures(journal)
    if (svc == null && st == "up") {
        add("D40", 1, "Проверка сервисов через туннель ещё не запускалась",
            "в журнале нет результата проверки",
            "Без неё неизвестно, доходят ли YouTube, WhatsApp и Telegram.",
            "Диагностика → «Проверить сервисы» (при включённом VPN), затем снова собери отчёт.",
            "services.go: ServiceCheck; DiagnosticsScreen.kt")
    } else if (svc != null && svc.isNotEmpty()) {
        add("D41", 2, "Часть сервисов не доходит через туннель",
            svc.joinToString("\n         "),
            "Туннель есть, но до этих адресов TCP не проходит. Если не отвечают только они, их режут по маршруту или адресу.",
            "Гидра подбирает другой дата-центр и стратегию сама. Если не прошло за 5 минут, отправь отчёт.",
            "services.go; gate.go; learn.go (адаптация под сервис — план v22.2)")
    }
    return out
}

/** Раздел отчёта «ДИАГНОЗ»: читается первым, написан простым языком, у каждой проблемы есть шаги. */
fun buildDoctor(ctx: Context, prefs: Prefs, vpn: VpnController, checks: List<DiagCheck>): String {
    val engine = try { mobile.Mobile.diagnostics() } catch (t: Throwable) { "" }
    val journal = try { mobile.Mobile.getJournalFull(4000) } catch (t: Throwable) { "" }
    val list = diagnose(ctx, prefs, vpn, checks, engine, journal).sortedByDescending { it.level }
    val sb = StringBuilder()
    sb.append("\n=== ДИАГНОЗ (читать первым) ===\n")
    val crit = list.count { it.level >= 3 }
    if (list.isEmpty()) {
        sb.append("Итог: правила Доктора проблем не нашли.\n")
        sb.append("Если что-то всё равно не работает, опиши словами, что именно и в какой сети, и отправь этот отчёт.\n")
    } else {
        sb.append("Итог: найдено проблем ").append(list.size).append(", критичных ").append(crit).append(".\n")
        sb.append("Что делать: иди сверху вниз и выполняй пункт «Что сделать». Не помогло, отправь этот файл Claude целиком.\n\n")
        for (f in list) {
            val tag = when (f.level) { 3 -> "КРИТИЧНО"; 2 -> "ВАЖНО"; else -> "ЗАМЕЧАНИЕ" }
            sb.append('[').append(f.id).append("] ").append(tag).append(": ").append(f.title).append('\n')
            sb.append("  Что видно:     ").append(f.seen).append('\n')
            sb.append("  Почему так:    ").append(f.why).append('\n')
            sb.append("  Что сделать:   ").append(f.fix).append('\n')
            sb.append("  Код (для Claude): ").append(f.dev).append("\n\n")
        }
    }
    sb.append(networkProfile(ctx, checks, engine))
    sb.append("--- реестр возможностей (честный статус) ---\n")
    sb.append("✔ Свой адрес сервера: добавляется первым в список стратегий.\n")
    sb.append("✔ Свой SNI: добавляется как дополнительные стратегии, остальные не пропадают.\n")
    sb.append("✔ Память по сетям: Wi-Fi различается отпечатком (шлюз + DNS), мобильная сеть кодом оператора.\n")
    sb.append("✔ Самообучение: мутации TTL, числа и размера фейков, SNI, портов, адресов; мёртвые отбрасываются.\n")
    sb.append("✔ Параллельная гонка стратегий и горячий резерв (включается настройкой).\n")
    sb.append("✔ Проверка Telegram, YouTube, WhatsApp, Instagram, Discord через туннель (достижимость адреса по TCP).\n")
    sb.append("⚠ Замедление по имени сайта (SNI) эта проверка не видит: нужна проверка скоростью.\n")
    sb.append("⚠ Свой DNS: обычный DNS внутри туннеля. DoH и DoT не поддерживаются.\n")
    sb.append("✘ Системный частный DNS не настраивается приложением, только определяется.\n")
    sb.append("✔ Память сервисов по сетям: какие из Telegram, YouTube, WhatsApp доходили через какую стратегию. Она влияет на порядок перебора, а при сбое сервиса Гидра сама придумывает новые варианты.\n")
    sb.append("⚠ Сбой YouTube или WhatsApp пока не заставляет мгновенно менять туннель (только Telegram): адрес берётся по имени, и подмена DNS дала бы ложные срабатывания. Решим по реальным отчётам.\n")
    sb.append("⚠ Знания об ограничениях операторов не вшиты: Гидра выучивает их сама по каждой сети (оператор SIM или Wi-Fi). Заранее известных «правил МТС/Билайна» нет, и выдумывать их я не буду.\n")
    sb.append("=== конец диагноза ===\n")
    return sb.toString()
}
