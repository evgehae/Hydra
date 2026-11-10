package app.hydra

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp

/** «Дополнительно»: список как в 1.1.1.1. */
@Composable
fun AdvancedScreen(onBack: () -> Unit, onConn: () -> Unit, onMore: () -> Unit) {
    SubPage(stringResource(R.string.menu_advanced), onBack) {
        Spacer(Modifier.height(16.dp))
        RowDivider()
        SettingRow(stringResource(R.string.conn_params), onClick = onConn)
        SettingRow(stringResource(R.string.adv_more), stringResource(R.string.adv_more_sub), onClick = onMore)
    }
}

/** «Параметры подключения»: приложения, маршруты, DNS, протокол, SNI, конечная точка, сбросы. */
@Composable
fun ConnScreen(
    prefs: Prefs,
    account: AccountController,
    vpn: VpnController,
    onBack: () -> Unit,
    onApps: () -> Unit,
    onRoutes: () -> Unit,
    onDns: () -> Unit,
    onResetAll: () -> Unit
) {
    var sni by remember { mutableStateOf(prefs.customSni) }
    var ep by remember { mutableStateOf(prefs.customEndpoint) }
    var proto by remember { mutableStateOf(prefs.protocol) }
    var dlg by remember { mutableStateOf("") } // sni | ep | proto | keys | all

    val protoName = stringResource(
        when (proto) {
            "masque" -> R.string.proto_masque_chip
            "wg" -> R.string.proto_wg_chip
            else -> R.string.proto_auto
        }
    )
    val dflt = stringResource(R.string.value_default)

    SubPage(stringResource(R.string.conn_params), onBack) {
        Spacer(Modifier.height(16.dp))
        RowDivider()
        SettingRow(stringResource(R.string.conn_apps), onClick = onApps)
        SettingRow(stringResource(R.string.conn_routes), onClick = onRoutes)
        SettingRow(stringResource(R.string.conn_dns), onClick = onDns)
        SettingRow(stringResource(R.string.conn_proto), value = protoName, onClick = { dlg = "proto" })
        NoteText(stringResource(R.string.proto_hint))
        SettingRow(stringResource(R.string.conn_reset_keys), onClick = { dlg = "keys" })
        SettingRow(stringResource(R.string.conn_reset_all), onClick = { dlg = "all" })
        SettingRow(
            stringResource(R.string.conn_sni), stringResource(R.string.conn_sni_sub),
            value = if (sni.isEmpty()) dflt else sni, onClick = { dlg = "sni" }
        )
        SettingRow(
            stringResource(R.string.conn_endpoint), stringResource(R.string.conn_endpoint_sub),
            value = if (ep.isEmpty()) dflt else ep, onClick = { dlg = "ep" }
        )
        Spacer(Modifier.height(24.dp))
    }

    when (dlg) {
        "sni" -> TextDialog(
            stringResource(R.string.conn_sni), sni, stringResource(R.string.conn_sni_hint),
            onDismiss = { dlg = "" },
            onApply = { sni = it; prefs.customSni = it; dlg = ""; vpn.restartIfActive() },
            onReset = { sni = ""; prefs.customSni = ""; dlg = ""; vpn.restartIfActive() }
        )
        "ep" -> TextDialog(
            stringResource(R.string.conn_endpoint), ep, stringResource(R.string.conn_endpoint_hint),
            onDismiss = { dlg = "" },
            onApply = { ep = it; prefs.customEndpoint = it; dlg = ""; vpn.restartIfActive() },
            onReset = { ep = ""; prefs.customEndpoint = ""; dlg = ""; vpn.restartIfActive() }
        )
        "proto" -> AlertDialog(
            onDismissRequest = { dlg = "" },
            title = { Text(stringResource(R.string.conn_proto)) },
            text = {
                Column {
                    listOf(
                        "auto" to R.string.proto_auto,
                        "masque" to R.string.proto_masque_chip,
                        "wg" to R.string.proto_wg_chip
                    ).forEach { (code, res) ->
                        Row(
                            Modifier.fillMaxWidth().clickable {
                                proto = code
                                prefs.protocol = code
                                dlg = ""
                                vpn.restartIfActive()
                            },
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            RadioButton(selected = proto == code, onClick = null)
                            Spacer(Modifier.width(12.dp))
                            Text(stringResource(res), modifier = Modifier.padding(vertical = 12.dp))
                        }
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { dlg = "" }) { Text(stringResource(R.string.btn_cancel)) } }
        )
        "keys" -> ConfirmDialog(
            stringResource(R.string.conn_reset_keys), stringResource(R.string.conn_reset_keys_q),
            onDismiss = { dlg = "" },
            onOk = {
                dlg = ""
                vpn.stop()
                account.resetKeys()
            }
        )
        "all" -> ConfirmDialog(
            stringResource(R.string.conn_reset_all), stringResource(R.string.conn_reset_all_q),
            onDismiss = { dlg = "" },
            onOk = {
                dlg = ""
                if (vpn.active) vpn.stop()
                prefs.resetAll()
                onResetAll()
            }
        )
    }
}

/** «Параметры DNS»: свой DNS внутри туннеля. */
@Composable
fun DnsScreen(prefs: Prefs, vpn: VpnController, onBack: () -> Unit) {
    var on by remember { mutableStateOf(prefs.customDnsOn) }
    var dns by remember { mutableStateOf(prefs.customDns) }
    var edit by remember { mutableStateOf(false) }

    SubPage(stringResource(R.string.conn_dns), onBack) {
        NoteText(stringResource(R.string.dns_note))
        RowDivider()
        SettingSwitchRow(stringResource(R.string.dns_use), checked = on) {
            on = it
            prefs.customDnsOn = it
            vpn.restartIfActive()
        }
        SettingRow(
            stringResource(R.string.dns_server),
            value = if (dns.isEmpty()) stringResource(R.string.dns_default) else dns,
            onClick = { edit = true }
        )
        NoteText(stringResource(R.string.dns_soon))
    }
    if (edit) {
        TextDialog(
            stringResource(R.string.dns_server), dns, stringResource(R.string.dns_hint),
            onDismiss = { edit = false },
            onApply = { dns = it; prefs.customDns = it; edit = false; if (on) vpn.restartIfActive() },
            onReset = { dns = ""; prefs.customDns = ""; edit = false; if (on) vpn.restartIfActive() }
        )
    }
}

/** «Исключённые маршруты»: подсети, которые идут напрямую. */
@Composable
fun RoutesScreen(prefs: Prefs, vpn: VpnController, onBack: () -> Unit) {
    fun parse(s: String) = s.split(',', ';', ' ', '\n').map { it.trim() }.filter { it.isNotEmpty() }
    var routes by remember { mutableStateOf(parse(prefs.excludedRoutes)) }
    var add by remember { mutableStateOf(false) }

    fun save(list: List<String>) {
        routes = list
        prefs.excludedRoutes = list.joinToString(",")
        vpn.restartIfActive()
    }

    SubPage(stringResource(R.string.conn_routes), onBack) {
        SectionLabel(stringResource(R.string.routes_list))
        RowDivider()
        routes.forEach { r ->
            Row(
                Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(r, Modifier.weight(1f).padding(vertical = 14.dp), style = MaterialTheme.typography.bodyLarge)
                IconButton(onClick = { save(routes - r) }) { Icon(Icons.Filled.Close, contentDescription = null) }
            }
            RowDivider()
        }
        NoteText(stringResource(R.string.routes_note))
        Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(10.dp)) {
            Button(onClick = { add = true }, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.routes_add)) }
            OutlinedButton(onClick = { save(parse(Prefs.DEFAULT_ROUTES)) }, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.routes_default))
            }
        }
        Spacer(Modifier.height(24.dp))
    }
    if (add) {
        TextDialog(
            stringResource(R.string.routes_add), "", stringResource(R.string.routes_hint),
            onDismiss = { add = false },
            onApply = { v ->
                add = false
                val ok = Regex("[0-9a-fA-F:.]+(/[0-9]{1,3})?").matches(v)
                if (ok && v !in routes) save(routes + v)
            }
        )
    }
}
