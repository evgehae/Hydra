#!/usr/bin/env bash
# Создаёт файлы Android-проекта Гидры, если их ещё нет (существующие не трогает).
set -e

put() {
  f="$1"
  mkdir -p "$(dirname "$f")"
  if [ -e "$f" ]; then cat > /dev/null; else cat > "$f"; fi
}

# Версия набора файлов: при смене номера файлы ниже обновляются один раз, потом их можно править руками.
STAMP=.hydra_bootstrap
OLD="$(cat "$STAMP" 2>/dev/null || echo 0)"
NEW=6
putv() {
  f="$1"
  mkdir -p "$(dirname "$f")"
  if [ ! -e "$f" ] || [ "$OLD" -lt "$NEW" ]; then cat > "$f"; else cat > /dev/null; fi
}
# то же для двоичных файлов (картинки), переданных как base64
putb() {
  f="$1"
  mkdir -p "$(dirname "$f")"
  if [ ! -e "$f" ] || [ "$OLD" -lt "$NEW" ]; then base64 -d > "$f"; else cat > /dev/null; fi
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

# ===================== v6 =====================
putv "$GODIR/colo.go" <<'HYDRA_EOF'
package hydra

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// ColoPolicy — политика выбора дата-центра Cloudflare (по коду аэропорта).
// Block — запрещённые коды; Allow — если не пусто, разрешены только они.
type ColoPolicy struct {
	Block []string
	Allow []string
}

// DefaultColoPolicy: никакой Москвы (DME) и остальных российских точек Cloudflare.
func DefaultColoPolicy() *ColoPolicy {
	return &ColoPolicy{Block: []string{"DME", "LED", "SVX", "KJA", "OVB", "KHV", "VVO", "KZN"}}
}

func normColo(s string) string { return strings.ToUpper(strings.TrimSpace(s)) }

// Allows: nil-политика и неизвестный дата-центр (пустой код) не блокируются.
func (p *ColoPolicy) Allows(colo string) bool {
	if p == nil {
		return true
	}
	c := normColo(colo)
	if c == "" {
		return true
	}
	for _, b := range p.Block {
		if normColo(b) == c {
			return false
		}
	}
	if len(p.Allow) > 0 {
		for _, a := range p.Allow {
			if normColo(a) == c {
				return true
			}
		}
		return false
	}
	return true
}

// ParseColoList разбирает "dme, LED;fra" в ["DME","LED","FRA"] без повторов.
func ParseColoList(s string) []string {
	seen := map[string]bool{}
	var out []string
	split := func(r rune) bool { return r == ',' || r == ';' || r == ' ' || r == '\n' || r == '\t' }
	for _, f := range strings.FieldsFunc(s, split) {
		c := normColo(f)
		if c != "" && !seen[c] {
			seen[c] = true
			out = append(out, c)
		}
	}
	return out
}

// ColoError — туннель поднялся, но попал в запрещённый дата-центр.
type ColoError struct{ Colo string }

func (e *ColoError) Error() string {
	return fmt.Sprintf("дата-центр %s запрещён политикой", e.Colo)
}

// ColoReporter — необязательный интерфейс туннеля: сказать, через какой
// дата-центр он идёт. Туннели без него пропускаются без проверки.
type ColoReporter interface {
	Colo(ctx context.Context) (string, error)
}

// ParseTrace разбирает ответ https://cloudflare.com/cdn-cgi/trace.
func ParseTrace(body string) map[string]string {
	m := map[string]string{}
	sc := bufio.NewScanner(strings.NewReader(body))
	for sc.Scan() {
		if k, v, ok := strings.Cut(sc.Text(), "="); ok {
			m[strings.TrimSpace(k)] = strings.TrimSpace(v)
		}
	}
	return m
}

// TraceColo — стандартный способ узнать дата-центр: запрос trace через туннель.
func TraceColo(ctx context.Context, t Tunnel) (string, error) {
	tr := &http.Transport{
		DialContext:         t.DialContext,
		DisableKeepAlives:   true,
		TLSHandshakeTimeout: 8 * time.Second,
	}
	cl := &http.Client{Transport: tr, Timeout: 10 * time.Second}
	req, err := http.NewRequestWithContext(ctx, "GET", "https://cloudflare.com/cdn-cgi/trace", nil)
	if err != nil {
		return "", err
	}
	resp, err := cl.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
	colo := normColo(ParseTrace(string(body))["colo"])
	if colo == "" {
		return "", errors.New("в ответе trace нет colo")
	}
	return colo, nil
}
HYDRA_EOF

putv "$GODIR/colo_test.go" <<'HYDRA_EOF'
package hydra

import (
	"context"
	"strings"
	"testing"
)

type coloTunnel struct {
	*fakeTunnel
	colo string
}

func (c *coloTunnel) Colo(context.Context) (string, error) { return c.colo, nil }

func coloTransport(colos map[string]string, order ...string) *fakeTransport {
	var ss []Strategy
	for _, id := range order {
		ss = append(ss, Strategy{ID: id, Transport: "fake"})
	}
	return &fakeTransport{
		strategies: ss,
		dial: func(ctx context.Context, s Strategy) (Tunnel, error) {
			return &coloTunnel{newFakeTunnel(0), colos[s.ID]}, nil
		},
	}
}

func TestColoPolicy(t *testing.T) {
	p := DefaultColoPolicy()
	for _, c := range []string{"DME", "dme", " LED "} {
		if p.Allows(c) {
			t.Fatalf("%q должен быть запрещён", c)
		}
	}
	for _, c := range []string{"HEL", "FRA", "AMS", "ARN", ""} {
		if !p.Allows(c) {
			t.Fatalf("%q должен быть разрешён", c)
		}
	}
	onlyEU := &ColoPolicy{Allow: []string{"hel", "fra"}}
	if !onlyEU.Allows("HEL") || onlyEU.Allows("AMS") {
		t.Fatal("Allow-список работает неверно")
	}
	var nilp *ColoPolicy
	if !nilp.Allows("DME") {
		t.Fatal("nil-политика ничего не блокирует")
	}
}

func TestParseColoList(t *testing.T) {
	got := strings.Join(ParseColoList("dme, LED;fra  dme"), ",")
	if got != "DME,LED,FRA" {
		t.Fatalf("получили %q", got)
	}
}

func TestParseTrace(t *testing.T) {
	m := ParseTrace("fl=1\nip=1.2.3.4\ncolo=HEL\nwarp=on\n")
	if m["colo"] != "HEL" || m["warp"] != "on" || m["ip"] != "1.2.3.4" {
		t.Fatalf("разбор trace: %v", m)
	}
}

func TestRaceSkipsBlockedColo(t *testing.T) {
	ft := coloTransport(map[string]string{"dme": "DME", "hel": "HEL"}, "dme", "hel")
	mem, _ := LoadMemory("")
	o := New(fastCfg(), mem, []Transport{ft}, nil)
	tun, s, err := o.race(context.Background(), "wifi:home", "")
	if err != nil || s.ID != "hel" {
		t.Fatalf("ждали hel, получили %q %v", s.ID, err)
	}
	tun.Close()
}

func TestRaceAllBlocked(t *testing.T) {
	ft := coloTransport(map[string]string{"a": "DME", "b": "LED"}, "a", "b")
	mem, _ := LoadMemory("")
	o := New(fastCfg(), mem, []Transport{ft}, nil)
	_, _, err := o.race(context.Background(), "wifi:home", "")
	if err == nil || !strings.Contains(err.Error(), "DME") {
		t.Fatalf("ждали ошибку про запрещённые дата-центры, получили %v", err)
	}
}
HYDRA_EOF

putv "$GODIR/dns.go" <<'HYDRA_EOF'
package hydra

import (
	"context"
	"net"
	"strings"
	"sync/atomic"
	"time"
)

// На Android у Go нет /etc/resolv.conf, поэтому встроенный резолвер идёт на
// localhost:53 — а там никого нет, и любое имя «не находится». Лечим: сами
// задаём DNS-серверы. Системные присылает Android-часть, запасные — ниже.
var fallbackDNS = []string{"8.8.8.8", "1.1.1.1", "77.88.8.8"}

// SetSystemDNS подменяет резолвер процесса: сначала переданные серверы
// (только IP-адреса), потом запасные. Каждая новая попытка идёт на следующий сервер.
func SetSystemDNS(servers []string) {
	var list []string
	seen := map[string]bool{}
	add := func(s string) {
		s = strings.TrimSpace(s)
		if s == "" || net.ParseIP(s) == nil || seen[s] {
			return
		}
		seen[s] = true
		list = append(list, s)
	}
	for _, s := range servers {
		add(s)
	}
	for _, s := range fallbackDNS {
		add(s)
	}
	var n uint32
	net.DefaultResolver = &net.Resolver{
		PreferGo: true,
		Dial: func(ctx context.Context, network, _ string) (net.Conn, error) {
			i := int(atomic.AddUint32(&n, 1)-1) % len(list)
			d := net.Dialer{Timeout: 3 * time.Second}
			return d.DialContext(ctx, network, net.JoinHostPort(list[i], "53"))
		},
	}
}
HYDRA_EOF

putv "$GODIR/dns_test.go" <<'HYDRA_EOF'
package hydra

import (
	"context"
	"net"
	"testing"
)

func TestSetSystemDNSRotatesServers(t *testing.T) {
	old := net.DefaultResolver
	defer func() { net.DefaultResolver = old }()

	SetSystemDNS([]string{"127.0.0.1", "мусор", "127.0.0.2", "127.0.0.1"})
	r := net.DefaultResolver
	if !r.PreferGo || r.Dial == nil {
		t.Fatal("резолвер не подменён")
	}
	var got []string
	for i := 0; i < 2; i++ {
		c, err := r.Dial(context.Background(), "udp", "ignored:53")
		if err != nil {
			t.Fatal(err)
		}
		got = append(got, c.RemoteAddr().String())
		c.Close()
	}
	if got[0] != "127.0.0.1:53" || got[1] != "127.0.0.2:53" {
		t.Fatalf("серверы по кругу: %v", got)
	}
}
HYDRA_EOF

putv "$GODIR/engine.go" <<'HYDRA_EOF'
package hydra

import (
	"context"
	"errors"
	"fmt"
	"io"
	"math/rand"
	"net"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// Engine — «сердце» Гидры на телефоне. Android отдаёт TUN (поток IP-пакетов),
// Engine гоняет их через туннель WARP и сам следит за ним:
//   - после подключения узнаёт дата-центр Cloudflare; запрещённый — отбрасывает;
//   - проверяет, что через туннель реально проходит TCP, а не только «рукопожатие»;
//   - при смене сети (Wi-Fi ↔ мобильная) сразу переподключается;
//   - при сбое переходит на другую стратегию; запоминает, что работало в каждой сети;
//   - всё, что происходит и почему, пишет в журнал.

// PacketDevice — «сетевая карта» для туннеля (те же методы, что у TunnelDevice в usque).
type PacketDevice interface {
	ReadPacket(buf []byte) (int, error)
	WritePacket(pkt []byte) error
}

// Runner держит туннель по стратегии s, пока ctx не отменён или не случилась
// непоправимая ошибка. Пакеты читает/пишет через dev.
type Runner func(ctx context.Context, dev PacketDevice, s Strategy) error

type EngineConfig struct {
	LocalIP      net.IP // IPv4-адрес внутри туннеля (из аккаунта)
	Strategies   []Strategy
	Runner       Runner
	Policy       *ColoPolicy
	SoftFallback bool // если все адреса ведут в запрещённый дата-центр — всё равно подключиться
	Mem          *Memory
	NetKey       func() string
	NetChanged   <-chan struct{} // сигнал «сеть сменилась» от Android
	ProbeEvery   time.Duration
	UpTimeout    time.Duration // сколько ждать первого ответа после старта стратегии
	BadProbes    int           // сколько проб подряд без ответа = туннель умер
	TCPCheck     bool          // проверять реальную передачу TCP
	TCPTimeout   time.Duration // ожидание SYN-ACK (по умолчанию 2 с)
}

func DefaultEngineConfig() EngineConfig {
	return EngineConfig{ProbeEvery: 3 * time.Second, UpTimeout: 8 * time.Second, BadProbes: 3, TCPCheck: true}
}

type Status struct {
	State    string // connecting | up | reconnecting | failed
	Strategy string
	Colo     string
	RTT      time.Duration
	Message  string
}

type Engine struct {
	cfg     EngineConfig
	tun     io.ReadWriteCloser
	out     chan []byte // пакеты из TUN (от приложений)
	probeQ  chan []byte
	port    uint16
	tcpPort uint16
	tcpSeq  uint32
	tcpAck  chan struct{}
	nextID  uint32
	events  chan Event
	tunDead chan struct{}
	once    sync.Once
	soft    bool

	mu      sync.Mutex
	status  Status
	waiters map[uint16]chan string
}

func NewEngine(tun io.ReadWriteCloser, cfg EngineConfig) *Engine {
	d := DefaultEngineConfig()
	if cfg.ProbeEvery <= 0 {
		cfg.ProbeEvery = d.ProbeEvery
	}
	if cfg.UpTimeout <= 0 {
		cfg.UpTimeout = d.UpTimeout
	}
	if cfg.BadProbes <= 0 {
		cfg.BadProbes = d.BadProbes
	}
	if cfg.TCPTimeout <= 0 {
		cfg.TCPTimeout = 2 * time.Second
	}
	if cfg.Mem == nil {
		cfg.Mem, _ = LoadMemory("")
	}
	if cfg.NetKey == nil {
		cfg.NetKey = func() string { return "default" }
	}
	return &Engine{
		cfg:     cfg,
		tun:     tun,
		out:     make(chan []byte, 512),
		probeQ:  make(chan []byte, 16),
		port:    uint16(20000 + rand.Intn(20000)),
		tcpPort: uint16(41000 + rand.Intn(20000)),
		tcpAck:  make(chan struct{}, 1),
		events:  make(chan Event, 64),
		tunDead: make(chan struct{}),
		waiters: map[uint16]chan string{},
		status:  Status{State: "connecting"},
	}
}

func (e *Engine) Events() <-chan Event { return e.events }

func (e *Engine) Status() Status {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.status
}

func (e *Engine) setStatus(s Status) {
	e.mu.Lock()
	e.status = s
	e.mu.Unlock()
}

func (e *Engine) emit(kind, strategy, msg string) {
	select {
	case e.events <- Event{Kind: kind, Strategy: strategy, Msg: msg, At: time.Now()}:
	default:
	}
}

func (e *Engine) Close() { e.once.Do(func() { e.tun.Close() }) }

func (e *Engine) policy() *ColoPolicy {
	if e.soft {
		return nil
	}
	return e.cfg.Policy
}

// readTun читает пакеты приложений. Пока туннеля нет, лишние пакеты отбрасываются.
func (e *Engine) readTun() {
	defer close(e.tunDead)
	for {
		buf := make([]byte, 2048)
		n, err := e.tun.Read(buf)
		if err != nil {
			return
		}
		select {
		case e.out <- buf[:n]:
		default:
		}
	}
}

// attemptDev — «карта» одной попытки: после отмены попытки её горутины
// просыпаются с ошибкой и не крадут пакеты у следующей попытки.
type attemptDev struct {
	e    *Engine
	done <-chan struct{}
}

func (d *attemptDev) ReadPacket(buf []byte) (int, error) {
	select {
	case <-d.done:
		return 0, io.EOF
	case <-d.e.tunDead:
		return 0, io.EOF
	case p := <-d.e.probeQ:
		return copy(buf, p), nil
	case p := <-d.e.out:
		return copy(buf, p), nil
	}
}

func (d *attemptDev) WritePacket(pkt []byte) error {
	select {
	case <-d.done:
		return io.ErrClosedPipe
	default:
	}
	if id, colo, ok := ParseColoReply(pkt, d.e.port); ok {
		d.e.deliver(id, colo)
		return nil
	}
	if ParseTCPSynAck(pkt, d.e.tcpPort, atomic.LoadUint32(&d.e.tcpSeq)+1) {
		select {
		case d.e.tcpAck <- struct{}{}:
		default:
		}
		return nil
	}
	_, err := d.e.tun.Write(pkt)
	return err
}

func (e *Engine) deliver(id uint16, colo string) {
	e.mu.Lock()
	ch := e.waiters[id]
	e.mu.Unlock()
	if ch != nil {
		select {
		case ch <- colo:
		default:
		}
	}
}

// probe шлёт UDP-пробу (DNS id.server) и ждёт ответ: задержка и код дата-центра.
func (e *Engine) probe(ctx context.Context, timeout time.Duration) (time.Duration, string, error) {
	id := uint16(atomic.AddUint32(&e.nextID, 1))
	ch := make(chan string, 1)
	e.mu.Lock()
	e.waiters[id] = ch
	e.mu.Unlock()
	defer func() {
		e.mu.Lock()
		delete(e.waiters, id)
		e.mu.Unlock()
	}()
	pkt := BuildColoProbe(e.cfg.LocalIP, e.port, id)
	if pkt == nil {
		return 0, "", errors.New("нет IPv4-адреса туннеля")
	}
	t0 := time.Now()
	select {
	case e.probeQ <- pkt:
	default:
		return 0, "", errors.New("очередь проб переполнена")
	}
	select {
	case colo := <-ch:
		return time.Since(t0), colo, nil
	case <-time.After(timeout):
		return 0, "", errors.New("нет ответа на пробу")
	case <-ctx.Done():
		return 0, "", ctx.Err()
	}
}

// tcpProbe: SYN на 1.1.1.1:443 через туннель, ждём SYN-ACK.
func (e *Engine) tcpProbe(ctx context.Context, timeout time.Duration) (time.Duration, error) {
	seq := rand.Uint32()
	atomic.StoreUint32(&e.tcpSeq, seq)
	select {
	case <-e.tcpAck:
	default:
	}
	id := uint16(atomic.AddUint32(&e.nextID, 1))
	syn := BuildTCPSyn(e.cfg.LocalIP, e.tcpPort, seq, id)
	if syn == nil {
		return 0, errors.New("нет IPv4-адреса туннеля")
	}
	t0 := time.Now()
	select {
	case e.probeQ <- syn:
	default:
		return 0, errors.New("очередь проб переполнена")
	}
	select {
	case <-e.tcpAck:
		rtt := time.Since(t0)
		if rst := BuildTCPRst(e.cfg.LocalIP, e.tcpPort, seq+1, id+1); rst != nil {
			select {
			case e.probeQ <- rst:
			default:
			}
		}
		return rtt, nil
	case <-time.After(timeout):
		return 0, errors.New("нет SYN-ACK")
	case <-ctx.Done():
		return 0, ctx.Err()
	}
}

type outcome struct {
	wasUp       bool
	netChanged  bool
	coloBlocked string
	reason      string
}

func policyText(p *ColoPolicy) string {
	if p == nil || (len(p.Block) == 0 && len(p.Allow) == 0) {
		return "нет"
	}
	s := strings.Join(p.Block, ",")
	if len(p.Allow) > 0 {
		s += "; только: " + strings.Join(p.Allow, ",")
	}
	return s
}

func (e *Engine) fail(nk string, s Strategy, msg string) outcome {
	e.cfg.Mem.Record(nk, s.ID, false, 0)
	e.emit("failed", s.ID, msg)
	return outcome{reason: msg}
}

func (e *Engine) runStrategy(ctx context.Context, nk string, s Strategy) outcome {
	e.setStatus(Status{State: "connecting", Strategy: s.ID})
	e.emit("connecting", s.ID, "")
	Logf("▶ стратегия %s", s.ID)
	Logf("   %s", describeStrategy(s))
	select {
	case <-e.cfg.NetChanged:
	default:
	}

	actx, cancel := context.WithCancel(ctx)
	defer cancel()
	dev := &attemptDev{e: e, done: actx.Done()}
	errc := make(chan error, 1)
	go func() { errc <- e.cfg.Runner(actx, dev, s) }()

	start := time.Now()
	var colo string
	var rtt time.Duration
	up := false
	for !up && time.Since(start) < e.cfg.UpTimeout {
		select {
		case err := <-errc:
			msg := "туннель не поднялся"
			if err != nil {
				msg = err.Error()
			}
			Logf("   ✘ клиент остановился: %s", msg)
			return e.fail(nk, s, msg)
		case <-ctx.Done():
			return outcome{reason: "остановка"}
		case <-e.cfg.NetChanged:
			Logf("   ↻ сеть сменилась во время подключения — начинаю заново")
			return outcome{netChanged: true, reason: "сменилась сеть"}
		default:
		}
		r, c, err := e.probe(actx, 1500*time.Millisecond)
		if err == nil {
			up, colo, rtt = true, c, r
		} else {
			time.Sleep(200 * time.Millisecond)
		}
	}
	if !up {
		hint := ""
		if s.Params["h2"] != "1" {
			hint = " — похоже, провайдер режет QUIC к этому адресу"
		}
		msg := fmt.Sprintf("нет ответа от туннеля за %d с%s", int(e.cfg.UpTimeout.Seconds()), hint)
		Logf("   ✘ %s", msg)
		return e.fail(nk, s, msg)
	}
	Logf("   туннель ответил за %d мс, дата-центр Cloudflare: %s", rtt.Milliseconds(), colo)

	if !e.policy().Allows(colo) {
		Logf("   ✘ дата-центр %s запрещён настройками — отбрасываю этот туннель", colo)
		e.cfg.Mem.Record(nk, s.ID, false, 0)
		e.emit("colo_blocked", s.ID, colo)
		return outcome{coloBlocked: colo, reason: "дата-центр " + colo + " запрещён"}
	}

	if e.cfg.TCPCheck {
		var tcpRTT time.Duration
		var terr error
		for i := 0; i < 3; i++ {
			if tcpRTT, terr = e.tcpProbe(actx, e.cfg.TCPTimeout); terr == nil {
				break
			}
			if ctx.Err() != nil {
				return outcome{reason: "остановка"}
			}
		}
		if terr != nil {
			msg := "UDP через туннель идёт, а TCP — нет (туннель не пропускает интернет)"
			Logf("   ✘ %s", msg)
			return e.fail(nk, s, msg)
		}
		Logf("   ✔ TCP до 1.1.1.1:443 проходит (%d мс)", tcpRTT.Milliseconds())
	}

	e.cfg.Mem.Record(nk, s.ID, true, time.Since(start))
	msg := ""
	if e.soft {
		msg = "режим «всё равно»: другого дата-центра нет"
		Logf("   ⚠ %s", msg)
	}
	e.setStatus(Status{State: "up", Strategy: s.ID, Colo: colo, RTT: rtt, Message: msg})
	e.emit("connected", s.ID, colo)
	Logf("✔ подключено за %.1f с: %s, дата-центр %s, пинг %d мс", time.Since(start).Seconds(), s.ID, colo, rtt.Milliseconds())

	bad, ticks := 0, 0
	tk := time.NewTicker(e.cfg.ProbeEvery)
	defer tk.Stop()
	for {
		select {
		case <-ctx.Done():
			return outcome{wasUp: true, reason: "остановка"}
		case <-e.cfg.NetChanged:
			Logf("↻ сеть сменилась — переподключаюсь")
			return outcome{wasUp: true, netChanged: true, reason: "сменилась сеть"}
		case err := <-errc:
			msg := "туннель закрылся"
			if err != nil {
				msg = err.Error()
			}
			Logf("✘ %s", msg)
			e.cfg.Mem.Record(nk, s.ID, false, 0)
			return outcome{wasUp: true, reason: msg}
		case <-tk.C:
			if e.cfg.NetKey() != nk {
				Logf("↻ сеть сменилась (%s → %s) — переподключаюсь", nk, e.cfg.NetKey())
				return outcome{wasUp: true, netChanged: true, reason: "сменилась сеть"}
			}
			ticks++
			r, c, err := e.probe(actx, e.cfg.ProbeEvery)
			if err == nil && e.cfg.TCPCheck && ticks%5 == 0 {
				_, err = e.tcpProbe(actx, e.cfg.TCPTimeout)
			}
			if err != nil {
				bad++
				Logf("   проба без ответа (%d из %d): %v", bad, e.cfg.BadProbes, err)
				if bad >= e.cfg.BadProbes {
					e.cfg.Mem.Record(nk, s.ID, false, 0)
					e.emit("degraded", s.ID, "туннель перестал отвечать")
					Logf("✘ туннель перестал отвечать — меняю стратегию")
					return outcome{wasUp: true, reason: "туннель перестал отвечать"}
				}
				continue
			}
			bad = 0
			if c != colo {
				Logf("   дата-центр сменился: %s → %s", colo, c)
				colo = c
				if !e.policy().Allows(c) {
					e.cfg.Mem.Record(nk, s.ID, false, 0)
					e.emit("colo_blocked", s.ID, c)
					Logf("✘ дата-центр %s запрещён — меняю стратегию", c)
					return outcome{wasUp: true, coloBlocked: c, reason: "дата-центр " + c + " запрещён"}
				}
			}
			e.setStatus(Status{State: "up", Strategy: s.ID, Colo: colo, RTT: r, Message: e.Status().Message})
		}
	}
}

// Run — главный цикл: подключиться, следить, при сбое перейти на другую стратегию.
func (e *Engine) Run(ctx context.Context) error {
	defer e.Close()
	go e.readTun()
	Logf("Гидра запущена: стратегий %d, запрещённые дата-центры: %s", len(e.cfg.Strategies), policyText(e.cfg.Policy))

	backoff := time.Second
	skip := ""
	lastNK := ""
	blocked := map[string]time.Time{}
	for ctx.Err() == nil {
		select {
		case <-e.tunDead:
			return errors.New("TUN закрыт")
		default:
		}
		nk := e.cfg.NetKey()
		if nk != lastNK {
			if lastNK != "" {
				Logf("↻ сеть: %s → %s", lastNK, nk)
			} else {
				Logf("сеть: %s", nk)
			}
			lastNK = nk
			blocked = map[string]time.Time{}
			e.soft = false
			skip = ""
		}
		cands := e.cfg.Mem.Rank(nk, e.cfg.Strategies)
		ran, skipped := 0, 0
		lastReason := ""
		sawBlocked := false
		restart := false
		for _, s := range cands {
			if ctx.Err() != nil {
				break
			}
			if s.ID == skip {
				continue
			}
			ep := s.Params["endpoint"]
			if until, ok := blocked[ep]; ep != "" && ok && time.Now().Before(until) {
				skipped++
				continue
			}
			ran++
			r := e.runStrategy(ctx, nk, s)
			if ctx.Err() != nil {
				break
			}
			lastReason = r.reason
			if r.coloBlocked != "" {
				sawBlocked = true
				if ep != "" {
					blocked[ep] = time.Now().Add(10 * time.Minute)
					Logf("   адрес %s ведёт в запрещённый %s — остальные стратегии с ним пропускаю на 10 минут", ep, r.coloBlocked)
				}
			}
			if r.netChanged {
				skip = ""
				restart = true
				break
			}
			if r.wasUp {
				skip = s.ID
				e.setStatus(Status{State: "reconnecting", Message: r.reason})
				backoff = time.Second
				restart = true
				break
			}
		}
		if ctx.Err() != nil {
			break
		}
		if restart {
			continue
		}
		if sawBlocked && e.cfg.SoftFallback && !e.soft {
			e.soft = true
			blocked = map[string]time.Time{}
			Logf("⚠ все рабочие адреса ведут в запрещённые дата-центры; включён режим «всё равно» — принимаю любой")
			continue
		}
		skip = ""
		msg := lastReason
		switch {
		case ran == 0 && skipped > 0:
			msg = "все адреса сейчас ведут в запрещённые дата-центры — жду"
		case ran == 0:
			msg = "нет стратегий"
		case sawBlocked:
			msg = "рабочие маршруты ведут только в запрещённые дата-центры"
		}
		Logf("✘ подключиться не удалось: %s; повтор через %s", msg, backoff)
		e.setStatus(Status{State: "failed", Message: msg})
		e.emit("failed", "", msg)
		if !sleep(ctx, backoff) {
			break
		}
		if backoff < 30*time.Second {
			backoff *= 2
		}
	}
	return ctx.Err()
}
HYDRA_EOF

putv "$GODIR/engine_test.go" <<'HYDRA_EOF'
package hydra

import (
	"context"
	"io"
	"net"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

type fakeTun struct {
	rd   chan []byte
	wr   chan []byte
	done chan struct{}
	once sync.Once
}

func newFakeTun() *fakeTun {
	return &fakeTun{rd: make(chan []byte, 16), wr: make(chan []byte, 64), done: make(chan struct{})}
}
func (f *fakeTun) Read(p []byte) (int, error) {
	select {
	case b := <-f.rd:
		return copy(p, b), nil
	case <-f.done:
		return 0, io.EOF
	}
}
func (f *fakeTun) Write(p []byte) (int, error) {
	select {
	case f.wr <- append([]byte(nil), p...):
	default:
	}
	return len(p), nil
}
func (f *fakeTun) Close() error { f.once.Do(func() { close(f.done) }); return nil }

// fakeRunner изображает туннель: отвечает на пробы кодом дата-центра из
// параметров стратегии; "dieAfter" — через сколько мс перестать отвечать;
// "dead" — не отвечать вовсе.
func fakeRunner(started *int32) Runner {
	return func(ctx context.Context, dev PacketDevice, s Strategy) error {
		atomic.AddInt32(started, 1)
		t0 := time.Now()
		buf := make([]byte, 2048)
		for {
			n, err := dev.ReadPacket(buf)
			if err != nil {
				return nil
			}
			if s.Params["dead"] == "1" {
				continue
			}
			if d := s.Params["dieAfter"]; d != "" {
				ms := 0
				for _, c := range d {
					ms = ms*10 + int(c-'0')
				}
				if time.Since(t0) > time.Duration(ms)*time.Millisecond {
					continue
				}
			}
			switch buf[9] {
			case 17: // UDP — проба дата-центра
				dev.WritePacket(buildColoReply(append([]byte(nil), buf[:n]...), s.Params["colo"]))
			case 6: // TCP — проба SYN (RST и прочее игнорируем)
				if s.Params["notcp"] != "1" && buf[ihlOf(buf)+13] == 0x02 {
					dev.WritePacket(buildSynAck(append([]byte(nil), buf[:n]...)))
				}
			}
		}
	}
}

func ihlOf(b []byte) int { return int(b[0]&0x0f) * 4 }

func testEngine(t *testing.T, ss []Strategy, policy *ColoPolicy, tcpCheck bool) (*Engine, context.CancelFunc, *int32) {
	var started int32
	cfg := DefaultEngineConfig()
	cfg.LocalIP = net.ParseIP("172.16.0.2")
	cfg.Strategies = ss
	cfg.Runner = fakeRunner(&started)
	cfg.Policy = policy
	cfg.ProbeEvery = 40 * time.Millisecond
	cfg.UpTimeout = 600 * time.Millisecond
	cfg.BadProbes = 2
	cfg.TCPCheck = tcpCheck
	cfg.TCPTimeout = 150 * time.Millisecond
	e := NewEngine(newFakeTun(), cfg)
	ctx, cancel := context.WithCancel(context.Background())
	go e.Run(ctx)
	return e, cancel, &started
}

func waitStatus(t *testing.T, e *Engine, what string, ok func(Status) bool) Status {
	t.Helper()
	deadline := time.Now().Add(6 * time.Second)
	for time.Now().Before(deadline) {
		if st := e.Status(); ok(st) {
			return st
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("не дождались: %s; статус %+v", what, e.Status())
	return Status{}
}

func TestEngineSkipsBlockedColo(t *testing.T) {
	ss := []Strategy{
		{ID: "moscow", Transport: "masque", Params: map[string]string{"colo": "DME"}},
		{ID: "helsinki", Transport: "masque", Params: map[string]string{"colo": "HEL"}},
	}
	e, cancel, _ := testEngine(t, ss, DefaultColoPolicy(), false)
	defer cancel()
	st := waitStatus(t, e, "up через HEL", func(s Status) bool { return s.State == "up" && s.Colo == "HEL" })
	if st.Strategy != "helsinki" {
		t.Fatalf("ждали стратегию helsinki, получили %q", st.Strategy)
	}
}

func TestEngineFailsOverWhenTunnelDies(t *testing.T) {
	ss := []Strategy{
		{ID: "a", Transport: "masque", Params: map[string]string{"colo": "HEL", "dieAfter": "250"}},
		{ID: "b", Transport: "masque", Params: map[string]string{"colo": "FRA"}},
	}
	e, cancel, started := testEngine(t, ss, DefaultColoPolicy(), false)
	defer cancel()
	waitStatus(t, e, "up через a", func(s Status) bool { return s.State == "up" && s.Strategy == "a" })
	st := waitStatus(t, e, "переход на b", func(s Status) bool { return s.State == "up" && s.Strategy == "b" })
	if st.Colo != "FRA" || atomic.LoadInt32(started) < 2 {
		t.Fatalf("неверное состояние после сбоя: %+v", st)
	}
}

func TestEngineReportsFailureWhenEverythingBlocked(t *testing.T) {
	ss := []Strategy{
		{ID: "a", Transport: "masque", Params: map[string]string{"colo": "DME"}},
		{ID: "b", Transport: "masque", Params: map[string]string{"dead": "1"}},
	}
	e, cancel, _ := testEngine(t, ss, DefaultColoPolicy(), false)
	defer cancel()
	waitStatus(t, e, "state=failed", func(s Status) bool { return s.State == "failed" })
}

func TestEngineRequiresRealTCP(t *testing.T) {
	ss := []Strategy{
		{ID: "udp-only", Transport: "masque", Params: map[string]string{"colo": "HEL", "notcp": "1"}},
		{ID: "full", Transport: "masque", Params: map[string]string{"colo": "FRA"}},
	}
	e, cancel, _ := testEngine(t, ss, DefaultColoPolicy(), true)
	defer cancel()
	st := waitStatus(t, e, "up через full", func(s Status) bool { return s.State == "up" && s.Strategy == "full" })
	if st.Colo != "FRA" {
		t.Fatalf("неверный дата-центр: %+v", st)
	}
}

func TestEngineReactsToNetworkChange(t *testing.T) {
	ss := []Strategy{
		{ID: "a", Transport: "masque", Params: map[string]string{"colo": "HEL"}},
		{ID: "b", Transport: "masque", Params: map[string]string{"colo": "FRA"}},
	}
	var started int32
	cfg := DefaultEngineConfig()
	cfg.LocalIP = net.ParseIP("172.16.0.2")
	cfg.Strategies = ss
	cfg.Runner = fakeRunner(&started)
	cfg.Policy = DefaultColoPolicy()
	cfg.ProbeEvery = time.Hour // сам не заметит — только по сигналу
	cfg.UpTimeout = 600 * time.Millisecond
	cfg.TCPCheck = false
	changed := make(chan struct{}, 1)
	cfg.NetChanged = changed
	e := NewEngine(newFakeTun(), cfg)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go e.Run(ctx)

	waitStatus(t, e, "up", func(s Status) bool { return s.State == "up" })
	before := atomic.LoadInt32(&started)
	changed <- struct{}{}
	deadline := time.Now().Add(3 * time.Second)
	for atomic.LoadInt32(&started) <= before && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if atomic.LoadInt32(&started) <= before {
		t.Fatal("после смены сети переподключения не произошло")
	}
}
HYDRA_EOF

putv "$GODIR/journal.go" <<'HYDRA_EOF'
package hydra

import (
	"fmt"
	"strings"
	"sync"
	"time"
)

// Журнал Гидры: подробно и по-русски, что происходит и почему.
// Показывается в приложении (вкладка «Проверка»).

type journalBuf struct {
	mu    sync.Mutex
	lines []string
	max   int
}

var jr = &journalBuf{max: 1200}

// Logf добавляет строку в журнал.
func Logf(format string, a ...any) {
	line := time.Now().Format("15:04:05.000") + "  " + fmt.Sprintf(format, a...)
	jr.mu.Lock()
	jr.lines = append(jr.lines, line)
	if len(jr.lines) > jr.max {
		jr.lines = append([]string(nil), jr.lines[len(jr.lines)-jr.max:]...)
	}
	jr.mu.Unlock()
}

// JournalText возвращает последние n строк (0 — все), новые в конце.
func JournalText(n int) string {
	jr.mu.Lock()
	defer jr.mu.Unlock()
	ls := jr.lines
	if n > 0 && len(ls) > n {
		ls = ls[len(ls)-n:]
	}
	return strings.Join(ls, "\n")
}

func JournalClear() {
	jr.mu.Lock()
	jr.lines = nil
	jr.mu.Unlock()
}

// JournalWriter — io.Writer для стандартного log: строки клиента MASQUE
// (usque) тоже попадут в журнал.
type JournalWriter struct{}

func (JournalWriter) Write(p []byte) (int, error) {
	for _, l := range strings.Split(strings.TrimRight(string(p), "\r\n"), "\n") {
		if l = strings.TrimSpace(l); l != "" {
			Logf("· %s", l)
		}
	}
	return len(p), nil
}
HYDRA_EOF

putv "$GODIR/masque_runner.go" <<'HYDRA_EOF'
//go:build usque

package hydra

import (
	"context"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/pem"
	"errors"
	"fmt"
	"math/big"
	"net"
	"strings"
	"time"

	"github.com/inipew/usque/api"
	"github.com/inipew/usque/masque"
)

// Этот файл собирается только с тегом usque: он подтягивает клиент MASQUE из
// проекта usque (MIT, автор Diniboy1123). Без тега ядро и тесты не требуют
// сетевых зависимостей.

func parsePeerKey(s string) (*ecdsa.PublicKey, error) {
	s = strings.TrimSpace(s)
	var der []byte
	if blk, _ := pem.Decode([]byte(s)); blk != nil {
		der = blk.Bytes
	} else {
		var err error
		if der, err = base64.StdEncoding.DecodeString(s); err != nil {
			return nil, fmt.Errorf("ключ сервера: %w", err)
		}
	}
	pub, err := x509.ParsePKIXPublicKey(der)
	if err != nil {
		return nil, fmt.Errorf("ключ сервера: %w", err)
	}
	ec, ok := pub.(*ecdsa.PublicKey)
	if !ok {
		return nil, errors.New("ключ сервера не ECDSA")
	}
	return ec, nil
}

func selfSignedCert(priv *ecdsa.PrivateKey) ([]byte, error) {
	serial, err := rand.Int(rand.Reader, big.NewInt(1<<62))
	if err != nil {
		return nil, err
	}
	now := time.Now()
	tpl := &x509.Certificate{
		SerialNumber: serial.Add(serial, big.NewInt(1)),
		Subject:      pkix.Name{CommonName: "hydra"},
		NotBefore:    now.Add(-time.Hour),
		NotAfter:     now.Add(24 * time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth},
	}
	return x509.CreateCertificate(rand.Reader, tpl, tpl, &priv.PublicKey, priv)
}

// NewMasqueRunner создаёт Runner, который держит туннель WARP средствами usque.
func NewMasqueRunner(acc *Account) (Runner, error) {
	keyDER, err := base64.StdEncoding.DecodeString(acc.PrivateKey)
	if err != nil {
		return nil, fmt.Errorf("ключ аккаунта: %w", err)
	}
	priv, err := x509.ParseECPrivateKey(keyDER)
	if err != nil {
		return nil, fmt.Errorf("ключ аккаунта: %w", err)
	}
	peer, err := parsePeerKey(acc.PeerPublicKey)
	if err != nil {
		return nil, err
	}
	return func(ctx context.Context, dev PacketDevice, s Strategy) error {
		cert, err := selfSignedCert(priv)
		if err != nil {
			return err
		}
		sni := s.Params["sni"]
		if sni == "" {
			sni = defaultMasqueSNI
		}
		tlsCfg, err := masque.PrepareTlsConfig(priv, peer, [][]byte{cert}, sni, true)
		if err != nil {
			return err
		}
		host, portStr, err := net.SplitHostPort(s.Params["endpoint"])
		if err != nil {
			return err
		}
		port := 443
		fmt.Sscanf(portStr, "%d", &port)
		ip := net.ParseIP(host)
		if ip == nil {
			return errors.New("адрес сервера не IP: " + host)
		}
		h2 := s.Params["h2"] == "1"
		var ep net.Addr = &net.UDPAddr{IP: ip, Port: port}
		if h2 {
			ep = &net.TCPAddr{IP: ip, Port: port}
		} else if fsni := s.Params["fake"]; fsni != "" {
			// фейковые QUIC-пакеты с малым TTL перед рукопожатием (как у Zarp)
			var fk FakeSpec
			fk.TTL = atoiDefault(s.Params["fttl"], 5)
			for i := 0; i < atoiDefault(s.Params["fcount"], 6); i++ {
				if p, err := BuildFakeQUICInitial(fsni, 1357); err == nil {
					fk.Payloads = append(fk.Payloads, p)
				}
			}
			if len(fk.Payloads) > 0 {
				relay, err := StartUDPRelay(&net.UDPAddr{IP: ip, Port: port}, fk)
				if err != nil {
					return err
				}
				defer relay.Close()
				ep = relay.Addr()
			}
		}
		Logf("   запускаю клиент MASQUE (usque)…")
		api.MaintainTunnel(ctx, api.MaintainTunnelConfig{
			TLSConfig:         tlsCfg,
			KeepalivePeriod:   30 * time.Second,
			InitialPacketSize: 1242,
			Endpoint:          ep,
			Device:            dev,
			MTU:               1280,
			ReconnectDelay:    time.Second,
			AlwaysReconnect:   true,
			UseHTTP2:          h2,
		})
		return ctx.Err()
	}, nil
}
HYDRA_EOF

putv "$GODIR/mobile/mobile.go" <<'HYDRA_EOF'
// Package mobile — тонкая обвязка для gomobile: то, что видно из Kotlin.
// Только простые типы (строки), чтобы привязка собиралась без сюрпризов.
package mobile

import (
	"context"
	"errors"
	"fmt"
	"log"
	"path/filepath"
	"strings"
	"time"

	hydra "hydra/core"
)

const version = "0.4.0"

// Version проверяет, что Go-ядро собрано и вызывается из Android.
func Version() string {
	cfg := hydra.DefaultConfig()
	return fmt.Sprintf("hydra-core %s (probe %s)", version, cfg.ProbeEvery)
}

// DefaultBlockedColos — запрещённые по умолчанию дата-центры ("DME,LED,...").
func DefaultBlockedColos() string {
	return strings.Join(hydra.DefaultColoPolicy().Block, ",")
}

// NormalizeColos приводит ввод пользователя к виду "DME,LED,FRA".
func NormalizeColos(s string) string {
	return strings.Join(hydra.ParseColoList(s), ",")
}

func init() {
	// Без этого Go на Android не умеет разрешать имена (нет resolv.conf).
	hydra.SetSystemDNS(nil)
	// Строки клиента MASQUE (usque) тоже попадают в журнал приложения.
	log.SetFlags(0)
	log.SetOutput(hydra.JournalWriter{})
}

// GetJournal возвращает последние n строк журнала (0 — все), новые в конце.
func GetJournal(n int) string { return hydra.JournalText(n) }

// ClearJournal очищает журнал.
func ClearJournal() { hydra.JournalClear() }

// SetDNS принимает DNS-серверы текущей сети от Android ("ip1,ip2,...").
func SetDNS(csv string) {
	hydra.SetSystemDNS(strings.Split(csv, ","))
}

func accountPath(dir string) string { return filepath.Join(dir, "account.json") }

// AccountID возвращает ID сохранённого аккаунта или "".
func AccountID(dir string) string {
	a, err := hydra.LoadAccount(accountPath(dir))
	if err != nil || a == nil {
		return ""
	}
	return a.ID
}

// RegisterReport регистрирует аккаунт WARP (если его ещё нет). Первая строка
// отчёта: "OK" или "FAIL <вид>", вид: rate_limited | blocked | api | storage.
func RegisterReport(dir string) string {
	path := accountPath(dir)
	if a, err := hydra.LoadAccount(path); err == nil && a != nil {
		return "OK\nаккаунт уже есть: " + a.ID
	}
	var sb strings.Builder
	r := hydra.NewRegistrar()
	r.Log = func(s string) {
		sb.WriteString(s + "\n")
		hydra.Logf("регистрация: %s", s)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()

	acc, err := r.Register(ctx)
	if err != nil {
		kind := "blocked"
		var re *hydra.RegError
		if errors.As(err, &re) {
			kind = re.Kind
		}
		return fmt.Sprintf("FAIL %s\n%s%v", kind, sb.String(), err)
	}
	if err := acc.Save(path); err != nil {
		return "FAIL storage\n" + err.Error()
	}
	return "OK\n" + sb.String() + "id: " + acc.ID
}

// ExportAccount возвращает строку для переноса аккаунта или "".
func ExportAccount(dir string) string {
	a, err := hydra.LoadAccount(accountPath(dir))
	if err != nil || a == nil {
		return ""
	}
	return a.Export()
}

// ImportAccount сохраняет аккаунт из строки; пустой ответ — успех.
func ImportAccount(dir, text string) string {
	a, err := hydra.ImportAccount(text)
	if err != nil {
		return err.Error()
	}
	if err := a.Save(accountPath(dir)); err != nil {
		return err.Error()
	}
	return ""
}

func stripMask(a string) string { return strings.TrimSpace(strings.Split(a, "/")[0]) }

// AccountAddr4 — IPv4-адрес устройства внутри туннеля ("" если аккаунта нет).
func AccountAddr4(dir string) string {
	a, err := hydra.LoadAccount(accountPath(dir))
	if err != nil || a == nil {
		return ""
	}
	return stripMask(a.AddrV4)
}

// AccountAddr6 — IPv6-адрес устройства внутри туннеля.
func AccountAddr6(dir string) string {
	a, err := hydra.LoadAccount(accountPath(dir))
	if err != nil || a == nil {
		return ""
	}
	return stripMask(a.AddrV6)
}
HYDRA_EOF

putv "$GODIR/mobile/policy.go" <<'HYDRA_EOF'
package mobile

import (
	"strings"
	"sync"

	hydra "hydra/core"
)

var (
	polMu    sync.Mutex
	polBlock = ""
	polAllow = ""
	polSoft  = false
	netKey   = "default"
	// netEvents — «сеть сменилась»: движок реагирует сразу, не ожидая очередной пробы.
	netEvents = make(chan struct{}, 1)
)

// SetColoPolicy задаёт запрещённые и (необязательно) единственно разрешённые
// дата-центры Cloudflare: "DME,LED" и "HEL,FRA".
func SetColoPolicy(block, allow string) {
	polMu.Lock()
	polBlock, polAllow = block, allow
	polMu.Unlock()
}

// SetFallback: если все адреса ведут в запрещённый дата-центр — всё равно подключиться.
func SetFallback(on bool) {
	polMu.Lock()
	polSoft = on
	polMu.Unlock()
}

// SetNetKey сообщает ядру, в какой сети телефон ("wifi", "cell"). Смена ключа
// сразу будит движок.
func SetNetKey(k string) {
	k = strings.TrimSpace(k)
	polMu.Lock()
	changed := k != netKey
	netKey = k
	polMu.Unlock()
	if changed {
		select {
		case netEvents <- struct{}{}:
		default:
		}
	}
}

func currentNetKey() string {
	polMu.Lock()
	defer polMu.Unlock()
	return netKey
}

func currentFallback() bool {
	polMu.Lock()
	defer polMu.Unlock()
	return polSoft
}

func currentPolicy() *hydra.ColoPolicy {
	polMu.Lock()
	defer polMu.Unlock()
	return &hydra.ColoPolicy{Block: hydra.ParseColoList(polBlock), Allow: hydra.ParseColoList(polAllow)}
}
HYDRA_EOF

putv "$GODIR/mobile/vpn_stub.go" <<'HYDRA_EOF'
//go:build !usque

package mobile

// Сборка без клиента MASQUE (без тега usque): подключение недоступно.

func StartTunnel(dir string, tunFd int) string {
	return "сборка без движка MASQUE (нет тега usque)"
}

func StopTunnel() {}

func EngineStatus() string { return "off||||" }
HYDRA_EOF

putv "$GODIR/mobile/vpn_usque.go" <<'HYDRA_EOF'
//go:build usque

package mobile

import (
	"context"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"

	hydra "hydra/core"
)

var (
	vpnMu     sync.Mutex
	vpnEngine *hydra.Engine
	vpnCancel context.CancelFunc
)

// StartTunnel запускает Гидру на TUN-интерфейсе, который создал Android (tunFd).
// Пустая строка — успех, иначе текст ошибки.
func StartTunnel(dir string, tunFd int) string {
	vpnMu.Lock()
	defer vpnMu.Unlock()
	if vpnEngine != nil {
		return "уже запущено"
	}
	acc, err := hydra.LoadAccount(accountPath(dir))
	if err != nil || acc == nil {
		return "нет аккаунта WARP"
	}
	runner, err := hydra.NewMasqueRunner(acc)
	if err != nil {
		return err.Error()
	}
	ip := net.ParseIP(strings.Split(acc.AddrV4, "/")[0])
	if ip == nil {
		return "в аккаунте нет IPv4-адреса"
	}
	mem, _ := hydra.LoadMemory(filepath.Join(dir, "memory.json"))

	cfg := hydra.DefaultEngineConfig()
	cfg.LocalIP = ip
	cfg.Strategies = hydra.MasqueStrategies(acc)
	cfg.Runner = runner
	cfg.Policy = currentPolicy()
	cfg.Mem = mem
	cfg.NetKey = currentNetKey
	cfg.NetChanged = netEvents
	cfg.SoftFallback = currentFallback()

	e := hydra.NewEngine(os.NewFile(uintptr(tunFd), "tun"), cfg)
	ctx, cancel := context.WithCancel(context.Background())
	vpnEngine, vpnCancel = e, cancel
	go func() {
		e.Run(ctx)
		mem.Save()
		vpnMu.Lock()
		if vpnEngine == e {
			vpnEngine, vpnCancel = nil, nil
		}
		vpnMu.Unlock()
	}()
	return ""
}

// StopTunnel останавливает Гидру и закрывает TUN.
func StopTunnel() {
	vpnMu.Lock()
	c, e := vpnCancel, vpnEngine
	vpnMu.Unlock()
	if c != nil {
		c()
	}
	if e != nil {
		e.Close()
	}
}

// EngineStatus: "состояние|стратегия|дата-центр|задержка_мс|сообщение".
// Состояния: off, connecting, up, reconnecting, failed.
func EngineStatus() string {
	vpnMu.Lock()
	e := vpnEngine
	vpnMu.Unlock()
	if e == nil {
		return "off||||"
	}
	st := e.Status()
	return fmt.Sprintf("%s|%s|%s|%d|%s", st.State, st.Strategy, st.Colo,
		st.RTT.Milliseconds(), strings.ReplaceAll(st.Message, "|", "/"))
}
HYDRA_EOF

putv "$GODIR/orchestrator.go" <<'HYDRA_EOF'
package hydra

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"
)

type Config struct {
	Stagger       time.Duration // пауза между стартами кандидатов в гонке
	DialTimeout   time.Duration
	ProbeEvery    time.Duration
	BadProbes     int     // сколько плохих проб подряд = деградация
	MaxRTTFactor  float64 // во сколько раз RTT может вырасти от базового
	MaxLoss       float64
	StandbyWait   time.Duration // сколько ждать резерв при сбое
	Colo          *ColoPolicy   // политика дата-центров (nil — без ограничений)
}

func DefaultConfig() Config {
	return Config{
		Stagger:      300 * time.Millisecond,
		DialTimeout:  10 * time.Second,
		ProbeEvery:   5 * time.Second,
		BadProbes:    3,
		MaxRTTFactor: 3,
		MaxLoss:      0.2,
		StandbyWait:  2 * time.Second,
		Colo:         DefaultColoPolicy(),
	}
}

var errNoStrategies = errors.New("нет доступных стратегий")

type Orchestrator struct {
	cfg    Config
	mem    *Memory
	ts     map[string]Transport
	order  []Transport
	diag   Diagnoser
	events chan Event
	front  *Front
}

func New(cfg Config, mem *Memory, ts []Transport, d Diagnoser) *Orchestrator {
	if d == nil {
		d = nopDiagnoser{}
	}
	o := &Orchestrator{cfg: cfg, mem: mem, ts: map[string]Transport{}, order: ts, diag: d,
		events: make(chan Event, 64), front: NewFront()}
	for _, t := range ts {
		o.ts[t.Name()] = t
	}
	return o
}

func (o *Orchestrator) Events() <-chan Event { return o.events }

// Front — постоянный локальный SOCKS5-вход; туннель под ним меняется на лету.
func (o *Orchestrator) Front() *Front { return o.front }

func (o *Orchestrator) emit(kind, strategy string, c Cause, msg string) {
	select {
	case o.events <- Event{Kind: kind, Strategy: strategy, Cause: c, Msg: msg, At: time.Now()}:
	default: // UI не успевает — не блокируем ядро
	}
}

func (o *Orchestrator) candidates(net, skip string) []Strategy {
	var all []Strategy
	for _, t := range o.order {
		for _, s := range t.Strategies() {
			if s.ID != skip {
				all = append(all, s)
			}
		}
	}
	return o.mem.Rank(net, all)
}

type dialRes struct {
	t    Tunnel
	s    Strategy
	d    time.Duration
	err  error
	colo string
}

func drain(res <-chan dialRes, n int) {
	for i := 0; i < n; i++ {
		if r := <-res; r.err == nil && r.t != nil {
			r.t.Close()
		}
	}
}

// checkColo спрашивает у туннеля, через какой дата-центр он идёт, и отбрасывает
// запрещённые политикой. Туннели без ColoReporter пропускаются без проверки.
func (o *Orchestrator) checkColo(ctx context.Context, t Tunnel) (Tunnel, string, error) {
	rep, ok := t.(ColoReporter)
	if !ok || o.cfg.Colo == nil {
		return t, "", nil
	}
	cctx, cancel := context.WithTimeout(ctx, 8*time.Second)
	colo, err := rep.Colo(cctx)
	cancel()
	if err != nil {
		return t, "", nil // не смогли узнать — не блокируем
	}
	if !o.cfg.Colo.Allows(colo) {
		t.Close()
		return nil, colo, &ColoError{Colo: colo}
	}
	return t, colo, nil
}

// race — «гонка стратегий»: кандидаты стартуют по очереди с небольшим
// сдвигом, побеждает первый рабочий, остальные отменяются.
func (o *Orchestrator) race(ctx context.Context, net, skip string) (Tunnel, Strategy, error) {
	cands := o.candidates(net, skip)
	if len(cands) == 0 {
		return nil, Strategy{}, errNoStrategies
	}
	rctx, cancel := context.WithCancel(ctx)
	defer cancel()
	res := make(chan dialRes, len(cands))
	started, finished := 0, 0
	var blockedColos []string
	start := func() {
		s := cands[started]
		started++
		go func() {
			t0 := time.Now()
			dctx, c := context.WithTimeout(rctx, o.cfg.DialTimeout)
			defer c()
			t, err := o.ts[s.Transport].Dial(dctx, s)
			colo := ""
			if err == nil {
				t, colo, err = o.checkColo(rctx, t)
			}
			res <- dialRes{t, s, time.Since(t0), err, colo}
		}()
	}
	timer := time.NewTimer(0)
	defer timer.Stop()
	for {
		select {
		case <-ctx.Done():
			go drain(res, started-finished)
			return nil, Strategy{}, ctx.Err()
		case <-timer.C:
			if started < len(cands) {
				start()
				timer.Reset(o.cfg.Stagger)
			}
		case r := <-res:
			finished++
			if r.err == nil {
				o.mem.Record(net, r.s.ID, true, r.d)
				if r.colo != "" {
					o.emit("colo", r.s.ID, CauseUnknown, r.colo)
				}
				cancel()
				go drain(res, started-finished)
				return r.t, r.s, nil
			}
			if ctx.Err() == nil {
				o.mem.Record(net, r.s.ID, false, r.d)
			}
			var ce *ColoError
			if errors.As(r.err, &ce) {
				blockedColos = append(blockedColos, ce.Colo)
				o.emit("colo_blocked", r.s.ID, CauseUnknown, ce.Colo)
			}
			if finished == len(cands) {
				if len(blockedColos) > 0 {
					return nil, Strategy{}, fmt.Errorf("все %d стратегий не сработали (запрещённые дата-центры: %s)",
						len(cands), strings.Join(blockedColos, ", "))
				}
				return nil, Strategy{}, fmt.Errorf("все %d стратегий не сработали", len(cands))
			}
			if finished == started && started < len(cands) {
				start() // ничего не бежит — не ждём паузу
				timer.Reset(o.cfg.Stagger)
			}
		}
	}
}

// watch следит за качеством. Возвращает причину и флаг «сменилась сеть».
func (o *Orchestrator) watch(ctx context.Context, netKey func() string, net string, t Tunnel) (string, bool) {
	tk := time.NewTicker(o.cfg.ProbeEvery)
	defer tk.Stop()
	var base time.Duration
	bad := 0
	for {
		select {
		case <-ctx.Done():
			return "остановка", false
		case <-t.Done():
			return "туннель закрылся", false
		case <-tk.C:
			if netKey() != net {
				return "сменилась сеть", true
			}
			pctx, c := context.WithTimeout(ctx, o.cfg.ProbeEvery)
			q, err := t.Probe(pctx)
			c()
			degraded := err != nil || q.Loss > o.cfg.MaxLoss ||
				(base > 0 && float64(q.RTT) > float64(base)*o.cfg.MaxRTTFactor)
			if !degraded {
				if base == 0 {
					base = q.RTT
				} else {
					base = (base*9 + q.RTT) / 10
				}
				bad = 0
				continue
			}
			bad++
			if bad >= o.cfg.BadProbes {
				return "качество упало", false
			}
		}
	}
}

type standbyRes struct {
	t   Tunnel
	s   Strategy
	err error
}

type standby struct {
	cancel context.CancelFunc
	ch     chan standbyRes
}

// warm прогревает резервный туннель на другой стратегии.
func (o *Orchestrator) warm(ctx context.Context, net, skip string) *standby {
	cctx, cancel := context.WithCancel(ctx)
	sb := &standby{cancel: cancel, ch: make(chan standbyRes, 1)}
	go func() {
		t, s, err := o.race(cctx, net, skip)
		sb.ch <- standbyRes{t, s, err}
	}()
	return sb
}

func (sb *standby) stop() {
	sb.cancel()
	go func() {
		if r := <-sb.ch; r.err == nil {
			r.t.Close()
		}
	}()
}

// session ведёт активный туннель + резерв; возвращается, когда нужна новая гонка.
func (o *Orchestrator) session(ctx context.Context, netKey func() string, net string, t Tunnel, s Strategy) {
	defer o.front.Set(nil)
	sb := o.warm(ctx, net, s.ID)
	for {
		reason, netChanged := o.watch(ctx, netKey, net, t)
		if ctx.Err() != nil || netChanged {
			t.Close()
			sb.stop()
			return
		}
		o.mem.Record(net, s.ID, false, 0)
		cause := o.diag.Diagnose(ctx)
		o.emit("degraded", s.ID, cause, reason)
		select {
		case r := <-sb.ch:
			if r.err == nil {
				old := t
				t, s = r.t, r.s
				o.front.Set(t)
				old.Close()
				o.emit("failover", s.ID, cause, "переключился на резерв")
				sb = o.warm(ctx, net, s.ID)
				continue
			}
			t.Close()
			return
		case <-time.After(o.cfg.StandbyWait):
			t.Close()
			sb.stop()
			return
		}
	}
}

func sleep(ctx context.Context, d time.Duration) bool {
	select {
	case <-ctx.Done():
		return false
	case <-time.After(d):
		return true
	}
}

// Run — главный цикл Гидры: подключиться, следить, лечить.
func (o *Orchestrator) Run(ctx context.Context, netKey func() string) error {
	backoff := time.Second
	for ctx.Err() == nil {
		net := netKey()
		o.emit("connecting", "", CauseUnknown, net)
		t, s, err := o.race(ctx, net, "")
		if err != nil {
			if ctx.Err() != nil {
				break
			}
			c := o.diag.Diagnose(ctx)
			o.emit("failed", "", c, err.Error())
			if !sleep(ctx, backoff) {
				break
			}
			if backoff < 30*time.Second {
				backoff *= 2
			}
			continue
		}
		backoff = time.Second
		o.front.Set(t)
		o.emit("connected", s.ID, CauseUnknown, "net="+net)
		o.session(ctx, netKey, net, t, s)
		_ = o.mem.Save()
	}
	return ctx.Err()
}
HYDRA_EOF

putv "$GODIR/probe.go" <<'HYDRA_EOF'
package hydra

import (
	"encoding/binary"
	"net"
	"strings"
)

// Проба дата-центра без всякого TCP/IP-стека: сами строим UDP-пакет с DNS-запросом
// «CHAOS TXT id.server» к 1.1.1.1. Резолвер Cloudflare отвечает кодом дата-центра
// (HEL, FRA, DME...). Пакет уходит в туннель, ответ приходит из туннеля — так мы
// заодно измеряем задержку и проверяем, что туннель вообще живой.

var probeDst = net.IPv4(1, 1, 1, 1).To4()

func ipChecksum(h []byte) uint16 {
	var sum uint32
	for i := 0; i+1 < len(h); i += 2 {
		sum += uint32(h[i])<<8 | uint32(h[i+1])
	}
	for sum>>16 != 0 {
		sum = sum&0xffff + sum>>16
	}
	return ^uint16(sum)
}

// BuildColoProbe строит IPv4-пакет с запросом id.server. nil, если src не IPv4.
func BuildColoProbe(src net.IP, srcPort, id uint16) []byte {
	s4 := src.To4()
	if s4 == nil {
		return nil
	}
	dns := []byte{byte(id >> 8), byte(id), 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0}
	dns = append(dns, 2, 'i', 'd', 6, 's', 'e', 'r', 'v', 'e', 'r', 0, 0, 16, 0, 3) // TXT, класс CH
	total := 20 + 8 + len(dns)
	p := make([]byte, total)
	p[0] = 0x45
	binary.BigEndian.PutUint16(p[2:], uint16(total))
	binary.BigEndian.PutUint16(p[4:], id)
	binary.BigEndian.PutUint16(p[6:], 0x4000) // DF
	p[8] = 64
	p[9] = 17
	copy(p[12:16], s4)
	copy(p[16:20], probeDst)
	binary.BigEndian.PutUint16(p[10:], ipChecksum(p[:20]))
	binary.BigEndian.PutUint16(p[20:], srcPort)
	binary.BigEndian.PutUint16(p[22:], 53)
	binary.BigEndian.PutUint16(p[24:], uint16(8+len(dns)))
	// контрольная сумма UDP = 0: для IPv4 это допустимо
	copy(p[28:], dns)
	return p
}

func skipName(b []byte, off int) int {
	for off < len(b) {
		c := int(b[off])
		switch {
		case c == 0:
			return off + 1
		case c&0xC0 == 0xC0:
			return off + 2
		default:
			off += c + 1
		}
	}
	return -1
}

// normProbeColo: из ответа берём код аэропорта (первые три буквы, заглавными).
func normProbeColo(s string) string {
	s = strings.ToUpper(strings.Trim(strings.TrimSpace(s), `"`))
	if len(s) > 3 {
		ok := true
		for _, r := range s[:3] {
			if r < 'A' || r > 'Z' {
				ok = false
			}
		}
		if ok {
			return s[:3]
		}
	}
	return s
}

// ParseColoReply разбирает ответ на пробу, пришедший на порт dstPort.
func ParseColoReply(pkt []byte, dstPort uint16) (id uint16, colo string, ok bool) {
	if len(pkt) < 28 || pkt[0]>>4 != 4 {
		return
	}
	ihl := int(pkt[0]&0x0f) * 4
	if ihl < 20 || len(pkt) < ihl+8+12 || pkt[9] != 17 {
		return
	}
	if !net.IP(pkt[12:16]).Equal(probeDst) {
		return
	}
	udp := pkt[ihl:]
	if binary.BigEndian.Uint16(udp[0:]) != 53 || binary.BigEndian.Uint16(udp[2:]) != dstPort {
		return
	}
	dns := udp[8:]
	if ulen := int(binary.BigEndian.Uint16(udp[4:])); ulen >= 8 && ulen-8 <= len(dns) {
		dns = dns[:ulen-8]
	}
	if len(dns) < 12 || dns[2]&0x80 == 0 || dns[3]&0x0f != 0 {
		return
	}
	id = binary.BigEndian.Uint16(dns[0:])
	qd := int(binary.BigEndian.Uint16(dns[4:]))
	an := int(binary.BigEndian.Uint16(dns[6:]))
	if an < 1 {
		return
	}
	off := 12
	for i := 0; i < qd; i++ {
		off = skipName(dns, off)
		if off < 0 || off+4 > len(dns) {
			return
		}
		off += 4
	}
	off = skipName(dns, off)
	if off < 0 || off+10 > len(dns) {
		return
	}
	typ := binary.BigEndian.Uint16(dns[off:])
	rdlen := int(binary.BigEndian.Uint16(dns[off+8:]))
	off += 10
	if typ != 16 || rdlen < 1 || off+rdlen > len(dns) {
		return
	}
	n := int(dns[off])
	if n+1 > rdlen {
		return
	}
	colo = normProbeColo(string(dns[off+1 : off+1+n]))
	return id, colo, colo != ""
}

// ---------- TCP-проба: проходит ли через туннель настоящий TCP ----------
// Шлём SYN на 1.1.1.1:443 и ждём SYN-ACK: так мы убеждаемся, что туннель не
// просто «подключён», а реально пропускает TCP (а на нём — весь интернет).

func tcpChecksum(src, dst net.IP, seg []byte) uint16 {
	pseudo := make([]byte, 0, 12+len(seg))
	pseudo = append(pseudo, src.To4()...)
	pseudo = append(pseudo, dst.To4()...)
	pseudo = append(pseudo, 0, 6, byte(len(seg)>>8), byte(len(seg)))
	pseudo = append(pseudo, seg...)
	if len(pseudo)%2 == 1 {
		pseudo = append(pseudo, 0)
	}
	var sum uint32
	for i := 0; i+1 < len(pseudo); i += 2 {
		sum += uint32(pseudo[i])<<8 | uint32(pseudo[i+1])
	}
	for sum>>16 != 0 {
		sum = sum&0xffff + sum>>16
	}
	return ^uint16(sum)
}

func buildTCP(src net.IP, sport uint16, seq, ack uint32, flags byte, id uint16, withMSS bool) []byte {
	s4 := src.To4()
	if s4 == nil {
		return nil
	}
	tcpLen := 20
	if withMSS {
		tcpLen = 24
	}
	total := 20 + tcpLen
	p := make([]byte, total)
	p[0] = 0x45
	binary.BigEndian.PutUint16(p[2:], uint16(total))
	binary.BigEndian.PutUint16(p[4:], id)
	binary.BigEndian.PutUint16(p[6:], 0x4000)
	p[8] = 64
	p[9] = 6
	copy(p[12:16], s4)
	copy(p[16:20], probeDst)
	binary.BigEndian.PutUint16(p[10:], ipChecksum(p[:20]))

	t := p[20:]
	binary.BigEndian.PutUint16(t[0:], sport)
	binary.BigEndian.PutUint16(t[2:], 443)
	binary.BigEndian.PutUint32(t[4:], seq)
	binary.BigEndian.PutUint32(t[8:], ack)
	t[12] = byte(tcpLen/4) << 4
	t[13] = flags
	binary.BigEndian.PutUint16(t[14:], 65535)
	if withMSS {
		t[20], t[21], t[22], t[23] = 2, 4, 0x04, 0xD8 // MSS 1240
	}
	binary.BigEndian.PutUint16(t[16:], tcpChecksum(s4, probeDst, t))
	return p
}

// BuildTCPSyn строит SYN к 1.1.1.1:443.
func BuildTCPSyn(src net.IP, sport uint16, seq uint32, id uint16) []byte {
	return buildTCP(src, sport, seq, 0, 0x02, id, true)
}

// BuildTCPRst строит RST — закрыть «полуоткрытое» соединение после пробы.
func BuildTCPRst(src net.IP, sport uint16, seq uint32, id uint16) []byte {
	return buildTCP(src, sport, seq, 0, 0x04, id, false)
}

// ParseTCPSynAck: это SYN-ACK от 1.1.1.1:443 на наш порт с ожидаемым ack?
func ParseTCPSynAck(pkt []byte, dport uint16, wantAck uint32) bool {
	if len(pkt) < 40 || pkt[0]>>4 != 4 || pkt[9] != 6 {
		return false
	}
	ihl := int(pkt[0]&0x0f) * 4
	if ihl < 20 || len(pkt) < ihl+20 || !net.IP(pkt[12:16]).Equal(probeDst) {
		return false
	}
	t := pkt[ihl:]
	if binary.BigEndian.Uint16(t[0:]) != 443 || binary.BigEndian.Uint16(t[2:]) != dport {
		return false
	}
	if t[13]&0x12 != 0x12 { // SYN+ACK
		return false
	}
	return binary.BigEndian.Uint32(t[8:]) == wantAck
}
HYDRA_EOF

putv "$GODIR/probe_test.go" <<'HYDRA_EOF'
package hydra

import (
	"encoding/binary"
	"net"
	"testing"
)

// buildColoReply — «сервер» для тестов: отвечает на пробу кодом дата-центра.
func buildColoReply(probe []byte, colo string) []byte {
	ihl := int(probe[0]&0x0f) * 4
	srcIP := probe[12:16]
	udp := probe[ihl:]
	sport := binary.BigEndian.Uint16(udp[0:])
	q := udp[8:]
	id := binary.BigEndian.Uint16(q[0:])

	dns := []byte{byte(id >> 8), byte(id), 0x81, 0x80, 0, 1, 0, 1, 0, 0, 0, 0}
	dns = append(dns, q[12:]...) // вопрос как есть
	dns = append(dns, 0xC0, 0x0C, 0, 16, 0, 3, 0, 0, 0, 0, 0, byte(len(colo)+1), byte(len(colo)))
	dns = append(dns, colo...)

	total := 20 + 8 + len(dns)
	p := make([]byte, total)
	p[0] = 0x45
	binary.BigEndian.PutUint16(p[2:], uint16(total))
	p[8] = 64
	p[9] = 17
	copy(p[12:16], probeDst)
	copy(p[16:20], srcIP)
	binary.BigEndian.PutUint16(p[10:], ipChecksum(p[:20]))
	binary.BigEndian.PutUint16(p[20:], 53)
	binary.BigEndian.PutUint16(p[22:], sport)
	binary.BigEndian.PutUint16(p[24:], uint16(8+len(dns)))
	copy(p[28:], dns)
	return p
}

func TestProbeRoundTrip(t *testing.T) {
	probe := BuildColoProbe(net.ParseIP("172.16.0.2"), 40000, 7)
	if probe == nil || len(probe) < 40 {
		t.Fatal("проба не построена")
	}
	if ipChecksum(probe[:20]) != 0 {
		t.Fatal("контрольная сумма IP неверна")
	}
	reply := buildColoReply(probe, "HEL")
	id, colo, ok := ParseColoReply(reply, 40000)
	if !ok || id != 7 || colo != "HEL" {
		t.Fatalf("разбор ответа: %v %q %v", id, colo, ok)
	}
	if _, _, ok := ParseColoReply(reply, 40001); ok {
		t.Fatal("ответ на чужой порт должен игнорироваться")
	}
	if _, _, ok := ParseColoReply(probe, 40000); ok {
		t.Fatal("сам запрос не должен приниматься за ответ")
	}
	if BuildColoProbe(net.ParseIP("2001:db8::1"), 1, 1) != nil {
		t.Fatal("для IPv6-адреса пробы нет")
	}
}

func TestNormProbeColo(t *testing.T) {
	for in, want := range map[string]string{"HEL": "HEL", `"ams"`: "AMS", "fra1": "FRA", "DME": "DME"} {
		if got := normProbeColo(in); got != want {
			t.Fatalf("%q -> %q, ждали %q", in, got, want)
		}
	}
}

// buildSynAck — «сервер» для тестов: отвечает SYN-ACK на SYN.
func buildSynAck(syn []byte) []byte {
	ihl := int(syn[0]&0x0f) * 4
	t := syn[ihl:]
	sport := binary.BigEndian.Uint16(t[0:])
	seq := binary.BigEndian.Uint32(t[4:])
	p := make([]byte, 40)
	p[0] = 0x45
	binary.BigEndian.PutUint16(p[2:], 40)
	p[8] = 64
	p[9] = 6
	copy(p[12:16], probeDst)
	copy(p[16:20], syn[12:16])
	binary.BigEndian.PutUint16(p[10:], ipChecksum(p[:20]))
	r := p[20:]
	binary.BigEndian.PutUint16(r[0:], 443)
	binary.BigEndian.PutUint16(r[2:], sport)
	binary.BigEndian.PutUint32(r[4:], 12345)
	binary.BigEndian.PutUint32(r[8:], seq+1)
	r[12] = 5 << 4
	r[13] = 0x12
	binary.BigEndian.PutUint16(r[14:], 65535)
	return p
}

func TestTCPSynRoundTrip(t *testing.T) {
	src := net.ParseIP("172.16.0.2")
	syn := BuildTCPSyn(src, 41000, 1000, 9)
	if syn == nil || ipChecksum(syn[:20]) != 0 {
		t.Fatal("SYN не построен или неверная сумма IP")
	}
	if tcpChecksum(src, probeDst, syn[20:]) != 0 {
		t.Fatal("контрольная сумма TCP неверна")
	}
	rep := buildSynAck(syn)
	if !ParseTCPSynAck(rep, 41000, 1001) {
		t.Fatal("SYN-ACK не распознан")
	}
	if ParseTCPSynAck(rep, 41001, 1001) || ParseTCPSynAck(rep, 41000, 999) {
		t.Fatal("чужой порт или чужой ack не должен приниматься")
	}
	if BuildTCPRst(src, 41000, 1001, 10) == nil {
		t.Fatal("RST не построен")
	}
}
HYDRA_EOF

putv "$GODIR/quicfake.go" <<'HYDRA_EOF'
package hydra

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"errors"
	"io"
	"net"
	"time"
)

// Фейковый QUIC Initial с чужим именем (SNI), например vk.com. Его отправляют
// перед настоящим рукопожатием с малым TTL: оборудование провайдера (DPI)
// видит «разрешённый» сайт и пропускает поток, а до сервера пакет не доходит.
// Реализация следует RFC 9001 (защита Initial-пакетов по версии QUIC v1).

var quicV1Salt = []byte{0x38, 0x76, 0x2c, 0xf7, 0xf5, 0x59, 0x34, 0xb3, 0x4d, 0x17,
	0x9a, 0xe6, 0xa4, 0xc8, 0x0c, 0xad, 0xcc, 0xbb, 0x7f, 0x0a}

func hkdfExtract(salt, ikm []byte) []byte {
	m := hmac.New(sha256.New, salt)
	m.Write(ikm)
	return m.Sum(nil)
}

// hkdfExpandLabel — HKDF-Expand-Label из TLS 1.3 для длины до 32 байт.
func hkdfExpandLabel(secret []byte, label string, length int) []byte {
	full := "tls13 " + label
	info := []byte{byte(length >> 8), byte(length), byte(len(full))}
	info = append(info, full...)
	info = append(info, 0)
	m := hmac.New(sha256.New, secret)
	m.Write(info)
	m.Write([]byte{1})
	return m.Sum(nil)[:length]
}

func initialKeys(dcid []byte) (key, iv, hp []byte) {
	cs := hkdfExpandLabel(hkdfExtract(quicV1Salt, dcid), "client in", 32)
	return hkdfExpandLabel(cs, "quic key", 16), hkdfExpandLabel(cs, "quic iv", 12), hkdfExpandLabel(cs, "quic hp", 16)
}

func quicVarint(n int) []byte {
	switch {
	case n < 64:
		return []byte{byte(n)}
	case n < 16384:
		return []byte{0x40 | byte(n>>8), byte(n)}
	}
	return []byte{0x80 | byte(n>>24), byte(n >> 16), byte(n >> 8), byte(n)}
}

// clientHelloFor получает настоящий ClientHello TLS 1.3 с нужным SNI, дав
// стандартному TLS-клиенту «поговорить» с заглушкой.
func clientHelloFor(sni string) ([]byte, error) {
	a, b := net.Pipe()
	defer a.Close()
	defer b.Close()
	go func() {
		c := tls.Client(a, &tls.Config{
			ServerName:         sni,
			MinVersion:         tls.VersionTLS13,
			NextProtos:         []string{"h3"},
			CurvePreferences:   []tls.CurveID{tls.X25519}, // без гибридного ключа: ClientHello остаётся коротким
			InsecureSkipVerify: true,
		})
		c.Handshake()
	}()
	b.SetReadDeadline(time.Now().Add(2 * time.Second))
	hdr := make([]byte, 5)
	if _, err := io.ReadFull(b, hdr); err != nil {
		return nil, err
	}
	body := make([]byte, int(hdr[3])<<8|int(hdr[4]))
	if _, err := io.ReadFull(b, body); err != nil {
		return nil, err
	}
	return body, nil
}

// BuildFakeQUICInitial строит один UDP-датаграмму-«Initial» длиной size байт.
func BuildFakeQUICInitial(sni string, size int) ([]byte, error) {
	ch, err := clientHelloFor(sni)
	if err != nil {
		return nil, err
	}
	dcid := make([]byte, 8)
	scid := make([]byte, 8)
	rand.Read(dcid)
	rand.Read(scid)
	key, iv, hp := initialKeys(dcid)

	frame := append([]byte{0x06, 0x00}, quicVarint(len(ch))...) // CRYPTO, offset 0
	frame = append(frame, ch...)

	const pnLen, tagLen = 2, 16
	hdrLen := 1 + 4 + 1 + len(dcid) + 1 + len(scid) + 1 + 2 + pnLen
	payloadLen := size - hdrLen - tagLen
	if payloadLen < len(frame) {
		payloadLen = len(frame)
	}
	payload := make([]byte, payloadLen) // нули = PADDING
	copy(payload, frame)

	lengthVal := pnLen + payloadLen + tagLen
	if lengthVal >= 16384 {
		return nil, errors.New("слишком длинный Initial")
	}
	header := []byte{0xC0 | byte(pnLen-1), 0, 0, 0, 1, byte(len(dcid))}
	header = append(header, dcid...)
	header = append(header, byte(len(scid)))
	header = append(header, scid...)
	header = append(header, 0) // длина токена
	header = append(header, 0x40|byte(lengthVal>>8), byte(lengthVal))
	pnOff := len(header)
	header = append(header, 0, 0) // номер пакета 0

	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	nonce := append([]byte(nil), iv...) // номер пакета 0: nonce = iv
	sealed := gcm.Seal(nil, nonce, payload, header)
	pkt := append(append([]byte(nil), header...), sealed...)

	hb, err := aes.NewCipher(hp)
	if err != nil {
		return nil, err
	}
	mask := make([]byte, 16)
	hb.Encrypt(mask, pkt[pnOff+4:pnOff+4+16])
	pkt[0] ^= mask[0] & 0x0f
	pkt[pnOff] ^= mask[1]
	pkt[pnOff+1] ^= mask[2]
	return pkt, nil
}
HYDRA_EOF

putv "$GODIR/quicfake_test.go" <<'HYDRA_EOF'
package hydra

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"testing"
)

func TestFakeQUICInitialDecrypts(t *testing.T) {
	pkt, err := BuildFakeQUICInitial("vk.com", 1357)
	if err != nil {
		t.Fatal(err)
	}
	if len(pkt) != 1357 {
		t.Fatalf("длина %d, ждали 1357 (ClientHello раздулся и фейк не влезает в один пакет)", len(pkt))
	}
	if pkt[0]&0x80 == 0 {
		t.Fatal("ждали длинный заголовок")
	}

	// разбор «как это делает сервер»
	dl := int(pkt[5])
	dcid := pkt[6 : 6+dl]
	off := 6 + dl
	off += 1 + int(pkt[off]) // SCID
	off++                    // длина токена (0)
	length := int(pkt[off]&0x3f)<<8 | int(pkt[off+1])
	off += 2
	pnOff := off

	key, iv, hp := initialKeys(dcid)
	hb, _ := aes.NewCipher(hp)
	mask := make([]byte, 16)
	hb.Encrypt(mask, pkt[pnOff+4:pnOff+4+16])
	first := pkt[0] ^ (mask[0] & 0x0f)
	pnLen := int(first&3) + 1
	hdr := append([]byte(nil), pkt[:pnOff+pnLen]...)
	hdr[0] = first
	for i := 0; i < pnLen; i++ {
		hdr[pnOff+i] ^= mask[1+i]
	}
	block, _ := aes.NewCipher(key)
	gcm, _ := cipher.NewGCM(block)
	plain, err := gcm.Open(nil, iv, pkt[pnOff+pnLen:pnOff+length], hdr)
	if err != nil {
		t.Fatalf("не расшифровывается: %v", err)
	}
	if plain[0] != 0x06 || !bytes.Contains(plain, []byte("vk.com")) {
		t.Fatalf("в CRYPTO-кадре нет ClientHello с vk.com")
	}
}
HYDRA_EOF

putv "$GODIR/register.go" <<'HYDRA_EOF'
package hydra

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

// Регистрация устройства в Cloudflare WARP + привязка ключа MASQUE.
// Протокол повторяет Android-клиент (описание: usque, MIT).
//
// Главная идея Гидры: регистрация — это не один запрос, а «гонка маршрутов».
// Если api.cloudflareclient.com режут (DPI, DNS, блок по SNI), пробуем:
//   direct   — как обычное приложение
//   frag     — ClientHello режется на два TCP-сегмента
//   doh      — имя резолвится через DoH по IP-адресам, мимо системного DNS
//   doh+frag — оба приёма сразу
// и по каждой доступной сети (Wi-Fi, мобильная) отдельно — их передаёт Android.

const (
	apiHost    = "api.cloudflareclient.com"
	apiBaseURL = "https://" + apiHost + "/v0a4471"
)

var apiHeaders = map[string]string{
	"User-Agent":        "WARP for Android",
	"CF-Client-Version": "a-6.35-4471",
	"Content-Type":      "application/json; charset=UTF-8",
}

// ---------- аккаунт ----------

// Account — всё, что нужно для подключения. Хранится на устройстве; можно
// перенести на другое устройство через Export/ImportAccount.
type Account struct {
	ID            string    `json:"id"`
	Token         string    `json:"token"`
	PrivateKey    string    `json:"private_key"` // base64(SEC1 DER), ключ MASQUE (P-256)
	PeerPublicKey string    `json:"peer_public_key"`
	EndpointV4    string    `json:"endpoint_v4"`
	EndpointV6    string    `json:"endpoint_v6"`
	AddrV4        string    `json:"addr_v4"`
	AddrV6        string    `json:"addr_v6"`
	Created       time.Time `json:"created"`
}

const exportPrefix = "hydra1:"

// Export превращает аккаунт в строку, которую удобно скопировать.
func (a *Account) Export() string {
	b, _ := json.Marshal(a)
	return exportPrefix + base64.RawURLEncoding.EncodeToString(b)
}

// ImportAccount разбирает строку из Export.
func ImportAccount(s string) (*Account, error) {
	s = strings.TrimSpace(s)
	if !strings.HasPrefix(s, exportPrefix) {
		return nil, errors.New("это не аккаунт Гидры (нет префикса hydra1:)")
	}
	b, err := base64.RawURLEncoding.DecodeString(strings.TrimPrefix(s, exportPrefix))
	if err != nil {
		return nil, fmt.Errorf("повреждённая строка: %w", err)
	}
	var a Account
	if err := json.Unmarshal(b, &a); err != nil {
		return nil, fmt.Errorf("повреждённые данные: %w", err)
	}
	if a.ID == "" || a.Token == "" || a.PrivateKey == "" {
		return nil, errors.New("в аккаунте не хватает данных")
	}
	return &a, nil
}

// LoadAccount читает аккаунт с диска; если файла нет — (nil, nil).
func LoadAccount(path string) (*Account, error) {
	b, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var a Account
	if err := json.Unmarshal(b, &a); err != nil {
		return nil, err
	}
	return &a, nil
}

func (a *Account) Save(path string) error {
	b, err := json.Marshal(a)
	if err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// EnsureAccount: берёт сохранённый аккаунт или регистрирует новый.
// Повторно не регистрируемся без нужды — у Cloudflare есть лимиты на регистрации.
func EnsureAccount(ctx context.Context, path string, r *Registrar) (*Account, error) {
	if a, err := LoadAccount(path); err == nil && a != nil {
		return a, nil
	}
	a, err := r.Register(ctx)
	if err != nil {
		return nil, err
	}
	if err := a.Save(path); err != nil {
		return nil, err
	}
	return a, nil
}

// ---------- ошибки ----------

const (
	KindRateLimited = "rate_limited" // 429: слишком много регистраций с этого IP
	KindBlocked     = "blocked"      // до API не достучаться (DPI/сеть)
	KindDNS         = "dns"          // имя API не определяется, DoH тоже не помог
	KindAPI         = "api"          // API ответил, но отказал
)

type RegError struct {
	Kind       string
	Detail     []string
	RetryAfter time.Duration
}

func (e *RegError) Error() string {
	return fmt.Sprintf("регистрация WARP не удалась (%s): %s", e.Kind, strings.Join(e.Detail, "; "))
}

type httpError struct {
	Status     int
	RetryAfter time.Duration
	Body       string
}

func (e *httpError) Error() string { return fmt.Sprintf("HTTP %d %s", e.Status, e.Body) }

// protoError — API ответил, но не так, как ждали (формат изменился?).
type protoError struct{ msg string }

func (e *protoError) Error() string { return e.msg }

func classify(errs []error) *RegError {
	re := &RegError{Kind: KindBlocked}
	rate, api, dns := false, false, false
	for _, e := range errs {
		re.Detail = append(re.Detail, e.Error())
		var he *httpError
		var pe *protoError
		switch {
		case errors.As(e, &he):
			if he.Status == http.StatusTooManyRequests {
				rate = true
				if he.RetryAfter > re.RetryAfter {
					re.RetryAfter = he.RetryAfter
				}
			} else {
				api = true
			}
		case errors.As(e, &pe):
			api = true
		case strings.Contains(e.Error(), "lookup "):
			dns = true
		}
	}
	switch {
	case rate:
		re.Kind = KindRateLimited
	case api:
		re.Kind = KindAPI
	case dns:
		re.Kind = KindDNS
	}
	return re
}

// ---------- регистратор ----------

// NamedDialer — способ открыть TCP-соединение. Android передаёт по одному на
// каждую доступную сеть (Wi-Fi, мобильная), привязанному к ней.
type NamedDialer struct {
	Name string
	Dial func(ctx context.Context, network, addr string) (net.Conn, error)
}

type regMethod struct {
	name      string
	doh, frag bool
	sni       string // другое имя в TLS; Host в запросе остаётся настоящим
}

var allMethods = []regMethod{
	{"direct", false, false, ""},
	{"frag", false, true, ""},
	{"doh", true, false, ""},
	{"doh+frag", true, true, ""},
	{"front-speed", true, false, "speed.cloudflare.com"},
	{"front-www", true, true, "www.cloudflare.com"},
}

type route struct {
	name string
	d    NamedDialer
	m    regMethod
}

type Registrar struct {
	Dialers  []NamedDialer // пусто = системная сеть
	Methods  []string      // пусто = все способы
	BaseURL  string        // для тестов; по умолчанию боевой API
	Stagger  time.Duration // пауза между стартами маршрутов
	Timeout  time.Duration // на один маршрут
	Attempts int           // сколько раундов гонки
	Backoff  time.Duration // базовая пауза между раундами (удваивается)
	Log      func(string)
}

func NewRegistrar() *Registrar {
	return &Registrar{
		Stagger:  400 * time.Millisecond,
		Timeout:  15 * time.Second,
		Attempts: 3,
		Backoff:  2 * time.Second,
	}
}

func (r *Registrar) logf(format string, a ...any) {
	if r.Log != nil {
		r.Log(fmt.Sprintf(format, a...))
	}
}

func (r *Registrar) base() string {
	if r.BaseURL != "" {
		return r.BaseURL
	}
	return apiBaseURL
}

func (r *Registrar) routes() []route {
	ds := r.Dialers
	if len(ds) == 0 {
		d := &net.Dialer{Timeout: 8 * time.Second}
		ds = []NamedDialer{{Name: "system", Dial: d.DialContext}}
	}
	var ms []regMethod
	for _, m := range allMethods {
		if len(r.Methods) == 0 {
			ms = append(ms, m)
			continue
		}
		for _, want := range r.Methods {
			if want == m.name {
				ms = append(ms, m)
			}
		}
	}
	var out []route
	for _, m := range ms { // сначала дешёвые способы на всех сетях
		for _, d := range ds {
			out = append(out, route{name: m.name + "@" + d.Name, d: d, m: m})
		}
	}
	return out
}

// Register регистрирует новое устройство, перебирая маршруты и повторяя раунды.
func (r *Registrar) Register(ctx context.Context) (*Account, error) {
	var last error
	for i := 0; i < r.Attempts; i++ {
		acc, err := r.raceOnce(ctx)
		if err == nil {
			return acc, nil
		}
		last = err
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		if i == r.Attempts-1 {
			break
		}
		wait := r.Backoff << uint(i)
		var re *RegError
		if errors.As(err, &re) && re.RetryAfter > wait {
			wait = re.RetryAfter
		}
		r.logf("раунд %d не удался, пауза %s", i+1, wait)
		if !sleep(ctx, wait) {
			return nil, ctx.Err()
		}
	}
	return nil, last
}

type regRes struct {
	acc   *Account
	err   error
	route string
}

func (r *Registrar) raceOnce(ctx context.Context) (*Account, error) {
	routes := r.routes()
	if len(routes) == 0 {
		return nil, errors.New("нет маршрутов для регистрации")
	}
	rctx, cancel := context.WithCancel(ctx)
	defer cancel()
	ch := make(chan regRes, len(routes))
	started, finished := 0, 0
	start := func() {
		rt := routes[started]
		started++
		go func() {
			actx, c := context.WithTimeout(rctx, r.Timeout)
			defer c()
			acc, err := r.attempt(actx, rt)
			ch <- regRes{acc, err, rt.name}
		}()
	}
	timer := time.NewTimer(0)
	defer timer.Stop()
	var errs []error
	for {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-timer.C:
			if started < len(routes) {
				start()
				timer.Reset(r.Stagger)
			}
		case x := <-ch:
			finished++
			if x.err == nil {
				r.logf("✔ %s: регистрация прошла", x.route)
				return x.acc, nil
			}
			r.logf("✘ %s: %v", x.route, x.err)
			errs = append(errs, x.err)
			if finished == len(routes) {
				return nil, classify(errs)
			}
			if finished == started && started < len(routes) {
				start()
				timer.Reset(r.Stagger)
			}
		}
	}
}

// ---------- один маршрут ----------

type regConfig struct {
	Peers []struct {
		PublicKey string `json:"public_key"`
		Endpoint  struct {
			V4   string `json:"v4"`
			V6   string `json:"v6"`
			Host string `json:"host"`
		} `json:"endpoint"`
	} `json:"peers"`
	Interface struct {
		Addresses struct {
			V4 string `json:"v4"`
			V6 string `json:"v6"`
		} `json:"addresses"`
	} `json:"interface"`
}

type regResp struct {
	ID     string     `json:"id"`
	Token  string     `json:"token"`
	Config regConfig  `json:"config"`
	Result *regResp   `json:"result"`
}

// norm: в разных версиях API ответ лежит либо в корне, либо в "result".
func (x *regResp) norm() *regResp {
	if x.Result != nil {
		return x.Result
	}
	return x
}

func randHex(n int) string {
	b := make([]byte, n)
	rand.Read(b)
	return hex.EncodeToString(b)
}

func (r *Registrar) attempt(ctx context.Context, rt route) (*Account, error) {
	cl := r.client(rt)

	wgPub := make([]byte, 32) // как у приложения: «ключ WireGuard», который мы не используем
	rand.Read(wgPub)
	regBody := map[string]any{
		"key":           base64.StdEncoding.EncodeToString(wgPub),
		"install_id":    "",
		"fcm_token":     "",
		"tos":           time.Now().UTC().Format("2006-01-02T15:04:05.000Z"),
		"model":         "Android",
		"serial_number": randHex(8),
		"locale":        "en_US",
		"key_type":      "curve25519",
		"tunnel_type":   "wireguard",
	}
	var reg regResp
	if err := r.do(ctx, cl, "POST", "/reg", "", regBody, &reg); err != nil {
		return nil, err
	}
	rr := reg.norm()
	if rr.ID == "" || rr.Token == "" {
		return nil, &protoError{"пустой ответ API при регистрации"}
	}

	priv, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, err
	}
	pubDER, err := x509.MarshalPKIXPublicKey(&priv.PublicKey)
	if err != nil {
		return nil, err
	}
	privDER, err := x509.MarshalECPrivateKey(priv)
	if err != nil {
		return nil, err
	}
	enroll := map[string]any{
		"key":         base64.StdEncoding.EncodeToString(pubDER),
		"key_type":    "secp256r1",
		"tunnel_type": "masque",
		"name":        "Hydra",
	}
	var en regResp
	if err := r.do(ctx, cl, "PATCH", "/reg/"+rr.ID, rr.Token, enroll, &en); err != nil {
		return nil, err
	}

	cfg := en.norm().Config
	if len(cfg.Peers) == 0 {
		cfg = rr.Config
	}
	acc := &Account{
		ID:         rr.ID,
		Token:      rr.Token,
		PrivateKey: base64.StdEncoding.EncodeToString(privDER),
		AddrV4:     cfg.Interface.Addresses.V4,
		AddrV6:     cfg.Interface.Addresses.V6,
		Created:    time.Now().UTC(),
	}
	if len(cfg.Peers) > 0 {
		acc.PeerPublicKey = cfg.Peers[0].PublicKey
		acc.EndpointV4 = cfg.Peers[0].Endpoint.V4
		acc.EndpointV6 = cfg.Peers[0].Endpoint.V6
	}
	return acc, nil
}

func (r *Registrar) do(ctx context.Context, cl *http.Client, verb, path, token string, body, out any) error {
	b, err := json.Marshal(body)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, verb, r.base()+path, bytes.NewReader(b))
	if err != nil {
		return err
	}
	for k, v := range apiHeaders {
		req.Header.Set(k, v)
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := cl.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		he := &httpError{Status: resp.StatusCode, Body: strings.TrimSpace(truncate(string(data), 160))}
		if ra := resp.Header.Get("Retry-After"); ra != "" {
			if n, err := strconv.Atoi(ra); err == nil {
				he.RetryAfter = time.Duration(n) * time.Second
			}
		}
		return he
	}
	if err := json.Unmarshal(data, out); err != nil {
		return &protoError{"неожиданный ответ API: " + err.Error()}
	}
	return nil
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}

// ---------- сеть: клиент, фрагментация, DoH ----------

func (r *Registrar) client(rt route) *http.Client {
	tr := &http.Transport{
		DisableKeepAlives:     true,
		ForceAttemptHTTP2:     false,
		TLSNextProto:          map[string]func(string, *tls.Conn) http.RoundTripper{},
		DialContext:           rt.d.Dial,
		TLSHandshakeTimeout:   10 * time.Second,
		ResponseHeaderTimeout: 15 * time.Second,
	}
	tr.DialTLSContext = func(ctx context.Context, network, addr string) (net.Conn, error) {
		return r.dialTLS(ctx, rt, addr)
	}
	return &http.Client{Transport: tr}
}

func (r *Registrar) dialTLS(ctx context.Context, rt route, addr string) (net.Conn, error) {
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		return nil, err
	}
	target := addr
	if rt.m.doh {
		ips, err := dohResolve(ctx, rt.d, host)
		if err != nil {
			return nil, err
		}
		target = net.JoinHostPort(ips[0], port)
	}
	raw, err := rt.d.Dial(ctx, "tcp", target)
	if err != nil {
		return nil, err
	}
	var c net.Conn = raw
	if rt.m.frag {
		c = &fragConn{Conn: raw, at: 3, delay: 15 * time.Millisecond}
	}
	name := host
	if rt.m.sni != "" {
		name = rt.m.sni
	}
	tc := tls.Client(c, &tls.Config{
		ServerName: name,
		NextProtos: []string{"http/1.1"},
		MinVersion: tls.VersionTLS12,
	})
	if err := tc.HandshakeContext(ctx); err != nil {
		raw.Close()
		return nil, err
	}
	return tc, nil
}

// fragConn режет первую запись (ClientHello) на два TCP-сегмента: простой DPI,
// который смотрит только на первый пакет, SNI не увидит.
type fragConn struct {
	net.Conn
	at    int
	delay time.Duration
	done  bool
}

func (c *fragConn) Write(b []byte) (int, error) {
	if c.done || len(b) <= c.at {
		return c.Conn.Write(b)
	}
	c.done = true
	n1, err := c.Conn.Write(b[:c.at])
	if err != nil {
		return n1, err
	}
	time.Sleep(c.delay)
	n2, err := c.Conn.Write(b[c.at:])
	return n1 + n2, err
}

// dohResolve узнаёт IP через DoH по IP-адресам серверов (системный DNS не нужен).
func dohResolve(ctx context.Context, d NamedDialer, host string) ([]string, error) {
	urls := []string{
		"https://1.1.1.1/dns-query?name=" + host + "&type=A",
		"https://8.8.8.8/resolve?name=" + host + "&type=A",
	}
	var lastErr error
	for _, u := range urls {
		ips, err := dohQuery(ctx, d, u)
		if err == nil && len(ips) > 0 {
			return ips, nil
		}
		lastErr = err
	}
	if lastErr == nil {
		lastErr = errors.New("пустой ответ")
	}
	return nil, fmt.Errorf("DoH не помог: %w", lastErr)
}

func dohQuery(ctx context.Context, d NamedDialer, u string) ([]string, error) {
	tr := &http.Transport{
		DialContext:         d.Dial,
		DisableKeepAlives:   true,
		TLSHandshakeTimeout: 5 * time.Second,
	}
	cl := &http.Client{Transport: tr, Timeout: 6 * time.Second}
	req, err := http.NewRequestWithContext(ctx, "GET", u, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/dns-json")
	resp, err := cl.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	var out struct {
		Answer []struct {
			Type int    `json:"type"`
			Data string `json:"data"`
		} `json:"Answer"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&out); err != nil {
		return nil, err
	}
	var ips []string
	for _, a := range out.Answer {
		if a.Type == 1 && net.ParseIP(a.Data) != nil {
			ips = append(ips, a.Data)
		}
	}
	return ips, nil
}
HYDRA_EOF

putv "$GODIR/register_test.go" <<'HYDRA_EOF'
package hydra

import (
	"context"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"
)

const fakeReg = `{"id":"abc","token":"tok","config":{"peers":[{"public_key":"PK","endpoint":{"v4":"162.159.198.1:443","v6":"[2606:4700:103::1]:443","host":"engage.cloudflareclient.com:443"}}],"interface":{"addresses":{"v4":"172.16.0.2","v6":"2606:4700:110::2"}}}}`

func TestRegisterRetriesAcrossRoutes(t *testing.T) {
	var posts int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		switch {
		case req.Method == "POST" && req.URL.Path == "/reg":
			if atomic.AddInt32(&posts, 1) == 1 {
				w.Header().Set("Retry-After", "0")
				http.Error(w, "slow down", http.StatusTooManyRequests)
				return
			}
			w.Write([]byte(fakeReg))
		case req.Method == "PATCH" && req.URL.Path == "/reg/abc":
			if req.Header.Get("Authorization") != "Bearer tok" {
				http.Error(w, "no", http.StatusUnauthorized)
				return
			}
			w.Write([]byte(fakeReg))
		default:
			http.NotFound(w, req)
		}
	}))
	defer srv.Close()

	good := (&net.Dialer{Timeout: time.Second}).DialContext
	bad := func(ctx context.Context, network, addr string) (net.Conn, error) {
		return nil, errors.New("сеть недоступна")
	}
	r := NewRegistrar()
	r.BaseURL = srv.URL
	r.Methods = []string{"direct"}
	r.Dialers = []NamedDialer{{Name: "wifi", Dial: bad}, {Name: "cell", Dial: good}}
	r.Stagger = 10 * time.Millisecond
	r.Backoff = 10 * time.Millisecond
	r.Timeout = 2 * time.Second

	var logs []string
	r.Log = func(s string) { logs = append(logs, s) }

	acc, err := r.Register(context.Background())
	if err != nil {
		t.Fatalf("регистрация не удалась: %v (лог: %v)", err, logs)
	}
	if acc.ID != "abc" || acc.Token != "tok" || acc.EndpointV4 != "162.159.198.1:443" || acc.PrivateKey == "" {
		t.Fatalf("неверный аккаунт: %+v", acc)
	}
	if n := atomic.LoadInt32(&posts); n != 2 {
		t.Fatalf("ждали 2 POST (429, потом успех), получили %d", n)
	}
}

func TestRegisterReportsBlocked(t *testing.T) {
	bad := func(ctx context.Context, network, addr string) (net.Conn, error) {
		return nil, errors.New("connection reset")
	}
	r := NewRegistrar()
	r.BaseURL = "http://127.0.0.1:1"
	r.Methods = []string{"direct"}
	r.Dialers = []NamedDialer{{Name: "wifi", Dial: bad}}
	r.Attempts = 2
	r.Stagger = time.Millisecond
	r.Backoff = time.Millisecond
	_, err := r.Register(context.Background())
	var re *RegError
	if !errors.As(err, &re) || re.Kind != KindBlocked {
		t.Fatalf("ждали ошибку вида blocked, получили %v", err)
	}
}

func TestClassifyKinds(t *testing.T) {
	dnsErr := errors.New("dial tcp: lookup api.cloudflareclient.com on [::1]:53: connection refused")
	if k := classify([]error{dnsErr}).Kind; k != KindDNS {
		t.Fatalf("ждали dns, получили %s", k)
	}
	if k := classify([]error{errors.New("connection reset by peer")}).Kind; k != KindBlocked {
		t.Fatalf("ждали blocked, получили %s", k)
	}
	if k := classify([]error{&protoError{"мусор"}}).Kind; k != KindAPI {
		t.Fatalf("ждали api, получили %s", k)
	}
	re := classify([]error{dnsErr, &httpError{Status: 429, RetryAfter: 3 * time.Second}})
	if re.Kind != KindRateLimited || re.RetryAfter != 3*time.Second {
		t.Fatalf("429 должен перекрывать остальное: %+v", re)
	}
}

func TestAccountExportImportAndStorage(t *testing.T) {
	a := &Account{ID: "id1", Token: "tok1", PrivateKey: "AAAA", EndpointV4: "1.2.3.4:443", Created: time.Unix(1700000000, 0).UTC()}
	got, err := ImportAccount(a.Export())
	if err != nil || got.ID != "id1" || got.Token != "tok1" || got.EndpointV4 != "1.2.3.4:443" {
		t.Fatalf("круг экспорт-импорт: %+v %v", got, err)
	}
	if _, err := ImportAccount("мусор"); err == nil {
		t.Fatal("мусор должен отвергаться")
	}
	if _, err := ImportAccount("hydra1:!!!"); err == nil {
		t.Fatal("повреждённая строка должна отвергаться")
	}

	p := filepath.Join(t.TempDir(), "account.json")
	if acc, err := LoadAccount(p); acc != nil || err != nil {
		t.Fatalf("без файла ждали (nil, nil), получили %v %v", acc, err)
	}
	if err := a.Save(p); err != nil {
		t.Fatal(err)
	}
	back, err := LoadAccount(p)
	if err != nil || back == nil || back.ID != "id1" {
		t.Fatalf("загрузка: %+v %v", back, err)
	}
}

func TestEnsureAccountUsesStored(t *testing.T) {
	p := filepath.Join(t.TempDir(), "account.json")
	if err := (&Account{ID: "x", Token: "y", PrivateKey: "z"}).Save(p); err != nil {
		t.Fatal(err)
	}
	r := NewRegistrar()
	r.Dialers = []NamedDialer{{Name: "none", Dial: func(ctx context.Context, network, addr string) (net.Conn, error) {
		return nil, errors.New("сеть не должна использоваться")
	}}}
	got, err := EnsureAccount(context.Background(), p, r)
	if err != nil || got.ID != "x" {
		t.Fatalf("ждали сохранённый аккаунт, получили %+v %v", got, err)
	}
}

func TestFragConnSplitsFirstWrite(t *testing.T) {
	c1, c2 := net.Pipe()
	defer c1.Close()
	defer c2.Close()
	fc := &fragConn{Conn: c1, at: 3}
	go func() {
		fc.Write([]byte("abcdef"))
		fc.Write([]byte("xyz"))
	}()
	buf := make([]byte, 16)
	var parts []string
	for i := 0; i < 3; i++ {
		n, err := c2.Read(buf)
		if err != nil {
			t.Fatal(err)
		}
		parts = append(parts, string(buf[:n]))
	}
	if parts[0] != "abc" || parts[1] != "def" || parts[2] != "xyz" {
		t.Fatalf("части: %v", parts)
	}
}
HYDRA_EOF

putv "$GODIR/strategies.go" <<'HYDRA_EOF'
package hydra

import (
	"fmt"
	"net"
	"strconv"
	"strings"
)

const defaultMasqueSNI = "consumer-masque.cloudflareclient.com"

func hostOnly(ep string) string {
	h, _, err := net.SplitHostPort(ep)
	if err != nil {
		return strings.Trim(ep, "[]")
	}
	return strings.Trim(h, "[]")
}

func atoiDefault(s string, def int) int {
	if n, err := strconv.Atoi(strings.TrimSpace(s)); err == nil {
		return n
	}
	return def
}

type fakeVariant struct {
	alias string
	sni   string
	ttl   int
	count int
}

// Фейковые QUIC-пакеты перед рукопожатием (см. UDPRelay). Первая — та, что у
// Zarp дала мгновенное подключение: «VK, TTL=5, ×6».
var fakeVariants = []fakeVariant{
	{"vk5x6", "vk.com", 5, 6},
	{"vk4x6", "vk.com", 4, 6},
	{"vk6x6", "vk.com", 6, 6},
	{"ya5x6", "ya.ru", 5, 6},
	{"g5x6", "www.google.com", 5, 6},
	{"plain", "", 0, 0},
}

// MasqueStrategies — способы подключиться к WARP по MASQUE: адрес сервера ×
// фейковые пакеты × имя в TLS (SNI) × HTTP/3 (UDP) или HTTP/2 (TCP, если режут QUIC).
// Порядок — «самое вероятное первым»; дальше его уточняет память по сетям.
// Разные группы адресов нужны ещё и чтобы уйти от нежелательного дата-центра:
// у разных префиксов Cloudflare маршруты бывают разные.
func MasqueStrategies(acc *Account) []Strategy {
	var eps []string
	seen := map[string]bool{}
	add := func(h string) {
		h = strings.TrimSpace(h)
		if h == "" || net.ParseIP(h) == nil || seen[h] {
			return
		}
		seen[h] = true
		eps = append(eps, h)
	}
	add("162.159.198.2")
	if acc != nil {
		add(hostOnly(acc.EndpointV4))
	}
	for _, h := range []string{
		"162.159.198.1", "162.159.192.1", "162.159.193.1", "162.159.195.1",
		"188.114.96.1", "188.114.97.1",
		"2606:4700:103::2", "2606:4700:103::1",
	} {
		add(h)
	}

	mk := func(proto, ep, alias, sni string, fv *fakeVariant) Strategy {
		p := map[string]string{
			"endpoint": net.JoinHostPort(ep, "443"),
			"sni":      sni,
			"h2":       "0",
		}
		if proto == "h2" {
			p["h2"] = "1"
		}
		if fv != nil && fv.count > 0 {
			p["fake"] = fv.sni
			p["fttl"] = strconv.Itoa(fv.ttl)
			p["fcount"] = strconv.Itoa(fv.count)
		}
		return Strategy{ID: fmt.Sprintf("%s/%s/%s", proto, ep, alias), Transport: "masque", Params: p}
	}

	var out []Strategy
	for i := range fakeVariants {
		fv := &fakeVariants[i]
		for _, ep := range eps {
			out = append(out, mk("h3", ep, fv.alias, defaultMasqueSNI, fv))
		}
	}
	// другое имя в TLS — только с самыми удачными фейками
	for _, alt := range []struct{ alias, name string }{
		{"speed", "speed.cloudflare.com"},
		{"www", "www.cloudflare.com"},
	} {
		for _, ep := range eps {
			out = append(out, mk("h3", ep, fakeVariants[0].alias+"+"+alt.alias, alt.name, &fakeVariants[0]))
		}
	}
	for _, ep := range eps {
		out = append(out, mk("h2", ep, "std", defaultMasqueSNI, nil))
	}
	return out
}

func describeStrategy(s Strategy) string {
	proto := "HTTP/3 (QUIC)"
	if s.Params["h2"] == "1" {
		proto = "HTTP/2 (TCP)"
	}
	out := fmt.Sprintf("%s → %s, SNI %s", proto, s.Params["endpoint"], s.Params["sni"])
	if f := s.Params["fake"]; f != "" {
		out += fmt.Sprintf(", фейки %s ×%s TTL %s", f, s.Params["fcount"], s.Params["fttl"])
	}
	return out
}
HYDRA_EOF

putv "$GODIR/strategies_test.go" <<'HYDRA_EOF'
package hydra

import "testing"

func TestMasqueStrategies(t *testing.T) {
	acc := &Account{EndpointV4: "162.159.198.3:0"}
	ss := MasqueStrategies(acc)
	if len(ss) < 60 {
		t.Fatalf("мало стратегий: %d", len(ss))
	}
	first := ss[0]
	if first.ID != "h3/162.159.198.2/vk5x6" || first.Params["fake"] != "vk.com" ||
		first.Params["fttl"] != "5" || first.Params["fcount"] != "6" {
		t.Fatalf("первой должна идти проверенная «VK ttl=5 ×6»: %+v", first)
	}
	if ss[1].Params["endpoint"] != "162.159.198.3:443" {
		t.Fatalf("вторым должен идти адрес из аккаунта: %+v", ss[1])
	}
	ids := map[string]bool{}
	sawH2, sawPlain, sawV6 := false, false, false
	for _, s := range ss {
		if ids[s.ID] {
			t.Fatalf("повтор ID %s", s.ID)
		}
		ids[s.ID] = true
		if s.Params["h2"] == "1" {
			sawH2 = true
		}
		if s.Params["fake"] == "" && s.Params["h2"] == "0" {
			sawPlain = true
		}
		if hostOnly(s.Params["endpoint"]) == "2606:4700:103::2" {
			sawV6 = true
		}
	}
	if !sawH2 || !sawPlain || !sawV6 {
		t.Fatalf("не хватает видов стратегий: h2=%v plain=%v v6=%v", sawH2, sawPlain, sawV6)
	}
}
HYDRA_EOF

putv "$GODIR/udprelay.go" <<'HYDRA_EOF'
package hydra

import (
	"net"
	"sync"
	"syscall"
)

// UDPRelay — локальный «переходник» для QUIC. Клиент MASQUE шлёт датаграммы на
// 127.0.0.1, а переходник сам общается с сервером Cloudflare: перед первым
// настоящим пакетом он отправляет фейки с малым TTL (как у Zarp), и только
// потом пропускает рукопожатие. Так обходим DPI, не трогая код клиента MASQUE.

// FakeSpec описывает фейковые пакеты: Payloads шлются по очереди с TTL.
type FakeSpec struct {
	Payloads [][]byte
	TTL      int
}

type UDPRelay struct {
	local  *net.UDPConn
	remote *net.UDPAddr
	fake   FakeSpec

	mu    sync.Mutex
	peers map[string]*net.UDPConn
	once  sync.Once
}

func StartUDPRelay(remote *net.UDPAddr, fake FakeSpec) (*UDPRelay, error) {
	local, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		return nil, err
	}
	r := &UDPRelay{local: local, remote: remote, fake: fake, peers: map[string]*net.UDPConn{}}
	go r.loop()
	return r, nil
}

func (r *UDPRelay) Addr() *net.UDPAddr { return r.local.LocalAddr().(*net.UDPAddr) }

func (r *UDPRelay) Close() {
	r.once.Do(func() {
		r.local.Close()
		r.mu.Lock()
		for _, c := range r.peers {
			c.Close()
		}
		r.mu.Unlock()
	})
}

func (r *UDPRelay) loop() {
	buf := make([]byte, 65535)
	for {
		n, from, err := r.local.ReadFromUDP(buf)
		if err != nil {
			return
		}
		if up := r.peer(from); up != nil {
			up.Write(buf[:n])
		}
	}
}

// peer возвращает «свой» сокет к серверу для данного клиента (создаёт и
// отправляет фейки при первом обращении).
func (r *UDPRelay) peer(from *net.UDPAddr) *net.UDPConn {
	key := from.String()
	r.mu.Lock()
	defer r.mu.Unlock()
	if c, ok := r.peers[key]; ok {
		return c
	}
	c, err := net.DialUDP("udp", nil, r.remote)
	if err != nil {
		Logf("   ✘ не удалось открыть сокет к %s: %v", r.remote, err)
		return nil
	}
	r.sendFakes(c)
	r.peers[key] = c
	go func() {
		buf := make([]byte, 65535)
		for {
			n, err := c.Read(buf)
			if err != nil {
				return
			}
			r.local.WriteToUDP(buf[:n], from)
		}
	}()
	return c
}

func (r *UDPRelay) sendFakes(c *net.UDPConn) {
	if len(r.fake.Payloads) == 0 || r.fake.TTL <= 0 {
		return
	}
	if err := setTTL(c, r.fake.TTL); err != nil {
		Logf("   ⚠ не удалось выставить TTL=%d (%v) — фейки не отправляю", r.fake.TTL, err)
		return
	}
	total := 0
	for _, p := range r.fake.Payloads {
		if _, err := c.Write(p); err == nil {
			total += len(p)
		}
	}
	setTTL(c, 64)
	Logf("   фейковых пакетов: %d, %d байт, TTL=%d → %s", len(r.fake.Payloads), total, r.fake.TTL, r.remote)
}

func setTTL(c *net.UDPConn, ttl int) error {
	rc, err := c.SyscallConn()
	if err != nil {
		return err
	}
	v6 := c.RemoteAddr().(*net.UDPAddr).IP.To4() == nil
	var serr error
	err = rc.Control(func(fd uintptr) {
		if v6 {
			serr = syscall.SetsockoptInt(int(fd), syscall.IPPROTO_IPV6, syscall.IPV6_UNICAST_HOPS, ttl)
		} else {
			serr = syscall.SetsockoptInt(int(fd), syscall.IPPROTO_IP, syscall.IP_TTL, ttl)
		}
	})
	if err != nil {
		return err
	}
	return serr
}
HYDRA_EOF

putv "$GODIR/udprelay_test.go" <<'HYDRA_EOF'
package hydra

import (
	"net"
	"testing"
	"time"
)

func TestUDPRelayForwardsAndSendsFakesFirst(t *testing.T) {
	srv, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	defer srv.Close()
	got := make(chan string, 16)
	go func() {
		buf := make([]byte, 2048)
		for {
			n, a, err := srv.ReadFromUDP(buf)
			if err != nil {
				return
			}
			got <- string(buf[:n])
			srv.WriteToUDP([]byte("pong"), a)
		}
	}()

	r, err := StartUDPRelay(srv.LocalAddr().(*net.UDPAddr), FakeSpec{
		Payloads: [][]byte{[]byte("FAKE-A"), []byte("FAKE-B")},
		TTL:      5,
	})
	if err != nil {
		t.Fatal(err)
	}
	defer r.Close()

	c, err := net.DialUDP("udp", nil, r.Addr())
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	c.Write([]byte("REAL-1"))

	for _, want := range []string{"FAKE-A", "FAKE-B", "REAL-1"} {
		select {
		case p := <-got:
			if p != want {
				t.Fatalf("порядок пакетов: ждали %q, пришло %q", want, p)
			}
		case <-time.After(2 * time.Second):
			t.Fatalf("не дождались %q", want)
		}
	}

	// ответ сервера доходит до клиента
	c.SetReadDeadline(time.Now().Add(2 * time.Second))
	buf := make([]byte, 64)
	n, err := c.Read(buf)
	if err != nil || string(buf[:n]) != "pong" {
		t.Fatalf("ответ сервера не дошёл: %q %v", buf[:n], err)
	}

	// второй пакет идёт уже без новых фейков
	c.Write([]byte("REAL-2"))
	select {
	case p := <-got:
		if p != "REAL-2" {
			t.Fatalf("после первого пакета фейков быть не должно, пришло %q", p)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("REAL-2 не дошёл")
	}
}

func TestJournal(t *testing.T) {
	JournalClear()
	Logf("привет %d", 1)
	Logf("второй")
	txt := JournalText(0)
	if !(len(txt) > 0) || JournalText(1) == txt {
		t.Fatalf("журнал: %q", txt)
	}
	JournalClear()
	if JournalText(0) != "" {
		t.Fatal("журнал не очистился")
	}
}
HYDRA_EOF

putv NOTICE <<'HYDRA_EOF'
Hydra — уведомления о сторонних компонентах / third-party notices

Hydra использует открытые компоненты:
- usque — https://github.com/Diniboy1123/usque — MIT License (Copyright (c) Diniboy1123 and contributors)
- форк usque, подключаемый как библиотека — https://github.com/inipew/usque — MIT License
- quic-go и connect-ip-go — https://github.com/quic-go — MIT License
- Go и golang.org/x/... — BSD-3-Clause License
- AndroidX и Jetpack Compose — Apache License 2.0

Полные тексты лицензий смотрите в репозиториях соответствующих проектов.
HYDRA_EOF

putv app/build.gradle.kts <<'HYDRA_EOF'
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
        versionCode = 4
        versionName = "0.4.0"
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
    implementation("androidx.core:core-ktx:1.13.1")
    implementation(files("libs/hydra.aar"))
}
HYDRA_EOF

putv app/src/main/AndroidManifest.xml <<'HYDRA_EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />

    <!-- Работает и на Android TV: сенсорный экран не обязателен -->
    <uses-feature android:name="android.hardware.touchscreen" android:required="false" />
    <uses-feature android:name="android.software.leanback" android:required="false" />

    <queries>
        <intent>
            <action android:name="android.intent.action.MAIN" />
            <category android:name="android.intent.category.LAUNCHER" />
        </intent>
    </queries>

    <application
        android:allowBackup="false"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:label="@string/app_name"
        android:theme="@style/Theme.Hydra">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
                <category android:name="android.intent.category.LEANBACK_LAUNCHER" />
            </intent-filter>
        </activity>

        <service
            android:name=".HydraVpnService"
            android:exported="false"
            android:permission="android.permission.BIND_VPN_SERVICE">
            <intent-filter>
                <action android:name="android.net.VpnService" />
            </intent-filter>
        </service>
    </application>
</manifest>
HYDRA_EOF

putv app/src/main/java/app/hydra/AccountController.kt <<'HYDRA_EOF'
package app.hydra

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** DNS-серверы текущих сетей телефона: Go на Android сам их найти не может. */
fun systemDns(ctx: Context): String {
    return try {
        val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val nets = cm.allNetworks.toMutableList()
        cm.activeNetwork?.let { nets.add(0, it) }
        val list = mutableListOf<String>()
        for (n in nets) {
            cm.getLinkProperties(n)?.dnsServers?.forEach { a ->
                a.hostAddress?.let { list.add(it) }
            }
        }
        list.distinct().joinToString(",")
    } catch (t: Throwable) {
        ""
    }
}

/** Состояние аккаунта WARP, общее для экранов; регистрация идёт в Go-ядре. */
class AccountController(
    private val ctx: Context,
    private val dir: String,
    private val scope: CoroutineScope,
    private val dnsProvider: () -> String
) {

    var id by mutableStateOf(readId())
        private set
    var busy by mutableStateOf(false)
        private set
    var report by mutableStateOf("")
        private set

    private fun readId(): String =
        try { mobile.Mobile.accountID(dir) } catch (t: Throwable) { "" }

    /** "" если ошибки нет, иначе вид: rate_limited | blocked | dns | api | storage | internal. */
    val failKind: String
        get() = if (report.startsWith("FAIL")) {
            report.lineSequence().first().removePrefix("FAIL").trim()
        } else {
            ""
        }

    private fun runRegister(): String =
        try {
            mobile.Mobile.setDNS(dnsProvider())
            mobile.Mobile.registerReport(dir)
        } catch (t: Throwable) {
            "FAIL internal\n" + t.message
        }

    fun register() {
        if (busy) return
        busy = true
        report = ""
        scope.launch {
            report = withContext(Dispatchers.IO) { runRegister() }
            id = readId()
            busy = false
        }
    }

    /** Регистрация через мобильную сеть — если домашний Wi-Fi режет api.cloudflareclient.com. */
    fun registerViaCellular() {
        if (busy) return
        busy = true
        report = ""
        val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val req = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        var finished = false
        lateinit var cb: ConnectivityManager.NetworkCallback
        fun finish(text: String?) {
            if (finished) return
            finished = true
            try { cm.bindProcessToNetwork(null) } catch (t: Throwable) { }
            try { cm.unregisterNetworkCallback(cb) } catch (t: Throwable) { }
            if (text != null) report = text
            id = readId()
            busy = false
        }
        cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                if (finished) return
                try { cm.bindProcessToNetwork(network) } catch (t: Throwable) { }
                scope.launch {
                    val r = withContext(Dispatchers.IO) { runRegister() }
                    finish(r)
                }
            }
        }
        try {
            cm.requestNetwork(req, cb)
        } catch (t: Throwable) {
            finish("FAIL cellular\n" + t.message)
            return
        }
        scope.launch {
            delay(12000)
            if (!finished && report.isEmpty() && busy) finish("FAIL cellular\nмобильная сеть недоступна")
        }
    }

    fun export(): String =
        try { mobile.Mobile.exportAccount(dir) } catch (t: Throwable) { "" }

    /** Пустая строка — успех, иначе текст ошибки. */
    fun importFrom(text: String): String {
        val err = try {
            mobile.Mobile.importAccount(dir, text)
        } catch (t: Throwable) {
            t.message ?: "error"
        }
        id = readId()
        return err
    }
}
HYDRA_EOF

putv app/src/main/java/app/hydra/AppsScreen.kt <<'HYDRA_EOF'
package app.hydra

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Checkbox
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.graphics.drawable.toBitmap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class AppItem(val pkg: String, val label: String, val icon: ImageBitmap?)

private fun loadApps(ctx: Context): List<AppItem> {
    val pm = ctx.packageManager
    val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
    return pm.queryIntentActivities(intent, 0)
        .distinctBy { it.activityInfo.packageName }
        .map { ri ->
            val icon = try {
                ri.loadIcon(pm).toBitmap(96, 96).asImageBitmap()
            } catch (t: Throwable) {
                null
            }
            AppItem(ri.activityInfo.packageName, ri.loadLabel(pm).toString(), icon)
        }
        .sortedBy { it.label.lowercase() }
}

@Composable
fun AppsScreen(prefs: Prefs) {
    val ctx = LocalContext.current
    var apps by remember { mutableStateOf<List<AppItem>>(emptyList()) }
    var selected by remember { mutableStateOf(prefs.splitApps) }
    var onlySelected by remember { mutableStateOf(prefs.splitOnlySelected) }
    var query by remember { mutableStateOf("") }

    LaunchedEffect(Unit) {
        apps = withContext(Dispatchers.IO) { loadApps(ctx) }
    }

    val filtered = remember(apps, query) {
        val q = query.trim()
        if (q.isEmpty()) apps else apps.filter { it.label.contains(q, ignoreCase = true) }
    }
    // выбранные — наверху
    val chosen = filtered.filter { it.pkg in selected }
    val rest = filtered.filter { it.pkg !in selected }

    fun toggle(pkg: String) {
        val n = if (pkg in selected) selected - pkg else selected + pkg
        selected = n
        prefs.splitApps = n
    }

    Column(Modifier.fillMaxSize()) {
        Column(Modifier.padding(start = 18.dp, end = 18.dp, top = 12.dp)) {
            Text(
                stringResource(R.string.apps_title),
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                color = NeonCyan
            )
            Spacer(Modifier.height(10.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(
                    selected = onlySelected,
                    onClick = {
                        onlySelected = true
                        prefs.splitOnlySelected = true
                    },
                    label = { Text(stringResource(R.string.mode_only)) }
                )
                FilterChip(
                    selected = !onlySelected,
                    onClick = {
                        onlySelected = false
                        prefs.splitOnlySelected = false
                    },
                    label = { Text(stringResource(R.string.mode_except)) }
                )
            }
            Spacer(Modifier.height(6.dp))
            Text(
                stringResource(if (onlySelected) R.string.mode_only_hint else R.string.mode_except_hint),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(Modifier.height(10.dp))
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                singleLine = true,
                shape = RoundedCornerShape(22.dp),
                placeholder = { Text(stringResource(R.string.apps_search)) },
                leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                modifier = Modifier.fillMaxWidth()
            )
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    stringResource(R.string.apps_selected, selected.size),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Row {
                    TextButton(onClick = {
                        val n = selected + filtered.map { it.pkg }
                        selected = n
                        prefs.splitApps = n
                    }) { Text(stringResource(R.string.apps_all)) }
                    TextButton(onClick = {
                        val n = selected - filtered.map { it.pkg }.toSet()
                        selected = n
                        prefs.splitApps = n
                    }) { Text(stringResource(R.string.apps_none)) }
                }
            }
        }

        LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 12.dp)) {
            if (chosen.isNotEmpty()) {
                item(key = "head_chosen") { ListHeader(stringResource(R.string.apps_header_chosen, chosen.size), NeonGreen) }
                items(chosen, key = { "s_" + it.pkg }) { a -> AppRow(a, true) { toggle(a.pkg) } }
                item(key = "head_rest") { ListHeader(stringResource(R.string.apps_header_rest), NeonViolet) }
            }
            items(rest, key = { it.pkg }) { a -> AppRow(a, false) { toggle(a.pkg) } }
        }
    }
}

@Composable
private fun ListHeader(text: String, color: Color) {
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        color = color,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(start = 22.dp, top = 12.dp, bottom = 4.dp)
    )
}

@Composable
private fun AppRow(a: AppItem, checked: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(18.dp)
    val border = if (checked) BorderStroke(1.6.dp, NeonGreen) else BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .clip(shape)
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f))
            .border(border, shape)
            .clickable { onClick() }
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Checkbox(checked = checked, onCheckedChange = null)
        Spacer(Modifier.width(10.dp))
        if (a.icon != null) {
            Image(bitmap = a.icon, contentDescription = null, modifier = Modifier.size(40.dp).clip(RoundedCornerShape(10.dp)))
        } else {
            Box(Modifier.size(40.dp))
        }
        Spacer(Modifier.width(12.dp))
        Text(a.label, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
    }
}
HYDRA_EOF

putv app/src/main/java/app/hydra/DiagScreen.kt <<'HYDRA_EOF'
package app.hydra

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

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
            .padding(horizontal = 18.dp, vertical = 12.dp)
    ) {
        Text(
            stringResource(R.string.diag_title),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            color = NeonCyan
        )
        Text(
            stringResource(R.string.diag_sub),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(14.dp))

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
            Spacer(Modifier.height(14.dp))
            HCard(accent = NeonGreen) {
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

        Spacer(Modifier.height(14.dp))
        JournalCard()
        Spacer(Modifier.height(8.dp))
    }
}

/** Подробный журнал: что делает Гидра и почему. Новые строки сверху. */
@Composable
fun JournalCard() {
    val clipboard = LocalClipboardManager.current
    var text by remember { mutableStateOf("") }

    LaunchedEffect(Unit) {
        while (isActive) {
            val raw = withContext(Dispatchers.IO) {
                try { mobile.Mobile.getJournal(400) } catch (t: Throwable) { "" }
            }
            text = raw.lines().reversed().joinToString("\n")
            delay(1500)
        }
    }

    HCard(accent = NeonViolet) {
        SectionTitle(stringResource(R.string.journal_title), NeonViolet)
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { clipboard.setText(AnnotatedString(unreverse(text))) }) {
                Text(stringResource(R.string.journal_copy))
            }
            OutlinedButton(onClick = {
                try { mobile.Mobile.clearJournal() } catch (t: Throwable) { }
                text = ""
            }) { Text(stringResource(R.string.journal_clear)) }
        }
        Spacer(Modifier.height(8.dp))
        SelectionContainer {
            Text(
                text = if (text.isEmpty()) stringResource(R.string.journal_empty) else text,
                fontFamily = FontFamily.Monospace,
                fontSize = 10.5.sp,
                lineHeight = 14.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 460.dp)
                    .verticalScroll(rememberScrollState())
            )
        }
    }
}

/** При копировании возвращаем строки в естественном порядке (старые сверху). */
private fun unreverse(shown: String): String = shown.lines().reversed().joinToString("\n")
HYDRA_EOF

putv app/src/main/java/app/hydra/Diagnostics.kt <<'HYDRA_EOF'
package app.hydra

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.URL

data class DiagResult(
    val dnsOk: Boolean,
    val dnsMs: Long,
    val httpsOk: Boolean,
    val httpsMs: Long,
    val ip: String,
    val loc: String,
    val colo: String,
    val warp: String
)

/** DNS + HTTPS до Cloudflare; trace показывает дата-центр и идёт ли трафик через WARP. */
suspend fun runDiagnostics(): DiagResult = withContext(Dispatchers.IO) {
    var dnsOk = false
    var t = System.currentTimeMillis()
    try {
        InetAddress.getByName("cloudflare.com")
        dnsOk = true
    } catch (e: Exception) {
    }
    val dnsMs = System.currentTimeMillis() - t

    var httpsOk = false
    var kv: Map<String, String> = emptyMap()
    t = System.currentTimeMillis()
    try {
        val c = URL("https://cloudflare.com/cdn-cgi/trace").openConnection() as HttpURLConnection
        c.connectTimeout = 5000
        c.readTimeout = 5000
        val body = c.inputStream.bufferedReader().use { it.readText() }
        c.disconnect()
        kv = body.lines()
            .mapNotNull { l -> l.split("=", limit = 2).takeIf { it.size == 2 }?.let { it[0] to it[1] } }
            .toMap()
        httpsOk = true
    } catch (e: Exception) {
    }
    val httpsMs = System.currentTimeMillis() - t

    DiagResult(
        dnsOk, dnsMs, httpsOk, httpsMs,
        kv["ip"].orEmpty(), kv["loc"].orEmpty(),
        (kv["colo"] ?: "").uppercase(), kv["warp"].orEmpty()
    )
}
HYDRA_EOF

putv app/src/main/java/app/hydra/HomeScreen.kt <<'HYDRA_EOF'
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
HYDRA_EOF

putv app/src/main/java/app/hydra/HydraHero.kt <<'HYDRA_EOF'
package app.hydra

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import kotlin.math.PI
import kotlin.math.sin

/** Что сейчас делает Гидра — решает, какая голова «оживает». */
enum class HeroMode { Off, Registering, Connecting, Connected, Failed }

private class HeadSpec(val eyes: List<Offset>, val mouth: Offset, val dir: Offset)

// Координаты — доли картинки hero_hydra (глаза, пасти, замочная скважина).
private val LEFT = HeadSpec(listOf(Offset(0.155f, 0.345f)), Offset(0.093f, 0.416f), Offset(-0.85f, 0.5f))
private val CENTER = HeadSpec(listOf(Offset(0.452f, 0.297f), Offset(0.554f, 0.297f)), Offset(0.5f, 0.408f), Offset(0f, 1f))
private val RIGHT = HeadSpec(listOf(Offset(0.845f, 0.345f)), Offset(0.897f, 0.426f), Offset(0.85f, 0.5f))
private val KEYHOLE = Offset(0.49f, 0.713f)

/**
 * Гидра в центре главного экрана:
 * регистрация — левая голова зажигает глаза и дышит огнём,
 * подключение — правая, «подключено» — центральная.
 */
@Composable
fun HydraHero(mode: HeroMode, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val inf = rememberInfiniteTransition(label = "hero")
    val t by inf.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1300, easing = LinearEasing)),
        label = "t"
    )
    Box(
        modifier
            .fillMaxWidth()
            .aspectRatio(504f / 498f)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onClick() }
    ) {
        Image(
            painter = painterResource(R.drawable.hero_hydra),
            contentDescription = null,
            contentScale = ContentScale.FillBounds,
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                .drawWithContent {
                    drawContent()
                    // растушёвка краёв, чтобы картинка растворялась в фоне
                    drawRect(
                        brush = Brush.radialGradient(
                            0.0f to Color.Black,
                            0.74f to Color.Black,
                            1.0f to Color.Transparent,
                            center = center,
                            radius = size.maxDimension * 0.62f
                        ),
                        blendMode = BlendMode.DstIn
                    )
                }
        )
        Canvas(Modifier.fillMaxSize()) {
            when (mode) {
                HeroMode.Registering -> {
                    head(LEFT, NeonAmber, t, true, Color(0xFFFFF2A8), Color(0xFFFF9A2E), Color(0xFFE8431A))
                    keyhole(NeonAmber, t, 0.5f)
                }
                HeroMode.Connecting -> {
                    head(RIGHT, NeonCyan, t, true, Color(0xFFE9FBFF), Color(0xFF47D4FF), Color(0xFF3B5BFF))
                    keyhole(NeonCyan, t, 0.7f)
                }
                HeroMode.Connected -> {
                    head(CENTER, NeonGreen, t, true, Color(0xFFF2FFE9), Color(0xFF84E36B), Color(0xFF19B38A), calm = true)
                    keyhole(NeonGreen, t, 1f)
                }
                HeroMode.Failed -> {
                    head(LEFT, Color(0xFFFF5A5A), t, false, Color.Red, Color.Red, Color.Red)
                    head(CENTER, Color(0xFFFF5A5A), t, false, Color.Red, Color.Red, Color.Red)
                    head(RIGHT, Color(0xFFFF5A5A), t, false, Color.Red, Color.Red, Color.Red)
                    keyhole(Color(0xFFFF5A5A), t, 0.6f)
                }
                HeroMode.Off -> {}
            }
        }
    }
}

private fun DrawScope.at(o: Offset) = Offset(o.x * size.width, o.y * size.height)

/** Светящиеся глаза и (если fire) огонь изо рта. */
private fun DrawScope.head(
    h: HeadSpec,
    eye: Color,
    t: Float,
    fire: Boolean,
    inner: Color,
    mid: Color,
    outer: Color,
    calm: Boolean = false
) {
    val pulse = 0.78f + 0.22f * sin(t * 2f * PI.toFloat() * 2f)
    val r = size.width * 0.024f
    for (e in h.eyes) {
        val c = at(e)
        drawCircle(
            brush = Brush.radialGradient(
                listOf(eye.copy(alpha = 0.95f * pulse), Color.Transparent),
                center = c,
                radius = r * 3.4f
            ),
            radius = r * 3.4f,
            center = c,
            blendMode = BlendMode.Plus
        )
        drawCircle(Color.White.copy(alpha = pulse), r * 0.55f, c)
    }
    if (!fire) return

    val len = size.width * (if (calm) 0.13f else 0.24f)
    val n = if (calm) 14 else 24
    val dir = h.dir / h.dir.getDistance()
    val perp = Offset(-dir.y, dir.x)
    val origin = at(h.mouth)
    for (i in 0 until n) {
        val ph = (t + i.toFloat() / n) % 1f
        val wob = sin(ph * 2f * PI.toFloat() * 1.5f + i * 1.7f) * len * 0.11f * ph
        val p = origin + dir * (ph * len) + perp * wob
        val pr = len * 0.17f * (1f - ph * 0.85f)
        val col = when {
            ph < 0.25f -> inner
            ph < 0.6f -> mid
            else -> outer
        }
        drawCircle(
            brush = Brush.radialGradient(
                listOf(col.copy(alpha = 0.9f * (1f - ph)), Color.Transparent),
                center = p,
                radius = pr * 2.1f
            ),
            radius = pr * 2.1f,
            center = p,
            blendMode = BlendMode.Plus
        )
    }
}

private fun DrawScope.keyhole(color: Color, t: Float, strength: Float) {
    val c = at(KEYHOLE)
    val k = strength * (0.7f + 0.3f * sin(t * 2f * PI.toFloat()))
    drawCircle(
        brush = Brush.radialGradient(listOf(color.copy(alpha = 0.55f * k), Color.Transparent), center = c, radius = size.width * 0.09f),
        radius = size.width * 0.09f,
        center = c,
        blendMode = BlendMode.Plus
    )
}
HYDRA_EOF

putv app/src/main/java/app/hydra/HydraVpnService.kt <<'HYDRA_EOF'
package app.hydra

import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Системный VPN-сервис: создаёт TUN-интерфейс и отдаёт его Go-ядру, которое
 * гонит пакеты через туннель WARP. Раздельное туннелирование — средствами Android:
 * в списке приложений либо «только эти», либо «все, кроме этих».
 * Само приложение всегда исключено из VPN, иначе его собственное QUIC-соединение
 * с Cloudflare пошло бы внутрь туннеля.
 * Сеть (Wi-Fi/мобильная) отслеживается через системные уведомления: при смене
 * ядро узнаёт об этом сразу и переподключается.
 */
class HydraVpnService : VpnService() {

    companion object {
        const val ACTION_START = "app.hydra.action.START"
        const val ACTION_STOP = "app.hydra.action.STOP"
        private const val TAG = "Hydra"
    }

    private val handler = Handler(Looper.getMainLooper())
    private var netCallback: ConnectivityManager.NetworkCallback? = null
    private var cellCallback: ConnectivityManager.NetworkCallback? = null
    private var forceCell = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return if (intent?.action == ACTION_STOP) {
            stopVpn()
            START_NOT_STICKY
        } else {
            startVpn()
            START_STICKY
        }
    }

    private fun cm() = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager

    private fun startVpn() {
        val running = try { !mobile.Mobile.engineStatus().startsWith("off") } catch (t: Throwable) { false }
        if (running) return

        val prefs = Prefs(this)
        forceCell = prefs.channel == "cell"
        try {
            mobile.Mobile.setColoPolicy(prefs.blockedColos, prefs.allowColos)
            mobile.Mobile.setFallback(prefs.fallbackAny)
            mobile.Mobile.setDNS(systemDns(this))
            mobile.Mobile.setNetKey(currentNetKey())
        } catch (t: Throwable) {
            Log.e(TAG, "настройки ядра: " + t.message)
        }

        if (forceCell) {
            // «Мобильная сеть»: привязываем процесс к мобильной сети — сокеты Гидры
            // (она сама исключена из VPN) пойдут через неё, даже если подключён Wi-Fi.
            val req = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()
            var started = false
            val cb = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    handler.post {
                        if (started) return@post
                        started = true
                        try { cm().bindProcessToNetwork(network) } catch (t: Throwable) { }
                        establishAndRun()
                    }
                }
            }
            cellCallback = cb
            try {
                cm().requestNetwork(req, cb)
            } catch (t: Throwable) {
                Log.e(TAG, "мобильная сеть: " + t.message)
                stopSelf()
                return
            }
            handler.postDelayed({
                if (!started) {
                    Log.e(TAG, "мобильная сеть недоступна")
                    stopVpn()
                }
            }, 10000)
        } else {
            establishAndRun()
        }
    }

    private fun establishAndRun() {
        val dir = filesDir.absolutePath
        val prefs = Prefs(this)

        val v4 = try { mobile.Mobile.accountAddr4(dir) } catch (t: Throwable) { "" }
        val v6 = try { mobile.Mobile.accountAddr6(dir) } catch (t: Throwable) { "" }
        if (v4.isEmpty()) {
            Log.e(TAG, "нет аккаунта WARP")
            stopVpn()
            return
        }

        val b = Builder()
            .setSession("Hydra")
            .setMtu(1280)
            .addAddress(v4, 32)
            .addRoute("0.0.0.0", 0)
            .addDnsServer("1.1.1.1")
            .addDnsServer("1.0.0.1")
        if (v6.isNotEmpty()) {
            b.addAddress(v6, 128)
            b.addRoute("::", 0)
            b.addDnsServer("2606:4700:4700::1111")
        }

        val apps = prefs.splitApps
        if (prefs.splitOnlySelected) {
            var any = false
            for (p in apps) {
                try {
                    b.addAllowedApplication(p)
                    any = true
                } catch (e: Exception) {
                }
            }
            if (!any) {
                stopVpn()
                return
            }
        } else {
            for (p in apps) {
                try {
                    b.addDisallowedApplication(p)
                } catch (e: Exception) {
                }
            }
            try {
                b.addDisallowedApplication(packageName)
            } catch (e: Exception) {
            }
        }

        val pfd = try { b.establish() } catch (e: Exception) { null }
        if (pfd == null) {
            Log.e(TAG, "не удалось создать TUN")
            stopVpn()
            return
        }
        val err = try {
            mobile.Mobile.startTunnel(dir, pfd.detachFd().toLong())
        } catch (t: Throwable) {
            t.message ?: "ошибка ядра"
        }
        if (err.isNotEmpty()) {
            Log.e(TAG, err)
            stopVpn()
            return
        }
        watchNetwork()
    }

    /** Ключ сети: "cell" при принудительном канале, иначе "wifi"/"cell"/"default" (сам VPN не считается). */
    private fun currentNetKey(): String {
        if (forceCell) return "cell"
        return try {
            var wifi = false
            var cell = false
            for (n in cm().allNetworks) {
                val c = cm().getNetworkCapabilities(n) ?: continue
                if (c.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
                if (c.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) wifi = true
                if (c.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) cell = true
            }
            when {
                wifi -> "wifi"
                cell -> "cell"
                else -> "default"
            }
        } catch (t: Throwable) {
            "default"
        }
    }

    /** Системные уведомления о сетях: смена Wi-Fi ↔ мобильная доходит до ядра сразу. */
    private fun watchNetwork() {
        if (netCallback != null) return
        val req = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        val cb = object : ConnectivityManager.NetworkCallback() {
            private fun push() {
                handler.postDelayed({
                    try { mobile.Mobile.setNetKey(currentNetKey()) } catch (t: Throwable) { }
                }, 300)
            }
            override fun onAvailable(network: Network) = push()
            override fun onLost(network: Network) = push()
        }
        netCallback = cb
        try {
            cm().registerNetworkCallback(req, cb)
        } catch (t: Throwable) {
            Log.e(TAG, "слежение за сетью: " + t.message)
        }
    }

    private fun stopVpn() {
        try { netCallback?.let { cm().unregisterNetworkCallback(it) } } catch (t: Throwable) { }
        netCallback = null
        try { cellCallback?.let { cm().unregisterNetworkCallback(it) } } catch (t: Throwable) { }
        cellCallback = null
        try { cm().bindProcessToNetwork(null) } catch (t: Throwable) { }
        handler.removeCallbacksAndMessages(null)
        try { mobile.Mobile.stopTunnel() } catch (t: Throwable) { }
        stopSelf()
    }

    override fun onRevoke() {
        stopVpn()
        super.onRevoke()
    }

    override fun onDestroy() {
        try { netCallback?.let { cm().unregisterNetworkCallback(it) } } catch (t: Throwable) { }
        try { cellCallback?.let { cm().unregisterNetworkCallback(it) } } catch (t: Throwable) { }
        try { cm().bindProcessToNetwork(null) } catch (t: Throwable) { }
        try { mobile.Mobile.stopTunnel() } catch (t: Throwable) { }
        super.onDestroy()
    }
}
HYDRA_EOF

putv app/src/main/java/app/hydra/MainActivity.kt <<'HYDRA_EOF'
package app.hydra

import android.content.Context
import android.content.res.Configuration
import android.os.Bundle
import androidx.activity.ComponentActivity
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
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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

@Composable
fun HydraApp(prefs: Prefs, onLanguageChanged: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val account = remember { AccountController(ctx.applicationContext, ctx.filesDir.absolutePath, scope) { systemDns(ctx) } }
    val vpn = remember { VpnController(ctx.applicationContext, scope) }
    var tab by rememberSaveable { mutableStateOf(0) }

    Scaffold(
        containerColor = Color.Transparent,
        bottomBar = {
            NavigationBar(containerColor = MaterialTheme.colorScheme.surfaceVariant) {
                NavigationBarItem(
                    selected = tab == 0,
                    onClick = { tab = 0 },
                    icon = { Icon(Icons.Filled.Home, contentDescription = null) },
                    label = { Text(stringResource(R.string.tab_home)) }
                )
                NavigationBarItem(
                    selected = tab == 1,
                    onClick = { tab = 1 },
                    icon = { Icon(Icons.Filled.Lock, contentDescription = null) },
                    label = { Text(stringResource(R.string.tab_split)) }
                )
                NavigationBarItem(
                    selected = tab == 2,
                    onClick = { tab = 2 },
                    icon = { Icon(Icons.Filled.Build, contentDescription = null) },
                    label = { Text(stringResource(R.string.tab_diag)) }
                )
                NavigationBarItem(
                    selected = tab == 3,
                    onClick = { tab = 3 },
                    icon = { Icon(Icons.Filled.Settings, contentDescription = null) },
                    label = { Text(stringResource(R.string.tab_settings)) }
                )
            }
        }
    ) { pad ->
        Box(Modifier.padding(pad).statusBarsPadding().fillMaxSize()) {
            when (tab) {
                0 -> HomeScreen(prefs, account, vpn)
                1 -> AppsScreen(prefs)
                2 -> DiagScreen(prefs)
                else -> SettingsScreen(prefs, account, onLanguageChanged)
            }
        }
    }
}
HYDRA_EOF

putv app/src/main/java/app/hydra/Prefs.kt <<'HYDRA_EOF'
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

    /** Запрещённые дата-центры Cloudflare, коды через запятую. */
    var blockedColos: String
        get() = sp.getString("colo_block", null) ?: defaultBlockedColos()
        set(v) { sp.edit().putString("colo_block", v).apply() }

    /** Если не пусто — разрешены только эти дата-центры. */
    var allowColos: String
        get() = sp.getString("colo_allow", "") ?: ""
        set(v) { sp.edit().putString("colo_allow", v).apply() }

    /** Канал связи с Cloudflare: "auto" или "cell" (принудительно мобильная сеть). */
    var channel: String
        get() = sp.getString("channel", "auto") ?: "auto"
        set(v) { sp.edit().putString("channel", v).apply() }

    /** Если все адреса ведут в запрещённый дата-центр — подключиться всё равно. */
    var fallbackAny: Boolean
        get() = sp.getBoolean("fallback_any", false)
        set(v) { sp.edit().putBoolean("fallback_any", v).apply() }

    fun defaultBlockedColos(): String =
        try { mobile.Mobile.defaultBlockedColos() } catch (t: Throwable) { "DME" }
}
HYDRA_EOF

putv app/src/main/java/app/hydra/SettingsScreen.kt <<'HYDRA_EOF'
package app.hydra

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp

@Composable
fun SettingsScreen(prefs: Prefs, account: AccountController, onLanguageChanged: () -> Unit) {
    val clipboard = LocalClipboardManager.current
    var lang by remember { mutableStateOf(prefs.lang) }
    var channel by remember { mutableStateOf(prefs.channel) }
    var block by remember { mutableStateOf(prefs.blockedColos) }
    var allow by remember { mutableStateOf(prefs.allowColos) }
    var fallback by remember { mutableStateOf(prefs.fallbackAny) }
    var auto by remember { mutableStateOf(prefs.autoStart) }
    var kill by remember { mutableStateOf(prefs.killSwitch) }
    var note by remember { mutableStateOf("") }
    var showLicenses by remember { mutableStateOf(false) }

    val copiedMsg = stringResource(R.string.account_copied)
    val nothingMsg = stringResource(R.string.account_nothing)
    val importedMsg = stringResource(R.string.account_imported)
    val scheme = MaterialTheme.colorScheme

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 18.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            stringResource(R.string.settings_title),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            color = NeonCyan
        )

        // Язык
        HCard(accent = NeonCyan) {
            SectionTitle(stringResource(R.string.settings_language), NeonCyan)
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(
                    "system" to R.string.lang_system,
                    "en" to R.string.lang_en,
                    "ru" to R.string.lang_ru
                ).forEach { (code, res) ->
                    FilterChip(
                        selected = lang == code,
                        onClick = {
                            if (lang != code) {
                                lang = code
                                prefs.lang = code
                                onLanguageChanged()
                            }
                        },
                        label = { Text(stringResource(res)) }
                    )
                }
            }
        }

        // Канал связи
        HCard(accent = NeonPink) {
            SectionTitle(stringResource(R.string.channel_title), NeonPink)
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("auto" to R.string.channel_auto, "cell" to R.string.channel_cell).forEach { (code, res) ->
                    FilterChip(
                        selected = channel == code,
                        onClick = {
                            channel = code
                            prefs.channel = code
                        },
                        label = { Text(stringResource(res)) }
                    )
                }
            }
            Text(
                stringResource(R.string.channel_hint),
                style = MaterialTheme.typography.bodySmall,
                color = scheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 6.dp)
            )
        }

        // Дата-центры Cloudflare
        HCard(accent = NeonViolet) {
            SectionTitle(stringResource(R.string.colo_title), NeonViolet)
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                value = block,
                onValueChange = {
                    block = it.uppercase()
                    prefs.blockedColos = block
                },
                label = { Text(stringResource(R.string.colo_block)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                value = allow,
                onValueChange = {
                    allow = it.uppercase()
                    prefs.allowColos = allow
                },
                label = { Text(stringResource(R.string.colo_allow)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                modifier = Modifier.fillMaxWidth()
            )
            Text(
                stringResource(R.string.colo_hint),
                style = MaterialTheme.typography.bodySmall,
                color = scheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 6.dp)
            )
            SwitchRow(stringResource(R.string.fallback_any), fallback) {
                fallback = it
                prefs.fallbackAny = it
            }
            Text(
                stringResource(R.string.fallback_hint),
                style = MaterialTheme.typography.bodySmall,
                color = scheme.onSurfaceVariant
            )
            TextButton(onClick = {
                block = prefs.defaultBlockedColos()
                prefs.blockedColos = block
                allow = ""
                prefs.allowColos = ""
            }) { Text(stringResource(R.string.colo_reset)) }
        }

        // Аккаунт WARP
        HCard(accent = NeonGreen) {
            SectionTitle(stringResource(R.string.account_title), NeonGreen)
            Spacer(Modifier.height(4.dp))
            Text(
                if (account.id.isEmpty()) {
                    stringResource(R.string.step_account_none)
                } else {
                    stringResource(R.string.step_account_ok, account.id.take(8))
                },
                style = MaterialTheme.typography.bodyMedium
            )
            Spacer(Modifier.height(10.dp))
            Button(
                onClick = { account.register() },
                enabled = !account.busy && account.id.isEmpty(),
                shape = RoundedCornerShape(14.dp),
                modifier = Modifier.fillMaxWidth().height(48.dp)
            ) {
                if (account.busy) {
                    CircularProgressIndicator(
                        Modifier.size(20.dp),
                        strokeWidth = 2.dp,
                        color = scheme.onPrimary
                    )
                } else {
                    Text(stringResource(R.string.action_register))
                }
            }
            Spacer(Modifier.height(8.dp))
            OutlinedButton(
                onClick = { account.registerViaCellular() },
                enabled = !account.busy && account.id.isEmpty(),
                modifier = Modifier.fillMaxWidth()
            ) { Text(stringResource(R.string.action_register_cell)) }
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = {
                        val s = account.export()
                        if (s.isEmpty()) {
                            note = nothingMsg
                        } else {
                            clipboard.setText(AnnotatedString(s))
                            note = copiedMsg
                        }
                    },
                    modifier = Modifier.weight(1f)
                ) { Text(stringResource(R.string.account_copy)) }
                OutlinedButton(
                    onClick = {
                        val text = clipboard.getText()?.text.orEmpty()
                        val err = account.importFrom(text)
                        note = if (err.isEmpty()) importedMsg else err
                    },
                    modifier = Modifier.weight(1f)
                ) { Text(stringResource(R.string.account_paste)) }
            }
            Text(
                stringResource(R.string.account_hint),
                style = MaterialTheme.typography.bodySmall,
                color = scheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 6.dp)
            )
            if (note.isNotEmpty()) {
                Text(
                    note,
                    style = MaterialTheme.typography.bodySmall,
                    color = scheme.primary,
                    modifier = Modifier.padding(top = 6.dp)
                )
            }
            if (account.failKind.isNotEmpty()) {
                Text(
                    failText(account.failKind),
                    style = MaterialTheme.typography.bodySmall,
                    color = scheme.error,
                    modifier = Modifier.padding(top = 6.dp)
                )
                Text(
                    stringResource(R.string.journal_see),
                    style = MaterialTheme.typography.bodySmall,
                    color = scheme.onSurfaceVariant
                )
            }
        }

        // Подключение
        HCard(accent = NeonAmber) {
            SectionTitle(stringResource(R.string.conn_title), NeonAmber)
            SwitchRow(stringResource(R.string.settings_autostart), auto) {
                auto = it
                prefs.autoStart = it
            }
            SwitchRow(stringResource(R.string.settings_killswitch), kill) {
                kill = it
                prefs.killSwitch = it
            }
            Text(
                stringResource(R.string.settings_soon),
                style = MaterialTheme.typography.bodySmall,
                color = scheme.onSurfaceVariant
            )
        }

        // О программе
        HCard(accent = NeonPink) {
            SectionTitle(stringResource(R.string.about_title), NeonPink)
            Spacer(Modifier.height(4.dp))
            Text(stringResource(R.string.about_text), style = MaterialTheme.typography.bodyMedium)
            val engine = remember { try { mobile.Mobile.version() } catch (t: Throwable) { "n/a" } }
            Text(
                stringResource(R.string.engine_label, engine),
                style = MaterialTheme.typography.bodySmall,
                color = scheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp)
            )
            TextButton(onClick = { showLicenses = !showLicenses }) {
                Text(stringResource(R.string.licenses_title))
            }
            if (showLicenses) {
                Text(
                    stringResource(R.string.licenses_text),
                    style = MaterialTheme.typography.bodySmall,
                    color = scheme.onSurfaceVariant
                )
            }
        }
        Spacer(Modifier.height(8.dp))
    }
}
HYDRA_EOF

putv app/src/main/java/app/hydra/Theme.kt <<'HYDRA_EOF'
package app.hydra

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.ImageShader
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.Canvas as GfxCanvas

// Неоновая палитра Гидры.
val NeonCyan = Color(0xFF47D4FF)
val NeonViolet = Color(0xFFA98BFF)
val NeonPink = Color(0xFFFF7AD9)
val NeonGreen = Color(0xFF84E36B)
val NeonAmber = Color(0xFFFFC857)
val HydraGreen = NeonGreen

private val HydraColors = darkColorScheme(
    primary = NeonCyan,
    onPrimary = Color(0xFF00243D),
    primaryContainer = Color(0xFF0F2A57),
    onPrimaryContainer = Color(0xFFCFE8FF),
    secondary = NeonViolet,
    onSecondary = Color(0xFF1B0F52),
    tertiary = NeonGreen,
    background = Color(0xFF080C18),
    onBackground = Color(0xFFE6ECFA),
    surface = Color(0xFF080C18),
    onSurface = Color(0xFFE6ECFA),
    surfaceVariant = Color(0xFF111B33),
    onSurfaceVariant = Color(0xFFA9B6D3),
    outline = Color(0xFF3C4B70),
    error = Color(0xFFFF8A80),
    onError = Color(0xFF410002)
)

/** Гидра всегда тёмная: неон на карбоне. */
@Composable
fun HydraTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = HydraColors, content = content)
}

/** Плитка «карбона» 24×24: тёмные и чуть светлее квадраты в шахматном порядке. */
private fun carbonTile(): ImageBitmap {
    val bmp = ImageBitmap(24, 24)
    val c = GfxCanvas(bmp)
    val dark = Paint().apply { color = Color(0xFF0A0F1D) }
    val light = Paint().apply { color = Color(0xFF0F1628) }
    c.drawRect(0f, 0f, 24f, 24f, dark)
    c.drawRect(0f, 0f, 12f, 12f, light)
    c.drawRect(12f, 12f, 24f, 24f, light)
    return bmp
}

/** Фон приложения: карбон с мягким неоновым свечением сверху. */
@Composable
fun HydraBackground(content: @Composable () -> Unit) {
    val tile = remember { carbonTile() }
    val carbon = remember(tile) { ShaderBrush(ImageShader(tile, TileMode.Repeated, TileMode.Repeated)) }
    Box(
        Modifier
            .fillMaxSize()
            .background(Color(0xFF080C18))
            .drawBehind { drawRect(brush = carbon) }
            .background(
                Brush.verticalGradient(
                    listOf(NeonViolet.copy(alpha = 0.10f), Color.Transparent, NeonCyan.copy(alpha = 0.06f))
                )
            )
    ) { content() }
}
HYDRA_EOF

putv app/src/main/java/app/hydra/Ui.kt <<'HYDRA_EOF'
package app.hydra

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.TextButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/** Карточка с неоновой рамкой: цвет рамки — accent. */
@Composable
fun HCard(
    modifier: Modifier = Modifier,
    accent: Color = NeonCyan,
    content: @Composable ColumnScope.() -> Unit
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(22.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.72f)
        ),
        border = BorderStroke(1.6.dp, accent.copy(alpha = 0.85f))
    ) {
        Column(Modifier.padding(16.dp), content = content)
    }
}

@Composable
fun SectionTitle(text: String, color: Color = Color.Unspecified) {
    Text(
        text,
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.SemiBold,
        color = color
    )
}

enum class StepState { Done, Pending, Failed }

/** Строка чек-листа: значок состояния, заголовок, пояснение и необязательное действие справа. */
@Composable
fun StepRow(
    state: StepState,
    title: String,
    subtitle: String,
    actionLabel: String? = null,
    onAction: () -> Unit = {}
) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        val icon = when (state) {
            StepState.Done -> Icons.Filled.CheckCircle
            StepState.Failed -> Icons.Filled.Warning
            StepState.Pending -> Icons.Filled.Info
        }
        val tint = when (state) {
            StepState.Done -> MaterialTheme.colorScheme.primary
            StepState.Failed -> MaterialTheme.colorScheme.error
            StepState.Pending -> MaterialTheme.colorScheme.outline
        }
        Icon(icon, contentDescription = null, tint = tint)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        if (actionLabel != null) {
            TextButton(onClick = onAction) { Text(actionLabel) }
        }
    }
}

@Composable
fun SwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label, Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
fun failText(kind: String): String = stringResource(
    when (kind) {
        "rate_limited" -> R.string.fail_rate_limited
        "blocked" -> R.string.fail_blocked
        "dns" -> R.string.fail_dns
        "api" -> R.string.fail_api
        else -> R.string.fail_other
    }
)

private val COLO_NAMES = mapOf(
    "DME" to "Moscow", "LED" to "Saint Petersburg", "SVX" to "Yekaterinburg",
    "KJA" to "Krasnoyarsk", "OVB" to "Novosibirsk", "KHV" to "Khabarovsk",
    "VVO" to "Vladivostok", "KZN" to "Kazan",
    "HEL" to "Helsinki", "FRA" to "Frankfurt", "AMS" to "Amsterdam",
    "ARN" to "Stockholm", "WAW" to "Warsaw", "VIE" to "Vienna",
    "PRG" to "Prague", "CDG" to "Paris", "LHR" to "London",
    "MAD" to "Madrid", "MXP" to "Milan", "ZRH" to "Zurich",
    "OSL" to "Oslo", "CPH" to "Copenhagen", "RIX" to "Riga",
    "VNO" to "Vilnius", "TLL" to "Tallinn", "IST" to "Istanbul"
)

/** "HEL · Helsinki" или просто код, если город неизвестен. */
fun coloLabel(code: String): String {
    val c = code.uppercase()
    val city = COLO_NAMES[c]
    return if (city != null) "$c · $city" else c
}

/** Разбирает "DME, led;fra" в множество кодов в верхнем регистре. */
fun parseColos(s: String): Set<String> =
    s.split(',', ';', ' ', '\n').map { it.trim().uppercase() }.filter { it.isNotEmpty() }.toSet()
HYDRA_EOF

putv app/src/main/java/app/hydra/VpnController.kt <<'HYDRA_EOF'
package app.hydra

import android.content.Context
import android.content.Intent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Состояние VPN для интерфейса: раз в секунду спрашивает у Go-ядра, как дела. */
class VpnController(private val ctx: Context, scope: CoroutineScope) {

    var state by mutableStateOf("off")
        private set
    var strategy by mutableStateOf("")
        private set
    var colo by mutableStateOf("")
        private set
    var rttMs by mutableStateOf(0)
        private set
    var message by mutableStateOf("")
        private set

    val active: Boolean get() = state != "off"

    init {
        scope.launch {
            while (isActive) {
                refresh()
                delay(1000)
            }
        }
    }

    private suspend fun refresh() {
        val raw = withContext(Dispatchers.IO) {
            try {
                mobile.Mobile.engineStatus()
            } catch (t: Throwable) {
                "off||||"
            }
        }
        val p = raw.split("|")
        state = p.getOrElse(0) { "off" }
        strategy = p.getOrElse(1) { "" }
        colo = p.getOrElse(2) { "" }
        rttMs = p.getOrElse(3) { "0" }.toIntOrNull() ?: 0
        message = p.getOrElse(4) { "" }
    }

    fun start() {
        ctx.startService(Intent(ctx, HydraVpnService::class.java).setAction(HydraVpnService.ACTION_START))
    }

    fun stop() {
        ctx.startService(Intent(ctx, HydraVpnService::class.java).setAction(HydraVpnService.ACTION_STOP))
    }
}

/** "h3/162.159.198.1/std" -> "H3 · std" */
fun routeLabel(strategy: String): String {
    val p = strategy.split("/")
    return if (p.size == 3) p[0].uppercase() + " · " + p[2] else "—"
}
HYDRA_EOF

putb app/src/main/res/drawable-nodpi/hero_hydra.webp <<'HYDRA_EOF'
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
HYDRA_EOF

putb app/src/main/res/drawable-nodpi/ic_launcher_art.webp <<'HYDRA_EOF'
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
HYDRA_EOF

putv app/src/main/res/drawable/ic_hydra_mark.xml <<'HYDRA_EOF'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <group android:scaleX="0.8" android:scaleY="0.8" android:pivotX="54" android:pivotY="54" android:translateY="-0.5">
        <path android:strokeColor="#2EC8FF" android:strokeAlpha="0.8" android:strokeWidth="1.7" android:strokeLineCap="round" android:pathData="M30 92 C40 97.5 68 97.5 78 92"/>
        <path android:strokeColor="#2EC8FF" android:strokeAlpha="0.45" android:strokeWidth="1.7" android:strokeLineCap="round" android:pathData="M25 96.5 C38 102.5 70 102.5 83 96.5"/>
        <path android:strokeColor="#2EC8FF" android:strokeWidth="5.6" android:strokeLineCap="round" android:pathData="M47 62 C37 58.5 34.5 50.5 37.6 42.2"/>
        <path android:strokeColor="#4FA6FF" android:strokeWidth="6.4" android:strokeLineCap="round" android:pathData="M54 62 L54 40.5"/>
        <path android:strokeColor="#8A6BFF" android:strokeWidth="5.6" android:strokeLineCap="round" android:pathData="M61 62 C71 58.5 73.5 50.5 70.4 42.2"/>
        <group android:pivotX="0" android:pivotY="0" android:rotation="-40" android:scaleX="0.88" android:scaleY="0.88" android:translateX="32.5" android:translateY="36.0">
            <path android:fillColor="#2EC8FF" android:strokeColor="#0A1030" android:strokeWidth="0.5" android:pathData="M0 -17 L3.6 -11.5 L8.6 -14.6 L6.2 -7.4 L7.4 -2.2 L4.2 4.6 L0 7.6 L-4.2 4.6 L-7.4 -2.2 L-6.2 -7.4 L-8.6 -14.6 L-3.6 -11.5 Z"/>
            <path android:fillColor="#E6FBFF" android:pathData="M-4.6 -4.6 L-1.2 -3.4 L-4.4 -2.2 Z M4.6 -4.6 L1.2 -3.4 L4.4 -2.2 Z"/>
        </group>
        <group android:pivotX="0" android:pivotY="0" android:rotation="40" android:scaleX="0.88" android:scaleY="0.88" android:translateX="75.5" android:translateY="36.0">
            <path android:fillColor="#8A6BFF" android:strokeColor="#0A1030" android:strokeWidth="0.5" android:pathData="M0 -17 L3.6 -11.5 L8.6 -14.6 L6.2 -7.4 L7.4 -2.2 L4.2 4.6 L0 7.6 L-4.2 4.6 L-7.4 -2.2 L-6.2 -7.4 L-8.6 -14.6 L-3.6 -11.5 Z"/>
            <path android:fillColor="#E6FBFF" android:pathData="M-4.6 -4.6 L-1.2 -3.4 L-4.4 -2.2 Z M4.6 -4.6 L1.2 -3.4 L4.4 -2.2 Z"/>
        </group>
        <group android:pivotX="0" android:pivotY="0" android:rotation="0" android:scaleX="1.12" android:scaleY="1.12" android:translateX="54.0" android:translateY="31.5">
            <path android:fillColor="#4FA6FF" android:strokeColor="#0A1030" android:strokeWidth="0.5" android:pathData="M0 -17 L3.6 -11.5 L8.6 -14.6 L6.2 -7.4 L7.4 -2.2 L4.2 4.6 L0 7.6 L-4.2 4.6 L-7.4 -2.2 L-6.2 -7.4 L-8.6 -14.6 L-3.6 -11.5 Z"/>
            <path android:fillColor="#E6FBFF" android:pathData="M-4.6 -4.6 L-1.2 -3.4 L-4.4 -2.2 Z M4.6 -4.6 L1.2 -3.4 L4.4 -2.2 Z"/>
        </group>
        <path android:fillColor="#0F2A63" android:strokeColor="#2EC8FF" android:strokeWidth="2.4" android:strokeLineJoin="round" android:pathData="M54 55.5 L68.5 60.5 V72 C68.5 80.5 62.5 86.5 54 90 C45.5 86.5 39.5 80.5 39.5 72 V60.5 Z"/>
        <path android:fillColor="#13398A" android:pathData="M54 59 L65 62.8 V72 C65 78.6 60.4 83.4 54 86.2 C47.6 83.4 43 78.6 43 72 V62.8 Z"/>
        <path android:fillColor="#E6FBFF" android:pathData="M54 65.2 m-3.6 0 a3.6 3.6 0 1 0 7.2 0 a3.6 3.6 0 1 0 -7.2 0 Z"/>
        <path android:fillColor="#E6FBFF" android:pathData="M52.4 67.6 L55.6 67.6 L56.7 76 L51.3 76 Z"/>
    </group>
</vector>
HYDRA_EOF

putv app/src/main/res/drawable/ic_launcher_background.xml <<'HYDRA_EOF'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:aapt="http://schemas.android.com/aapt"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path android:pathData="M0 0 H108 V108 H0 Z">
        <aapt:attr name="android:fillColor">
            <gradient
                android:startX="54" android:startY="0"
                android:endX="54" android:endY="108"
                android:startColor="#0A1030"
                android:endColor="#142560"
                android:type="linear" />
        </aapt:attr>
    </path>
</vector>
HYDRA_EOF

putv app/src/main/res/drawable/ic_launcher_foreground.xml <<'HYDRA_EOF'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <group android:scaleX="0.8" android:scaleY="0.8" android:pivotX="54" android:pivotY="54" android:translateY="-0.5">
        <path android:strokeColor="#2EC8FF" android:strokeAlpha="0.8" android:strokeWidth="1.7" android:strokeLineCap="round" android:pathData="M30 92 C40 97.5 68 97.5 78 92"/>
        <path android:strokeColor="#2EC8FF" android:strokeAlpha="0.45" android:strokeWidth="1.7" android:strokeLineCap="round" android:pathData="M25 96.5 C38 102.5 70 102.5 83 96.5"/>
        <path android:strokeColor="#2EC8FF" android:strokeWidth="5.6" android:strokeLineCap="round" android:pathData="M47 62 C37 58.5 34.5 50.5 37.6 42.2"/>
        <path android:strokeColor="#4FA6FF" android:strokeWidth="6.4" android:strokeLineCap="round" android:pathData="M54 62 L54 40.5"/>
        <path android:strokeColor="#8A6BFF" android:strokeWidth="5.6" android:strokeLineCap="round" android:pathData="M61 62 C71 58.5 73.5 50.5 70.4 42.2"/>
        <group android:pivotX="0" android:pivotY="0" android:rotation="-40" android:scaleX="0.88" android:scaleY="0.88" android:translateX="32.5" android:translateY="36.0">
            <path android:fillColor="#2EC8FF" android:strokeColor="#0A1030" android:strokeWidth="0.5" android:pathData="M0 -17 L3.6 -11.5 L8.6 -14.6 L6.2 -7.4 L7.4 -2.2 L4.2 4.6 L0 7.6 L-4.2 4.6 L-7.4 -2.2 L-6.2 -7.4 L-8.6 -14.6 L-3.6 -11.5 Z"/>
            <path android:fillColor="#E6FBFF" android:pathData="M-4.6 -4.6 L-1.2 -3.4 L-4.4 -2.2 Z M4.6 -4.6 L1.2 -3.4 L4.4 -2.2 Z"/>
        </group>
        <group android:pivotX="0" android:pivotY="0" android:rotation="40" android:scaleX="0.88" android:scaleY="0.88" android:translateX="75.5" android:translateY="36.0">
            <path android:fillColor="#8A6BFF" android:strokeColor="#0A1030" android:strokeWidth="0.5" android:pathData="M0 -17 L3.6 -11.5 L8.6 -14.6 L6.2 -7.4 L7.4 -2.2 L4.2 4.6 L0 7.6 L-4.2 4.6 L-7.4 -2.2 L-6.2 -7.4 L-8.6 -14.6 L-3.6 -11.5 Z"/>
            <path android:fillColor="#E6FBFF" android:pathData="M-4.6 -4.6 L-1.2 -3.4 L-4.4 -2.2 Z M4.6 -4.6 L1.2 -3.4 L4.4 -2.2 Z"/>
        </group>
        <group android:pivotX="0" android:pivotY="0" android:rotation="0" android:scaleX="1.12" android:scaleY="1.12" android:translateX="54.0" android:translateY="31.5">
            <path android:fillColor="#4FA6FF" android:strokeColor="#0A1030" android:strokeWidth="0.5" android:pathData="M0 -17 L3.6 -11.5 L8.6 -14.6 L6.2 -7.4 L7.4 -2.2 L4.2 4.6 L0 7.6 L-4.2 4.6 L-7.4 -2.2 L-6.2 -7.4 L-8.6 -14.6 L-3.6 -11.5 Z"/>
            <path android:fillColor="#E6FBFF" android:pathData="M-4.6 -4.6 L-1.2 -3.4 L-4.4 -2.2 Z M4.6 -4.6 L1.2 -3.4 L4.4 -2.2 Z"/>
        </group>
        <path android:fillColor="#0F2A63" android:strokeColor="#2EC8FF" android:strokeWidth="2.4" android:strokeLineJoin="round" android:pathData="M54 55.5 L68.5 60.5 V72 C68.5 80.5 62.5 86.5 54 90 C45.5 86.5 39.5 80.5 39.5 72 V60.5 Z"/>
        <path android:fillColor="#13398A" android:pathData="M54 59 L65 62.8 V72 C65 78.6 60.4 83.4 54 86.2 C47.6 83.4 43 78.6 43 72 V62.8 Z"/>
        <path android:fillColor="#E6FBFF" android:pathData="M54 65.2 m-3.6 0 a3.6 3.6 0 1 0 7.2 0 a3.6 3.6 0 1 0 -7.2 0 Z"/>
        <path android:fillColor="#E6FBFF" android:pathData="M52.4 67.6 L55.6 67.6 L56.7 76 L51.3 76 Z"/>
    </group>
</vector>
HYDRA_EOF

putv app/src/main/res/drawable/ic_launcher_monochrome.xml <<'HYDRA_EOF'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <group android:scaleX="0.8" android:scaleY="0.8" android:pivotX="54" android:pivotY="54" android:translateY="-0.5">
        <path android:strokeColor="#FFFFFF" android:strokeWidth="5.6" android:strokeLineCap="round" android:pathData="M47 62 C37 58.5 34.5 50.5 37.6 42.2"/>
        <path android:strokeColor="#FFFFFF" android:strokeWidth="6.4" android:strokeLineCap="round" android:pathData="M54 62 L54 40.5"/>
        <path android:strokeColor="#FFFFFF" android:strokeWidth="5.6" android:strokeLineCap="round" android:pathData="M61 62 C71 58.5 73.5 50.5 70.4 42.2"/>
        <group android:pivotX="0" android:pivotY="0" android:rotation="-40" android:scaleX="0.88" android:scaleY="0.88" android:translateX="32.5" android:translateY="36.0">
            <path android:fillColor="#FFFFFF" android:fillType="evenOdd" android:pathData="M0 -17 L3.6 -11.5 L8.6 -14.6 L6.2 -7.4 L7.4 -2.2 L4.2 4.6 L0 7.6 L-4.2 4.6 L-7.4 -2.2 L-6.2 -7.4 L-8.6 -14.6 L-3.6 -11.5 Z M-4.6 -4.6 L-1.2 -3.4 L-4.4 -2.2 Z M4.6 -4.6 L1.2 -3.4 L4.4 -2.2 Z"/>
        </group>
        <group android:pivotX="0" android:pivotY="0" android:rotation="40" android:scaleX="0.88" android:scaleY="0.88" android:translateX="75.5" android:translateY="36.0">
            <path android:fillColor="#FFFFFF" android:fillType="evenOdd" android:pathData="M0 -17 L3.6 -11.5 L8.6 -14.6 L6.2 -7.4 L7.4 -2.2 L4.2 4.6 L0 7.6 L-4.2 4.6 L-7.4 -2.2 L-6.2 -7.4 L-8.6 -14.6 L-3.6 -11.5 Z M-4.6 -4.6 L-1.2 -3.4 L-4.4 -2.2 Z M4.6 -4.6 L1.2 -3.4 L4.4 -2.2 Z"/>
        </group>
        <group android:pivotX="0" android:pivotY="0" android:rotation="0" android:scaleX="1.12" android:scaleY="1.12" android:translateX="54.0" android:translateY="31.5">
            <path android:fillColor="#FFFFFF" android:fillType="evenOdd" android:pathData="M0 -17 L3.6 -11.5 L8.6 -14.6 L6.2 -7.4 L7.4 -2.2 L4.2 4.6 L0 7.6 L-4.2 4.6 L-7.4 -2.2 L-6.2 -7.4 L-8.6 -14.6 L-3.6 -11.5 Z M-4.6 -4.6 L-1.2 -3.4 L-4.4 -2.2 Z M4.6 -4.6 L1.2 -3.4 L4.4 -2.2 Z"/>
        </group>
        <path android:strokeColor="#FFFFFF" android:strokeWidth="2.4" android:strokeLineJoin="round" android:pathData="M54 55.5 L68.5 60.5 V72 C68.5 80.5 62.5 86.5 54 90 C45.5 86.5 39.5 80.5 39.5 72 V60.5 Z"/>
        <path android:fillColor="#FFFFFF" android:pathData="M54 65.2 m-3.6 0 a3.6 3.6 0 1 0 7.2 0 a3.6 3.6 0 1 0 -7.2 0 Z"/>
        <path android:fillColor="#FFFFFF" android:pathData="M52.4 67.6 L55.6 67.6 L56.7 76 L51.3 76 Z"/>
    </group>
</vector>
HYDRA_EOF

putv app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml <<'HYDRA_EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/hydra_icon_bg" />
    <foreground android:drawable="@drawable/ic_launcher_art" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
HYDRA_EOF

putv app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml <<'HYDRA_EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/hydra_icon_bg" />
    <foreground android:drawable="@drawable/ic_launcher_art" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
HYDRA_EOF

putv app/src/main/res/values-ru/strings.xml <<'HYDRA_EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">Hydra</string>

    <string name="tab_home">Главная</string>
    <string name="tab_split">Приложения</string>
    <string name="tab_diag">Проверка</string>
    <string name="tab_settings">Настройки</string>

    <string name="home_tagline">WARP, который чинит себя</string>
    <string name="home_status_need_account">Нужен аккаунт</string>
    <string name="home_sub_need_account">Нажми кнопку, чтобы создать аккаунт WARP</string>
    <string name="home_status_registering">Регистрирую…</string>
    <string name="home_sub_registering">Пробую несколько маршрутов до Cloudflare</string>
    <string name="home_status_ready">Готово</string>
    <string name="home_sub_ready">Подключение появится в следующей сборке</string>
    <string name="home_soon_toast">Подключение появится в следующей сборке</string>

    <string name="ready_title">Готовность</string>
    <string name="step_engine">Движок Go</string>
    <string name="step_account">Аккаунт WARP</string>
    <string name="step_account_ok">Зарегистрирован · %1$s</string>
    <string name="step_account_none">Не зарегистрирован</string>
    <string name="step_connect">Подключение</string>
    <string name="step_connect_sub">Нажми на щит сверху</string>
    <string name="action_register">Зарегистрировать</string>
    <string name="fail_rate_limited">Cloudflare ограничивает регистрации с этого IP. Подожди несколько минут и повтори.</string>
    <string name="fail_blocked">Не удаётся достучаться до API Cloudflare: сеть или DNS блокируют. Попробуй другую сеть (мобильную или Wi-Fi).</string>
    <string name="fail_dns">Не удаётся определить адрес API Cloudflare: DNS не отвечает, а DoH недоступен. Проверь сеть или смени её.</string>
    <string name="fail_api">API Cloudflare отказал в запросе.</string>
    <string name="fail_other">Не удалось зарегистрироваться.</string>

    <string name="dc_title">Дата-центр</string>
    <string name="dc_blocked">Запрещены: %1$s</string>
    <string name="dc_allow">Только: %1$s</string>
    <string name="dc_hint">После подключения Гидра проверит, в какой дата-центр Cloudflare ты попал, и если он запрещён, попробует другие маршруты.</string>

    <string name="apps_title">Раздельное туннелирование</string>
    <string name="mode_only">Только выбранные</string>
    <string name="mode_except">Все, кроме выбранных</string>
    <string name="mode_only_hint">Через VPN пойдут только отмеченные приложения</string>
    <string name="mode_except_hint">Отмеченные приложения пойдут напрямую</string>
    <string name="apps_search">Поиск приложений</string>
    <string name="apps_selected">Выбрано: %1$d</string>
    <string name="apps_all">Все</string>
    <string name="apps_none">Сбросить</string>

    <string name="diag_title">Диагностика</string>
    <string name="diag_sub">Проверяет DNS, HTTPS и в какой дата-центр Cloudflare ты попадаешь</string>
    <string name="diag_run">Проверить</string>
    <string name="diag_dns">DNS</string>
    <string name="diag_https">HTTPS</string>
    <string name="diag_ms">%1$d мс</string>
    <string name="diag_fail">ошибка</string>
    <string name="diag_ip">Публичный IP</string>
    <string name="diag_dc">Дата-центр</string>
    <string name="diag_dc_unknown">не определён</string>
    <string name="diag_dc_blocked">%1$s — запрещён политикой</string>
    <string name="diag_warp">WARP</string>
    <string name="diag_warp_on">включён</string>
    <string name="diag_warp_off">выключен (прямое соединение)</string>

    <string name="settings_title">Настройки</string>
    <string name="settings_language">Язык</string>
    <string name="lang_system">Системный</string>
    <string name="lang_en">English</string>
    <string name="lang_ru">Русский</string>

    <string name="colo_title">Дата-центры Cloudflare</string>
    <string name="colo_block">Запрещённые (коды)</string>
    <string name="colo_allow">Только эти (необязательно)</string>
    <string name="colo_hint">Коды аэропортов через запятую: HEL, FRA, AMS…</string>
    <string name="colo_reset">По умолчанию</string>

    <string name="account_title">Аккаунт WARP</string>
    <string name="account_copy">Копировать</string>
    <string name="account_paste">Вставить</string>
    <string name="account_copied">Аккаунт скопирован</string>
    <string name="account_nothing">Аккаунта ещё нет</string>
    <string name="account_imported">Аккаунт импортирован</string>
    <string name="account_hint">Скопируй аккаунт, чтобы перенести его на другое устройство</string>

    <string name="conn_title">Подключение</string>
    <string name="settings_autostart">Подключаться при запуске</string>
    <string name="settings_killswitch">Блокировать трафик при обрыве VPN</string>
    <string name="settings_soon">Эти опции заработают, когда будет готово подключение.</string>

    <string name="about_title">О программе</string>
    <string name="about_text">Hydra 0.4 · отрубишь одну голову — вырастут две. Сделано для тех, кому нужен интернет без компромиссов.</string>
    <string name="engine_label">Движок: %1$s</string>

    <string name="vpn_off">Не подключено</string>
    <string name="vpn_off_sub">Нажми на щит, чтобы подключиться</string>
    <string name="vpn_connecting">Подключаюсь…</string>
    <string name="vpn_connecting_sub">Ищу лучший маршрут</string>
    <string name="vpn_up">Подключено</string>
    <string name="vpn_up_sub">Дата-центр %1$s</string>
    <string name="vpn_reconnecting">Переподключаюсь…</string>
    <string name="vpn_failed">Нет соединения</string>
    <string name="tile_dc">Дата-центр</string>
    <string name="tile_rtt">Задержка</string>
    <string name="tile_route">Маршрут</string>
    <string name="need_apps_toast">Сначала выбери приложения (вкладка «Приложения») или включи режим «Все, кроме выбранных»</string>

    <string name="apps_header_chosen">Выбранные (%1$d)</string>
    <string name="apps_header_rest">Все приложения</string>
    <string name="journal_title">Журнал</string>
    <string name="journal_copy">Копировать</string>
    <string name="journal_clear">Очистить</string>
    <string name="journal_empty">Пока пусто. Подключись или зарегистрируйся — каждый шаг появится здесь.</string>
    <string name="journal_see">Подробности — в журнале (вкладка «Проверка»).</string>
    <string name="channel_title">Канал связи</string>
    <string name="channel_auto">Автоматически</string>
    <string name="channel_cell">Мобильная сеть</string>
    <string name="channel_hint">Мобильная сеть: туннель идёт через мобильный интернет, даже когда включён Wi-Fi. Помогает, если провайдер домашнего Wi-Fi ведёт только в запрещённый дата-центр. Расходует мобильный трафик.</string>
    <string name="fallback_any">Подключаться, даже если иначе никак</string>
    <string name="fallback_hint">Если все адреса ведут в запрещённый дата-центр — подключиться к нему, а не сидеть без интернета.</string>
    <string name="action_register_cell">Зарегистрировать через мобильную сеть</string>
    <string name="licenses_title">Лицензии</string>
    <string name="licenses_text">Гидра использует открытые компоненты: usque (лицензия MIT), quic-go и другие под свободными лицензиями. Полные тексты — в файле NOTICE репозитория проекта.</string>
</resources>
HYDRA_EOF

putv app/src/main/res/values/ic_colors.xml <<'HYDRA_EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="hydra_icon_bg">#081F3F</color>
</resources>
HYDRA_EOF

putv app/src/main/res/values/strings.xml <<'HYDRA_EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">Hydra</string>

    <string name="tab_home">Home</string>
    <string name="tab_split">Apps</string>
    <string name="tab_diag">Check</string>
    <string name="tab_settings">Settings</string>

    <string name="home_tagline">WARP that heals itself</string>
    <string name="home_status_need_account">Account required</string>
    <string name="home_sub_need_account">Tap the button to create a WARP account</string>
    <string name="home_status_registering">Registering…</string>
    <string name="home_sub_registering">Trying several routes to Cloudflare</string>
    <string name="home_status_ready">Ready</string>
    <string name="home_sub_ready">Connecting arrives in the next build</string>
    <string name="home_soon_toast">Connecting arrives in the next build</string>

    <string name="ready_title">Readiness</string>
    <string name="step_engine">Go engine</string>
    <string name="step_account">WARP account</string>
    <string name="step_account_ok">Registered · %1$s</string>
    <string name="step_account_none">Not registered</string>
    <string name="step_connect">Connection</string>
    <string name="step_connect_sub">Tap the shield above</string>
    <string name="action_register">Register</string>
    <string name="fail_rate_limited">Cloudflare limits registrations from this IP. Wait a few minutes and try again.</string>
    <string name="fail_blocked">Cannot reach the Cloudflare API: the network or DNS blocks it. Try another network (mobile data or Wi-Fi).</string>
    <string name="fail_dns">Cannot resolve the Cloudflare API address: DNS does not answer and DoH is unreachable. Check the network or switch to another one.</string>
    <string name="fail_api">The Cloudflare API refused the request.</string>
    <string name="fail_other">Registration failed.</string>

    <string name="dc_title">Datacenter</string>
    <string name="dc_blocked">Blocked: %1$s</string>
    <string name="dc_allow">Only: %1$s</string>
    <string name="dc_hint">After connecting, Hydra checks which Cloudflare datacenter you landed in and tries other routes if it is blocked.</string>

    <string name="apps_title">Split tunneling</string>
    <string name="mode_only">Only selected</string>
    <string name="mode_except">All except selected</string>
    <string name="mode_only_hint">Only checked apps go through the VPN</string>
    <string name="mode_except_hint">Checked apps bypass the VPN</string>
    <string name="apps_search">Search apps</string>
    <string name="apps_selected">Selected: %1$d</string>
    <string name="apps_all">All</string>
    <string name="apps_none">Clear</string>

    <string name="diag_title">Diagnostics</string>
    <string name="diag_sub">Checks DNS, HTTPS and which Cloudflare datacenter serves you</string>
    <string name="diag_run">Run check</string>
    <string name="diag_dns">DNS</string>
    <string name="diag_https">HTTPS</string>
    <string name="diag_ms">%1$d ms</string>
    <string name="diag_fail">failed</string>
    <string name="diag_ip">Public IP</string>
    <string name="diag_dc">Datacenter</string>
    <string name="diag_dc_unknown">unknown</string>
    <string name="diag_dc_blocked">%1$s — blocked by policy</string>
    <string name="diag_warp">WARP</string>
    <string name="diag_warp_on">active</string>
    <string name="diag_warp_off">off (direct connection)</string>

    <string name="settings_title">Settings</string>
    <string name="settings_language">Language</string>
    <string name="lang_system">System</string>
    <string name="lang_en">English</string>
    <string name="lang_ru">Русский</string>

    <string name="colo_title">Cloudflare datacenters</string>
    <string name="colo_block">Blocked (codes)</string>
    <string name="colo_allow">Only these (optional)</string>
    <string name="colo_hint">Airport codes, comma separated: HEL, FRA, AMS…</string>
    <string name="colo_reset">Reset to default</string>

    <string name="account_title">WARP account</string>
    <string name="account_copy">Copy</string>
    <string name="account_paste">Paste</string>
    <string name="account_copied">Account copied</string>
    <string name="account_nothing">No account yet</string>
    <string name="account_imported">Account imported</string>
    <string name="account_hint">Copy the account to move it to another device</string>

    <string name="conn_title">Connection</string>
    <string name="settings_autostart">Connect on startup</string>
    <string name="settings_killswitch">Block traffic if the VPN drops</string>
    <string name="settings_soon">These options take effect once connecting is ready.</string>

    <string name="about_title">About</string>
    <string name="about_text">Hydra 0.4 · cut off one head and two grow back. Built for people who want the internet without compromises.</string>
    <string name="engine_label">Engine: %1$s</string>

    <string name="vpn_off">Not connected</string>
    <string name="vpn_off_sub">Tap the shield to connect</string>
    <string name="vpn_connecting">Connecting…</string>
    <string name="vpn_connecting_sub">Looking for the best route</string>
    <string name="vpn_up">Connected</string>
    <string name="vpn_up_sub">Datacenter %1$s</string>
    <string name="vpn_reconnecting">Reconnecting…</string>
    <string name="vpn_failed">No connection</string>
    <string name="tile_dc">Datacenter</string>
    <string name="tile_rtt">Latency</string>
    <string name="tile_route">Route</string>
    <string name="need_apps_toast">Select apps first (Apps tab) or switch the mode to “All except selected”</string>

    <string name="apps_header_chosen">Selected (%1$d)</string>
    <string name="apps_header_rest">All apps</string>
    <string name="journal_title">Journal</string>
    <string name="journal_copy">Copy</string>
    <string name="journal_clear">Clear</string>
    <string name="journal_empty">Empty for now. Connect or register, and every step appears here.</string>
    <string name="journal_see">Details are in the journal (Check tab).</string>
    <string name="channel_title">Connection channel</string>
    <string name="channel_auto">Automatic</string>
    <string name="channel_cell">Mobile network</string>
    <string name="channel_hint">Mobile network: the tunnel is carried over mobile data even when Wi-Fi is on. Helps when your Wi-Fi provider only leads to a blocked datacenter. Uses mobile data.</string>
    <string name="fallback_any">Connect anyway if there is no other way</string>
    <string name="fallback_hint">If every address leads to a blocked datacenter, connect to it rather than stay offline.</string>
    <string name="action_register_cell">Register via mobile network</string>
    <string name="licenses_title">Licenses</string>
    <string name="licenses_text">Hydra uses open-source components: usque (MIT License), quic-go and others under permissive licenses. Full notices are in the NOTICE file of the project repository.</string>
</resources>
HYDRA_EOF

echo "$NEW" > "$STAMP"
