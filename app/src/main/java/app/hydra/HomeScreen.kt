package app.hydra

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

@Composable
fun HomeScreen(prefs: Prefs, account: AccountController) {
    val ctx = LocalContext.current
    val engine = remember { try { mobile.Mobile.version() } catch (t: Throwable) { "n/a" } }
    val hasAccount = account.id.isNotEmpty()
    val failKind = account.failKind
    val soonToast = stringResource(R.string.home_soon_toast)

    val title = when {
        account.busy -> stringResource(R.string.home_status_registering)
        !hasAccount -> stringResource(R.string.home_status_need_account)
        else -> stringResource(R.string.home_status_ready)
    }
    val sub = when {
        account.busy -> stringResource(R.string.home_sub_registering)
        !hasAccount -> stringResource(R.string.home_sub_need_account)
        else -> stringResource(R.string.home_sub_ready)
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text("Hydra", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
        Text(
            stringResource(R.string.home_tagline),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(32.dp))

        PowerButton(busy = account.busy, ready = hasAccount) {
            if (!hasAccount) {
                account.register()
            } else {
                Toast.makeText(ctx, soonToast, Toast.LENGTH_SHORT).show()
            }
        }

        Spacer(Modifier.height(20.dp))
        Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(4.dp))
        Text(
            sub,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.height(28.dp))

        HCard {
            SectionTitle(stringResource(R.string.ready_title))
            StepRow(StepState.Done, stringResource(R.string.step_engine), engine)

            val registerLabel = stringResource(R.string.action_register)
            val accountState = when {
                hasAccount -> StepState.Done
                failKind.isNotEmpty() -> StepState.Failed
                else -> StepState.Pending
            }
            val accountSub = when {
                hasAccount -> stringResource(R.string.step_account_ok, account.id.take(8))
                failKind.isNotEmpty() -> failText(failKind)
                else -> stringResource(R.string.step_account_none)
            }
            StepRow(
                accountState,
                stringResource(R.string.step_account),
                accountSub,
                actionLabel = if (hasAccount || account.busy) null else registerLabel,
                onAction = { account.register() }
            )

            StepRow(
                StepState.Pending,
                stringResource(R.string.step_connect),
                stringResource(R.string.step_connect_sub)
            )
        }

        Spacer(Modifier.height(12.dp))

        HCard {
            SectionTitle(stringResource(R.string.dc_title))
            Spacer(Modifier.height(6.dp))
            val blocked = prefs.blockedColos.trim()
            if (blocked.isNotEmpty()) {
                Text(stringResource(R.string.dc_blocked, blocked), style = MaterialTheme.typography.bodyMedium)
            }
            val allow = prefs.allowColos.trim()
            if (allow.isNotEmpty()) {
                Text(stringResource(R.string.dc_allow, allow), style = MaterialTheme.typography.bodyMedium)
            }
            Spacer(Modifier.height(6.dp))
            Text(
                stringResource(R.string.dc_hint),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
fun PowerButton(busy: Boolean, ready: Boolean, onClick: () -> Unit) {
    val ring = if (ready) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline
    val fill = MaterialTheme.colorScheme.primaryContainer
    Box(
        modifier = Modifier
            .size(168.dp)
            .clip(CircleShape)
            .background(if (ready) fill else fill.copy(alpha = 0.5f))
            .border(3.dp, ring, CircleShape)
            .clickable(enabled = !busy) { onClick() },
        contentAlignment = Alignment.Center
    ) {
        if (busy) {
            CircularProgressIndicator(Modifier.size(56.dp), color = MaterialTheme.colorScheme.primary)
        } else {
            Icon(Icons.Filled.PlayArrow, contentDescription = null, modifier = Modifier.size(72.dp), tint = ring)
        }
    }
}
