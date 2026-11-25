package app.hydra

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/**
 * Один экран «DNS и обход ИИ».
 *  - Тумблер включается сразу: запоминается последний сервер и его проверка (ничего ждать не надо).
 *  - Результаты проверки и порядок «лучшие сверху» сохраняются между открытиями.
 *  - Автопоиск: раз в 30 минут проверяет все серверы и сам переходит на лучший.
 *  - Приложения ИИ автоматически добавляются в туннель.
 *  - Системный частный DNS не включается сам (из-за него пропадал интернет).
 */
@Composable
fun AiDnsScreen(prefs: Prefs, vpn: VpnController, onBack: () -> Unit) {
    val ctx = LocalContext.current

    var tick by remember { mutableStateOf(0) }
    var on by remember { mutableStateOf(prefs.aiDnsEnabled) }
    var providerId by remember { mutableStateOf(prefs.aiDnsProvider.ifBlank { "comss" }) }
    var enabledSvc by remember { mutableStateOf(AiDns.enabledServices(ctx)) }
    var busy by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }
    var probes by remember { mutableStateOf<List<AiDns.ProviderProbe>>(emptyList()) }
    var customText by remember { mutableStateOf("") }
    var adv by remember { mutableStateOf(false) }
    var auto by remember { mutableStateOf(AiDns.autoOn(ctx)) }
    var ownDnsOn by remember { mutableStateOf(prefs.customDnsOn) }
    var ownDns by remember { mutableStateOf(prefs.customDns) }
    var sysDns by remember {
        mutableStateOf(AiDns.readPrivateDns(ctx).let { (m, h) -> if (h.isBlank()) m else "$m · $h" })
    }

    // загрузить список и сохранённые результаты (порядок «лучшие сверху» остаётся)
    LaunchedEffect(Unit) {
        AiDns.reload(ctx)
        probes = AiDns.sortedProbes(AiDns.loadProbes(ctx))
        tick++
    }

    fun refreshSys() {
        sysDns = AiDns.readPrivateDns(ctx).let { (m, h) -> if (h.isBlank()) m else "$m · $h" }
    }

    fun toast(s: String) = Toast.makeText(ctx, s.take(160), Toast.LENGTH_LONG).show()

    fun turnOn(id: String) {
        busy = true
        status = "Включаю «${AiDns.provider(id).title}»…"
        AiDns.enable(ctx, id, enabledSvc) { r ->
            busy = false
            status = r.message
            probes = AiDns.sortedProbes(AiDns.loadProbes(ctx))
            if (r.ok) {
                on = true
                prefs.aiDnsEnabled = true
                prefs.aiDnsProvider = id
                AiDns.startAuto(ctx)
                vpn.restartIfActive()
            } else {
                on = false
                prefs.aiDnsEnabled = false
            }
            refreshSys()
        }
    }

    fun findBest() {
        if (busy) return
        busy = true
        status = "Проверяю серверы…"
        AiDns.probeAllAndSave(ctx, enabledSvc, onProgress = { d, t -> status = "Проверено $d из $t…" }) { sorted ->
            probes = sorted
            val best = AiDns.pickBest(sorted)
            if (best != null) { providerId = best.id; prefs.aiDnsProvider = best.id }
            if (on) {
                val out = AiDns.applyProbes(ctx, sorted, enabledSvc, providerId)
                busy = false
                status = out.message
                if (out.ov != null && out.needRestart) vpn.restartIfActive()
                AiDns.makeSnapshot(ctx)
            } else {
                busy = false
                status = if (best != null) "Лучший: ${best.title}. Включи переключатель «Обход ИИ»." else
                    "Ни один сервер сейчас не открывает ИИ. Нажми «Обновить список» или добавь свой сервер."
            }
        }
    }

    SubPage("DNS и обход ИИ", onBack = onBack) {
        val title = AiDns.activeProviderTitle(ctx)
        NoteText(
            if (on) "Обход ИИ включён" + (if (title.isNotEmpty()) ": $title" else "") +
                ". Для каждого сервиса работает свой лучший сервер; остальное идёт через WARP."
            else "Обход выключен. Включай — ничего ждать не нужно, последний сервер запоминается."
        )

        SettingSwitchRow(
            "Обход ИИ",
            subtitle = "ChatGPT / Claude / Grok / Gemini через Smart DNS, остальное через WARP",
            checked = on
        ) { v ->
            if (busy) return@SettingSwitchRow
            if (v) turnOn(providerId)
            else {
                AiDns.deactivate(ctx)
                prefs.aiDnsEnabled = false
                on = false
                status = "Обход выключен"
                vpn.restartIfActive()
            }
        }

        SettingSwitchRow(
            "Автопоиск лучшего сервера",
            subtitle = "Каждые 30 минут проверяет все серверы и пересобирает карту; если ИИ перестал открываться — раньше",
            checked = auto
        ) { v ->
            auto = v
            AiDns.setAuto(ctx, v)
            if (v && on) AiDns.startAuto(ctx)
        }

        if (status.isNotBlank()) {
            Text(
                status,
                color = MaterialTheme.colorScheme.primary,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(16.dp)
            )
        }

        SectionTitle("Сервер")
        val age = AiDns.lastProbeAgeMin(ctx)
        SettingRow(
            if (busy) "Проверяю…" else "Найти лучший",
            subtitle = "Реальная проверка адреса ИИ. Зелёный — открывает, жёлтый — живой, но ИИ нет, красный — не отвечает." +
                if (age >= 0) " Последняя проверка: ${if (age < 1) "только что" else "$age мин назад"}." else "",
            onClick = { findBest() }
        )
        SettingRow(
            "Обновить список из репозитория",
            subtitle = "Новые серверы и вычеркнутые мёртвые, без новой сборки приложения",
            onClick = {
                if (busy) return@SettingRow
                status = "Обновляю список…"
                AiDns.syncAll(ctx) { msg -> status = msg; tick++ }
            }
        )

        val allProviders = tick.let { AiDns.providers.filter { p -> p.id != "cloudflare" } }
        val byId = probes.associateBy { it.providerId }
        // порядок: сначала проверенные по рейтингу (как сохранили), потом непроверенные
        val ordered = allProviders.sortedByDescending { p -> if (byId[p.id] == null) -2000 else AiDns.score(byId[p.id]) }

        ordered.forEach { p ->
            val pr = byId[p.id]
            val aiCount = AiDns.openCount(pr)
            val tunnelOk = pr == null || pr.dnsIps.isNotEmpty()
            val dot = when {
                pr == null -> Color(0xFF757575)
                !pr.alive -> Color(0xFFE53935)
                aiCount > 0 -> Color(0xFF43A047)
                else -> Color(0xFFFDD835)
            }
            val line = if (pr == null) p.hostname + (if (p.note.isNotBlank()) " · ${p.note}" else "")
            else if (!pr.alive) "не отвечает"
            else run {
                AiDns.services.filter { s -> s.id in pr.marks.keys }
                    .joinToString(" · ") { s -> s.title + " " + (pr.marks[s.id] ?: "") } +
                    " · ${pr.via} ${pr.latencyMs} мс" + (if (!tunnelOk) " · только DoH/DoT" else "") +
                    (if (pr.udpHijacked) " · UDP перехвачен" else "")
            }
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(Modifier.size(10.dp).background(dot, CircleShape))
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        (if (on && AiDns.activeProviderId(ctx) == p.id) "● " else "") + p.title,
                        style = MaterialTheme.typography.bodyLarge
                    )
                    Text(line, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (providerId == p.id) Text("✓", color = MaterialTheme.colorScheme.primary)
                else TextButton(onClick = {
                    providerId = p.id
                    prefs.aiDnsProvider = p.id
                    if (on) turnOn(p.id)
                }) { Text("основной") }
                if (p.custom) TextButton(onClick = { AiDns.removeCustom(ctx, p.id); tick++ }) { Text("✕") }
            }
            RowDivider()
        }

        SectionTitle("Свой сервер")
        OutlinedTextField(
            value = customText,
            onValueChange = { customText = it },
            label = { Text("hostname, IP или https://…/dns-query") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)
        )
        Button(
            onClick = {
                val err = AiDns.addCustom(ctx, customText)
                if (err == null) { status = "Добавлен: ${customText.trim()}. Нажми «Найти лучший»."; customText = ""; tick++ }
                else toast(err)
            },
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)
        ) { Text("Добавить") }

        SectionTitle("Сервисы")
        AiDns.services.forEach { svc ->
            val sOn = svc.id in enabledSvc
            SettingRow(
                svc.title,
                value = if (sOn) "вкл" else "выкл",
                onClick = {
                    enabledSvc = if (sOn) enabledSvc - svc.id else enabledSvc + svc.id
                    prefs.aiDnsServices = enabledSvc.joinToString(",")
                }
            )
        }
        NoteText("Приложения ChatGPT, Claude, Grok, Gemini и др. сами попадают в туннель при включении обхода. Браузеры добавь вручную в «Приложения».")

        SectionTitle("DNS туннеля (когда обход ИИ выключен)")
        NoteText("Обычный DNS внутри WARP. При включённом обходе ИИ его заменяет Smart DNS, поэтому этот пункт не трогай.")
        SettingSwitchRow("Свой DNS", checked = ownDnsOn) {
            ownDnsOn = it; prefs.customDnsOn = it; vpn.restartIfActive()
        }
        OutlinedTextField(
            value = ownDns,
            onValueChange = { ownDns = it; prefs.customDns = it },
            label = { Text("IP через запятую, например 1.1.1.1,1.0.0.1") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)
        )
        SettingRow("Cloudflare 1.1.1.1", onClick = {
            ownDns = "1.1.1.1,1.0.0.1"; prefs.customDns = ownDns; ownDnsOn = true; prefs.customDnsOn = true; vpn.restartIfActive()
        })
        SettingRow("Google 8.8.8.8", onClick = {
            ownDns = "8.8.8.8,8.8.4.4"; prefs.customDns = ownDns; ownDnsOn = true; prefs.customDnsOn = true; vpn.restartIfActive()
        })

        SettingRow(
            if (adv) "Дополнительно ▲" else "Дополнительно ▼",
            subtitle = "Системный частный DNS, hosts и local DNS (root) — запасные пути",
            onClick = { adv = !adv }
        )
        if (adv) {
            NoteText("Сейчас в системе: $sysDns. Приложение больше не включает частный DNS само: с ним в VPN может пропасть интернет.")
            SettingRow("Сбросить системный частный DNS", subtitle = "Вернуть «Автоматически» — если интернет пропал", onClick = {
                val r = AiDns.disablePrivateDns(ctx)
                refreshSys(); status = r.message; toast(r.message)
            })
            SettingRow("Применить сервер как частный DNS (на свой риск)",
                subtitle = "Только для серверов с DoT; в VPN часто ломает сайты и Telegram", onClick = {
                val r = AiDns.applyPrivateDns(ctx, providerId)
                refreshSys(); status = r.message; toast(r.message)
            })
            SettingRow("Только домены ИИ (hosts / local DNS, root)", onClick = {
                if (busy) return@SettingRow
                busy = true; status = "Строю карту имён…"
                AiDns.activateAiOnly(ctx, providerId, enabledSvc) { r -> busy = false; status = r.message }
            })
            SettingRow("Сбросить всё (частный DNS, hosts, redirect)", onClick = {
                val r = AiDns.disablePrivateDns(ctx)
                RootHelper.disableDnsRedirect()
                AiDns.clearHosts()
                LocalDnsServer.stop()
                AiDns.deactivate(ctx)
                on = false
                refreshSys(); status = r.message
                vpn.restartIfActive()
            })
        }
    }
}

/** Живой индикатор обхода ИИ для главного экрана: точка + что сейчас открывается. Обновляется раз в минуту. */
@Composable
fun AiStatusRow(prefs: Prefs, active: Boolean) {
    val ctx = LocalContext.current
    var h by remember { mutableStateOf(AiDns.lastHealth) }
    LaunchedEffect(active) {
        while (active && prefs.aiDnsEnabled) {
            val r = withContext(Dispatchers.IO) { AiDns.quickHealth(ctx) }
            h = r
            delay(60_000)
        }
    }
    if (!prefs.aiDnsEnabled) return
    val dot = if (!active) Color(0xFF757575) else when (h.state) {
        1 -> Color(0xFF43A047)
        2 -> Color(0xFFFDD835)
        3 -> Color(0xFFE53935)
        else -> Color(0xFF757575)
    }
    HCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(10.dp).background(dot, CircleShape))
            Spacer(Modifier.width(12.dp))
            Column {
                Text("Обход ИИ", style = MaterialTheme.typography.bodyMedium)
                Text(
                    if (!active) "VPN выключен" else h.text,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}
