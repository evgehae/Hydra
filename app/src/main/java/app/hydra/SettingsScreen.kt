package app.hydra

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp

@Composable
fun SettingsScreen(prefs: Prefs, account: AccountController, onLanguageChanged: () -> Unit) {
    val clipboard = LocalClipboardManager.current
    var lang by remember { mutableStateOf(prefs.lang) }
    var channel by remember { mutableStateOf(prefs.channel) }
    var block by remember { mutableStateOf(prefs.blockedColos) }
    var allow by remember { mutableStateOf(prefs.allowColos) }
    var fallback by remember { mutableStateOf(prefs.fallbackAny) }
    var auto by remember { mutableStateOf(prefs.autoStart) }
    var proto by remember { mutableStateOf(prefs.protocol) }
    var editing by remember { mutableStateOf(false) }
    var conf by remember { mutableStateOf("") }
    val ctx = LocalContext.current
    val openVpnSettings: () -> Unit = {
        try { ctx.startActivity(Intent(Settings.ACTION_VPN_SETTINGS)) } catch (t: Throwable) { }
    }
    val openBattery: () -> Unit = {
        try {
            ctx.startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:" + ctx.packageName))
            )
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
                ctx.startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + ctx.packageName))
                )
            } catch (t2: Throwable) { }
        }
    }
    var note by remember { mutableStateOf("") }
    var wgNote by remember { mutableStateOf("") }
    var showLicenses by remember { mutableStateOf(false) }

    val copiedMsg = stringResource(R.string.account_copied)
    val nothingMsg = stringResource(R.string.account_nothing)
    val importedMsg = stringResource(R.string.account_imported)
    val wgCopiedMsg = stringResource(R.string.wg_copied)
    val wgNothingMsg = stringResource(R.string.wg_nothing)
    val wgImportedMsg = stringResource(R.string.wg_imported)
    val scheme = MaterialTheme.colorScheme

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 18.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        RainbowText(stringResource(R.string.settings_title))

        // Язык
        HCard(accent = NeonCyan) {
            SectionTitle(stringResource(R.string.settings_language), NeonCyan)
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(
                    "system" to R.string.lang_system,
                    "en" to R.string.lang_en,
                    "ru" to R.string.lang_ru
                ).forEach { (code, res) ->
                    FilterChip(
                        selected = lang == code,
                        onClick = {
                            if (lang != code) {
                                lang = code
                                prefs.lang = code
                                onLanguageChanged()
                            }
                        },
                        label = { Text(stringResource(res)) }
                    )
                }
            }
        }

        // Канал связи
        HCard(accent = NeonPink) {
            SectionTitle(stringResource(R.string.channel_title), NeonPink)
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("auto" to R.string.channel_auto, "cell" to R.string.channel_cell).forEach { (code, res) ->
                    FilterChip(
                        selected = channel == code,
                        onClick = {
                            channel = code
                            prefs.channel = code
                        },
                        label = { Text(stringResource(res)) }
                    )
                }
            }
            Text(
                stringResource(R.string.channel_hint),
                style = MaterialTheme.typography.bodySmall,
                color = scheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 6.dp)
            )
        }

        // Протокол
        HCard(accent = NeonCyan) {
            SectionTitle(stringResource(R.string.proto_title), NeonCyan)
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(
                    "auto" to R.string.proto_auto,
                    "masque" to R.string.proto_masque_chip,
                    "wg" to R.string.proto_wg_chip
                ).forEach { (code, res) ->
                    FilterChip(
                        selected = proto == code,
                        onClick = {
                            proto = code
                            prefs.protocol = code
                        },
                        label = { Text(stringResource(res)) }
                    )
                }
            }
            Text(
                stringResource(R.string.proto_hint),
                style = MaterialTheme.typography.bodySmall,
                color = scheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 6.dp)
            )
        }

        // Дата-центры Cloudflare
        HCard(accent = NeonViolet) {
            SectionTitle(stringResource(R.string.colo_title), NeonViolet)
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                value = block,
                onValueChange = {
                    block = it.uppercase()
                    prefs.blockedColos = block
                },
                label = { Text(stringResource(R.string.colo_block)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                value = allow,
                onValueChange = {
                    allow = it.uppercase()
                    prefs.allowColos = allow
                },
                label = { Text(stringResource(R.string.colo_allow)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                modifier = Modifier.fillMaxWidth()
            )
            Text(
                stringResource(R.string.colo_hint),
                style = MaterialTheme.typography.bodySmall,
                color = scheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 6.dp)
            )
            SwitchRow(stringResource(R.string.fallback_any), fallback) {
                fallback = it
                prefs.fallbackAny = it
            }
            Text(
                stringResource(R.string.fallback_hint),
                style = MaterialTheme.typography.bodySmall,
                color = scheme.onSurfaceVariant
            )
            TextButton(onClick = {
                block = prefs.defaultBlockedColos()
                prefs.blockedColos = block
                allow = ""
                prefs.allowColos = ""
            }) { Text(stringResource(R.string.colo_reset)) }
        }

        // Аккаунт WARP
        HCard(accent = NeonGreen) {
            SectionTitle(stringResource(R.string.account_title), NeonGreen)
            Spacer(Modifier.height(4.dp))
            Text(
                if (account.id.isEmpty()) {
                    stringResource(R.string.step_account_none)
                } else {
                    stringResource(R.string.step_account_ok, account.id.take(8))
                },
                style = MaterialTheme.typography.bodyMedium
            )
            Spacer(Modifier.height(10.dp))
            Button(
                onClick = { account.register() },
                enabled = !account.busy && account.id.isEmpty(),
                shape = RoundedCornerShape(14.dp),
                modifier = Modifier.fillMaxWidth().height(48.dp)
            ) {
                if (account.busy) {
                    CircularProgressIndicator(
                        Modifier.size(20.dp),
                        strokeWidth = 2.dp,
                        color = scheme.onPrimary
                    )
                } else {
                    Text(stringResource(R.string.action_register))
                }
            }
            Spacer(Modifier.height(8.dp))
            OutlinedButton(
                onClick = { account.registerViaCellular() },
                enabled = !account.busy && account.id.isEmpty(),
                modifier = Modifier.fillMaxWidth()
            ) { Text(stringResource(R.string.action_register_cell)) }
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = {
                        val s = account.export()
                        if (s.isEmpty()) {
                            note = nothingMsg
                        } else {
                            clipboard.setText(AnnotatedString(s))
                            note = copiedMsg
                        }
                    },
                    modifier = Modifier.weight(1f)
                ) { Text(stringResource(R.string.account_copy)) }
                OutlinedButton(
                    onClick = {
                        val text = clipboard.getText()?.text.orEmpty()
                        val err = account.importFrom(text)
                        note = if (err.isEmpty()) importedMsg else err
                    },
                    modifier = Modifier.weight(1f)
                ) { Text(stringResource(R.string.account_paste)) }
            }
            Text(
                stringResource(R.string.account_hint),
                style = MaterialTheme.typography.bodySmall,
                color = scheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 6.dp)
            )
            if (note.isNotEmpty()) {
                Text(
                    note,
                    style = MaterialTheme.typography.bodySmall,
                    color = scheme.primary,
                    modifier = Modifier.padding(top = 6.dp)
                )
            }
            if (account.failKind.isNotEmpty()) {
                Text(
                    failText(account.failKind),
                    style = MaterialTheme.typography.bodySmall,
                    color = scheme.error,
                    modifier = Modifier.padding(top = 6.dp)
                )
                Text(
                    stringResource(R.string.journal_see),
                    style = MaterialTheme.typography.bodySmall,
                    color = scheme.onSurfaceVariant
                )
            }
        }

        // Конфигурации WARP (WireGuard): создать как wgcf или импортировать свою
        HCard(accent = NeonAmber) {
            SectionTitle(stringResource(R.string.wg_title), NeonAmber)
            Spacer(Modifier.height(4.dp))
            Text(
                if (account.wgId.isEmpty()) {
                    stringResource(R.string.wg_none)
                } else {
                    stringResource(R.string.wg_ok, account.wgId.take(8))
                },
                style = MaterialTheme.typography.bodyMedium
            )
            Text(
                stringResource(R.string.wg_hint),
                style = MaterialTheme.typography.bodySmall,
                color = scheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp, bottom = 8.dp)
            )
            Button(
                onClick = { account.registerWg() },
                enabled = !account.wgBusy && account.wgId.isEmpty(),
                shape = RoundedCornerShape(14.dp),
                modifier = Modifier.fillMaxWidth().height(48.dp)
            ) {
                if (account.wgBusy) {
                    CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = scheme.onPrimary)
                } else {
                    Text(stringResource(R.string.wg_create))
                }
            }
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = {
                        val s = account.exportWg()
                        if (s.isEmpty()) {
                            wgNote = wgNothingMsg
                        } else {
                            clipboard.setText(AnnotatedString(s))
                            wgNote = wgCopiedMsg
                        }
                    },
                    modifier = Modifier.weight(1f)
                ) { Text(stringResource(R.string.wg_copy)) }
                OutlinedButton(
                    onClick = {
                        val text = clipboard.getText()?.text.orEmpty()
                        val err = account.importWg(text)
                        wgNote = if (err.isEmpty()) wgImportedMsg else err
                    },
                    modifier = Modifier.weight(1f)
                ) { Text(stringResource(R.string.wg_import)) }
            }
            OutlinedButton(
                onClick = {
                    if (editing) {
                        editing = false
                    } else {
                        conf = account.exportWg().ifEmpty { WG_TEMPLATE }
                        editing = true
                    }
                },
                modifier = Modifier.fillMaxWidth()
            ) { Text(stringResource(if (editing) R.string.wg_cancel else R.string.wg_edit)) }
            if (editing) {
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = conf,
                    onValueChange = { conf = it },
                    minLines = 8,
                    textStyle = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 12.sp),
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(8.dp))
                Button(
                    onClick = {
                        val err = account.importWg(conf)
                        if (err.isEmpty()) {
                            editing = false
                            wgNote = wgImportedMsg
                        } else {
                            wgNote = err
                        }
                    },
                    shape = RoundedCornerShape(14.dp),
                    modifier = Modifier.fillMaxWidth().height(48.dp)
                ) { Text(stringResource(R.string.wg_save)) }
            }
            if (account.wgId.isNotEmpty()) {
                TextButton(onClick = { account.deleteWg(); wgNote = "" }) {
                    Text(stringResource(R.string.wg_delete))
                }
            }
            if (wgNote.isNotEmpty()) {
                Text(
                    wgNote,
                    style = MaterialTheme.typography.bodySmall,
                    color = scheme.primary,
                    modifier = Modifier.padding(top = 6.dp)
                )
            }
            if (account.wgFailKind.isNotEmpty()) {
                Text(
                    failText(account.wgFailKind),
                    style = MaterialTheme.typography.bodySmall,
                    color = scheme.error,
                    modifier = Modifier.padding(top = 6.dp)
                )
                Text(
                    stringResource(R.string.journal_see),
                    style = MaterialTheme.typography.bodySmall,
                    color = scheme.onSurfaceVariant
                )
            }
        }

        // Подключение
        HCard(accent = NeonOrange) {
            SectionTitle(stringResource(R.string.persist_title), NeonOrange)
            SwitchRow(stringResource(R.string.settings_autostart), auto) {
                auto = it
                prefs.autoStart = it
            }
            Text(
                stringResource(R.string.persist_hint),
                style = MaterialTheme.typography.bodySmall,
                color = scheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp, bottom = 8.dp)
            )
            OutlinedButton(onClick = openVpnSettings, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.btn_always_on))
            }
            Spacer(Modifier.height(6.dp))
            OutlinedButton(onClick = openBattery, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.btn_battery))
            }
            Spacer(Modifier.height(6.dp))
            OutlinedButton(onClick = openAutostart, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.btn_autostart_xiaomi))
            }
            Text(
                stringResource(R.string.kill_info),
                style = MaterialTheme.typography.bodySmall,
                color = scheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 8.dp)
            )
        }

        // О программе
        HCard(accent = NeonPink) {
            SectionTitle(stringResource(R.string.about_title), NeonPink)
            Spacer(Modifier.height(4.dp))
            Text(stringResource(R.string.about_text), style = MaterialTheme.typography.bodyMedium)
            val engine = remember { try { mobile.Mobile.version() } catch (t: Throwable) { "n/a" } }
            Text(
                stringResource(R.string.engine_label, engine),
                style = MaterialTheme.typography.bodySmall,
                color = scheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp)
            )
            TextButton(onClick = { showLicenses = !showLicenses }) {
                Text(stringResource(R.string.licenses_title))
            }
            if (showLicenses) {
                Text(
                    stringResource(R.string.licenses_text),
                    style = MaterialTheme.typography.bodySmall,
                    color = scheme.onSurfaceVariant
                )
            }
        }
        Spacer(Modifier.height(8.dp))
    }
}

private const val WG_TEMPLATE = """[Interface]
PrivateKey = 
Address = 172.16.0.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = 
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = 162.159.192.3:2408
PersistentKeepalive = 25
"""
