package app.hydra

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp

/** «Дополнительно»: все настройки в одном меню, как в 1.1.1.1. */
@Composable
fun AdvancedScreen(
    prefs: Prefs,
    account: AccountController,
    vpn: VpnController,
    onBack: () -> Unit,
    onApps: () -> Unit,
    onRoutes: () -> Unit,
    onDns: () -> Unit,
    onResetAll: () -> Unit,
    onLanguageChanged: () -> Unit
) {
    val ctx = LocalContext.current
    var sni by remember { mutableStateOf(prefs.customSni) }
    var ep by remember { mutableStateOf(prefs.customEndpoint) }
    var proto by remember { mutableStateOf(prefs.protocol) }
    var channel by remember { mutableStateOf(prefs.channel) }
    var lang by remember { mutableStateOf(prefs.lang) }
    var block by remember { mutableStateOf(prefs.blockedColos) }
    var allow by remember { mutableStateOf(prefs.allowColos) }
    var fallback by remember { mutableStateOf(prefs.fallbackAny) }
    var auto by remember { mutableStateOf(prefs.autoStart) }
    var dlg by remember { mutableStateOf("") }
    var showLicenses by remember { mutableStateOf(false) }

    val openVpnSettings: () -> Unit = {
        try { ctx.startActivity(Intent(Settings.ACTION_VPN_SETTINGS)) } catch (t: Throwable) { }
    }
    val openBattery: () -> Unit = {
        try {
            ctx.startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:" + ctx.packageName)))
        } catch (t: Throwable) {
            try { ctx.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) } catch (t2: Throwable) { }
        }
    }
    val openAutostart: () -> Unit = {
        try {
            ctx.startActivity(
                Intent().setComponent(
                    ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")
                )
            )
        } catch (t: Throwable) {
            try {
                ctx.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + ctx.packageName)))
            } catch (t2: Throwable) { }
        }
    }

    val dflt = stringResource(R.string.value_default)
    val none = stringResource(R.string.value_none)
    val protoOpts = listOf(
        "auto" to stringResource(R.string.proto_auto),
        "masque" to stringResource(R.string.proto_masque_chip),
        "wg" to stringResource(R.string.proto_wg_chip)
    )
    val channelOpts = listOf(
        "auto" to stringResource(R.string.channel_auto),
        "cell" to stringResource(R.string.channel_cell)
    )
    val langOpts = listOf(
        "system" to stringResource(R.string.lang_system),
        "en" to stringResource(R.string.lang_en),
        "ru" to stringResource(R.string.lang_ru)
    )
    val engine = remember { try { mobile.Mobile.version() } catch (t: Throwable) { "n/a" } }

    SubPage(stringResource(R.string.menu_advanced), onBack) {
        SectionLabel(stringResource(R.string.adv_sec_apps))
        RowDivider()
        SettingRow(stringResource(R.string.conn_apps), onClick = onApps)
        SettingRow(stringResource(R.string.conn_routes), onClick = onRoutes)
        SettingRow(stringResource(R.string.conn_dns), onClick = onDns)

        SectionLabel(stringResource(R.string.adv_sec_conn))
        RowDivider()
        SettingRow(stringResource(R.string.conn_proto), subtitle = stringResource(R.string.proto_hint),
            value = protoOpts.firstOrNull { it.first == proto }?.second, onClick = { dlg = "proto" })
        SettingRow(stringResource(R.string.channel_title), subtitle = stringResource(R.string.channel_hint),
            value = channelOpts.firstOrNull { it.first == channel }?.second, onClick = { dlg = "channel" })
        SettingRow(
            stringResource(R.string.conn_sni), stringResource(R.string.conn_sni_sub),
            value = if (sni.isEmpty()) dflt else sni, onClick = { dlg = "sni" }
        )
        SettingRow(
            stringResource(R.string.conn_endpoint), stringResource(R.string.conn_endpoint_sub),
            value = if (ep.isEmpty()) dflt else ep, onClick = { dlg = "ep" }
        )

        SectionLabel(stringResource(R.string.colo_title))
        RowDivider()
        SettingRow(stringResource(R.string.colo_block), value = block.ifEmpty { none }, onClick = { dlg = "block" })
        SettingRow(stringResource(R.string.colo_allow), value = allow.ifEmpty { none }, onClick = { dlg = "allow" })
        SettingSwitchRow(stringResource(R.string.fallback_any), stringResource(R.string.fallback_hint), fallback) {
            fallback = it
            prefs.fallbackAny = it
            vpn.restartIfActive()
        }
        SettingRow(stringResource(R.string.colo_reset), onClick = {
            block = prefs.defaultBlockedColos()
            prefs.blockedColos = block
            allow = ""
            prefs.allowColos = ""
            vpn.restartIfActive()
        })
        NoteText(stringResource(R.string.colo_hint))

        SectionLabel(stringResource(R.string.persist_title))
        RowDivider()
        SettingSwitchRow(stringResource(R.string.settings_autostart), stringResource(R.string.persist_hint), auto) {
            auto = it
            prefs.autoStart = it
        }
        SettingRow(stringResource(R.string.btn_always_on), onClick = openVpnSettings)
        SettingRow(stringResource(R.string.btn_battery), onClick = openBattery)
        SettingRow(stringResource(R.string.btn_autostart_xiaomi), onClick = openAutostart)
        NoteText(stringResource(R.string.kill_info))

        SectionLabel(stringResource(R.string.adv_sec_other))
        RowDivider()
        SettingRow(stringResource(R.string.settings_language),
            value = langOpts.firstOrNull { it.first == lang }?.second, onClick = { dlg = "lang" })
        SettingRow(stringResource(R.string.conn_reset_keys), onClick = { dlg = "keys" })
        SettingRow(stringResource(R.string.conn_reset_all), onClick = { dlg = "all" })
        SettingRow(stringResource(R.string.about_title), stringResource(R.string.engine_label, engine),
            onClick = { showLicenses = !showLicenses })
        if (showLicenses) {
            NoteText(stringResource(R.string.about_text))
            NoteText(stringResource(R.string.licenses_text))
        }
        Spacer(Modifier.height(24.dp))
    }

    when (dlg) {
        "proto" -> ChoiceDialog(stringResource(R.string.conn_proto), protoOpts, proto,
            onPick = { proto = it; prefs.protocol = it; dlg = ""; vpn.restartIfActive() }, onDismiss = { dlg = "" })
        "channel" -> ChoiceDialog(stringResource(R.string.channel_title), channelOpts, channel,
            onPick = { channel = it; prefs.channel = it; dlg = ""; vpn.restartIfActive() }, onDismiss = { dlg = "" })
        "lang" -> ChoiceDialog(stringResource(R.string.settings_language), langOpts, lang,
            onPick = { lang = it; prefs.lang = it; dlg = ""; onLanguageChanged() }, onDismiss = { dlg = "" })
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
        "block" -> TextDialog(
            stringResource(R.string.colo_block), block, "DME",
            onDismiss = { dlg = "" },
            onApply = { block = it.uppercase(); prefs.blockedColos = block; dlg = ""; vpn.restartIfActive() },
            onReset = { block = ""; prefs.blockedColos = ""; dlg = ""; vpn.restartIfActive() }
        )
        "allow" -> TextDialog(
            stringResource(R.string.colo_allow), allow, "HEL, FRA, AMS",
            onDismiss = { dlg = "" },
            onApply = { allow = it.uppercase(); prefs.allowColos = allow; dlg = ""; vpn.restartIfActive() },
            onReset = { allow = ""; prefs.allowColos = ""; dlg = ""; vpn.restartIfActive() }
        )
        "keys" -> ConfirmDialog(
            stringResource(R.string.conn_reset_keys), stringResource(R.string.conn_reset_keys_q),
            onDismiss = { dlg = "" },
            onOk = { dlg = ""; vpn.stop(); account.resetKeys() }
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
