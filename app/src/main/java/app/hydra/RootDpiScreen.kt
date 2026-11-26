package app.hydra

import android.widget.Toast
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Блок «Сеть и root» для экрана «Дополнительно»: семейство адресов, DPI-обход для 4PDA, обмен опытом. */
@Composable
fun NetRootSection(prefs: Prefs, vpn: VpnController) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var mode by remember { mutableStateOf(Ext.ipMode(ctx)) }
    var info by remember { mutableStateOf("проверяю root…") }
    var r4 by remember { mutableStateOf(Ext.bool(ctx, "root4pda")) }
    var busy by remember { mutableStateOf(false) }
    var msg by remember { mutableStateOf("") }

    fun refresh() {
        scope.launch {
            val i = withContext(Dispatchers.IO) { RootDpi.detect() }
            info = i.text
        }
    }
    LaunchedEffect(Unit) { refresh() }

    SectionTitle("Сеть и root")

    SettingRow(
        "Семейство адресов (IPv4 / IPv6)",
        subtitle = "Как искать путь до Cloudflare. Авто — как раньше; «только IPv6» часто даёт другие дата-центры; " +
            "«вместе» пробует оба, IPv6 первым. Если нужного семейства нет, Гидра сама откатится на другое.",
        value = Ext.ipModeTitle(mode),
        onClick = {
            val order = listOf("auto", "v4", "v6", "both")
            mode = order[(order.indexOf(mode) + 1) % order.size]
            Ext.setIpMode(ctx, mode)
            vpn.restartIfActive()
        }
    )

    NoteText("Root: $info")
    SettingSwitchRow(
        "Обход DPI для 4PDA (root, nfqws2)",
        subtitle = "Управляет модулем nfqws2-android-ext: включает его, держит рабочим при VPN, добавляет домены 4PDA и выводит клиент 4PDA из туннеля Гидры",
        checked = r4
    ) { v ->
        r4 = v
        Ext.setBool(ctx, "root4pda", v)
        if (v) {
            RootDpi.applyPolicy(ctx)
            busy = true
            scope.launch {
                val m = withContext(Dispatchers.IO) { RootDpi.ensure4pda(ctx) }
                msg = m; busy = false; refresh()
                vpn.restartIfActive()
            }
        }
    }
    SettingRow("Запустить модуль", onClick = {
        scope.launch { msg = withContext(Dispatchers.IO) { RootDpi.start() }; refresh() }
    })
    SettingRow("Остановить модуль", onClick = {
        scope.launch { msg = withContext(Dispatchers.IO) { RootDpi.stop() }; refresh() }
    })
    if (msg.isNotBlank()) Text(msg.take(300), style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(16.dp))

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
