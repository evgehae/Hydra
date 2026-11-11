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
NEW=16
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
rm -f app/src/main/java/app/hydra/SettingsScreen.kt

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
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/file_paths" />
        </provider>
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

    private var healTries = 0
    private var nextHealAt = 0L

    /**
     * Самовосстановление регистрации: вызывается раз в несколько секунд. Если аккаунта нет —
     * пробует снова с нарастающей паузой (15 с … 5 мин), чередуя обычную сеть и мобильную.
     */
    fun heal() {
        if (working) return
        if (id.isNotEmpty() && wgId.isNotEmpty()) { healTries = 0; return }
        val now = System.currentTimeMillis()
        if (now < nextHealAt) return
        healTries++
        nextHealAt = now + minOf(300_000L, 15_000L shl minOf(healTries - 1, 5))
        when {
            id.isNotEmpty() -> registerWg()
            healTries % 2 == 0 -> registerViaCellular()
            else -> register()
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

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp

/** «Дополнительно»: все настройки в одном меню, как в 1.1.1.1. */
@Composable
fun AdvancedScreen(
    prefs: Prefs,
    account: AccountController,
    vpn: VpnController,
    onBack: () -> Unit,
    onApps: () -> Unit,
    onRoutes: () -> Unit,
    onDns: () -> Unit,
    onResetAll: () -> Unit,
    onLanguageChanged: () -> Unit
) {
    val ctx = LocalContext.current
    var sni by remember { mutableStateOf(prefs.customSni) }
    var ep by remember { mutableStateOf(prefs.customEndpoint) }
    var proto by remember { mutableStateOf(prefs.protocol) }
    var channel by remember { mutableStateOf(prefs.channel) }
    var lang by remember { mutableStateOf(prefs.lang) }
    var block by remember { mutableStateOf(prefs.blockedColos) }
    var allow by remember { mutableStateOf(prefs.allowColos) }
    var fallback by remember { mutableStateOf(prefs.fallbackAny) }
    var auto by remember { mutableStateOf(prefs.autoStart) }
    var parallel by remember { mutableStateOf(prefs.parallel) }
    var dlg by remember { mutableStateOf("") }
    var showLicenses by remember { mutableStateOf(false) }

    val openVpnSettings: () -> Unit = {
        try { ctx.startActivity(Intent(Settings.ACTION_VPN_SETTINGS)) } catch (t: Throwable) { }
    }
    val openBattery: () -> Unit = {
        try {
            ctx.startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:" + ctx.packageName)))
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
                ctx.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + ctx.packageName)))
            } catch (t2: Throwable) { }
        }
    }

    val dflt = stringResource(R.string.value_default)
    val none = stringResource(R.string.value_none)
    val protoOpts = listOf(
        "auto" to stringResource(R.string.proto_auto),
        "masque" to stringResource(R.string.proto_masque_chip),
        "wg" to stringResource(R.string.proto_wg_chip)
    )
    val channelOpts = listOf(
        "auto" to stringResource(R.string.channel_auto),
        "cell" to stringResource(R.string.channel_cell)
    )
    val langOpts = listOf(
        "system" to stringResource(R.string.lang_system),
        "en" to stringResource(R.string.lang_en),
        "ru" to stringResource(R.string.lang_ru)
    )
    val engine = remember { try { mobile.Mobile.version() } catch (t: Throwable) { "n/a" } }

    SubPage(stringResource(R.string.menu_advanced), onBack) {
        SectionLabel(stringResource(R.string.adv_sec_apps))
        RowDivider()
        SettingRow(stringResource(R.string.conn_apps), onClick = onApps)
        SettingRow(stringResource(R.string.conn_routes), onClick = onRoutes)
        SettingRow(stringResource(R.string.conn_dns), onClick = onDns)

        SectionLabel(stringResource(R.string.adv_sec_conn))
        RowDivider()
        SettingSwitchRow(stringResource(R.string.adv_parallel), stringResource(R.string.adv_parallel_sub), parallel) {
            parallel = it
            prefs.parallel = it
            vpn.restartIfActive()
        }
        SettingRow(stringResource(R.string.conn_proto), subtitle = stringResource(R.string.proto_hint),
            value = protoOpts.firstOrNull { it.first == proto }?.second, onClick = { dlg = "proto" })
        SettingRow(stringResource(R.string.channel_title), subtitle = stringResource(R.string.channel_hint),
            value = channelOpts.firstOrNull { it.first == channel }?.second, onClick = { dlg = "channel" })
        SettingRow(
            stringResource(R.string.conn_sni), stringResource(R.string.conn_sni_sub),
            value = if (sni.isEmpty()) dflt else sni, onClick = { dlg = "sni" }
        )
        SettingRow(
            stringResource(R.string.conn_endpoint), stringResource(R.string.conn_endpoint_sub),
            value = if (ep.isEmpty()) dflt else ep, onClick = { dlg = "ep" }
        )

        SectionLabel(stringResource(R.string.colo_title))
        RowDivider()
        SettingRow(stringResource(R.string.colo_block), value = block.ifEmpty { none }, onClick = { dlg = "block" })
        SettingRow(stringResource(R.string.colo_allow), value = allow.ifEmpty { none }, onClick = { dlg = "allow" })
        SettingSwitchRow(stringResource(R.string.fallback_any), stringResource(R.string.fallback_hint), fallback) {
            fallback = it
            prefs.fallbackAny = it
            vpn.restartIfActive()
        }
        SettingRow(stringResource(R.string.colo_reset), onClick = {
            block = prefs.defaultBlockedColos()
            prefs.blockedColos = block
            allow = ""
            prefs.allowColos = ""
            vpn.restartIfActive()
        })
        NoteText(stringResource(R.string.colo_hint))

        SectionLabel(stringResource(R.string.persist_title))
        RowDivider()
        SettingSwitchRow(stringResource(R.string.settings_autostart), stringResource(R.string.persist_hint), auto) {
            auto = it
            prefs.autoStart = it
        }
        SettingRow(stringResource(R.string.btn_always_on), onClick = openVpnSettings)
        SettingRow(stringResource(R.string.btn_battery), onClick = openBattery)
        SettingRow(stringResource(R.string.btn_autostart_xiaomi), onClick = openAutostart)
        NoteText(stringResource(R.string.kill_info))

        SectionLabel(stringResource(R.string.adv_sec_other))
        RowDivider()
        SettingRow(stringResource(R.string.settings_language),
            value = langOpts.firstOrNull { it.first == lang }?.second, onClick = { dlg = "lang" })
        SettingRow(stringResource(R.string.conn_reset_keys), onClick = { dlg = "keys" })
        SettingRow(stringResource(R.string.conn_reset_all), onClick = { dlg = "all" })
        SettingRow(stringResource(R.string.about_title), stringResource(R.string.engine_label, engine),
            onClick = { showLicenses = !showLicenses })
        if (showLicenses) {
            NoteText(stringResource(R.string.about_text))
            NoteText(stringResource(R.string.licenses_text))
        }
        Spacer(Modifier.height(24.dp))
    }

    when (dlg) {
        "proto" -> ChoiceDialog(stringResource(R.string.conn_proto), protoOpts, proto,
            onPick = { proto = it; prefs.protocol = it; dlg = ""; vpn.restartIfActive() }, onDismiss = { dlg = "" })
        "channel" -> ChoiceDialog(stringResource(R.string.channel_title), channelOpts, channel,
            onPick = { channel = it; prefs.channel = it; dlg = ""; vpn.restartIfActive() }, onDismiss = { dlg = "" })
        "lang" -> ChoiceDialog(stringResource(R.string.settings_language), langOpts, lang,
            onPick = { lang = it; prefs.lang = it; dlg = ""; onLanguageChanged() }, onDismiss = { dlg = "" })
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
        "block" -> TextDialog(
            stringResource(R.string.colo_block), block, "DME",
            onDismiss = { dlg = "" },
            onApply = { block = it.uppercase(); prefs.blockedColos = block; dlg = ""; vpn.restartIfActive() },
            onReset = { block = ""; prefs.blockedColos = ""; dlg = ""; vpn.restartIfActive() }
        )
        "allow" -> TextDialog(
            stringResource(R.string.colo_allow), allow, "HEL, FRA, AMS",
            onDismiss = { dlg = "" },
            onApply = { allow = it.uppercase(); prefs.allowColos = allow; dlg = ""; vpn.restartIfActive() },
            onReset = { allow = ""; prefs.allowColos = ""; dlg = ""; vpn.restartIfActive() }
        )
        "keys" -> ConfirmDialog(
            stringResource(R.string.conn_reset_keys), stringResource(R.string.conn_reset_keys_q),
            onDismiss = { dlg = "" },
            onOk = { dlg = ""; vpn.stop(); account.resetKeys() }
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
    // результаты попадают и в журнал, чтобы они были в отчёте
    try {
        mobile.Mobile.logLine("🔎 полная диагностика (мимо VPN):")
        out.forEach { mobile.Mobile.logLine("   " + (if (it.ok) "✔ " else "✘ ") + it.name + ": " + it.detail) }
        if (base.ip.isNotEmpty()) mobile.Mobile.logLine("   публичный IP: " + base.ip)
    } catch (t: Throwable) { }
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

/** Полный отчёт: система, настройки, состояние движка и память, проверки, журнал. Ключи и токены не включаются. */
fun buildReport(ctx: android.content.Context, prefs: Prefs, vpn: VpnController, account: AccountController, checks: List<DiagCheck>): String {
    val sb = StringBuilder()
    sb.append("Hydra report ").append(java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US).format(java.util.Date())).append('\n')
    sb.append("core: ").append(try { mobile.Mobile.version() } catch (t: Throwable) { "n/a" }).append('\n')
    sb.append("\n--- состояние ---\n")
    sb.append("state: ").append(vpn.state).append(", strategy: ").append(vpn.strategy).append(", colo: ").append(vpn.colo)
        .append(", rtt: ").append(vpn.rttMs).append(" ms, rx/tx: ").append(fmtBytes(vpn.rxBytes)).append(" / ").append(fmtBytes(vpn.txBytes)).append('\n')
    if (vpn.message.isNotEmpty()) sb.append("message: ").append(vpn.message).append('\n')
    sb.append("account: masque=").append(account.id.take(8)).append(" wg=").append(account.wgId.take(8)).append('\n')
    sb.append("settings: protocol=").append(prefs.protocol).append(", channel=").append(prefs.channel)
        .append(", blockedColos=").append(prefs.blockedColos).append(", allowColos=").append(prefs.allowColos)
        .append(", fallbackAny=").append(prefs.fallbackAny).append(", parallel=").append(prefs.parallel)
        .append(", autostart=").append(prefs.autoStart)
        .append(", customSni=").append(prefs.customSni).append(", customEndpoint=").append(prefs.customEndpoint)
        .append(", customDns=").append(if (prefs.customDnsOn) prefs.customDns else "off")
        .append(", excludedRoutes=").append(prefs.excludedRoutes.split(',').size)
        .append(", splitOnlySelected=").append(prefs.splitOnlySelected).append(", splitApps=").append(prefs.splitApps.size).append('\n')
    sb.append("\n--- движок и память ---\n")
    sb.append(try { mobile.Mobile.diagnostics() } catch (t: Throwable) { "н/д\n" })
    sb.append("\n--- система ---\n")
    sb.append(try { systemReport(ctx) } catch (t: Throwable) { "н/д\n" })
    if (checks.isNotEmpty()) {
        sb.append("\n--- проверки (мимо VPN) ---\n")
        checks.forEach { sb.append(if (it.ok) "OK   " else "FAIL ").append(it.name).append(": ").append(it.detail).append('\n') }
    }
    sb.append("\n--- журнал ---\n")
    sb.append(try { mobile.Mobile.getJournal(1500) } catch (t: Throwable) { "" })
    return sb.toString()
}

/** Отправляет отчёт файлом .txt (так его принимают мессенджеры и почта); если не вышло — текстом. */
fun shareReport(ctx: android.content.Context, text: String) {
    try {
        val dir = java.io.File(ctx.cacheDir, "reports")
        dir.mkdirs()
        dir.listFiles()?.forEach { if (it.name.startsWith("hydra-report")) it.delete() }
        val name = "hydra-report-" + java.text.SimpleDateFormat("yyyyMMdd-HHmmss", java.util.Locale.US).format(java.util.Date()) + ".txt"
        val f = java.io.File(dir, name)
        f.writeText(text)
        val uri = androidx.core.content.FileProvider.getUriForFile(ctx, ctx.packageName + ".fileprovider", f)
        val i = android.content.Intent(android.content.Intent.ACTION_SEND)
            .setType("text/plain")
            .putExtra(android.content.Intent.EXTRA_STREAM, uri)
            .putExtra(android.content.Intent.EXTRA_SUBJECT, name)
            .addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
        i.clipData = android.content.ClipData.newRawUri(name, uri)
        ctx.startActivity(android.content.Intent.createChooser(i, null).addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION))
    } catch (t: Throwable) {
        try {
            val i = android.content.Intent(android.content.Intent.ACTION_SEND).setType("text/plain")
                .putExtra(android.content.Intent.EXTRA_TEXT, text.takeLast(200_000))
            ctx.startActivity(android.content.Intent.createChooser(i, null))
        } catch (t2: Throwable) { }
    }
}
HYDRA_EOF

putv app/src/main/java/app/hydra/DiagnosticsScreen.kt <<'HYDRA_EOF'
package app.hydra

import android.content.Intent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.verticalScroll
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
    var showResult by remember { mutableStateOf(false) }
    var showQuick by remember { mutableStateOf(false) }
    var showSys by remember { mutableStateOf(false) }

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
                    scope.launch {
                        val r = runDiagnostics()
                        base = r
                        quick = false
                        try {
                            mobile.Mobile.logLine("🔎 быстрая проверка (мимо VPN): DNS " + (if (r.dnsOk) "ок ${r.dnsMs} мс" else "сбой") +
                                ", HTTPS " + (if (r.httpsOk) "ок ${r.httpsMs} мс" else "сбой") + ", дата-центр " + r.colo + ", IP " + r.ip)
                        } catch (t: Throwable) { }
                        showQuick = true
                    }
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
                        showResult = true
                    }
                }
            }
        )
        SettingRow(stringResource(R.string.diag_errors), stringResource(R.string.diag_errors_sub), onClick = onErrors)
        SettingRow(stringResource(R.string.journal_title), onClick = onJournal)
        SettingRow(
            stringResource(R.string.diag_sys),
            stringResource(R.string.diag_sys_sub),
            onClick = { showSys = true }
        )
        SettingRow(
            stringResource(R.string.diag_share),
            stringResource(R.string.diag_share_sub),
            onClick = {
                shareReport(ctx, buildReport(ctx, prefs, vpn, account, checks))
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

        if (running) NoteText(stringResource(R.string.diag_full_running))
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
    if (showResult) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { showResult = false },
            title = { Text(stringResource(R.string.diag_full)) },
            text = {
                Column {
                    checks.forEach { c ->
                        Text((if (c.ok) "✔ " else "✘ ") + c.name + ": " + c.detail, modifier = Modifier.padding(vertical = 3.dp))
                    }
                }
            },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = {
                    showResult = false
                    shareReport(ctx, buildReport(ctx, prefs, vpn, account, checks))
                }) { Text(stringResource(R.string.diag_share)) }
            },
            dismissButton = {
                androidx.compose.material3.TextButton(onClick = { showResult = false }) { Text(stringResource(R.string.btn_ok)) }
            }
        )
    }
    if (showQuick) {
        val r = base
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { showQuick = false },
            title = { Text(stringResource(R.string.diag_quick)) },
            text = {
                Column {
                    if (r != null) {
                        Text((if (r.dnsOk) "✔ " else "✘ ") + stringResource(R.string.chk_dns) + ": " + (if (r.dnsOk) "${r.dnsMs} ms" else stringResource(R.string.diag_fail)), modifier = Modifier.padding(vertical = 3.dp))
                        Text((if (r.httpsOk) "✔ " else "✘ ") + stringResource(R.string.chk_https) + ": " + (if (r.httpsOk) "${r.httpsMs} ms" else stringResource(R.string.diag_fail)), modifier = Modifier.padding(vertical = 3.dp))
                        Text(stringResource(R.string.diag_dc) + ": " + (if (r.colo.isEmpty()) "—" else coloLabel(r.colo)), modifier = Modifier.padding(vertical = 3.dp))
                        Text(stringResource(R.string.diag_ip) + ": " + (if (r.ip.isEmpty()) "—" else r.ip), modifier = Modifier.padding(vertical = 3.dp))
                    }
                }
            },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = { showQuick = false }) { Text(stringResource(R.string.btn_ok)) }
            }
        )
    }
    if (showSys) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { showSys = false },
            title = { Text(stringResource(R.string.diag_sys)) },
            text = {
                SelectionContainer {
                    Text(
                        (try { mobile.Mobile.diagnostics() } catch (t: Throwable) { "" }) + "\n" + systemReport(ctx),
                        fontFamily = FontFamily.Monospace,
                        fontSize = 10.sp,
                        lineHeight = 13.sp,
                        modifier = Modifier.verticalScroll(androidx.compose.foundation.rememberScrollState())
                    )
                }
            },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = { showSys = false }) { Text(stringResource(R.string.btn_ok)) }
            }
        )
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

        Spacer(Modifier.weight(0.45f))
        // «WARP» крупными огненно-красными буквами, под ним синим «CLAUDE» поменьше
        Text(
            "WARP",
            style = TextStyle(
                brush = Brush.linearGradient(
                    listOf(Color(0xFFFF3B2F), Color(0xFFFF7A33), Color(0xFFE5301F), Color(0xFFFF5A3C))
                ),
                fontSize = 62.sp,
                fontWeight = FontWeight.Black,
                letterSpacing = (-2).sp,
                textAlign = TextAlign.Center
            )
        )
        Text(
            "CLAUDE",
            color = TitleBlue,
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = 8.sp,
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.weight(0.40f))

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
        Spacer(Modifier.weight(3.2f))
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

    private fun jlog(s: String) { try { mobile.Mobile.logLine(s) } catch (t: Throwable) { } }

    private fun describeNet(n: Network): String = try {
        val c = cm().getNetworkCapabilities(n)
        val t = when {
            c == null -> "?"
            c.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi"
            c.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "сотовая"
            c.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "Ethernet"
            else -> "другая"
        }
        t + (if (c?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true) ", проверена" else ", не проверена")
    } catch (t: Throwable) { "?" }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        jlog("служба: команда " + (intent?.action ?: "перезапуск системой / запуск"))
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
            mobile.Mobile.setParallel(if (prefs.parallel) 3L else 1L)
            jlog("настройки: протокол=${prefs.protocol}, канал=${prefs.channel}, параллельно=${prefs.parallel}, свой DNS=${if (prefs.customDnsOn) prefs.customDns else "нет"}")
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
            for (raw in prefs.customDns.split(',', ';', ' ', '\n').map { it.trim() }.filter { it.isNotEmpty() }) {
                // принимаем IP, имя хоста, tls://host и https://host/path: имя превращаем в IP-адреса
                val host = raw.substringAfter("://").substringBefore("/").substringBefore(":")
                val ips = if (host.matches(Regex("[0-9a-fA-F:.]+"))) listOf(raw.substringAfter("://").substringBefore("/"))
                          else resolveHost(host)
                for (d in ips.take(2)) {
                    try { b.addDnsServer(d); dnsAdded++ } catch (e: Exception) { }
                }
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

    /** Имя хоста в IP-адреса (в отдельном потоке с таймаутом: на главном потоке сеть запрещена). */
    private fun resolveHost(host: String): List<String> {
        var res: List<String> = emptyList()
        val t = Thread {
            res = try {
                java.net.InetAddress.getAllByName(host).mapNotNull { it.hostAddress }.filter { !it.contains("%") }
            } catch (e: Exception) { emptyList() }
        }
        t.start()
        t.join(4000)
        return res
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
            override fun onAvailable(network: Network) { jlog("📶 сеть появилась: " + describeNet(network)); push() }
            override fun onLost(network: Network) { jlog("📶 сеть пропала"); push() }
        }
        netCallback = cb
        try {
            cm().registerNetworkCallback(req, cb)
        } catch (t: Throwable) {
            Log.e(TAG, "слежение за сетью: " + t.message)
        }
    }

    private fun stopVpn() {
        jlog("служба: остановка")
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
        jlog("система отозвала VPN (включён другой VPN или VPN выключен в настройках)")
        stopVpn()
        super.onRevoke()
    }

    override fun onDestroy() {
        jlog("служба: уничтожена")
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
        window.navigationBarColor = android.graphics.Color.BLACK
        window.statusBarColor = android.graphics.Color.BLACK
        if (android.os.Build.VERSION.SDK_INT >= 29) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }
        androidx.core.view.WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightNavigationBars = false
            isAppearanceLightStatusBars = false
        }
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

    /** Параллельная гонка стратегий и горячий резерв. */
    var parallel: Boolean
        get() = sp.getBoolean("parallel", true)
        set(v) { sp.edit().putBoolean("parallel", v).apply() }

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

putv app/src/main/java/app/hydra/SystemInfo.kt <<'HYDRA_EOF'
package app.hydra

import android.app.ActivityManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import android.telephony.TelephonyManager
import androidx.core.app.NotificationManagerCompat
import java.util.Locale
import java.util.TimeZone

private fun safe(f: () -> String): String = try { f() } catch (t: Throwable) { "н/д" }

/** Всё, что в системе влияет на работу VPN: сети, батарея, режимы Android, DNS, оператор. */
fun systemReport(ctx: Context): String {
    val sb = StringBuilder()
    fun line(k: String, v: String) { sb.append(k).append(": ").append(v).append('\n') }

    line("приложение", safe { ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName ?: "?" })
    line("устройство", "${Build.MANUFACTURER} ${Build.MODEL} (${Build.DEVICE}), ${Build.HARDWARE}")
    line("система", "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT}), патч ${Build.VERSION.SECURITY_PATCH}, сборка ${Build.DISPLAY}")
    line("язык / часовой пояс", Locale.getDefault().toString() + " / " + TimeZone.getDefault().id)
    line("время на телефоне", java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss Z", Locale.US).format(java.util.Date()))
    line("телефон включён", (SystemClock.elapsedRealtime() / 60000).toString() + " мин")

    // питание и фон: частая причина того, что систему «убивает» VPN
    line("экономия батареи Android", safe { (ctx.getSystemService(Context.POWER_SERVICE) as PowerManager).isPowerSaveMode.toString() })
    line("режим Doze", safe { (ctx.getSystemService(Context.POWER_SERVICE) as PowerManager).isDeviceIdleMode.toString() })
    line("вне оптимизации батареи", safe { (ctx.getSystemService(Context.POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(ctx.packageName).toString() })
    line("фон ограничен системой", safe { (ctx.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).isBackgroundRestricted.toString() })
    line("группа ожидания (10 активно … 45 ограничено)", safe { (ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager).appStandbyBucket.toString() })
    line("уведомления разрешены", safe { NotificationManagerCompat.from(ctx).areNotificationsEnabled().toString() })
    val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    line("экономия трафика (1 выкл, 2 исключение, 3 вкл)", safe { cm.restrictBackgroundStatus.toString() })
    line("постоянный VPN (приложение)", safe { Settings.Secure.getString(ctx.contentResolver, "always_on_vpn_app") ?: "нет" })
    line("блокировка без VPN", safe { Settings.Secure.getInt(ctx.contentResolver, "always_on_vpn_lockdown", 0).toString() })
    line("частный DNS Android", safe {
        (Settings.Global.getString(ctx.contentResolver, "private_dns_mode") ?: "н/д") + " " +
            (Settings.Global.getString(ctx.contentResolver, "private_dns_specifier") ?: "")
    })
    line("режим «в самолёте»", safe { Settings.Global.getInt(ctx.contentResolver, Settings.Global.AIRPLANE_MODE_ON, 0).toString() })

    // оператор
    safe {
        val tm = ctx.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        line("оператор сети", "${tm.networkOperatorName} (${tm.networkOperator}), SIM ${tm.simOperator}, роуминг ${tm.isNetworkRoaming}")
        ""
    }

    // сети
    val active = safe { cm.activeNetwork.toString() }
    sb.append("\nсети (активная: ").append(active).append("):\n")
    try {
        for (n in cm.allNetworks) {
            val c = cm.getNetworkCapabilities(n)
            val lp = cm.getLinkProperties(n)
            val tr = listOf(
                NetworkCapabilities.TRANSPORT_WIFI to "Wi-Fi",
                NetworkCapabilities.TRANSPORT_CELLULAR to "сотовая",
                NetworkCapabilities.TRANSPORT_VPN to "VPN",
                NetworkCapabilities.TRANSPORT_ETHERNET to "Ethernet"
            ).filter { c?.hasTransport(it.first) == true }.joinToString("+") { it.second }
            val caps = listOf(
                NetworkCapabilities.NET_CAPABILITY_INTERNET to "интернет",
                NetworkCapabilities.NET_CAPABILITY_VALIDATED to "проверена",
                NetworkCapabilities.NET_CAPABILITY_NOT_METERED to "безлимит",
                NetworkCapabilities.NET_CAPABILITY_NOT_VPN to "не VPN"
            ).filter { c?.hasCapability(it.first) == true }.joinToString(",") { it.second }
            sb.append(" - ").append(n.toString()).append(' ').append(tr.ifEmpty { "?" }).append(" [").append(caps).append("]")
            sb.append(" вниз ").append(c?.linkDownstreamBandwidthKbps ?: 0).append(" кбит/с")
            sb.append(" if=").append(lp?.interfaceName ?: "?")
            sb.append(" адреса=").append(lp?.linkAddresses?.joinToString(",") { it.address.hostAddress ?: "" } ?: "")
            sb.append(" шлюз=").append(lp?.routes?.firstOrNull { it.isDefaultRoute }?.gateway?.hostAddress ?: "")
            sb.append(" DNS=").append(lp?.dnsServers?.joinToString(",") { it.hostAddress ?: "" } ?: "")
            if (Build.VERSION.SDK_INT >= 29) sb.append(" MTU=").append(lp?.mtu ?: 0)
            if (lp?.isPrivateDnsActive == true) sb.append(" частный DNS=").append(lp?.privateDnsServerName ?: "авто")
            sb.append('\n')
        }
    } catch (t: Throwable) {
        sb.append("  не удалось прочитать: ").append(t.message).append('\n')
    }
    return sb.toString()
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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
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

/** Диалог выбора одного из вариантов (код, подпись). */
@Composable
fun ChoiceDialog(
    title: String,
    options: List<Pair<String, String>>,
    selected: String,
    onPick: (String) -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column {
                options.forEach { (code, label) ->
                    Row(
                        Modifier.fillMaxWidth().clickable { onPick(code) },
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        RadioButton(selected = selected == code, onClick = null)
                        Spacer(Modifier.width(12.dp))
                        Text(label, modifier = Modifier.padding(vertical = 12.dp))
                    }
                }
            }
        },
        confirmButton = {},
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
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
EYZIVzAlcTFkCjcw4kjtDUgSR0a+AAAA
HYDRA_EOF

putb app/src/main/res/drawable-nodpi/ic_launcher_art.webp <<'HYDRA_EOF'
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
czxcnCCtVOxRBWOvabGZrBVMcAY1Ytdf8zmAAAA=
HYDRA_EOF

putb app/src/main/res/drawable-nodpi/ic_launcher_bg.webp <<'HYDRA_EOF'
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
HYDRA_EOF

putb app/src/main/res/drawable-nodpi/ic_launcher_fg.webp <<'HYDRA_EOF'
UklGRvQbAABXRUJQVlA4TOgbAAAvh8KhELVgoG3btO1a/RqxnTzbtm3bNoNn27Zt27YV49mInV7K
2nuv0dec6/yy9tdacfLzb79I3jzxjaAAAADiJFon3R3SzegGGd3NdtsY3WDS9RMbabBbwla6G1vq
pVulG8mNMWjRth23bfZz1jyQKmKK4ANIvP4N/2kYvf96//X+6/3X+6/3X++/3n+9/3r/9f7r/df7
r/df77/ef73/ev/1/uv91/uv91/vv95/vf96//X+6/3X+6/3X++/3n+9/3r/9f7r/df7r/df77//
NoTzPImDEjJieSRsIt117Iu3kMfkbIDVRQsyKZIE+0ujWM59bnGJI/zMKt5mPL2pQEga7C8Ngywe
cHOWQ2xhKTNJpAZh3RRfCQjIiC8C5sjIsTzGgUFHgVPV9sa4RFIFd9nJdBoSkkK6vWAjk6nYQTFa
wDsyZij4XUa7EmNxAzxXVBxMJGVwjjcp11zSGM4ge9d0TMKGxyYFj4hV8YqAhBzNjtr5Ce9J+HJ1
U4mDW7xGzm6JkFNiR7DWDwUArIRQ7hQlrn3FENewU7BltA0i4Bqq80T30noQgW6bUkhnJhHNJA8u
M6BbfrC2xHHTWwAgJaFOkTz5raElIZIHsb1WAdhwGDTMbuCv/xZQoNQ+pbCbAo1kCL4nV5fEJMHz
qgxdCc9qPv/LsJXQpMTe0V2BroZQLpYGcfNsOLZR4SSFWqVwmrId0qzg2xOGo4TvNPsdzqeACJiC
iYL7P6pAUkOH0sQHvxs8bVT4i2ytUlZTtTs6mYexQ5hL/AEAoeBS0eIyqQAgpGCN4MLxFWDE7qpG
Dj5aPxTarVTe8KhdCucp2h0/2FXiuEamISqgXBE94rmhppxycTP29505JBuug4Scp5VG8eAn8ASk
lco1bdul/LCXqM6IVwVPfAMAOAED9WM2LJN0QX2sxzaMNAwtzXx30hBrp++MAdUu5dnZnRHtBZ/7
37AR8LHqT1uGD8ApuuS3L6tAVsNPpWFc4CJM26lc6cLZ7XIo8+ImXdEKHsf2PZhHBgHQGMeLGuc9
b/CkeK95pf8q4JRQtjT17AoQgGin17ZAv13KR78D0xU/2C+d9UAwvvrME9m97hmKCVI2DmQs9LPh
pe0xLzX22/W5JMgnd9ixJ2IxdaPwc5+70c0dyr80dDhL9IdNr069E/Y88oZhZ908+wU1O84XNS4e
CWhHxELprAeqIXrq3tRumIZ4qsS+OmIb5hKCOVMax3WuwjaDILaMfnuXevBYlkwUc0g3yfrZH9Er
GqHZEdEnyVkPc3W7LBoeIVIFz/xYgbKEFjxp7hiDIzP7nvc0dyg0+PKwl/i/sV3zl+35ZHB3QxQW
/HlbOOvhz6LHJhEGe4QPBTe8UQGfhI8T2J++ZiA0s/PzqiSPf23o5WKLn9ivQoNZR/yKUyWO818w
eBrl3u69X+/WeYZMhGOxw1nrBNvwBURBDP/FPt5b4rjHXbjNpgfi5FYdByTYIAJl4NcNOkbxulYA
cE+/E8MweyzYIQYcnBZRfzknecxLd8Sv+FRw7/vhWQ+tSq0d5z/8o96L6wyDxmdSP/ltG1aDgmSe
xK6Q/r2p2JeHDaEcggDmTdWKd3+2wZ5uJ8KA6O2uST7WY+h0QwwSvKXTMA2QVu/1rY8qqfeDacO5
8ZnUKxor0EiTSLnnih/5Qkh+2yYWRtkNDNDaqyGZzTAX/ttlxU4LPgHgTojygt2Xw7MettS7253L
pgaNZM1AA1WPedLZiA0RBUV5LHRTeosooYPnCa/hA1h21FV86IcNlXwGPlMcxJhDMvi74VdcLnFs
HhWcIBPG3XrnOjufsu9B0KcT5eDyp5p7myYb6OKJAPzVEaUfAKeyo6zWyWXoZcQQ6bsbhhnK3RDf
CW5fYMjUol7U++zP/6r31HeGVi2ykakc5W3YDwoOx341B8B+4GPlGhDw2VFI8aJaG8YZ0VmyTaxh
3g3xrODlDYZBLZ6v994v9pPe1vvioGFXizZS36MNnUqCw/ST3lY2pPAo9ppmA5sbFRTbl9krMqKh
5EJxhlM3RG3p3Boutfi+3kOf2de83CQHl5npcm9ZJDjfhQo0WR/7594iKlRzW6EN5zFMM6KR5IJx
BqEbIpQ7Ul8j0PL71ksmV5czDmHUb8jl0gyhOmxXPkeJubdEcC32wxlXwE1/YbtvVwDn3BguOIK1
dpB9UkZ0Eb9jILvhBxuF/6I3umlIqkfUvffnke3T+KXeo0oM9bpmzf1kubd0L7FtSytwGsjJw9gn
eg2+zFgmdqRCKyOGib/EwHZDTBM8q8LQUfs1PzNgGya8GfW+1J3CnJAu95YfhU+OW8VUoCpt0KHM
TSKglxcFuC945IsKlDNiieJAxhySDc5uiBaCr48a9up1nie8rkCezkF6Qe1VcMYny70lHxnKjnrs
6goJwpY/qgRegGTF28p4m+MrEMqHUC4odpy3DY5uiGgyhC7hRdS6vkZO1rt6pm1wk5us6Co4eCex
SnDFDDH3ljHKIBh77ISfGO4qh29IJBbvoHLmXwE8H5Kk73/kpzvjd4aTShxXpdVce6FQOIjQ8AZ4
4P/qVXCCuZEs95Y/hba2cXhlbMA+y5V+dVjkQym+kbLD1g8d60jNhmiOSnYorwDZEfGm4HGvDI0J
9I4GVds4PQwsVq+CUy1Z7i2VpbE4k6fzdFW6u0EEKgMiyUcZOjKJHWTxRHGnIldW5jH5r1MbbwHf
oSOis+BT/Yb1BOZHk0zYUA3fPe62ZHhOYKTgGR/EcxHekMY1eGJHieCmMAhsPmVlm8bFnOEKCEDm
QjSf8kTy5+15ZBtOXRF5yIr9a28uCQRAxrGn3s1uVSAwDBQNtnGzSIND/yx1gxu20t9DCOeFc5Z1
g21PDILhE2Hjb5wF+xZ5bYsrVfptHgSfyF880by8wTbMhq4YHCxxXCLJEFCuVB/B2iDUHhtEyOl6
t803ZMbxr9APv3aQlntL2xL7aA8AG0Sg9K1631eDuy0OZW5f5pETgEiPUPJSji7MmvgztLwQQ7kz
4h3BQ58ZKsqV6l/O2YaNkHX10vqJyyKUSpZ7y1IxJw2Wk1lFXBE6DdYNhlZL7LV6VRqAMZDKO15V
/Ldr8HVGBATv/eLx02Neig+nwI0wOLoUCJcxpCiHSi33lhzcF8a/rBFQOb1JV+P9H8ED4Db4+862
pYuotseSgVs2fn/09crZzojigj9sGt6zI2ytd9fbFYgJ1xgPO14r0ECP8L6Ut2ZDWMg71wYIuG6s
Ps0E3xoHAJH8fv730SXrBtsTv6hlnlNpuxqP0B2Dv0sc5z5ncFcI5169c56xDaSSc3G9a+Nd3BwR
bBGl5d6yU5liMTjDIJh/lZHOMMntIMa2pfPI9hgQoQxQy/xoZjF1BNwdEkuUMXqGfIX6pdbvNmzD
UcrZfdp7Q3t0kZAniXJvKU2WklMW5aQxR/D0DyAsy95k/7S1Q/lRI3CFAEAt88fNLaM99rs7JIYJ
3thumFR4od57vtiGnpSz+6Uhw07M3Xlbl3aoZIY2PsD141+oq5zZzCFBtgVN9rfr170GAF5QAgSg
lvnz9ugXGURwd0lUFuy8MDa6mB/rPeRpBdJSzu7+9AWU0VGf2YL7PdRybzkpOKYC46abds3LsGlF
k31C/rLWTRa11+ooZ9iGJkBdEsFck6aIANswcDXuoTtjoicvGH1/+fTRWRC/J8q9pYl4HcQQa3rD
jTd3GOytaLLMbZuP9awf6hHYAwpQpwxWCG6dZ5waqBhd27HhNkwEG+o9usRQl2649rcdLfeWD8SB
1VFOGdUE+x6sEXB2O5os41vlr//u+8AegQcwAHVLvCh4SZ2hH43O/HR//XGbqVHGFfADrcSeZRiG
iOKWMi1NBQbNLyvd9TZc2+EIFp3aY5+D51evGzzxBdwAdUzUHxNPEcFnUe6PDflJNA8+Jxk+gJAm
2K5MyL3V8mt/szaHpOTDrpZuzQHBhFMyzSOvH3q+C7fJe2HN7zfEZvuXDQq1xC/+blu6TrA9Bq5g
B6hTqumgDLvFgeJUvatdqu+hI4r0YOpig5etiXJvWceTXHE4a8toGKSeGmwu6c7F4jc+2d0C+9O/
MPj416P32+NgDgRA3TOU9nu9a95MO0jGWUy14Q2wOqn2fR94gRr3YgfQF/rZ8Iwn1yOzZIvHvoQP
YMmnqFs/9Jtj2vbfKjaXI1gHMfbe//P2jvNfHn7352dV3OX2JZMXUFwTJ1SzjXdQ/1Z6rX27xHrL
x3Jva/B6vbd2+vLhJfaVYalnmRdLPscY0umnSlziv1zym7WlsimTeZsGvIFbBlAnRSupAb+sot5z
qypQqUPHaEaobZ+Jqa5QCvFXRuVyabBMmiIG8DKwQwJap20S8Zs1afufWA5US8DxhOqGmd0UsTxS
Dug/no1uPGlDoA65eBzMCPXRnjS5t9QqOb2yEURg0k/ZCalrpUv23l/fuQXgA0uogBOgDhv8UeK4
/vWToxvxGoTj9BZz+4K/7aTJvWVeVn/fWeg3myF1e9mbGqQdeF4VxLNZDW94wAl4GEMDUuBeDlC3
DeYIvjQU9JEAsGHT4AYHR5XYj2eV3FvCuJJVuVXu0TmGsmwouM++dKK9kd/ZKQe/du+I8yPU8cbQ
bHKDAzX3VpuTJmfCNXhzNNknZ2qpilCdcpC/qTsX29GNJ89s6nYFSu4t32Z2CHOjcOjmQLa/rkvX
YNbzB2K6MXC0oW1iK1G74WRDm0cJubfkIT2z8rBn8AIkR5NlsrQDT3kH3JSDDxqmDdrxjcn5pJk9
VpTcW0byJLcfzhjiOZDjn5uKf+yuTQVyukG/Zt71SRlSwsBaaXJv+S27cuF4mGVpsszULgpBc7pB
6WYe9EQZ6Em5ZkbZWJAIZybO73lVIACZA3n33ZEm11lKBmKqMXCukYslSpNpcbGRC8ZVgG58p/Pd
l90sHvxEGbs4jwyFLE2WWdKr8sgXUJtu8GUT/9wby70N8U0dLfcWLtEsJvyjjPVsaNPIw1nKpSHY
ZUHBAw8UpywiAj7VYFQTn+wbjV2JMbZZJ6MNw+YPJnbpFDeMr49Kb47BmaXJskh7ewOVqQbVG6V7
VSAXI66JbUuF3Fs+l07lm3r4c8EB9LWDgMuC4ocwFL9eW+AD2DSDEG42cBVaBVzCdnK7gSukx3ME
k427Y+LEIbgMTYJiyryJ93kAd4CzNFk+lF6Ye9+H4jRjYM0kZX5kG16zwnayTncAfQHFhmd4X3Lp
uQ9saKaeHvdrowAgnAVlDmMqdl2a5wnINIOJum+M2YbFIFih+/KwkHvLVnGWCYOnGV4QHME611kY
52myLNWuj0JumkFj3bMrbENFQVPd0z/EubeUIEvw/Oqx7zdDSelSIHwBz4LKpyp+OTfHDZApBhE8
kN04qwL+Jk+DpWRMxrm3TCmCy6WlmIKBP5SuzjkkyCRosskei+w2eadPMQZ2qo5grRdig7C8ydNg
pci95Zhgr9Wx7zfFhKLcQAFWeRAn+fEsnAGeYvCK6md/bMN6kPCqPAucbeAb3+XxBTUVuA5N8ZTi
DW0GW54my1rp1blJFqSmGLRTvapJP3TTXvWy+grUpfmWo7l4bOCGxsE+ZVjLEn+o5bFC8p0JOE4x
yEGm6E5FFYiI28njRLm3RHJD6cCeQ6qAV9P47ewdi1ala7JxP4EywRkkphcDe0Vbx1SAUD9RJsq9
pbd4M3rDNd0zS0R3uIRAHrSUfHUE9lOMYYCGxYBD2u3U5p8Fn4UAbkgRYLMQtc+ndqajaNZkYWEl
IDoMTXai64OwCro6iKigEzsm1Oz7TVslvAHNBHwS2E4zAAdRBKnk2wmJECDwiox9Pw2oWAhI5mqy
wEsvD4SmGMOZImCTbyfQoWMsgFYiYFfgdC4QlMCqsf80jN5/vf96//X+6/33vx8iP22ZzMds4ggX
uU0GmdxdzQHWMY9hxBH2n3EIphmzhHWPFv7jKxJOCzE42DDKpnVCXGggSqXZPspWGj2rGCeb7dpq
HpHOHa7yL0f4jfUsYQ7P0ZPqRDd/WZIEZbsu8jCOE3rFYljJ0+3B7hIGM9qoYb2OOMiHBE6bbhDL
lJNKo2APif/fDpQtMU4R3EaNgwfL6HLs9IJ2nCuNgyZ5JHnar+NbKE3dW+hLyHSCSN4tJaPznANg
sKd748tZxZvaDWyNZrvWyG5LNlySt+HCz1RMS3ihOyrysbukcBWXViC+FGntAlCbmQoPeX76QBFO
lCSuQoMdJAHOj8+LFHe9vap9kgUfEz5lOI7DJREABn92ZOOu5ouDhsBMVdh81FSBcH4uMwcD1acx
2ToGBjNWYS0R0wTmFGUtQC+qvW3+xRM3CF1EnU9ZO2ib2KvS7n3/VU2/nGsVdpSxkKqjMGOVI6cI
xJfYB75dLg1AfZy6Q/mO863BU2Spdl0ypNtstW3Pp6wVuFXM5dPvevv51d+fkgoxc7+wprurRidF
GIfjJ1aqlhcSVxzmxlnfGGsJ0hq81QC+3epis8jty367HjuQfh6FaQFj4pOV9UKsxS1zjm0Dgjld
v7DCgxj1tfowsDOEvYi6XdkB9BLFJ78CMh0glLPhl8VUj4MztCABbiCXzwJ+NAQgA1042l5MfXbF
5dObybD89oc//8jP4OGEoDpj2BeM23Up/LjumekAfcOfnfg2TKNHGTkaynCynR+f1j+B2GaRdygM
HsIPzi3QfJNnAQcGvJAGDnYgesOwX86FS16CbNPd7cjB2qjnZvx3wEXqR4QIrPMjljtBX+VS//0O
g+VPrWi5ugAaynDbKubvO9HHReNOngKQi4wSLxjSBl59dCaIwzk3UoMHPLXf/TlY/hT02y16ghgo
3SYnLBwSLKYAJJbAReLHvujrEjwOmuDNi231a2ao3nfcPDtYixq8j2u3KMDx1cGwqC4Q6v5YFK4v
2PaqZqt+yopSZNWX4Mj2Qso/t4JVdEJqJhlu4h4+Phksuz/+DDy6ZAQCQ1sxPX6AO+D5OFjk3OyM
QsiflsNlQoOr6yOYh4GLJlRgPLQWJ4NCWNmGDK2DpY6DCMxMMvBR+EiW0Eh6PZHdXRRFo4d9nke2
Da7Woll8HgYCEIRyuX7xpoupUJkB9E378A/DueujkbCiKdgMrXVSvVvk2IZ5WI6KOxSeMaNQN37B
ge346FZKeNICpZZoXC2wYxdRK5AK10D8mQGDbyahYAlrjQTJjo/EwFs6R99vLVK0BYgTzD/1XZdb
REFvJjkrsPe+DVxK3xizYd05MSheERp8AW4ttogLEGdWUK4TeB83gww8DGqfYMNsqvDq5lFlq9qK
4jwWFyBO7ahgVpCcSUivdwizesE7PgLxd2DeWkyNFyAOb0CU+jpePh2nZxBCS71/7dlw7/joFtfQ
CAatxfF6V/7PNTvIS8FxAERgZg4KB36/YZ/a8dE4fgp36LUVjYUn14bQOCoFy4lbRIXyzEH9uFZX
IHZ8FIv7z6HbVnwQLL+mviAiHAgevxxOMwfDw8I/GgR5m7Xoos4iPUzzOamliOZ2VNEZGzpiXYM/
1W/w1qB/4AIXBawIKgWVHp8HnldVfafjG9gTeFRJa38JgahKghXwi2v2O+x4s0joyl2ql0kVsCW4
EJPcv7kWuG2+Dfeuj8WBb4619g9iY0kW25XVraCUroGrZwr4NUiUS45eQkkAYdf1EQgXjtnS/nOK
8TidX/w1JNRL7ncoFHA2qJxWagTzW4mPDDDt+nmP5CYjLMQNuFqJSSVhXCYVFuqalJ7yLq4UGTFk
BWtmt+GUFP2UheQD1/nHZ7EuGp91VRoUW4mjKb2isaYK5ISTHkxtES8diLpxxSpgnxJlTlLKEQ2J
9LrueNXdltbzaCMaJl6EPZTEhYDsvX9KmJ9OWlhpCMMmIQpzUqtdWOdHGH+H4/cXC8qI4lXqZ8N7
JWncOg+Oaqr2zW5FBZwhmEPB4WOjcBtm6VB9NBVunO0Bp6F7a75G0i/8JJeIrhwvNMmFKG6m9fFe
g0esBMlPf88jQy14ZykkDkM3FaKZwkNp5aiGxhSA8LiqS7vN0FRaBhW7SsmHhNKMUubBya518pAZ
rU0XpvVLeeZyWKVCG0ppUJRJXBAqYLd6BJxTgIFWwnScfL0qQAnGc7iUnFhfEsejS+AFiFqRnNc0
rstTV1Z3LpX4Ko8h3BChxFKMeiTzFnvIKmLNhgzLYRowvDi3CMFRZtOLauQmglCyUYImDGRxTSk8
Zo+DRt34/STBpfE5v8nU6Uukg7i8FrW/bzKfTpQm+5kUojbPs1sqJImBrJcy3tY1uRqbxK9oV/2h
b/eXRHEV92o+kxyYEM18bCnuVBRs7qWSYZ5+PffXyKzAfsjk0/0L/UZgMUwHho0Ef/UnkavQnAeH
631hEIBmif8+B8Ha+2rKPEjTI1gasfSYhkYmXxhc4u8KfME+LRi20NxtqcWoV6J6rInxpnb5fyQD
c9P4285mkSPgyOMNbQsoHoHsMDUYNsJ/c6yV/rRlw2Pg7ehOQapjgu29ZU7NEumI/PLnFA4+us7V
8WVO5XAA/eHPbdcs3z39K9pRAbLI8XWtbXUyN6Lqa1WAbX6XtY/21F06JMd3R5s7hFnlitmGYA5f
HTnv+YlFfy2fJgxAwulGN3+/0U70Fk5kYCkuLzaq40jd2vuWSn7we+Prj9e8DGAE5kN6P5y5Zc4c
ksfMAjpMFQZg4LJGwBPf7L3fsMHcqWg+JQvWRNV5q0BaQ4WoTvS1/yMZoHXv+//aa+QjP8d+h08A
OrX9Dt/9+QY3atYmCcgwZRiAhI03CN2hXP87D2F+oreqCbFz2DSQzKgcerZcz2x+i6rnuKzunQrw
Jz6rQv93+ZXha10B4BEQIJS0DR/C/OnvVzffJm+p/+S34AuFYZg6DMuhZ88hXe2S9H8JYL/DD36/
y+11g+1Mtn0mZFXDIE3lIC6RVJssAThsASz1v+vtT/btdyj41dxzKi8Y54kvkBiaOpx1CHN/+t93
fru+4/x3Jz8z8PauF9Q84vktcy4cv9CvfhGHYB+mEcMAEbjb9sbhN7zx+Ndv6fzi4M4Lf97e5+BQ
5sFHf9nedekH05/qf17VXW5fNGFUqKwaNQEZJ4mVwkIiIZhgubBxQU3PhqnthX5XoT3k6WtbPvf/
z//+eXvfg0OZh7MOZPxjd4+Vb4697+tT3t06b/Oomm2EV92upH5VYDeqz1Gube66hrOhCu+GDQZS
AGcBi1RLKgWH6wOKQYNs9mrADOghD/jAGMLDML0YBiChvEoGwgkQytRKgAKxHtSHBgHbemdGrwY0
9G/Aqvq8ngEIcIAuJAAbhuy6b0AAuKOVz1pHQgqIbK0ESulu/wR51we4wyMEpGGxXHA0NP8vXRsG
cfVyeMHtaNjiNIyOhSLEwTlW7qoW6MRxFkSgAgPg4bzy1AICPM+AHSyAOwVcy/9jOH9bcST0YAmH
lfApBb7wWvVvmEBtGdAA/adh9P7r/df7r/df77/ef73/ev/1/uv91/uv91/vv95/vf96//X+6/3X
+6/3X++/3n+9/3r/9f7r/df7r/df77/ef73/ev/1/uv91/uv594A
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
    <string name="dns_hint">IP или имя хоста, например 8.8.8.8 или dns.google</string>
    <string name="dns_soon">Имя хоста превращается в IP-адреса при подключении и работает как обычный DNS внутри туннеля. Настоящие DoH/DoT пока не поддерживаются.</string>
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
    <string name="reg_working">Идёт регистрация устройства…</string>
    <string name="reg_none">Устройство не зарегистрировано</string>
    <string name="reg_retry">Повторю регистрацию сам: то по Wi-Fi, то через мобильную сеть</string>
    <string name="value_none">нет</string>
    <string name="adv_sec_apps">Приложения и сеть</string>
    <string name="adv_sec_conn">Подключение</string>
    <string name="adv_sec_other">Прочее</string>
    <string name="adv_parallel">Параллельный режим и горячий резерв</string>
    <string name="adv_parallel_sub">Несколько путей одновременно, мгновенный переход на резерв при сбое. Отключите, если что-то работает странно.</string>
    <string name="diag_full_running">Проверяю, это займёт несколько секунд…</string>
    <string name="diag_sys">Состояние системы и памяти</string>
    <string name="diag_sys_sub">Сети, батарея, режимы Android, DNS, оператор, память стратегий</string>
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
    <string name="dns_hint">IP or hostname, e.g. 8.8.8.8 or dns.google</string>
    <string name="dns_soon">A hostname is resolved to IP addresses on connect and works as plain DNS inside the tunnel. Real DoH/DoT is not supported yet.</string>
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
    <string name="reg_working">Registering the device…</string>
    <string name="reg_none">Device is not registered</string>
    <string name="reg_retry">I will retry on my own: via Wi-Fi, then via mobile network</string>
    <string name="value_none">none</string>
    <string name="adv_sec_apps">Apps and network</string>
    <string name="adv_sec_conn">Connection</string>
    <string name="adv_sec_other">Other</string>
    <string name="adv_parallel">Parallel mode and hot standby</string>
    <string name="adv_parallel_sub">Several paths at once, instant switch to the standby on failure. Turn off if something misbehaves.</string>
    <string name="diag_full_running">Checking, this takes a few seconds…</string>
    <string name="diag_sys">System state and memory</string>
    <string name="diag_sys_sub">Networks, battery, Android modes, DNS, operator, strategy memory</string>
</resources>
HYDRA_EOF

putv app/src/main/res/values/themes.xml <<'HYDRA_EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="Theme.Hydra" parent="android:Theme.Material.NoActionBar">
        <item name="android:navigationBarColor">@android:color/black</item>
        <item name="android:statusBarColor">@android:color/black</item>
        <item name="android:windowBackground">@android:color/black</item>
    </style>
</resources>
HYDRA_EOF

putv app/src/main/res/xml/file_paths.xml <<'HYDRA_EOF'
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <cache-path name="reports" path="reports/" />
</paths>
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
	NetAlive     func() bool   // есть ли вообще интернет мимо туннеля (nil — не проверять)
	DropV6       bool          // в аккаунте нет IPv6: пакеты v6 из TUN отбрасываются
	Parallel     int           // >1: параллельная гонка стратегий и горячий резерв; 0/1 — по очереди
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

	// статистика работы (под mu)
	nConnect, nFailover, nLost int
	upSince                    time.Time
	lastFail                   string
	lastFailAt                 time.Time

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

// attemptDev — «карта» одной попытки: после отмены попытки её горутины просыпаются с ошибкой
// и не крадут пакеты у следующей. У каждой попытки свои порты и очередь проб, поэтому несколько
// попыток могут работать одновременно; трафик приложений идёт только через активную.
type attemptDev struct {
	e       *Engine
	done    <-chan struct{}
	probeQ  chan []byte
	port    uint16
	tcpPort uint16
	tcpSeq  uint32
	tcpAck  chan struct{}
	active  int32         // 1 — через эту карту идёт трафик приложений
	sent    int32         // сколько пакетов клиент туннеля забрал у нас (пробы и трафик)
	recv    int32         // сколько пакетов клиент туннеля отдал нам
	wake    chan struct{} // будит ReadPacket, когда карта становится активной
}

func newAttemptDev(e *Engine, done <-chan struct{}, active bool) *attemptDev {
	d := &attemptDev{
		e:       e,
		done:    done,
		probeQ:  make(chan []byte, 16),
		port:    uint16(20000 + rand.Intn(20000)),
		tcpPort: uint16(41000 + rand.Intn(20000)),
		tcpAck:  make(chan struct{}, 1),
		wake:    make(chan struct{}, 1),
	}
	if active {
		d.active = 1
	}
	return d
}

// promote делает карту активной: с этого момента через неё идёт трафик приложений.
func (d *attemptDev) promote() {
	atomic.StoreInt32(&d.active, 1)
	select {
	case d.wake <- struct{}{}:
	default:
	}
}

// demote лишает карту трафика приложений (она остаётся пригодной для проб).
func (d *attemptDev) demote() { atomic.StoreInt32(&d.active, 0) }

func (d *attemptDev) ReadPacket(buf []byte) (int, error) {
	for {
		var outc <-chan []byte
		if atomic.LoadInt32(&d.active) == 1 {
			outc = d.e.out
		}
		select {
		case <-d.done:
			return 0, io.EOF
		case <-d.e.tunDead:
			return 0, io.EOF
		case p := <-d.probeQ:
			atomic.AddInt32(&d.sent, 1)
			return copy(buf, p), nil
		case p := <-outc:
			atomic.AddInt32(&d.sent, 1)
			return copy(buf, p), nil
		case <-d.wake:
		}
	}
}

func (d *attemptDev) WritePacket(pkt []byte) error {
	select {
	case <-d.done:
		return io.ErrClosedPipe
	default:
	}
	atomic.AddInt32(&d.recv, 1)
	if id, colo, ok := ParseColoReply(pkt, d.port); ok {
		d.e.deliver(id, colo)
		return nil
	}
	if ParseTCPSynAck(pkt, d.tcpPort, atomic.LoadUint32(&d.tcpSeq)+1) {
		select {
		case d.tcpAck <- struct{}{}:
		default:
		}
		return nil
	}
	if atomic.LoadInt32(&d.active) != 1 {
		return nil // резервный туннель трафик приложений не пропускает
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

// probe шлёт UDP-пробу (DNS id.server) через эту карту и ждёт ответ: задержка и код дата-центра.
func (d *attemptDev) probe(ctx context.Context, timeout time.Duration) (time.Duration, string, error) {
	e := d.e
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
	pkt := BuildColoProbe(e.cfg.LocalIP, d.port, id)
	if pkt == nil {
		return 0, "", errors.New("нет IPv4-адреса туннеля")
	}
	t0 := time.Now()
	select {
	case d.probeQ <- pkt:
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

// tcpProbe: SYN на 1.1.1.1:443 через эту карту, ждём SYN-ACK.
func (d *attemptDev) tcpProbe(ctx context.Context, timeout time.Duration) (time.Duration, error) {
	e := d.e
	seq := rand.Uint32()
	atomic.StoreUint32(&d.tcpSeq, seq)
	select {
	case <-d.tcpAck:
	default:
	}
	id := uint16(atomic.AddUint32(&e.nextID, 1))
	syn := BuildTCPSyn(e.cfg.LocalIP, d.tcpPort, seq, id)
	if syn == nil {
		return 0, errors.New("нет IPv4-адреса туннеля")
	}
	t0 := time.Now()
	select {
	case d.probeQ <- syn:
	default:
		return 0, errors.New("очередь проб переполнена")
	}
	select {
	case <-d.tcpAck:
		rtt := time.Since(t0)
		if rst := BuildTCPRst(e.cfg.LocalIP, d.tcpPort, seq+1, id+1); rst != nil {
			select {
			case d.probeQ <- rst:
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
	offline     bool // интернета нет совсем: стратегию не винить, ждать сеть
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
	if !e.blame(nk, s.ID) {
		return outcome{reason: "нет интернета", offline: true}
	}
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
	dev := newAttemptDev(e, actx.Done(), true)
	errc := make(chan error, 1)
	go func() { errc <- e.cfg.Runner(actx, dev, s) }()

	timeout := e.cfg.UpTimeout
	if e.cfg.Mem.Worked(nk, s.ID) {
		timeout = timeout * 5 / 3 // уже работала здесь: на медленной сети рукопожатие бывает 5–6 с
	} else if e.cfg.Mem.Doomed(nk, s.ID) {
		timeout = timeout * 2 / 3 // не раз подводила: не тратим на неё время
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
		r, c, err := dev.probe(actx, 1500*time.Millisecond)
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
			if tcpRTT, terr = dev.tcpProbe(actx, e.cfg.TCPTimeout); terr == nil {
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
			e.blame(nk, s.ID)
			return outcome{wasUp: true, reason: msg}
		case <-tk.C:
			if e.cfg.NetKey() != nk {
				Logf("↻ сеть сменилась (%s → %s) — переподключаюсь", nk, e.cfg.NetKey())
				return outcome{wasUp: true, netChanged: true, reason: "сменилась сеть"}
			}
			ticks++
			r, c, err := dev.probe(actx, e.cfg.ProbeEvery)
			if err == nil && e.cfg.TCPCheck && ticks%5 == 0 {
				_, err = dev.tcpProbe(actx, e.cfg.TCPTimeout)
			}
			if err != nil {
				bad++
				Logf("   проба без ответа (%d из %d): %v", bad, e.cfg.BadProbes, err)
				if bad >= e.cfg.BadProbes {
					e.blame(nk, s.ID)
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
	select { // стартовый сигнал о смене сети (его присылает Android при запуске) не нужен
	case <-e.cfg.NetChanged:
	default:
	}
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
			if n := e.cfg.Mem.Prune(nk); n > 0 {
				Logf("🧹 убрал %d придуманных способов, которые в этой сети не работают", n)
			}
		}
		cands := e.cfg.Mem.Rank(nk, e.allStrategies(nk))
		ran, skipped := 0, 0
		lastReason := ""
		sawBlocked := false
		restart := false
		if e.cfg.Parallel > 1 {
			ran, skipped, lastReason, sawBlocked, restart, skip = e.raceRound(ctx, nk, cands, skip, blocked)
			cands = nil // старый последовательный перебор ниже не нужен
		}
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
			if r.offline {
				e.setStatus(Status{State: "reconnecting", Message: "нет интернета — жду сеть"})
				e.waitOnline(ctx)
				skip = ""
				restart = true
				break
			}
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
		if ran > 0 && !sawBlocked {
			e.learn(nk) // все способы подвели — придумываем новые на основе лучших
		}
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

func (e *Engine) noteConnect() {
	e.mu.Lock()
	e.nConnect++
	e.upSince = time.Now()
	e.mu.Unlock()
}

func (e *Engine) noteLoss(reason string, failover bool) {
	e.mu.Lock()
	if failover {
		e.nFailover++
	} else {
		e.nLost++
	}
	e.lastFail = reason
	e.lastFailAt = time.Now()
	e.mu.Unlock()
}

// Stats — сводка работы движка для диагностики.
func (e *Engine) Stats() string {
	e.mu.Lock()
	defer e.mu.Unlock()
	mode := "по очереди"
	if e.cfg.Parallel > 1 {
		mode = "параллельный (гонка + горячий резерв)"
	}
	s := "режим: " + mode + "\n"
	s += "подключений: " + itoa(e.nConnect) + ", мгновенных переходов на резерв: " + itoa(e.nFailover) + ", потерь без резерва: " + itoa(e.nLost) + "\n"
	if !e.upSince.IsZero() {
		s += "с последнего подключения: " + time.Since(e.upSince).Round(time.Second).String() + "\n"
	}
	if e.lastFail != "" {
		s += "последний сбой: " + e.lastFail + " (" + e.lastFailAt.Format("15:04:05") + ")\n"
	}
	return s
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

putv "$GODIR/learn.go" <<'HYDRA_EOF'
package hydra

import (
	"context"
	"fmt"
	"math/rand"
	"strconv"
	"time"
)

// Самообучение: когда все известные способы подвели, Гидра придумывает новые — мутирует лучшие
// (TTL и число фейковых пакетов, их размер, SNI, адрес), запоминает и выбрасывает те, что не работают.

var fakeSNIPool = []string{"www.google.com", "vk.com", "ya.ru", "yandex.ru", "mail.ru", "www.microsoft.com", "cloudflare.com", "dzen.ru"}
var fakeSizePool = []int{64, 100, 128, 200, 256, 400, 600, 900, 1200}

func clampInt(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

// allStrategies — встроенные стратегии плюс придуманные для этой сети.
func (e *Engine) allStrategies(nk string) []Strategy {
	out := append([]Strategy(nil), e.cfg.Strategies...)
	return append(out, e.cfg.Mem.Generated(nk)...)
}

// sniPool — SNI, которые принимает сервер MASQUE Cloudflare (сертификат проверяется по ключу, а не по имени).
var sniPool = []string{
	"consumer-masque.cloudflareclient.com", "cdnjs.cloudflare.com", "www.cloudflare.com",
	"one.one.one.one", "developers.cloudflare.com", "dash.cloudflare.com",
}

func family(s Strategy) string {
	switch {
	case s.Transport == "masque" && s.Params["h2"] == "1":
		return "h2"
	case s.Transport == "masque" && s.Params["fake"] != "":
		return "h3"
	case s.Transport == "wg" && s.Params["jc"] != "":
		return "wg"
	}
	return ""
}

// GenerateVariants возвращает до n новых вариантов на основе лучших известных в этой сети:
// QUIC с фейковыми пакетами (h3), HTTP/2 (h2) и WireGuard с «мусорным» прологом (wg).
func GenerateVariants(nk string, mem *Memory, all []Strategy, n int, rnd *rand.Rand) []Strategy {
	parents := map[string][]Strategy{}
	for _, s := range mem.Rank(nk, all) {
		f := family(s)
		if f == "" || len(parents[f]) >= 3 {
			continue
		}
		parents[f] = append(parents[f], s)
	}
	var fams []string
	for _, f := range []string{"h3", "h3", "h2", "wg"} { // QUIC — вдвое чаще остальных
		if len(parents[f]) > 0 {
			fams = append(fams, f)
		}
	}
	if len(fams) == 0 {
		return nil
	}
	eps := map[string][]string{}
	seenEP := map[string]bool{}
	for _, s := range all {
		f := family(s)
		ep := s.Params["endpoint"]
		if f == "" || ep == "" || seenEP[f+ep] {
			continue
		}
		seenEP[f+ep] = true
		eps[f] = append(eps[f], ep)
	}
	have := map[string]bool{}
	for _, s := range all {
		have[s.ID] = true
	}
	var out []Strategy
	for tries := 0; tries < n*8 && len(out) < n; tries++ {
		f := fams[rnd.Intn(len(fams))]
		ps := parents[f]
		p := ps[rnd.Intn(len(ps))]
		q := map[string]string{}
		for k, v := range p.Params {
			q[k] = v
		}
		if len(eps[f]) > 1 && rnd.Intn(4) == 0 {
			q["endpoint"] = eps[f][rnd.Intn(len(eps[f]))]
		}
		var id string
		switch f {
		case "h3":
			ttl := clampInt(atoiDefault(q["fttl"], 5)+rnd.Intn(5)-2, 2, 12)
			cnt := clampInt(atoiDefault(q["fcount"], 4)+rnd.Intn(5)-2, 1, 10)
			size := atoiDefault(q["fsize"], 1200)
			if rnd.Intn(10) < 3 {
				size = fakeSizePool[rnd.Intn(len(fakeSizePool))]
			}
			if rnd.Intn(10) < 3 {
				q["fake"] = fakeSNIPool[rnd.Intn(len(fakeSNIPool))]
			}
			if rnd.Intn(4) == 0 { // настоящий SNI в QUIC Initial — то, что читает DPI
				q["sni"] = sniPool[rnd.Intn(len(sniPool))]
			}
			q["fttl"] = strconv.Itoa(ttl)
			q["fcount"] = strconv.Itoa(cnt)
			q["fsize"] = strconv.Itoa(size)
			id = fmt.Sprintf("h3/%s/g:%s:%s:%dx%ds%d", q["endpoint"], q["sni"], q["fake"], ttl, cnt, size)
		case "h2":
			q["sni"] = sniPool[rnd.Intn(len(sniPool))]
			id = fmt.Sprintf("h2/%s/g:%s", q["endpoint"], q["sni"])
		case "wg":
			jc := clampInt(atoiDefault(q["jc"], 4)+rnd.Intn(5)-2, 1, 16)
			jmin := clampInt(atoiDefault(q["jmin"], 40)+rnd.Intn(21)-10, 5, 100)
			jmax := clampInt(atoiDefault(q["jmax"], 70)+rnd.Intn(61)-30, jmin+10, 300)
			q["jc"], q["jmin"], q["jmax"] = strconv.Itoa(jc), strconv.Itoa(jmin), strconv.Itoa(jmax)
			id = fmt.Sprintf("wg/%s/g:%d-%d-%d", q["endpoint"], jc, jmin, jmax)
		}
		if id == "" || have[id] {
			continue
		}
		have[id] = true
		out = append(out, Strategy{ID: id, Transport: p.Transport, Params: q})
	}
	return out
}

// learn придумывает и запоминает новые способы для этой сети.
func (e *Engine) learn(nk string) {
	if e.cfg.Mem == nil {
		return
	}
	rnd := rand.New(rand.NewSource(time.Now().UnixNano()))
	gen := GenerateVariants(nk, e.cfg.Mem, e.allStrategies(nk), 6, rnd)
	if len(gen) == 0 {
		return
	}
	e.cfg.Mem.AddGenerated(nk, gen)
	Logf("🧬 все известные способы не сработали — придумал %d новых вариантов обхода для сети %s", len(gen), nk)
}

// blame записывает провал стратегии, но только если интернет вообще есть: иначе виновата сеть, а не стратегия.
func (e *Engine) blame(nk, id string) bool {
	if e.cfg.NetAlive != nil && !e.cfg.NetAlive() {
		Logf("   ⚠ интернета нет совсем — стратегию не виню")
		return false
	}
	e.cfg.Mem.Record(nk, id, false, 0)
	return true
}

// waitOnline ждёт, пока интернет снова появится (проверка раз в 3 с или по сигналу о смене сети).
func (e *Engine) waitOnline(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case <-e.cfg.NetChanged:
		case <-time.After(3 * time.Second):
		}
		if e.cfg.NetAlive == nil || e.cfg.NetAlive() {
			return
		}
	}
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
	"fmt"
	"math"
	"os"
	"sort"
	"strings"
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
	// Gen — стратегии, которые Гидра придумала сама, по сетям.
	Gen map[string][]Strategy `json:"gen"`
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
	m.saveSoonLocked()
}

// saveSoonLocked планирует сохранение через 2 с (вызывать под m.mu): если систему убьёт процесс,
// накопленный опыт не пропадёт, а на диск пишем не на каждый чих.
func (m *Memory) saveSoonLocked() {
	if m.path == "" || m.pending {
		return
	}
	m.pending = true
	time.AfterFunc(2*time.Second, func() {
		m.mu.Lock()
		m.pending = false
		m.mu.Unlock()
		_ = m.Save()
	})
}

const maxGenerated = 24

// Generated — придуманные Гидрой стратегии для этой сети.
func (m *Memory) Generated(net string) []Strategy {
	m.mu.Lock()
	defer m.mu.Unlock()
	return append([]Strategy(nil), m.Gen[net]...)
}

// AddGenerated запоминает новые стратегии; при переполнении выбрасывает самые старые, не имевшие побед.
func (m *Memory) AddGenerated(net string, list []Strategy) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.Gen == nil {
		m.Gen = map[string][]Strategy{}
	}
	have := map[string]bool{}
	for _, s := range m.Gen[net] {
		have[s.ID] = true
	}
	for _, s := range list {
		if !have[s.ID] {
			m.Gen[net] = append(m.Gen[net], s)
			have[s.ID] = true
		}
	}
	over := len(m.Gen[net]) - maxGenerated
	if over > 0 {
		var kept []Strategy
		for _, s := range m.Gen[net] {
			st := m.Nets[net][s.ID]
			if over > 0 && (st == nil || st.OK == 0) {
				over--
				delete(m.Nets[net], s.ID)
				continue
			}
			kept = append(kept, s)
		}
		m.Gen[net] = kept
	}
	m.saveSoonLocked()
}

// Prune удаляет придуманные стратегии, которые в этой сети не работают. Возвращает, сколько удалено.
func (m *Memory) Prune(net string) int {
	m.mu.Lock()
	defer m.mu.Unlock()
	removed := 0
	var kept []Strategy
	for _, s := range m.Gen[net] {
		st := m.Nets[net][s.ID]
		dead := st != nil && ((st.OK == 0 && st.Fail >= 3) ||
			(st.Fail >= 8 && float64(st.OK)/float64(st.OK+st.Fail) < 0.15))
		if dead {
			delete(m.Nets[net], s.ID)
			removed++
			continue
		}
		kept = append(kept, s)
	}
	if removed > 0 {
		m.Gen[net] = kept
		m.saveSoonLocked()
	}
	return removed
}

// Doomed: стратегия в этой сети уже не раз подводила и ни разу не работала.
func (m *Memory) Doomed(net, id string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	st := m.Nets[net][id]
	return st != nil && st.OK == 0 && st.Fail >= 3
}

// priorLocked — оценка стратегии для сети без истории: опыт в других сетях того же класса
// (все "wifi:*" или все "cell:*") с пониженным доверием. Вызывать под m.mu.
func (m *Memory) priorLocked(net, id string) float64 {
	class := net
	if i := strings.Index(net, ":"); i > 0 {
		class = net[:i]
	}
	ok, fail := 0, 0
	for k, ns := range m.Nets {
		if k == net || !strings.HasPrefix(k, class+":") {
			continue
		}
		if st := ns[id]; st != nil {
			ok += st.OK
			fail += st.Fail
		}
	}
	if ok+fail == 0 {
		return 0.5
	}
	rate := float64(ok+1) / float64(ok+fail+2)
	return 0.5 + (rate-0.5)*0.6
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
			return m.priorLocked(net, s.ID)
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

// Summary — читаемая сводка памяти для диагностики: лучшие стратегии в этой сети и счётчики.
func (m *Memory) Summary(net string, n int) string {
	m.mu.Lock()
	defer m.mu.Unlock()
	ns := m.Nets[net]
	type row struct {
		id string
		st *stat
	}
	rows := make([]row, 0, len(ns))
	for id, st := range ns {
		rows = append(rows, row{id, st})
	}
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].st.OK != rows[j].st.OK {
			return rows[i].st.OK > rows[j].st.OK
		}
		return rows[i].st.Fail < rows[j].st.Fail
	})
	out := fmt.Sprintf("память: сетей %d; в этой сети (%s) стратегий с опытом %d, придуманных %d\n", len(m.Nets), net, len(ns), len(m.Gen[net]))
	for i, r := range rows {
		if i >= n {
			break
		}
		last := "—"
		if !r.st.LastOK.IsZero() {
			last = r.st.LastOK.Format("01-02 15:04")
		}
		out += fmt.Sprintf("  %s: успехов %d, сбоев %d, ~%.0f мс, последний успех %s\n", r.id, r.st.OK, r.st.Fail, r.st.EWMAms, last)
	}
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

putv "$GODIR/mobile/netalive.go" <<'HYDRA_EOF'
package mobile

import (
	"net"
	"time"
)

// realNetAlive: есть ли интернет мимо туннеля (приложение исключено из VPN, поэтому проверка честная).
// Достаточно, чтобы ответил любой из нескольких известных адресов.
func realNetAlive() bool {
	targets := []string{"1.1.1.1:443", "8.8.8.8:443", "77.88.8.8:443", "9.9.9.9:443"}
	ch := make(chan bool, len(targets))
	for _, t := range targets {
		go func(t string) {
			c, err := net.DialTimeout("tcp", t, 2500*time.Millisecond)
			if err == nil {
				c.Close()
			}
			ch <- err == nil
		}(t)
	}
	for range targets {
		if <-ch {
			return true
		}
	}
	return false
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
	polProto = "auto"
	netKey   = "default"
	polPar   = 3  // сколько стратегий пробовать одновременно (0/1 — по очереди)
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

// SetParallel включает параллельную гонку стратегий и горячий резерв: n — сколько стратегий
// пробовать одновременно (0 или 1 — по очереди, как раньше).
func SetParallel(n int) {
	polMu.Lock()
	polPar = n
	polMu.Unlock()
}

func currentParallel() int {
	polMu.Lock()
	defer polMu.Unlock()
	return polPar
}

// LogLine дописывает строку в журнал Гидры (для результатов диагностики из приложения).
func LogLine(s string) { hydra.Logf("%s", s) }
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
	vpnMem    *hydra.Memory
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
	vpnMem = mem

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
	cfg.NetAlive = realNetAlive
	cfg.Parallel = currentParallel()

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

// Diagnostics — сводка движка и памяти стратегий для отчёта.
func Diagnostics() string {
	out := ""
	if e := vpnEngine; e != nil {
		out += e.Stats()
	} else {
		out += "движок не запущен\n"
	}
	polMu.Lock()
	nk := netKey
	polMu.Unlock()
	if m := vpnMem; m != nil {
		out += m.Summary(nk, 15)
	}
	return out
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

putv "$GODIR/race.go" <<'HYDRA_EOF'
package hydra

import (
	"context"
	"sync/atomic"
	"time"
)

// Параллельный режим: несколько стратегий поднимаются одновременно (со сдвигом), побеждает
// первая рабочая, вторая рабочая остаётся горячим резервом. При сбое основного туннеля трафик
// мгновенно переходит на резерв, без нового подключения. Пока всё хорошо, свободный слот резерва
// используется для проверки других стратегий: так Гидра учится прямо во время работы.

const (
	raceStagger  = 700 * time.Millisecond // пауза перед запуском следующей стратегии в гонке
	standbyEvery = 45 * time.Second       // как часто пробовать новый резерв
	standbyRetry = 10 * time.Minute       // не пробовать одну и ту же стратегию в резерве чаще
)

// attempt — одна запущенная стратегия.
type attempt struct {
	s      Strategy
	dev    *attemptDev
	ctx    context.Context
	cancel context.CancelFunc
	errc   chan error
	start  time.Time
	colo   string
	rtt    time.Duration
}

type verdict struct {
	a  *attempt
	ok bool
	o  outcome
}

func (e *Engine) startAttempt(ctx context.Context, s Strategy, active bool) *attempt {
	actx, cancel := context.WithCancel(ctx)
	a := &attempt{
		s:      s,
		dev:    newAttemptDev(e, actx.Done(), active),
		ctx:    actx,
		cancel: cancel,
		errc:   make(chan error, 1),
		start:  time.Now(),
	}
	Logf("▶ стратегия %s", s.ID)
	Logf("   %s", describeStrategy(s))
	go func() { a.errc <- e.cfg.Runner(actx, a.dev, s) }()
	return a
}

// verify ждёт, пока попытка поднимется, и проверяет её: ответ туннеля, дата-центр, реальный TCP.
func (e *Engine) verify(nk string, a *attempt) (bool, outcome) {
	s := a.s
	timeout := e.cfg.UpTimeout
	if e.cfg.Mem.Worked(nk, s.ID) {
		timeout = timeout * 5 / 3
	} else if e.cfg.Mem.Doomed(nk, s.ID) {
		timeout = timeout * 2 / 3
	}
	up := false
	var colo string
	var rtt time.Duration
	for !up && time.Since(a.start) < timeout {
		select {
		case err := <-a.errc:
			msg := "туннель не поднялся"
			if err != nil {
				msg = err.Error()
			}
			Logf("   ✘ %s: клиент остановился: %s", s.ID, msg)
			return false, e.fail(nk, s, msg)
		case <-a.ctx.Done():
			return false, outcome{reason: "остановка"}
		default:
		}
		r, c, err := a.dev.probe(a.ctx, 1500*time.Millisecond)
		if err == nil {
			up, colo, rtt = true, c, r
		} else {
			select {
			case <-a.ctx.Done():
				return false, outcome{reason: "остановка"}
			case <-time.After(200 * time.Millisecond):
			}
		}
	}
	if !up {
		sent, recv := int(atomic.LoadInt32(&a.dev.sent)), int(atomic.LoadInt32(&a.dev.recv))
		hint := ""
		switch {
		case recv > 0:
			hint = " — пакеты из туннеля приходят, но проба без ответа: сервер принял туннель, но не пропускает трафик"
		case s.Transport == "wg":
			hint = " — WireGuard: рукопожатие могло пройти, но данные из туннеля не возвращаются"
		case s.Params["h2"] == "1":
			hint = " — из туннеля не пришло ни одного пакета (HTTP/2 к этому адресу)"
		default:
			hint = " — из туннеля не пришло ни одного пакета: похоже, QUIC к этому адресу режется"
		}
		msg := "нет ответа от туннеля за " + itoa(int(timeout.Seconds())) + " с (в туннель ушло пакетов: " + itoa(sent) + ", пришло из туннеля: " + itoa(recv) + ")" + hint
		Logf("   ✘ %s: %s", s.ID, msg)
		return false, e.fail(nk, s, msg)
	}
	Logf("   %s: туннель ответил за %d мс, дата-центр Cloudflare: %s", s.ID, rtt.Milliseconds(), colo)
	if !e.policy().Allows(colo) {
		Logf("   ✘ %s: дата-центр %s запрещён настройками", s.ID, colo)
		e.cfg.Mem.Record(nk, s.ID, false, 0)
		e.emit("colo_blocked", s.ID, colo)
		return false, outcome{coloBlocked: colo, reason: "дата-центр " + colo + " запрещён"}
	}
	if e.cfg.TCPCheck {
		var terr error
		for i := 0; i < 3; i++ {
			if _, terr = a.dev.tcpProbe(a.ctx, e.cfg.TCPTimeout); terr == nil {
				break
			}
			if a.ctx.Err() != nil {
				return false, outcome{reason: "остановка"}
			}
		}
		if terr != nil {
			msg := "UDP через туннель идёт, а TCP — нет (туннель не пропускает интернет)"
			Logf("   ✘ %s: %s", s.ID, msg)
			return false, e.fail(nk, s, msg)
		}
	}
	e.cfg.Mem.Record(nk, s.ID, true, time.Since(a.start))
	a.colo, a.rtt = colo, rtt
	return true, outcome{}
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var b [20]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		b[i] = '-'
	}
	return string(b[i:])
}

// pickStandby выбирает стратегию для резерва: лучшая по памяти того же транспорта, что и основная,
// по возможности с другим адресом; другие транспорты — только если своих кандидатов не осталось.
func (e *Engine) pickStandby(nk string, primary Strategy, blocked map[string]time.Time, tried map[string]time.Time) (Strategy, bool) {
	pep := hostOnly(primary.Params["endpoint"])
	ranked := e.cfg.Mem.Rank(nk, e.allStrategies(nk))
	pass := func(sameTransport bool) (Strategy, bool) {
		var fb Strategy
		haveFB := false
		for _, s := range ranked {
			if s.ID == primary.ID || (s.Transport == primary.Transport) != sameTransport {
				continue
			}
			if t, ok := tried[s.ID]; ok && time.Since(t) < standbyRetry {
				continue
			}
			ep := s.Params["endpoint"]
			if until, ok := blocked[hostOnly(ep)]; ep != "" && ok && time.Now().Before(until) {
				continue
			}
			if e.cfg.Mem.Doomed(nk, s.ID) {
				continue
			}
			if hostOnly(ep) != pep {
				return s, true
			}
			if !haveFB {
				fb, haveFB = s, true
			}
		}
		return fb, haveFB
	}
	if s, ok := pass(true); ok {
		return s, true
	}
	return pass(false)
}

// raceRound — один «раунд» параллельного режима: гонка, затем работа с горячим резервом,
// пока соединение не оборвётся окончательно. Возвращает то же, что собирал бы последовательный перебор.
func (e *Engine) raceRound(ctx context.Context, nk string, cands []Strategy, skip string, blocked map[string]time.Time) (ran, skipped int, lastReason string, sawBlocked, restart bool, newSkip string) {
	newSkip = skip
	n := e.cfg.Parallel
	if n > 4 {
		n = 4
	}
	idx := 0
	res := make(chan verdict, 64)
	live := 0
	var all []*attempt
	defer func() {
		for _, a := range all {
			a.cancel()
		}
	}()

	nextCand := func() (Strategy, bool) {
		for idx < len(cands) {
			s := cands[idx]
			idx++
			if s.ID == skip {
				continue
			}
			ep := s.Params["endpoint"]
			if until, ok := blocked[hostOnly(ep)]; ep != "" && ok && time.Now().Before(until) {
				skipped++
				continue
			}
			return s, true
		}
		return Strategy{}, false
	}
	launch := func(s Strategy) {
		a := e.startAttempt(ctx, s, false)
		all = append(all, a)
		live++
		ran++
		go func() {
			ok, o := e.verify(nk, a)
			res <- verdict{a, ok, o}
		}()
	}
	noteFail := func(v verdict) {
		lastReason = v.o.reason
		if v.o.coloBlocked != "" {
			sawBlocked = true
			if ep := v.a.s.Params["endpoint"]; ep != "" {
				blocked[hostOnly(ep)] = time.Now().Add(10 * time.Minute)
				Logf("   адрес %s ведёт в запрещённый %s — остальные стратегии с ним пропускаю на 10 минут", ep, v.o.coloBlocked)
			}
		}
		v.a.cancel()
	}

	// ---- гонка ----
	var p *attempt
	exhausted := false
	stagger := time.NewTimer(0)
	defer stagger.Stop()
	e.setStatus(Status{State: "connecting"})
	for p == nil {
		select {
		case <-ctx.Done():
			return
		case <-e.cfg.NetChanged:
			Logf("   ↻ сеть сменилась во время подключения — начинаю заново")
			newSkip = ""
			restart = true
			return
		case <-stagger.C:
			if live < n && !exhausted {
				if s, ok := nextCand(); ok {
					launch(s)
				} else {
					exhausted = true
				}
			}
			if live == 0 && exhausted {
				return
			}
			if !exhausted {
				stagger.Reset(raceStagger)
			}
		case v := <-res:
			live--
			if v.ok {
				p = v.a
				continue
			}
			if v.o.offline {
				e.setStatus(Status{State: "reconnecting", Message: "нет интернета — жду сеть"})
				e.waitOnline(ctx)
				newSkip = ""
				restart = true
				return
			}
			noteFail(v)
			if live == 0 {
				if s, ok := nextCand(); ok {
					launch(s)
				} else {
					return
				}
			}
		}
	}

	// ---- победитель ----
	p.dev.promote()
	msg := ""
	if e.soft {
		msg = "режим «всё равно»: другого дата-центра нет"
		Logf("   ⚠ %s", msg)
	}
	colo := p.colo
	e.setStatus(Status{State: "up", Strategy: p.s.ID, Colo: colo, RTT: p.rtt, Message: msg})
	e.emit("connected", p.s.ID, colo)
	Logf("✔ подключено за %.1f с: %s, дата-центр %s, пинг %d мс", time.Since(p.start).Seconds(), p.s.ID, colo, p.rtt.Milliseconds())
	e.noteConnect()

	var sb *attempt
	tried := map[string]time.Time{}
	bad, sbBad, ticks := 0, 0, 0
	nextSb := time.Now().Add(3 * time.Second)
	lastLearn := time.Time{}

	// мгновенный переход на резерв; false — резерва нет
	failover := func(reason string) bool {
		if sb == nil {
			return false
		}
		old := p
		old.dev.demote()
		old.cancel()
		p = sb
		sb = nil
		sbBad, bad = 0, 0
		p.dev.promote()
		colo = p.colo
		e.setStatus(Status{State: "up", Strategy: p.s.ID, Colo: colo, RTT: p.rtt, Message: msg})
		e.emit("connected", p.s.ID, colo)
		Logf("⚡ резерв принял нагрузку без разрыва: %s → %s (%s)", old.s.ID, p.s.ID, reason)
		e.noteLoss(reason, true)
		nextSb = time.Now().Add(5 * time.Second)
		return true
	}
	lose := func(reason string) {
		e.noteLoss(reason, false)
		e.setStatus(Status{State: "reconnecting", Message: reason})
		newSkip = p.s.ID
		restart = true
	}

	// ---- работа ----
	tk := time.NewTicker(e.cfg.ProbeEvery)
	defer tk.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-e.cfg.NetChanged:
			Logf("↻ сеть сменилась — переподключаюсь")
			newSkip = ""
			restart = true
			return
		case v := <-res:
			live--
			if v.ok {
				if sb == nil {
					sb = v.a
					sbBad = 0
					Logf("🛡 резерв готов: %s, дата-центр %s", sb.s.ID, sb.colo)
				} else {
					v.a.cancel()
				}
			} else {
				noteFail(v)
			}
		case err := <-p.errc:
			reason := "туннель закрылся"
			if err != nil {
				reason = err.Error()
			}
			Logf("✘ %s", reason)
			e.blame(nk, p.s.ID)
			if failover(reason) {
				continue
			}
			lose(reason)
			return
		case <-tk.C:
			if e.cfg.NetKey() != nk {
				Logf("↻ сеть сменилась (%s → %s) — переподключаюсь", nk, e.cfg.NetKey())
				newSkip = ""
				restart = true
				return
			}
			ticks++
			r, c, err := p.dev.probe(p.ctx, e.cfg.ProbeEvery)
			if err == nil && e.cfg.TCPCheck && ticks%5 == 0 {
				_, err = p.dev.tcpProbe(p.ctx, e.cfg.TCPTimeout)
			}
			if err != nil {
				bad++
				Logf("   проба без ответа (%d из %d): %v", bad, e.cfg.BadProbes, err)
				if bad >= e.cfg.BadProbes {
					e.blame(nk, p.s.ID)
					e.emit("degraded", p.s.ID, "туннель перестал отвечать")
					Logf("✘ туннель перестал отвечать")
					if failover("туннель перестал отвечать") {
						continue
					}
					lose("туннель перестал отвечать")
					return
				}
			} else {
				bad = 0
				if c != colo {
					Logf("   дата-центр сменился: %s → %s", colo, c)
					colo = c
					if !e.policy().Allows(c) {
						e.cfg.Mem.Record(nk, p.s.ID, false, 0)
						e.emit("colo_blocked", p.s.ID, c)
						Logf("✘ дата-центр %s запрещён", c)
						sawBlocked = true
						if ep := p.s.Params["endpoint"]; ep != "" {
							blocked[hostOnly(ep)] = time.Now().Add(10 * time.Minute)
						}
						if failover("дата-центр " + c + " запрещён") {
							continue
						}
						lose("дата-центр " + c + " запрещён")
						return
					}
				}
				e.setStatus(Status{State: "up", Strategy: p.s.ID, Colo: colo, RTT: r, Message: msg})
			}

			// здоровье резерва
			if sb != nil {
				select {
				case serr := <-sb.errc:
					Logf("   резерв %s остановился: %v", sb.s.ID, serr)
					sb.cancel()
					sb = nil
				default:
				}
			}
			if sb != nil {
				if _, _, perr := sb.dev.probe(sb.ctx, 1500*time.Millisecond); perr != nil {
					sbBad++
					if sbBad >= e.cfg.BadProbes {
						Logf("   резерв %s не отвечает — убираю", sb.s.ID)
						sb.cancel()
						sb = nil
						sbBad = 0
					}
				} else {
					sbBad = 0
				}
			}
			// новый резерв или проверка другой стратегии «на лету»
			if sb == nil && live == 0 && time.Now().After(nextSb) {
				nextSb = time.Now().Add(standbyEvery)
				if s, ok := e.pickStandby(nk, p.s, blocked, tried); ok {
					tried[s.ID] = time.Now()
					Logf("🛡 готовлю резерв: %s", s.ID)
					launch(s)
				} else if time.Since(lastLearn) > 10*time.Minute {
					lastLearn = time.Now()
					e.learn(nk)
				}
			}
		}
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
				if l := fmt.Sprintf(format, args...); strings.Contains(l, "andshake") && !strings.Contains(l, "Routine:") {
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
