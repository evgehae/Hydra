package app.hydra

import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
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
            val colors = if (isSystemInDarkTheme()) darkColorScheme() else lightColorScheme()
            MaterialTheme(colorScheme = colors) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    HydraApp(prefs) { recreate() }
                }
            }
        }
    }
}

@Composable
fun HydraApp(prefs: Prefs, onLanguageChanged: () -> Unit) {
    var tab by rememberSaveable { mutableStateOf(0) }
    Scaffold(
        bottomBar = {
            NavigationBar {
                NavigationBarItem(
                    selected = tab == 0, onClick = { tab = 0 },
                    icon = { Icon(Icons.Filled.Home, contentDescription = null) },
                    label = { Text(stringResource(R.string.tab_home)) }
                )
                NavigationBarItem(
                    selected = tab == 1, onClick = { tab = 1 },
                    icon = { Icon(Icons.Filled.Lock, contentDescription = null) },
                    label = { Text(stringResource(R.string.tab_split)) }
                )
                NavigationBarItem(
                    selected = tab == 2, onClick = { tab = 2 },
                    icon = { Icon(Icons.Filled.Build, contentDescription = null) },
                    label = { Text(stringResource(R.string.tab_diag)) }
                )
                NavigationBarItem(
                    selected = tab == 3, onClick = { tab = 3 },
                    icon = { Icon(Icons.Filled.Settings, contentDescription = null) },
                    label = { Text(stringResource(R.string.tab_settings)) }
                )
            }
        }
    ) { pad ->
        Box(Modifier.padding(pad).statusBarsPadding().fillMaxSize()) {
            when (tab) {
                0 -> HomeScreen()
                1 -> SplitScreen(prefs)
                2 -> DiagScreen()
                else -> SettingsScreen(prefs, onLanguageChanged)
            }
        }
    }
}

@Composable
fun HomeScreen() {
    val engine = remember {
        try { mobile.Mobile.version() } catch (t: Throwable) { "n/a" }
    }
    Column(
        Modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text("Hydra", style = MaterialTheme.typography.displayMedium)
        Spacer(Modifier.height(8.dp))
        Text(stringResource(R.string.home_status_idle), style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(24.dp))
        Button(onClick = {}, enabled = false) { Text(stringResource(R.string.home_connect)) }
        Spacer(Modifier.height(12.dp))
        Text(stringResource(R.string.home_soon), style = MaterialTheme.typography.bodyMedium)
        Spacer(Modifier.height(24.dp))
        Text(stringResource(R.string.home_engine, engine), style = MaterialTheme.typography.bodySmall)
    }
}

data class AppItem(val pkg: String, val label: String)

@Composable
fun SplitScreen(prefs: Prefs) {
    val ctx = LocalContext.current
    var apps by remember { mutableStateOf<List<AppItem>>(emptyList()) }
    var selected by remember { mutableStateOf(prefs.splitApps) }
    var onlySelected by remember { mutableStateOf(prefs.splitOnlySelected) }

    LaunchedEffect(Unit) {
        apps = withContext(Dispatchers.IO) {
            val pm = ctx.packageManager
            val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
            pm.queryIntentActivities(intent, 0)
                .map { AppItem(it.activityInfo.packageName, it.loadLabel(pm).toString()) }
                .distinctBy { it.pkg }
                .sortedBy { it.label.lowercase() }
        }
    }

    Column(Modifier.fillMaxSize()) {
        Text(
            stringResource(R.string.split_title),
            style = MaterialTheme.typography.titleLarge,
            modifier = Modifier.padding(16.dp)
        )
        ModeRow(R.string.split_mode_only, onlySelected) {
            onlySelected = true
            prefs.splitOnlySelected = true
        }
        ModeRow(R.string.split_mode_except, !onlySelected) {
            onlySelected = false
            prefs.splitOnlySelected = false
        }
        Text(
            stringResource(R.string.split_count, selected.size),
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.padding(16.dp)
        )
        LazyColumn(Modifier.fillMaxSize()) {
            items(apps, key = { it.pkg }) { a ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clickable {
                            val n = if (a.pkg in selected) selected - a.pkg else selected + a.pkg
                            selected = n
                            prefs.splitApps = n
                        }
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Checkbox(checked = a.pkg in selected, onCheckedChange = null)
                    Spacer(Modifier.width(12.dp))
                    Text(a.label)
                }
            }
        }
    }
}

@Composable
fun ModeRow(label: Int, selected: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable { onClick() }.padding(horizontal = 16.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        RadioButton(selected = selected, onClick = null)
        Spacer(Modifier.width(8.dp))
        Text(stringResource(label))
    }
}

@Composable
fun DiagScreen() {
    val scope = rememberCoroutineScope()
    var running by remember { mutableStateOf(false) }
    var report by remember { mutableStateOf("") }
    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Text(stringResource(R.string.diag_title), style = MaterialTheme.typography.titleLarge)
        Spacer(Modifier.height(12.dp))
        Button(
            onClick = {
                if (!running) {
                    running = true
                    scope.launch {
                        report = runDiagnostics()
                        running = false
                    }
                }
            },
            enabled = !running
        ) {
            Text(stringResource(if (running) R.string.diag_running else R.string.diag_run))
        }
        Spacer(Modifier.height(12.dp))
        Text(text = report, fontFamily = FontFamily.Monospace)
    }
}

@Composable
fun SettingsScreen(prefs: Prefs, onLanguageChanged: () -> Unit) {
    var lang by remember { mutableStateOf(prefs.lang) }
    var auto by remember { mutableStateOf(prefs.autoStart) }
    var kill by remember { mutableStateOf(prefs.killSwitch) }
    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Text(stringResource(R.string.settings_title), style = MaterialTheme.typography.titleLarge)
        Spacer(Modifier.height(16.dp))
        Text(stringResource(R.string.settings_language), style = MaterialTheme.typography.titleMedium)
        listOf(
            "system" to R.string.lang_system,
            "en" to R.string.lang_en,
            "ru" to R.string.lang_ru
        ).forEach { (code, res) ->
            Row(
                Modifier
                    .fillMaxWidth()
                    .clickable {
                        if (lang != code) {
                            lang = code
                            prefs.lang = code
                            onLanguageChanged()
                        }
                    }
                    .padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                RadioButton(selected = lang == code, onClick = null)
                Spacer(Modifier.width(8.dp))
                Text(stringResource(res))
            }
        }
        Spacer(Modifier.height(16.dp))
        SwitchRow(R.string.settings_autostart, auto) {
            auto = it
            prefs.autoStart = it
        }
        SwitchRow(R.string.settings_killswitch, kill) {
            kill = it
            prefs.killSwitch = it
        }
        Spacer(Modifier.height(8.dp))
        Text(stringResource(R.string.settings_soon), style = MaterialTheme.typography.bodySmall)
        Spacer(Modifier.height(24.dp))
        Text("Hydra 0.1.0", style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
fun SwitchRow(label: Int, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(stringResource(label))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}
