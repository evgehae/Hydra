package app.hydra

import android.app.Activity
import android.net.VpnService
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
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

    val onRing: () -> Unit = {
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
    val ringColor = when {
        account.busy -> scheme.primary
        !hasAccount -> scheme.outline
        vpn.state == "up" -> HydraGreen
        vpn.state == "connecting" || vpn.state == "reconnecting" -> scheme.primary
        vpn.state == "failed" -> scheme.error
        else -> scheme.primary
    }
    val animating = account.busy || vpn.state == "connecting" || vpn.state == "reconnecting"

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
        vpn.state == "up" -> stringResource(R.string.vpn_up_sub, coloLabel(vpn.colo))
        vpn.state == "connecting" -> stringResource(R.string.vpn_connecting_sub)
        vpn.state == "reconnecting" || vpn.state == "failed" ->
            if (vpn.message.isNotEmpty()) vpn.message else stringResource(R.string.vpn_connecting_sub)
        else -> stringResource(R.string.vpn_off_sub)
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Image(painterResource(R.drawable.ic_hydra_mark), contentDescription = null, modifier = Modifier.size(56.dp))
            Spacer(Modifier.width(10.dp))
            Column {
                Text("HYDRA", fontSize = 22.sp, fontWeight = FontWeight.Bold, letterSpacing = 4.sp)
                Text(
                    stringResource(R.string.home_tagline),
                    style = MaterialTheme.typography.bodySmall,
                    color = scheme.onSurfaceVariant
                )
            }
        }

        Spacer(Modifier.height(20.dp))
        PowerRing(color = ringColor, animating = animating, on = vpn.state == "up", onClick = onRing)
        Spacer(Modifier.height(12.dp))

        Text(title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(4.dp))
        Text(
            sub,
            style = MaterialTheme.typography.bodyMedium,
            color = scheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.height(22.dp))

        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Tile(
                stringResource(R.string.tile_dc),
                if (vpn.state == "up" && vpn.colo.isNotEmpty()) vpn.colo else "—",
                Modifier.weight(1f)
            )
            Tile(
                stringResource(R.string.tile_rtt),
                if (vpn.state == "up") stringResource(R.string.diag_ms, vpn.rttMs) else "—",
                Modifier.weight(1f)
            )
            Tile(
                stringResource(R.string.tile_route),
                if (vpn.state == "up") routeLabel(vpn.strategy) else "—",
                Modifier.weight(1f)
            )
        }

        Spacer(Modifier.height(12.dp))
        HCard {
            SectionTitle(stringResource(R.string.ready_title))
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
                color = scheme.onSurfaceVariant
            )
        }
    }
}

@Composable
fun Tile(label: String, value: String, modifier: Modifier = Modifier) {
    HCard(modifier) {
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(4.dp))
        Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, maxLines = 1)
    }
}

/** Большая кнопка-щит: цвет и пульсация показывают состояние. */
@Composable
fun PowerRing(color: Color, animating: Boolean, on: Boolean, onClick: () -> Unit) {
    val inf = rememberInfiniteTransition(label = "pulse")
    val pulse by inf.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1500, easing = LinearEasing), RepeatMode.Restart),
        label = "pulse"
    )
    val disc = MaterialTheme.colorScheme.primaryContainer

    Box(
        Modifier
            .size(236.dp)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onClick() },
        contentAlignment = Alignment.Center
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val c = center
            val r = size.minDimension / 2f
            // свечение
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(color.copy(alpha = if (on) 0.40f else 0.22f), Color.Transparent),
                    center = c,
                    radius = r
                ),
                radius = r,
                center = c
            )
            // расходящаяся волна
            if (animating) {
                drawCircle(
                    color = color.copy(alpha = 0.35f * (1f - pulse)),
                    radius = r * (0.70f + 0.30f * pulse),
                    center = c,
                    style = Stroke(width = 3.dp.toPx())
                )
            }
            // кольцо и диск
            drawCircle(color = disc, radius = r * 0.66f, center = c)
            drawCircle(color = color, radius = r * 0.70f, center = c, style = Stroke(width = 5.dp.toPx()))

            // щит
            val w = r * 0.60f
            val h = r * 0.70f
            val top = c.y - h / 2f
            val shield = Path().apply {
                moveTo(c.x, top)
                lineTo(c.x + w / 2f, top + h * 0.14f)
                lineTo(c.x + w / 2f, top + h * 0.56f)
                cubicTo(c.x + w / 2f, top + h * 0.80f, c.x + w * 0.24f, top + h * 0.93f, c.x, top + h)
                cubicTo(c.x - w * 0.24f, top + h * 0.93f, c.x - w / 2f, top + h * 0.80f, c.x - w / 2f, top + h * 0.56f)
                lineTo(c.x - w / 2f, top + h * 0.14f)
                close()
            }
            drawPath(
                shield,
                color = color,
                style = Stroke(width = 4.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round)
            )
            // замочная скважина
            val kc = Offset(c.x, top + h * 0.42f)
            drawCircle(color = color, radius = r * 0.075f, center = kc)
            val slot = Path().apply {
                moveTo(kc.x - r * 0.03f, kc.y + r * 0.04f)
                lineTo(kc.x + r * 0.03f, kc.y + r * 0.04f)
                lineTo(kc.x + r * 0.05f, kc.y + r * 0.17f)
                lineTo(kc.x - r * 0.05f, kc.y + r * 0.17f)
                close()
            }
            drawPath(slot, color = color)
        }
    }
}
