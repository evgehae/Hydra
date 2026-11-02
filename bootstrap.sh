#!/usr/bin/env bash
# Создаёт файлы Android-проекта Гидры, если их ещё нет (существующие не трогает).
set -e

put() {
  f="$1"
  mkdir -p "$(dirname "$f")"
  if [ -e "$f" ]; then cat > /dev/null; else cat > "$f"; fi
}

# Версия набора файлов: файлы «v2» перезаписываются один раз, потом их можно править руками.
STAMP=.hydra_bootstrap
OLD="$(cat "$STAMP" 2>/dev/null || echo 0)"
NEW=2
putv() {
  f="$1"
  mkdir -p "$(dirname "$f")"
  if [ ! -e "$f" ] || [ "$OLD" -lt "$NEW" ]; then cat > "$f"; else cat > /dev/null; fi
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

# ===================== v2: регистрация, дата-центры, новый интерфейс =====================
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

putv "$GODIR/mobile/mobile.go" <<'HYDRA_EOF'
// Package mobile — тонкая обвязка для gomobile: то, что видно из Kotlin.
// Только простые типы (строки), чтобы привязка собиралась без сюрпризов.
package mobile

import (
	"context"
	"errors"
	"fmt"
	"path/filepath"
	"strings"
	"time"

	hydra "hydra/core"
)

const version = "0.2.0"

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
	var log strings.Builder
	r := hydra.NewRegistrar()
	r.Log = func(s string) { log.WriteString(s + "\n") }
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()

	acc, err := r.Register(ctx)
	if err != nil {
		kind := "blocked"
		var re *hydra.RegError
		if errors.As(err, &re) {
			kind = re.Kind
		}
		return fmt.Sprintf("FAIL %s\n%s%v", kind, log.String(), err)
	}
	if err := acc.Save(path); err != nil {
		return "FAIL storage\n" + err.Error()
	}
	return "OK\n" + log.String() + "id: " + acc.ID
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
	KindBlocked     = "blocked"      // до API не достучаться (DNS/DPI/сеть)
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

func classify(errs []error) *RegError {
	re := &RegError{Kind: KindBlocked}
	rate, api := false, false
	for _, e := range errs {
		re.Detail = append(re.Detail, e.Error())
		var he *httpError
		if errors.As(e, &he) {
			if he.Status == http.StatusTooManyRequests {
				rate = true
				if he.RetryAfter > re.RetryAfter {
					re.RetryAfter = he.RetryAfter
				}
			} else {
				api = true
			}
		}
	}
	switch {
	case rate:
		re.Kind = KindRateLimited
	case api:
		re.Kind = KindAPI
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
}

var allMethods = []regMethod{
	{"direct", false, false},
	{"frag", false, true},
	{"doh", true, false},
	{"doh+frag", true, true},
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
		return nil, errors.New("пустой ответ API при регистрации")
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
	return json.Unmarshal(data, out)
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
	tc := tls.Client(c, &tls.Config{
		ServerName: host,
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
        versionCode = 2
        versionName = "0.2.0"
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
    </application>
</manifest>
HYDRA_EOF

putv app/src/main/java/app/hydra/AccountController.kt <<'HYDRA_EOF'
package app.hydra

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Состояние аккаунта WARP, общее для экранов; регистрация идёт в Go-ядре. */
class AccountController(private val dir: String, private val scope: CoroutineScope) {

    var id by mutableStateOf(readId())
        private set
    var busy by mutableStateOf(false)
        private set
    var report by mutableStateOf("")
        private set

    private fun readId(): String =
        try { mobile.Mobile.accountID(dir) } catch (t: Throwable) { "" }

    /** "" если ошибки нет, иначе вид: rate_limited | blocked | api | storage | internal. */
    val failKind: String
        get() = if (report.startsWith("FAIL")) {
            report.lineSequence().first().removePrefix("FAIL").trim()
        } else {
            ""
        }

    fun register() {
        if (busy) return
        busy = true
        report = ""
        scope.launch {
            report = withContext(Dispatchers.IO) {
                try {
                    mobile.Mobile.registerReport(dir)
                } catch (t: Throwable) {
                    "FAIL internal\n" + t.message
                }
            }
            id = readId()
            busy = false
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
import androidx.compose.foundation.Image
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

    Column(Modifier.fillMaxSize()) {
        Column(Modifier.padding(start = 20.dp, end = 20.dp, top = 16.dp)) {
            Text(
                stringResource(R.string.apps_title),
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold
            )
            Spacer(Modifier.height(12.dp))
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

        LazyColumn(Modifier.fillMaxSize()) {
            items(filtered, key = { it.pkg }) { a ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clickable {
                            val n = if (a.pkg in selected) selected - a.pkg else selected + a.pkg
                            selected = n
                            prefs.splitApps = n
                        }
                        .padding(horizontal = 20.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (a.icon != null) {
                        Image(bitmap = a.icon, contentDescription = null, modifier = Modifier.size(40.dp))
                    } else {
                        Box(Modifier.size(40.dp))
                    }
                    Spacer(Modifier.width(14.dp))
                    Text(a.label, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                    Checkbox(checked = a.pkg in selected, onCheckedChange = null)
                }
            }
        }
    }
}
HYDRA_EOF

putv app/src/main/java/app/hydra/DiagScreen.kt <<'HYDRA_EOF'
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
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    HydraApp(prefs) { recreate() }
                }
            }
        }
    }
}

@Composable
fun HydraApp(prefs: Prefs, onLanguageChanged: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val account = remember { AccountController(ctx.filesDir.absolutePath, scope) }
    var tab by rememberSaveable { mutableStateOf(0) }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
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
                0 -> HomeScreen(prefs, account)
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
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun SettingsScreen(prefs: Prefs, account: AccountController, onLanguageChanged: () -> Unit) {
    val clipboard = LocalClipboardManager.current
    var lang by remember { mutableStateOf(prefs.lang) }
    var block by remember { mutableStateOf(prefs.blockedColos) }
    var allow by remember { mutableStateOf(prefs.allowColos) }
    var auto by remember { mutableStateOf(prefs.autoStart) }
    var kill by remember { mutableStateOf(prefs.killSwitch) }
    var note by remember { mutableStateOf("") }

    val copiedMsg = stringResource(R.string.account_copied)
    val nothingMsg = stringResource(R.string.account_nothing)
    val importedMsg = stringResource(R.string.account_imported)

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            stringResource(R.string.settings_title),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold
        )

        // Язык
        HCard {
            SectionTitle(stringResource(R.string.settings_language))
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

        // Дата-центры Cloudflare
        HCard {
            SectionTitle(stringResource(R.string.colo_title))
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
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 6.dp)
            )
            TextButton(onClick = {
                block = prefs.defaultBlockedColos()
                prefs.blockedColos = block
                allow = ""
                prefs.allowColos = ""
            }) { Text(stringResource(R.string.colo_reset)) }
        }

        // Аккаунт WARP
        HCard {
            SectionTitle(stringResource(R.string.account_title))
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
                        color = MaterialTheme.colorScheme.onPrimary
                    )
                } else {
                    Text(stringResource(R.string.action_register))
                }
            }
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
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 6.dp)
            )
            if (note.isNotEmpty()) {
                Text(
                    note,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(top = 6.dp)
                )
            }
            if (account.failKind.isNotEmpty()) {
                Text(
                    failText(account.failKind),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(top = 6.dp)
                )
            }
            if (account.report.isNotEmpty()) {
                Text(
                    account.report,
                    fontFamily = FontFamily.Monospace,
                    fontSize = 11.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 8.dp)
                )
            }
        }

        // Подключение
        HCard {
            SectionTitle(stringResource(R.string.conn_title))
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
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        // О программе
        HCard {
            SectionTitle(stringResource(R.string.about_title))
            Spacer(Modifier.height(4.dp))
            Text(stringResource(R.string.about_text), style = MaterialTheme.typography.bodySmall)
            val engine = remember { try { mobile.Mobile.version() } catch (t: Throwable) { "n/a" } }
            Text(
                stringResource(R.string.engine_label, engine),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp)
            )
        }
    }
}
HYDRA_EOF

putv app/src/main/java/app/hydra/Theme.kt <<'HYDRA_EOF'
package app.hydra

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DarkColors = darkColorScheme(
    primary = Color(0xFF3DDBB0),
    onPrimary = Color(0xFF00382A),
    primaryContainer = Color(0xFF0E3B31),
    onPrimaryContainer = Color(0xFFB9F6E4),
    secondary = Color(0xFF9CC4B8),
    onSecondary = Color(0xFF0B2A22),
    background = Color(0xFF0A110F),
    onBackground = Color(0xFFE1EAE6),
    surface = Color(0xFF0A110F),
    onSurface = Color(0xFFE1EAE6),
    surfaceVariant = Color(0xFF16221E),
    onSurfaceVariant = Color(0xFFAFC0BA),
    outline = Color(0xFF50635C),
    error = Color(0xFFFF8A80),
    onError = Color(0xFF410002)
)

private val LightColors = lightColorScheme(
    primary = Color(0xFF00796B),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFCDEFE6),
    onPrimaryContainer = Color(0xFF00201A),
    secondary = Color(0xFF4A635C),
    background = Color(0xFFF5FAF8),
    onBackground = Color(0xFF111917),
    surface = Color(0xFFF5FAF8),
    onSurface = Color(0xFF111917),
    surfaceVariant = Color(0xFFE2EDE9),
    onSurfaceVariant = Color(0xFF3E4E49),
    outline = Color(0xFF70827B),
    error = Color(0xFFBA1A1A)
)

@Composable
fun HydraTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) DarkColors else LightColors,
        content = content
    )
}
HYDRA_EOF

putv app/src/main/java/app/hydra/Ui.kt <<'HYDRA_EOF'
package app.hydra

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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/** Карточка-контейнер с мягкими углами. */
@Composable
fun HCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
    ) {
        Column(Modifier.padding(16.dp), content = content)
    }
}

@Composable
fun SectionTitle(text: String) {
    Text(text, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
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
    <string name="step_connect_sub">Появится в следующей сборке</string>
    <string name="action_register">Зарегистрировать</string>
    <string name="fail_rate_limited">Cloudflare ограничивает регистрации с этого IP. Подожди несколько минут и повтори.</string>
    <string name="fail_blocked">Не удаётся достучаться до API Cloudflare: сеть или DNS блокируют. Попробуй другую сеть (мобильную или Wi-Fi).</string>
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
    <string name="about_text">Hydra 0.2.0 · основано на идеях открытого клиента usque (MIT)</string>
    <string name="engine_label">Движок: %1$s</string>
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
    <string name="step_connect_sub">Coming in the next build</string>
    <string name="action_register">Register</string>
    <string name="fail_rate_limited">Cloudflare limits registrations from this IP. Wait a few minutes and try again.</string>
    <string name="fail_blocked">Cannot reach the Cloudflare API: the network or DNS blocks it. Try another network (mobile data or Wi-Fi).</string>
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
    <string name="about_text">Hydra 0.2.0 · built on ideas of the open-source usque client (MIT)</string>
    <string name="engine_label">Engine: %1$s</string>
</resources>
HYDRA_EOF

echo "$NEW" > "$STAMP"
