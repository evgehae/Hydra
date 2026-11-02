#!/usr/bin/env bash
# Создаёт файлы Android-проекта Гидры, если их ещё нет (существующие не трогает).
set -e

put() {
  f="$1"
  mkdir -p "$(dirname "$f")"
  if [ -e "$f" ]; then cat > /dev/null; else cat > "$f"; fi
}

GODIR="$(dirname "$(find . -name go.mod -not -path './app/*' | head -1)")"

put .gitignore <<'HYDRA_EOF'
.gradle/
build/
app/build/
app/libs/
local.properties
*.aar
HYDRA_EOF

put "$GODIR/mobile/mobile.go" <<'HYDRA_EOF'
// Package mobile — тонкая обвязка для gomobile: то, что видно из Kotlin.
package mobile

import (
	"fmt"

	hydra "hydra/core"
)

const version = "0.1.0"

// Version проверяет, что Go-ядро собрано и вызывается из Android.
func Version() string {
	cfg := hydra.DefaultConfig()
	return fmt.Sprintf("hydra-core %s (probe %s)", version, cfg.ProbeEvery)
}
HYDRA_EOF

put settings.gradle.kts <<'HYDRA_EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "Hydra"
include(":app")
HYDRA_EOF

put build.gradle.kts <<'HYDRA_EOF'
plugins {
    id("com.android.application") version "8.7.3" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21" apply false
}
HYDRA_EOF

put gradle.properties <<'HYDRA_EOF'
org.gradle.jvmargs=-Xmx3g -Dfile.encoding=UTF-8
android.useAndroidX=true
android.nonTransitiveRClass=true
HYDRA_EOF

put app/build.gradle.kts <<'HYDRA_EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "app.hydra"
    compileSdk = 35

    defaultConfig {
        applicationId = "app.hydra"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
        ndk { abiFilters += listOf("arm64-v8a") }
    }

    buildTypes {
        release { isMinifyEnabled = false }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.10.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation(files("libs/hydra.aar"))
}
HYDRA_EOF

put app/src/main/AndroidManifest.xml <<'HYDRA_EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />

    <queries>
        <intent>
            <action android:name="android.intent.action.MAIN" />
            <category android:name="android.intent.category.LAUNCHER" />
        </intent>
    </queries>

    <application
        android:allowBackup="false"
        android:label="@string/app_name"
        android:theme="@style/Theme.Hydra">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
HYDRA_EOF

put app/src/main/res/values/themes.xml <<'HYDRA_EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="Theme.Hydra" parent="android:Theme.Material.NoActionBar" />
</resources>
HYDRA_EOF

put app/src/main/res/values/strings.xml <<'HYDRA_EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">Hydra</string>

    <string name="tab_home">Home</string>
    <string name="tab_split">Apps</string>
    <string name="tab_diag">Diagnostics</string>
    <string name="tab_settings">Settings</string>

    <string name="home_status_idle">Not connected</string>
    <string name="home_connect">Connect</string>
    <string name="home_soon">Connection arrives in the next build</string>
    <string name="home_engine">Engine: %1$s</string>

    <string name="split_title">Split tunneling</string>
    <string name="split_mode_only">Only selected apps use the VPN</string>
    <string name="split_mode_except">All apps except the selected ones</string>
    <string name="split_count">Selected: %1$d</string>

    <string name="diag_title">Diagnostics</string>
    <string name="diag_run">Check network</string>
    <string name="diag_running">Checking…</string>

    <string name="settings_title">Settings</string>
    <string name="settings_language">Language</string>
    <string name="lang_system">System</string>
    <string name="lang_en">English</string>
    <string name="lang_ru">Русский</string>
    <string name="settings_autostart">Connect on startup</string>
    <string name="settings_killswitch">Block traffic if the VPN drops</string>
    <string name="settings_soon">These options take effect once connection is ready.</string>
</resources>
HYDRA_EOF

put app/src/main/res/values-ru/strings.xml <<'HYDRA_EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">Hydra</string>

    <string name="tab_home">Главная</string>
    <string name="tab_split">Приложения</string>
    <string name="tab_diag">Диагностика</string>
    <string name="tab_settings">Настройки</string>

    <string name="home_status_idle">Не подключено</string>
    <string name="home_connect">Подключить</string>
    <string name="home_soon">Подключение появится в следующей сборке</string>
    <string name="home_engine">Движок: %1$s</string>

    <string name="split_title">Раздельное туннелирование</string>
    <string name="split_mode_only">Через VPN только выбранные приложения</string>
    <string name="split_mode_except">Все приложения, кроме выбранных</string>
    <string name="split_count">Выбрано: %1$d</string>

    <string name="diag_title">Диагностика</string>
    <string name="diag_run">Проверить сеть</string>
    <string name="diag_running">Проверяю…</string>

    <string name="settings_title">Настройки</string>
    <string name="settings_language">Язык</string>
    <string name="lang_system">Системный</string>
    <string name="lang_en">English</string>
    <string name="lang_ru">Русский</string>
    <string name="settings_autostart">Подключаться при запуске</string>
    <string name="settings_killswitch">Блокировать трафик при обрыве VPN</string>
    <string name="settings_soon">Эти опции заработают, когда будет готово подключение.</string>
</resources>
HYDRA_EOF

put app/src/main/java/app/hydra/Prefs.kt <<'HYDRA_EOF'
package app.hydra

import android.content.Context

class Prefs(ctx: Context) {
    private val sp = ctx.getSharedPreferences("hydra", Context.MODE_PRIVATE)

    var lang: String
        get() = sp.getString("lang", "system") ?: "system"
        set(v) { sp.edit().putString("lang", v).apply() }

    var splitOnlySelected: Boolean
        get() = sp.getBoolean("split_only", true)
        set(v) { sp.edit().putBoolean("split_only", v).apply() }

    var splitApps: Set<String>
        get() = sp.getStringSet("split_apps", emptySet())?.toSet() ?: emptySet()
        set(v) { sp.edit().putStringSet("split_apps", v.toSet()).apply() }

    var autoStart: Boolean
        get() = sp.getBoolean("auto_start", false)
        set(v) { sp.edit().putBoolean("auto_start", v).apply() }

    var killSwitch: Boolean
        get() = sp.getBoolean("kill_switch", false)
        set(v) { sp.edit().putBoolean("kill_switch", v).apply() }
}
HYDRA_EOF

put app/src/main/java/app/hydra/Diagnostics.kt <<'HYDRA_EOF'
package app.hydra

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.URL

/** Простая проверка сети: DNS и HTTPS до Cloudflare (+ покажет, идёт ли трафик через WARP). */
suspend fun runDiagnostics(): String = withContext(Dispatchers.IO) {
    val sb = StringBuilder()

    var t = System.currentTimeMillis()
    try {
        val ip = InetAddress.getByName("cloudflare.com").hostAddress
        sb.append("DNS: OK ($ip, ${System.currentTimeMillis() - t} ms)\n")
    } catch (e: Exception) {
        sb.append("DNS: FAIL (${e.javaClass.simpleName})\n")
    }

    t = System.currentTimeMillis()
    try {
        val c = URL("https://cloudflare.com/cdn-cgi/trace").openConnection() as HttpURLConnection
        c.connectTimeout = 5000
        c.readTimeout = 5000
        val body = c.inputStream.bufferedReader().use { it.readText() }
        c.disconnect()
        val kv = body.lines()
            .mapNotNull { l -> l.split("=", limit = 2).takeIf { it.size == 2 }?.let { it[0] to it[1] } }
            .toMap()
        sb.append("HTTPS: OK (${System.currentTimeMillis() - t} ms)\n")
        sb.append("IP: ${kv["ip"]}\n")
        sb.append("Loc: ${kv["loc"]}\n")
        sb.append("Colo: ${kv["colo"]}\n")
        sb.append("WARP: ${kv["warp"]}\n")
    } catch (e: Exception) {
        sb.append("HTTPS: FAIL (${e.javaClass.simpleName})\n")
    }

    sb.toString()
}
HYDRA_EOF

put app/src/main/java/app/hydra/MainActivity.kt <<'HYDRA_EOF'
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
HYDRA_EOF
