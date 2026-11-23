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
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.TextButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import android.widget.Toast
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
    onAiDns: () -> Unit,
    onResetAll: () -> Unit,
    onLanguageChanged: () -> Unit
) {
    val ctx = LocalContext.current
    var backupMsg by remember { mutableStateOf<String?>(null) }
    var pendingImportKind by remember { mutableStateOf("full") }

    val openBackupImport = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        try {
            val text = ctx.contentResolver.openInputStream(uri)?.use {
                it.readBytes().toString(Charsets.UTF_8)
            }?.trim().orEmpty()
            if (text.isEmpty()) {
                backupMsg = "FAIL: файл пустой"
                Toast.makeText(ctx, backupMsg, Toast.LENGTH_LONG).show()
                return@rememberLauncherForActivityResult
            }
            val dir = ctx.filesDir.absolutePath
            val result = if (pendingImportKind == "account") {
                val err = try { mobile.Mobile.importAccount(dir, text) } catch (e: Throwable) { e.message ?: "error" }
                if (err.isNullOrBlank()) "OK: аккаунт импортирован" else "FAIL: $err"
            } else {
                try {
                    val r = mobile.Mobile.importFullState(dir, text)
                    "OK: полный бэкап\n" + (r ?: "")
                } catch (e: Throwable) {
                    "FAIL: " + (e.message ?: "")
                }
            }
            backupMsg = result
            Toast.makeText(ctx, result.take(120), Toast.LENGTH_LONG).show()
        } catch (e: Throwable) {
            backupMsg = "FAIL: " + (e.message ?: "")
            Toast.makeText(ctx, backupMsg, Toast.LENGTH_LONG).show()
        }
    }

    val createBackupExport = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("text/plain")
    ) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        try {
            val dir = ctx.filesDir.absolutePath
            val body = if (pendingImportKind == "account") {
                try { mobile.Mobile.exportAccount(dir) } catch (e: Throwable) { "" }
            } else {
                try {
                    val json = "{" +
                        "\"protocol\":\"" + prefs.protocol + "\"," +
                        "\"parallel\":" + prefs.parallel + "," +
                        "\"tgGate\":" + prefs.tgGate + "," +
                        "\"useRoot\":" + prefs.useRoot +
                        "}"
                    mobile.Mobile.exportFullState(dir, json)
                } catch (e: Throwable) { e.message ?: "" }
            }
            if (body.isNullOrBlank()) {
                backupMsg = "FAIL: нечего экспортировать"
                Toast.makeText(ctx, backupMsg, Toast.LENGTH_LONG).show()
                return@rememberLauncherForActivityResult
            }
            ctx.contentResolver.openOutputStream(uri)?.use { os ->
                os.write(body.toByteArray(Charsets.UTF_8))
            }
            backupMsg = "OK: сохранено"
            Toast.makeText(ctx, "Бэкап сохранён", Toast.LENGTH_SHORT).show()
        } catch (e: Throwable) {
            backupMsg = "FAIL: " + (e.message ?: "")
            Toast.makeText(ctx, backupMsg, Toast.LENGTH_LONG).show()
        }
    }

    var sni by remember { mutableStateOf(prefs.customSni) }
    var ep by remember { mutableStateOf(prefs.customEndpoint) }
    var proto by remember { mutableStateOf(prefs.protocol) }
    var channel by remember { mutableStateOf(prefs.channel) }
    var lang by remember { mutableStateOf(prefs.lang) }
    var updateRepo by remember { mutableStateOf(prefs.updateRepo.ifEmpty { UpdateChecker.DEFAULT_REPO }) }
    var updateCheckBusy by remember { mutableStateOf(false) }
    var updateCheckMsg by remember { mutableStateOf("") }
    var forceUpdateInfo by remember { mutableStateOf<UpdateChecker.Info?>(null) }
    var block by remember { mutableStateOf(prefs.blockedColos) }
    var allow by remember { mutableStateOf(prefs.allowColos) }
    var fallback by remember { mutableStateOf(prefs.fallbackAny) }
    var auto by remember { mutableStateOf(prefs.autoStart) }
    var parallel by remember { mutableStateOf(prefs.parallel) }
    var ipv6 by remember { mutableStateOf(prefs.ipv6) }
    var tgGate by remember { mutableStateOf(prefs.tgGate) }
    var useRoot by remember { mutableStateOf(prefs.useRoot) }
    var stabilityMode by remember { mutableStateOf(prefs.stabilityMode) }
    var tvProfile by remember { mutableStateOf(prefs.tvProfile) }
    var notifyStrategy by remember { mutableStateOf(prefs.notifyStrategy) }
    var notifyErrors by remember { mutableStateOf(prefs.notifyErrors) }
    var notifyStatus by remember { mutableStateOf(prefs.notifyStatus) }
    var wgJc by remember { mutableStateOf(prefs.wgJc) }
    var wgJmin by remember { mutableStateOf(prefs.wgJmin) }
    var wgJmax by remember { mutableStateOf(prefs.wgJmax) }
    var hsTimeout by remember { mutableStateOf(prefs.handshakeTimeoutMs) }
    val hasRoot = remember { RootHelper.hasRoot() }
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
        SettingRow("Обход ИИ (AI-DNS)", subtitle = "DoH-подмена имён ChatGPT/Claude/Grok", onClick = onAiDns)

        SectionLabel(stringResource(R.string.adv_sec_conn))
        RowDivider()
        SettingSwitchRow(stringResource(R.string.adv_parallel), stringResource(R.string.adv_parallel_sub), parallel) {
            parallel = it
            prefs.parallel = it
            vpn.restartIfActive()
        }
        SettingSwitchRow(stringResource(R.string.adv_ipv6), stringResource(R.string.adv_ipv6_sub), ipv6) {
            ipv6 = it
            prefs.ipv6 = it
            vpn.restartIfActive()
        }
        SettingSwitchRow(stringResource(R.string.adv_tg), stringResource(R.string.adv_tg_sub), tgGate) {
            tgGate = it
            prefs.tgGate = it
            vpn.restartIfActive()
        }
        SettingRow(stringResource(R.string.conn_proto), subtitle = stringResource(R.string.proto_hint),
            value = protoOpts.firstOrNull { it.first == proto }?.second, onClick = { dlg = "proto" })
        SettingRow(stringResource(R.string.channel_title), subtitle = stringResource(R.string.channel_hint),
            value = channelOpts.firstOrNull { it.first == channel }?.second, onClick = { dlg = "channel" })
        SettingRow(
            stringResource(R.string.conn_sni), stringResource(R.string.conn_sni_sub),
            value = if (sni.isEmpty()) "авто" else sni, onClick = { dlg = "sni" }
        )
        SettingRow(
            "Подобрать SNI",
            subtitle = "Короткий список проверенных имён; пусто = ядро само",
            value = "авто",
            onClick = {
                val pool = listOf(
                    "",
                    "consumer-masque.cloudflareclient.com",
                    "www.cloudflare.com",
                    "speed.cloudflare.com",
                    "cloudflare.com",
                    "cdnjs.cloudflare.com"
                )
                val i = (pool.indexOf(sni).let { if (it < 0) 0 else it } + 1) % pool.size
                sni = pool[i]
                prefs.customSni = sni
                Toast.makeText(
                    ctx,
                    if (sni.isEmpty()) "SNI: авто (ядро само)" else "SNI: $sni",
                    Toast.LENGTH_SHORT
                ).show()
                vpn.restartIfActive()
            }
        )
        SettingRow(
            stringResource(R.string.conn_endpoint), stringResource(R.string.conn_endpoint_sub),
            value = if (ep.isEmpty()) "авто" else ep, onClick = { dlg = "ep" }
        )

        ExpandableSection("WireGuard junk / таймаут", initiallyExpanded = false) {
            RowDivider()
            SettingRow(
                stringResource(R.string.wg_jc),
                stringResource(R.string.wg_junk_sub),
                value = if (wgJc == 0) "авто" else wgJc.toString(),
                onClick = { dlg = "wg_jc" }
            )
            SettingRow(
                stringResource(R.string.wg_jmin),
                value = if (wgJc == 0) "авто" else wgJmin.toString(),
                onClick = { dlg = "wg_jmin" }
            )
            SettingRow(
                stringResource(R.string.wg_jmax),
                value = if (wgJc == 0) "авто" else wgJmax.toString(),
                onClick = { dlg = "wg_jmax" }
            )
            SettingRow(
                stringResource(R.string.hs_timeout_title),
                stringResource(R.string.hs_timeout_sub),
                value = "${hsTimeout} ms",
                onClick = { dlg = "hs_timeout" }
            )
        }
        val forgetCtx = LocalContext.current
        SettingRow(
            stringResource(R.string.forget_net_title),
            stringResource(R.string.forget_net_sub),
            onClick = {
                Prefs(forgetCtx).clearAllCellWifi()
                Thread {
                    try { mobile.Mobile.forgetCurrentNet(forgetCtx.filesDir.absolutePath) } catch (t: Throwable) { }
                    android.os.Handler(android.os.Looper.getMainLooper()).post { vpn.restartIfActive() }
                }.start()
            }
        )

        SectionLabel(stringResource(R.string.colo_title))
        RowDivider()
        SettingRow(stringResource(R.string.colo_block), value = block.ifEmpty { none }, onClick = { dlg = "block" })
        SettingRow(stringResource(R.string.colo_allow), value = allow.ifEmpty { none }, onClick = { dlg = "allow" })
        SettingRow(
            "Пресет ДЦ: Европа",
            subtitle = "HEL, FRA, AMS, ARN — не жёсткий запрет остальных, если включён fallback",
            value = "применить",
            onClick = {
                allow = "HEL,FRA,AMS,ARN"
                prefs.allowColos = allow
                Toast.makeText(ctx, "Разрешены: HEL, FRA, AMS, ARN", Toast.LENGTH_SHORT).show()
                vpn.restartIfActive()
            }
        )
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

        SectionLabel("Root и стабильность")
        RowDivider()
        if (hasRoot) {
            SettingSwitchRow(
                "Использовать root (iptables/nftables)",
                "Жёсткий kill-switch: трафик мимо VPN режется на уровне ядра",
                useRoot
            ) {
                useRoot = it
                prefs.useRoot = it
                if (!it) {
                    try { RootHelper.disableKillSwitch() } catch (t: Throwable) { }
                }
                vpn.restartIfActive()
            }
            NoteText("Root: да · backend: " + RootHelper.firewallBackend())
        } else {
            NoteText("Root не обнаружен — ползунок недоступен. На Magisk/KernelSU появится автоматически.")
        }
        SettingSwitchRow(
            "Режим максимальной стабильности",
            "Приоритет WG + европейские ДЦ, меньше экспериментов",
            stabilityMode
        ) {
            stabilityMode = it
            prefs.stabilityMode = it
            vpn.restartIfActive()
        }
        SettingSwitchRow(
            "Профиль ТВ / приставки",
            "Длиннее таймауты, спокойнее гонка, упор на стабильность",
            tvProfile
        ) {
            tvProfile = it
            prefs.tvProfile = it
            vpn.restartIfActive()
        }

        SectionLabel(stringResource(R.string.notif_section))
        RowDivider()
        SettingSwitchRow(stringResource(R.string.notify_status), "", notifyStatus) {
            notifyStatus = it; prefs.notifyStatus = it
        }
        SettingSwitchRow(stringResource(R.string.notify_strategy), "", notifyStrategy) {
            notifyStrategy = it; prefs.notifyStrategy = it
        }
        SettingSwitchRow(stringResource(R.string.notify_errors), "", notifyErrors) {
            notifyErrors = it; prefs.notifyErrors = it
        }

        ExpandableSection("Бэкап и тест", initiallyExpanded = false) {
            RowDivider()
            SettingRow(stringResource(R.string.export_full), onClick = { dlg = "export_full" })
            SettingRow(stringResource(R.string.import_full), onClick = { dlg = "import_full" })
            SettingRow(stringResource(R.string.export_file), onClick = {
                pendingImportKind = "full"
                createBackupExport.launch("hydra-backup.txt")
            })
            SettingRow(stringResource(R.string.import_file), onClick = {
                pendingImportKind = "full"
                openBackupImport.launch(arrayOf("text/*", "application/octet-stream", "*/*"))
            })
            SettingRow(stringResource(R.string.export_account_file), onClick = {
                pendingImportKind = "account"
                createBackupExport.launch("hydra-account.txt")
            })
            SettingRow(stringResource(R.string.import_account_file), onClick = {
                pendingImportKind = "account"
                openBackupImport.launch(arrayOf("text/*", "application/octet-stream", "*/*"))
            })
            SettingRow(stringResource(R.string.speed_test), onClick = { dlg = "speed" })
        }

        SectionLabel(stringResource(R.string.adv_sec_other))

        RowDivider()
        SettingRow(stringResource(R.string.settings_language),
            value = langOpts.firstOrNull { it.first == lang }?.second, onClick = { dlg = "lang" })
        SettingRow(stringResource(R.string.conn_reset_keys), onClick = { dlg = "keys" })
        SettingRow(stringResource(R.string.conn_reset_all), onClick = { dlg = "all" })
        SettingRow(
            "Проверить обновления",
            value = if (updateCheckBusy) "…" else updateCheckMsg.ifEmpty { "сейчас" },
            onClick = {
                if (!updateCheckBusy) {
                    updateCheckBusy = true
                    updateCheckMsg = "…"
                    UpdateChecker.check(ctx, force = true) { info: UpdateChecker.Info? ->
                        updateCheckBusy = false
                        if (info == null) {
                            updateCheckMsg = "актуально"
                            Toast.makeText(ctx, "Обновлений нет", Toast.LENGTH_SHORT).show()
                        } else {
                            updateCheckMsg = info.tag
                            forceUpdateInfo = info
                        }
                    }
                }
            }
        )
        SettingRow(stringResource(R.string.about_title), stringResource(R.string.engine_label, engine),
            onClick = { showLicenses = !showLicenses })
    if (showLicenses) {
            NoteText(stringResource(R.string.about_text))
            NoteText(stringResource(R.string.licenses_text))
        }
        Spacer(Modifier.height(24.dp))
    }

    forceUpdateInfo?.let { info: UpdateChecker.Info ->
        AlertDialog(
            onDismissRequest = { forceUpdateInfo = null },
            title = { Text("WARP CLAUDE — обновление") },
            text = {
                Text(info.tag + " (code " + info.versionCode + ")\n" + info.name)
            },
            confirmButton = {
                TextButton(onClick = {
                    val inf = info
                    forceUpdateInfo = null
                    Thread {
                        try {
                            if (!UpdateChecker.canRequestInstall(ctx)) {
                                android.os.Handler(android.os.Looper.getMainLooper()).post {
                                    UpdateChecker.openUnknownSourcesSettings(ctx)
                                }
                                return@Thread
                            }
                            val f = UpdateChecker.downloadApk(ctx, inf.apkUrl, null)
                            UpdateChecker.installApk(ctx, f)
                        } catch (e: Throwable) {
                            android.os.Handler(android.os.Looper.getMainLooper()).post {
                                Toast.makeText(ctx, "Ошибка: " + (e.message ?: ""), Toast.LENGTH_LONG).show()
                            }
                        }
                    }.start()
                }) { Text("Обновить") }
            },
            dismissButton = {
                TextButton(onClick = { forceUpdateInfo = null }) { Text("Позже") }
            }
        )
    }

    if (backupMsg != null) {
        TextDialog(
            "Бэкап",
            backupMsg ?: "",
            "",
            onDismiss = { backupMsg = null },
            onApply = { backupMsg = null },
            onReset = { backupMsg = null }
        )
    }

    when (dlg) {
        "proto" -> ChoiceDialog(stringResource(R.string.conn_proto), protoOpts, proto,
            onPick = { proto = it; prefs.protocol = it; dlg = ""; vpn.restartIfActive() }, onDismiss = { dlg = "" })
        "channel" -> ChoiceDialog(stringResource(R.string.channel_title), channelOpts, channel,
            onPick = { channel = it; prefs.channel = it; dlg = ""; vpn.restartIfActive() }, onDismiss = { dlg = "" })
        "lang" -> ChoiceDialog(stringResource(R.string.settings_language), langOpts, lang,
            onPick = { lang = it; prefs.lang = it; dlg = ""; onLanguageChanged() }, onDismiss = { dlg = "" })
        "update_repo" -> TextDialog(
            stringResource(R.string.update_repo), updateRepo, "evgehae/Hydra",
            onDismiss = { dlg = "" },
            onApply = { updateRepo = it.trim(); prefs.updateRepo = updateRepo; dlg = "" },
            onReset = { updateRepo = UpdateChecker.DEFAULT_REPO; prefs.updateRepo = updateRepo; dlg = "" }
        )
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
        "wg_jc" -> TextDialog(
            stringResource(R.string.wg_jc), if (wgJc == 0) "" else wgJc.toString(), "0 = auto, 1–16",
            onDismiss = { dlg = "" },
            onApply = {
                wgJc = it.toIntOrNull()?.coerceIn(0, 16) ?: 0
                prefs.wgJc = wgJc
                dlg = ""
                vpn.restartIfActive()
            },
            onReset = { wgJc = 0; prefs.wgJc = 0; dlg = ""; vpn.restartIfActive() }
        )
        "wg_jmin" -> TextDialog(
            stringResource(R.string.wg_jmin), wgJmin.toString(), "5–200",
            onDismiss = { dlg = "" },
            onApply = {
                wgJmin = it.toIntOrNull()?.coerceIn(5, 200) ?: 40
                prefs.wgJmin = wgJmin
                if (wgJmax < wgJmin + 10) { wgJmax = wgJmin + 10; prefs.wgJmax = wgJmax }
                dlg = ""
                vpn.restartIfActive()
            },
            onReset = { wgJmin = 40; prefs.wgJmin = 40; dlg = ""; vpn.restartIfActive() }
        )
        "wg_jmax" -> TextDialog(
            stringResource(R.string.wg_jmax), wgJmax.toString(), "20–300",
            onDismiss = { dlg = "" },
            onApply = {
                wgJmax = it.toIntOrNull()?.coerceIn(20, 300) ?: 70
                if (wgJmax < wgJmin + 10) wgJmax = wgJmin + 10
                prefs.wgJmax = wgJmax
                dlg = ""
                vpn.restartIfActive()
            },
            onReset = { wgJmax = 70; prefs.wgJmax = 70; dlg = ""; vpn.restartIfActive() }
        )
        "hs_timeout" -> TextDialog(
            stringResource(R.string.hs_timeout_title), hsTimeout.toString(), "1200–5000",
            onDismiss = { dlg = "" },
            onApply = {
                hsTimeout = it.toIntOrNull()?.coerceIn(1200, 5000) ?: 2000
                prefs.handshakeTimeoutMs = hsTimeout
                dlg = ""
                vpn.restartIfActive()
            },
            onReset = { hsTimeout = 2000; prefs.handshakeTimeoutMs = 2000; dlg = ""; vpn.restartIfActive() }
        )

        "export_full" -> {
            val snap = try {
                val json = "{" +
                    "\"protocol\":\"${prefs.protocol}\"," +
                    "\"parallel\":${prefs.parallel}," +
                    "\"tgGate\":${prefs.tgGate}," +
                    "\"useRoot\":${prefs.useRoot}" +
                    "}"
                mobile.Mobile.exportFullState(ctx.filesDir.absolutePath, json)
            } catch (e: Throwable) { e.message ?: "" }
            TextDialog(
                stringResource(R.string.export_full), snap, "hydra-full1:…",
                onDismiss = { dlg = "" },
                onApply = { dlg = "" },
                onReset = { dlg = "" }
            )
        }
        "import_full" -> TextDialog(
            stringResource(R.string.import_full), "", "hydra-full1:…",
            onDismiss = { dlg = "" },
            onApply = {
                try { mobile.Mobile.importFullState(ctx.filesDir.absolutePath, it) } catch (e: Throwable) { }
                dlg = ""
            },
            onReset = { dlg = "" }
        )
        "export_file" -> {
            val body = try {
                val json = "{" +
                    "\"protocol\":\"${prefs.protocol}\"," +
                    "\"parallel\":${prefs.parallel}," +
                    "\"tgGate\":${prefs.tgGate}," +
                    "\"useRoot\":${prefs.useRoot}" +
                    "}"
                mobile.Mobile.exportFullState(ctx.filesDir.absolutePath, json)
            } catch (e: Throwable) { e.message ?: "" }
            val result = if (body.isNotBlank()) BackupIO.write(ctx, BackupIO.FILE_FULL, body) else "FAIL: empty export"
            TextDialog(
                stringResource(R.string.export_file),
                result + "\n\n" + stringResource(R.string.backup_hint),
                "",
                onDismiss = { dlg = "" },
                onApply = { dlg = "" },
                onReset = { dlg = "" }
            )
        }
        "import_file" -> {
            val pair = BackupIO.read(ctx, BackupIO.FILE_FULL)
            val text = pair.first
            val info = pair.second
            val result = if (text != null) {
                try {
                    val r = mobile.Mobile.importFullState(ctx.filesDir.absolutePath, text)
                    "OK\n" + info + "\n" + (r ?: "")
                } catch (e: Throwable) {
                    "FAIL: " + (e.message ?: "") + "\n" + info
                }
            } else {
                "FAIL\n" + info + "\n\n" + stringResource(R.string.backup_hint)
            }
            TextDialog(
                stringResource(R.string.import_file),
                result,
                "",
                onDismiss = { dlg = "" },
                onApply = { dlg = "" },
                onReset = { dlg = "" }
            )
        }
        "export_acc_file" -> {
            val body = try { mobile.Mobile.exportAccount(ctx.filesDir.absolutePath) } catch (e: Throwable) { "" }
            val result = if (body.isNotBlank()) BackupIO.write(ctx, BackupIO.FILE_ACCOUNT, body) else "FAIL: no account"
            TextDialog(
                stringResource(R.string.export_account_file),
                result + "\n\n" + stringResource(R.string.backup_hint),
                "",
                onDismiss = { dlg = "" },
                onApply = { dlg = "" },
                onReset = { dlg = "" }
            )
        }
        "import_acc_file" -> {
            val pair = BackupIO.read(ctx, BackupIO.FILE_ACCOUNT)
            val text = pair.first
            val info = pair.second
            val result = if (text != null) {
                try {
                    val err = mobile.Mobile.importAccount(ctx.filesDir.absolutePath, text)
                    if (err.isNullOrBlank()) "OK\n" + info else "FAIL: " + err + "\n" + info
                } catch (e: Throwable) {
                    "FAIL: " + (e.message ?: "") + "\n" + info
                }
            } else {
                "FAIL\n" + info + "\n\nПоложи hydra-account.txt в Download и повтори."
            }
            TextDialog(
                stringResource(R.string.import_account_file),
                result,
                "",
                onDismiss = { dlg = "" },
                onApply = { dlg = "" },
                onReset = { dlg = "" }
            )
        }
        "speed" -> {
            val report = try { mobile.Mobile.speedTest() } catch (e: Throwable) { e.message ?: "error" }
            TextDialog(
                stringResource(R.string.speed_test), report, "",
                onDismiss = { dlg = "" },
                onApply = { dlg = "" },
                onReset = { dlg = "" }
            )
        }

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
