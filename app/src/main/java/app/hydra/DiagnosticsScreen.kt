package app.hydra

import android.content.Intent
import androidx.compose.foundation.layout.Column
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
import kotlinx.coroutines.launch

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
                    scope.launch { base = runDiagnostics(); quick = false }
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
                    }
                }
            }
        )
        SettingRow(stringResource(R.string.diag_errors), stringResource(R.string.diag_errors_sub), onClick = onErrors)
        SettingRow(stringResource(R.string.journal_title), onClick = onJournal)
        SettingRow(
            stringResource(R.string.diag_share),
            stringResource(R.string.diag_share_sub),
            onClick = {
                val text = buildReport(ctx, prefs, vpn, account, checks)
                val i = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
                try { ctx.startActivity(Intent.createChooser(i, null)) } catch (t: Throwable) { }
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
