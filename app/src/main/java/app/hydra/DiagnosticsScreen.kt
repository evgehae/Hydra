package app.hydra

import android.content.Intent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** «Диагностика»: состояние, проверки, ошибки, журнал, отчёт. */
@Composable
fun DiagnosticsScreen(
    prefs: Prefs,
    account: AccountController,
    vpn: VpnController,
    onBack: () -> Unit,
    onErrors: () -> Unit,
    onJournal: () -> Unit
) {
    val ctx = LocalContext.current
    val clipboard = LocalClipboardManager.current
    val scope = rememberCoroutineScope()
    var running by remember { mutableStateOf(false) }
    var checks by remember { mutableStateOf<List<DiagCheck>>(emptyList()) }
    var base by remember { mutableStateOf<DiagResult?>(null) }
    var quick by remember { mutableStateOf(false) }
    var copied by remember { mutableStateOf(false) }
    var showResult by remember { mutableStateOf(false) }
    var showQuick by remember { mutableStateOf(false) }
    var showSys by remember { mutableStateOf(false) }
    var wlRunning by remember { mutableStateOf(false) }
    var wlText by remember { mutableStateOf<String?>(null) }

    val onWord = stringResource(R.string.diag_on)
    val offWord = stringResource(R.string.diag_off)
    val dash = "—"
    val stateText = when (vpn.state) {
        "up" -> onWord
        "connecting" -> stringResource(R.string.vpn_connecting)
        "reconnecting" -> stringResource(R.string.vpn_reconnecting)
        "failed" -> stringResource(R.string.vpn_failed)
        else -> offWord
    }

    SubPage(stringResource(R.string.menu_diag), onBack) {
        SectionLabel(stringResource(R.string.diag_sec_conn))
        RowDivider()
        SettingRow(stringResource(R.string.diag_conn), value = stateText)
        SettingRow(stringResource(R.string.diag_proto), value = if (vpn.strategy.isEmpty()) dash else stringResource(protoRes(vpn.strategy)))
        SettingRow(stringResource(R.string.diag_strategy), value = if (vpn.strategy.isEmpty()) dash else vpn.strategy)
        SettingRow(stringResource(R.string.diag_dc), value = if (vpn.colo.isEmpty()) dash else coloLabel(vpn.colo))
        SettingRow(stringResource(R.string.diag_ping), value = if (vpn.state == "up") stringResource(R.string.diag_ms, vpn.rttMs) else dash)

        SectionLabel(stringResource(R.string.diag_sec_dev))
        RowDivider()
        SettingRow(stringResource(R.string.diag_nettype), value = networkType(ctx))
        SettingRow(stringResource(R.string.diag_ip), value = base?.ip?.ifEmpty { dash } ?: dash)

        SectionLabel(stringResource(R.string.diag_sec_cfg))
        RowDivider()
        SettingRow(stringResource(R.string.diag_id), value = account.id.ifEmpty { dash })
        SettingRow(stringResource(R.string.diag_id_wg), value = account.wgId.ifEmpty { dash })

        SectionLabel(stringResource(R.string.diag_sec_stats))
        RowDivider()
        SettingRow(stringResource(R.string.diag_rx), value = if (vpn.active) fmtBytes(vpn.rxBytes) else dash)
        SettingRow(stringResource(R.string.diag_tx), value = if (vpn.active) fmtBytes(vpn.txBytes) else dash)

        SectionLabel(stringResource(R.string.diag_sec_tools))
        RowDivider()
        SettingRow(
            stringResource(R.string.diag_quick),
            stringResource(R.string.diag_quick_sub),
            value = if (quick) "…" else null,
            onClick = {
                if (!quick) {
                    quick = true
                    scope.launch {
                        val r = runDiagnostics()
                        base = r
                        quick = false
                        try {
                            mobile.Mobile.logLine("🔎 быстрая проверка (мимо VPN): DNS " + (if (r.dnsOk) "ок ${r.dnsMs} мс" else "сбой") +
                                ", HTTPS " + (if (r.httpsOk) "ок ${r.httpsMs} мс" else "сбой") + ", дата-центр " + r.colo + ", IP " + r.ip)
                        } catch (t: Throwable) { }
                        showQuick = true
                    }
                }
            }
        )
        SettingRow(
            stringResource(R.string.diag_full),
            stringResource(R.string.diag_full_sub),
            value = if (running) "…" else null,
            onClick = {
                if (!running) {
                    running = true
                    scope.launch {
                        checks = runFullDiagnostics(ctx)
                        running = false
                        showResult = true
                    }
                }
            }
        )
        SettingRow(
            stringResource(R.string.diag_test_failover),
            stringResource(R.string.diag_test_failover_sub),
            onClick = { try { mobile.Mobile.testFailover() } catch (t: Throwable) { } }
        )
        SettingRow(stringResource(R.string.diag_errors), stringResource(R.string.diag_errors_sub), onClick = onErrors)
        SettingRow(stringResource(R.string.journal_title), onClick = onJournal)
        SettingRow(
            stringResource(R.string.diag_wl),
            stringResource(R.string.diag_wl_sub),
            value = if (wlRunning) "…" else null,
            onClick = {
                if (!wlRunning) {
                    wlRunning = true
                    scope.launch {
                        val t = withContext(Dispatchers.IO) { try { mobile.Mobile.whitelistCheck() } catch (e: Throwable) { "н/д" } }
                        try { mobile.Mobile.logLine("🔎 проверка белых списков:\n" + t) } catch (e: Throwable) { }
                        wlText = t
                        wlRunning = false
                    }
                }
            }
        )
        SettingRow(
            stringResource(R.string.diag_sys),
            stringResource(R.string.diag_sys_sub),
            onClick = { showSys = true }
        )
        SettingRow(
            stringResource(R.string.diag_share),
            stringResource(R.string.diag_share_sub),
            onClick = {
                shareReport(ctx, buildReport(ctx, prefs, vpn, account, checks))
            }
        )
        SettingRow(
            stringResource(R.string.diag_copy_report),
            value = if (copied) stringResource(R.string.diag_report_copied) else null,
            onClick = {
                clipboard.setText(AnnotatedString(buildReport(ctx, prefs, vpn, account, checks)))
                copied = true
            }
        )

        if (running) NoteText(stringResource(R.string.diag_full_running))
        if (checks.isNotEmpty()) {
            SectionLabel(stringResource(R.string.diag_full))
            RowDivider()
            checks.forEach { c ->
                SettingRow(c.name, value = (if (c.ok) "✔ " else "✘ ") + c.detail)
            }
            NoteText(stringResource(R.string.diag_direct_hint))
        }
        Spacer(Modifier.height(24.dp))
    }
    if (showResult) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { showResult = false },
            title = { Text(stringResource(R.string.diag_full)) },
            text = {
                Column {
                    checks.forEach { c ->
                        Text((if (c.ok) "✔ " else "✘ ") + c.name + ": " + c.detail, modifier = Modifier.padding(vertical = 3.dp))
                    }
                }
            },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = {
                    showResult = false
                    shareReport(ctx, buildReport(ctx, prefs, vpn, account, checks))
                }) { Text(stringResource(R.string.diag_share)) }
            },
            dismissButton = {
                androidx.compose.material3.TextButton(onClick = { showResult = false }) { Text(stringResource(R.string.btn_ok)) }
            }
        )
    }
    if (showQuick) {
        val r = base
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { showQuick = false },
            title = { Text(stringResource(R.string.diag_quick)) },
            text = {
                Column {
                    if (r != null) {
                        Text((if (r.dnsOk) "✔ " else "✘ ") + stringResource(R.string.chk_dns) + ": " + (if (r.dnsOk) "${r.dnsMs} ms" else stringResource(R.string.diag_fail)), modifier = Modifier.padding(vertical = 3.dp))
                        Text((if (r.httpsOk) "✔ " else "✘ ") + stringResource(R.string.chk_https) + ": " + (if (r.httpsOk) "${r.httpsMs} ms" else stringResource(R.string.diag_fail)), modifier = Modifier.padding(vertical = 3.dp))
                        Text(stringResource(R.string.diag_dc) + ": " + (if (r.colo.isEmpty()) "—" else coloLabel(r.colo)), modifier = Modifier.padding(vertical = 3.dp))
                        Text(stringResource(R.string.diag_ip) + ": " + (if (r.ip.isEmpty()) "—" else r.ip), modifier = Modifier.padding(vertical = 3.dp))
                    }
                }
            },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = { showQuick = false }) { Text(stringResource(R.string.btn_ok)) }
            }
        )
    }
    if (showSys) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { showSys = false },
            title = { Text(stringResource(R.string.diag_sys)) },
            text = {
                SelectionContainer {
                    Text(
                        (try { mobile.Mobile.diagnostics() } catch (t: Throwable) { "" }) + "\n" + systemReport(ctx),
                        fontFamily = FontFamily.Monospace,
                        fontSize = 10.sp,
                        lineHeight = 13.sp,
                        modifier = Modifier.verticalScroll(androidx.compose.foundation.rememberScrollState())
                    )
                }
            },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = { showSys = false }) { Text(stringResource(R.string.btn_ok)) }
            }
        )
    }
    wlText?.let { t ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { wlText = null },
            title = { Text(stringResource(R.string.diag_wl)) },
            text = {
                SelectionContainer {
                    Text(t, fontFamily = FontFamily.Monospace, fontSize = 11.sp, lineHeight = 15.sp,
                        modifier = Modifier.verticalScroll(androidx.compose.foundation.rememberScrollState()))
                }
            },
            confirmButton = { androidx.compose.material3.TextButton(onClick = { wlText = null }) { Text(stringResource(R.string.btn_ok)) } }
        )
    }
}

/** Только сбои из журнала. */
@Composable
fun ErrorsScreen(onBack: () -> Unit) {
    val clipboard = LocalClipboardManager.current
    var lines by remember { mutableStateOf(journalErrors()) }
    SubPage(stringResource(R.string.diag_errors), onBack) {
        SettingRow(stringResource(R.string.errors_refresh), onClick = { lines = journalErrors() })
        SettingRow(stringResource(R.string.journal_copy), onClick = { clipboard.setText(AnnotatedString(lines.joinToString("\n"))) })
        if (lines.isEmpty()) {
            NoteText(stringResource(R.string.errors_none))
        } else {
            SelectionContainer {
                Text(
                    lines.reversed().joinToString("\n"),
                    fontFamily = FontFamily.Monospace,
                    fontSize = 11.sp,
                    lineHeight = 15.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.fillMaxWidth().padding(16.dp)
                )
            }
        }
    }
}

/** Полный журнал. */
@Composable
fun JournalScreen(onBack: () -> Unit) {
    SubPage(stringResource(R.string.journal_title), onBack) {
        Column(Modifier.padding(12.dp)) { JournalCard() }
    }
}
