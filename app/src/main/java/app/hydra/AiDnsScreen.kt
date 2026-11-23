package app.hydra

import android.widget.Toast
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp

@Composable
fun AiDnsScreen(prefs: Prefs, onBack: () -> Unit) {
    val ctx = LocalContext.current

    var enabled by remember { mutableStateOf(prefs.aiDnsEnabled) }
    var providerId by remember { mutableStateOf(prefs.aiDnsProvider.ifBlank { "geodema" }) }
    var enabledSvc by remember {
        mutableStateOf(
            prefs.aiDnsServices.split(',').map { it.trim() }.filter { it.isNotEmpty() }.toSet()
                .ifEmpty { setOf("chatgpt", "claude", "grok", "gemini") }
        )
    }
    var busy by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }
    var probes by remember { mutableStateOf<List<AiDns.ProviderProbe>>(emptyList()) }
    var sysDns by remember {
        mutableStateOf(AiDns.readPrivateDns(ctx).let { (m, h) -> if (h.isBlank()) m else "$m · $h" })
    }

    fun refreshSys() {
        sysDns = AiDns.readPrivateDns(ctx).let { (m, h) -> if (h.isBlank()) m else "$m · $h" }
    }

    SubPage("Обход ИИ (AI-DNS)", onBack = onBack) {
        SectionTitle("Сейчас")
        SettingRow(
            "Частный DNS Android",
            subtitle = sysDns,
            value = "открыть",
            onClick = { AiDns.openPrivateDnsSettings(ctx) }
        )
        TextButton(onClick = { refreshSys() }, modifier = Modifier.padding(horizontal = 8.dp)) {
            Text("Обновить · local: ${LocalDnsServer.stats()}")
        }

        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(Modifier.weight(1f)) {
                Text("Обход ИИ", style = MaterialTheme.typography.bodyLarge)
                Text(
                    "Только ИИ-домены → IP прокси. Остальной интернет — обычный DNS.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Switch(
                checked = enabled,
                onCheckedChange = {
                    enabled = it
                    prefs.aiDnsEnabled = it
                    if (!it) {
                        AiDns.clearHosts()
                        RootHelper.disableDnsRedirect()
                        LocalDnsServer.setMap(emptyList())
                        LocalDnsServer.stop()
                        status = "Выключено (hosts/redirect сброшены)"
                    }
                }
            )
        }

        SectionTitle("1. Найти живые DNS")
        SettingRow(
            if (busy) "Проверяю…" else "Проверить все провайдеры",
            subtitle = "Кто жив и что открывает: ChatGPT, Claude, Grok, Gemini…",
            onClick = {
                if (busy) return@SettingRow
                busy = true
                status = "Опрос DoH (до 30 с)…"
                probes = emptyList()
                AiDns.probeProviders(
                    serviceIds = enabledSvc.toList().ifEmpty { AiDns.services.map { it.id } }
                ) { list ->
                    busy = false
                    probes = list
                    val best = AiDns.pickBest(list)
                    if (best != null) {
                        providerId = best.id
                        prefs.aiDnsProvider = best.id
                        val pr = list.find { it.providerId == best.id }
                        status = "Лучший: ${best.title} · ${pr?.detail ?: ""}"
                    } else {
                        status = "Подмены не найдено. Смени сеть или попробуй позже."
                    }
                }
            }
        )

        if (probes.isNotEmpty()) {
            probes.sortedByDescending { p ->
                (if (p.alive) 100 else 0) + p.bypass.values.count { it } * 10 - (p.latencyMs / 50).toInt()
            }.forEach { pr ->
                val p = AiDns.provider(pr.providerId)
                val bypassTitles = AiDns.services
                    .filter { pr.bypass[it.id] == true }
                    .joinToString(", ") { it.title }
                    .ifBlank { null }
                val head = when {
                    !pr.alive -> "✘ мёртвый"
                    bypassTitles != null -> "✔ $bypassTitles"
                    else -> "△ живой, без подмены ИИ"
                }
                SettingRow(
                    p.title,
                    subtitle = "$head · ${pr.latencyMs} мс\n${pr.detail}",
                    value = if (providerId == p.id) "выбран" else "выбрать",
                    onClick = {
                        providerId = p.id
                        prefs.aiDnsProvider = p.id
                    }
                )
            }
        } else {
            SectionTitle("Провайдеры")
            AiDns.providers.forEach { p ->
                SettingRow(
                    p.title,
                    subtitle = p.hostname + if (p.note.isNotBlank()) " · ${p.note}" else "",
                    value = if (providerId == p.id) "✓" else null,
                    onClick = {
                        providerId = p.id
                        prefs.aiDnsProvider = p.id
                    }
                )
            }
        }

        SectionTitle("Сервисы")
        AiDns.services.forEach { svc ->
            val on = svc.id in enabledSvc
            SettingRow(
                svc.title,
                subtitle = svc.probeDomain,
                value = if (on) "вкл" else "выкл",
                onClick = {
                    enabledSvc = if (on) enabledSvc - svc.id else enabledSvc + svc.id
                    prefs.aiDnsServices = enabledSvc.joinToString(",")
                }
            )
        }

        SectionTitle("2. Применить")
        if (status.isNotBlank()) {
            Text(
                status,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp)
            )
        }

        Button(
            onClick = {
                if (busy) return@Button
                busy = true
                status = "Строю карту только-ИИ…"
                prefs.aiDnsEnabled = true
                enabled = true
                prefs.aiDnsProvider = providerId
                AiDns.activateAiOnly(ctx, providerId, enabledSvc) { r ->
                    busy = false
                    status = r.message
                    Toast.makeText(ctx, r.message.take(120), Toast.LENGTH_LONG).show()
                }
            },
            enabled = !busy,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)
        ) {
            Text(if (busy) "Работаю…" else "Только ИИ (рекомендуется)")
        }

        OutlinedButton(
            onClick = {
                val r = AiDns.applyPrivateDns(ctx, providerId)
                refreshSys()
                status = "Весь телефон: " + r.message
                prefs.aiDnsEnabled = true
                enabled = true
                Toast.makeText(ctx, status.take(100), Toast.LENGTH_LONG).show()
            },
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)
        ) {
            Text("Весь телефон (частный DNS)")
        }

        OutlinedButton(
            onClick = {
                val r = AiDns.disablePrivateDns(ctx)
                RootHelper.disableDnsRedirect()
                AiDns.clearHosts()
                LocalDnsServer.stop()
                refreshSys()
                status = r.message
            },
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)
        ) {
            Text("Сбросить DNS / hosts / redirect")
        }

        NoteText(
            "«Только ИИ» — подмена только доменов ChatGPT/Claude/Grok/…\n" +
                "• С root: hosts + iptables redirect на локальный DNS (остальной интернет без «левого» DNS).\n" +
                "• Без root: карта + локальный DNS в VPN — переподключи VPN после применения.\n\n" +
                "«Весь телефон» — системный частный DNS (как ручная настройка, на все приложения).\n\n" +
                "Сначала «Проверить все провайдеры», потом «Только ИИ»."
        )
    }
}
