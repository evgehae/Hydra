package app.hydra

import android.content.Context
import android.content.res.Configuration
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import kotlinx.coroutines.delay
import androidx.core.content.ContextCompat
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import java.util.Locale

class MainActivity : ComponentActivity() {

    // Язык приложения: выбранный в настройках либо системный.
    override fun attachBaseContext(base: Context) {
        val lang = Prefs(base).lang
        if (lang == "system") {
            super.attachBaseContext(base)
            return
        }
        val cfg = Configuration(base.resources.configuration)
        cfg.setLocale(Locale(lang))
        super.attachBaseContext(base.createConfigurationContext(cfg))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val prefs = Prefs(this)
        setContent {
            HydraTheme {
                HydraBackground {
                    Surface(
                        modifier = Modifier.fillMaxSize(),
                        color = Color.Transparent,
                        contentColor = MaterialTheme.colorScheme.onBackground
                    ) {
                        HydraApp(prefs) { recreate() }
                    }
                }
            }
        }
    }
}

enum class Dest { Home, Advanced, Dns, Routes, Apps, Diag, Errors, Journal }

@Composable
fun HydraApp(prefs: Prefs, onLanguageChanged: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val account = remember { AccountController(ctx.applicationContext, ctx.filesDir.absolutePath, scope) { systemDns(ctx) } }
    val vpn = remember { VpnController(ctx.applicationContext, scope) }
    val stack = remember { mutableStateListOf(Dest.Home) }

    fun go(d: Dest) { stack.add(d) }
    fun back() { if (stack.size > 1) stack.removeAt(stack.lastIndex) }
    BackHandler(enabled = stack.size > 1) { back() }

    // разрешение на уведомления (Android 13+): постоянное уведомление держит VPN живым
    val notifLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    LaunchedEffect(Unit) {
        if (android.os.Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            notifLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        account.ensureAll()
    }
    // самовосстановление регистрации: если аккаунта нет, пробуем снова (то по Wi-Fi, то через мобильную сеть)
    LaunchedEffect(Unit) {
        while (true) {
            delay(5000)
            account.heal()
        }
    }

    Box(Modifier.fillMaxSize().statusBarsPadding()) {
        when (stack.last()) {
            Dest.Home -> HomeScreen(prefs, account, vpn, onAdvanced = { go(Dest.Advanced) }, onDiag = { go(Dest.Diag) })
            Dest.Advanced -> AdvancedScreen(
                prefs, account, vpn, onBack = { back() },
                onApps = { go(Dest.Apps) }, onRoutes = { go(Dest.Routes) }, onDns = { go(Dest.Dns) },
                onResetAll = onLanguageChanged, onLanguageChanged = onLanguageChanged
            )
            Dest.Dns -> DnsScreen(prefs, vpn, onBack = { back() })
            Dest.Routes -> RoutesScreen(prefs, vpn, onBack = { back() })
            Dest.Apps -> SubPage(stringResource(R.string.conn_apps), onBack = { back() }, scroll = false) { AppsScreen(prefs) }
            Dest.Diag -> DiagnosticsScreen(
                prefs, account, vpn, onBack = { back() },
                onErrors = { go(Dest.Errors) }, onJournal = { go(Dest.Journal) }
            )
            Dest.Errors -> ErrorsScreen(onBack = { back() })
            Dest.Journal -> JournalScreen(onBack = { back() })
        }
    }
}
