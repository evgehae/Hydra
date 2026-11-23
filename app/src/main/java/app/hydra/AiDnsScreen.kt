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

/**
 * Один экран «DNS и обход ИИ» вместо двух (раньше были «Параметры DNS» и «Обход ИИ»).
 *  1. Главный переключатель «Обход ИИ» — Smart DNS внутри туннеля, VPN выключать не нужно.
 *  2. Выбор сервера: «Найти лучший» проверяет все по-настоящему (подключение к выданному адресу).
 *  3. Список можно обновить из репозитория и дополнить своим сервером.
 *  4. Обычный DNS туннеля (если обход ИИ выключен) — внизу.
 *  5. «Дополнительно»: системный частный DNS и hosts (root) — запасные пути.
 */
@Composable
fun AiDnsScreen(prefs: Prefs, vpn: VpnController, onBack: () -> Unit) {
    val ctx = LocalContext.current

    var tick by remember { mutableStateOf(0) }
    LaunchedEffect(Unit) { AiDns.reload(ctx); tick++ }

    var on by remember { mutableStateOf(prefs.aiDnsEnabled) }
    var providerId by remember { mutableStateOf(prefs.aiDnsProvider.ifBlank { "comss" }) }
    var enabledSvc by remember {
        mutableStateOf(
            prefs.aiDnsServices.split(',').map { it.trim() }.filter { it.isNotEmpty() }.toSet()
                .ifEmpty { setOf("chatgpt", "claude", "grok", "gemini") }
        )
    }
    var busy by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }
    var probes by remember { mutableStateOf<List<AiDns.ProviderProbe>>(emptyList()) }
    var customText by remember { mutableStateOf("") }
    var adv by remember { mutableStateOf(false) }
    var ownDnsOn by remember { mutableStateOf(prefs.customDnsOn) }
    var ownDns by remember { mutableStateOf(prefs.customDns) }
    var sysDns by remember {
        mutableStateOf(AiDns.readPrivateDns(ctx).let { (m, h) -> if (h.isBlank()) m else "$m · $h" })
    }

    fun refreshSys() {
        sysDns = AiDns.readPrivateDns(ctx).let { (m, h) -> if (h.isBlank()) m else "$m · $h" }
    }

    fun toast(s: String) = Toast.makeText(ctx, s.take(140), Toast.LENGTH_LONG).show()

    fun turnOn(id: String) {
        busy = true
        status = "Проверяю «${AiDns.provider(id).title}» и включаю…"
        AiDns.enable(ctx, id, enabledSvc) { r ->
            busy = false
            status = r.message
            if (r.ok) {
                on = true
                prefs.aiDnsEnabled = true
                prefs.aiDnsProvider = id
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
        probes = emptyList()
        status = "Проверяю серверы…"
        val ids = AiDns.providers.map { it.id }
        AiDns.probeProviders(ids, enabledSvc.toList(), onProgress = { d, t -> status = "Проверено $d из $t…" }) { list ->
            busy = false
            probes = list
            val best = AiDns.pickBest(list)
            if (best != null) {
                providerId = best.id
                prefs.aiDnsProvider = best.id
                val pr = list.find { it.providerId == best.id }
                status = "Лучший: ${best.title} — ${pr?.detail ?: ""}. Нажми переключатель «Обход ИИ»."
            } else {
                status = "Ни один сервер сейчас не открывает ИИ. Нажми «Обновить список» или добавь свой сервер."
            }
        }
    }

    SubPage("DNS и обход ИИ", onBack = onBack) {
        val title = AiDns.activeProviderTitle(ctx)
        NoteText(
            if (on) "Обход ИИ включён" + (if (title.isNotEmpty()) ": $title" else "") +
                ". Туннель и обход работают вместе: ИИ идёт через Smart DNS, всё остальное — через WARP."
            else "Обход выключен. Включи переключатель ниже — VPN выключать не нужно."
        )

        SettingSwitchRow(
            "Обход ИИ",
            subtitle = "ChatGPT / Claude / Grok / Gemini через Smart DNS, остальное через WARP",
            checked = on
        ) { v ->
            if (busy) return@SettingSwitchRow
            if (v) turnOn(providerId)
            else {
                AiDns.disable(ctx)
                prefs.aiDnsEnabled = false
                on = false
                status = "Обход выключен"
                vpn.restartIfActive()
            }
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
        SettingRow(
            if (busy) "Проверяю…" else "Найти лучший",
            subtitle = "Реальная проверка: подключается к адресу ИИ и смотрит, открывается ли. Красный — мёртвый, жёлтый — живой, но ИИ не открывает, зелёный — открывает",
            onClick = { findBest() }
        )
        SettingRow(
            "Обновить список из репозитория",
            subtitle = "Новые серверы и вычеркнутые мёртвые, без новой сборки приложения",
            onClick = {
                if (busy) return@SettingRow
                status = "Обновляю список…"
                AiDns.syncRemote(ctx) { ok, msg -> status = msg; if (ok) tick++ }
            }
        )

        val shown = tick.let { AiDns.providers.filter { it.id != "cloudflare" } }
        val byId = probes.associateBy { it.providerId }
        val ordered = if (probes.isNotEmpty()) {
            shown.sortedByDescending { p ->
                val pr = byId[p.id]
                if (pr == null) -1000 else
                    (if (pr.alive) 50 else 0) + pr.bypass.values.count { it } * 20 - (pr.latencyMs / 100).toInt()
            }
        } else shown

        ordered.forEach { p ->
            val pr = byId[p.id]
            val aiCount = pr?.bypass?.values?.count { it } ?: 0
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
                    .joinToString(" · ") { s -> s.title + " " + (pr.marks[s.id] ?: "") } + " · ${pr.via} ${pr.latencyMs} мс"
            }
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(Modifier.size(10.dp).background(dot, CircleShape))
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(p.title, style = MaterialTheme.typography.bodyLarge)
                    Text(line, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (providerId == p.id) Text("✓", color = MaterialTheme.colorScheme.primary)
                else TextButton(onClick = {
                    providerId = p.id
                    prefs.aiDnsProvider = p.id
                    if (on) turnOn(p.id)
                }) { Text("выбрать") }
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
            NoteText("Сейчас в системе: $sysDns. Нужен, только если у выбранного сервера нет обычного DNS (только DoH/DoT).")
            SettingRow("Применить сервер как частный DNS", onClick = {
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
                AiDns.disable(ctx)
                prefs.aiDnsEnabled = false
                on = false
                refreshSys(); status = r.message
                vpn.restartIfActive()
            })
        }
    }
}
