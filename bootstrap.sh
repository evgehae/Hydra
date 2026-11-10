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
NEW=13
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
# убрать лишний файл из прошлой версии (манифест лежал не там)
rm -f app/src/main/java/AndroidManifest.xml

GODIR="$(dirname "$(find . -name go.mod -not -path './app/*' | head -1)")"

putv .gitignore <<'HYDRA_EOF'
.gradle/
build/
app/build/
app/libs/
local.properties
*.aar
HYDRA_EOF

putv NOTICE <<'HYDRA_EOF'
Hydra — уведомления о сторонних компонентах / third-party notices

Hydra использует открытые компоненты:
- usque — https://github.com/Diniboy1123/usque — MIT License (Copyright (c) Diniboy1123 and contributors)
- форк usque, подключаемый как библиотека — https://github.com/inipew/usque — MIT License
- quic-go и connect-ip-go — https://github.com/quic-go — MIT License
- wireguard-go (golang.zx2c4.com/wireguard) — MIT License (Copyright (C) Jason A. Donenfeld)
- Go и golang.org/x/... — BSD-3-Clause License
- AndroidX и Jetpack Compose — Apache License 2.0

Полные тексты лицензий смотрите в репозиториях соответствующих проектов.
HYDRA_EOF

putv README.md <<'HYDRA_EOF'
# Гидра (Hydra) — «WARP CLAUDE»

VPN-клиент для Android поверх Cloudflare WARP (MASQUE и WireGuard), который сам подбирает рабочий путь и чинит себя.

## Как устроено
- `engine.go` — движок: TUN ↔ туннель, проверки (UDP, реальный TCP), политика дата-центров, смена сети, перебор стратегий.
- `strategies.go`, `custom.go`, `wg.go` — стратегии подключения (фейковые QUIC-пакеты, SNI, порты, HTTP/2, WireGuard).
- `memory.go` — память: что работало в какой сети (сохраняется сразу после результата).
- `register.go` — регистрация аккаунта WARP «гонкой маршрутов».
- `mobile/` — обвязка gomobile для Kotlin.
- `orchestrator.go`, `front.go`, `transport.go` — прототип гонки/горячего резерва (пока не подключён к движку).
- `app/` — Android-приложение (Compose): главный экран с ползунком; меню → «Дополнительно» и «Диагностика».

## Сборка
Через GitHub Actions: `bootstrap.sh` раскладывает файлы проекта, workflow собирает AAR и APK.
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
        versionCode = 7
        versionName = "0.6.0"
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
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />

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
            android:foregroundServiceType="specialUse"
            android:permission="android.permission.BIND_VPN_SERVICE">
            <intent-filter>
                <action android:name="android.net.VpnService" />
            </intent-filter>
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="vpn" />
        </service>

        <receiver
            android:name=".BootReceiver"
            android:enabled="true"
            android:exported="false">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
            </intent-filter>
        </receiver>
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

    // ---- конфигурация WireGuard (обычный WARP как у wgcf или своя) ----
    var wgId by mutableStateOf(readWgId())
        private set
    var wgBusy by mutableStateOf(false)
        private set
    var wgReport by mutableStateOf("")
        private set

    private fun readWgId(): String =
        try { mobile.Mobile.wireguardAccountID(dir) } catch (t: Throwable) { "" }

    val wgFailKind: String
        get() = if (wgReport.startsWith("FAIL")) {
            wgReport.lineSequence().first().removePrefix("FAIL").trim()
        } else {
            ""
        }

    fun registerWg() {
        if (wgBusy) return
        wgBusy = true
        wgReport = ""
        scope.launch {
            wgReport = withContext(Dispatchers.IO) { runRegisterWg() }
            wgId = readWgId()
            wgBusy = false
        }
    }

    fun exportWg(): String =
        try { mobile.Mobile.exportWireguardConfig(dir) } catch (t: Throwable) { "" }

    /** Пустая строка — успех, иначе текст ошибки. */
    fun importWg(text: String): String {
        val err = try { mobile.Mobile.importWireguardConfig(dir, text) } catch (t: Throwable) { t.message ?: "error" }
        wgId = readWgId()
        return err
    }

    fun deleteWg() {
        try { mobile.Mobile.deleteWireguardConfig(dir) } catch (t: Throwable) { }
        wgId = readWgId()
    }

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

    private var autoTried = false

    val working: Boolean get() = busy || wgBusy

    private fun runRegisterWg(): String =
        try {
            mobile.Mobile.setDNS(dnsProvider())
            mobile.Mobile.registerWireguardReport(dir)
        } catch (t: Throwable) {
            "FAIL internal\n" + t.message
        }

    /** При первом запуске тихо создаёт оба аккаунта (MASQUE и WireGuard): протоколы страхуют друг друга. */
    fun ensureAll() {
        if (autoTried) return
        autoTried = true
        scope.launch {
            if (id.isEmpty() && !busy) {
                busy = true
                report = ""
                report = withContext(Dispatchers.IO) { runRegister() }
                id = readId()
                busy = false
            }
            if (wgId.isEmpty() && !wgBusy) {
                wgBusy = true
                wgReport = ""
                wgReport = withContext(Dispatchers.IO) { runRegisterWg() }
                wgId = readWgId()
                wgBusy = false
            }
        }
    }

    /** «Сбросить ключи безопасности»: удаляет оба аккаунта и регистрирует заново. */
    fun resetKeys() {
        try { mobile.Mobile.deleteAccount(dir) } catch (t: Throwable) { }
        try { mobile.Mobile.deleteWireguardConfig(dir) } catch (t: Throwable) { }
        id = readId()
        wgId = readWgId()
        report = ""
        wgReport = ""
        autoTried = false
        ensureAll()
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

putv app/src/main/java/app/hydra/AdvancedScreens.kt <<'HYDRA_EOF'
package app.hydra

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp

/** «Дополнительно»: список как в 1.1.1.1. */
@Composable
fun AdvancedScreen(onBack: () -> Unit, onConn: () -> Unit, onMore: () -> Unit) {
    SubPage(stringResource(R.string.menu_advanced), onBack) {
        Spacer(Modifier.height(16.dp))
        RowDivider()
        SettingRow(stringResource(R.string.conn_params), onClick = onConn)
        SettingRow(stringResource(R.string.adv_more), stringResource(R.string.adv_more_sub), onClick = onMore)
    }
}

/** «Параметры подключения»: приложения, маршруты, DNS, протокол, SNI, конечная точка, сбросы. */
@Composable
fun ConnScreen(
    prefs: Prefs,
    account: AccountController,
    vpn: VpnController,
    onBack: () -> Unit,
    onApps: () -> Unit,
    onRoutes: () -> Unit,
    onDns: () -> Unit,
    onResetAll: () -> Unit
) {
    var sni by remember { mutableStateOf(prefs.customSni) }
    var ep by remember { mutableStateOf(prefs.customEndpoint) }
    var proto by remember { mutableStateOf(prefs.protocol) }
    var dlg by remember { mutableStateOf("") } // sni | ep | proto | keys | all

    val protoName = stringResource(
        when (proto) {
            "masque" -> R.string.proto_masque_chip
            "wg" -> R.string.proto_wg_chip
            else -> R.string.proto_auto
        }
    )
    val dflt = stringResource(R.string.value_default)

    SubPage(stringResource(R.string.conn_params), onBack) {
        Spacer(Modifier.height(16.dp))
        RowDivider()
        SettingRow(stringResource(R.string.conn_apps), onClick = onApps)
        SettingRow(stringResource(R.string.conn_routes), onClick = onRoutes)
        SettingRow(stringResource(R.string.conn_dns), onClick = onDns)
        SettingRow(stringResource(R.string.conn_proto), value = protoName, onClick = { dlg = "proto" })
        NoteText(stringResource(R.string.proto_hint))
        SettingRow(stringResource(R.string.conn_reset_keys), onClick = { dlg = "keys" })
        SettingRow(stringResource(R.string.conn_reset_all), onClick = { dlg = "all" })
        SettingRow(
            stringResource(R.string.conn_sni), stringResource(R.string.conn_sni_sub),
            value = if (sni.isEmpty()) dflt else sni, onClick = { dlg = "sni" }
        )
        SettingRow(
            stringResource(R.string.conn_endpoint), stringResource(R.string.conn_endpoint_sub),
            value = if (ep.isEmpty()) dflt else ep, onClick = { dlg = "ep" }
        )
        Spacer(Modifier.height(24.dp))
    }

    when (dlg) {
        "sni" -> TextDialog(
            stringResource(R.string.conn_sni), sni, stringResource(R.string.conn_sni_hint),
            onDismiss = { dlg = "" },
            onApply = { sni = it; prefs.customSni = it; dlg = ""; vpn.restartIfActive() },
            onReset = { sni = ""; prefs.customSni = ""; dlg = ""; vpn.restartIfActive() }
        )
        "ep" -> TextDialog(
            stringResource(R.string.conn_endpoint), ep, stringResource(R.string.conn_endpoint_hint),
            onDismiss = { dlg = "" },
            onApply = { ep = it; prefs.customEndpoint = it; dlg = ""; vpn.restartIfActive() },
            onReset = { ep = ""; prefs.customEndpoint = ""; dlg = ""; vpn.restartIfActive() }
        )
        "proto" -> AlertDialog(
            onDismissRequest = { dlg = "" },
            title = { Text(stringResource(R.string.conn_proto)) },
            text = {
                Column {
                    listOf(
                        "auto" to R.string.proto_auto,
                        "masque" to R.string.proto_masque_chip,
                        "wg" to R.string.proto_wg_chip
                    ).forEach { (code, res) ->
                        Row(
                            Modifier.fillMaxWidth().clickable {
                                proto = code
                                prefs.protocol = code
                                dlg = ""
                                vpn.restartIfActive()
                            },
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            RadioButton(selected = proto == code, onClick = null)
                            Spacer(Modifier.width(12.dp))
                            Text(stringResource(res), modifier = Modifier.padding(vertical = 12.dp))
                        }
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { dlg = "" }) { Text(stringResource(R.string.btn_cancel)) } }
        )
        "keys" -> ConfirmDialog(
            stringResource(R.string.conn_reset_keys), stringResource(R.string.conn_reset_keys_q),
            onDismiss = { dlg = "" },
            onOk = {
                dlg = ""
                vpn.stop()
                account.resetKeys()
            }
        )
        "all" -> ConfirmDialog(
            stringResource(R.string.conn_reset_all), stringResource(R.string.conn_reset_all_q),
            onDismiss = { dlg = "" },
            onOk = {
                dlg = ""
                if (vpn.active) vpn.stop()
                prefs.resetAll()
                onResetAll()
            }
        )
    }
}

/** «Параметры DNS»: свой DNS внутри туннеля. */
@Composable
fun DnsScreen(prefs: Prefs, vpn: VpnController, onBack: () -> Unit) {
    var on by remember { mutableStateOf(prefs.customDnsOn) }
    var dns by remember { mutableStateOf(prefs.customDns) }
    var edit by remember { mutableStateOf(false) }

    SubPage(stringResource(R.string.conn_dns), onBack) {
        NoteText(stringResource(R.string.dns_note))
        RowDivider()
        SettingSwitchRow(stringResource(R.string.dns_use), checked = on) {
            on = it
            prefs.customDnsOn = it
            vpn.restartIfActive()
        }
        SettingRow(
            stringResource(R.string.dns_server),
            value = if (dns.isEmpty()) stringResource(R.string.dns_default) else dns,
            onClick = { edit = true }
        )
        NoteText(stringResource(R.string.dns_soon))
    }
    if (edit) {
        TextDialog(
            stringResource(R.string.dns_server), dns, stringResource(R.string.dns_hint),
            onDismiss = { edit = false },
            onApply = { dns = it; prefs.customDns = it; edit = false; if (on) vpn.restartIfActive() },
            onReset = { dns = ""; prefs.customDns = ""; edit = false; if (on) vpn.restartIfActive() }
        )
    }
}

/** «Исключённые маршруты»: подсети, которые идут напрямую. */
@Composable
fun RoutesScreen(prefs: Prefs, vpn: VpnController, onBack: () -> Unit) {
    fun parse(s: String) = s.split(',', ';', ' ', '\n').map { it.trim() }.filter { it.isNotEmpty() }
    var routes by remember { mutableStateOf(parse(prefs.excludedRoutes)) }
    var add by remember { mutableStateOf(false) }

    fun save(list: List<String>) {
        routes = list
        prefs.excludedRoutes = list.joinToString(",")
        vpn.restartIfActive()
    }

    SubPage(stringResource(R.string.conn_routes), onBack) {
        SectionLabel(stringResource(R.string.routes_list))
        RowDivider()
        routes.forEach { r ->
            Row(
                Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(r, Modifier.weight(1f).padding(vertical = 14.dp), style = MaterialTheme.typography.bodyLarge)
                IconButton(onClick = { save(routes - r) }) { Icon(Icons.Filled.Close, contentDescription = null) }
            }
            RowDivider()
        }
        NoteText(stringResource(R.string.routes_note))
        Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(10.dp)) {
            Button(onClick = { add = true }, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.routes_add)) }
            OutlinedButton(onClick = { save(parse(Prefs.DEFAULT_ROUTES)) }, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.routes_default))
            }
        }
        Spacer(Modifier.height(24.dp))
    }
    if (add) {
        TextDialog(
            stringResource(R.string.routes_add), "", stringResource(R.string.routes_hint),
            onDismiss = { add = false },
            onApply = { v ->
                add = false
                val ok = Regex("[0-9a-fA-F:.]+(/[0-9]{1,3})?").matches(v)
                if (ok && v !in routes) save(routes + v)
            }
        )
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

putv app/src/main/java/app/hydra/BootReceiver.kt <<'HYDRA_EOF'
package app.hydra

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.util.Log
import androidx.core.content.ContextCompat

/** После загрузки телефона (и после обновления приложения) сразу поднимает VPN. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val a = intent.action ?: return
        val ok = a == Intent.ACTION_BOOT_COMPLETED ||
            a == Intent.ACTION_MY_PACKAGE_REPLACED ||
            a == "android.intent.action.QUICKBOOT_POWERON" ||
            a == "com.htc.intent.action.QUICKBOOT_POWERON"
        if (!ok) return
        val prefs = Prefs(context)
        val replaced = a == Intent.ACTION_MY_PACKAGE_REPLACED
        if (!prefs.autoStart && !(replaced && prefs.wantConnected)) return
        if (VpnService.prepare(context) != null) {
            Log.w("Hydra", "автозапуск: нет разрешения на VPN — открой приложение один раз")
            return
        }
        prefs.wantConnected = true
        try {
            ContextCompat.startForegroundService(
                context,
                Intent(context, HydraVpnService::class.java).setAction(HydraVpnService.ACTION_START)
            )
        } catch (t: Throwable) {
            Log.e("Hydra", "автозапуск: " + t.message)
        }
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
fun DiagScreen(prefs: Prefs, vpn: VpnController) {
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
        RainbowText(stringResource(R.string.diag_title))
        Text(
            stringResource(R.string.diag_sub),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(14.dp))

        // Что делает сам туннель Гидры (проверяется изнутри, а не снаружи)
        HCard(accent = NeonOrange) {
            SectionTitle(stringResource(R.string.diag_tunnel_title), NeonOrange)
            if (vpn.state == "up") {
                StepRow(StepState.Done, stringResource(R.string.diag_proto), stringResource(protoRes(vpn.strategy)))
                StepRow(
                    if (vpn.colo in blocked) StepState.Failed else StepState.Done,
                    stringResource(R.string.diag_dc),
                    coloLabel(vpn.colo)
                )
                StepRow(StepState.Done, stringResource(R.string.diag_ping), stringResource(R.string.diag_ms, vpn.rttMs))
            } else {
                Text(
                    stringResource(R.string.diag_tunnel_off),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 6.dp)
                )
            }
        }
        Spacer(Modifier.height(12.dp))

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
                SectionTitle(stringResource(R.string.diag_direct_title), NeonGreen)
                Text(
                    stringResource(R.string.diag_direct_hint),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 4.dp, bottom = 4.dp)
                )
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

// ---------- Полная диагностика и отчёт ----------

data class DiagCheck(val name: String, val ok: Boolean, val detail: String)

private fun tcpCheck(host: String, port: Int): Pair<Boolean, String> {
    val t = System.currentTimeMillis()
    return try {
        java.net.Socket().use { s -> s.connect(java.net.InetSocketAddress(host, port), 4000) }
        true to ((System.currentTimeMillis() - t).toString() + " ms")
    } catch (e: Exception) {
        false to (e.message ?: e.javaClass.simpleName)
    }
}

/** Набор проверок «мимо VPN»: DNS, HTTPS, API регистрации, сервер MASQUE, IPv6, обычный сайт. */
suspend fun runFullDiagnostics(ctx: android.content.Context): List<DiagCheck> = withContext(Dispatchers.IO) {
    val out = mutableListOf<DiagCheck>()
    val base = runDiagnostics()
    out += DiagCheck(ctx.getString(R.string.chk_dns), base.dnsOk, if (base.dnsOk) "${base.dnsMs} ms" else ctx.getString(R.string.diag_fail))
    val httpsDetail = if (base.httpsOk) "${base.httpsMs} ms" + (if (base.colo.isNotEmpty()) " · ${base.colo}" else "") else ctx.getString(R.string.diag_fail)
    out += DiagCheck(ctx.getString(R.string.chk_https), base.httpsOk, httpsDetail)
    val api = tcpCheck("api.cloudflareclient.com", 443)
    out += DiagCheck(ctx.getString(R.string.chk_api), api.first, api.second)
    val ms = tcpCheck("162.159.198.2", 443)
    out += DiagCheck(ctx.getString(R.string.chk_masque), ms.first, ms.second)
    val v6 = tcpCheck("2606:4700:4700::1111", 443)
    out += DiagCheck(ctx.getString(R.string.chk_v6), v6.first, v6.second)
    val web = tcpCheck("www.google.com", 443)
    out += DiagCheck(ctx.getString(R.string.chk_web), web.first, web.second)
    out
}

/** Тип текущей сети (без самого VPN). */
fun networkType(ctx: android.content.Context): String = try {
    val cm = ctx.getSystemService(android.content.Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
    var wifi = false
    var cell = false
    for (n in cm.allNetworks) {
        val c = cm.getNetworkCapabilities(n) ?: continue
        if (c.hasTransport(android.net.NetworkCapabilities.TRANSPORT_VPN)) continue
        if (c.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI)) wifi = true
        if (c.hasTransport(android.net.NetworkCapabilities.TRANSPORT_CELLULAR)) cell = true
    }
    when {
        wifi -> ctx.getString(R.string.net_wifi)
        cell -> ctx.getString(R.string.net_cell)
        else -> "—"
    }
} catch (t: Throwable) {
    "—"
}

fun fmtBytes(n: Long): String {
    if (n < 1024) return "$n B"
    val u = arrayOf("KB", "MB", "GB", "TB")
    var v = n.toDouble()
    var i = -1
    while (v >= 1024 && i < u.size - 1) { v /= 1024; i++ }
    return String.format(java.util.Locale.US, "%.1f %s", v, u[i])
}

/** Строки журнала с ошибками и предупреждениями. */
fun journalErrors(): List<String> = try {
    mobile.Mobile.getJournal(0).lines().filter { it.contains("✘") || it.contains("⚠") || it.contains("⛔") || it.contains("ошибк", true) }
} catch (t: Throwable) { emptyList() }

/** Текст отчёта для разработчика: версия, устройство, состояние, проверки, журнал. Ключи и токены не включаются. */
fun buildReport(ctx: android.content.Context, prefs: Prefs, vpn: VpnController, account: AccountController, checks: List<DiagCheck>): String {
    val sb = StringBuilder()
    sb.append("Hydra report ").append(java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US).format(java.util.Date())).append('\n')
    sb.append("device: ").append(android.os.Build.MANUFACTURER).append(' ').append(android.os.Build.MODEL)
        .append(", Android ").append(android.os.Build.VERSION.RELEASE).append(" (API ").append(android.os.Build.VERSION.SDK_INT).append(")\n")
    sb.append("core: ").append(try { mobile.Mobile.version() } catch (t: Throwable) { "n/a" }).append('\n')
    sb.append("state: ").append(vpn.state).append(", strategy: ").append(vpn.strategy).append(", colo: ").append(vpn.colo)
        .append(", rtt: ").append(vpn.rttMs).append(" ms, rx/tx: ").append(fmtBytes(vpn.rxBytes)).append(" / ").append(fmtBytes(vpn.txBytes)).append('\n')
    if (vpn.message.isNotEmpty()) sb.append("message: ").append(vpn.message).append('\n')
    sb.append("network: ").append(networkType(ctx)).append('\n')
    sb.append("account: masque=").append(account.id.take(8)).append(" wg=").append(account.wgId.take(8)).append('\n')
    sb.append("settings: protocol=").append(prefs.protocol).append(", channel=").append(prefs.channel)
        .append(", blockedColos=").append(prefs.blockedColos).append(", allowColos=").append(prefs.allowColos)
        .append(", fallbackAny=").append(prefs.fallbackAny).append(", customSni=").append(prefs.customSni)
        .append(", customEndpoint=").append(prefs.customEndpoint).append(", customDns=").append(if (prefs.customDnsOn) prefs.customDns else "off").append('\n')
    if (checks.isNotEmpty()) {
        sb.append("\n--- checks ---\n")
        checks.forEach { sb.append(if (it.ok) "OK   " else "FAIL ").append(it.name).append(": ").append(it.detail).append('\n') }
    }
    sb.append("\n--- journal ---\n")
    sb.append(try { mobile.Mobile.getJournal(600) } catch (t: Throwable) { "" })
    return sb.toString()
}
HYDRA_EOF

putv app/src/main/java/app/hydra/DiagnosticsScreen.kt <<'HYDRA_EOF'
package app.hydra

import android.content.Intent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch

/** «Диагностика»: состояние, проверки, ошибки, журнал, отчёт. */
@Composable
fun DiagnosticsScreen(
    prefs: Prefs,
    account: AccountController,
    vpn: VpnController,
    onBack: () -> Unit,
    onErrors: () -> Unit,
    onJournal: () -> Unit
) {
    val ctx = LocalContext.current
    val clipboard = LocalClipboardManager.current
    val scope = rememberCoroutineScope()
    var running by remember { mutableStateOf(false) }
    var checks by remember { mutableStateOf<List<DiagCheck>>(emptyList()) }
    var base by remember { mutableStateOf<DiagResult?>(null) }
    var quick by remember { mutableStateOf(false) }
    var copied by remember { mutableStateOf(false) }

    val onWord = stringResource(R.string.diag_on)
    val offWord = stringResource(R.string.diag_off)
    val dash = "—"
    val stateText = when (vpn.state) {
        "up" -> onWord
        "connecting" -> stringResource(R.string.vpn_connecting)
        "reconnecting" -> stringResource(R.string.vpn_reconnecting)
        "failed" -> stringResource(R.string.vpn_failed)
        else -> offWord
    }

    SubPage(stringResource(R.string.menu_diag), onBack) {
        SectionLabel(stringResource(R.string.diag_sec_conn))
        RowDivider()
        SettingRow(stringResource(R.string.diag_conn), value = stateText)
        SettingRow(stringResource(R.string.diag_proto), value = if (vpn.strategy.isEmpty()) dash else stringResource(protoRes(vpn.strategy)))
        SettingRow(stringResource(R.string.diag_strategy), value = if (vpn.strategy.isEmpty()) dash else vpn.strategy)
        SettingRow(stringResource(R.string.diag_dc), value = if (vpn.colo.isEmpty()) dash else coloLabel(vpn.colo))
        SettingRow(stringResource(R.string.diag_ping), value = if (vpn.state == "up") stringResource(R.string.diag_ms, vpn.rttMs) else dash)

        SectionLabel(stringResource(R.string.diag_sec_dev))
        RowDivider()
        SettingRow(stringResource(R.string.diag_nettype), value = networkType(ctx))
        SettingRow(stringResource(R.string.diag_ip), value = base?.ip?.ifEmpty { dash } ?: dash)

        SectionLabel(stringResource(R.string.diag_sec_cfg))
        RowDivider()
        SettingRow(stringResource(R.string.diag_id), value = account.id.ifEmpty { dash })
        SettingRow(stringResource(R.string.diag_id_wg), value = account.wgId.ifEmpty { dash })

        SectionLabel(stringResource(R.string.diag_sec_stats))
        RowDivider()
        SettingRow(stringResource(R.string.diag_rx), value = if (vpn.active) fmtBytes(vpn.rxBytes) else dash)
        SettingRow(stringResource(R.string.diag_tx), value = if (vpn.active) fmtBytes(vpn.txBytes) else dash)

        SectionLabel(stringResource(R.string.diag_sec_tools))
        RowDivider()
        SettingRow(
            stringResource(R.string.diag_quick),
            stringResource(R.string.diag_quick_sub),
            value = if (quick) "…" else null,
            onClick = {
                if (!quick) {
                    quick = true
                    scope.launch { base = runDiagnostics(); quick = false }
                }
            }
        )
        SettingRow(
            stringResource(R.string.diag_full),
            stringResource(R.string.diag_full_sub),
            value = if (running) "…" else null,
            onClick = {
                if (!running) {
                    running = true
                    scope.launch {
                        checks = runFullDiagnostics(ctx)
                        running = false
                    }
                }
            }
        )
        SettingRow(stringResource(R.string.diag_errors), stringResource(R.string.diag_errors_sub), onClick = onErrors)
        SettingRow(stringResource(R.string.journal_title), onClick = onJournal)
        SettingRow(
            stringResource(R.string.diag_share),
            stringResource(R.string.diag_share_sub),
            onClick = {
                val text = buildReport(ctx, prefs, vpn, account, checks)
                val i = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
                try { ctx.startActivity(Intent.createChooser(i, null)) } catch (t: Throwable) { }
            }
        )
        SettingRow(
            stringResource(R.string.diag_copy_report),
            value = if (copied) stringResource(R.string.diag_report_copied) else null,
            onClick = {
                clipboard.setText(AnnotatedString(buildReport(ctx, prefs, vpn, account, checks)))
                copied = true
            }
        )

        if (checks.isNotEmpty()) {
            SectionLabel(stringResource(R.string.diag_full))
            RowDivider()
            checks.forEach { c ->
                SettingRow(c.name, value = (if (c.ok) "✔ " else "✘ ") + c.detail)
            }
            NoteText(stringResource(R.string.diag_direct_hint))
        }
        Spacer(Modifier.height(24.dp))
    }
}

/** Только сбои из журнала. */
@Composable
fun ErrorsScreen(onBack: () -> Unit) {
    val clipboard = LocalClipboardManager.current
    var lines by remember { mutableStateOf(journalErrors()) }
    SubPage(stringResource(R.string.diag_errors), onBack) {
        SettingRow(stringResource(R.string.errors_refresh), onClick = { lines = journalErrors() })
        SettingRow(stringResource(R.string.journal_copy), onClick = { clipboard.setText(AnnotatedString(lines.joinToString("\n"))) })
        if (lines.isEmpty()) {
            NoteText(stringResource(R.string.errors_none))
        } else {
            SelectionContainer {
                Text(
                    lines.reversed().joinToString("\n"),
                    fontFamily = FontFamily.Monospace,
                    fontSize = 11.sp,
                    lineHeight = 15.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.fillMaxWidth().padding(16.dp)
                )
            }
        }
    }
}

/** Полный журнал. */
@Composable
fun JournalScreen(onBack: () -> Unit) {
    SubPage(stringResource(R.string.journal_title), onBack) {
        Column(Modifier.padding(12.dp)) { JournalCard() }
    }
}
HYDRA_EOF

putv app/src/main/java/app/hydra/HomeScreen.kt <<'HYDRA_EOF'
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private val TitleBlue = Color(0xFF3949D8)

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

        Spacer(Modifier.weight(1.1f))
        Text(
            "WARP CLAUDE",
            color = TitleBlue,
            fontSize = 40.sp,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.weight(0.9f))

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
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import kotlin.math.PI
import kotlin.math.sin

/**
 * Что делает Гидра. Головы зажигаются по очереди и остаются гореть:
 * аккаунт готов — у левой горят глаза; регистрация — левая дышит огнём;
 * подключение — к левой добавляется правая; «подключено» — горят все три.
 */
enum class HeroMode { Off, Registered, Registering, Connecting, Connected, Failed }

private class HeadSpec(val eyes: List<Offset>, val mouth: Offset, val dir: Offset)

// Координаты — доли картинки hero_hydra (глаза, пасти, замочная скважина).
private val LEFT = HeadSpec(listOf(Offset(0.155f, 0.345f)), Offset(0.1125f, 0.4418f), Offset(-0.85f, 0.45f))
private val CENTER = HeadSpec(listOf(Offset(0.452f, 0.297f), Offset(0.554f, 0.297f)), Offset(0.5f, 0.4418f), Offset(0f, 1f))
private val RIGHT = HeadSpec(listOf(Offset(0.845f, 0.345f)), Offset(0.873f, 0.463f), Offset(0.85f, 0.45f))
private val KEYHOLE = Offset(0.49f, 0.713f)

// Огонь везде огненный: от белого жара к оранжевому и красному.
private val FIRE_IN = Color(0xFFFFF4B0)
private val FIRE_MID = Color(0xFFFF9A2E)
private val FIRE_OUT = Color(0xFFE8341A)

// уровни: 0 — тёмная, 1 — горят глаза, 2 — спокойный огонь, 3 — сильный огонь
private fun levels(mode: HeroMode): Triple<Int, Int, Int> = when (mode) {
    HeroMode.Off -> Triple(0, 0, 0)
    HeroMode.Registered -> Triple(1, 0, 0)
    HeroMode.Registering -> Triple(3, 0, 0)
    HeroMode.Connecting -> Triple(2, 0, 3)
    HeroMode.Connected -> Triple(2, 3, 2)
    HeroMode.Failed -> Triple(0, 0, 0)
}

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
            if (mode == HeroMode.Failed) {
                val red = Color(0xFFFF5A5A)
                head(LEFT, red, t, 1)
                head(CENTER, red, t, 1)
                head(RIGHT, red, t, 1)
                keyhole(red, t, 0.6f)
            } else {
                val (l, c, r) = levels(mode)
                head(LEFT, NeonAmber, t, l)
                head(RIGHT, NeonPink, t, r)
                head(CENTER, Color(0xFF4DFFD0), t, c)
                val k = maxOf(l, c, r)
                if (k > 0) keyhole(if (c > 0) NeonGreen else NeonAmber, t, if (c > 0) 1f else 0.6f)
            }
        }
    }
}

private fun DrawScope.at(o: Offset) = Offset(o.x * size.width, o.y * size.height)

/** Светящиеся глаза (level ≥ 1) и огонь изо рта (level ≥ 2; 3 — сильнее). */
private fun DrawScope.head(h: HeadSpec, eye: Color, t: Float, level: Int) {
    if (level <= 0) return
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
    if (level < 2) return

    val strong = level >= 3
    val len = size.width * (if (strong) 0.36f else 0.22f)
    val n = if (strong) 40 else 24
    val dir = h.dir / h.dir.getDistance()
    val perp = Offset(-dir.y, dir.x)
    val origin = at(h.mouth)

    // раскалённое свечение у пасти
    drawCircle(
        brush = Brush.radialGradient(
            listOf(FIRE_MID.copy(alpha = 0.55f * pulse), Color.Transparent),
            center = origin,
            radius = len * 0.45f
        ),
        radius = len * 0.45f,
        center = origin,
        blendMode = BlendMode.Plus
    )
    // языки пламени
    for (i in 0 until n) {
        val ph = (t + i.toFloat() / n) % 1f
        val wob = sin(ph * 2f * PI.toFloat() * 2.2f + i * 1.9f) * len * 0.16f * ph
        val p = origin + dir * (ph * len) + perp * wob
        val pr = len * 0.20f * (1f - ph * 0.8f)
        val col = when {
            ph < 0.22f -> FIRE_IN
            ph < 0.55f -> FIRE_MID
            else -> FIRE_OUT
        }
        drawCircle(
            brush = Brush.radialGradient(
                listOf(col.copy(alpha = 0.95f * (1f - ph)), Color.Transparent),
                center = p,
                radius = pr * 2.1f
            ),
            radius = pr * 2.1f,
            center = p,
            blendMode = BlendMode.Plus
        )
    }
    // искры
    val sparks = if (strong) 10 else 5
    for (i in 0 until sparks) {
        val ph = (t * 1.5f + i * 0.37f) % 1f
        val side = sin(i * 12.9898f) * len * 0.35f * ph
        val p = origin + dir * (ph * len * 1.25f) + perp * side
        drawCircle(FIRE_IN.copy(alpha = 0.9f * (1f - ph)), size.width * 0.006f, p)
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

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import android.telephony.TelephonyManager
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
        private const val CHANNEL = "hydra_status"
        private const val NOTIF_ID = 1
    }

    private val handler = Handler(Looper.getMainLooper())
    private var netCallback: ConnectivityManager.NetworkCallback? = null
    private var cellCallback: ConnectivityManager.NetworkCallback? = null
    private var forceCell = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        goForeground(getString(R.string.notif_connecting))
        val prefs = Prefs(this)
        if (intent?.action == ACTION_STOP) {
            stopVpn()
            return START_NOT_STICKY
        }
        // перезапуск системой (intent == null) — только если пользователь хотел VPN
        if (intent == null && !(prefs.wantConnected || prefs.autoStart)) {
            stopVpn()
            return START_NOT_STICKY
        }
        startVpn()
        return START_STICKY
    }

    private fun buildNotification(text: String): Notification {
        val pi = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Builder(this, CHANNEL)
            .setContentTitle("Hydra")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
    }

    /** Постоянное уведомление держит сервис на переднем плане: система его не убивает. */
    private fun goForeground(text: String) {
        try {
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Hydra", NotificationManager.IMPORTANCE_LOW)
            )
            val n = buildNotification(text)
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(NOTIF_ID, n)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "передний план: " + t.message)
        }
    }

    /** Раз в 3 секунды: обновляет уведомление и, если ядро остановилось, а VPN нужен, поднимает заново. */
    private val statusUpdater = object : Runnable {
        override fun run() {
            try {
                val raw = mobile.Mobile.engineStatus()
                val p = raw.split("|")
                val text = when (p.getOrElse(0) { "off" }) {
                    "up" -> getString(R.string.notif_up, p.getOrElse(2) { "" }, p.getOrElse(3) { "0" }.toIntOrNull() ?: 0)
                    "reconnecting" -> getString(R.string.notif_reconnecting)
                    "failed" -> getString(R.string.notif_failed)
                    else -> getString(R.string.notif_connecting)
                }
                getSystemService(NotificationManager::class.java).notify(NOTIF_ID, buildNotification(text))
                if (raw.startsWith("off") && Prefs(this@HydraVpnService).wantConnected) {
                    Log.w(TAG, "ядро остановилось — поднимаю заново")
                    startVpn()
                }
            } catch (t: Throwable) {
            }
            handler.postDelayed(this, 3000)
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
            mobile.Mobile.setProtocol(prefs.protocol)
            mobile.Mobile.setCustomSNI(prefs.customSni)
            mobile.Mobile.setCustomEndpoint(prefs.customEndpoint)
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

        // свой DNS (внутри туннеля) или по умолчанию Cloudflare
        var dnsAdded = 0
        if (prefs.customDnsOn) {
            for (d in prefs.customDns.split(',', ';', ' ', '\n').map { it.trim() }.filter { it.isNotEmpty() }) {
                if (!d.matches(Regex("[0-9a-fA-F:.]+"))) continue
                try { b.addDnsServer(d); dnsAdded++ } catch (e: Exception) { }
            }
        }
        if (dnsAdded == 0) {
            b.addDnsServer("1.1.1.1")
            b.addDnsServer("1.0.0.1")
        }

        // подсети, которые идут напрямую, мимо VPN (Android 13+)
        if (Build.VERSION.SDK_INT >= 33) {
            for (r in prefs.excludedRoutes.split(',', ';', ' ', '\n').map { it.trim() }.filter { it.isNotEmpty() }) {
                try {
                    val parts = r.split("/")
                    if (!parts[0].matches(Regex("[0-9a-fA-F:.]+"))) continue
                    val len = parts.getOrNull(1)?.toIntOrNull() ?: if (parts[0].contains(":")) 128 else 32
                    b.excludeRoute(android.net.IpPrefix(java.net.InetAddress.getByName(parts[0]), len))
                } catch (e: Exception) { }
            }
        }
        if (v6.isNotEmpty()) {
            b.addAddress(v6, 128)
            b.addRoute("::", 0)
            b.addDnsServer("2606:4700:4700::1111")
        } else {
            // IPv6 в аккаунте нет: всё равно забираем ::/0 в TUN, ядро его отбросит —
            // иначе IPv6-трафик пошёл бы мимо VPN
            b.addAddress("fd00:7a7a::2", 128)
            b.addRoute("::", 0)
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
        handler.removeCallbacks(statusUpdater)
        handler.postDelayed(statusUpdater, 3000)
    }

    /** Оператор сотовой сети (MCC+MNC, без разрешений): у разных операторов разный DPI. */
    private fun cellOperator(): String = try {
        (getSystemService(TELEPHONY_SERVICE) as TelephonyManager).networkOperator.orEmpty()
    } catch (t: Throwable) { "" }

    /** Отпечаток Wi-Fi: шлюз + DNS (SSID без разрешения на геолокацию недоступен). */
    private fun wifiPrint(n: Network): String = try {
        val lp = cm().getLinkProperties(n)
        val gw = lp?.routes?.firstOrNull { it.isDefaultRoute }?.gateway?.hostAddress.orEmpty()
        val dns = lp?.dnsServers?.joinToString(",") { it.hostAddress.orEmpty() }.orEmpty()
        Integer.toHexString((gw + "|" + dns).hashCode())
    } catch (t: Throwable) { "" }

    /**
     * Ключ сети для памяти стратегий: "wifi:<отпечаток>", "cell:<MCC+MNC>" или "default".
     * Сам VPN не считается. При принудительном канале — всегда сотовая.
     */
    private fun currentNetKey(): String {
        val op = cellOperator()
        if (forceCell) return "cell:$op"
        return try {
            var wifi: String? = null
            var cell = false
            for (n in cm().allNetworks) {
                val c = cm().getNetworkCapabilities(n) ?: continue
                if (c.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
                if (c.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) wifi = wifiPrint(n)
                if (c.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) cell = true
            }
            when {
                wifi != null -> "wifi:$wifi"
                cell -> "cell:$op"
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
        Prefs(this).wantConnected = false
        try { stopForeground(STOP_FOREGROUND_REMOVE) } catch (t: Throwable) { }
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
        handler.removeCallbacksAndMessages(null)
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

enum class Dest { Home, Advanced, Conn, Dns, Routes, Apps, More, Diag, Errors, Journal }

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

    Box(Modifier.fillMaxSize().statusBarsPadding()) {
        when (stack.last()) {
            Dest.Home -> HomeScreen(prefs, account, vpn, onAdvanced = { go(Dest.Advanced) }, onDiag = { go(Dest.Diag) })
            Dest.Advanced -> AdvancedScreen(onBack = { back() }, onConn = { go(Dest.Conn) }, onMore = { go(Dest.More) })
            Dest.Conn -> ConnScreen(
                prefs, account, vpn, onBack = { back() },
                onApps = { go(Dest.Apps) }, onRoutes = { go(Dest.Routes) }, onDns = { go(Dest.Dns) },
                onResetAll = onLanguageChanged
            )
            Dest.Dns -> DnsScreen(prefs, vpn, onBack = { back() })
            Dest.Routes -> RoutesScreen(prefs, vpn, onBack = { back() })
            Dest.Apps -> SubPage(stringResource(R.string.conn_apps), onBack = { back() }, scroll = false) { AppsScreen(prefs) }
            Dest.More -> SubPage(stringResource(R.string.adv_more), onBack = { back() }, scroll = false) {
                SettingsScreen(prefs, account, onLanguageChanged)
            }
            Dest.Diag -> DiagnosticsScreen(
                prefs, account, vpn, onBack = { back() },
                onErrors = { go(Dest.Errors) }, onJournal = { go(Dest.Journal) }
            )
            Dest.Errors -> ErrorsScreen(onBack = { back() })
            Dest.Journal -> JournalScreen(onBack = { back() })
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
        get() = sp.getBoolean("auto_start", true)
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

    /** Пользователь нажал «подключить» и не отключал: держим VPN, пока он сам не выключит. */
    var wantConnected: Boolean
        get() = sp.getBoolean("want_connected", false)
        set(v) { sp.edit().putBoolean("want_connected", v).apply() }

    /** Протокол: "auto" (оба, запасной подхватывает), "masque" или "wg". */
    var protocol: String
        get() = sp.getString("protocol", "auto") ?: "auto"
        set(v) { sp.edit().putString("protocol", v).apply() }

    /** Свой SNI для туннеля MASQUE ("" — по умолчанию). */
    var customSni: String
        get() = sp.getString("custom_sni", "") ?: ""
        set(v) { sp.edit().putString("custom_sni", v).apply() }

    /** Свой адрес сервера MASQUE: "IP" или "IP:порт". */
    var customEndpoint: String
        get() = sp.getString("custom_endpoint", "") ?: ""
        set(v) { sp.edit().putString("custom_endpoint", v).apply() }

    /** Свой DNS внутри туннеля: IP-адреса через запятую. */
    var customDns: String
        get() = sp.getString("custom_dns", "") ?: ""
        set(v) { sp.edit().putString("custom_dns", v).apply() }

    var customDnsOn: Boolean
        get() = sp.getBoolean("custom_dns_on", false)
        set(v) { sp.edit().putBoolean("custom_dns_on", v).apply() }

    /** Подсети, которые идут напрямую, мимо VPN (Android 13+). */
    var excludedRoutes: String
        get() = sp.getString("excl_routes", null) ?: DEFAULT_ROUTES
        set(v) { sp.edit().putString("excl_routes", v).apply() }

    fun resetAll() { sp.edit().clear().apply() }

    companion object {
        const val DEFAULT_ROUTES =
            "10.0.0.0/8,100.64.0.0/10,169.254.0.0/16,172.16.0.0/12,192.0.0.0/24,192.168.0.0/16," +
            "224.0.0.0/24,240.0.0.0/4,239.255.255.250/32,255.255.255.255/32,17.249.0.0/16"
    }

    fun defaultBlockedColos(): String =
        try { mobile.Mobile.defaultBlockedColos() } catch (t: Throwable) { "DME" }
}
HYDRA_EOF

putv app/src/main/java/app/hydra/SettingsScreen.kt <<'HYDRA_EOF'
package app.hydra

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.sp
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
    var proto by remember { mutableStateOf(prefs.protocol) }
    var editing by remember { mutableStateOf(false) }
    var conf by remember { mutableStateOf("") }
    val ctx = LocalContext.current
    val openVpnSettings: () -> Unit = {
        try { ctx.startActivity(Intent(Settings.ACTION_VPN_SETTINGS)) } catch (t: Throwable) { }
    }
    val openBattery: () -> Unit = {
        try {
            ctx.startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:" + ctx.packageName))
            )
        } catch (t: Throwable) {
            try { ctx.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) } catch (t2: Throwable) { }
        }
    }
    val openAutostart: () -> Unit = {
        try {
            ctx.startActivity(
                Intent().setComponent(
                    ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")
                )
            )
        } catch (t: Throwable) {
            try {
                ctx.startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + ctx.packageName))
                )
            } catch (t2: Throwable) { }
        }
    }
    var note by remember { mutableStateOf("") }
    var wgNote by remember { mutableStateOf("") }
    var showLicenses by remember { mutableStateOf(false) }

    val copiedMsg = stringResource(R.string.account_copied)
    val nothingMsg = stringResource(R.string.account_nothing)
    val importedMsg = stringResource(R.string.account_imported)
    val wgCopiedMsg = stringResource(R.string.wg_copied)
    val wgNothingMsg = stringResource(R.string.wg_nothing)
    val wgImportedMsg = stringResource(R.string.wg_imported)
    val scheme = MaterialTheme.colorScheme

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 18.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {

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

        // Протокол
        HCard(accent = NeonCyan) {
            SectionTitle(stringResource(R.string.proto_title), NeonCyan)
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(
                    "auto" to R.string.proto_auto,
                    "masque" to R.string.proto_masque_chip,
                    "wg" to R.string.proto_wg_chip
                ).forEach { (code, res) ->
                    FilterChip(
                        selected = proto == code,
                        onClick = {
                            proto = code
                            prefs.protocol = code
                        },
                        label = { Text(stringResource(res)) }
                    )
                }
            }
            Text(
                stringResource(R.string.proto_hint),
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

        // Конфигурации WARP (WireGuard): создать как wgcf или импортировать свою
        HCard(accent = NeonAmber) {
            SectionTitle(stringResource(R.string.wg_title), NeonAmber)
            Spacer(Modifier.height(4.dp))
            Text(
                if (account.wgId.isEmpty()) {
                    stringResource(R.string.wg_none)
                } else {
                    stringResource(R.string.wg_ok, account.wgId.take(8))
                },
                style = MaterialTheme.typography.bodyMedium
            )
            Text(
                stringResource(R.string.wg_hint),
                style = MaterialTheme.typography.bodySmall,
                color = scheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp, bottom = 8.dp)
            )
            Button(
                onClick = { account.registerWg() },
                enabled = !account.wgBusy && account.wgId.isEmpty(),
                shape = RoundedCornerShape(14.dp),
                modifier = Modifier.fillMaxWidth().height(48.dp)
            ) {
                if (account.wgBusy) {
                    CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = scheme.onPrimary)
                } else {
                    Text(stringResource(R.string.wg_create))
                }
            }
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = {
                        val s = account.exportWg()
                        if (s.isEmpty()) {
                            wgNote = wgNothingMsg
                        } else {
                            clipboard.setText(AnnotatedString(s))
                            wgNote = wgCopiedMsg
                        }
                    },
                    modifier = Modifier.weight(1f)
                ) { Text(stringResource(R.string.wg_copy)) }
                OutlinedButton(
                    onClick = {
                        val text = clipboard.getText()?.text.orEmpty()
                        val err = account.importWg(text)
                        wgNote = if (err.isEmpty()) wgImportedMsg else err
                    },
                    modifier = Modifier.weight(1f)
                ) { Text(stringResource(R.string.wg_import)) }
            }
            OutlinedButton(
                onClick = {
                    if (editing) {
                        editing = false
                    } else {
                        conf = account.exportWg().ifEmpty { WG_TEMPLATE }
                        editing = true
                    }
                },
                modifier = Modifier.fillMaxWidth()
            ) { Text(stringResource(if (editing) R.string.wg_cancel else R.string.wg_edit)) }
            if (editing) {
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = conf,
                    onValueChange = { conf = it },
                    minLines = 8,
                    textStyle = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 12.sp),
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(8.dp))
                Button(
                    onClick = {
                        val err = account.importWg(conf)
                        if (err.isEmpty()) {
                            editing = false
                            wgNote = wgImportedMsg
                        } else {
                            wgNote = err
                        }
                    },
                    shape = RoundedCornerShape(14.dp),
                    modifier = Modifier.fillMaxWidth().height(48.dp)
                ) { Text(stringResource(R.string.wg_save)) }
            }
            if (account.wgId.isNotEmpty()) {
                TextButton(onClick = { account.deleteWg(); wgNote = "" }) {
                    Text(stringResource(R.string.wg_delete))
                }
            }
            if (wgNote.isNotEmpty()) {
                Text(
                    wgNote,
                    style = MaterialTheme.typography.bodySmall,
                    color = scheme.primary,
                    modifier = Modifier.padding(top = 6.dp)
                )
            }
            if (account.wgFailKind.isNotEmpty()) {
                Text(
                    failText(account.wgFailKind),
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
        HCard(accent = NeonOrange) {
            SectionTitle(stringResource(R.string.persist_title), NeonOrange)
            SwitchRow(stringResource(R.string.settings_autostart), auto) {
                auto = it
                prefs.autoStart = it
            }
            Text(
                stringResource(R.string.persist_hint),
                style = MaterialTheme.typography.bodySmall,
                color = scheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp, bottom = 8.dp)
            )
            OutlinedButton(onClick = openVpnSettings, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.btn_always_on))
            }
            Spacer(Modifier.height(6.dp))
            OutlinedButton(onClick = openBattery, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.btn_battery))
            }
            Spacer(Modifier.height(6.dp))
            OutlinedButton(onClick = openAutostart, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.btn_autostart_xiaomi))
            }
            Text(
                stringResource(R.string.kill_info),
                style = MaterialTheme.typography.bodySmall,
                color = scheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 8.dp)
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

private const val WG_TEMPLATE = """[Interface]
PrivateKey = 
Address = 172.16.0.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = 
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = 162.159.192.3:2408
PersistentKeepalive = 25
"""
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
import androidx.compose.material3.Text
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp

// Неоновая палитра Гидры.
val NeonCyan = Color(0xFF47D4FF)
val NeonViolet = Color(0xFFA98BFF)
val NeonPink = Color(0xFFFF7AD9)
val NeonGreen = Color(0xFF84E36B)
val NeonAmber = Color(0xFFFFC857)
val NeonOrange = Color(0xFFFF9A62)

/** Радуга для заголовков: голубой → синий → фиолетовый → розовый → оранжевый → янтарный. */
val RainbowColors = listOf(
    Color(0xFF4DD2FF), Color(0xFF7C8CFF), Color(0xFFB06BFF),
    Color(0xFFFF6BD6), Color(0xFFFF9A62), Color(0xFFFFD166)
)
val HydraGreen = NeonGreen

private val HydraColors = darkColorScheme(
    primary = Color(0xFF2F6BFF),
    onPrimary = Color.White,
    primaryContainer = Color(0xFF0F2A57),
    onPrimaryContainer = Color(0xFFCFE8FF),
    secondary = Color(0xFF3949D8),
    onSecondary = Color.White,
    tertiary = NeonGreen,
    background = Color.Black,
    onBackground = Color.White,
    surface = Color.Black,
    onSurface = Color.White,
    surfaceVariant = Color(0xFF1E1E1E),
    onSurfaceVariant = Color(0xFF9E9E9E),
    outline = Color(0xFF3A3A3A),
    error = Color(0xFFFF6B6B),
    onError = Color(0xFF410002)
)

/** Гидра всегда тёмная: неон на карбоне. */
@Composable
fun HydraTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = HydraColors, content = content)
}

/** Фон приложения: чистый чёрный, как у 1.1.1.1. */
@Composable
fun HydraBackground(content: @Composable () -> Unit) {
    Box(Modifier.fillMaxSize().background(Color.Black)) { content() }
}

/** Заголовок экрана: обычный жирный белый текст (имя оставлено для совместимости). */
@Composable
fun RainbowText(text: String, fontSize: TextUnit = 28.sp, letterSpacing: TextUnit = 0.sp) {
    Text(text, style = TextStyle(fontSize = fontSize, fontWeight = FontWeight.Bold, letterSpacing = letterSpacing))
}
HYDRA_EOF

putv app/src/main/java/app/hydra/Ui.kt <<'HYDRA_EOF'
package app.hydra

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.text.style.TextOverflow
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

/** Плоская тёмно-серая карточка (accent оставлен для совместимости и не используется). */
@Composable
fun HCard(
    modifier: Modifier = Modifier,
    accent: Color = NeonCyan,
    content: @Composable ColumnScope.() -> Unit
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
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

// ---------- Экраны настроек в стиле 1.1.1.1 ----------

/** Страница с серой шапкой: стрелка «назад» и заголовок. */
@Composable
fun SubPage(title: String, onBack: () -> Unit, scroll: Boolean = true, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surfaceVariant)
                .height(56.dp)
                .padding(horizontal = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null) }
            Spacer(Modifier.width(16.dp))
            Text(title, style = MaterialTheme.typography.titleLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        val m = if (scroll) Modifier.fillMaxSize().verticalScroll(rememberScrollState()) else Modifier.fillMaxSize()
        Column(m, content = content)
    }
}

@Composable
fun RowDivider() {
    Box(Modifier.fillMaxWidth().height(1.dp).background(Color(0xFF2C2C2C)))
}

/** Строка списка: заголовок, необязательные пояснение и значение справа. */
@Composable
fun SettingRow(title: String, subtitle: String? = null, value: String? = null, onClick: (() -> Unit)? = null) {
    var m = Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceVariant)
    if (onClick != null) m = m.clickable { onClick() }
    Row(m.padding(horizontal = 16.dp, vertical = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            if (subtitle != null) {
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (value != null) {
            Spacer(Modifier.width(12.dp))
            Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(0.6f, fill = false))
        }
    }
    RowDivider()
}

@Composable
fun SettingSwitchRow(title: String, subtitle: String? = null, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .clickable { onChange(!checked) }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            if (subtitle != null) {
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Spacer(Modifier.width(12.dp))
        Switch(checked = checked, onCheckedChange = onChange)
    }
    RowDivider()
}

/** Мелкая подпись раздела на чёрном фоне. */
@Composable
fun SectionLabel(text: String) {
    Text(
        text.uppercase(),
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurface,
        modifier = Modifier.padding(start = 16.dp, top = 22.dp, bottom = 8.dp)
    )
}

@Composable
fun NoteText(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)
    )
}

/** Диалог с одной строкой ввода: «Сбросить» / «Применить». */
@Composable
fun TextDialog(
    title: String,
    initial: String,
    hint: String,
    onDismiss: () -> Unit,
    onApply: (String) -> Unit,
    onReset: (() -> Unit)? = null
) {
    var v by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            OutlinedTextField(value = v, onValueChange = { v = it }, singleLine = true, placeholder = { Text(hint) })
        },
        confirmButton = { TextButton(onClick = { onApply(v.trim()) }) { Text(stringResource(R.string.btn_apply)) } },
        dismissButton = {
            if (onReset != null) TextButton(onClick = onReset) { Text(stringResource(R.string.btn_reset)) }
            else TextButton(onClick = onDismiss) { Text(stringResource(R.string.btn_cancel)) }
        }
    )
}

/** Подтверждение опасного действия. */
@Composable
fun ConfirmDialog(title: String, text: String, onDismiss: () -> Unit, onOk: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(text) },
        confirmButton = { TextButton(onClick = onOk) { Text(stringResource(R.string.btn_ok)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.btn_cancel)) } }
    )
}
HYDRA_EOF

putv app/src/main/java/app/hydra/VpnController.kt <<'HYDRA_EOF'
package app.hydra

import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
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
class VpnController(private val ctx: Context, private val scope: CoroutineScope) {

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

    var rxBytes by mutableStateOf(0L)
        private set
    var txBytes by mutableStateOf(0L)
        private set

    val active: Boolean get() = state != "off"

    /** Применить изменённые настройки: если VPN включён — переподключить. */
    fun restartIfActive() {
        if (!active) return
        scope.launch {
            stop()
            delay(1200)
            start()
        }
    }

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
        rxBytes = p.getOrElse(5) { "0" }.toLongOrNull() ?: 0L
        txBytes = p.getOrElse(6) { "0" }.toLongOrNull() ?: 0L
    }

    fun start() {
        Prefs(ctx).wantConnected = true
        ContextCompat.startForegroundService(
            ctx, Intent(ctx, HydraVpnService::class.java).setAction(HydraVpnService.ACTION_START)
        )
    }

    fun stop() {
        Prefs(ctx).wantConnected = false
        ctx.startService(Intent(ctx, HydraVpnService::class.java).setAction(HydraVpnService.ACTION_STOP))
    }
}

/** "wg/162.159.192.3:2408/q3" -> "WireGuard", "h3/..." -> "MASQUE·H3". */
fun routeLabel(strategy: String): String = when (strategy.substringBefore("/")) {
    "wg" -> "WireGuard"
    "h2" -> "MASQUE·H2"
    "h3" -> "MASQUE·H3"
    else -> "—"
}

fun protoRes(strategy: String): Int = when (strategy.substringBefore("/")) {
    "wg" -> R.string.proto_wg
    "h2" -> R.string.proto_masque2
    "h3" -> R.string.proto_masque
    else -> R.string.proto_unknown
}
HYDRA_EOF

putb app/src/main/res/drawable-nodpi/hero_hydra.webp <<'HYDRA_EOF'
UklGRpSWAABXRUJQVlA4IIiWAACwBgKdASr4AfIBPjEYikMiIaEgpnIbEEAGCWJrk/Mwsp4qC1F6
TKFn+3epexSFiHJ/ruxlHh5b8j/8Z+1vzSWd+2/4H/Lf3z/Bf+j/O/Nf/l/bN7ddc/937lfgh83/
Xv8t/h/3Q/vP///833Q/3P/C/y3vB/Sf/Q/zH7sfQJ/Hv5p/kv7r/if+d/gf///+PrT/Y/3s/uR/
2/YX/V/73/2f8D++fy//7n/jf6P9//mn/av9n/vf8t/jP//9An9B/uX/Q/O745fZK/c//4e4V/Uv
8n/5vZ8/4//1/2X+4///0gf1X/Xf/P/Uf7b/8//H7FP57/gv/D+1////8H0Af+P//+9N/AP+j///
YA87fvX/svUX8p+1njH+T/cP57+//uF/iPkK/e7hn9j+qvUr+U/f79V/hf3O/v/v/+0vnj84v9n1
C/yn+jf5z+7/uB/ff3b5tK4//X9Q73O+4f8L/L/vf/ufhI+7/8/px9tf+v/jfgC/p39r/33+H/J3
22PEQ9V9gT+gf4X/1/6T8rvph/wP/l/uvzH9236F/r//X/oP9d8h380/uX/M/w/+l/+P+d////08
nnoxfu2aHBu0KPUEf//nUH+Hm2PPSfvlflXkT8kqv0WEjwuEQufGfnaFwJrTg6HzTwcQco3/VVVl
8eyn4o2+S/kbX/X/vzSNrwb2xS/SaRtS4VY9xiqZ6zh8qSXLTw4otjbfVIsqMrpuSHOPaXaWVuIZ
ADa9EVsYZXM5iXgYFI6qt7WPUP1TsDVHrsPxF6u2D6/XEEL6kzXSIwSEP3uEjPgMwtaY0LcxZXmB
qk9VvethxSHE68bSRI7cvh/YYbb/qkNUVCFWIW4hpxB+m0m3YmTErsoG2AkJ1d2f8KlZAzMWv5xx
5NLS1c5L2cf6ZadrPcnfXPQOKNNbnCZo7cKSfKxDXKDBmHq1K0ipqbQmaggcf8VsEPi+Yv4mj5zd
576ipcEbGYQ9/PbeYHoerGlFyx6eCozoUixRtvKZeCkWIhLgpL6yTX05lA8skYDSis3+8ci9FsHa
H+ahQV4H4kgpaNMFHAHXiET+sO2dvVD+ZMFH9Nvv/TfYFmnIHOBaIsgi+FBuNz9VLabtOIlhNJPO
a4d1729VicL+LMqjT2wwrbSmkVUTT7m+UZGZZ352YW7Td2/Vr8B/iXVqoRoF21a17byPVbvy7+JO
c+buuINOamh5aYWZzV8e0PjxzgEJoOU+9IkmuQxu35uM49h2zRIUWYQDDigcsJmwr29Yw6XQLmu5
kuqyf8B89ycOwhS1sYdyseCH9XsFsmZeZi/yIneh9gCzFSPihutjFjvD4eGsDi16w26wEcMrkMBi
cqPSvsrfT6PQOGrV1v882rQzeAUzfXCSWsoHqLN4c//pzCUY/KOF73Ki1RyEI/DqyBmaE2otEFMB
8al08M4QaKPmrR1DOoFipy9ejX0J3ACSxdth+42dDlbwlYxGRG3OwlDiEcrKdYB2QeAzm/lz0VY1
SAOEidtikwVDHOCpkJblhQgf+Q//9QmQp/0U7R/IbECkLQlocsFU5Vad6FPuqI9hdfMA9DNKplS4
2HMIJZqsoRQ6bs+DFrzwJLcvGPXiwVJmmn0fHF9TWjdzTejCuTZ3VNRMKVH2/wROer62jwRXq9hR
wGcIik5bznsvadZ6lyx+YOIkIL0xZnfz3bvkKU7Qp5//fA925/T/6wDQg89Rw1XIgzD3n1WwI+Id
MeZAsxkmmT9aBu+aSjEV7je36NhPj6MXYXuMdYr3YUKhWjl2xc2Zm8OFroeTuYqgCIa8mAAL6gcQ
tkFZV2KEhgd+L8cuXmc7XK2x30cp9URryI3z5OfaZph4Y+TsZ3A4Kv5sV8P1MRAdRXqnG5erQQn7
EX9dFn4Yk/ityYmGbz8EynuIxSTK0kUKHTmTm2R48UO8vtq3BuwyGQvB5ZS/S1qrsLeksN6ftcIZ
xurDPkJK86w0f7f5I04nxcuof5w84A9/XaNcrIEpiaHsxDLknkTftTSYo/Y4fsCdxvU+rDlWSAT0
u/Ulx6wGMVG3PQxTGmqIqFMerVt6p/0Qafsl+FwoSI2RTHdTyIybWn5PlVrOgfpyTkO7NnGbT+NN
WRv2zx1mpYXyHTjSUSh93PlVy5JFQV+dhyH9cSm2GeHx+acpMtOxptKJ76y3rRSqdXN7WT5puinX
GezguD/NpxvQrpc4SdHdO2mTGhEMfMvkkOBI5mN0zHGtmkP9LcoYdURUu8qroHT3GgxW1BuBUg6s
eRolWCb9DtliUJ9GJ/+71DdPFZloK81ylOLsDlijNZiB+2tf06X8HQkusJw1rWlAqfIyoifAjSj5
1u33UIG7G4gj0GUKq0iW2MyUm8GDEDCKGET+s4+fK25tEQqr4mnjk5SPpe2DyO4AQzuWsF+dsEqz
/gmEhv4xa24QW2XJ/xEPW15ujSET3prv9IEQerh3PI4LFNosb760CW0sKSHJ3sMQj1hjP1u2OBKl
K8Csk1Nr50MeROjf7LC3CnF4f7ffOtNIPr87hn4UoAlKBC/VVH8IajFaf5iALIWXKTY7w7j+8jVO
rTzVMKvxx6WcCbfECKlkH2M1Cl1xSIkJPr4/9/KENCC6nzS6PVgnweqLBctYP+9QlWRaDJnHNwys
tDz2TFRMOiPbRJa0FJz/OYw1dKxTbLZh4T5mp9d66/lIFd9NBqnda/6VVIRV3YKAgl84UFAd1joG
jrqkO49dEjnUpIpA4MMpjP/oDLV8+uMTHrAg/Prb59/cvRrmJraomEy6OZj6m+/z5kXttKG6FHBP
KPmvpXbMRJp/XdeHaGQRJwtai1TRHyL/syKgwmtrp55/u3r02AF59gxPdRRyWvYSUlO6MCL9eKUo
sLV81lLC3+k1+MeTfDvbj199iI4NEJZ75sWk9t3RL3h8RoKPgEgWnSyIptmUXT//J7He+mua3sAc
1sLkpfr2xp9AMECB1hw3YS/cSsT4eU1S8HCKosX+G6gVNSFH7uymsL7Px9J6Cwb8TdfP2KlFDYN2
Xq9koSZVN1K8gO9RA0o9iif28qbNF0IjF0V5p76JQQELyLs40X3UlYAEblooX1WInpgeclzC10R/
OLGIwi/LXldKsXdaSursHFfah4mbWm6mSScJpvJDMRfohn+VbHvP34VsZQmXY+X4OfePGWtj/8uU
VdtVpPjPfVhWtAauAkxOsCIUjrXdnCMz7P9W8SbgTcRfTv8bZ/F7ibKG5sEjvvUxyOjL7pDF1TXB
mXrEY5f/7+twlwGx1P3EOA1tWC1qOmsflaA4W5IaMx9k9aSYPCRvwiF+SvinwGZ02Sl5bu2cLyi0
6SlaoePxqWj0L/VhF/lhmCuUAqiYcvtsgdMLyBrcqsxru7mA1wId7afoz/2lc4GGHq7eqRWi+uig
0TCQuJ/JsBj5Bs6arcZpZPbj1HPk9OfkE7qlqa6z+2jaBmldGzBlLNq1g2TBbyfsKM7hiM337w8e
wrTtxP0q0epectadmI+114+vKlCinO1sPTBMrqj4USDbZ4H/j8zdvL7Bhi747+9HD4ldfd/++T8h
yOdlGVm9dnecLcv5p8FPxG3BAttJxOeNfUrTf4tlVRU5db0EbV0hurpwIxx/0Nzoe69ZUD7LPQXZ
fp9CYWpr0Rv/GNte9bL9yDGS35Kg0dZmU3wYHGymrGVoF4EQUfS8cEobxQvw+sw+HxwhsKbrARqu
42Rqnu+sXOJEmfuE0JcGxc8e7At/r5ACgYIlgsIhaFpBHPgz4e/SYgLUCML8dxgBU6y2RHwi9RmJ
DW0gGretn96/CVr/+SdlsSI/9y5AwWSKu9S1ucpp5CNpM6R83T5OOyVu8p9CXFfBk8j9QmIWs0qu
Kf5/DDPcJhcU7EyNCxFEnbH/rSarGKMoNSyiC7A9Yotx3LgIvLFMz32r+L9fbb2jsWiydNrFa3BK
YoucxnnROJ2W4B4ZNY2VvKY8qZN2Y+TYLGR2yzojlDCFCKYdzIY4k7iMpE/DeIgZBcwHPyHWRXW7
VtNZoZsAmU87hvJhIkmnOlhUUKz2dSGW6a/tdwO3n1Yl5m8OkqaxGKKuspAX5IHQBe53s5By+jpb
3QjcQk5RFzdwRCwL+3J9vBXHjrJujFedkupxQh1YXYhGEK5u/uaU99vSuBpz6otqonTKAAnQor2H
j/A1aHW3zyXEaEsdTOhdeDZ67QG15JnCQ3o4fsytSn7gUUdOLN3u/1rJcaW6KB2O9xpcZCBu6UxB
dwSosV1ScC9gPeb3GOxhuh5r0MIWrT120YwkQaOtxkYnF2sBfdIK8Nn6thUuTqWIlRU3NmCTiUlz
py49P3pVGjoCMdSKzqWmkoRqTJs8I8nHWizIswmYBTnue0DjYbAZLNQzMygJqu1jaqD5yVj7bkip
VdPPKZGDA0D5yL/OiS+gGnzf7pGGfPqeDREaLRxqv//0cygB1N3BDGO33EOn3n3gxSDsK2/LpDLZ
cSSfYOqL7oMFWxXtLOrjFJ/Clk7VNjYoR/XN7cJOYJyHTUjoPP8lKW4X5CE4/PaxBtXeLeSviLbW
+Y+oK6CbawcKJdIzgiVQqQ03EHWcyhqy4rF0MOoGwwVMRq748faYuPkUi8MGEXyWt5NkGI4IlkUA
91SOwvCAZeY7aH27vht3qi++egMZVICJKvtN3HDw3kBsCkpXGJQ0zqk1n1yxpytw8Ji+1aOtn/Sw
8Ws48idmCl2GxQm6vv43D7eoL0xEew1e4JAiUPa7/8IpCUh85tfYO/VGjDtWwzQ3AY1zYGquP5SA
6qAB0HUskwkn6rATYjsKs+32wRQClMIa7dxHZ+kwxd2wIhP9amyZUQG15VfF6DP/W1qmZGj5dhHM
oA2dV9UyOWugl6zI0ulxjhM93tqy+thDXPOMEuPpq8jfxuF/+MswcpQfJE4a9HEmj5xGMzxPopge
JHGCtAqb+36RtMu6/yz2wRMdmK7QxkbEP+DIViT3o2/fPZadmvCmVVaAr9fTf56XVVcljWLcMaAV
THHsuiU2kW4WW5Etz0KUHF7MGb6PPHV9m5h33MVdb+lkKgnLkLj7Swj2YwrbLDT4OdI0tnCzM1Cl
WYXcFXp38DLoIMY5uJ3vfpxj0783DiMIi1cjHkoLsRDKxr4tJrsSwXr/H1Ac2IN+qmfFBX4f/EL6
u/Od3hpqtVL7FcTZcot8HUvKjnCTlKI/zttG0/dV2pGzCKpbx/vga0MqoONkRdSPdu364UvQA9Db
7Azdi7GJa9JT+zRo+1MJKbbvasrJzFhxv7xSNDQ4OSfk33SjSmVy7ndBeoO2PZ4j/6o/r0uCsPsc
g07f57+vk+SSqHW0E5bVQo1S9VQjfcuHLrwrGb8rt13oNvOLQpnarLxAF5aHUZjiA3Zm/XoG9uNU
hZ1sQPWdgQqxIbgtvsJOCHCxHDjWG/9PMkYG4T+r5ZYSSeOJ7LTzIJb8B+6DY/tYc04/SOEpeSAf
nQfeGiBiQX88o5VU//9O+H3Sd/23lpzW5/d4987+vxJWhXNPdlvqzDc6qNHZPwOxs8t2+OyYORJv
JuAI4ivVmH51txZ7A4m/QAAA/vjlvtwEnOsgdzqOg8ZjnR1c6ntAzjGVbIKTXiDwHx+He04q1j7Z
62rIaDAhfxhwEaRukOxbjBFHpvYtnmIrJ3+EErHh99BsQMTsNkKQ4Y380Whc5F0oVHr68TnwITB3
ll4GdoWed23C3D8VcSWXkd2vIEY+tQfZ9soLnP6NfcrXTtWN5sf+dEYMUHQxkF36XsNDnKYA6ZO3
ScX8vAYZ1Si/i2sFzI+QdnzyjYn+zkN0+ohUEmOd7bbhOI33O/XcwOryPHuOEPJd8mOysFJwB+tq
TghZYZyyYZ/it+gEKVSyh+S0mj68g+eWS6OkXOSiEuacUnzp66QqGs9mbEa2RCF9bgXWZ5yGxgr5
tdW8SfwdS21G8e2HfYUYgBdTaOETR7YXob4qwLQIWAv57TE/K1+jFSlpk1aoSXs3+c123lb6NfEb
SVr94AeHYePmny+487AYRg5+KLSh/GW5ggNwU1/tLV116yap/3Pfzb+C8jv1fg6NXr3t1ohMyRwd
ElrIvn8ZsHsVpE8mb7rN5oT33JLghqbhirAYCwgSiMbwEab34I7b3g56ge/2nx0P8WahwoUXz337
3qjCiDCBz46LaitdPzGNO77loP6O+/cwJcIbrwSd77Q4EW0LChJuUvqwlOFe4HrjJU7plTGjDku/
lVHTY9SyRydrJxgs6am/3rQlzDorX2BwdTLKmYDf50JYxnov9o736OCKOT5g46tuh/7NDDDy6CZ5
FUcolURM3W60LJgZFbVvCumE/wzFVcwDzb6Nl61I+XGHcbwGIChXfzPmveJsb8hQTExpoPhzC93z
XzBGQtBUFLL0ixLf5JZ3pHzwACMfmJ6H0JP7+ugVLAm/k0SCdvU4PxXLD4Be4XAO6MbdsPMBs0QM
/1W0IPlScy6CSA6vEZLUESgXed2WEiYq2Hf8qkTimuOd223oAKb6f6dS1UcCCZyF7btHdbEJUyC+
CCrjAoA3rAsoyfzhSlFYvdKHTHU5xC87kR+6KqkCE4oa9lJ9lmXUz/B++9L4At+aANJsC0XmJZ1Q
R/CGNZ2yWfM0lgdOlPrJyOHz1YyknUykwik8Smp2oToofFaEKYb7DuAo2Y3jsh4noErHFh0pGkxC
v+WdRWHtEs2gSFQwR5UdtJCA8jBKkZzZWo32D8eAyGLH0AH7WXTzFLel+wzC/H1yZN/SyU3O6h12
flpDj/qpepHuMWQmszCCnq3SoxUCdYSHNsVAGfw3l+4BMsh1DPxsuvlMPMJmuqxyCeEsr8I+XIZa
bW+TV8LN+RTMiAm5a73K8rbMcOS2nVU7FyDtDuBncRBvcZb10Fuwchtwvq2wcbabOc2yyThCKP8f
6rjsHogCl3uj3T6fUSjdYnQOGVf0DQLpouvktaHES2JfnoUNYUMCliOnCFNleMm5/bVgjvwml8Kn
ci96wluezgR78y39jUJbGMoklY7siiTI9RCSgKnoiVX1erVGBvyYVXdpkL4KJHK/NBVgiChdUPXR
GZD/T1CrwUrUVG3lcUgPTqoP/baz5VZ339H60n6ZDhmP3lq2v1obNoUVIDwxU2yme2Pgy01EKkkj
diu2FwHIM/VUr8HcA2W8jxLsHpoPSW63m5a/pfKL38mDexVpE3QrGBhSo/OMtPRyu0VCv5i4xFa7
YOEMX+JuXghp6SfRzjzUDsuWAW9VqXSPQP3l3+mKdo+OXuq9EapQDCdFWbPnjt6oXZWLtMyib39i
9GIkoMi3OFD/ZYSgGq31QQtvUiyzoTdVUq0dfFSC8NrhW7vvDKEMQ8J9oUIH6kVr0mU4eBG/o8VC
HugiOckh1NHTSUN2QVB4VLudOsUA1fzqmd85dDCvTAODm0sWfwKyfkmHYp4GNc2HiNLsBkOGiEwB
RFMs//z9Y0jUfO9BPsrr/c+50GZvKaR/bAZ2CU0axS/AZG02kkm7vPeMEv+IXhXCVt6TiR5bTB2Z
wdYkUlRcDcVJs6w48d3DabmiCtDT4MVRIlC0A/C6YI4o374L7F7j0oPc4+g+kLjncspyny9lp5KQ
HX7HC3VVJ1EyBsZSFt8JygnWr7o+ODLGwwZmjU6Y/odeDZr7rLJjqiu1VRwHWlnHwnpDq5Z9uBvW
Q5uh2MNi2vV3ihbQJPF6ZVQ6gULhTsS9dIQ7ezQFU+aXo3y8+R10ZJj+Gdx/z4OLEIFab+OoLHlc
Jm2zWG/OF++IuY6fx8GqUPBenobaJYL1+zt/b65FXbjopf1peGEVzC1p+XqzyUKLf5TZIXLXO/c9
S64ZGn2wmqUosjF+QuOuhA30QZpL91eUOj7JGxRbde+tSDcx9bQPe2UWzPjTWV3rxpZ95aTRpXj9
cwUTuvZwDilr+8YhNzPhdnyH2nx09eUD2FGExlbz7PZC+iV+5vp5+pLK40F3WJqsSSJLUiXBvgE8
KEkwxqeWlde4AHaZg/6mnStEa4RFHO0AqLYohoHfOC+uXOF9Qqmf95HeaofmUSayDmZPkCFgMinV
TwxI7k9ZUC/WSUPQAtEKVU3AMRGdV0dlrQoJglepU8fNe8u27iy0CffRf3z6LyO3gj151qWzwv0r
W3D4Tx1tLyZ34A6dSCcidzu89d5Fq54vS9in9x8d2VSR0PCBlflGn5OGBLcUubV7cCzRyRfRzdeG
BX3FIhcwrfQEqsLFvQx+oRyUdcPbd/5ZQ7Aq2EhWi3hBtsObXgHl5+PItfhCD+EKGIlRA2RYbi6M
s5pw5oEnPqejDJ0rrrTjefBL7VSq0LaocOYcONq9cyaI880fEracp3yUGhFMpuhV072EreTkl9z0
lklrrE0RMsu7N8Tb7R9YXOQ/NLPd9S9EXIyAeGdO6TIh93NUlC2bORHVhqKeUnId8lKvp0JnW/cq
iLm/ZbKFpNnZkcNHHmKrpTVwASNNuGvvZv/hrYomo7ltjUucdeJoT4wfBav2y18w0+fxQsYJ31yL
PhpaO0NeX+t88b3mK5F4sVfhkKZBSK+1JYyY1Z57Zt8hYHmwh5IGlAd5k3nWDLlvqc7MxnUobSJv
GuCFbg9b8FnfzuDOT3ZSFPBo72bRia7a8LoH+JrQ8cWDsNU4YBBd70MGtaYrn+U/tZtt9A6WDum/
GbLH+fvZ5fqug9Q5wnkwGKrQVIb1x7xDxeS/Q7+pnXvx6Bv7snM0K1PJcBcLCNJZOjNuGqrWVH4c
j8vJazyR7aANl7qWPe8264EwD3GvhNdkGTjvHcFY6Ag76Sbr18zagMrdPrciZQTP3weoCaFek4bT
2osWfOH6d/YVC4oB1aVNfGgiIj2qxTCaQgLuYAh0TqBV0aqZ91Nj6H5Wz9OXZsG7NhraU71m8CR0
QPIpktd6WV9cIRfSpCuepEJvE2ow0alfy/vFnPS2IIPUVyKDR05NtsaTp2XlxLaFrp3vkuKwB+wo
3yNyZr2XbfZCfRO0UaWD8z0QWryDMjAz36RdjYos4QSSod3BN4snxAHGTJo/eI7MIjKkwodBQcq3
sT1Let+H+n6uXVsbGGlAGQteEfkDZTl4F3FJzZdgIBT7vBKd/PdS6KXvmQtzOnE3OhjDTJs8ZQn3
UcMvi1vv2mQuU7iCVAh7rZiIPe68XrXs0ejlSGtZFULitFdxc9ihJ7GONwbZ/lW+6KYi8BcKDg/1
S/xxyrXDm++aqACJVStWMtyAnBOzId0kOzEookf/bPasW14Povt6CohUxmCkAph1maBmW9lwjJ3H
50oVEpUZZVFGyg5/XO+12VJRqVdxoxASIrV/qs1jSYv1+QVf600NpNdnPEpAmGT7BDCjG3R3rPt3
krL90bXfo/MBWrbC3TsryB/0hqOiPzn1ajQcolxSSdoWKtN98g6R5S3IYHgjlHXPJUZJv2efWiNV
BgFP+kTW/fPKP9/Tyo5L+n4hbHyvJY9XGsNusPKwRXoKERHBXnZltwH6xtjsLLAZ/iBkBc79Mus/
wTe+0nxMGS2fQveIgOLVp1eWbkEOsc+9i7Tj5m9XWxwiigbx2496Ae8sA00k5+sW0QQlP3CBT78p
lYvnU7Lov2Xt56sb3mfrNuHzUVmLbuq25cUDdZkLywlZzQ5BT+3xtz61h27R2gBw9mglJHpzjJ09
VdZY8FtGUHFJEwitkpl519/qGFIrx3R0yzSouW+yfaBekE5GmKlDnXqbisXyLVqY8sJ7QLUJqRt2
KnRPS/arQ7HbqYXqBLkDtr3Fja6hci2iqmoWGV71Owtyi6obSoMUF3iCdHzS1rG5Jx6z5WzS+XjK
8/QEh82oyM8cuRa0RTgvKRrflpd1KSIOp26LbbJFgf/hjvO31Hw84ZdtD8KF9hUX/+TtMlWEimOg
uYisWqx/w3mxdpjZCE0n9oD0V2R1KJVt1iALecwt4Fgcl/1W4DNQMJOY/ceTUskP27tFa3Yms9IC
YEGfCb1IfrW/B3v2iybjDMvL2GRByrD3okfoHsKr2u83DUGHDymv0SjGkHUWmnCwwe/wDlGgIVmr
e+yBeptgsyGo4xf63+jQeUoEeKGkSiP/Yr+rScJnvCZWzEfocraoWNQw+scAb9acprs098nUPyWX
rn4NNxeulNLE4hKt3yQVkysZ+khmC9pJRSBV+hAIbZv+BSd4NOwMVhi7rwYx90YwBxKteLZL77+8
PbK4PL10nWaCnNs3K5tyS7JeB86LScgUeKEyoGOXXknNH8caT3bt/qIZLYbU1wPQuyrhONeNkPd+
ysrCHa06Aga5yF9HWsRZRQt9sf8/kWQq7SdoO1Ej/YhRHZSJ8EZXirh6KEfYw4z3Xd0mwzvqO9iL
LgmKeY7FK24/BDMtGCjRPSytfjBfFK34s/eVSZq3ZRvSyVPia4QCQ8vOrcMHHYk/BSf3zb1Dlv4M
DvvtcvWwmOFgL2tVQcbOgLN+7LXrYy5Q81OsMZ3+5WPMCstv023ByQnQb5f9Ke9MhYr3TYFVVLx/
Sk/bUCiWYHONmRkCeTgZhSRLU3yih2eo5kQGMMepI6kGAWDYnVS4Kckn1FKaaq0qBYgL1TDuylun
KWOWZGqK8QUvcpCtDRE3qdQvIhFiClepfM4LJSz4sI+ljPdZQ1VcStyTuHc6IO/DD4ClVNXUiLdD
u2t0berd1pLojvxO71pzleAGFwXAcPbXMMy/O4afCNvrXyQOcdFvzzARMEfBWhqV3dkPU1Ecd7m4
IpgEBBEJ3qoc2ac2p5NBLrCnmlOytMU44YL5k1id/Jc06qRI91aHAq4nK1T167vHEN0HG1fJ5MlG
ZrZXnvcg1Vq2Co+lnzCfB7/MME+YlpFCQHHgYtYXf0cS3f1Tt/DdV4T/yF3a/7/ymZS8aDNnFL03
gQRZSwy64hXJMDvaVjr3sYPeEH+ONt+rZyllVXUfAoc9e3n0T4s7m+Sm/0x0C8gDAZLBZWJi0shg
T++PcfwgntBL67qLKTys4wPNoweWV9Aq0ZcmIVAT4uibLSJIJyNiVzUCJwQkaHKr/CfhRQwY7wB+
Agix/ReDlH0UkFle+ZzVCzyzzXz1CZmdfm1dUymawaYv+hs24jysJj18Kt8nl0bKGZhTx8o2GWcV
sux+FWgvvTd+NLWKGmCznm+BqdBzljopInPPTtobd0clV5OD5leVcnMeDmG9/XwK3A/nIxFOX0Gw
oXMcpNUsvf8CKP7M7L/iZPOY8TdsrmAcXjtNBMOFlY/Jy/eujB2I/AeIR2eNi+HPbzvTmy/YIEBn
9XIbxRDs48jExwkJ6SmFslESQuvgKaABf8//erBJnEWGIXr93NsIYMLyegQmAnThZvQPJz5Kx87G
A/50s+yicgffzwzo00z+jRSPKqHZBszkVjK5SDv04EHOfQhG/nKYLbR91H2iXdHvDrX5uJ2V4tjR
BaH+4FR4FFe0Bm3GKVgaEPyn1Pc0xotsv6StIDHYRY1xP3CAnWiLQrv6M/+jiuVs9O+bM6GjGyjG
55C09BDbog2pXSNq7bl1FMEbogmN5eTZl6e0My7oi37nzfIcX/w+T71aWmDWPf+6kwVo40W204C/
dPTSQH6nT31Sq+vHXHgSJ5Hn2UgLE3tEYb+dsWAKVuoghe8z+AhBWZgL5qwCOWR7L9ayF6iMc8DB
VQDQq3P6biT50C/O6YD6aHd3wG3OF6gupN2US4n0Gr0IIymB31yOqkAJ6s9J+ayI4dlZeyuznbbt
vtvkswFMyOu4pfASBja1t+XrTP0FAjUeU0dH2XqCkajXCDOnLB70FxYHpKv2IpGGNyXMC8+hf8pR
N+41dPPUIDZIjFcgzxEQmgxMSG6dwDoQTKr+FVR0eRyyrG+saraq9OhzRHgQtPOj2s7Oh1ftAhpL
SJ+gRmCBOhEcHapNA9FL1UpWNg0Pz63HdVTq6pzDl/uC3wJwCSrW6fb5xDi4lASHny85EOu5vX8e
ZlXuZSgKzwh1wLDiGlkl2WVChFL6Oq1hRmi+65bcqlIxrQ4T6KblS9Sq7EqEt5z1WBhqdoqdYKoj
M+v/Yhdv/sZSxdvJNENtE+NovQjcHDxIm6+V1zdV/0yGnkKIaWJaImhgFQPqNoKfTrgFhLxoXCsl
5gvQ8QHocgSdry0rXW/hoMSGnsEjswg03QR+Zd3ecXlu7ou5a/TCbToA7A9frDzkDcVIfNuWQHBm
xpm4SoQ/Lahe9pVijweCEoUdjHV8SU/gSNOlcrhV9TiCE89YG8BX8At1SD7jQGwsXdWcbaXITPNN
EJ4xHVx1+Ieo55Z+qE0O3EgIKa0GdLRHZKzRX1Pv3NATZzm+TctXPdaPTsQy8O2D/C2xh+BHFdl7
PE8ZGfPAUDxbH/dBlaEwFjtY0SuabXm+YxQ25iNKV6VlxlC+RkCuf33mgzbiyp/PCQ7HEfjZ93hz
ttpNJoLJcp1WasgmkOypz5htABNahGo2fpp/9JZoVIwi6uwLyIgsxxTXlRkpFH43gXmPzpGpeKeK
YHKGYyKFh6iSoXts9FF6nKNME+H/jCxxA/AAU1oSXcbAxZNz46zvfmI1UBLimA8GoOCcbx/UKbrW
EBta8cuh9DjJMBuQdHUZWcmaE38qxI6AKNSAQefLB0fbeVd6liqD5fT+X5aBzmduKIO0zlA03kif
8kXrJVmuzK1077ZM3PE7LTBp5Y7dLj+eOvdIVlDAwqjZwWJ2WJNALRbCVzRegUsDsRYp2z0nweTI
+GUQlsCYV8x0DeJiAZdGV8X57NWiMUTJSs/nu2qz92s6rbOekBO86zkGN12wlGXTyhEmoepgs/j2
Fp2Bi7vOxbDOkVsm1RezKvlkI7PV3m/bh0S/0bfZ75aTXrWl5K0e0UQ1yDq/crk6HY3t/FRBbZ5q
qDLTJTXMGvWr8LfOu/9PJrd10AaJDsUJoeaD8m4UJxnH+rwzcrqyupX901d2CidZDzqU3FJ4cMiu
OR7b9T5O7npt3HR0x+ipqT9fe4pfW4zHBhjArYDvtp+pQqpF3fzqdH3u98PkZfSgKB0JSmCblXCM
qjY/+PgBZ9gOedXvf59quBCi5FCKu0iU42EkmXq6dby/kV0ib/8d+VoILVpV0oNdZ+lUhgrTDbss
zqNLWgLG2ROy4YY9KV3LcvKIV2XJT/UmNF/RnfttisKWMwm8b7BNJmwYCHc+Fn6eqOmHYhGOCCBU
ZnJiVi0nabI2xKT0oxBNlCdqCAZ+4d0OoN+J4Il6/52jJTvY0GDHoQt8BnyUKEDVf8OEtBHP3Etc
M43TfA+609SNGCVCUGIED2QX+/W4NXXYh512Anqw+SncQX29bsDtlF5L9UhalxxRn03YLUkxM/y/
1+L83FvvO6PlF4WJvrMPZ1No5j+EtEb/x5z7bro+l/cVepLztb7BztFK97MWDO7yfuHJpbsUcMQe
bfyqN2sOsvpxRnl3PJIV4zXMeYIUCfwvIAr97CfcksF7L0H/fPMe/Lfkk8Ny76gMs2dPpUN+SjQ/
sNsQcn0VKci0XHY3ZJGcI/HDo8bh60cXtxxmRFz8RH9jMbvnTdFbAmgEBTHo8ggUTFmVyJ9plmO1
8+25F9ycLfuAdgXfUMm63EqjTyFZMT1YfEt+o+2s2xdyLWIxDCq6bgId7S281ib6afPa95jdJ+Zg
Mnyuc5xnSf+RCqyzL9brLiwIQwl46jS7jE8SVBKz4ToFEDEkIlx7/05r8uYLQm3B/ixV6gcVOrQ+
Bm574i8+J0yXYtxp/1EqBL0nPMgdMYYQ1PDNI4F/5q+ls5M7EeMPRXtsYvBGS7o44pXdCanuq3ku
5XoVtpdU2Lh/mn2flqxucabjsLfQFr34FWbAlYAd5lNAogsYN4YEhlGuMAYQ1flwScEfxxRRab6o
8z0C9v7gdaKFJHUIiYk+UrvltNhpFhSafuebHKZUQFvoEy/tCEiyWj1qG5dW37Ndz1TQA1yPuInp
vuFVjON1VXfF8Ca+iT7knrRFIH+EYkSjESAcOgvMaJjEHyIxmRuV3f1+Ma1mjfKJ8g4VUcJ7bDvw
1fHL3gvtx1dLRaAd2dQODr9hhLYb3Xnrs3OJRefwGtRdW7/GOYlLRgFvGEXL5qNgdBIZTZRwDRFJ
nYY5nRa9fWi7qCqcxIwXL4F9huatn8om9gRRQFSeDyZ2u1rwI55OBrjffscbw6wjyu8t77A69+FF
P7CE46OKBMHX4ouvxWaaKQLZaD6fAgm9Smx0FPFW0ruJ/6HOWHeFWxGC3uyD2jZ4OhfOLp80VeiI
VQySN27Kr+wIu53IwWww1exB5GnXkJcdM4zzvASbpXc6R+q4KS/DiI6sOgV45q/69LZ3SyUlT+z3
0ZvaqfMyQUwjBQ0fDS1u1VXsxIOh5yOgDub6Nz2tTVWkpWog5XxDRzhdhavCtQpB3RHaubbeSjw6
xa7Ql20vJaJGntgs8gn/VZYjemPbSGkF4Uvv6iY8383BPwqehdGiCEKRuv6ww36xolxH+Oqce/7G
XIWwInEm041a7KUV6hA0ctmaBGb/eXW4I6+9wTm+UTuwvHKM6kZlP6FT5b0FuWIqMhAxXzdxQeqI
IGO7aUFcviEq/hIOfdcY3gNdwFo4/RnC0G8KprIRoI6SoJdR2VDU28EO278mumAm3exeLs74+ms0
xCruAOZZqYiEAzajBgDBm8ftt8Jb6OkueggijrwUqDsCvCAplCOabrFi2+tFENSUv/W/4ogDP6WT
rJQQOkJuX939n/dP8K5EssDtfRvn87kp0sbRVMkel3Cjjvs3+ScNm+lWfn+b7Z+l4xHiBQ0qEIf1
oCaApaXFxy4jKPjlE5tSeRVc2bP/meWBJrT8kODFINXi3HbFCbmU/WAgRAkwaGcU7DBTfnjo7iFT
Ed7tk6G7+910cVsdMQNy11KGRFAFOrOsirLXp+x95SGGh4r1HvOTrEw3Ylfh3CzmXJes4OTLyNTT
UTHSoRtg1WczaL4ikS/uZmCu6A5a2dMm05zyshdNmILfX0tYJJcNi9YdufqLiQQ5FnETYs9mf3AC
KeA0XVC4o+hcSLxshEXu+AWIiRvC7g/VpvnreSR85wkU+nDJZiJFGyci5UK4k1uAKtcBxeF6JErf
OKVpWviH9kM2vmaYmQ/CoNP8b3s9AnlbTdAp6oflf+G82c+LZ17RSh6KjhVf1nGGL89uCDinAFV3
U7MCDXFtpEbz28eKYrcztOK/j+4Qfg5KkqXN9ML1x/1si0qo3HOjT/lm8u1q8PT2G1c5rpuxIWvL
Qpdfkh1AjQm640L+jJCwqqaQolfeZ6uw+53n/iPu8AmQwK89WYvIjXwoNQqnEWRquqTo9SATW06l
7NmP2ni55oKf2GRno1O5ff0DmQKNHZLqL4mtZ4U/wlTy2KnokzIGt+AsV+zpAR9It9JgmPXAUWiA
AB4K/URY7S7S6JDiLyahw3oUL5L756QAeHTQb3o61xZWHYLzYI9nI9nQI58xuWl/z6NnRJhFbqBC
l/ahcbOwrUrGtMFcB8/lt7U6Gml3blNvLedkT+bjiRwTLdAAQT0nRq1RtxnUhOT5Xz1XkNyN2dv+
66WO6T2DnRIfnfROt3yd2h5D6aiUINXBIU04WySvEO2OVfB3wMivWG1N0p2xf6PD6TX17JhGL8Ka
JtwVEcInUfCu2LqyPt+FZq19F05YVmXazzXo1hZ3degOelHDF+6fm71Q9G1dnP21Mgi7rTA+aIeU
o/Qwc8woZaGzmaLkfjgg0owFLTTYtKxweUmm1H+MQY+m4ZlJbHLPqDlHMC0uxZsdIW1ZTHJb1F7d
c2Y60c4C+keLT2ah0wE3WCLF4xsXkmML0bp0rJMxLQcWbbAlWnGTAYaR4P4W8yhU/x3w9puwYGaM
yM+1sp9EG4F4U6w5BkleAOE+oC5+xRsTjuySVw4PYtHHUS27WMd5t26rQCUHJIwUU2HUKRzv/fRc
SRlNMCfLxlt3w++QxdWjsNehlOS9H5b2YXw2tvbmQyMQkf3sJNZZvmX+KhpGA+th5lv5XlFDZ8ut
YDRW0yMxKshSpC3NXLuR8r2d2sBmrIvRa0fICyyBdNnGQlY6qtdfR9KXdkaC2oZOgbdlHk9mcsPI
Rwz5tt9qdSfEvVS5Sil7pypX5BsU6HMD4N0SMkG+4CqwNk42GvKMKyDF3hiPzs8HXq5rPkC3vYrq
pP8Ud1C7Oa7suH6wLds6FMYMdpLhJj523VIV/0D9G0k8GvRMKW9HjAu18HBp6DVSv6mES545IFtM
FHdz5DaA8xxJWmxYG36Nk9jLhibQVMAn18Z9xbItVeKkUAZ1nJFZyzHWYLF7cwde2NymzpreRh2S
AuYMh+8e+meWXygcyQrVibg4LW7EY3/IH+7oE5AV6S7vlVduuqy+rtgmNyZekaG8LQUaJYSGxD+W
jrS10xcVoQ6h8eAdflR558UYLVRZzVUQ+F1xTFH7ByNPS/PmP1EwcZ5gesQqJ9OC8SZl5tNRn6Ry
eVYUIpC3jvHeqbNvJ5FO/U7Kqup18KQL2UotglwoC4oagg7ehTL/3RtgnjyNImBXkwixVMQ4n3f4
tVXQ04BrreE/2HnYeN2rz/4iRD0GJKQlnMCkkye3HiVlhVuZ3RxFTQ3e+S9Pz+1ACkuqmbE3QSQ8
3QYt62VKxFEXO9MVk9AZRc11Ifk7vY5Wt4n6S8r25O8C+spxInFfMIKhB5I1oc7BJflOr1OuiiVq
isa1gD0WMK8YlWBY7pYPCXYVr24IhgFb9Y/NRedyGY+J/ij56+IUJFR1Q+ToNx0GxUph6e/3f9ll
aQRJGwUYrzNI/NM7KM6asodVkITO8JoYcuOEFk4TQv/x4J40vf4IZhOfizoDNuBqEO6nWtBoMu/V
Gl+hEXPLwcu44gyE3hYizo0aXBKAIZVHvMRcY52+BCLLbUqHS5ph1xV50DzboHF/31kxpaL9Lkvy
OMGNiuv4m0/bfJYVg/9RHrcSAiB4XpBSOPc2pMNmAr58c2KqNnV/et5ktwhY5m+/TxbS8I95wa0T
BTH1arF58W8b4C3Mo26bPkRLBzYbqCqLeSQEDeKPehcj11PcB498va7nOsNvdFVaVO9DkCQoqi9E
F5plYtdFyeJiCyeDs0am8lqdtD/otr1TZ7o3OvRzDU3SFqAzgqWIpQT+P42NHKPJmnLYAgC4aFAT
YUb7xNk+jqKQPQJ61anbuv5DcaY7a63k6e2PXUadxjvP7vhetP1cAg6GLCxUFvhbac++jXxsKNhS
96wfw+u1Hx1bvkEjEDpH4aaeFVEecS4/E3qmVnejAxKYK86MoB3QzLiASZkNFWetTaYfFxTKK2fU
d7ltZ24gmwUomr3vI15e2ZXwfa/8v46r8vwjUO6cAffz2Iws4rmwzZKaVlbqKvkaGLoszBU87BiE
cf/YFWlhXMOFfrHxNovwAOn2KBCHJFNszRqs6FafCMJGMirjGrMuvspOkRRzLi0dAKzveed+7atZ
fA0DHFITF5sVR3rqy6NF/h6ThiRkkCPgZDlxwPDTEkxapcKQeq6SoV3PKTmix1yMPfxxbhRqnkRS
DypQ6vuhSO8ZZMquCsRIUyls1xeeALZMWRZ56UIGg2zBSR2KqZ7Vsych49jlDojVvGA4FOIbqO1d
i4WLKfb836Q+SeEqPsnC6oBrzv/SxOYdYPn/lGl5NLxLjKu+nqrshENBmfI2XfmMU8pvOrVcNhhO
A5z297ETHQXqz3aFuh2m61Gtlbh2t0xRosoFJSUoyeHPYshjAMj2jsG54iMMqcWCjdBtD8jFps38
yjCPH0FQdAHz2ezHszxFF8A3KFAvRZkw9Bw4l9Fo3MsMnZpoaXOt+WbJL7ceaBNIZSCmqJW6qcez
1uk/6ogHMdgAfVzLdlG39v4DWFHBk4qKWPLR/DtIGAc17GlgvBnFWPioD/HBZzZVOhWCfSxM35qq
pT5OTgRHENNKXsc6bxf5o8KGyV8fhgKLAWgZcXUowhQWQgxfY6aCBUlB3taer9/3KvvV//0NufGa
e06M//eCpLWMGckwXSQOybZk45IKISWhZgQoCSGmce/1hD6Y6d5lGYtB3jM2irbNOOSzm6LxOkMI
f3L2qO+c/RbRB9oDdBIYJOxonob2tXZxPnWoyifcnOjBrcXVssSOGju+VNOUqQn2dqTO2AoWFvWV
D0qZsDb06cdbbItW+ic5xmehSFeuQ3RYE6gkLWj+KJJ9PjSgh5T18qD9j8VMEbAKv9B7FHiwKMxr
9uGrcW9n+pWjrxwpmPu7zB/5ocQx5/7vq/8rVXAK08Q4AWoZMZcvLTKYB9xtzGyYKCqd2thLd2It
pDORv338HiZhDQ+o3cdEUmZYE6OPiOMisgUJFIS5pXM2d9N3lNyShll1a8Ovr0Y3OOvYwXJH3vxx
GZ1YPOKPDAooqF/ZSecOoYjliezTYasixy8fVfL3Zn9BRn8OEKkxAl8XjdjBYawzEc4I+9iOJ2d+
C9oZHrAotAN5W87nBRwUF4FG0bFhwTeBgyCRbVdL69YzWZCBq5EOjnKF/mgUgQg50Lt6qnFMPoc5
KdD/tSwAUO7NGuCFfeIfJ/o4SqhRdfVPDLjtdgxCG9AI4645Jn2WvRiHTTsMtEQqu5MTP8i1+3eY
D6yRxzl0ORi5w//xuCCyDbTJYQAgDzYpK9uYLZbg0BwU7WzQZba9CcSt99rrj9g376aP6driuaED
cHG9uVRLxnhEr35erjPxNFR9+X+kyufyoL+y55g6rDynVnvYxIo710IlkVEbbP85a96NdNpqkt8l
8j5Y5rhuHou9BKq6j22kG8cXlUZ6NJQN+BcnNt4eQbQTS4IUM7Fjf1Bt51LTNs6fMrF0emFevn4G
b4pZQa2HcLge06JSUSbHvX4gbXiUIodzObq33s61dWvrnhcecJJIM9rnmhV+AMSI8lMYX9eOrcTY
+JkUAjQa1Qb4WQ+2pijgBGrwJjEVZZCJrSb/0rUtQ0cG6Sex2P2xEadLm0gHN9PbQmbB5wXou7ja
B7GDwHMXQPX9PNsJ1vvCzThB4elW4xWllPHbo0tKpIgAyMTKg6Hk31ov+LkXSzFPP0V4L+v4LuE2
d1Gt8FX/LFkbFLcyMVdbmoCfEjIzIlq1suokLN4b6EshED9/dntcwTPxtBjmehD0coN+3w2ZuwNJ
xr6aNxFaNoMFNcoD05dK5bb4YXJxhOOEQQvx8vjnzWiNJCcyQ5gyn7gGReRryvhwGO0aZnixONJR
GchjuuDb6ek6Q5+PdJMKnN6ZryMiAJOoJClkeA9D4ai4fGnDwW6+M2zgXhBSoaQo20oubMsL1sBg
F/E65JIZm6nlAzwwf2xPhzxlUuYshO1v+t84zw2lg8WI12352iT7ZfynVCSVoM26dP86plAhruCL
rjeZlbRrIXSNdwWIszbGwk2V+FpkbBD6dqxg/PuRt+uLCxAbXwIp64LRje/4sRYHYIzbSJo/Fwnc
+8Rb/TFjpz4qzFZfuIw8k7xH30qyqdyAlLNEusXhu04a9xKD4RzyKphjThrVZdDqj1TSvIXlCZSQ
6/3a5HRaOhIluN0z1oUQYw3eEYPA7+Pvn+B6mrkpMNuOrLoQaUmhpnxu4aIJl/6GwMznTs9Pszhv
yPjKSxb/XxiszVIWs4T284NDanbOjrmwZw/VdNBPmF94h5yetjH94n+AxCxzi1WH0c1qoCHwEEiP
hUxOieYOm2jb7S6SG+bQv/8tvLQLk4up1XP9PRmINH2tQD+RGHusY+xAqcbTC2abrUCYlOUtx56j
4T2E6jSU0xb8U7CtfjQBJjf/HM4g0GosmeG0ffU9hAJZF58V1NsPhVfqkWAEsELvdjWE6gFwMnR/
uCHmjor8cmc4n6kGYxCM75BMCNOYRzN3gWYclqc09LCXg0n4Gn9ujlGM+psgMGDtHknCUnZu9dMm
R86un21i4eZSPYo6mskbFZOwmQLBXN/nXlBk9LVa61c1Tr2Jh0olhIfgazvryj2mCzbrhitI81e0
wGO98qzUY47sM8f8vAxQ1aOHR34fv/LJHZqnynS61KJYZbxeiZkGFpZB8D+VIxXzedVKWjJc/lTJ
rIG5N3uyLj634s2WY22kvnrIURHSvw+Jrh8n26B0bVM7CHdPXX0GK5O00IA2KqRHgaKIMUXYgbSj
gRxPnv/IhXGU+LTps7aXf0cJ74w01xLSjTPYd2W7tH1L7c6AygnfIJrpapl9p9L8MLpqokKxIU6f
1atkkv3KioEcgm4UGEFvRy16myE3QmBvInwmDkGHJBo+RKih0iOfKzVG7S+ivYOAmIYgG1nVlQkO
rERL44BoUoA+pv5bcn2hp0U0zRYI2L6m7ZnII6dOqzN0PmVpZpfnsytckGz9ntJsc55A2FIrORiU
cKWD49Mp21+XcSwzbmbH4vVxZAzzkFq3OWwBOJpZQ7gtuz0x7yQD+1/AfwqirJ7v5UWw0ZQIl+40
07dxJIEsAUTjSMTkiPTeV1VW0DQ4gnzw2AMVxmWZMR+uauHX6EWlp1inDBADMZdyKZyPCNyAdB2V
1lWT3AEH7H30ZFTLAmI96FZerjxmpJbsT70g9SzRYGhiCE2v3CNm5ixro5m/+3DD+RdwWuk2tgMc
8b27kGW9EtsDny92FgaoIfkcb54NNUL6jZ/PcrIBGx6pxfqe8uAVkeGktshjw4AstmcvM+vXiSt5
sLeiQhjnnuokhzzBHExjpItIgLOH+ms/W1Y+Y6RtE8I64ecI1ayo/pJ8pkrb0Xx5BF35YoU2VS2b
/Qo8Lq+wvP3aX6LY0/noSAbTonmx5tauyhGttCgzKzniNO2Xh09qgO+6DgBfxZAZCKafylwUIDSc
cj9rMExU6FgWgJh4aHWBaLWIUmJ9Htn5NT648cbGI47BGoLy10BecP0pnppeg6Lk3k9HLUgFMM6b
SMiDyXN2Tf6lHONYGXtGfUktDfJbr1gtGQA6DowK/+Do7r31TB9ey8yOfUeIbk4nJxGKh36WB+9N
pH39UpP+1S6dlt24rj1okQRYxrOW/+QcHZMXasGUJABnaQ24X2rU24J917fpk7fBv7CaavBMoe2L
bCP/fcaHJjO0E1ecUC42JU4MsujbXX1rucyWKyEb/t8IbUDj020/NnUnayXi7pYcNVEMsuZ0LsF7
SVHNm8Rb3ZUMV+nNa+bSjvD+3wQzsGGbQ0m1HdrcgHpMpAuXn7/2Gn2mmcJEpMKdo1kivYYYMbTn
CXK6Gk2Yr7DaGxl3Z9h01mgOKmSt+quW/0nwUG8hWtaXqhX+KU7px/vukYINChUsTwah/fl/wdd3
uTglxNCpVc7qq3VJjG/JlVpS8LtYcxuesksM5pBC50JJMT45EaV27wtz/nx1g81wdk3zvtsapc7c
9RHz/XB8yUfILORVftJDKeYDp7Abz2UgSpp5ZmwXiCNTqzHyjOAKV9POXileLVOYGZOm2oOeYS0k
y/uFSlPxJekl1DDzXUop/jk7fsF0qEQde/JyGBmDI+HU4jOvt+DaIl/tQ8u9N8Eh8+dY60OaJFoI
KNSc0K5GN/+EePP/TNhdQ7EHtRh5hlEP2ct7QkGzignbCWxonmmLUPNbmchqa3HITG2SVo2O9ZTp
18kj6O2k+wTJ5twMQ2zgIkE0q4QZ4Mu6QjSOMUjGOWQn8wiujBIXGCr7mvtBxRYpcizWw+00k+6d
wh/LLciBbtFIQzRU8J9Dgd8rc7emy0HIR8mBOxTljm3yB4gYUaWiiTe9muCcRSoghX5fz7vA1ngz
MGzJ/zHaMHbpWoIyyXOsMY7/LAURzS3JEe1G2ZLW8ExtHg+7oK37saAtj6j2qh+1M7c0rOoinBMD
rRJgoOCHGCdr07mcS344WDakCAV6Nz+LAV0GJySUztp65cX+zDvdQWl8gzaC4wxqQDqVCdLlEL44
GUwqHr62+oZC/pwnv/1KWxpVae1v6tELJcmHuGFsyN1IgVgZJvS8y+SbdZ921iwreZC21HoVgwwT
CbHRUjbqa3K8NVqygt5avHZZKxJyJ6NfN65aOfo0CJdncHXaYXFg32uSgzesNuug1vcXOcIFFnyX
HvIllheABTmhD0s8bH1ofsbbJWxe//CEKodJym+WnaAepbd62Vw7rlOHx+qyyGVCIJKkcBWBR8BD
7mOrJ+QUozGplTB3KAWhTTcYFdYMJ3bspiIabrG4oBtqOUflmKTxHqqwkWNAqI0ekqmTZppS3L9P
TdJmBE+/RQR8AGxCDrYS9StbDTeBUVciI2PNCMUn7sNJmgQqlhhVYZNnlnopFhUjY3adQEyT5Cws
MA6ARMGxBuV8wY9mmVIyu3lye854ppR+bDA+SRRr6BSHkxn6Io/Rwc0/H4TTEWYCP5HRZh53gfuN
kLVpZyroWyM1G3i8Qg1VujjT8wAFEhrtqfKkD0dYu5cwx8bMMom4piD9Lyz7Y9/Nmc6Viu5Tnd8f
E1gXOSFl5Ms5HLOz5JCAD2kl6ztIOKazCtxjGYG4Rh2LmfpbMaVRKUIpVZsKh3xcR1uggYZPqmYm
4Jkxe0TReLEsaKCdq9LfTIAUy+ubDjMji3YTHqhuAlhEmIniLc1GN3g2va8n1tdLxw3M+x3PHDnH
s92wggMKfl3jaiBw6pyNirU+/9B6ro2KtLle5MGiuhAPMkScDhSvilAy0tjPhcvBTACi6SKn3nv4
mIkbEr5HePsbQm9AwrQ4ed5mjZDa90oKtxVtaDb4U6k28YzIs75H28xtdmST1B+VCbCbikgwOB0V
n8AzX/gv74sXXfAtTAh9FBapQFJ/bmjxkE7WiIlaH0Wdk0d+nRIpIYI8J+U1ZBCdlPhcuPxR1myZ
ZkCzN+ryYCbO1ftExWaS0t+osWW54m9N2IZQTSQ1ZMxFZGbnLsB0eKX8jvI5up99p1rQwqWQjG9I
COFsNYg4/oK5ls91pkKxsjZ0zQRb9bm6e9LxOV0foVKvRrvXjt1SK/UuD9K8sC+uqoeFUyfq0q5m
Sj93X+pSXd7SlV/+qe/FdOQn8EGx+LYi+13uBRvdPV1igU/RmANdzthvrC0cbr3yTqey+qFwfpV0
1j+2Hh2HK5rEmWsWWksauZMX8bKwJK6Fy7P1Lo6V94pTnTUXq4fAZHPH+PpCono2wZ0uWvXEbo7V
HuN04RC8UR1Tc10NqdYxo4Byh/yko/gl9IBchnLvmKsKu8HtnrZJZqYWJEPK5m6naZnHd23Tidko
wmPt7b9aLv/AdWvJ3C5hUh83avMpUXHlwIRe3h0crHs5Py4E5WYwaCIjwLUdmGk4B/pZxzv4dKBD
vqAPgqs6RY3Nje5/Sr2OInUv9uaYHbhDCdARcahtnh07p4D26pqpAMWcBtNrNLqJDraJANgp78pn
VDo+bgwN937duCAiHdH2JgdanWgbfZ7p3hMm0tlE2y6hMqA9TFg+5GWdC6lN8PGVjvOQ7/TW31qY
R80iW6zJNVkfmppvNTd8708mupr2AmO4Z6IQFklQlyB+gPwFjGRrU2CKMkhBaYerjnENSKUji3y7
qrcSrSd+tAqZEbRgvwtJjhsondzrK5/YWhsXWp+Y9TQWZhYtO3TO2IPwoEkcsOwIkRrM8qojieSY
GGETrVSfdXeYuQxdXMZwGRsOjAUZ77kyVl6iSW3Z68e4TbE+fBdFHTmUpdD0rLyMYbXnJw4k/ctb
7bHKxt8pZygSunvSVYDM/No6/7KT1kn8qqGdiwpcO/wLtNNW5+irRlWpTXRgysrxzMjiyETYvUlJ
kCmsS+r9fkFxu/Bl7rVqxm0nKgGxR/KIszMX7eAgYFkfb898REdFr2Wq0W/Dza6RTmr7Y5z5IOjy
yZ008UI/xT4EQdbEeSdrPc9uZxfW1MM1krmYD2UMPR7geMct1chzu7R3mbJFrUvkcQHWpvNtwoTy
DbVJmb6j05+xr09I/ZjUtn26PNzAjaSyW0dJzNgQrThBjqusCDdvKAdVlh9fz24HcKRWsy0At73A
cMm6nKqoOTvHtGDB2YsNSzhs5WqUxSWLIAzziM4rHhHiu3G7NZ/LRrw/fLz3McjSP64TcxQrQXLW
2YHmak171+63k4t3f07TqvCaYO7p2CmxREr05z90Ew59MLDV7+cESOrEMp24CKYZgvLuVKAgu7le
mtyBTHxfYN+9rvickxDMWlrN8ac202vvjLkhoYcQXXtqUo8STWyRJO9gVhGR4QJXKPwJ8X+uMBG0
uTRc02b1U8zd1vNmCAqEZ/y61vtG/AswSufLL2VlnyETxhZcRiycWP17AOZyRCzsOgM/+JcJwFId
SK6zoLiFh+D3aXmIBojs1md2gpJulfP/IEsU/5VrvUmtL5pu6d7jUR49BeNpleWUtUsZjjXqx92U
bJ+P5LdSp8UesH0+tvGYQzcWxQzrYaNFw+zrTiwRF1CLx8YZYuktHl8yY2+QNb3m6PVw9yjnVlty
GTh6JLi6iZ2Lt5hXP04VIuV4UC0rR2/Qnh3hCmAW2ekdr8Ax3UNM/Tvejwf5UdaIQYgnj9t3PfkV
dakGhwb3O5AjxNWXrO3HoTnx57bdvt/yUfJ+J26jRWqsRfkjxe2sba6/oR2df6OGYlbS4zYyXhJm
aNJEEuElCM9X7jlgKivldCiNFun1DEMMYRuKaBKG2EKLxHikx7X5l6GaMhtvBmZU6R5Yu9ut7iis
ltfsnEHPekBSb/KBd5qjCCKNBs8kuSQ044grv3AcAxE8sg6DTn9UNvDkJPxCnpjf9C0NEW/zC+m2
rtk4+sC+VJQQbXZE1QehR/R4hSoqwcqD81NTTS0N0VUoKcNjaY8bJc4zF36ZOt4QDGmU/YilsFID
uHGuuEDmgI+1y62ByR8X9qIwhaKnjw18cVYWd9yhHJItj+bMOqHWrMXZAQ901VYl03Q+rbG400pE
lr/2rfY2TRdzqAhObNjPPSa1aIMhNDpwjZwKCs8ah6Z/tZK1bma10xUJzEhh7XmMtRkk1e2lxe3x
Uam+77DJrWOFWnzvhFg612m2+tAKsLGDF4NeGsD0m54i5UxUNC2WKFHwwvyRt3bKg9sAa6aJP7dI
R31x+ae/Iu6ipJbrBEI7y1z3aD1pMxnO6RfP5b66w8CWINc2ol0RV29HU0htgBWuj7TIQt5wBsN4
CF1W/sOoFOw65U9i1y84stOopT6dw4H/I3WBE25z+DhEoY+jZpUQCBO3fNdo3TDXM/WFKfybSSx9
LpK1gGjk4hD5O4+xi3pedBudRNemwXvbN7Rk/xIf8LCLQ12DCfB6hViWcIQ/n4PdOj6yyNtdbhxT
XpnlyvhLsmE3JSv9XxFMrKclbsGm0tU84je5jGYQBeabuPGt1D4GPojLzaBTal+1kFoTHFVRfiAH
bYepNODDVeKJxmmx1EkscbutOgYVrNncLOZdVLhOZ55JUC32+Q5qM4P3GwJ6phT8ns+pTY1nagMF
i1ZvvRjdzEAokro4FnCjFqn1T05Ddq5HDs8H8CfCU+Uv9JDL/13kdV2J0hE1ECC0601km7ksO+JE
2mLmGWQ9W+rvF9YvX1iyKqSUGIk2kwfEw6wNRZJDJDhBz/QDeTx6E6fxPFxnHGH1eudk+kNtdguz
/JKYfcbSmdn41fKpkiVBieLkzloRHJVIIlvb1X5oE1NaiHQi5U0r4kL4yak7sbj0TzexdMNFEPXs
XOXxEBCiUE+8lMsIxbInyb19CML+0bh4I9DWJFMuwm6ODjCKRTV60ADKx8OCdEHS44s0hTQhmjhk
w2D6VeTcMAdIznzbxv6kyUjk/7MwqQMUY8S8+XX1w1kqI9TLqX6rFDqt0xn52tUVR7ppMYoLkvBZ
IFy0TM3AysVdK7SXA8Ec1HDWWnj1vTB1aaZQCCVRtARwlPo1yKzFys9+PSEbTMT6raTSkNJaK+f2
4Icrr/b2AyYkCPoK0YkH5AGXm/k8wnEsZaYtkoS1Q+AGzMFuq/GLEz2HYHIH17M7PlnHqL77gey5
gYdz8DFYPp0n5KydRqXGCbhr5AH4UIdC6ZYeT/BK2Skcf45kWOxHrRjtAn5w6n0Xeoo50++Ueanl
MEVJGx+0oMp1vsKEuMmS4edvQaWler0qF3JvkGHHpzagXBgIjZqXFpgyFXNSY6YsRvFJIu8zzGj7
2cyHm+2jZsQ8GJXM9sCfQXEIPX8AnrtIOq4jQpItjvEYhmoozbjFoaUzjrtG971hka+tdup/1gnk
TmMaxP2gDPwitqFw/qFfDDRu3PGPPAxUaPRYFP8LgUAJE3TxAc41HQqARFDAHP/tH3ai9ko0WL7/
3WSajUVwZMLdRnb4CgPJZFCWoXL6hPU1zn8qLb1HARNmXh/dK9CbCYp/dXGm5xg/37P6Xk9HMXZi
B9Vi8rMRN8kFU8Z3pqlQhnrShRIeGDkyQtplLtqFY7wcKngaqW3H/JqNX07gVRx+fQ/KgYTZUCCx
lQ/NtHYct7898A0A1kfC9mryZQa7kEcFHEgmA2Kvw4OJP34rYjNqj6cTgSk51xw/K07C+xyipZNv
XgdfFLVlx3+llMCB/asNHir4gCZM9mWdZifrSkkL0mXauR3uetk2EfYMEbVnquv3XX1F9fPBZ1jb
nTf2QyIrIvEh46MD2J+Go0p7RN/z+dMAtLhz0HB+9TWsJrn6H8YoKxPnHMsdN9Rs2tvVxi6kKk0r
GkBOVDnd+X0qaICP6CJyIZ/M3ZbRr4U1pWIPLKmA2yh+jzCguVD4BaCUHv9q/shvHZpATcdh5Emj
TuGN3u82oKmq0Uny/n396c7voC6zZQPtueG0+pXWjIAsRhOcKASwKMPAZJzqZCruZNm+lE0CnQ21
Ajh50jnwXHfHO4AjC+PwzQxW+sQXGCVqFnGvS4iSRdxu2ku5dYXuEoOr0vfHWiBwyJ0YBpVbCM0S
9uICyt7zSEhlqTVRTgdiPPCyr1Ei8xiiXkYJi6ejztJzNWwB4koog45MNp1I/eFkw0VqKOSBseYR
u8N+lzcaPCpG8S38Vz0IcFHAfJ63ITiytmkGUt/y46lbipa1jivla2jaycLGEdP2DL7AQJ8qOibz
HiHvG7NAPWuZGpjHRMxusLwfYhxjsfrZ3cA7b4T/B2E4qxBTHUzYVSordA2EFhxep7+0N8sylxgL
AFqssgkhv9/cpMQkyPK3htDIvVWx+Ux/rB3kVJNmlan65HH8WUjj0Y28118CVlk7CPK0zFQTMlYG
5atmLXAG0V1xiMEc93xgFEBuupc/QRGeEEQGeeItAiYXl+YS3kkfUtgq8p33I0qmoPSK9BMR3/M9
se5B6n+klIFvkNoJsBGMW4X7VDVAKgca2qsR2upbeiO3XF+hKXzxjv3UgYdDOg6t6XAUFCArkZau
1vx3R3WzcGytzujkjXuwVMUbIxOKxyQTRNp9MyyBu+C/Fo00Fc3Q9L2e8wH/q7+jHip3J6Ay3y85
mGiG+aNKjEEjVi7iw0oG8KXRoG8/ofqeBUPtRcF6LrD1uNfxrflFA0EALCunuM/DbRj52VUPOPO1
ptpjdb4/KpTgSykomLTU/EHq82d7GHEGAbMi2j4Ly1s+4gEP5mAoLt2qMEWPVVra/WQQOzlwJeCJ
dU5KYRrqtRhCX6OGRlG1EPIvoIFfxvlSLoH9LzvuqABORLn/sbInxMcWPvG2AabaYehPegb5Atgb
ugdsXJ86tx9q4+2SzhXoXFuhICgrPcUBwokkmnF2+lca77InU1rl2Tokg4sSn8wavJKi7xwu2gMX
MYB6c/+0+7J+JCKxSfGEIWHhTBbYB7SxH0FtluKNkag9GgW5TXVSF6DhQy9+SbayVV1ueveH1PPq
vDybhoobn9yNKGBsNLEopkja7YVWu4GAu/Xtu8Vrx8waRX/RZld2ZIiu/p5rDV2uv3ebPEq6ROVv
ejvH7sPmnlN0IoFkxxvgqLywDgNb+U6geVAgcn5MN3PCyCuhsUqDjdB6Dc9VuNKSxmGptrPsiK0u
NPY3Neb+UK7bLuN6q/DYX/bvc83g4Zf7wemycmRlmdIjOzwOOK6tlz6jbABb0xdI0t1jR5m4YQp/
RBpI5VPtOupo5Q5Q8sj6X/NDKQq5dhpAIUKMvUPEubDZ9tJUmHe/+VdAqMvhwPOjMyLG9WZPWGqe
t6eJLcoxW6UVeYwqehTcd/YCvw4QxEA5KkNDvtqoxuVDNNuezc2vFAktOpgNtlIjPREN1I0d9Zvk
naRttnwuI8FK3cyfM7Oioue/wKGAVRhOCvMgQ2t3sX+7lBR6uSrUVpN2RnJGx1fmUvtwS0hKrv+D
dEZskTRuBJgvZ497bnn9AmDY8Aue8QRr/j6Pu1EuB3ZSNz2OQtnXvj3hDFUnzPPvAGSz2WqIMtQd
EYtmkZ8JyfXKgnoTq1JCt5VT8r7jMf2cmRBQl14hEA82RURxUNIyUKLLD9/8izW7jUQQlRDXWpn+
/bKDuq09O16cYOdDk/WpARG9sQUvvoEa+ONpfuMltlYzgKIxjpUTvtjggs9VqNk7B47vWqQH/yGi
GNaw/rC+R9PA6Z3eulKdadrX8UZt39J+rr81KFU/nMRizfapWuLB0HAv6ab4KsCXygVFBY0eKHdq
6uVtyUbY93357YEQd4cpsv7Ram5oII5CTA9uXbmUjUzxj1TxqzIp7K7naEbJv2Y4kMUr5c7E5Wen
ZQkw+FcuRZAIrpt9a0NvuivHLDvgalYAm3U7bjIHE3uC5rk38nTmdFTEOWiWDJ9oZnjNATAb02UW
pkICY+MKWbAaZpcM5f1tPChB6EVSOw7LQt3WGpz1CBetrmLyXOanmnkY5aGWLKmhfZ4BVMrEV2Wk
HDtLAN2o7vc3ecN3jJ/ZRqZR0tkNG4tYiSRLYbijP0Ppztnx70/Nz+0/JLd8xposzwGCit7NbYWl
oKxVHHL9ZqCMhQFTrAdKHaZ6SL2r9Wc2E5mqKN8q8HzNvC0Ua/qnyIBpjdWebkEWz8F/UgZpXXLk
dQprRQ9j781ae3rasvWJ6W127b5ONILzdT300BU/XJh8IQxWcPATPSCwlnh8KjiZ2nlv4p2i1Y1P
19xoYDo3AY18a11PAiDv+1mCSgFHOcIL8kVhBzZ6k2B+z3+14bsoKfRLMuCMGZhjM1d43XpBCc2s
De7xziZrofxu0U12hvC0zpYI59Upemom9ApHlVVv/Y54yzTDWkCHzGh+CVCJCEiyLZSt4icuXFeE
8aUwcyJ/xyXsAygsnCVMWy5gsvjUeQdaYrJ0vkQFeVijXlnnfjyaA0qADXkPexVRMTIlETG7LkjG
r8LCJcTiCvcq2T4cIIYUJ8PtZgHxFgDa8s9dTbCASdjhMun31AIOJiekkrnl7ezxV3hekdMCr553
2LaCOWyqF38Wd5UjoVjyj4gCJ0NjD0PeqHWwxFbxHrKeIuib/0U9Ii9P4Yc/qQzGE7PzaI+rzAvh
ngp/M5Bn8FVV6nsbn7EPC6Cg3BvvHD7z+GEAAIzmqcdnw7ItiRSbQ9RUc75g8QyQiqtNdcijtvfG
azytjPHmgIZehtsiEyWGAnH3q6OMBSCI7FsLThbLcnEpNn+YiYrnK7irFz6ftTPbNf3Y9GLQByeI
tdYjpK8vb2HFcGIFqrosrCS7QbAnvaCvy7SdsslzPtknl4e9MIeIOfpC5ZtGiCsRt9XS7mV0MG6n
09TQFBchgTTF/GZ0EwM4Fxe83I6y5KxkOzcTv6UqKQYx7nfqeCEI3XGRhsJ69CXjO2ASMpW7ZrYu
bL/A4ORG3/3eQ6jP2TZOuLDFHX/BA6DrBcygV/avtDhcyzkr4C3kh2z53Sd//WfWtz89LTW3FYqf
m1hxKZltv29zRble1gon2RjjhI91nBDGKaq2t/Jj7cOagi4oUNEBU2+B5JG/dTdx9GvzSjaJZugq
SItjYYY8bh3SE6jrbImU7FIivhRCVcQzyzCk8RKRDpqjhSbVBBktuGhF2o01cbYTxrs/V168fRr6
dGhiu/Uf3PM2PjHnrG7+WCFK3Ex1+hgXOhLFC/GBYVS6sNski7jdvZ55LdhIOJ0rLdeF7j3Q2Hh9
GjBrmPb8okyYIZVggQNaGyqOktfJgagbNU6BhYlhLJ9ZQwvuH1pK4TjUljNTYfbgyV7dp+wpHmR/
lEmoSUR2JiYQgsQbIIyx8wrW01q1YCqQpu6sDrY8jER2vAypJ6eFs62MLwmhth2NB4gR4Kv7IT96
p4jWSvn62pxF7E60Q1epyas1ApwCqWssjU2UXiD0VmglhFcCKIyCCZG1o/9SGuReQHrTVqDTRhkV
wWRFBMBl7v4eD338db/X5/qQx2qQIdnWDqMD8Bskrq6GGjPS1LKYRJ/NQ7DPgqH0QSED4VG05hpa
RHOjLziOMbkbuM8FU80I7il+wwPR62X9dDctIA4yrhdhzTFXj0FqBnjWjb4vaY/usIYnk5gSNcmB
vdATHVz7ZyC9hM1CQfINozVsYv8lW9isuUALoZbaOA6fyIt7MODWdhAAc3WdlG1YsS1joi5mcNko
V7TqrY6mig7xDpX3Ejb56BaOvRM2I4oTlO+kAsw3R0YOrCSp35wdrZi/Qnq72xg1/1LjA/7B0BQ1
U4Nn0sWbZ4tBy8ThnQ/BblluvT4EtYcfcEyGtzLyo62n5tuqKiYLYQoohDPP+wVriOnrlCP+VFUb
076MguG7iO3tUgHhXUdcgBrG4T3+TE/2Ik2ySFZcJTeltfG/vI3p4mKlJxPSvYu1iFZT4BQ9Tpvz
xbUc05xmQAZneAQ4KyfkXL0OI8Zpna/SrdASoFhPcFPOFwj4ETZ3wF111urCYTYxmOKZuwnaCqAS
xPIiD2NdC9kALdp9Zzer1Ye/ODXizDFxZCE8dxft737sUR9X2teut7BKNc38FK2J4ETq7Mv6BbO2
ksQ5NmQlS+WH+CuNEY0g/coIQw5o2/UtK4z/Nv4bEYzLu0XY72QoguyWuFacTYsxu1FB/Azg7a4L
x8LBD4yLCWnHsx3v+ZpM69P+gm96r3XWlrpS/06eDI8p7+ytNYS10DUUj5w6n8Lp35GqLkFygJvB
KAALBzxTf/5J+KuG4UUokj6n5d21rjF9NKWnE/CzMu9urdZ/8wCCUMl/OshHcgFnYWQrikNKKOkS
BzZwLUQmOLfEOUyGD+ZSm91YKtiCC7JHlinBMNqXoJw6PfbWEmhBwAEleQQYk8rkRf3JVKGD3TMe
i3HH2xo6fBBYfRZOSYkmLTGyb9BgnspVK+GZ6pjTCEIJY41pmP0bji7cwQMzbSoLae77wAMYahkT
QuwvW0h5GrefNQNj99gyzXM7tiZSaszuTI4gjl5GLBinUrDZMwggd+671TOvIXhPKVoTv5rv1YgZ
a5pkpuKz7thv3b5VRn6OY3s+xyNGxSwBATw87PDDdYdDvF3mH4KjMsXEkhXNGjw+4OtiIe/5170u
ZDaaEFmDz+cN8thoazp1d2k03Vdv5p3e8rcPbBo3mj5iaGAX2R0z7OXYt4Q9Zpk3xYswiXmWcvCS
Ri5MOWM/nfuYOYfRDcFSrN9mXz6BiyOb/s6683JUeTOQQ4wRbIZ/XxxqbNsbE2dIJn1h6NfkSt32
sLGBOLm/5yiGdCjLbOs20yCwVmrOvMsk6ARzKkqTQR1HxSbWKzOBUqb70gw8rfGMDmbV2hNedgpk
jlGKkdVpU1hTPnlZvU4q1xeAfJXQj6SePE6YIp3I9XhoB+nt4X8M4xk89Muc6zWURdoNoGdpMDRt
FCvb388BIPYgaeaX2juMubOAKtULpIZNM1I07KNzlfE8cFiQm0Gog1OvWq3xm53h7eEFiC8XOnJQ
8JAxnL9iuX8b+cBgbecqH+JdTR18BkKil4pcsnvPVau4Beha+2Izo3nI4Rbx7hkPoeBfhK8N4W1I
PaxYCsTpt8tmSjsoePyfzEB3mBdCX+QYdFx3EeZd8jjJPkLWgHiGLBdJbExX5G94Tpp5OUwzT58N
nIQDkRlIgYWLZ8Ti3HrQSNLT198+KKylKJ8ZJlHIBwdQlJV8inFkaEBZEl+AZ8EO2kHQ8ZPGUNL+
rUh8Sv0c41fPBhh1z2fyrKP5Nt7SwMQ9r224kJmVSDWTRhSPBBzaW9dhHkFoR3HdcRXKNVgldtxv
pT4VZI6Ol0QlOGwU+l8yfIbniASeAQjVQibS36WWbAUMJltnpTF5l5NPkV0K6hzgwf1503sXfnZ5
SyAAcIgM+kiILWFScVNs2MzkOAywvBJdPuZHjALg3csBvWdTTfUK6vOYjgKhAuMSTcyDM+IGHfat
H4asqhxUjmgfGuqEoxL5DFeUwd6b7jJzZgVAizwNKo+/YeCO6u98C0oym8tNncbRIuIEYQqJG2Ax
OHDjeIOCtbMG75m94m9ZX/S8sfhH9GvYHwCfChj4qeIYVykk0hgytJxX1a0kEaaw73+XzOR+uNFj
wyGVIDVasZ9luS+93/jZQZB/ldtcizxMz+DKcx05HLGYqu5ZHtQFeguA1EvjQNmsphBlaMqKQ5Qo
93IdbL45+rAJCZhmq41POjOqRRawaUp7pcvhqGobrjEizWqQviAv0cP5nDzQEcqYjSeC4qTn0nga
pGtrx6uR/6clWXW63VqmGRV3OOs5plX1owWpILAAdLOpRcMUro2lmHuQf0uHaUnk6jgj7IEkBxEH
AHhJS3pXfjKKtNRPUxHg2QyPqgTDWxhrOVCHnM3WxSHWt4RL91X9j34tgaP4g4Hugizv/CGh14Ls
K52BuQlPwQJDfIqRQIaGoBTE+sx7e4ClKXuou7IWGdknaLmUDYqH55/x7kJkum0tc1hBgYHL4nMz
Y/Uonnv/cRVXcuzru8b4tT5RAU3t/FyrMEBR4GaQ3rkncZysPkyJQtuh/oTJQiaNacia0NTNp1rF
5UId0TzF+XUCZRp+WEpP9Ez4RGe890b4I7IFtAuOecjUgYYUZL22Bz50RP5UYwMynMg185yV+3dt
rnr/Q++dVnpeNOpUhOW4jZKQSLZqwpS4ajxtRinphLxykghIpkernF+/CNMjh5cFCQ8cftmbsnpP
4PJMf+354BNXdgw7MH+hW05wPXmpu2fLqHVwApC2xtL5fuQyCivriP5TVYeZrgFpsZuLDbCn8tHX
xwyJ0v/j9sBqr4d180hiPuaGD/r9Q+2KHXWnyQf0/FfVgtpDROLgzyUqdlCjwQULBw9VikqhIFYw
hl0jjzUNzKXHB788KQk0H6e4GWXKDBbRej05P09C+078qM1pWXblJ+HLbLSHpWElDmkwYwppda3b
aAczbMEkbLayfaINLWg9y1nMe3+vByy9lbBjHy2EaOtXO/ThfG7f315mLjEPV4D6ZV4tGXDgc2Gn
PZhDoIYBWnoSzKCanDu4nbu1gjYsmW+3EbqXY/thgvtyiyYIlWJbbAFjp09KhIPVGFX5h5fmqeEF
cH8tERx7wvhpFSh4YLdQNsKoqCLcj68cC5dPAUgAIyTvhgqj0g2fBzpXCohQtN4Bv8/9uox2M2mL
XdLuJI3aDSFZYNA+MjDyo6P7rAsxx7odMcf6IAecdiA0X8Y5QXZyNPGBeUfz76JSWefJYeiFdP3f
6HY3aJJPeUT2nDq3J7mvFaEAyfGVP4qIMy3w7je2c3iHFX1Qj1D30YVwSQ0VsxtIIWYc0ewMcBGd
SRvFBpOByFTcb+dgdsepus4+cfhJCfzArjQEQwvpuiyi3cEexgpQeGXoy8CpHytmGFr85dkCFh5z
f7Nyofb83S16mFxadBcw2vhIux6oieMdan8woerYWCv1F1PhurE7AZ7ZVugVVzZxq6G1ihVi9Rh0
nPl9hEkTeUbVDja8NTWEuYx/7Z0qJtacroc9Dhui4UVvL+nNMZUQjPkbZqndMdsonhAL3UkwnebH
XBjqyFvMjhVszPbxgPvOBWdoIqY/0NubtdvHpdffCbM6FNkcgVOxaieQrPAe8WD/jsojVzsWIVpD
MDUWbnUPruGk8bSvLeH05G7endqrZgtEalZsMWyW4S9B+MAGaf9rqrqPKP6Qt8gQwAYAdzRvkIE7
9oQvWT9HagZj51XVzFgMXx8HR7mYdApPXukLwRR1Xq2lAYtRJarjhogizCqlyYQwlAAZ2Be/6y5k
wo5b1bTqUuoUCMM1fw2c7EpceMlBS3kPXE8wukvpVHSQDfQUeXOzVc7O+X0IUd1bOXFHjZMiZwNb
x4kOlhTGssDP/I1QNXJLT63Z6byn9It8RBi2ojV282bZz/llAC54Id322K/bwMsWNAL79PY4GtNM
/fE7xak32cQYBZBDQ96HsgskDWYs5iLKyIepNfRIIqevygQCZ71MC3GzxahauOkq6nMe2KQnam0M
Bf51rsKDiRiXKQuDl/CWpi09LpU4yHyzJRdLIfoY43GxNcGSZXR+u5z0FiovW4UWUgcPKouqDclR
CUImws0riiHM97wPuK2aIrXvMidn9hjTU7wCUcipTMVoSIdomLhsdZ/pmF+exauzvh5Lj6f3thk2
QyE85f82aKcY5xdKmNWsSFoktu8zVp5hgW6NSUMY1ByIFymBCUg5CqT/9xx4ZgpBMzO5RVQwqhuJ
URMGlxUxctNcD3pxtMlOYLYct4qf0OTBYpSScUUmr3jYc9vH/G67CDlsVaq9BBL8hRKGn9lv5IWP
k7nWRRegzaZVHHPJ2F84KHJneYONwtf9oj3HXM0WdibjFYin1ur4xaZKtBa6oMKl5FpB/A8tXcGi
Nh/3TCstZHV+7hCHLAsSM/X8qx4RhEHK5EHxpCNhK7FhfNMrSPAjJ6L1361DOT9boGJYJp2BYoCg
zQLcKQ1FQTHQn2/WwJnhlNPa4KIpYg8lAZUaM6Rb3MSZ7AfPlDIh9NoVgXN1G1UtaD5tYRJTshQQ
D8xmNoq53O0aW2jp4ikREyif8LZOVjtxfrCJyyK045l1KgQSV9SK/AYQMKc0Kmcf6E+QCSpLQXAF
ItYfQnpNvdz3sHSiEzF+Q7sNqraxDuhYuuGe4cYV2AAEY2MZo6RZyp+vNCY2EnhE4cgjU7aVRA4x
e9Q/dQlbIHBoBgsuP92bWFSrARETlkVM6+d9qoEtDpGw68z0E2WV5LAJt5HssLG4dUeKRY58+uhQ
H2pspSJT68SfK5dC1Q0nQbgxNI90ZputjnhL2jRPRgCGxqr49EQocg9cNy5SQxmWS0rVLUtU/n2Y
MDDshwzez2l9F4wPr+p+AUqwso+u1ga1C0tSXVy0P+dYxQqypfHfXU4Q4B+ecx3VWER9iZHKg0Pz
xbeq2HvOKRWKTG7iuUrhKZzv6yjUBGPKrdaGfyn+dAfzjw+KkTpnURkbZPii8Inj2QSAShYDWKM8
YllERMYgs8c1iSDk50haZo7ZRDb/XaF0ZzweKO5TBELuM4a7zZQvcC3Br57IlchQHK7eo8x4yFMz
wLFYzphIg8CnX9r0DU/TERPOwglQK/CneA9liNMzb5U4a2b1bfJeo7GZNiBFtGw8dmUMsNcRUPS7
wx0VyWWiv83dF1ZTwgDrnUQzvfxNOpCAog+bntDzEW0xcQKa35FGY28jrIZ2BKlJRaDpHfNX1N3z
ubQKqyJe3tGQVtXFdniCMMk1CIQX5KOLVPBuPk2qNwCWywqNOfCD6C3AWTh8uaDirPbed+6aZ2u/
Pkoxl00fsS+A5iQ2UGAlHpooZW1JMN9CCdpNvpoOLo9XM3zpqk3cs7/w2EoqSRC2mxZUaQH8J8UF
i0qGZ4JOMYDRXntW/89E1W5blOUTnQka+uD7+2K26Qq+4GYOBBvVJHpU86OoIbpjlwMzoarrTQFU
nZfCZbWYqwq8Nbwb0PtNFgT8U+srfS9mm3umTWw2jPCNbtWVloE48LoQ2wAHX7S39ZftmWFwrq2Y
iwzyQFkDhjHxlYtactRC75uVy0jv1nkCNb4+tPA7a8jnf8WbYoz1Nj5+SxCKkBElUn6RSdK9VLeg
lcqyhv/d7xA/L/BXRikNJDt1uuZBI1EVbYEw2nv+Nz+IzTDJWQOtE7uCxNg/I9+K4BVxyCn9RGlu
qAzmSLy5kBnxoK6KCbTh6IQ+Dp3bAc3xxJVdhitn6OSoYLokldf9FruslSBoiz4mTK7rZhNn+JYc
+n2KlY4QvHvEuxr/sBR3Eg56RQFKK9Ptcadz9Qm/V5vDVLCC1kFdq/ZfBiV0xQW2wr7NJUh9da5t
F1WXgsfomHk9NQdbh80R25NDQ9sii/Kah9+H5hCX2wl4zpX/uvJSrrS3mlQXhD3JU/i8mp8q9V+D
0pBeGd+GiVRpiZG8U5gceM39m/QRWhXXRB2jiGqGg2H2JbN9nohx6SQB4+nxY/OfJR3KlTt/Xo49
hqahCKu5udGb7BX8KOCzanoUmhD+uWqUHBpNe/FI2vPWh3Eb5p4ruMGuwdVgX5PkT3UH8khYUSb5
j9y+TjKzeYck8lvos7Gcok6B/b4K9CciAE6nE2gbZIJWXZMXnMTLZxPY6mHJbRdCJaOKbk2gil9m
yEqTfSGhsDLxGo0h6NbIcDKSeHts3HFuUuKSAvaVsfozwT/Mezc0bS77CZWJYDlJRvyHng39TfRy
2LCjmL33qe5mfYqFphis7idkLl52lIS4tjvbA3cQLyGOjrz72vAw9THD6/LzAwkf1n0W8BE2J+HI
hbhXoK4REe4DRNLmYdYqmfCTPOAMz0tzoqZi3bhmj98KEBOYnQ7Hc26ylQfzcftXlZQVFRHc4YTA
Ddi2mg8IEJj2YeL2JSV910Yzadj2JxZSQ8Am7HQ9Y+UXdYr9xq3zukrOPPPi/4r/pBiod9oyTvML
y/RQ+QWs7TTHCdslMLH+ivH/vP+dg+Sr0Ts6otWy3n224o7DhL07LgW6XkXVD91PMG/CLTsno5Rp
kHBHoAICesiu+X66Rz5sZXIoXhc6whU1nXT8rvuMOQ1cX34JraLNAq98HUHswEBcnLQlw4PRGmdq
kX2AHynV0ZWIJ77ne7hVtA3F4hIOsm5qG+WwgLguT68dbIU8r8gsHlGoBC/xMIY2X8LLfbrov3SK
qzLYcs6ab7FccZMabj1z3ZBAlYhFPYFVRB5qIOQTiPXJAxs++1N1D/rQWDjWDeKH1x8wjVVVccIF
EhzgN83pK82xyhGf7cD5UGR+5S6zMAlkMcM9nGqD5/IC4eMK5ceaPnfa5VZ6VFRoRpEvoDzvwhLZ
wonih4Vxq1fZ/7ckcVYBu6u8LCBZNWVHKs8VjvCllLh68ooNdZqpR1Yoz2S0DJaRU7W4RvXrON5C
H3/YDXWSQqMPMKBMX2WBzp2TZeSlaDkrgWa1VSULSgsqYA9FCzGSvXdjcjDmdiY/ayEMdCc2Rmz0
k0r0F6Al/t11Amp1xmldvmJ63S/bKE/uIZ3RhJv60uehb5MUz1UVwJsKxj6fm2+dIVwXDLoq0kJJ
CJ2Hd1A/cksgg/yAf+4VyhSng5QKhlqgFCiYjHGq2DJIbdw04DIpZo/e4/9bhLLQCdZwbIB4WOA5
IDxD4bYCrHLDt04gLeZx3rtRTWhHmh3U4TFGA9D0093NuXJPhHRlc3i+FbxnkghdYeP4AussXWTw
JUpsg8PDh+RCHV2jiOxaZK+jlrq2ZcQMkRmChRP4jr8FOcwMKHW/ZKSj6n2zDEkWbXWSW+TmTBzZ
PuHSfHT0SVEhncYyKfM6h/0x/yjHnJkj0TNACMVPruRs/TSyF5qK+cPFyLXvgF11Om847oR3QmgD
2Jl1K7zH4gxEeWQGR9k4fn+XepeOyLadeQwz4e6u9nQ+bZZF/hQ93VXw9dO5GaSWNAjw3NLqh/vc
Imu0Jizcw+XXGETcRiqCUAlAtuCNhLrQ05joVBcOtvZwmYFtoKgwUMZ1X4/a15tSQWOdKmMwXyKd
zrvjZB8vZgfTpeDMqoeZ7CdL8YXG0Fbn0426S/aUr2sTdz2i3asuOCwupn7bHV0c3pRnLbXjnjYN
qb0ZI7K4aNaZr0aejC7HQuYx+AbIGBnEsG0Lx79BRDgbOT/q8Yo10lg9w1Zvw2xcgHu5qb4P1wgf
UbBgc8v1DpHHwIoJrCU8DEgaxVhL7gzithLTMsIwRudRd19HEoDeJTryLx7QfYw46vGtsAqjGFvL
nwDbfJTAlyRYjAthdTg3GtRyJ7uE4f7R+s77bJI1eYOCIuIwqtejAvVrt87czJmQGFAouB0WcCRM
tIiqsOqyxSICfgW0CJuDafzt+qtH1aAmh3ttxr7BFjiBiMPHVFYf8hp4yjjJkfQMKE3siKGYTKZ6
1V2Y1+lwXfdxNOtOfeQaGtVoSmnXUUHKx0QcRyhmDOeVHK/pq2nQ51ic/jf5li145wcJrtQbJsr+
SI8+KeH6tFsRaHOP2NgOJFhlWU79ZxjqK38VG0ZJwigMuSxnZb1qeDu7oVL3UGwuiATlbmK1eDts
sOlz+I9iFS7uq5uCHO9RHG5c6g5ixfW+tQlTrmw7100UZ+yyKlaRA92kjC3C20QC575fialxetF7
sTRLh9q4z4BCTnFNheqQLO/1DciFC/qeiG6AztcNx+PP3LHe6S7y+GtHO6ef+lFTsvXrPMSpQzYm
OsH0mLSBJpLvKGRp/S4vbeN9yrfZYZJulJT1lfQ6XdO2/L302NIPpTAis/wqt+fI1ePEb/UvIKcR
+qAZTguBR/YWQsUxyietclolWgG6b7B+vG7ewtZYtZ54bHCDDnzyI81/Hb+29D1G7DLbttEeZQvR
G9HQeUteTv3pIq1ybUvRf8M5eC5h64tvT/HWoDdosi2wLVw1K6Eu7pnVWzpsD127rS68nm4iwsRg
6+1CA4sRC4EmlWyLVzjLxIiNIoQRumuwsnywq6CJdFwFj4RhVMJoXNr2IQN4X4Qvu9jY8LSkxqzX
gMJoxcO6nlfl0Y1A2CUdhjBTMlcgBFuDPJuuzSWrZi0QVudY3kKmlhlQMOJESMDixppIV6JJXajd
AuqhddztCA48/tKCBeVjBkMXqTqat+rDDZn/tdOFLpbjcoieO8uobh9gsQvsHhF+9n4bfTbDMDKe
EMxg29lgSZ7o48EaOlQvwZTbOHZjwYZJXM+aX5osmpqtMyT4b5+08M8FYPmVUZqSCsgmk/GWP4wE
2GwPwleLRKpZnLOPBBFMrGRvVcYeB3v0KrIIi4YQF3S0LxenwNCXKnFEBuaNb/BjFYVKuesw1/49
6xdHKX0dM068yIGqrDHwZzg+7zfGzL2tlfXk+0pI1KV0ET14yKDmSisE9E+xjncK3u5MO7ztzR7z
WC05fOZsPrE27B494phFm9E2PmYxWXJmoxShFIBa+fRCbDHbsPTvNvN1slLdBODO00ryftxsMfdj
6cGD3gT4x8Qe/jTReZvscjmOfQp9lGS0jknvlfC7Jh27zCKFVC7wVTZU34ufBjn1ya7873kZUEDS
Jr/1GVZAlJ2o6Qc5K5qn3YZs0x8suWIZv7RuKbQf5ecpuN8RwzC1RsBLSHmf7yF2x7EQCtyiO4wC
jYStg5dmQ8UP8WbMEIDf4TVE+QRGnjzxsEbbfKAUDTNwZTXHYGOlWDfjC2xG0dUDx2x56XXlJLlS
X2CRwM24a9bsPopkxek5p9ohPe3Zm5xiNCK9dbcWojxBpgdLKwgQl28DSnww2HAsJaFXTlnREIgs
bGEv5PkvMBdQRw3okb8K35+JvrqJveXdEIpzzEslJNCk6ms/P2FHSIwzAGmP+y1Fl9WsxJimbATb
KlIrk93n8cKNeSNJoc/278bPz/hQ4NOk4jTH4nnwtgPG1JQHUUubDG1V9jqVa2Sep4N3ktu4KMvy
3l7geFB9VQlayIG/jqLMmxcDNqMffJpxHA/Ss5YPc+gcXj4kUW0d5NGxJQ8i8LIzmvU7I2+sdrt6
u886/QKAFE0BMPCI9ZE+lBJiNtcGSSAgrG6jpdw2Ji10NzYnMcVyW43MaV0y1qhmLY1gdTTuwzwF
VHVMBZFJ83wuFtlX6nCOA6NBEuGckopCSheuR/xHJa23Nu78dGy0XmBlSJrrptA5yk2pOd4lz84K
MPmPqXjvyRoRJeGAfEFkjKYPQoUCWBae5aJYyRwIt8TK1AnDGVSJKV3JkhqlHzzCTbdlUGH7RB9R
KFONwbL54nS3cWP/wxHIinTT5r60abaMvld7tihfbLAJz9uB0zMUkSXuINim1KBHIRDSOUj8MgyR
OfK//ifMHHJ+wBq8HuXGI9ICs/fhfxG0aqbCCpjl+qG8UFTPlo2VeS74929pAeMvhmdGhVjlGiWr
C5hGnDRFPnWCl87UKUwAWKqHovGR3m3Om+ufIGNLqWc5+lPJvcqh8eDg2KXTFGyE47pFn/4VYHY1
j6l+FbG9rLcXOkHgesdPpjDETQVkfDpjgO0wTNspnCutBBDrK4SN30wFlRS3ZoAJpyJQIHLtiAIJ
mXMPjOTj0gHb+CSno69SnhDuqEYuAcgYFJhBA5ZMx1aRme2FYCjWMl3C/n/1spIkLcLzvYJGB914
GpxtwBCZeKZnNxf8stjG2m4x1/Q7eQp6BOFrGdvkyAQ8QOcGQ39Ypfee6I0qZPQmIMY82+oHqv33
KFKsJ92cVzXoou8arUReTm2GmTdeVMu4+OdSHbSUzv/Qq1wuDBDJ2R6bCLcqhkZRTbmS6y7friDV
NRoTi+JXzOTEncHtmwl2o+wM5MzrMOImUn4LpSXSaFYD4g8BfVrby4QN2FQA/btLE9klJWY23Fb9
lRbmfSUPNQKzuyH3ET23d3ZaenXgZ4h/N/pW5yYF7kfbwSv8N186PP5lj6CPbk52w67GZgxOTCeh
1UCICd0lXiJkXiTGdHIptDPwa7s4Cf/V3/6HqLN3I4Ct6R9NLHJ7xo0y/uAN9XQZygjuTlL85y1U
C2dKj/Su3Rr8kgHsi2Ei0mnY/PYPg24kIFuTLCojFmAlQj8VYkZ2/X5lxCttHupReOQ1PJeWxiKM
tRBkEC2l9BMbriuwArKPYZQF0nlI/3QYTICkIY+mlGRn1+zU0XLd3e5TJa6RRqvtEIvMCm+snIkb
/BB76pTmg5kwwy0TXi3Owp1GoMPDRx4FE+hNu43At+cbM9pRNWOBfSKg1NpiutsoEouwan4s8yVr
lBGbEIQJjwCsLrNmZ+LLvLIl9ab0H6wOKVxvT9wycbJylrxCr8uVaZXx0ylMRlaCYyxr+bf4qnL8
v7mnHC7DO5IwHYqWHVN+FXAPYdQ1QQeZVYnvh4ZvEQRlGvC74Y0BoE6P2EKTGN4Q8h1oHVUsYI+X
Z/oRbxEMV+obaaUBHSiSdxrJNK4uODJrIAcf2mvAu8CzJVG3FqJVfsCMFsRkSoEw6juOD0BG9iy/
6APAKTzeOZF0u8nlwDVd5+ORuV7fFSo2vCvQdDlOr4/+Kz9a0uKNuYod8TudQz3YE83xVyo945bp
cKv8IYrBKgaxRLD4lhq7+WSm3Ibuefx+cdHfaKLrDK+4pnWZKDQ3XPBoOlriLoFVaW5SD5OIsxKW
58D7SJwrA8VQ36A/CkD8FsxCAXuCWnw3AZbXgbrF+XtJBYzwZ17hdwChmGXlXLDCxClYaJ5CnJ3n
AKly/9r6yaM7Be73RobbqWRp5RakjUV9f42JLZjcJRmmjbpx83tfoWGVulIk/qwoiVfiSsq12ZWD
BnTcI7C287bZz2hRkK6JSn9lsyYJ751wVs7hCChdAYJc1BzbNhv9zL0dsUri02dsKAhFi7gMgmAD
zaLY3itMvAVR6RgvCZC/3buFgSCHG26VHitSGRS4gRkQ4+DpgjsCtnlRlQc1G4YvAH12Tx/7UrOs
Uc3mCC0sLd5XJfFoNswRTq0TKMnU+ST3v9kZ44WC/J9c6XjxXACyBxGI21DqbCCv4zWBUi9kfRKv
IJMUOJt1whdlmRAylmIkDjwGqdvSUe3rO4wDVxe0LbM1lL9eLhAeNIFu0Q1LG0XCdyxms2bM3Nql
5klhyuZ9LpwHSMOui5mCKkeXjF6qdqQPQL0PXyW2lQJ0H/N8Ts4IjGQSqDwWeLwjs2iUp2Pl9NXa
Do5N6QpIcXVBuslwDo5JHY+ggSi3a0wbTNx6gXhEmIyQUNYXAMkcoMT9eHq3zbaJEqBKYZXJhbb1
iNLE7h1LSuulxiKP3Tp06hoD8cHFnZ4k6HWnicCzE48HiLajTLm2YQ+ocAtv+wPX1atkz28dgvY1
1faben4At80TvCEw1s6A9aF5j5F4dJzDZkRxWhCN7Vs8aKhutZTki4Iud1eyfY2rWknpHl9fGTj9
HlzYrrl56Al1ZZ0sZtNhMojm4EKjjcBT8vUDj6QQgI/enE3L0oJh3UiuuWD4xngDcmi9sWgIECG2
nChMwW2OImJ/YzxV6pbNVd2j+WoojR/+SKJI6+/y9z4h21tYOBapIgw5/pBBhW/ZKl6G/eZOMJEY
BWd2EJVuzkYqtmWZZE7vqwcfWbBAss7LQaydoqRqegjOo2pNpnbqGdstBngeq/TjDfODf8CrlvGC
DyWX+MhwqesQgjmCBAWSciI4zApBYSMLdqOrY63ruz4jz3SwhB56yr8558uRjTJivaxzuShbBKDa
aO1q3wKTfhZaATH/iuMm6LrocPTOKlXLLx5gyQRFs7GYpqUhpqfOToGxWeFb3JxDBwZ55xidWRcl
jrS24Vs7+Ao3S3DQfBcCHXhGC8yjC0fbbK4b3ndHordRQloyb8FN/RjiR219YI0ypHxC1DQfMhot
LxpR73zZ5vpTuRNcc4ef9aHCtYYSwRLGqv1tCssQhXp8tu8jGBlPc5TWTq1YHDP5PYWCAwIjYAMN
HcIdzpTK5d1lV0kSn71W0HjjgKSng6NnuyQB6qhC6scd9K2O5CLBx7Oidbiv6bx9TKIDkw2rRx5B
/dUlWz/G9teheZoIKzfqh/v+NLo9w7GLsuXs9OOMcRaYCcihUnkNt7DQIqZ2zgYvl0XSzmcEct5P
8oanzzKN54ycLjqfO8pOXjusp3zm103PD17FVaT3J5bK/ssZ0XS+cB1kj5KB/C5BO3z37+NFkf0K
G7MZHfdmOloDCdo+Lke8Ugp9PJfD7fG/xX1nl3wPA67ZdJcku1gvRCOWBmnUi8kmqHeWsdmz39cl
OJnB1k/uGNfzhGMPS7Oo14jlBZdjVKFnh+Ebsy2p1QOZ5EmHOBGnNhCQdA6NofbNA4nCUcI34a3m
imYqzckvaQx5qa/vHyfB8OZ3MmM79EVllrRgRzpK4JguOnTULegT6uJjY3/RXot+7n6Sa6Slge3Y
JoJtpld7bVdJ5sUESL4+v8UwsoZ9JI11/e/hR7vp6n6C2Ivxr4gRIWRW2FK78bK9ylsRutLlpGXP
Fr6IqShg1JogUZszAiLitBtK+mLrRC67a5HkoxhJrb+Qm6yLLrC0m+dOwlC/DU/70I3P0yVCdUHw
/ys2LAxWsN7NWqUmb3iG5dAVI+hK0N+bttgTMB7VrAWPmawO4egHiB/MVorBZB99y31O1HDslj0Z
3I12a4W1k3FgBk4BGBraDRpkYF+k0KdOkW2XLethr/5j4y19Xgqh4ZVe7Vvi6K+Qcav7ndgkX/W0
ATGIHyvCW0I6tamYm7VdAUhc2iO/CHgZivJLsfuqFhs1XhQldax9t+8hje3XngpaNqmIicg85y2N
1Rt60WLLPcV0qIaX6mmuqTA53eQvbkbb4/pZO1Ko2b0MEAZ4n65C8DIfXE57sUYe9fT41PJskaby
B+GhoxauPQ4N+8Xb/qW0reO96Os2kugRk9+yaToeoiMsezGWiPl1xskkfHPDCK3vjWXxtEqRJVwS
0zySuqQ4KGlvhJ4WTerinZ7DuuUCPtnFrnj3xkdWL2t+P17tzRmEMlL3VSUwD3fytfOBRJSdNDoA
8skfla9Fm+65GU0U5T19dilaIV4h5USGnCgFDIsA1W/Xvqjc9NNbAh8BcQnzDuOIpctzGzCmTzbp
/s/VECGUCSieZ/woJoVTMLowEFDHO6jpgpzkIp9hyg0t1MIKGPxMA8oGPw4dJxJgtQKzPJceNTqH
q21MMeMQa1rm9lnVuHQuIIE9JgypQIn1mNDNkHc6S1g2ZtVFdedQxEZSHjn8IG9BwQ7e8otCG+pu
3mufMKtenKB8A/4yEaTB9yrOrEakdzVqVArqddarK0I9h36WMYp3ioP+hB2OPs8273B5gCaFfz33
kdrpbeF6MwTvKRcnLo3iQDJPd9Rj3e8k+q3QIyFzWRr3/7BvtL0IZlElsT0KMQvjVL0IGgxtLKkA
VVOlcrA/34oSXxQT5sggbgbBjqll+4xopGwDz0+hCx+KK7h1HNs10Lc67IG58J9nR+tGzaf4pScG
wNRJAsCk3h1MW1AB9Q9Ij7XHIYJfB+3NNnsrgW4AWRL+4mYICspULHwCu0hkCPV6Yz/TN/Y6pLgr
H+FomsylmO7v+O1lIcFpIfQBbgYuvIygmks2BrbIfXtnAaXuZThUUw0G2UjTGpb+eJmePL+TwKTh
4B/YyTqNRqYkZAoIBmyAnKRf4dbM547jDm85r8tKAnJlV0EA41goGrpd8nwQJnRhPnrbEQmJ0LbU
GkNC44+YeGyt4wbdE//gTSjEFyQcv2tFOXbG/Ewc/nGkDM+gAKKp8gBgDcKDZFJNAEexi1LKfsaU
a7mjU9AI/0rD2Y4XzRG5jiUzVo/V8Fj9B+Eiob11dtB3jJ4h9Ppx43uiALAh+s1oG3fXchtRNdsd
FCiEyQetJaXuDdvEL47q77aQjlANmQsP+rNt5+EDro/unZFj2zHkaeRxkZ+SA2rfTAvmG3grkBQP
dvIW6zTM6tfKlbKg4vQeC/K4+ePsf9bpeARRO7iBeAK2P2o4FNjGjPEIj0dUZlHDLWuxDg32zcgo
DtDR2WRdhmbfpbR8uxJOrjbqM2K4E6S3dXOD7tMn9lJ+ajeANGfUu3b0tFxGCLaBAMnvC/Pq1ZeZ
UTKAqXNeuNI5XaZPKSi6yvFvxbM5apZxwpQHePG2TopGyXfXsxRY3ltE3Ji/+5T0TSCAiB0KFHNc
5nP9+61Ak+AYFh5SbxTeh7S4DJPPLsNUAvFeqD/VlpT/gvmJwGIGgqkstxxqVPVPX/64GA0dJZVz
7oExgCg6e1cN/t3s2MmfGJH/dx3AjtSmKvIP4WFex95JVwia54TpGpEckgsl6Th7xUNh/bj9q3Fy
zFFUIlQOZB6UJK3m+xyJHR5gNEFfzPApGwpwVuR1tLtVG7CaNg9g31ANOsowc4MgEhN3Nxk8i9iE
smudLwqCq0HB2idkPvmQbIVztW/jC3is1718o+sDZWvxbqqmVPq0fczYVaTf6z6vXl3geGIfO0QU
jSAl9X0OkQnojgbsjjv2eM8Vvj3/w0dSUhQ15V0W5asxue+8aME1JwgfhBlBBp2lSLRmb12LD01i
HmxAH+0V6va4+NAL2IgSXuEvZqq/P04wGf1cqhXaeSoTZkGvN1fdoX2C+sr61R5KXDcqc8h7oMLa
rPiN445HKg8CGLMmRphIQb5QFToXDr7WSrO9b9bNWKmb1q9hWWVgP8aFpbVwWgoEmimGx2rPNnU/
SV/xKaaO6XK8kLMlz17LOe6MIk5FY2zQgLINbCkbckJIw+GJJDXLKlIc2JGMqHulDG4OEeF8OvpB
4sde7GWZFT1pIbgnoy4u0CHSLSO+r8C6jM1RVSIN4/w7Wp/UaoKsNX5WzltORpvC+73vyF0wfDDU
q7fHDgbpQlQy521CMrm44q4zetPZKAmiyUA+o2t13MVLzpt/w9l41t6sm/T9Q37blzcHppjpWDpv
bIh4I9KyXPUYehTEzMx3Xht350Cf78eHUM5DhYy97KYOXMkpC0RIyytEq9IR9zLJjD9aH5E/bFBY
EkrR3oX1JrhWuFAp9vn+q4lWsxflBXNAe4WuuxrpLd3wV0Q5YgMK2tTN8oZ1qS15kPM1mQc6vFOb
t2P/5zQ3uoU9EXpx+0etIYV0PQ0vRPCS3lUtdF+5chWODRlNwEV+dmRf6symFbvKdruaORoMqqns
MXFK0/sFGZayUtTsd6Dn4DD80cOQ4nvnoRO1/LE3+mi0F+5q9lQfwLqk71ZyHllIakcJVc9N0BTI
uTpOu7jyOe6NSyyygJuk9crCptgdjPcEoAYat/VH2Rl5SFH4TVxvAOgbdP9C5HCy2ktJc/Ngy+RW
TqCv3SW0bD31ev0fGgzTltbSPop9wivj/kIcilmu0PDgeeTai7+UhMho/cXK+Zn0zoq4qlwP7+sb
IhaSpJvXQk881gmExp65HBVM0KiOSfB4NFNioYZGtGLFbLHy5HNLllC4CaupY2lf5H7jR2riE+bw
rPs+txGZYNKV/Yy+6thmf96KbUi1SoSI9MjSJRdnzcG80vO17Q38Tv4upnO4Qf3YwcEmxTV5QLQU
GlhlbWL0qUD3EEUWF7etV3uGNNRc+fL6HS3+y7U5ZcVT97+Lxz21DtmK1Rot0X18Euf8RNJwdduE
21thMoPH+6P8E/TJOgxTKinfvV5wBlfrppQRZoWQW9cIP4VsFq36tF9UKMRWYZt3gqyGkNjSb1Jc
KKGKHtXp+vEcFwNSfM82UK4EbRJq6KpOmu2RZxQ6yYfNCimM51/KEUyRQ+Nq3MsGjj+KlU6KGb5P
8TQIq4CfWwlHMBRSUgVSVUPj2foYwTJ17npPDf2FpSuriVT/at90slLb5VKZZu2BB0k6BupkBpM0
pwFdkgyu+DQ6NUUMuUbZAHpACODHqO7kXmnfhQQNmojGwZmYpZDgxTu5IoptrxXfCwdft9pG8A78
4gvKKN5Ljg1AcXWL4qJ7R30wDMABaT/w1iMCN413VUul7zi8s3uD/yniDpg0PO2JuXNBZML89DiQ
xsSd0oJQFL7CIc8EP7udnG5BeGzT4AyRQ7+U3KBHA0cWYDsj/nwpZJZWS/rTufupWcAVNcS6q2Iq
JnxmiFS8ITrtikQpyzxKhOsujo+/hm+MDjTuYcVfjHUoXVbdLEzdwVFdVBFdqu/XYu3aYgFawF3Q
TvmH/w9J4o8mFluYGVd+d/nbX12sM0pZPXCxR6uzElbPVfiL66RXcmGvpJ4bkV/FF+96u3qq+aJA
n4SKgC6sIGCG/4+HNAIxwY4+CTCwp2GJSWNYr2ShuKvixoS3w3RLG4v1MKMGDEwstZ7DUvC9W4tQ
eskeYUP369zSyYvWqO9CB33kwNIeaFS+pRLGhZbmmhx9CL1QpOlDDQ3JEGIwanREABHu6cA5cUZu
rZ6anmcuGhtAC8g9WnpBcr5wb08PRSNSV9ps5nAfpQh9nNgkqujDtXF6oDuFQXVEcSUNET8BHbEE
WYr8eaUoVWBcr0uu6SxDHu8Ie3PgOnoiWF778LViJ2GB6VIeE/cGFdIzsHCneVgq9VADi0/NHnve
KXoSeC2Q8AeTpRMex505zCx04CYEu2IUaziledPckjk9xl0OJAejlW0X9crB+UNtoDekLi+5PUd5
QI5Abcw4iN7FLwaKT7SOGDCsmvaLN+lI7foSqSRUYr99XTo/JqGbStWOBaoudKzsqv7E0mcKpWaT
JtliFj0QKEAxq/8tUgMW0rKBByBhDe2MMv+oKuHnJIFKWnRvo0L5Kg/t89iDcHWFsJ+9WTsyUujR
2Z6V3EssHSFWosf/KvLHbavkXbNY9oSj5cyJtbaKptcoXHrvCytkdgyUJ1QbCf9U3zYiESSTgCot
pdt61ZgF6tGWWGBwdkir0WIToi8AgqE5GqR05Ue/auprZpA/+I3kUCIKnK+2xTmcG46mHTfu2pf+
THT5UyN2nOUHdOwEMgETyPw4Lax/Cauy79bjevDAlIqGO6rD57e3N1CEZLKw1O5ix9ZQV+s1hQmS
USLmhm2bI6dr2imdfXdJxVQWCd1kNCtgt93PDp4C9IHC7XKFiIuCOdiZACshK6F8bjSqnBYpgTJF
BIdjQEy3uEGofugqNYlWpv75SMlzBZZOBIG9dU2+xVKp9MQNa/zu+g/8ZYM9CSoOnpVM5S32w3zg
eG93cP9otkF72xDqmDe4h+cEqLUoFCYiiqUG2IVWYR6sV+v2CyyvWp0CkvkhMRF2RPyAJTlJsJaT
J2mmZhWzwK3Va1jPu2HggIXtckCXCTXukr9IVoDK2NSb1nIl9h6OvLaeOyx778jN82S5AuI+F3nX
u7aUXtg+B5ea0XddHX70+RCbsydQm56/rpYdHwmqeHP0MVRJsw+BhoREsvDWizoruef60O/QQn7J
eA7OS4/gHqhDlgUlezUmS43lvv2htQUW1tiw16qCuz5h4vhspR/mj/UDRokqjkJSmftnP43MamaI
MrWCPufJMPM/YM51jDQB8XQdAwVp/Nyp61ZcMkHmPwoiV8JGezxh1aCTWlSlk7LKfSh/qGFjth/C
jxfZRwAGG62b39Svo1/oQsSRmhinvomYM8iXlN15ZqseH6to+YUTIjsdFh7kzKLvoUa5o+Cb03nN
bqzJHeMXHnPUF08PwEvgarWlcOk9Zw1PVPmQO2LeCKA7gE38tvfuIMtTneYYE1j/y5MQnVXa563t
yIsIBmeXbIPqWNUaCOdnDSLuXirLoeHaNes5Dwl1UWJAlKdiC9oPywicZmuVOVAauy4a3CkDiYla
kB8lKufDhPVn0fpWpcQhZXO2nZdzOkD1l9PN19FDsmemxr+yeFtFPddv6RdPZ5xZTh3769whQM9a
vVIShPkVdqA7QzHSM0hj/9p2ZOyuGZ9kL8+9b5GfPiF2uIjc/ui44HzcD69IYhigxpxJTfHCvBds
SdhlcC6JBBBjLZZUcVTHbdLJC0QpmyFlchE2y3KEfCmvyUK+AatQzDGEL5MPYcdWaYe297YNn6sT
kzcJX3lU5oaP/85oyp5Lwn7RIXocFZWyql4BDdA+ILj48WAwa+LgTVhUcUIez4QHC2uzFSXp/oi3
qicO5wK+z0Y5ks3Vz48i0Aj3okV4jlSrMReYryaVhyZTsoqsNS4x+bhoVAr108x14llrHW6NkMoG
TJpWpKiLDzdZtPgytW4SOsnQ9mDrzvhr1bi74tjcSDS/fbV4fRKcKPazexnV47ehX2z5t2oETaLX
9/yNvJU4bmPP8ufyc9gpUyq/c+Hx1zdafkJAKmRprN1Sne5LGSMFA1lyNGfJyW4feR/QKMgsFkvA
KeBGZabc6ZSD11LvSlgRIUz3FJV+3OtBclpskw12CmCELv2ekv5vML8UFd5qDiBOHHq/WEriMcXF
YPtxAL6A0zmutTnoBbe7rE6luwUFur4iBLEMgTo7CRKKoQxoLHCDjAH/0P4uwtTIE0nTOiRAFCMw
u4fv0LmcO9nnAi/mRTuIYQON/UZiOdqfCl6fQnJvpBWGHT9Yq7VHtIqWNkb2G0h0tUXFiydnzYsL
Qn2eRjHVy1C/np1xDsBQHeoY7KLsRcsopvMPkccVOzPzljdPDrpj3SV5NJeEZQ/gKqDGYfUzWzVo
Z35+a+j7LYfXQjZS/iETi9jfawjkqtsd8SOXNAV28udIYPeLemW5hyn93ZMhyv56sv3a28z0Ci5U
zQnsKARsyb1OqXSsgHORYXG+OL4BkCDG5rrRawXA9JIE8TfOJT9YDF7dOA9RrFGllGUPL67GR+yy
Gee/vtfLORUyxCM29QfUxXH6cpNb6+l7Q8ii0wiL7ZceKGtVUn+Ih7DraV+uumjFAn8rG3QR/kOD
0wBrDgl+B93o+bwVnNDaXGSLUyqKmtDxMgc10nrRahF3ITJEyOh6cZWRK/dqpl+IJxRdEWsizT2p
WMuTd5laObfK3+PsFCJqgN/PKUzNFvm9EQ3qzuZ3pucBMSiriBEpA1dPVc0OsbOaUZyHmxsdaP8y
HwGoT2Ndj6yf0CjZDAxeSvcacvNHhCiJv19DEfJHQJnF4e7jDW1wFzdrJp9dDHRihEIZsu96vF1t
g+MnPJh3vS/ybzFRKnvS5LPFfPjb1FA0PexRn/KAIehbWz28ptDbGFHC6c3AG8RyCoZ86JuKlrXQ
OsL3zsao2WcWF845FO41+3lvMhs14hVuSe1kIHO856TCMGZec1Y7CMzO6yIRCwQcRGJYUoZiJX6X
df6nWNElCW4kv9+bTynyhE8YdTOPEtVpIQzeVk3a5MpFFMy+AHxv8KFGvqiUo+h0zZYaEpH7Fnyz
VbnM3jv7NXCd5OcxmegKHWLxatyG2vKm9KD3q4DffFkWaKZeVmXtst8WydpiSDsoGAmcYGnsBjLn
QLnWyl4jBM3qvPm1XvKKbbldvtFlF0kc5QWpdEgIyocoSMO3sUKhl5sGr3POs7rkXma8SW9u0tSg
Ge+oXF/NMczkd2BfRDxbfLo8NXMte3nTbd09cbVPLdJwx0lGW8vDG4ZDNKZb45TFG+4DqWX83NQv
2a58GpGdHwRL6PUYRSbli3JmqTScctcyiwXigYOeLNu6Ke+qxr2hKnG895NSAO3YNa5q2+RjoZAW
l4Mmp1XuaL+4Ijk3K2DFxiTzldWbDyWzi5YYB8ZPBqpv2Qo9zq+wRo34D75LhNiB/Y5ACkl4b2cQ
n6D3pYkvW9UvFxaGAZS32zB46YpGBq9fyAGYFQ9bc9NlAPCaPiX1RIKeAJjMYVV1EIqtOP5ngTaP
Lk0Q2DGDd2H8XQ35DpzPdvPtyNCEfM6W3dO/XGfGQs7Wh20nA6uPyIL3tvr/GNoTNbbkyJ3y4MF7
iHIf438MdRvjBBjCPc+gVr9FmSMAVd4VKV856PCzuS20gCGyqnZf8+hzy63Vc7/+I6ezqrTNoUYg
UH7c8xqBKvij8qVJbS8bTVcxJUUZWhmf1Ad+EG8LNzDE1wOLxn1Qj2M+P093chW4RTuiRA3TTWnD
1H2BznDxkMrwuG4j4YVck1ZzPRpVvSZ4eqzHPMY+DxbgPzKLbh3t9amxTbAS2bUAZSIOr8Q0UUsC
7Op5EefCRpo82pi0cmJGEGyImVuiH1k0CT1HAY9XUHpJUDO6HTr9/MpOTnMb8XfuqP4B163CGy4T
4kl71J/3lp7VOTf9a1vr9LdPgUXaxRBWi5msKHKVYpMitmW+hAuwBEUWkL4y5Xu7/xXXGiHhF1hr
3v65WsR1YklvxZc5Mfi6m4WRBzTSHgYSj4HS+YgqIGLlm5hn9rzi/e81wALy7EiEGqX8KencBwGn
re3ayXBLvDgAh6VwgVecxae530PS5qgtL+qela0wglZgOkbselvh/Hd4yyzHF62xiRh1MM0O7hO+
lHexlpe9b6YUw8XQdn3ep38sWhSDRl+eMwubYWP3xUO0JSe/l9VkZHxm4Cn+B8wBbJnvs5JHfdGF
McfB+sozr78WwRn0EZI2YKTm4dxZdk3MjLAUlALKM9ZPVY5woDxuv2mXj1jjm2q+FbO8T2GcAogc
mDqMZIx3asbnbnHFxRuSI7uV1ePjWHBeEP7Ko8qsbKBoA5zl/EITVqqJkLHAZuOV+UbbQA3gCcsf
l/bwLoLxWiKEtE4GPCZRLSPnZJpwqDpq7iHSOhqqrZkX9gltqLkyCpcnbRcF0ms3k/twKqwk6jq7
pBqLK6LZEsznz1sbfmC9GDwIDDVi0eUFLiAqvatJgp/LPFMLBC6q2mGC337r9nld9C9zDP1AHhQ7
Hf1aX7vxdn5H5v7A2USjTei9FByBlgLhkw8jN2OlqcWCbHsT451TiJIoisRMAMUYnGNNWLFPv74D
4L8bkM3S0tU5TnNwifw2x8hYwKHRKoETu6KkM96KJXR/NDmhLkHtNzWp4mSbUN9qKeML81JRq29u
EYZIVzAlcTFkCjcw4kjtDUgSR0a+AAAA
HYDRA_EOF

putb app/src/main/res/drawable-nodpi/ic_launcher_art.webp <<'HYDRA_EOF'
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
czxcnCCtVOxRBWOvabGZrBVMcAY1Ytdf8zmAAAA=
HYDRA_EOF

putb app/src/main/res/drawable-nodpi/ic_launcher_bg.webp <<'HYDRA_EOF'
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
QAAA
HYDRA_EOF

putb app/src/main/res/drawable-nodpi/ic_launcher_fg.webp <<'HYDRA_EOF'
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
zYTABaZRkgAhE6G8ACYhMkAJNoJVEkAA
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
    <background android:drawable="@drawable/ic_launcher_bg" />
    <foreground android:drawable="@drawable/ic_launcher_fg" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
HYDRA_EOF

putv app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml <<'HYDRA_EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_bg" />
    <foreground android:drawable="@drawable/ic_launcher_fg" />
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
    <string name="about_text">Hydra 0.6 · отрубишь одну голову — вырастут две. Сделано для тех, кому нужен интернет без компромиссов.</string>
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
    <string name="need_apps_toast">Сначала выберите приложения (Меню → Дополнительно → Параметры подключения → Управление исключёнными приложениями) или включите режим «Все, кроме выбранных»</string>

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
    <string name="licenses_text">Гидра использует открытые компоненты: usque (лицензия MIT), quic-go, wireguard-go и другие под свободными лицензиями. Полные тексты — в файле NOTICE репозитория проекта.</string>

    <string name="banner_blocked_title">Все маршруты ведут в запрещённый дата-центр</string>
    <string name="banner_blocked_text">В этой сети Cloudflare всегда отправляет тебя в дата-центр, который ты запретил. Выбери выход:</string>
    <string name="banner_use_cell">Через мобильную сеть</string>
    <string name="banner_allow">Подключиться всё равно</string>

    <string name="step_account_wg">Конфигурация WireGuard · %1$s</string>
    <string name="wg_title">Конфигурации WARP (WireGuard)</string>
    <string name="wg_none">Конфигурации WireGuard ещё нет</string>
    <string name="wg_ok">Конфигурация готова · %1$s</string>
    <string name="wg_hint">Гидра создаёт обычную конфигурацию WARP (как wgcf) и подключается по ней. Серверы WireGuard у Cloudflare нередко ведут в другой дата-центр, чем MASQUE (например, во Франкфурт вместо Москвы). Конфигурацию можно скопировать в другие приложения или импортировать свою .conf (WireGuard / AmneziaWG с Jc, Jmin, Jmax).</string>
    <string name="wg_create">Создать конфигурацию WARP (WireGuard)</string>
    <string name="wg_copy">Копировать .conf</string>
    <string name="wg_import">Импорт .conf</string>
    <string name="wg_delete">Удалить конфигурацию</string>
    <string name="wg_copied">Конфигурация скопирована</string>
    <string name="wg_nothing">Конфигурации ещё нет</string>
    <string name="wg_imported">Конфигурация импортирована</string>

    <string name="notif_connecting">Подключаюсь…</string>
    <string name="notif_up">Подключено · %1$s · %2$d мс</string>
    <string name="notif_reconnecting">Переподключаюсь…</string>
    <string name="notif_failed">Нет соединения, повторяю</string>
    <string name="diag_tunnel_title">Через Гидру (туннель)</string>
    <string name="diag_tunnel_off">Туннель выключен. Подключись, чтобы увидеть его проверки.</string>
    <string name="diag_proto">Протокол</string>
    <string name="diag_ping">Задержка</string>
    <string name="proto_masque">MASQUE (HTTP/3, QUIC)</string>
    <string name="proto_masque2">MASQUE (HTTP/2)</string>
    <string name="proto_wg">WireGuard</string>
    <string name="proto_unknown">неизвестно</string>
    <string name="diag_direct_title">Прямое соединение (мимо VPN)</string>
    <string name="diag_direct_hint">Сама Гидра работает мимо VPN, поэтому эти проверки идут напрямую. «WARP: выключен» здесь нормально.</string>
    <string name="persist_title">Постоянная работа</string>
    <string name="persist_hint">Гидра подключается после загрузки телефона и держит соединение, пока ты сам не выключишь. Для самой крепкой хватки включи системный «Всегда включённый VPN», разреши работу в фоне и (на Xiaomi) автозапуск.</string>
    <string name="btn_always_on">Системный «Всегда включённый VPN»</string>
    <string name="btn_battery">Разрешить работу в фоне</string>
    <string name="btn_autostart_xiaomi">Автозапуск (Xiaomi)</string>
    <string name="kill_info">Пока туннель не работает или переключается, трафик приложений в VPN блокируется, а не утекает. Системный пункт «Блокировать подключения без VPN» делает это ещё строже.</string>
    <string name="proto_title">Протокол</string>
    <string name="proto_auto">Авто</string>
    <string name="proto_masque_chip">MASQUE</string>
    <string name="proto_wg_chip">WireGuard</string>
    <string name="proto_hint">Авто: оба протокола страхуют друг друга. Если один перестал работать, второй подхватывает.</string>
    <string name="wg_edit">Править конфигурацию</string>
    <string name="wg_cancel">Отменить правку</string>
    <string name="wg_save">Сохранить конфигурацию</string>
    <string name="menu_title">Меню</string>
    <string name="menu_advanced">Дополнительно</string>
    <string name="menu_diag">Диагностика</string>
    <string name="home_private">Ваше интернет-подключение конфиденциально.</string>
    <string name="home_not_private">Ваше интернет-подключение не конфиденциально.</string>
    <string name="btn_apply">Применить</string>
    <string name="btn_reset">Сбросить</string>
    <string name="btn_cancel">Отмена</string>
    <string name="btn_ok">Да</string>
    <string name="value_default">По умолчанию</string>
    <string name="conn_params">Параметры подключения</string>
    <string name="adv_more">Расширенные настройки Гидры</string>
    <string name="adv_more_sub">Язык, дата-центры, канал связи, автозапуск, аккаунт и WireGuard</string>
    <string name="conn_apps">Управление исключёнными приложениями</string>
    <string name="conn_routes">Управление исключёнными маршрутами</string>
    <string name="conn_dns">Параметры DNS</string>
    <string name="conn_proto">Протокол туннелирования</string>
    <string name="conn_reset_keys">Сбросить ключи безопасности</string>
    <string name="conn_reset_keys_q">Аккаунты WARP будут удалены и созданы заново. VPN выключится.</string>
    <string name="conn_reset_all">Сбросить все настройки</string>
    <string name="conn_reset_all_q">Все настройки приложения вернутся к значениям по умолчанию. Аккаунт сохранится. VPN выключится.</string>
    <string name="conn_sni">Польз. SNI (MASQUE)</string>
    <string name="conn_sni_sub">Переопределяет SNI для туннеля MASQUE</string>
    <string name="conn_sni_hint">например cdnjs.cloudflare.com</string>
    <string name="conn_endpoint">Польз. конечная точка</string>
    <string name="conn_endpoint_sub">Свой адрес сервера, пробуется первым</string>
    <string name="conn_endpoint_hint">IP-адрес с портом</string>
    <string name="dns_note">Свой DNS работает внутри туннеля WARP: сервер видит адрес Cloudflare, а не ваш. Изменения применяются после переподключения.</string>
    <string name="dns_use">Использовать польз. DNS</string>
    <string name="dns_server">DNS-сервер</string>
    <string name="dns_default">Cloudflare 1.1.1.1</string>
    <string name="dns_hint">IP через запятую, например 8.8.8.8</string>
    <string name="dns_soon">Пока поддерживаются только IP-адреса (DNS поверх WARP). DoH и DoT по имени хоста появятся позже.</string>
    <string name="routes_list">Исключённые IP-адреса и подсети</string>
    <string name="routes_note">Указанные подсети идут напрямую, мимо VPN. Работает на Android 13 и новее.</string>
    <string name="routes_add">Ввести исключённые маршруты</string>
    <string name="routes_default">Восстановить значения по умолчанию</string>
    <string name="routes_hint">например 192.168.0.0/16</string>
    <string name="diag_on">ВКЛ</string>
    <string name="diag_off">ВЫКЛ</string>
    <string name="diag_sec_conn">Подключение</string>
    <string name="diag_conn">Подключение</string>
    <string name="diag_strategy">Стратегия</string>
    <string name="diag_sec_dev">Ваше устройство</string>
    <string name="diag_nettype">Тип подключения</string>
    <string name="net_wifi">Wi-Fi</string>
    <string name="net_cell">Мобильная сеть</string>
    <string name="diag_sec_cfg">Конфигурация клиента</string>
    <string name="diag_id">ID (MASQUE)</string>
    <string name="diag_id_wg">ID (WireGuard)</string>
    <string name="diag_sec_stats">Статистика</string>
    <string name="diag_rx">Получено</string>
    <string name="diag_tx">Отправлено</string>
    <string name="diag_sec_tools">Инструменты</string>
    <string name="diag_quick">Быстрая проверка</string>
    <string name="diag_quick_sub">Узнать публичный IP и дата-центр напрямую</string>
    <string name="diag_full">Полная диагностика</string>
    <string name="diag_full_sub">DNS, HTTPS, API Cloudflare, сервер MASQUE, IPv6, интернет</string>
    <string name="diag_errors">Ошибки</string>
    <string name="diag_errors_sub">Только сбои и предупреждения из журнала</string>
    <string name="diag_share">Поделиться отчётом</string>
    <string name="diag_share_sub">Версия, устройство, проверки и журнал (без ключей)</string>
    <string name="diag_copy_report">Скопировать отчёт</string>
    <string name="diag_report_copied">Скопировано</string>
    <string name="errors_none">Ошибок в журнале нет.</string>
    <string name="errors_refresh">Обновить</string>
    <string name="chk_dns">DNS (cloudflare.com)</string>
    <string name="chk_https">HTTPS (cloudflare.com)</string>
    <string name="chk_api">API регистрации WARP</string>
    <string name="chk_masque">Сервер MASQUE (TCP 443)</string>
    <string name="chk_v6">IPv6</string>
    <string name="chk_web">Интернет (google.com)</string>
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
    <string name="about_text">Hydra 0.6 · cut off one head and two grow back. Built for people who want the internet without compromises.</string>
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
    <string name="need_apps_toast">First choose apps (Menu → Advanced → Connection settings → Manage excluded apps) or switch to the "All except selected" mode</string>

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
    <string name="licenses_text">Hydra uses open-source components: usque (MIT License), quic-go, wireguard-go and others under permissive licenses. Full notices are in the NOTICE file of the project repository.</string>

    <string name="banner_blocked_title">Every route leads to a blocked datacenter</string>
    <string name="banner_blocked_text">On this network Cloudflare always sends you to a datacenter you blocked. Pick a way out:</string>
    <string name="banner_use_cell">Via mobile network</string>
    <string name="banner_allow">Connect anyway</string>

    <string name="step_account_wg">WireGuard config · %1$s</string>
    <string name="wg_title">WARP configurations (WireGuard)</string>
    <string name="wg_none">No WireGuard config yet</string>
    <string name="wg_ok">Config ready · %1$s</string>
    <string name="wg_hint">Hydra creates a regular WARP config (like wgcf) and connects with it. WireGuard servers of Cloudflare often lead to another datacenter than MASQUE (for example Frankfurt instead of Moscow). You can copy the config to other apps or import your own .conf (WireGuard / AmneziaWG with Jc, Jmin, Jmax).</string>
    <string name="wg_create">Create WARP config (WireGuard)</string>
    <string name="wg_copy">Copy .conf</string>
    <string name="wg_import">Import .conf</string>
    <string name="wg_delete">Delete config</string>
    <string name="wg_copied">Config copied</string>
    <string name="wg_nothing">No config yet</string>
    <string name="wg_imported">Config imported</string>

    <string name="notif_connecting">Connecting…</string>
    <string name="notif_up">Connected · %1$s · %2$d ms</string>
    <string name="notif_reconnecting">Reconnecting…</string>
    <string name="notif_failed">No connection, retrying</string>
    <string name="diag_tunnel_title">Through Hydra (tunnel)</string>
    <string name="diag_tunnel_off">The tunnel is off. Connect to see its checks.</string>
    <string name="diag_proto">Protocol</string>
    <string name="diag_ping">Latency</string>
    <string name="proto_masque">MASQUE (HTTP/3, QUIC)</string>
    <string name="proto_masque2">MASQUE (HTTP/2)</string>
    <string name="proto_wg">WireGuard</string>
    <string name="proto_unknown">unknown</string>
    <string name="diag_direct_title">Direct connection (bypasses VPN)</string>
    <string name="diag_direct_hint">Hydra itself stays outside the VPN, so these checks go directly. “WARP: off” here is normal.</string>
    <string name="persist_title">Always running</string>
    <string name="persist_hint">Hydra connects after the phone boots and holds the connection until you turn it off. For the strongest hold, enable the system Always-on VPN, allow background work and (Xiaomi) autostart.</string>
    <string name="btn_always_on">System Always-on VPN</string>
    <string name="btn_battery">Allow background work</string>
    <string name="btn_autostart_xiaomi">Autostart (Xiaomi)</string>
    <string name="kill_info">While the tunnel is down or switching, traffic of routed apps is blocked, not leaked. The system option “Block connections without VPN” makes it even stricter.</string>
    <string name="proto_title">Protocol</string>
    <string name="proto_auto">Auto</string>
    <string name="proto_masque_chip">MASQUE</string>
    <string name="proto_wg_chip">WireGuard</string>
    <string name="proto_hint">Auto: both protocols back each other up. If one stops working, the other takes over.</string>
    <string name="wg_edit">Edit config</string>
    <string name="wg_cancel">Cancel editing</string>
    <string name="wg_save">Save config</string>
    <string name="menu_title">Menu</string>
    <string name="menu_advanced">Advanced</string>
    <string name="menu_diag">Diagnostics</string>
    <string name="home_private">Your internet connection is private.</string>
    <string name="home_not_private">Your internet connection is not private.</string>
    <string name="btn_apply">Apply</string>
    <string name="btn_reset">Reset</string>
    <string name="btn_cancel">Cancel</string>
    <string name="btn_ok">Yes</string>
    <string name="value_default">Default</string>
    <string name="conn_params">Connection settings</string>
    <string name="adv_more">Hydra advanced options</string>
    <string name="adv_more_sub">Language, data centers, channel, autostart, account and WireGuard</string>
    <string name="conn_apps">Manage excluded apps</string>
    <string name="conn_routes">Manage excluded routes</string>
    <string name="conn_dns">DNS settings</string>
    <string name="conn_proto">Tunnel protocol</string>
    <string name="conn_reset_keys">Reset security keys</string>
    <string name="conn_reset_keys_q">WARP accounts will be deleted and created again. The VPN will turn off.</string>
    <string name="conn_reset_all">Reset all settings</string>
    <string name="conn_reset_all_q">All app settings return to defaults. The account is kept. The VPN will turn off.</string>
    <string name="conn_sni">Custom SNI (MASQUE)</string>
    <string name="conn_sni_sub">Overrides the SNI of the MASQUE tunnel</string>
    <string name="conn_sni_hint">e.g. cdnjs.cloudflare.com</string>
    <string name="conn_endpoint">Custom endpoint</string>
    <string name="conn_endpoint_sub">Your own server address, tried first</string>
    <string name="conn_endpoint_hint">IP address with port</string>
    <string name="dns_note">Custom DNS works inside the WARP tunnel: the server sees a Cloudflare address, not yours. Changes apply after reconnecting.</string>
    <string name="dns_use">Use custom DNS</string>
    <string name="dns_server">DNS server</string>
    <string name="dns_default">Cloudflare 1.1.1.1</string>
    <string name="dns_hint">IPs separated by commas, e.g. 8.8.8.8</string>
    <string name="dns_soon">Only IP addresses are supported for now (DNS over WARP). DoH and DoT by hostname will come later.</string>
    <string name="routes_list">Excluded IP addresses and subnets</string>
    <string name="routes_note">These subnets go directly, bypassing the VPN. Works on Android 13 and newer.</string>
    <string name="routes_add">Add excluded route</string>
    <string name="routes_default">Restore defaults</string>
    <string name="routes_hint">e.g. 192.168.0.0/16</string>
    <string name="diag_on">ON</string>
    <string name="diag_off">OFF</string>
    <string name="diag_sec_conn">Connection</string>
    <string name="diag_conn">Connection</string>
    <string name="diag_strategy">Strategy</string>
    <string name="diag_sec_dev">Your device</string>
    <string name="diag_nettype">Connection type</string>
    <string name="net_wifi">Wi-Fi</string>
    <string name="net_cell">Mobile network</string>
    <string name="diag_sec_cfg">Client configuration</string>
    <string name="diag_id">ID (MASQUE)</string>
    <string name="diag_id_wg">ID (WireGuard)</string>
    <string name="diag_sec_stats">Statistics</string>
    <string name="diag_rx">Received</string>
    <string name="diag_tx">Sent</string>
    <string name="diag_sec_tools">Tools</string>
    <string name="diag_quick">Quick check</string>
    <string name="diag_quick_sub">Find the public IP and data center directly</string>
    <string name="diag_full">Full diagnostics</string>
    <string name="diag_full_sub">DNS, HTTPS, Cloudflare API, MASQUE server, IPv6, internet</string>
    <string name="diag_errors">Errors</string>
    <string name="diag_errors_sub">Only failures and warnings from the journal</string>
    <string name="diag_share">Share report</string>
    <string name="diag_share_sub">Version, device, checks and journal (no keys)</string>
    <string name="diag_copy_report">Copy report</string>
    <string name="diag_report_copied">Copied</string>
    <string name="errors_none">No errors in the journal.</string>
    <string name="errors_refresh">Refresh</string>
    <string name="chk_dns">DNS (cloudflare.com)</string>
    <string name="chk_https">HTTPS (cloudflare.com)</string>
    <string name="chk_api">WARP registration API</string>
    <string name="chk_masque">MASQUE server (TCP 443)</string>
    <string name="chk_v6">IPv6</string>
    <string name="chk_web">Internet (google.com)</string>
</resources>
HYDRA_EOF

putv app/src/main/res/values/themes.xml <<'HYDRA_EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="Theme.Hydra" parent="android:Theme.Material.NoActionBar" />
</resources>
HYDRA_EOF

putv build.gradle.kts <<'HYDRA_EOF'
plugins {
    id("com.android.application") version "8.7.3" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21" apply false
}
HYDRA_EOF

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

putv "$GODIR/custom.go" <<'HYDRA_EOF'
package hydra

import (
	"net"
	"strconv"
	"strings"
)

// CustomEndpointStrategies — стратегии MASQUE для адреса, который задал пользователь
// ("IP" или "IP:порт"). Они пробуются раньше остальных. Неверный адрес даёт nil.
func CustomEndpointStrategies(ep string) []Strategy {
	ep = strings.TrimSpace(ep)
	if ep == "" {
		return nil
	}
	host := hostOnly(ep)
	if net.ParseIP(host) == nil {
		return nil
	}
	hostPort := ep
	if _, _, err := net.SplitHostPort(ep); err != nil {
		hostPort = net.JoinHostPort(host, "443")
	}
	mk := func(proto, alias string, fv *fakeVariant) Strategy {
		p := map[string]string{"endpoint": hostPort, "sni": defaultMasqueSNI, "h2": "0"}
		if proto == "h2" {
			p["h2"] = "1"
		}
		if fv != nil && fv.count > 0 {
			p["fake"] = fv.sni
			p["fttl"] = strconv.Itoa(fv.ttl)
			p["fcount"] = strconv.Itoa(fv.count)
			p["fsize"] = strconv.Itoa(fv.size)
		}
		return Strategy{ID: proto + "/" + hostPort + "/" + alias, Transport: "masque", Params: p}
	}
	var out []Strategy
	for i := 0; i < 3 && i < len(fakeVariants); i++ {
		out = append(out, mk("h3", fakeVariants[i].alias, &fakeVariants[i]))
	}
	return append(out, mk("h2", "std", nil))
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
	DropV6       bool          // в аккаунте нет IPv6: пакеты v6 из TUN отбрасываются
}

func DefaultEngineConfig() EngineConfig {
	return EngineConfig{ProbeEvery: 3 * time.Second, UpTimeout: 6 * time.Second, BadProbes: 3, TCPCheck: true}
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
	rx, tx  uint64 // байты из туннеля в приложения / из приложений в туннель
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
		if e.cfg.DropV6 && n > 0 && buf[0]>>4 == 6 {
			continue
		}
		atomic.AddUint64(&e.tx, uint64(n))
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
	atomic.AddUint64(&d.e.rx, uint64(len(pkt)))
	_, err := d.e.tun.Write(pkt)
	return err
}

// Traffic — сколько байт получено из туннеля и отправлено в него с запуска.
func (e *Engine) Traffic() (rx, tx uint64) {
	return atomic.LoadUint64(&e.rx), atomic.LoadUint64(&e.tx)
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
	// старые пробы от прошлых попыток в очереди только мешают
	for drained := false; !drained; {
		select {
		case <-e.probeQ:
		default:
			drained = true
		}
	}

	actx, cancel := context.WithCancel(ctx)
	defer cancel()
	dev := &attemptDev{e: e, done: actx.Done()}
	errc := make(chan error, 1)
	go func() { errc <- e.cfg.Runner(actx, dev, s) }()

	timeout := e.cfg.UpTimeout
	if e.cfg.Mem.Worked(nk, s.ID) {
		timeout = timeout * 5 / 3 // уже работала здесь: на медленной сети рукопожатие бывает 5–6 с
	}
	start := time.Now()
	var colo string
	var rtt time.Duration
	up := false
	for !up && time.Since(start) < timeout {
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
		if s.Transport == "wg" {
			hint = " — похоже, провайдер режет WireGuard (UDP) к этому адресу"
		} else if s.Params["h2"] != "1" {
			hint = " — похоже, провайдер режет QUIC к этому адресу"
		}
		msg := fmt.Sprintf("нет ответа от туннеля за %d с%s", int(timeout.Seconds()), hint)
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
			epKey := hostOnly(ep)
			if until, ok := blocked[epKey]; ep != "" && ok && time.Now().Before(until) {
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
					blocked[epKey] = time.Now().Add(10 * time.Minute)
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
			msg = "⛔ все адреса сейчас ведут в запрещённые дата-центры — жду"
		case ran == 0:
			msg = "нет стратегий"
		case sawBlocked:
			msg = "⛔ рабочие маршруты ведут только в запрещённые дата-центры"
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

putv "$GODIR/events.go" <<'HYDRA_EOF'
package hydra

import (
	"context"
	"time"
)

// Cause — почему сломалось. Нужен для понятного статуса и точечного лечения.
type Cause int

const (
	CauseUnknown Cause = iota
	CauseNetwork       // сети нет вообще
	CauseDNS
	CauseDPI      // сеть есть, но наш трафик режут
	CauseEndpoint // сеть и DNS в порядке, сервер не отвечает
)

func (c Cause) String() string {
	switch c {
	case CauseNetwork:
		return "нет сети"
	case CauseDNS:
		return "сломан DNS"
	case CauseDPI:
		return "оператор режет трафик (DPI)"
	case CauseEndpoint:
		return "сервер не отвечает"
	}
	return "неизвестно"
}

// Diagnoser определяет причину сбоя (реальная реализация — позже).
type Diagnoser interface {
	Diagnose(ctx context.Context) Cause
}

type nopDiagnoser struct{}

func (nopDiagnoser) Diagnose(context.Context) Cause { return CauseUnknown }

// Event — то, что UI показывает человеку.
type Event struct {
	Kind     string // connecting | connected | degraded | failover | failed
	Strategy string
	Cause    Cause
	Msg      string
	At       time.Time
}
HYDRA_EOF

putv "$GODIR/front.go" <<'HYDRA_EOF'
package hydra

import (
	"context"
	"encoding/binary"
	"io"
	"net"
	"strconv"
	"sync"
	"time"
)

// Front — постоянный локальный SOCKS5-вход. Android-часть (hev-socks5-tunnel)
// всегда ходит в один и тот же адрес, а туннель под ним Гидра меняет на лету:
// новые соединения сразу идут через новый туннель.
type Front struct {
	mu          sync.RWMutex
	cur         Tunnel
	ln          net.Listener
	DialTimeout time.Duration
}

func NewFront() *Front { return &Front{DialTimeout: 10 * time.Second} }

// Set подставляет активный туннель (nil — туннеля нет).
func (f *Front) Set(t Tunnel) {
	f.mu.Lock()
	f.cur = t
	f.mu.Unlock()
}

func (f *Front) tunnel() Tunnel {
	f.mu.RLock()
	defer f.mu.RUnlock()
	return f.cur
}

// Listen начинает слушать addr (например "127.0.0.1:0") и возвращает реальный адрес.
func (f *Front) Listen(addr string) (string, error) {
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return "", err
	}
	f.ln = ln
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go f.handle(c)
		}
	}()
	return ln.Addr().String(), nil
}

func (f *Front) Close() error {
	if f.ln != nil {
		return f.ln.Close()
	}
	return nil
}

func socksReply(c net.Conn, code byte) error {
	_, err := c.Write([]byte{5, code, 0, 1, 0, 0, 0, 0, 0, 0})
	return err
}

func (f *Front) handle(c net.Conn) {
	defer c.Close()
	c.SetDeadline(time.Now().Add(10 * time.Second))

	var hdr [2]byte
	if _, err := io.ReadFull(c, hdr[:]); err != nil || hdr[0] != 5 {
		return
	}
	if _, err := io.ReadFull(c, make([]byte, hdr[1])); err != nil {
		return
	}
	if _, err := c.Write([]byte{5, 0}); err != nil {
		return
	}

	var req [4]byte
	if _, err := io.ReadFull(c, req[:]); err != nil || req[0] != 5 {
		return
	}
	var host string
	switch req[3] {
	case 1:
		var b [4]byte
		if _, err := io.ReadFull(c, b[:]); err != nil {
			return
		}
		host = net.IP(b[:]).String()
	case 3:
		var l [1]byte
		if _, err := io.ReadFull(c, l[:]); err != nil {
			return
		}
		b := make([]byte, l[0])
		if _, err := io.ReadFull(c, b); err != nil {
			return
		}
		host = string(b)
	case 4:
		var b [16]byte
		if _, err := io.ReadFull(c, b[:]); err != nil {
			return
		}
		host = net.IP(b[:]).String()
	default:
		socksReply(c, 8)
		return
	}
	var pb [2]byte
	if _, err := io.ReadFull(c, pb[:]); err != nil {
		return
	}
	port := binary.BigEndian.Uint16(pb[:])

	if req[1] != 1 { // пока только CONNECT; UDP ASSOCIATE — следующим шагом
		socksReply(c, 7)
		return
	}
	t := f.tunnel()
	if t == nil {
		socksReply(c, 3) // network unreachable
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), f.DialTimeout)
	up, err := t.DialContext(ctx, "tcp", net.JoinHostPort(host, strconv.Itoa(int(port))))
	cancel()
	if err != nil {
		socksReply(c, 5)
		return
	}
	defer up.Close()
	c.SetDeadline(time.Time{})
	if socksReply(c, 0) != nil {
		return
	}
	pipe(c, up)
}

func pipe(a, b net.Conn) {
	done := make(chan struct{}, 2)
	cp := func(dst, src net.Conn) {
		io.Copy(dst, src)
		if cw, ok := dst.(interface{ CloseWrite() error }); ok {
			cw.CloseWrite()
		} else {
			dst.Close()
		}
		done <- struct{}{}
	}
	go cp(a, b)
	go cp(b, a)
	<-done
	<-done
}
HYDRA_EOF

putv "$GODIR/front_test.go" <<'HYDRA_EOF'
package hydra

import (
	"context"
	"io"
	"net"
	"strconv"
	"sync/atomic"
	"testing"
	"time"
)

func (t *fakeTunnel) DialContext(ctx context.Context, network, addr string) (net.Conn, error) {
	atomic.AddInt32(&t.dials, 1)
	var d net.Dialer
	return d.DialContext(ctx, network, addr)
}

func echoServer(t *testing.T) string {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go func() { io.Copy(c, c); c.Close() }()
		}
	}()
	return ln.Addr().String()
}

// socksConnect делает рукопожатие SOCKS5 и возвращает соединение и код ответа.
func socksConnect(t *testing.T, proxy, target string) (net.Conn, byte) {
	c, err := net.DialTimeout("tcp", proxy, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { c.Close() })
	c.SetDeadline(time.Now().Add(2 * time.Second))
	c.Write([]byte{5, 1, 0})
	var r [2]byte
	if _, err := io.ReadFull(c, r[:]); err != nil || r[0] != 5 || r[1] != 0 {
		t.Fatalf("рукопожатие: %v %v", r, err)
	}
	host, ps, _ := net.SplitHostPort(target)
	port, _ := strconv.Atoi(ps)
	req := []byte{5, 1, 0, 1}
	req = append(req, net.ParseIP(host).To4()...)
	req = append(req, byte(port>>8), byte(port))
	c.Write(req)
	var rep [10]byte
	if _, err := io.ReadFull(c, rep[:]); err != nil {
		t.Fatalf("ответ: %v", err)
	}
	return c, rep[1]
}

func TestFrontSwapsTunnels(t *testing.T) {
	echo := echoServer(t)
	front := NewFront()
	addr, err := front.Listen("127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { front.Close() })

	t1, t2 := newFakeTunnel(0), newFakeTunnel(0)

	front.Set(t1)
	c, code := socksConnect(t, addr, echo)
	if code != 0 {
		t.Fatalf("код %d", code)
	}
	c.Write([]byte("ping"))
	buf := make([]byte, 4)
	if _, err := io.ReadFull(c, buf); err != nil || string(buf) != "ping" {
		t.Fatalf("эхо: %q %v", buf, err)
	}
	if atomic.LoadInt32(&t1.dials) != 1 {
		t.Fatal("соединение должно идти через t1")
	}

	front.Set(t2) // «горячая» подмена
	if _, code := socksConnect(t, addr, echo); code != 0 {
		t.Fatalf("код %d", code)
	}
	if atomic.LoadInt32(&t2.dials) != 1 || atomic.LoadInt32(&t1.dials) != 1 {
		t.Fatal("новое соединение должно идти через t2")
	}

	front.Set(nil)
	if _, code := socksConnect(t, addr, echo); code != 3 {
		t.Fatalf("без туннеля ждали код 3, получили %d", code)
	}
}
HYDRA_EOF

putv gradle.properties <<'HYDRA_EOF'
org.gradle.jvmargs=-Xmx3g -Dfile.encoding=UTF-8
android.useAndroidX=true
android.nonTransitiveRClass=true
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
		l = strings.TrimSpace(l)
		if l == "" || strings.Contains(l, "Hop Limit too small") {
			continue // служебные пакеты с hop limit 1 — не интересны
		}
		Logf("· %s", l)
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
		if !h2 {
			// быстрая проверка маршрута: «network is unreachable» (например, нет IPv6) — сразу отказ
			c, derr := net.DialUDP("udp", nil, &net.UDPAddr{IP: ip, Port: port})
			if derr != nil {
				Logf("   ✘ нет маршрута до %s: %v", host, derr)
				return fmt.Errorf("нет маршрута до %s", host)
			}
			c.Close()
		}
		var ep net.Addr = &net.UDPAddr{IP: ip, Port: port}
		if h2 {
			ep = &net.TCPAddr{IP: ip, Port: port}
		} else if fsni := s.Params["fake"]; fsni != "" {
			// фейковые QUIC-пакеты с малым TTL перед рукопожатием (как у Zarp)
			var fk FakeSpec
			fk.TTL = atoiDefault(s.Params["fttl"], 5)
			for i := 0; i < atoiDefault(s.Params["fcount"], 6); i++ {
				if p, err := BuildFakeQUICInitial(fsni, atoiDefault(s.Params["fsize"], 1357)); err == nil {
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

putv "$GODIR/memory.go" <<'HYDRA_EOF'
package hydra

import (
	"encoding/json"
	"math"
	"os"
	"sort"
	"sync"
	"time"
)

type stat struct {
	OK     int       `json:"ok"`
	Fail   int       `json:"fail"`
	EWMAms float64   `json:"ewma_ms"`
	LastOK time.Time `json:"last_ok"`
}

// Memory — «память Гидры»: что работало в какой сети.
// Ключ сети (net) выдаёт Android-часть: например "wifi:<hash>" или "cell:25001".
type Memory struct {
	mu      sync.Mutex
	path    string
	pending bool // отложенное сохранение уже запланировано
	Nets map[string]map[string]*stat `json:"nets"`
}

func LoadMemory(path string) (*Memory, error) {
	m := &Memory{path: path, Nets: map[string]map[string]*stat{}}
	if path == "" {
		return m, nil
	}
	b, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return m, nil
	}
	if err != nil {
		return m, err
	}
	if err := json.Unmarshal(b, m); err != nil {
		m.Nets = map[string]map[string]*stat{}
		return m, err
	}
	if m.Nets == nil {
		m.Nets = map[string]map[string]*stat{}
	}
	return m, nil
}

func (m *Memory) Save() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.path == "" {
		return nil
	}
	b, err := json.Marshal(m)
	if err != nil {
		return err
	}
	tmp := m.path + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, m.path)
}

func (m *Memory) Record(net, id string, ok bool, d time.Duration) {
	m.mu.Lock()
	defer m.mu.Unlock()
	n := m.Nets[net]
	if n == nil {
		n = map[string]*stat{}
		m.Nets[net] = n
	}
	s := n[id]
	if s == nil {
		s = &stat{}
		n[id] = s
	}
	if ok {
		s.OK++
		s.LastOK = time.Now()
		ms := float64(d.Milliseconds())
		if s.EWMAms == 0 {
			s.EWMAms = ms
		} else {
			s.EWMAms = 0.7*s.EWMAms + 0.3*ms
		}
	} else {
		s.Fail++
	}
	if s.OK+s.Fail > 20 { // забываем старое: DPI меняется
		s.OK /= 2
		s.Fail /= 2
	}
	// Сохраняем сразу после результата (с паузой, чтобы не писать на каждый чих):
	// если систему убьёт процесс, накопленный опыт не пропадёт.
	if m.path != "" && !m.pending {
		m.pending = true
		time.AfterFunc(2*time.Second, func() {
			m.mu.Lock()
			m.pending = false
			m.mu.Unlock()
			_ = m.Save()
		})
	}
}

// Worked: стратегия уже хотя бы раз подключалась в этой сети.
func (m *Memory) Worked(net, id string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	st := m.Nets[net][id]
	return st != nil && st.OK > 0
}

// Rank сортирует стратегии: лучшие для этой сети — первыми.
// Неизвестные получают нейтральный балл и пробуются после проверенных.
func (m *Memory) Rank(net string, all []Strategy) []Strategy {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := append([]Strategy(nil), all...)
	score := func(s Strategy) float64 {
		st := m.Nets[net][s.ID]
		if st == nil {
			return 0.5
		}
		rate := float64(st.OK+1) / float64(st.OK+st.Fail+2)
		pen := math.Min(st.EWMAms/5000, 0.3)
		bonus := 0.0
		if time.Since(st.LastOK) < 24*time.Hour {
			bonus = 0.1
		}
		return rate - pen + bonus
	}
	sort.SliceStable(out, func(i, j int) bool { return score(out[i]) > score(out[j]) })
	return out
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
	"os"
	"path/filepath"
	"strings"
	"time"

	hydra "hydra/core"
)

const version = "0.6.0"

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
func wgPath(dir string) string      { return filepath.Join(dir, "wg.json") }

// AccountID возвращает ID сохранённого аккаунта или "".
func AccountID(dir string) string {
	a, err := hydra.LoadAccount(accountPath(dir))
	if err != nil || a == nil {
		return ""
	}
	return a.ID
}

// RegisterReport регистрирует аккаунт WARP для MASQUE (если его ещё нет). Первая строка
// отчёта: "OK" или "FAIL <вид>", вид: rate_limited | blocked | dns | api | storage.
func RegisterReport(dir string) string { return registerReport(accountPath(dir), false) }

// RegisterWireguardReport создаёт обычную конфигурацию WARP (WireGuard), как wgcf.
func RegisterWireguardReport(dir string) string { return registerReport(wgPath(dir), true) }

func registerReport(path string, wg bool) string {
	if a, err := hydra.LoadAccount(path); err == nil && a != nil {
		return "OK\nуже есть: " + a.ID
	}
	var sb strings.Builder
	r := hydra.NewRegistrar()
	r.WG = wg
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

// DeleteAccount удаляет аккаунт MASQUE (для «Сбросить ключи»).
func DeleteAccount(dir string) { os.Remove(accountPath(dir)) }

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
	a := primaryAccount(dir)
	if a == nil {
		return ""
	}
	return stripMask(a.AddrV4)
}

// primaryAccount: аккаунт MASQUE, а если его нет — конфигурация WireGuard.
func primaryAccount(dir string) *hydra.Account {
	if a, err := hydra.LoadAccount(accountPath(dir)); err == nil && a != nil {
		return a
	}
	if a, err := hydra.LoadAccount(wgPath(dir)); err == nil && a != nil {
		return a
	}
	return nil
}

// AccountAddr6 — IPv6-адрес устройства внутри туннеля.
func AccountAddr6(dir string) string {
	a := primaryAccount(dir)
	if a == nil {
		return ""
	}
	return stripMask(a.AddrV6)
}

// WireguardAccountID — ID конфигурации WireGuard ("custom" для импортированной) или "".
func WireguardAccountID(dir string) string {
	a, err := hydra.LoadAccount(wgPath(dir))
	if err != nil || a == nil {
		return ""
	}
	return a.ID
}

// ExportWireguardConfig — текст .conf для других приложений (WireGuard/AmneziaWG) или "".
func ExportWireguardConfig(dir string) string {
	a, err := hydra.LoadAccount(wgPath(dir))
	if err != nil || a == nil {
		return ""
	}
	return a.WGConfig()
}

// ImportWireguardConfig сохраняет свою конфигурацию (.conf); пустой ответ — успех.
func ImportWireguardConfig(dir, text string) string {
	a, err := hydra.ParseWGConfig(text)
	if err != nil {
		return err.Error()
	}
	if err := a.Save(wgPath(dir)); err != nil {
		return err.Error()
	}
	return ""
}

// DeleteWireguardConfig удаляет сохранённую конфигурацию WireGuard.
func DeleteWireguardConfig(dir string) { os.Remove(wgPath(dir)) }
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
	polProto = "auto"
	netKey   = "default"
	polSNI   = "" // свой SNI для туннеля MASQUE ("" — по умолчанию)
	polEP    = "" // свой адрес сервера "IP" или "IP:порт" ("" — не задан)
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

// SetProtocol выбирает протокол: "auto" (оба, запасной подхватывает), "masque" или "wg".
func SetProtocol(p string) {
	polMu.Lock()
	polProto = strings.TrimSpace(p)
	polMu.Unlock()
}

func currentProtocol() string {
	polMu.Lock()
	defer polMu.Unlock()
	return polProto
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

// SetCustomSNI переопределяет SNI в TLS-рукопожатии туннеля MASQUE ("" — сброс).
func SetCustomSNI(s string) {
	polMu.Lock()
	polSNI = strings.TrimSpace(s)
	polMu.Unlock()
}

// SetCustomEndpoint задаёт свой адрес сервера MASQUE ("IP" или "IP:порт"): он пробуется первым.
func SetCustomEndpoint(s string) {
	polMu.Lock()
	polEP = strings.TrimSpace(s)
	polMu.Unlock()
}

func currentCustom() (sni, ep string) {
	polMu.Lock()
	defer polMu.Unlock()
	return polSNI, polEP
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
	macc, _ := hydra.LoadAccount(accountPath(dir))
	wacc, _ := hydra.LoadAccount(wgPath(dir))
	if macc == nil && wacc == nil {
		return "нет аккаунта WARP"
	}
	runners := map[string]hydra.Runner{}
	var strategies []hydra.Strategy
	if macc != nil {
		r, err := hydra.NewMasqueRunner(macc)
		if err != nil {
			return err.Error()
		}
		runners["masque"] = r
	}
	if wacc != nil {
		r, err := hydra.NewWGRunner(wacc)
		if err != nil {
			return err.Error()
		}
		runners["wg"] = r
	}
	var mS, wS []hydra.Strategy
	if macc != nil {
		mS = hydra.MasqueStrategies(macc)
		sni, cep := currentCustom()
		if cep != "" {
			mS = append(hydra.CustomEndpointStrategies(cep), mS...) // свой адрес — первым
		}
		if sni != "" {
			for i := range mS {
				mS[i].Params["sni"] = sni
			}
		}
	}
	if wacc != nil {
		wS = hydra.WGStrategies(wacc)
	}
	switch currentProtocol() {
	case "masque":
		if len(mS) > 0 {
			wS = nil
		}
	case "wg":
		if len(wS) > 0 {
			mS = nil
		}
	}
	strategies = hydra.Interleave(mS, wS, 3)
	runner := func(ctx context.Context, d hydra.PacketDevice, s hydra.Strategy) error {
		r := runners[s.Transport]
		if r == nil {
			return fmt.Errorf("нет транспорта %q", s.Transport)
		}
		return r(ctx, d, s)
	}
	acc := primaryAccount(dir)
	ip := net.ParseIP(strings.Split(acc.AddrV4, "/")[0])
	if ip == nil {
		return "в аккаунте нет IPv4-адреса"
	}
	mem, _ := hydra.LoadMemory(filepath.Join(dir, "memory.json"))

	cfg := hydra.DefaultEngineConfig()
	cfg.LocalIP = ip
	cfg.Strategies = strategies
	cfg.Runner = runner
	cfg.Policy = currentPolicy()
	cfg.Mem = mem
	cfg.NetKey = currentNetKey
	cfg.NetChanged = netEvents
	cfg.SoftFallback = currentFallback()
	cfg.DropV6 = stripMask(acc.AddrV6) == ""

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
	rx, tx := e.Traffic()
	return fmt.Sprintf("%s|%s|%s|%d|%s|%d|%d", st.State, st.Strategy, st.Colo,
		st.RTT.Milliseconds(), strings.ReplaceAll(st.Message, "|", "/"), rx, tx)
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

putv "$GODIR/orchestrator_test.go" <<'HYDRA_EOF'
package hydra

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"
)

type fakeTunnel struct {
	done  chan struct{}
	once  sync.Once
	dials int32
}

func newFakeTunnel(dieAfter time.Duration) *fakeTunnel {
	t := &fakeTunnel{done: make(chan struct{})}
	if dieAfter > 0 {
		time.AfterFunc(dieAfter, func() { t.Close() })
	}
	return t
}
func (t *fakeTunnel) Probe(context.Context) (Quality, error) { return Quality{RTT: 10 * time.Millisecond}, nil }
func (t *fakeTunnel) Done() <-chan struct{}                  { return t.done }
func (t *fakeTunnel) Close() error                           { t.once.Do(func() { close(t.done) }); return nil }

type fakeTransport struct {
	strategies []Strategy
	dial       func(ctx context.Context, s Strategy) (Tunnel, error)
}

func (f *fakeTransport) Name() string                { return "fake" }
func (f *fakeTransport) Strategies() []Strategy      { return f.strategies }
func (f *fakeTransport) Dial(ctx context.Context, s Strategy) (Tunnel, error) { return f.dial(ctx, s) }

func fastCfg() Config {
	c := DefaultConfig()
	c.Stagger = 50 * time.Millisecond
	c.ProbeEvery = 20 * time.Millisecond
	return c
}

func TestRaceWinnerAndMemory(t *testing.T) {
	ft := &fakeTransport{
		strategies: []Strategy{{ID: "bad", Transport: "fake"}, {ID: "slow", Transport: "fake"}, {ID: "good", Transport: "fake"}},
		dial: func(ctx context.Context, s Strategy) (Tunnel, error) {
			switch s.ID {
			case "bad":
				return nil, errors.New("blocked")
			case "slow":
				select {
				case <-time.After(2 * time.Second):
					return newFakeTunnel(0), nil
				case <-ctx.Done():
					return nil, ctx.Err()
				}
			}
			time.Sleep(50 * time.Millisecond)
			return newFakeTunnel(0), nil
		},
	}
	mem, _ := LoadMemory("")
	o := New(fastCfg(), mem, []Transport{ft}, nil)

	t0 := time.Now()
	tun, s, err := o.race(context.Background(), "wifi:home", "")
	if err != nil || s.ID != "good" || time.Since(t0) > time.Second {
		t.Fatalf("ожидали good быстро, получили %v %v %v", s.ID, err, time.Since(t0))
	}
	tun.Close()

	// второй раз память должна поставить good первым
	if first := o.candidates("wifi:home", "")[0].ID; first != "good" {
		t.Fatalf("память не подняла good, первый: %s", first)
	}
	// в другой сети порядок исходный
	if first := o.candidates("cell:other", "")[0].ID; first != "bad" {
		t.Fatalf("в чужой сети память не должна влиять, первый: %s", first)
	}
}

func TestFailoverToStandby(t *testing.T) {
	ft := &fakeTransport{
		strategies: []Strategy{{ID: "A", Transport: "fake"}, {ID: "B", Transport: "fake"}},
		dial: func(ctx context.Context, s Strategy) (Tunnel, error) {
			if s.ID == "A" {
				return newFakeTunnel(150 * time.Millisecond), nil // A умирает
			}
			return newFakeTunnel(0), nil
		},
	}
	mem, _ := LoadMemory("")
	o := New(fastCfg(), mem, []Transport{ft}, nil)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	go o.Run(ctx, func() string { return "wifi:home" })

	var got []string
	for {
		select {
		case e := <-o.Events():
			got = append(got, e.Kind+":"+e.Strategy)
			if e.Kind == "failover" {
				if e.Strategy != "B" {
					t.Fatalf("резерв должен быть B, события: %v", got)
				}
				return
			}
		case <-ctx.Done():
			t.Fatalf("failover не случился, события: %v", got)
		}
	}
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
	"crypto/ecdh"
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

	// Для конфигураций WireGuard (Kind == "wg"): ключ — X25519 в base64.
	Kind     string `json:"kind,omitempty"`
	Custom   bool   `json:"custom,omitempty"` // импортирована пользователем
	Jc       int    `json:"jc,omitempty"`     // «мусорные» пакеты перед рукопожатием (как в AmneziaWG)
	Jmin     int    `json:"jmin,omitempty"`
	Jmax     int    `json:"jmax,omitempty"`
	ClientID string `json:"client_id,omitempty"`
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
	base string // адрес API (у Cloudflare их два: api.cloudflareclient.com и api.devices.cloudflare.com)
}

type Registrar struct {
	Dialers  []NamedDialer // пусто = системная сеть
	Methods  []string      // пусто = все способы
	BaseURL  string        // для тестов; по умолчанию боевой API
	Stagger  time.Duration // пауза между стартами маршрутов
	Timeout  time.Duration // на один маршрут
	Attempts int           // сколько раундов гонки
	Backoff  time.Duration // базовая пауза между раундами (удваивается)
	WG       bool          // регистрировать конфигурацию WireGuard (а не MASQUE)
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
	type baseSpec struct{ tag, url string }
	bases := []baseSpec{
		{"cf", apiBaseURL},
		{"dev4471", "https://api.devices.cloudflare.com/v0a4471"},
		{"dev5641", "https://api.devices.cloudflare.com/v0a5641"},
	}
	if r.BaseURL != "" { // тесты
		bases = []baseSpec{{"", r.BaseURL}}
	}
	var out []route
	for _, m := range ms { // сначала дешёвые способы на всех сетях
		for _, b := range bases {
			for _, d := range ds {
				name := m.name + "@" + d.Name
				if b.tag != "" {
					name += "/" + b.tag
				}
				out = append(out, route{name: name, d: d, m: m, base: b.url})
			}
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
	ClientID string `json:"client_id"`
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
	if r.WG {
		return r.attemptWG(ctx, cl, rt.base)
	}

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
	if err := r.do(ctx, cl, rt.base, "POST", "/reg", "", regBody, &reg); err != nil {
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
	if err := r.do(ctx, cl, rt.base, "PATCH", "/reg/"+rr.ID, rr.Token, enroll, &en); err != nil {
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

func (r *Registrar) do(ctx context.Context, cl *http.Client, base, verb, path, token string, body, out any) error {
	b, err := json.Marshal(body)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, verb, base+path, bytes.NewReader(b))
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

// attemptWG — регистрация обычного (WireGuard) устройства WARP: как делает wgcf.
func (r *Registrar) attemptWG(ctx context.Context, cl *http.Client, base string) (*Account, error) {
	k, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		return nil, err
	}
	body := map[string]any{
		"key":           base64.StdEncoding.EncodeToString(k.PublicKey().Bytes()),
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
	if err := r.do(ctx, cl, base, "POST", "/reg", "", body, &reg); err != nil {
		return nil, err
	}
	rr := reg.norm()
	if rr.ID == "" || rr.Token == "" || len(rr.Config.Peers) == 0 {
		return nil, &protoError{"в ответе API нет данных о сервере WireGuard"}
	}
	cfg := rr.Config
	host := hostOnly(cfg.Peers[0].Endpoint.V4)
	if host == "" {
		host = hostOnly(cfg.Peers[0].Endpoint.Host)
	}
	if host == "" {
		host = "162.159.192.1"
	}
	return &Account{
		Kind:          "wg",
		ID:            rr.ID,
		Token:         rr.Token,
		PrivateKey:    base64.StdEncoding.EncodeToString(k.Bytes()),
		PeerPublicKey: cfg.Peers[0].PublicKey,
		EndpointV4:    net.JoinHostPort(host, "2408"),
		AddrV4:        cfg.Interface.Addresses.V4,
		AddrV6:        cfg.Interface.Addresses.V6,
		ClientID:      cfg.ClientID,
		Jc:            4, Jmin: 40, Jmax: 70,
		Created: time.Now().UTC(),
	}, nil
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

putv settings.gradle.kts <<'HYDRA_EOF'
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
	size  int // размер каждого фейкового пакета, байт
}

// Фейковые QUIC-пакеты перед рукопожатием (см. UDPRelay). По журналам Zarp:
// «google ×3» (3 пакета по 1200 байт) — основная стратегия, «VK ×6» (по 1357 байт) — запасная.
var fakeVariants = []fakeVariant{
	{"g3", "www.google.com", 5, 3, 1200},
	{"vk5x6", "vk.com", 5, 6, 1357},
	{"g6", "www.google.com", 5, 6, 1200},
	{"vk4x6", "vk.com", 4, 6, 1357},
	{"vk6x6", "vk.com", 6, 6, 1357},
	{"ya5x6", "ya.ru", 5, 6, 1357},
	{"plain", "", 0, 0, 0},
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
	// Только настоящие серверы MASQUE. Адреса WireGuard (162.159.192/193/195.x,
	// 188.114.96/97.x) отвечают на QUIC, но на рукопожатии получают TLS handshake failure.
	for _, h := range []string{
		"162.159.198.1",
		"2606:4700:103::2", "2606:4700:103::1",
	} {
		add(h)
	}

	mk := func(proto, ep, alias, sni string, fv *fakeVariant) Strategy {
		hostPort := ep
		if _, _, err := net.SplitHostPort(ep); err != nil {
			hostPort = net.JoinHostPort(ep, "443")
		}
		p := map[string]string{
			"endpoint": hostPort,
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
			p["fsize"] = strconv.Itoa(fv.size)
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
	// другие порты: некоторые провайдеры режут именно UDP 443 (у Zarp рабочими бывали 500 и др.)
	for _, port := range []string{"500", "1701", "4500"} {
		for _, ep := range []string{"162.159.198.2", "162.159.198.1"} {
			for i := 0; i < 2; i++ {
				fv := &fakeVariants[i]
				out = append(out, mk("h3", net.JoinHostPort(ep, port), fv.alias, defaultMasqueSNI, fv))
			}
		}
	}
	for _, ep := range eps {
		out = append(out, mk("h2", ep, "std", defaultMasqueSNI, nil))
	}
	return out
}

func describeStrategy(s Strategy) string {
	if s.Transport == "wg" {
		out := "WireGuard → " + s.Params["endpoint"]
		if sg := s.Params["sig"]; sg != "" {
			out += ", сигнатура " + sg
		}
		if jc := s.Params["jc"]; jc != "" {
			out += fmt.Sprintf(", мусор %s × %s–%s байт", jc, s.Params["jmin"], s.Params["jmax"])
		}
		return out
	}
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
	if len(ss) < 30 {
		t.Fatalf("мало стратегий: %d", len(ss))
	}
	first := ss[0]
	if first.ID != "h3/162.159.198.2/g3" || first.Params["fake"] != "www.google.com" ||
		first.Params["fcount"] != "3" || first.Params["fsize"] != "1200" {
		t.Fatalf("первой должна идти основная стратегия Zarp «google ×3»: %+v", first)
	}
	sawPort500 := false
	for _, s := range ss {
		if s.Params["endpoint"] == "162.159.198.2:500" {
			sawPort500 = true
		}
	}
	if !sawPort500 {
		t.Fatal("нет стратегий с портом 500")
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

putv "$GODIR/transport.go" <<'HYDRA_EOF'
package hydra

import (
	"context"
	"net"
	"time"
)

// Strategy — одна конкретная схема подключения (транспорт + параметры).
// ID должен быть стабильным: по нему Память Гидры копит статистику.
type Strategy struct {
	ID        string
	Transport string
	Params    map[string]string
}

// Quality — результат одной пробы туннеля.
type Quality struct {
	RTT  time.Duration
	Loss float64 // 0..1
}

// Tunnel — живое соединение. Время жизни туннеля НЕ привязано к ctx из Dial:
// ctx ограничивает только установку соединения.
type Tunnel interface {
	Probe(ctx context.Context) (Quality, error)
	// DialContext открывает TCP-соединение к addr через туннель (для SOCKS-входа).
	DialContext(ctx context.Context, network, addr string) (net.Conn, error)
	Done() <-chan struct{} // закрывается, когда туннель умер
	Close() error
}

// Transport — бэкенд (WARP/MASQUE, AmneziaWG, позже свой сервер).
type Transport interface {
	Name() string
	Strategies() []Strategy
	Dial(ctx context.Context, s Strategy) (Tunnel, error)
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
	TTL      int // 0 — отправлять с обычным TTL
	// PerInit — «мусор» перед каждым рукопожатием WireGuard (сообщение типа 1).
	PerInit func() [][]byte
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
			if r.fake.PerInit != nil && IsWGInit(buf[:n]) {
				for _, j := range r.fake.PerInit() {
					up.Write(j)
				}
			}
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
	if len(r.fake.Payloads) == 0 {
		return
	}
	if r.fake.TTL > 0 {
		if err := setTTL(c, r.fake.TTL); err != nil {
			Logf("   ⚠ не удалось выставить TTL=%d (%v) — фейки не отправляю", r.fake.TTL, err)
			return
		}
	}
	total := 0
	for _, p := range r.fake.Payloads {
		if _, err := c.Write(p); err == nil {
			total += len(p)
		}
	}
	if r.fake.TTL > 0 {
		setTTL(c, 64)
	}
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
	"strings"
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

func TestJournalWriterFiltersNoise(t *testing.T) {
	JournalClear()
	w := JournalWriter{}
	w.Write([]byte("dropping proxied packet (96 bytes) that can't be proxied: connect-ip: datagram Hop Limit too small: 1\n"))
	w.Write([]byte("Connected to MASQUE server\n"))
	txt := JournalText(0)
	if !strings.Contains(txt, "Connected to MASQUE server") || strings.Contains(txt, "Hop Limit") {
		t.Fatalf("журнал: %q", txt)
	}
}

func TestUDPRelayJunkBeforeEveryWGInit(t *testing.T) {
	srv, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	defer srv.Close()
	got := make(chan int, 32)
	go func() {
		buf := make([]byte, 2048)
		for {
			n, _, err := srv.ReadFromUDP(buf)
			if err != nil {
				return
			}
			got <- n
		}
	}()
	r, err := StartUDPRelay(srv.LocalAddr().(*net.UDPAddr), FakeSpec{
		PerInit: func() [][]byte { return [][]byte{make([]byte, 41), make([]byte, 42)} },
	})
	if err != nil {
		t.Fatal(err)
	}
	defer r.Close()
	c, _ := net.DialUDP("udp", nil, r.Addr())
	defer c.Close()

	init := append([]byte{1, 0, 0, 0}, make([]byte, 144)...)
	for round := 0; round < 2; round++ {
		c.Write(init)
		for _, want := range []int{41, 42, 148} {
			select {
			case n := <-got:
				if n != want {
					t.Fatalf("раунд %d: ждали пакет %d байт, пришло %d", round, want, n)
				}
			case <-time.After(2 * time.Second):
				t.Fatalf("раунд %d: не дождались пакета %d байт", round, want)
			}
		}
	}
	c.Write(make([]byte, 20)) // не рукопожатие — без «мусора»
	select {
	case n := <-got:
		if n != 20 {
			t.Fatalf("после обычного пакета «мусора» быть не должно, пришло %d", n)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("обычный пакет не дошёл")
	}
}
HYDRA_EOF

putv "$GODIR/wg.go" <<'HYDRA_EOF'
package hydra

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"net"
	"strconv"
	"strings"
)

// WireGuard-транспорт: для обычных конфигураций WARP (как у wgcf) и для своих.
// Адреса WireGuard-серверов Cloudflare (162.159.192/193/195.x, 188.114.96-99.x)
// относятся к другим префиксам, чем MASQUE (162.159.198.x), и многие провайдеры
// маршрутизируют их в другие дата-центры (например, FRA вместо DME).

// IsWGInit: это начало рукопожатия WireGuard (сообщение типа 1, 148 байт)?
func IsWGInit(p []byte) bool {
	return len(p) == 148 && p[0] == 1 && p[1] == 0 && p[2] == 0 && p[3] == 0
}

// GenJunk — «мусорные» пакеты случайной длины, которые отправляются перед
// рукопожатием (как Jc/Jmin/Jmax в AmneziaWG). Настоящий сервер WireGuard их
// просто отбрасывает, а оборудование провайдера теряет сигнатуру WireGuard.
func GenJunk(count, minLen, maxLen int) [][]byte {
	if count <= 0 {
		return nil
	}
	if minLen < 1 {
		minLen = 40
	}
	if maxLen < minLen {
		maxLen = minLen + 30
	}
	out := make([][]byte, count)
	for i := range out {
		r := make([]byte, 1)
		rand.Read(r)
		n := minLen + int(r[0])%(maxLen-minLen+1)
		b := make([]byte, n)
		rand.Read(b)
		if b[0] >= 1 && b[0] <= 4 { // не похоже на сообщения WireGuard
			b[0] = 0xA5
		}
		out[i] = b
	}
	return out
}

func b64ToHex(s string) (string, error) {
	b, err := base64.StdEncoding.DecodeString(strings.TrimSpace(s))
	if err != nil || len(b) != 32 {
		return "", errors.New("ключ WireGuard должен быть 32 байта в base64")
	}
	return hex.EncodeToString(b), nil
}

// WGUAPI строит конфигурацию в формате UAPI wireguard-go; endpoint — адрес
// локального переходника.
func WGUAPI(acc *Account, endpoint string) (string, error) {
	priv, err := b64ToHex(acc.PrivateKey)
	if err != nil {
		return "", fmt.Errorf("PrivateKey: %w", err)
	}
	pub, err := b64ToHex(acc.PeerPublicKey)
	if err != nil {
		return "", fmt.Errorf("PublicKey: %w", err)
	}
	return "private_key=" + priv + "\npublic_key=" + pub + "\nendpoint=" + endpoint +
		"\npersistent_keepalive_interval=25\nallowed_ip=0.0.0.0/0\nallowed_ip=::/0\n", nil
}

func withMask(a string, bits int) string {
	if strings.Contains(a, "/") {
		return a
	}
	return fmt.Sprintf("%s/%d", a, bits)
}

// WGConfig — обычный файл .conf: его можно вставить в любое приложение WireGuard/AmneziaWG.
func (a *Account) WGConfig() string {
	var addrs []string
	if a.AddrV4 != "" {
		addrs = append(addrs, withMask(a.AddrV4, 32))
	}
	if a.AddrV6 != "" {
		addrs = append(addrs, withMask(a.AddrV6, 128))
	}
	var sb strings.Builder
	sb.WriteString("[Interface]\n")
	fmt.Fprintf(&sb, "PrivateKey = %s\n", a.PrivateKey)
	fmt.Fprintf(&sb, "Address = %s\nDNS = 1.1.1.1, 1.0.0.1\nMTU = 1280\n", strings.Join(addrs, ", "))
	if a.Jc > 0 {
		fmt.Fprintf(&sb, "Jc = %d\nJmin = %d\nJmax = %d\nS1 = 0\nS2 = 0\nH1 = 1\nH2 = 2\nH3 = 3\nH4 = 4\n", a.Jc, a.Jmin, a.Jmax)
	}
	sb.WriteString("\n[Peer]\n")
	fmt.Fprintf(&sb, "PublicKey = %s\nAllowedIPs = 0.0.0.0/0, ::/0\nEndpoint = %s\nPersistentKeepalive = 25\n", a.PeerPublicKey, a.EndpointV4)
	return sb.String()
}

// ParseWGConfig разбирает .conf (WireGuard или AmneziaWG). Из обфускации
// AmneziaWG поддерживаются «мусорные» пакеты Jc/Jmin/Jmax; изменение формата
// пакетов (S1/S2/H1–H4) требует отдельной библиотеки и отвергается.
func ParseWGConfig(text string) (*Account, error) {
	acc := &Account{Kind: "wg", Custom: true, ID: "custom"}
	section := ""
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if i := strings.IndexAny(line, "#;"); i >= 0 {
			line = strings.TrimSpace(line[:i])
		}
		if line == "" {
			continue
		}
		if strings.HasPrefix(line, "[") {
			section = strings.ToLower(strings.Trim(line, "[]"))
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		k = strings.ToLower(strings.TrimSpace(k))
		v = strings.TrimSpace(v)
		switch section {
		case "interface":
			switch k {
			case "privatekey":
				acc.PrivateKey = v
			case "address":
				for _, a := range strings.Split(v, ",") {
					a = strings.TrimSpace(a)
					ip := strings.Split(a, "/")[0]
					if p := net.ParseIP(ip); p != nil {
						if p.To4() != nil && acc.AddrV4 == "" {
							acc.AddrV4 = ip
						} else if p.To4() == nil && acc.AddrV6 == "" {
							acc.AddrV6 = ip
						}
					}
				}
			case "jc":
				acc.Jc, _ = strconv.Atoi(v)
			case "jmin":
				acc.Jmin, _ = strconv.Atoi(v)
			case "jmax":
				acc.Jmax, _ = strconv.Atoi(v)
			case "s1", "s2":
				if n, _ := strconv.Atoi(v); n != 0 {
					return nil, errors.New("конфигурация меняет формат пакетов AmneziaWG (S1/S2) — это пока не поддерживается; поддерживаются Jc/Jmin/Jmax")
				}
			case "h1", "h2", "h3", "h4":
				if n, _ := strconv.Atoi(v); n != 0 && strconv.Itoa(n) != string(k[1]) {
					return nil, errors.New("конфигурация меняет формат пакетов AmneziaWG (H1–H4) — это пока не поддерживается; поддерживаются Jc/Jmin/Jmax")
				}
			}
		case "peer":
			switch k {
			case "publickey":
				acc.PeerPublicKey = v
			case "endpoint":
				acc.EndpointV4 = v
			}
		}
	}
	if _, err := b64ToHex(acc.PrivateKey); err != nil {
		return nil, errors.New("в [Interface] нет корректного PrivateKey")
	}
	if _, err := b64ToHex(acc.PeerPublicKey); err != nil {
		return nil, errors.New("в [Peer] нет корректного PublicKey")
	}
	if _, _, err := net.SplitHostPort(acc.EndpointV4); err != nil {
		return nil, errors.New("в [Peer] нет корректного Endpoint (хост:порт)")
	}
	if acc.AddrV4 == "" {
		acc.AddrV4 = "172.16.0.2"
	}
	return acc, nil
}

// BuildQUICLike — пакет, похожий на заголовок QUIC Initial (108 байт), как первый
// пакет Варвары в её захвате: длинный заголовок, версия 1, DCID 8 байт, длина 90.
func BuildQUICLike() []byte {
	b := make([]byte, 108)
	rand.Read(b)
	b[0] = 0xC0
	b[1], b[2], b[3], b[4] = 0, 0, 0, 1
	b[5] = 8
	b[14], b[15] = 0, 0
	b[16], b[17] = 0x40, 90
	return b
}

// BuildSTUNLike — пакет, похожий на запрос STUN Binding (20 байт, magic cookie 2112A442).
func BuildSTUNLike() []byte {
	b := make([]byte, 20)
	rand.Read(b)
	b[0], b[1], b[2], b[3] = 0, 1, 0, 0
	b[4], b[5], b[6], b[7] = 0x21, 0x12, 0xA4, 0x42
	return b
}

// WGPrefix — «пролог» перед каждым рукопожатием WireGuard. По захвату Варвары:
// сначала пакет, похожий на QUIC (или STUN), затем несколько пакетов случайной
// длины, затем настоящее рукопожатие. Сервер Cloudflare всё лишнее отбрасывает.
func WGPrefix(sig string, jc, jmin, jmax int) [][]byte {
	var out [][]byte
	switch sig {
	case "quic":
		out = append(out, BuildQUICLike())
	case "stun":
		out = append(out, BuildSTUNLike())
	}
	if sig != "" {
		out = append(out, GenJunk(4, 80, 120)...)
	}
	return append(out, GenJunk(jc, jmin, jmax)...)
}

// Подсети WireGuard-серверов Cloudflare (по данным Варвары). Разные подсети
// по-разному маршрутизируются провайдерами: на одном Wi-Fi 162.159.192.x ведёт в HEL,
// а 188.114.x — во FRA, тогда как MASQUE (162.159.198.x) — в DME.
var wgSubnets = []string{
	"162.159.192", "188.114.97", "188.114.96", "162.159.193", "162.159.195",
	"188.114.98", "188.114.99", "8.34.70", "8.34.146", "8.35.211",
	"8.39.125", "8.39.204", "8.39.214", "8.47.69", "8.6.112",
}

// WGStrategies — способы подключиться по WireGuard: адрес × порт × пролог.
func WGStrategies(acc *Account) []Strategy {
	if acc == nil || acc.Kind != "wg" {
		return nil
	}
	mk := func(ep, sig string, jc, jmin, jmax int, alias string) Strategy {
		p := map[string]string{"endpoint": ep}
		if sig != "" {
			p["sig"] = sig
		}
		if jc > 0 {
			p["jc"] = strconv.Itoa(jc)
			p["jmin"] = strconv.Itoa(jmin)
			p["jmax"] = strconv.Itoa(jmax)
		}
		return Strategy{ID: fmt.Sprintf("wg/%s/%s", ep, alias), Transport: "wg", Params: p}
	}
	var out []Strategy
	if acc.Custom {
		// своя конфигурация: сначала ровно как написано, потом тот же адрес с прологом или без него
		out = append(out, mk(acc.EndpointV4, "", acc.Jc, acc.Jmin, acc.Jmax, "cfg"))
		if acc.Jc == 0 {
			out = append(out, mk(acc.EndpointV4, "quic", 3, 41, 78, "q3"))
		} else {
			out = append(out, mk(acc.EndpointV4, "", 0, 0, 0, "plain"))
		}
		return out
	}
	hosts := []string{}
	seen := map[string]bool{}
	add := func(h string) {
		if h != "" && net.ParseIP(h) != nil && !seen[h] {
			seen[h] = true
			hosts = append(hosts, h)
		}
	}
	// 1) адрес из аккаунта и проверенный у Варвары 162.159.192.3 — с разными прологами
	first := []string{hostOnly(acc.EndpointV4), "162.159.192.3"}
	for _, h := range first {
		add(h)
	}
	for _, h := range hosts {
		ep := net.JoinHostPort(h, "2408")
		out = append(out, mk(ep, "quic", 3, 41, 78, "q3"))
		out = append(out, mk(ep, "stun", 3, 41, 78, "s3"))
		out = append(out, mk(ep, "", 4, 40, 70, "j4"))
		out = append(out, mk(ep, "", 0, 0, 0, "plain"))
	}
	// 2) по одному адресу из каждой подсети (разные подсети — разные дата-центры)
	for _, host := range []int{3, 1} {
		for _, sub := range wgSubnets {
			h := fmt.Sprintf("%s.%d", sub, host)
			if seen[h] {
				continue
			}
			seen[h] = true
			out = append(out, mk(net.JoinHostPort(h, "2408"), "quic", 3, 41, 78, "q3"))
		}
	}
	// 3) другие порты: некоторые провайдеры режут именно 2408
	for _, port := range []string{"500", "4500", "1701"} {
		out = append(out, mk(net.JoinHostPort("162.159.192.3", port), "quic", 3, 41, 78, "q3"))
	}
	return out
}

// Interleave перемешивает два списка стратегий пачками по chunk: так запасной
// протокол начинает пробоваться сразу, а не после десятков попыток основного.
func Interleave(a, b []Strategy, chunk int) []Strategy {
	if chunk < 1 {
		chunk = 3
	}
	var out []Strategy
	for len(a) > 0 || len(b) > 0 {
		n := chunk
		if n > len(a) {
			n = len(a)
		}
		out = append(out, a[:n]...)
		a = a[n:]
		n = chunk
		if n > len(b) {
			n = len(b)
		}
		out = append(out, b[:n]...)
		b = b[n:]
	}
	return out
}
HYDRA_EOF

putv "$GODIR/wg_runner.go" <<'HYDRA_EOF'
//go:build usque

package hydra

import (
	"context"
	"errors"
	"fmt"
	"net"
	"os"
	"strings"
	"sync"

	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun"
)

// Транспорт WireGuard на wireguard-go. «Сетевая карта» (tun.Device) — в памяти:
// пакеты берутся из PacketDevice движка и туда же возвращаются, поэтому
// проверки дата-центра и TCP работают точно так же, как для MASQUE.

type memTun struct {
	dev    PacketDevice
	mtu    int
	events chan tun.Event
	once   sync.Once
}

func (m *memTun) File() *os.File { return nil }

func (m *memTun) Read(bufs [][]byte, sizes []int, offset int) (int, error) {
	n, err := m.dev.ReadPacket(bufs[0][offset:])
	if err != nil {
		return 0, err
	}
	sizes[0] = n
	return 1, nil
}

func (m *memTun) Write(bufs [][]byte, offset int) (int, error) {
	for i, b := range bufs {
		if err := m.dev.WritePacket(b[offset:]); err != nil {
			return i, err
		}
	}
	return len(bufs), nil
}

func (m *memTun) MTU() (int, error)        { return m.mtu, nil }
func (m *memTun) Name() (string, error)    { return "hydra0", nil }
func (m *memTun) Events() <-chan tun.Event { return m.events }
func (m *memTun) BatchSize() int           { return 1 }
func (m *memTun) Close() error {
	m.once.Do(func() { close(m.events) })
	return nil
}

// NewWGRunner создаёт Runner, который держит туннель WireGuard по конфигурации acc.
func NewWGRunner(acc *Account) (Runner, error) {
	if acc == nil || acc.Kind != "wg" {
		return nil, errors.New("нет конфигурации WireGuard")
	}
	if _, err := WGUAPI(acc, "127.0.0.1:1"); err != nil {
		return nil, err
	}
	return func(ctx context.Context, dev PacketDevice, s Strategy) error {
		remote, err := net.ResolveUDPAddr("udp", s.Params["endpoint"])
		if err != nil {
			return fmt.Errorf("адрес %s: %w", s.Params["endpoint"], err)
		}
		// быстрая проверка маршрута
		if c, derr := net.DialUDP("udp", nil, remote); derr != nil {
			Logf("   ✘ нет маршрута до %s: %v", remote, derr)
			return fmt.Errorf("нет маршрута до %s", remote)
		} else {
			c.Close()
		}

		var fk FakeSpec
		sig := s.Params["sig"]
		jc := atoiDefault(s.Params["jc"], 0)
		jmin, jmax := atoiDefault(s.Params["jmin"], 40), atoiDefault(s.Params["jmax"], 70)
		if sig != "" || jc > 0 {
			fk.PerInit = func() [][]byte { return WGPrefix(sig, jc, jmin, jmax) }
			Logf("   пролог перед рукопожатием: сигнатура %q + мусор %d × %d–%d байт", sig, jc, jmin, jmax)
		}
		relay, err := StartUDPRelay(remote, fk)
		if err != nil {
			return err
		}
		defer relay.Close()

		uapi, err := WGUAPI(acc, relay.Addr().String())
		if err != nil {
			return err
		}
		mt := &memTun{dev: dev, mtu: 1280, events: make(chan tun.Event, 4)}
		logger := &device.Logger{
			Verbosef: func(format string, args ...any) {
				if l := fmt.Sprintf(format, args...); strings.Contains(l, "andshake") {
					Logf("   wg: %s", l)
				}
			},
			Errorf: func(format string, args ...any) {
				Logf("   wg ✘ %s", fmt.Sprintf(format, args...))
			},
		}
		d := device.NewDevice(mt, conn.NewDefaultBind(), logger)
		defer d.Close()
		if err := d.IpcSet(uapi); err != nil {
			return err
		}
		if err := d.Up(); err != nil {
			return err
		}
		Logf("   WireGuard запущен, жду рукопожатие…")
		<-ctx.Done()
		return ctx.Err()
	}, nil
}
HYDRA_EOF

putv "$GODIR/wg_test.go" <<'HYDRA_EOF'
package hydra

import (
	"encoding/base64"
	"strings"
	"testing"
)

func testKey(b byte) string {
	k := make([]byte, 32)
	for i := range k {
		k[i] = b
	}
	return base64.StdEncoding.EncodeToString(k)
}

func TestWGConfigRoundTrip(t *testing.T) {
	a := &Account{Kind: "wg", PrivateKey: testKey(1), PeerPublicKey: testKey(2), EndpointV4: "162.159.192.1:2408",
		AddrV4: "172.16.0.2", AddrV6: "2606:4700:110:8a1c::2", Jc: 4, Jmin: 40, Jmax: 70}
	txt := a.WGConfig()
	for _, want := range []string{"[Interface]", "PrivateKey = " + a.PrivateKey, "172.16.0.2/32", "Jc = 4", "Endpoint = 162.159.192.1:2408"} {
		if !strings.Contains(txt, want) {
			t.Fatalf("в .conf нет %q:\n%s", want, txt)
		}
	}
	b, err := ParseWGConfig(txt)
	if err != nil {
		t.Fatal(err)
	}
	if b.PrivateKey != a.PrivateKey || b.PeerPublicKey != a.PeerPublicKey || b.EndpointV4 != a.EndpointV4 ||
		b.AddrV4 != "172.16.0.2" || b.AddrV6 != "2606:4700:110:8a1c::2" || b.Jc != 4 || b.Jmax != 70 || !b.Custom {
		t.Fatalf("после разбора: %+v", b)
	}
}

func TestParseWGConfigRejectsBadInput(t *testing.T) {
	good := "[Interface]\nPrivateKey = " + testKey(1) + "\nAddress = 172.16.0.2/32\n[Peer]\nPublicKey = " + testKey(2) + "\nEndpoint = 1.2.3.4:51820\n"
	if _, err := ParseWGConfig(good); err != nil {
		t.Fatalf("корректный конфиг отвергнут: %v", err)
	}
	if _, err := ParseWGConfig(strings.Replace(good, "Endpoint = 1.2.3.4:51820", "Endpoint = nowhere", 1)); err == nil {
		t.Fatal("плохой Endpoint должен отвергаться")
	}
	if _, err := ParseWGConfig(strings.Replace(good, "[Peer]", "S1 = 15\n[Peer]", 1)); err == nil {
		t.Fatal("S1 != 0 (изменённый формат пакетов) должен отвергаться")
	}
	if _, err := ParseWGConfig(strings.Replace(good, "[Peer]", "H1 = 1\nH2 = 2\nH3 = 3\nH4 = 4\nJc = 3\nJmin = 20\nJmax = 40\n[Peer]", 1)); err != nil {
		t.Fatalf("стандартные H1–H4 и Jc/Jmin/Jmax должны приниматься: %v", err)
	}
	if _, err := ParseWGConfig("мусор"); err == nil {
		t.Fatal("мусор должен отвергаться")
	}
}

func TestWGUAPIAndJunk(t *testing.T) {
	a := &Account{PrivateKey: testKey(1), PeerPublicKey: testKey(2)}
	u, err := WGUAPI(a, "127.0.0.1:5555")
	if err != nil || !strings.Contains(u, "endpoint=127.0.0.1:5555") || !strings.Contains(u, strings.Repeat("01", 32)) {
		t.Fatalf("UAPI: %q %v", u, err)
	}
	j := GenJunk(4, 40, 70)
	if len(j) != 4 {
		t.Fatalf("нужно 4 пакета, получили %d", len(j))
	}
	for _, p := range j {
		if len(p) < 40 || len(p) > 70 || (p[0] >= 1 && p[0] <= 4) {
			t.Fatalf("плохой «мусорный» пакет: %d байт, первый байт %d", len(p), p[0])
		}
	}
	if !IsWGInit(append([]byte{1, 0, 0, 0}, make([]byte, 144)...)) || IsWGInit(make([]byte, 148)) {
		t.Fatal("IsWGInit определяет рукопожатие неверно")
	}
}

func TestWGStrategies(t *testing.T) {
	a := &Account{Kind: "wg", EndpointV4: "162.159.192.1:2408"}
	ss := WGStrategies(a)
	if len(ss) < 30 || ss[0].Params["sig"] != "quic" || ss[0].Params["jc"] != "3" || ss[0].Transport != "wg" {
		t.Fatalf("стратегии: %d, первая %+v", len(ss), ss[0])
	}
	saw188, saw8 := false, false
	for _, s := range ss {
		h := hostOnly(s.Params["endpoint"])
		if strings.HasPrefix(h, "188.114.") {
			saw188 = true
		}
		if strings.HasPrefix(h, "8.34.") || strings.HasPrefix(h, "8.39.") {
			saw8 = true
		}
	}
	if !saw188 || !saw8 {
		t.Fatalf("не хватает подсетей: 188.114=%v 8.x=%v", saw188, saw8)
	}
	own := &Account{Kind: "wg", Custom: true, EndpointV4: "vpn.example.com:51820"}
	os := WGStrategies(own)
	if len(os) != 2 || os[0].Params["endpoint"] != "vpn.example.com:51820" {
		t.Fatalf("свой конфиг: %+v", os)
	}
}

func TestWGPrefixLooksLikeVarvara(t *testing.T) {
	q := BuildQUICLike()
	if len(q) != 108 || q[0] != 0xC0 || q[4] != 1 || q[5] != 8 || q[16] != 0x40 || q[17] != 90 {
		t.Fatalf("QUIC-подобный пакет: %x", q[:20])
	}
	pre := WGPrefix("quic", 3, 41, 78)
	if len(pre) != 1+4+3 || len(pre[0]) != 108 {
		t.Fatalf("пролог: %d пакетов, первый %d байт", len(pre), len(pre[0]))
	}
	if len(WGPrefix("", 0, 0, 0)) != 0 {
		t.Fatal("без сигнатуры и мусора пролога быть не должно")
	}
	st := BuildSTUNLike()
	if len(st) != 20 || st[4] != 0x21 || st[7] != 0x42 {
		t.Fatalf("STUN-подобный пакет: %x", st)
	}
}

func TestInterleave(t *testing.T) {
	a := []Strategy{{ID: "a1"}, {ID: "a2"}, {ID: "a3"}, {ID: "a4"}}
	b := []Strategy{{ID: "b1"}, {ID: "b2"}}
	var ids []string
	for _, s := range Interleave(a, b, 2) {
		ids = append(ids, s.ID)
	}
	if strings.Join(ids, ",") != "a1,a2,b1,b2,a3,a4" {
		t.Fatalf("порядок: %v", ids)
	}
}
HYDRA_EOF

echo "$NEW" > "$STAMP"
