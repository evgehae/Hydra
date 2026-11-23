package app.hydra

import android.widget.Toast
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp

/**
 * Обход ИИ внутри приложения (без увода в системные «Частный DNS»).
 * Основное: подбор живого DNS → «Только ИИ» (карта доменов + hosts/local DNS).
 * Опционально: весь телефон через системный Private DNS — внизу, мелко.
 */
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

    SubPage("Обход ИИ", onBack = onBack) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(Modifier.weight(1f)) {
                Text("Обход включён", style = MaterialTheme.typography.bodyLarge)
                Text(
                    "Только домены ИИ → прокси. Остальной трафик без «левого» DNS.",
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
                        status = "Выключено"
                    }
                }
            )
        }

        SectionTitle("Подбор DNS")
        SettingRow(
            if (busy) "Проверяю провайдеров…" else "Проверить, кто живой",
            subtitle = "ChatGPT · Claude · Grok · Gemini — кто открывается",
            onClick = {
                if (busy) return@SettingRow
                busy = true
                status = "Опрос…"
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
                        status = "Выбран ${best.title}"
                    } else status = "Подмены не найдены"
                }
            }
        )

        if (probes.isNotEmpty()) {
            probes.sortedByDescending { p ->
                (if (p.alive) 100 else 0) + p.bypass.values.count { it } * 10
            }.forEach { pr ->
                val p = AiDns.provider(pr.providerId)
                val titles = AiDns.services.filter { pr.bypass[it.id] == true }
                    .joinToString(", ") { it.title }
                val head = when {
                    !pr.alive -> "мёртвый"
                    titles.isNotEmpty() -> "✔ $titles"
                    else -> "живой, без ИИ"
                }
                SettingRow(
                    p.title,
                    subtitle = "$head · ${pr.latencyMs} мс",
                    value = if (providerId == p.id) "✓" else null,
                    onClick = {
                        providerId = p.id
                        prefs.aiDnsProvider = p.id
                    }
                )
            }
        } else {
            AiDns.providers.filter { it.id != "cloudflare" }.forEach { p ->
                SettingRow(
                    p.title,
                    subtitle = p.hostname,
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
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.padding(16.dp)
            )
        }

        Button(
            onClick = {
                if (busy) return@Button
                busy = true
                status = "Применяю только ИИ…"
                prefs.aiDnsEnabled = true
                enabled = true
                AiDns.activateAiOnly(ctx, providerId, enabledSvc) { r ->
                    busy = false
                    status = r.message
                    Toast.makeText(ctx, r.message.take(100), Toast.LENGTH_LONG).show()
                }
            },
            enabled = !busy,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)
        ) {
            Text(if (busy) "…" else "Применить (только ИИ)")
        }

        NoteText(
            "1) «Проверить, кто живой» → 2) «Применить (только ИИ)».\n" +
                "С root: hosts + redirect. Без root: переподключи VPN.\n" +
                "Пункт «Параметры DNS» в приложении — для DNS внутри WARP (IP), не для DoH-обхода ИИ."
        )

        // вторично, без акцента
        TextButton(
            onClick = {
                val r = AiDns.applyPrivateDns(ctx, providerId)
                status = r.message
                Toast.makeText(ctx, status.take(80), Toast.LENGTH_LONG).show()
            },
            modifier = Modifier.padding(horizontal = 8.dp)
        ) {
            Text("Дополнительно: частный DNS на весь телефон", style = MaterialTheme.typography.bodySmall)
        }
    }
}
