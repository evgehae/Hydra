package app.hydra

import android.app.Activity
import android.net.VpnService
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun HomeScreen(prefs: Prefs, account: AccountController, vpn: VpnController) {
    val ctx = LocalContext.current
    val engine = remember { try { mobile.Mobile.version() } catch (t: Throwable) { "n/a" } }
    val hasAccount = account.id.isNotEmpty()
    val needAppsToast = stringResource(R.string.need_apps_toast)

    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        if (r.resultCode == Activity.RESULT_OK) vpn.start()
    }

    val onTap: () -> Unit = {
        when {
            account.busy -> {}
            !hasAccount -> account.register()
            vpn.active -> vpn.stop()
            prefs.splitOnlySelected && prefs.splitApps.isEmpty() ->
                Toast.makeText(ctx, needAppsToast, Toast.LENGTH_LONG).show()
            else -> {
                val i = VpnService.prepare(ctx)
                if (i != null) launcher.launch(i) else vpn.start()
            }
        }
    }

    val scheme = MaterialTheme.colorScheme
    val mode = when {
        account.busy -> HeroMode.Registering
        !hasAccount -> HeroMode.Off
        vpn.state == "up" -> HeroMode.Connected
        vpn.state == "connecting" || vpn.state == "reconnecting" -> HeroMode.Connecting
        vpn.state == "failed" -> HeroMode.Failed
        else -> HeroMode.Off
    }

    val title = when {
        account.busy -> stringResource(R.string.home_status_registering)
        !hasAccount -> stringResource(R.string.home_status_need_account)
        vpn.state == "up" -> stringResource(R.string.vpn_up)
        vpn.state == "connecting" -> stringResource(R.string.vpn_connecting)
        vpn.state == "reconnecting" -> stringResource(R.string.vpn_reconnecting)
        vpn.state == "failed" -> stringResource(R.string.vpn_failed)
        else -> stringResource(R.string.vpn_off)
    }
    val sub = when {
        account.busy -> stringResource(R.string.home_sub_registering)
        !hasAccount -> stringResource(R.string.home_sub_need_account)
        vpn.state == "up" ->
            if (vpn.message.isNotEmpty()) vpn.message else stringResource(R.string.vpn_up_sub, coloLabel(vpn.colo))
        vpn.state == "connecting" -> stringResource(R.string.vpn_connecting_sub)
        vpn.state == "reconnecting" || vpn.state == "failed" ->
            if (vpn.message.isNotEmpty()) vpn.message else stringResource(R.string.vpn_connecting_sub)
        else -> stringResource(R.string.vpn_off_sub)
    }
    val titleColor = when (mode) {
        HeroMode.Connected -> NeonGreen
        HeroMode.Failed -> scheme.error
        HeroMode.Registering -> NeonAmber
        HeroMode.Connecting -> NeonCyan
        HeroMode.Off -> scheme.onBackground
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 18.dp, vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Image(
                painterResource(R.drawable.ic_launcher_art),
                contentDescription = null,
                modifier = Modifier.size(52.dp).clip(RoundedCornerShape(14.dp))
            )
            Spacer(Modifier.width(12.dp))
            Column {
                Text(
                    "HYDRA",
                    style = TextStyle(
                        brush = Brush.linearGradient(listOf(NeonCyan, NeonViolet, NeonPink)),
                        fontSize = 30.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 5.sp
                    )
                )
                Text(
                    stringResource(R.string.home_tagline),
                    style = MaterialTheme.typography.bodySmall,
                    color = scheme.onSurfaceVariant
                )
            }
        }

        Spacer(Modifier.height(6.dp))
        HydraHero(mode = mode, onClick = onTap, modifier = Modifier.fillMaxWidth(0.92f))

        Text(title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold, color = titleColor)
        Spacer(Modifier.height(4.dp))
        Text(
            sub,
            style = MaterialTheme.typography.bodyMedium,
            color = scheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.height(18.dp))

        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Tile(
                stringResource(R.string.tile_dc),
                if (vpn.state == "up" && vpn.colo.isNotEmpty()) vpn.colo else "—",
                NeonGreen,
                Modifier.weight(1f)
            )
            Tile(
                stringResource(R.string.tile_rtt),
                if (vpn.state == "up") stringResource(R.string.diag_ms, vpn.rttMs) else "—",
                NeonViolet,
                Modifier.weight(1f)
            )
            Tile(
                stringResource(R.string.tile_route),
                if (vpn.state == "up") routeLabel(vpn.strategy) else "—",
                NeonCyan,
                Modifier.weight(1f)
            )
        }

        Spacer(Modifier.height(12.dp))
        HCard(accent = NeonGreen) {
            SectionTitle(stringResource(R.string.ready_title), NeonGreen)
            StepRow(StepState.Done, stringResource(R.string.step_engine), engine)
            val failKind = account.failKind
            val registerLabel = stringResource(R.string.action_register)
            StepRow(
                when {
                    hasAccount -> StepState.Done
                    failKind.isNotEmpty() -> StepState.Failed
                    else -> StepState.Pending
                },
                stringResource(R.string.step_account),
                when {
                    hasAccount -> stringResource(R.string.step_account_ok, account.id.take(8))
                    failKind.isNotEmpty() -> failText(failKind)
                    else -> stringResource(R.string.step_account_none)
                },
                actionLabel = if (hasAccount || account.busy) null else registerLabel,
                onAction = { account.register() }
            )
            StepRow(
                if (vpn.state == "up") StepState.Done else StepState.Pending,
                stringResource(R.string.step_connect),
                stringResource(R.string.step_connect_sub)
            )
        }

        Spacer(Modifier.height(12.dp))
        HCard(accent = NeonViolet) {
            SectionTitle(stringResource(R.string.dc_title), NeonViolet)
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
                color = scheme.onSurfaceVariant
            )
        }
        Spacer(Modifier.height(8.dp))
    }
}

@Composable
fun Tile(label: String, value: String, accent: androidx.compose.ui.graphics.Color, modifier: Modifier = Modifier) {
    HCard(modifier, accent = accent) {
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(4.dp))
        Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, maxLines = 1)
    }
}
