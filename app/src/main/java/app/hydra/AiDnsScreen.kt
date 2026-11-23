package app.hydra

import android.widget.Toast
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp

@Composable
fun AiDnsScreen(prefs: Prefs, onBack: () -> Unit) {
    val ctx = LocalContext.current
    var enabled by remember { mutableStateOf(prefs.aiDnsEnabled) }
    var providerId by remember { mutableStateOf(prefs.aiDnsProvider) }
    var enabledSvc by remember {
        mutableStateOf(prefs.aiDnsServices.split(',').map { it.trim() }.filter { it.isNotEmpty() }.toSet())
    }
    var status by remember { mutableStateOf("Выбери DNS и сервисы, затем «Проверить и применить».") }
    var busy by remember { mutableStateOf(false) }
    var lastHits by remember { mutableStateOf<List<AiDns.ResolveHit>>(emptyList()) }

    SubPage("Обход ИИ (AI-DNS)", onBack) {
        SettingSwitchRow(
            "Обход ИИ-сервисов",
            "DoH → карта IP прокси → локальный DNS в VPN (без root). WARP сам по себе ИИ часто не открывает.",
            enabled
        ) {
            enabled = it
            prefs.aiDnsEnabled = it
            if (!it) {
                AiDns.clearHosts()
                status = "Выключено"
            }
        }

        SectionLabel("DNS-сервер (DoH)")
        RowDivider()
        for (p in AiDns.providers) {
            SettingRow(
                p.title,
                subtitle = p.dohUrl.removePrefix("https://").take(48) +
                    (if (p.note.isNotEmpty()) " · ${p.note}" else ""),
                value = if (providerId == p.id) "✓" else null,
                onClick = {
                    providerId = p.id
                    prefs.aiDnsProvider = p.id
                }
            )
        }

        SectionLabel("Сервисы")
        RowDivider()
        for (s in AiDns.services) {
            val on = s.id in enabledSvc
            SettingSwitchRow(s.title, "${s.domains.size} имён", on) { checked ->
                enabledSvc = if (checked) enabledSvc + s.id else enabledSvc - s.id
                prefs.aiDnsServices = enabledSvc.joinToString(",")
            }
        }

        Spacer(Modifier.height(12.dp))
        Text(
            status,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 16.dp)
        )
        if (lastHits.isNotEmpty()) {
            Spacer(Modifier.height(8.dp))
            Text(
                lastHits.take(14).joinToString("\n") {
                    "${it.domain} → ${it.ip}" + if (it.isProxyGuess) " (подмена?)" else ""
                } + if (lastHits.size > 14) "\n…" else "",
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(horizontal = 16.dp)
            )
        }

        Spacer(Modifier.height(16.dp))
        Button(
            onClick = {
                if (busy) return@Button
                if (!enabled) {
                    Toast.makeText(ctx, "Сначала включи обход", Toast.LENGTH_SHORT).show()
                    return@Button
                }
                busy = true
                status = "Спрашиваю DoH…"
                AiDns.resolveAll(ctx, providerId, enabledSvc) { ok, msg, hits ->
                    busy = false
                    lastHits = hits
                    status = if (ok) msg else "Ошибка: $msg"
                    Toast.makeText(ctx, status, Toast.LENGTH_LONG).show()
                }
            },
            enabled = !busy,
            modifier = Modifier.padding(horizontal = 16.dp)
        ) {
            Text(if (busy) "Проверяю…" else "Проверить и применить")
        }
        Spacer(Modifier.height(8.dp))
        OutlinedButton(
            onClick = {
                AiDns.clearHosts()
                lastHits = emptyList()
                status = "hosts очищен (если был root)"
            },
            modifier = Modifier.padding(horizontal = 16.dp)
        ) { Text("Сбросить hosts") }

        NoteText(
            "1) Выбери DoH и сервисы → Проверить и применить.\n" +
                "2) Переподключи VPN — DNS станет 127.0.0.1 (локальная подмена).\n" +
                "3) AI-приложения должны быть в split (или выключи split).\n" +
                "WARP-IP Cloudflare для ChatGPT/Claude часто режется — нужен именно прокси из DoH."
        )
    }
}
