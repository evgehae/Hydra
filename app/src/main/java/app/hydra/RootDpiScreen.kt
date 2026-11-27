package app.hydra

import android.widget.Toast
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Единый выбор интернет-протокола (вместо двух пунктов «IPv6 через туннель» и «Семейство адресов»):
 * Авто — Гидра сама, IPv4 — только IPv4, IPv6 — только IPv6, Оба — оба, IPv6 первым.
 */
@Composable
fun IpModeRow(prefs: Prefs, vpn: VpnController) {
    val ctx = LocalContext.current
    var mode by remember { mutableStateOf(Ext.ipMode(ctx)) }
    LaunchedEffect(Unit) {
        // один раз переносим старый тумблер «IPv6 через туннель» в общий выбор; root-обход 4PDA убран
        if (!Ext.bool(ctx, "ip_unified")) {
            if (prefs.ipv6 && Ext.ipMode(ctx) == "auto") { Ext.setIpMode(ctx, "both"); mode = "both" }
            Ext.setBool(ctx, "ip_unified", true)
            Ext.setBool(ctx, "root4pda", false)
        }
    }
    SettingRow(
        "Интернет-протокол (IPv4 / IPv6)",
        subtitle = "Авто — Гидра сама выбирает для этой сети (рекомендуется). IPv4 — быстрее и без зависаний. " +
            "IPv6 — другие дата-центры. Оба — пробует оба, IPv6 первым. Если нужного семейства в сети нет, Гидра откатится на другое.",
        value = Ext.ipModeTitle(mode),
        onClick = {
            val order = listOf("auto", "v4", "v6", "both")
            mode = order[(order.indexOf(mode) + 1) % order.size]
            Ext.setIpMode(ctx, mode)
            prefs.ipv6 = (mode == "v6" || mode == "both")
            vpn.restartIfActive()
        }
    )
}

/** Блок «Общая база опыта» для экрана «Дополнительно». */
@Composable
fun NetRootSection(prefs: Prefs, vpn: VpnController) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()

    SectionTitle("Общая база опыта")
    var auto by remember { mutableStateOf(Telemetry.enabled(ctx)) }
    var preview by remember { mutableStateOf("") }
    NoteText("Гидра учится на опыте пользователей: какие порты, стратегии и DNS-серверы работают у разных провайдеров. " +
        "Отправляются только технические данные: БЕЗ вашего IP, названия Wi-Fi, списка приложений и содержимого трафика.")
    SettingSwitchRow(
        "Делиться опытом автоматически",
        "Раз в сутки, анонимно, через Wi-Fi или мобильную сеть. Выключить можно в любой момент.",
        auto
    ) { v ->
        auto = v
        Telemetry.setEnabled(ctx, v)
        if (v) Telemetry.sendNow(ctx) { m -> Toast.makeText(ctx, m, Toast.LENGTH_LONG).show() }
    }
    SettingRow("Что именно отправляется", subtitle = "Показать точный текст, который уходит на сервер",
        onClick = { preview = Telemetry.buildPayload(ctx) })
    if (preview.isNotBlank()) NoteText(preview.take(1800) + if (preview.length > 1800) "…" else "")
    SettingRow(
        "Отправить опыт сейчас",
        subtitle = if (Telemetry.lastSent(ctx) > 0) "Последняя отправка: " +
            java.text.SimpleDateFormat("dd.MM HH:mm", java.util.Locale.getDefault()).format(java.util.Date(Telemetry.lastSent(ctx))) else "Ещё не отправлялось",
        onClick = { Telemetry.sendNow(ctx) { m -> Toast.makeText(ctx, m, Toast.LENGTH_LONG).show() } }
    )
    SettingRow(
        "Поделиться накопленным опытом",
        subtitle = "Отправить автору список рабочих конфигов этого телефона (без личных данных) — он попадёт в общую базу для новых пользователей",
        onClick = { shareReport(ctx, Priors.export()) }
    )
    SettingRow(
        "Обновить общую базу опыта",
        subtitle = "Раз в сутки Гидра делает это сама",
        onClick = {
            scope.launch {
                val r = withContext(Dispatchers.IO) { Priors.maybeSync(ctx, force = true) }
                Toast.makeText(ctx, r.ifBlank { "готово" }, Toast.LENGTH_LONG).show()
            }
        }
    )
}


/** Один раз просим согласие на автоматический обмен опытом: по умолчанию ничего не отправляется. */
@Composable
fun ShareConsentDialog(onClose: () -> Unit) {
    val ctx = LocalContext.current
    androidx.compose.material3.AlertDialog(
        onDismissRequest = { Telemetry.markAsked(ctx); onClose() },
        title = { androidx.compose.material3.Text("Помогите улучшить Гидру") },
        text = {
            androidx.compose.material3.Text(
                "Гидра может раз в сутки анонимно отправлять разработчику, какие порты, стратегии и DNS-серверы работают у вашего провайдера. " +
                    "Так новые пользователи получают рабочие настройки сразу.\n\n" +
                    "НЕ отправляется: ваш IP-адрес, название Wi-Fi, список приложений, содержимое трафика. " +
                    "Точный текст можно посмотреть в «Дополнительно → Общая база опыта». Выключить можно в любой момент."
            )
        },
        confirmButton = {
            androidx.compose.material3.TextButton(onClick = {
                Telemetry.setEnabled(ctx, true)
                Telemetry.sendNow(ctx)
                onClose()
            }) { androidx.compose.material3.Text("Делиться") }
        },
        dismissButton = {
            androidx.compose.material3.TextButton(onClick = { Telemetry.markAsked(ctx); onClose() }) {
                androidx.compose.material3.Text("Не сейчас")
            }
        }
    )
}
