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
 * Один экран обхода ИИ.
 * «Параметры DNS» в приложении — только IP внутри WARP, не сюда.
 * Здесь: подбор Smart DNS + применение (частный DNS / только ИИ).
 */
@Composable
fun AiDnsScreen(prefs: Prefs, onBack: () -> Unit) {
    val ctx = LocalContext.current

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
    var sysDns by remember {
        mutableStateOf(AiDns.readPrivateDns(ctx).let { (m, h) ->
            if (h.isBlank()) m else "$m · $h"
        })
    }

    fun refreshSys() {
        sysDns = AiDns.readPrivateDns(ctx).let { (m, h) -> if (h.isBlank()) m else "$m · $h" }
    }

    SubPage("Обход ИИ", onBack = onBack) {
        NoteText(
            "Это не «Параметры DNS» WARP. Здесь Smart DNS для ChatGPT/Claude/Grok/Gemini.\n" +
                "Сейчас в системе: $sysDns"
        )

        SectionTitle("1. Проверить DNS")
        SettingRow(
            if (busy) "Проверяю…" else "Проверить все серверы",
            subtitle = "Красный = мёртвый · Жёлтый = живой без ИИ · Зелёный = открывает ИИ",
            onClick = {
                if (busy) return@SettingRow
                busy = true
                status = "Опрос DoH (лучше на секунду выключить VPN)…"
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
                        status = "Лучший: ${best.title} — ${pr?.detail ?: ""}"
                    } else {
                        status = "Никто не дал подмену. Выключи VPN и проверь снова (DoH через WARP часто «мертвит» серверы)."
                    }
                    refreshSys()
                }
            }
        )

        val list = if (probes.isNotEmpty()) {
            probes.sortedByDescending { p ->
                (if (p.alive) 50 else 0) + p.bypass.values.count { it } * 20 - (p.latencyMs / 100).toInt()
            }
        } else null

        if (list != null) {
            list.forEach { pr ->
                val p = AiDns.provider(pr.providerId)
                val aiCount = pr.bypass.values.count { it }
                val (dotColor, label) = when {
                    !pr.alive -> Color(0xFFE53935) to "мёртвый"
                    aiCount > 0 -> Color(0xFF43A047) to ("ИИ: " + AiDns.services.filter { pr.bypass[it.id] == true }.joinToString { it.title })
                    else -> Color(0xFFFDD835) to "живой, без ИИ"
                }
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        Modifier
                            .size(10.dp)
                            .background(dotColor, CircleShape)
                    )
                    if (aiCount > 0) {
                        Spacer(Modifier.width(4.dp))
                        Box(
                            Modifier
                                .size(10.dp)
                                .background(Color(0xFF43A047), CircleShape)
                        )
                    }
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(p.title, style = MaterialTheme.typography.bodyLarge)
                        Text(
                            "$label · ${pr.latencyMs} мс",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    if (providerId == p.id) {
                        Text("✓", color = MaterialTheme.colorScheme.primary)
                    } else {
                        TextButton(onClick = {
                            providerId = p.id
                            prefs.aiDnsProvider = p.id
                        }) { Text("выбрать") }
                    }
                }
                RowDivider()
            }
        } else {
            AiDns.providers.filter { it.id != "cloudflare" }.forEach { p ->
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
                value = if (on) "вкл" else "выкл",
                onClick = {
                    enabledSvc = if (on) enabledSvc - svc.id else enabledSvc + svc.id
                    prefs.aiDnsServices = enabledSvc.joinToString(",")
                }
            )
        }

        if (status.isNotBlank()) {
            Text(
                status,
                color = MaterialTheme.colorScheme.primary,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(16.dp)
            )
        }

        SectionTitle("2. Включить")
        Button(
            onClick = {
                // Главный рабочий путь — частный DNS (как у тебя руками)
                prefs.aiDnsEnabled = true
                prefs.aiDnsProvider = providerId
                val r = AiDns.applyPrivateDns(ctx, providerId)
                refreshSys()
                status = r.message
                Toast.makeText(ctx, r.message.take(120), Toast.LENGTH_LONG).show()
            },
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)
        ) {
            Text("Включить (частный DNS)")
        }

        OutlinedButton(
            onClick = {
                if (busy) return@OutlinedButton
                busy = true
                status = "Карта только-ИИ…"
                prefs.aiDnsEnabled = true
                AiDns.activateAiOnly(ctx, providerId, enabledSvc) { r ->
                    busy = false
                    status = r.message
                    Toast.makeText(ctx, r.message.take(100), Toast.LENGTH_LONG).show()
                }
            },
            enabled = !busy,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)
        ) {
            Text("Только домены ИИ (hosts / local DNS)")
        }

        OutlinedButton(
            onClick = {
                val r = AiDns.disablePrivateDns(ctx)
                RootHelper.disableDnsRedirect()
                AiDns.clearHosts()
                LocalDnsServer.stop()
                prefs.aiDnsEnabled = false
                refreshSys()
                status = r.message
            },
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)
        ) {
            Text("Выключить обход")
        }

        NoteText(
            "«Включить (частный DNS)» — то, что уже открывает тебе ИИ вручную.\n" +
                "С root пишется само; без root — hostname в буфер и экран настроек.\n" +
                "«Параметры DNS» в меню WARP — другие: IP 1.1.1.1 внутри туннеля, не Smart DNS.\n" +
                "Перед проверкой серверов лучше выключить VPN на 30 с."
        )
    }
}
