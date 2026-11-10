package app.hydra

import android.app.Activity
import android.net.VpnService
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private val TitleBlue = Color(0xFF3F5BFF)

/** Главный экран: как у 1.1.1.1 — название, большой ползунок, статус. Меню (три полоски) — справа сверху. */
@Composable
fun HomeScreen(
    prefs: Prefs,
    account: AccountController,
    vpn: VpnController,
    onAdvanced: () -> Unit,
    onDiag: () -> Unit
) {
    val ctx = LocalContext.current
    val hasAccount = account.id.isNotEmpty() || account.wgId.isNotEmpty()
    val needAppsToast = stringResource(R.string.need_apps_toast)
    val scope = rememberCoroutineScope()
    var menu by remember { mutableStateOf(false) }

    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        if (r.resultCode == Activity.RESULT_OK) vpn.start()
    }

    val onTap: () -> Unit = {
        when {
            account.working -> {}
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

    val up = vpn.state == "up"
    val busy = account.working || vpn.state == "connecting" || vpn.state == "reconnecting"
    val scheme = MaterialTheme.colorScheme

    val title = when {
        account.working -> stringResource(R.string.home_status_registering)
        !hasAccount -> stringResource(R.string.home_status_need_account)
        vpn.state == "up" -> stringResource(R.string.vpn_up)
        vpn.state == "connecting" -> stringResource(R.string.vpn_connecting)
        vpn.state == "reconnecting" -> stringResource(R.string.vpn_reconnecting)
        vpn.state == "failed" -> stringResource(R.string.vpn_failed)
        else -> stringResource(R.string.vpn_off)
    }
    val sub = when {
        account.working -> stringResource(R.string.home_sub_registering)
        !hasAccount -> stringResource(R.string.home_sub_need_account)
        up -> if (vpn.message.isNotEmpty()) vpn.message else stringResource(R.string.home_private)
        vpn.state == "connecting" -> stringResource(R.string.vpn_connecting_sub)
        vpn.state == "reconnecting" || vpn.state == "failed" ->
            if (vpn.message.isNotEmpty()) vpn.message else stringResource(R.string.vpn_connecting_sub)
        else -> stringResource(R.string.home_not_private)
    }

    Column(Modifier.fillMaxSize().padding(horizontal = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        // три полоски справа сверху: «Дополнительно» и «Диагностика»
        Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.End) {
            Box {
                IconButton(onClick = { menu = true }) {
                    Icon(Icons.Filled.Menu, contentDescription = stringResource(R.string.menu_title), modifier = Modifier.size(32.dp))
                }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.menu_advanced)) },
                        onClick = { menu = false; onAdvanced() }
                    )
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.menu_diag)) },
                        onClick = { menu = false; onDiag() }
                    )
                }
            }
        }

        Spacer(Modifier.weight(0.8f))
        // «WARP» крупными огненно-красными буквами, под ним синим «CLAUDE» поменьше
        Text(
            "WARP",
            style = TextStyle(
                brush = Brush.linearGradient(
                    listOf(Color(0xFFFF3B2F), Color(0xFFFF7A33), Color(0xFFE5301F), Color(0xFFFF5A3C))
                ),
                fontSize = 86.sp,
                fontWeight = FontWeight.Black,
                letterSpacing = (-2).sp,
                textAlign = TextAlign.Center
            )
        )
        Text(
            "CLAUDE",
            color = TitleBlue,
            fontSize = 30.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = 10.sp,
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.weight(0.7f))

        BigToggle(on = up, busy = busy, onClick = onTap)

        Spacer(Modifier.height(28.dp))
        Text(title, fontSize = 26.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        Spacer(Modifier.height(14.dp))
        Text(
            sub,
            fontSize = 20.sp,
            lineHeight = 26.sp,
            color = Color.White,
            textAlign = TextAlign.Center
        )
        // регистрация: идёт ли она сейчас или устройство ещё не зарегистрировано
        if (account.working || !hasAccount) {
            Spacer(Modifier.height(12.dp))
            Text(
                "● " + stringResource(if (account.working) R.string.reg_working else R.string.reg_none),
                style = MaterialTheme.typography.bodyMedium,
                color = NeonAmber,
                textAlign = TextAlign.Center
            )
            if (!account.working && account.failKind.isNotEmpty()) {
                Text(
                    stringResource(R.string.reg_retry),
                    style = MaterialTheme.typography.bodySmall,
                    color = scheme.onSurfaceVariant,
                    textAlign = TextAlign.Center
                )
            }
        }
        if (up && vpn.colo.isNotEmpty()) {
            Spacer(Modifier.height(10.dp))
            Text(
                coloLabel(vpn.colo) + " · " + stringResource(R.string.diag_ms, vpn.rttMs),
                style = MaterialTheme.typography.bodyMedium,
                color = scheme.onSurfaceVariant
            )
        }

        // ошибка регистрации: показываем причину и запасной путь
        val failKind = account.failKind
        if (!hasAccount && !account.working && failKind.isNotEmpty()) {
            Spacer(Modifier.height(16.dp))
            Text(failText(failKind), style = MaterialTheme.typography.bodySmall, color = scheme.error, textAlign = TextAlign.Center)
            Spacer(Modifier.height(8.dp))
            OutlinedButton(onClick = { account.registerViaCellular() }) {
                Text(stringResource(R.string.action_register_cell))
            }
        }

        // все маршруты ведут в запрещённый дата-центр: выход одним нажатием
        if (vpn.state == "failed" && vpn.message.startsWith("⛔")) {
            Spacer(Modifier.height(16.dp))
            HCard {
                Text(stringResource(R.string.banner_blocked_title), fontWeight = FontWeight.SemiBold, color = NeonAmber)
                Text(
                    stringResource(R.string.banner_blocked_text),
                    style = MaterialTheme.typography.bodySmall,
                    color = scheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 4.dp, bottom = 8.dp)
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(
                        onClick = {
                            prefs.channel = "cell"
                            scope.launch { vpn.stop(); delay(1200); vpn.start() }
                        },
                        modifier = Modifier.weight(1f)
                    ) { Text(stringResource(R.string.banner_use_cell)) }
                    OutlinedButton(
                        onClick = {
                            prefs.fallbackAny = true
                            scope.launch { vpn.stop(); delay(1200); vpn.start() }
                        },
                        modifier = Modifier.weight(1f)
                    ) { Text(stringResource(R.string.banner_allow)) }
                }
            }
        }
        Spacer(Modifier.weight(2.2f))
    }
}

/** Большой ползунок как у 1.1.1.1: белый кружок слева — выключено, справа — включено. */
@Composable
fun BigToggle(on: Boolean, busy: Boolean, onClick: () -> Unit) {
    val right = on || busy
    val offset by animateDpAsState(if (right) 74.dp else 0.dp, label = "thumb")
    val track = when {
        on -> Color(0xFF2F6BFF)
        busy -> Color(0xFFE8A317)
        else -> Color(0xFF1E1E1E)
    }
    Box(
        Modifier
            .size(width = 150.dp, height = 76.dp)
            .clip(RoundedCornerShape(38.dp))
            .background(track)
            .clickable(onClick = onClick)
            .padding(7.dp)
    ) {
        Box(Modifier.offset(x = offset).size(62.dp).clip(CircleShape).background(Color.White))
    }
}
