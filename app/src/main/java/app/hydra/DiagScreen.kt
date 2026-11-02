package app.hydra

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

@Composable
fun DiagScreen(prefs: Prefs) {
    val scope = rememberCoroutineScope()
    var running by remember { mutableStateOf(false) }
    var res by remember { mutableStateOf<DiagResult?>(null) }
    val blocked = remember { parseColos(prefs.blockedColos) }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 16.dp)
    ) {
        Text(
            stringResource(R.string.diag_title),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold
        )
        Text(
            stringResource(R.string.diag_sub),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(16.dp))

        Button(
            onClick = {
                if (!running) {
                    running = true
                    scope.launch {
                        res = runDiagnostics()
                        running = false
                    }
                }
            },
            enabled = !running,
            shape = RoundedCornerShape(16.dp),
            modifier = Modifier.fillMaxWidth().height(52.dp)
        ) {
            if (running) {
                CircularProgressIndicator(
                    Modifier.size(22.dp),
                    strokeWidth = 2.dp,
                    color = MaterialTheme.colorScheme.onPrimary
                )
            } else {
                Text(stringResource(R.string.diag_run))
            }
        }

        val r = res
        if (r != null) {
            Spacer(Modifier.height(16.dp))
            HCard {
                val failed = stringResource(R.string.diag_fail)
                val dnsText = if (r.dnsOk) stringResource(R.string.diag_ms, r.dnsMs.toInt()) else failed
                val httpsText = if (r.httpsOk) stringResource(R.string.diag_ms, r.httpsMs.toInt()) else failed

                StepRow(
                    if (r.dnsOk) StepState.Done else StepState.Failed,
                    stringResource(R.string.diag_dns),
                    dnsText
                )
                StepRow(
                    if (r.httpsOk) StepState.Done else StepState.Failed,
                    stringResource(R.string.diag_https),
                    httpsText
                )
                if (r.ip.isNotEmpty()) {
                    StepRow(
                        StepState.Done,
                        stringResource(R.string.diag_ip),
                        if (r.loc.isNotEmpty()) r.ip + " · " + r.loc else r.ip
                    )
                }

                val dcState: StepState
                val dcText: String
                when {
                    r.colo.isEmpty() -> {
                        dcState = StepState.Pending
                        dcText = stringResource(R.string.diag_dc_unknown)
                    }
                    r.colo in blocked -> {
                        dcState = StepState.Failed
                        dcText = stringResource(R.string.diag_dc_blocked, coloLabel(r.colo))
                    }
                    else -> {
                        dcState = StepState.Done
                        dcText = coloLabel(r.colo)
                    }
                }
                StepRow(dcState, stringResource(R.string.diag_dc), dcText)

                val warpOn = r.warp == "on" || r.warp == "plus"
                StepRow(
                    if (warpOn) StepState.Done else StepState.Pending,
                    stringResource(R.string.diag_warp),
                    stringResource(if (warpOn) R.string.diag_warp_on else R.string.diag_warp_off)
                )
            }
        }
    }
}
