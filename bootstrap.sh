#!/usr/bin/env bash
# WARP CLAUDE (Гидра) — полная синхронизация проекта, набор 21 (v22.6).
# Новое: регистрация WARP на старых прошивках и ТВ-приставках (встроенные корневые сертификаты + поправка на неверные
# часы устройства), запрет целой подсети /24 при уходе адреса в запрещённый дата-центр (быстрее на Билайне),
# проверка даты в «Диагнозе». Включает всё из наборов 13–20.
# Кладёт ВСЕ файлы проекта и убирает лишние .go/.kt, которых нет в наборе. Файлы заменяются один раз при смене номера.
set -e

STAMP=.hydra_bootstrap
OLD="$(cat "$STAMP" 2>/dev/null || echo 0)"
NEW=21
putv() {
  f="$1"
  mkdir -p "$(dirname "$f")"
  if [ ! -e "$f" ] || [ "$OLD" -lt "$NEW" ]; then cat > "$f"; else cat > /dev/null; fi
}
putb() {
  f="$1"
  mkdir -p "$(dirname "$f")"
  if [ ! -e "$f" ] || [ "$OLD" -lt "$NEW" ]; then base64 -d > "$f"; else cat > /dev/null; fi
}

GODIR="$(dirname "$(find . -name go.mod -not -path './app/*' | head -1)")"

putv ".gitignore" <<'HYDRA_EOF'
.gradle/
build/
app/build/
app/libs/
local.properties
*.aar
HYDRA_EOF

putv "NOTICE" <<'HYDRA_EOF'
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

putv "README.md" <<'HYDRA_EOF'
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

putv "app/build.gradle.kts" <<'HYDRA_EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "app.hydra"
    compileSdk = 35

    defaultConfig {
        applicationId = "warp.claude.app"
        minSdk = 26
        targetSdk = 35
        versionCode = 11
        versionName = "0.9.1"
        ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") }
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

putv "app/src/main/AndroidManifest.xml" <<'HYDRA_EOF'
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
        android:name=".HydraApp"
        android:banner="@drawable/tv_banner"
        android:allowBackup="false"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:label="@string/app_name"
        android:theme="@style/Theme.Hydra">
        <activity
            android:name=".MainActivity"
            android:banner="@drawable/tv_banner"
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

putv "app/src/main/java/app/hydra/AccountController.kt" <<'HYDRA_EOF'
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

    private var wg2Busy = false
    private var wg2Fails = 0

    /** Второй аккаунт WireGuard: у сервера одна сессия на ключ, без него резерв WireGuard невозможен. */
    private fun ensureWg2() {
        if (wg2Busy || wg2Fails >= 3 || wgId.isEmpty()) return
        val has = try { mobile.Mobile.wireguardExtraID(dir).isNotEmpty() } catch (t: Throwable) { true }
        if (has) return
        wg2Busy = true
        scope.launch {
            val r = withContext(Dispatchers.IO) {
                try {
                    mobile.Mobile.setDNS(dnsProvider())
                    mobile.Mobile.registerWireguardExtraReport(dir)
                } catch (t: Throwable) { "FAIL " + (t.message ?: "") }
            }
            if (!r.startsWith("OK")) wg2Fails++
            wg2Busy = false
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
        if (id.isNotEmpty() && wgId.isNotEmpty()) { healTries = 0; ensureWg2(); return }
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

putv "app/src/main/java/app/hydra/AdvancedScreens.kt" <<'HYDRA_EOF'
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
    var ipv6 by remember { mutableStateOf(prefs.ipv6) }
    var tgGate by remember { mutableStateOf(prefs.tgGate) }
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
        SettingSwitchRow(stringResource(R.string.adv_ipv6), stringResource(R.string.adv_ipv6_sub), ipv6) {
            ipv6 = it
            prefs.ipv6 = it
            vpn.restartIfActive()
        }
        SettingSwitchRow(stringResource(R.string.adv_tg), stringResource(R.string.adv_tg_sub), tgGate) {
            tgGate = it
            prefs.tgGate = it
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

putv "app/src/main/java/app/hydra/AppsScreen.kt" <<'HYDRA_EOF'
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

putv "app/src/main/java/app/hydra/BootReceiver.kt" <<'HYDRA_EOF'
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

putv "app/src/main/java/app/hydra/DiagScreen.kt" <<'HYDRA_EOF'
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

putv "app/src/main/java/app/hydra/Diagnostics.kt" <<'HYDRA_EOF'
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
    // кто провайдер этой сети: имя узла публичного IP (справочная строка, всегда «ОК»)
    out += try {
        if (base.ip.isNotEmpty()) {
            val host = InetAddress.getByName(base.ip).canonicalHostName
            DiagCheck("Провайдер сети (имя узла публичного IP)", true, if (host == base.ip) base.ip + ": имя узла не опубликовано" else base.ip + " → " + host)
        } else {
            DiagCheck("Провайдер сети (имя узла публичного IP)", true, "публичный IP не получен")
        }
    } catch (e: Exception) {
        DiagCheck("Провайдер сети (имя узла публичного IP)", true, "не определён: " + (e.message ?: e.javaClass.simpleName))
    }
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
    sb.append(try { buildDoctor(ctx, prefs, vpn, checks) } catch (t: Throwable) { "\n=== ДИАГНОЗ: сбой разбора (" + t + ") ===\n" })
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
    sb.append("selected apps: ").append(prefs.splitApps.sorted().joinToString(", ").ifEmpty { "—" }).append('\n')
    sb.append("telegram selected: ").append(prefs.splitApps.any { it.contains("telegram", true) }).append('\n')
    sb.append("\n--- движок и память ---\n")
    sb.append(try { mobile.Mobile.diagnostics() } catch (t: Throwable) { "н/д\n" })
    sb.append("\n--- система ---\n")
    sb.append(try { systemReport(ctx) } catch (t: Throwable) { "н/д\n" })
    if (checks.isNotEmpty()) {
        sb.append("\n--- проверки (мимо VPN) ---\n")
        checks.forEach { sb.append(if (it.ok) "OK   " else "FAIL ").append(it.name).append(": ").append(it.detail).append('\n') }
    }
    sb.append("\n--- журнал ---\n")
    sb.append(try { mobile.Mobile.getJournalFull(4000) } catch (t: Throwable) { try { mobile.Mobile.getJournal(1500) } catch (t2: Throwable) { "" } })
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

putv "app/src/main/java/app/hydra/DiagnosticsScreen.kt" <<'HYDRA_EOF'
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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

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
    var wlRunning by remember { mutableStateOf(false) }
    var svcRunning by remember { mutableStateOf(false) }
    var svcText by remember { mutableStateOf<String?>(null) }
    var wlText by remember { mutableStateOf<String?>(null) }

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
        SettingRow(
            stringResource(R.string.diag_test_failover),
            stringResource(R.string.diag_test_failover_sub),
            onClick = { try { mobile.Mobile.testFailover() } catch (t: Throwable) { } }
        )
        SettingRow(stringResource(R.string.diag_errors), stringResource(R.string.diag_errors_sub), onClick = onErrors)
        SettingRow(stringResource(R.string.journal_title), onClick = onJournal)
        SettingRow(
            stringResource(R.string.diag_svc),
            stringResource(R.string.diag_svc_sub),
            value = if (svcRunning) "…" else null,
            onClick = {
                if (!svcRunning) {
                    svcRunning = true
                    scope.launch {
                        svcText = withContext(Dispatchers.IO) { try { mobile.Mobile.serviceCheck() } catch (e: Throwable) { "н/д" } }
                        svcRunning = false
                    }
                }
            }
        )
        SettingRow(
            stringResource(R.string.diag_wl),
            stringResource(R.string.diag_wl_sub),
            value = if (wlRunning) "…" else null,
            onClick = {
                if (!wlRunning) {
                    wlRunning = true
                    scope.launch {
                        val t = withContext(Dispatchers.IO) { try { mobile.Mobile.whitelistCheck() } catch (e: Throwable) { "н/д" } }
                        try { mobile.Mobile.logLine("🔎 проверка белых списков:\n" + t) } catch (e: Throwable) { }
                        wlText = t
                        wlRunning = false
                    }
                }
            }
        )
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
    wlText?.let { t ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { wlText = null },
            title = { Text(stringResource(R.string.diag_wl)) },
            text = {
                SelectionContainer {
                    Text(t, fontFamily = FontFamily.Monospace, fontSize = 11.sp, lineHeight = 15.sp,
                        modifier = Modifier.verticalScroll(androidx.compose.foundation.rememberScrollState()))
                }
            },
            confirmButton = { androidx.compose.material3.TextButton(onClick = { wlText = null }) { Text(stringResource(R.string.btn_ok)) } }
        )
    }
    svcText?.let { t ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { svcText = null },
            title = { Text(stringResource(R.string.diag_svc)) },
            text = {
                SelectionContainer {
                    Text(t, fontFamily = FontFamily.Monospace, fontSize = 11.sp, lineHeight = 15.sp,
                        modifier = Modifier.verticalScroll(androidx.compose.foundation.rememberScrollState()))
                }
            },
            confirmButton = { androidx.compose.material3.TextButton(onClick = { svcText = null }) { Text(stringResource(R.string.btn_ok)) } }
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

putv "app/src/main/java/app/hydra/Doctor.kt" <<'HYDRA_EOF'
package app.hydra

import android.content.Context
import android.os.PowerManager
import android.provider.Settings

/** Одна найденная проблема: что видно, почему так, что сделать человеку и что чинить в коде. */
data class Finding(
    val id: String,
    val level: Int, // 3 — критично, 2 — важно, 1 — замечание
    val title: String,
    val seen: String,
    val why: String,
    val fix: String,
    val dev: String
)

private fun validEndpoint(s: String): Boolean {
    val t = s.trim()
    if (t.startsWith("[")) return true
    val parts = t.split(":")
    if (parts.size > 2) return t.contains("::")
    val ip = parts[0].split(".")
    if (ip.size != 4) return false
    for (o in ip) {
        val n = o.toIntOrNull() ?: return false
        if (n !in 0..255) return false
    }
    if (parts.size == 2) {
        val p = parts[1].toIntOrNull() ?: return false
        if (p !in 1..65535) return false
    }
    return true
}

/** Строки с ✘ из последней проверки сервисов через туннель (если её запускали). */
private fun lastServiceFailures(journal: String): List<String>? {
    val i = journal.lastIndexOf("проверка сервисов через туннель")
    if (i < 0) return null
    val block = journal.substring(i).lines().take(30)
    val end = block.indexOfFirst { it.contains("Доступно") }
    val part = if (end >= 0) block.take(end) else block.take(15)
    val fails = part.filter { it.contains("✘") }.map { it.trim() }
    val tg = fails.filter { it.contains("Telegram DC") }
    // один недоступный дата-центр Telegram из четырёх — не проблема: клиенту хватает остальных
    return if (tg.size < 4) fails.filterNot { it.contains("Telegram DC") } else fails
}

private fun operatorName(code: String): String = when (code) {
    "25001" -> "МТС"
    "25002" -> "МегаФон"
    "25020" -> "Tele2"
    "25099" -> "Билайн"
    "25011" -> "Yota"
    "25035" -> "МОТИВ"
    "" -> "нет данных"
    else -> "оператор $code"
}

/** Раздел «профиль сети»: какая сеть сейчас, кто оператор и что Гидра успела о ней узнать. */
private fun networkProfile(ctx: Context, checks: List<DiagCheck>, engine: String): String {
    val sb = StringBuilder()
    sb.append("\n--- профиль сети ---\n")
    sb.append("Тип сети сейчас: ").append(networkType(ctx)).append('\n')
    try {
        val tm = ctx.getSystemService(Context.TELEPHONY_SERVICE) as android.telephony.TelephonyManager
        val net = tm.networkOperator.orEmpty()
        val sim = tm.simOperator.orEmpty()
        sb.append("Оператор сети: ").append(operatorName(net)).append(" (").append(net).append(")\n")
        sb.append("Оператор SIM: ").append(operatorName(sim)).append(" (").append(sim).append(")\n")
    } catch (t: Throwable) {
        sb.append("Оператор: не определён\n")
    }
    val prov = checks.lastOrNull { it.name.startsWith("Провайдер сети") }
    if (prov != null) sb.append("Провайдер по публичному IP: ").append(prov.detail).append('\n')
    val brain = engine.substringAfter("🧠 что Гидра знает", "")
    if (brain.isNotEmpty()) {
        sb.append("Что Гидра знает об этой сети (сервисы по стратегиям, плохие дата-центры):\n")
        sb.append("🧠 что Гидра знает").append(brain)
        if (!brain.endsWith("\n")) sb.append('\n')
    } else {
        sb.append("Что Гидра знает об этой сети: данных пока нет (нужно подключение и несколько секунд).\n")
    }
    return sb.toString()
}

fun diagnose(
    ctx: Context, prefs: Prefs, vpn: VpnController,
    checks: List<DiagCheck>, engine: String, journal: String
): List<Finding> {
    val out = mutableListOf<Finding>()
    fun add(id: String, level: Int, title: String, seen: String, why: String, fix: String, dev: String) {
        out += Finding(id, level, title, seen, why, fix, dev)
    }

    // ---- проверки мимо VPN ----
    val dns = checks.getOrNull(0)
    val https = checks.getOrNull(1)
    val api = checks.getOrNull(2)
    val web = checks.getOrNull(5)
    if (dns != null && !dns.ok) {
        add("D01", 3, "Не работает DNS",
            "проверка DNS: ${dns.detail}",
            "Телефон не может превратить имя сайта в адрес. Сети нет, либо DNS провайдера не отвечает.",
            "1) Выключи и включи Wi-Fi или мобильную сеть. 2) Попробуй другую сеть. 3) Нажми «Диагностика» ещё раз.",
            "Diagnostics.kt: runDiagnostics (InetAddress.getByName); dns.go: SetSystemDNS")
    } else if (https != null && !https.ok) {
        add("D02", 3, "Нет HTTPS до Cloudflare",
            "DNS работает, а HTTPS к cloudflare.com не проходит: ${https.detail}",
            "Провайдер или сеть режут соединения к Cloudflare. Это бывает при «белых списках».",
            "Подключись к другой сети (Wi-Fi вместо мобильной или наоборот) и повтори диагностику.",
            "mobile/netalive.go: realNetState/classify; learn.go: sniPool (российские имена)")
    }
    if (api != null && !api.ok) {
        add("D03", 2, "Не открывается сервер регистрации WARP",
            "api.cloudflareclient.com:443: ${api.detail}",
            "Без него нельзя получить или обновить ключи WARP. Уже подключённый туннель при этом может работать.",
            "Если ключей ещё нет: подключись по другой сети, зарегистрируйся, потом возвращайся. Если есть, ничего делать не нужно.",
            "register.go: гонка маршрутов регистрации (api.devices.cloudflare.com запасной)")
    }
    if (web != null && !web.ok && dns?.ok == true && https?.ok == true) {
        add("D04", 1, "Обычный сайт (google.com) не открывается напрямую",
            "tcp www.google.com:443: ${web.detail}",
            "Прямой доступ к Google закрыт у этой сети. Для VPN это нормально, важно, что он открывается через туннель.",
            "Ничего, если через включённый VPN сайты открываются.",
            "Diagnostics.kt: runFullDiagnostics")
    }

    // ---- состояние туннеля ----
    val st = vpn.state
    if (st == "failed") {
        add("D10", 3, "Туннель не поднимается",
            "состояние: failed. ${vpn.message}",
            "Все стратегии из списка не сработали в этой сети.",
            "1) Подожди 1–2 минуты: Гидра пробует новые варианты сама. 2) Если не помогло, смени сеть. 3) Отправь этот отчёт целиком.",
            "engine.go: Run/runStrategy; learn.go: мутации; memory.go: Rank")
    } else if (st == "reconnecting") {
        add("D11", 2, "Туннель переподключается",
            "состояние: reconnecting. ${vpn.message}",
            "Связь пропала, Гидра ищет другой путь.",
            "Подожди минуту. Если так повторяется часто, отправь отчёт.",
            "engine.go: noteLoss; race.go: горячий резерв")
    }
    if (st == "up" && vpn.rttMs > 700) {
        add("D12", 2, "Очень большая задержка",
            "задержка ${vpn.rttMs} мс (норма до 400)",
            "Путь до дата-центра плохой или канал перегружен.",
            "Попробуй другой дата-центр: Дополнительно → Дата-центры → разрешить HEL, FRA, AMS.",
            "colo.go; engine.go: политика дата-центров")
    }
    val blocked = prefs.blockedColos.split(",").map { it.trim().uppercase() }.filter { it.isNotEmpty() }
    if (st == "up" && vpn.colo.isNotEmpty() && blocked.contains(vpn.colo.uppercase())) {
        add("D13", 2, "Подключились к запрещённому дата-центру",
            "дата-центр ${vpn.colo} есть в списке запрещённых",
            "Включена настройка «всё равно подключаться», когда других нет.",
            "Если нужно строго без этого дата-центра: Дополнительно → отключи «подключаться к любому».",
            "mobile/policy.go: SetFallback; gate.go: coloAllowed")
    }

    // ---- настройки, которые ломают работу ----
    if (prefs.splitOnlySelected && prefs.splitApps.isEmpty()) {
        add("D20", 3, "VPN включён, но ни одно приложение не пускается в туннель",
            "режим «только выбранные приложения», выбрано 0",
            "Весь трафик идёт мимо VPN, поэтому кажется, что VPN «не работает».",
            "Меню → Приложения: отметь нужные (Telegram, YouTube, WhatsApp) или выключи режим «только выбранные».",
            "AppsScreen.kt; HydraVpnService.kt (addAllowedApplication)")
    }
    if (!prefs.parallel) {
        add("D21", 2, "Выключен горячий резерв и гонка стратегий",
            "параллельный режим: выкл",
            "Стратегии пробуются по одной, а при обрыве связь пропадает на время переподключения.",
            "Включи параллельный режим в «Дополнительно».",
            "mobile/policy.go: SetParallel; race.go")
    }
    if (!prefs.autoStart) {
        add("D22", 1, "Нет автозапуска после перезагрузки",
            "автозапуск: выкл",
            "После перезагрузки телефона VPN сам не включится («включил и забыл» не работает).",
            "Дополнительно → Постоянная работа → включи автозапуск.",
            "BootReceiver.kt")
    }
    if (prefs.customEndpoint.isNotBlank() && !validEndpoint(prefs.customEndpoint)) {
        add("D23", 2, "Свой адрес сервера записан неверно",
            "значение: «${prefs.customEndpoint}»",
            "Нужен IP или IP:порт, например 162.159.198.2 или 162.159.198.2:443. Имя сайта не подойдёт.",
            "Дополнительно → Свой адрес сервера → введи IP или нажми «Сбросить».",
            "mobile/vpn_usque.go (currentCustom); custom.go: CustomEndpointStrategies")
    }
    if (prefs.customDnsOn && prefs.customDns.isBlank()) {
        add("D24", 1, "Свой DNS включён, но сервер не указан",
            "customDnsOn=true, customDns пусто",
            "Используется DNS по умолчанию, настройка ничего не меняет.",
            "Параметры DNS → укажи сервер (например 1.1.1.1) или выключи переключатель.",
            "AdvancedScreens.kt: DnsScreen; AccountController.kt: dnsProvider")
    }
    try {
        val mode = Settings.Global.getString(ctx.contentResolver, "private_dns_mode")
        if (mode == "hostname") {
            add("D25", 2, "В Android включён строгий частный DNS",
                "private_dns_mode=hostname (${Settings.Global.getString(ctx.contentResolver, "private_dns_specifier") ?: ""})",
                "Строгий частный DNS (DoT) часто не работает через VPN: сайты и Telegram не открываются.",
                "Настройки Android → Подключение → Частный DNS → «Автоматически» или «Отключено».",
                "HomeScreen.kt (предупреждение); HydraVpnService.kt")
        }
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!pm.isIgnoringBatteryOptimizations(ctx.packageName)) {
            add("D26", 2, "Система может убить VPN в фоне",
                "приложение не исключено из оптимизации батареи",
                "Xiaomi/HyperOS агрессивно закрывает фоновые приложения, и VPN отваливается.",
                "Дополнительно → «Разрешить работу в фоне», затем «Автозапуск (Xiaomi)».",
                "SystemInfo.kt; BootReceiver.kt")
        }
    } catch (t: Throwable) { }

    if (System.currentTimeMillis() < 1735689600000L) { // раньше 2025-01-01
        add("D27", 3, "Часы устройства показывают неверную дату",
            "дата на устройстве: " + java.util.Date(),
            "С неверной датой сертификаты сайтов считаются недействительными: регистрация WARP и подключение не работают. Часто бывает на ТВ-приставках без батарейки часов.",
            "Настройки → Дата и время → включить «Автоматически» (по сети) или выставить дату вручную.",
            "clock.go: learnClockSkew (ядро умеет подстроиться само); register.go: dialTLS")
    }
    // ---- по журналу и движку ----
    val lost = Regex("потерь без резерва: (\\d+)").find(engine)?.groupValues?.get(1)?.toIntOrNull() ?: 0
    if (lost > 0) {
        add("D30", 2, "Были обрывы без резерва",
            "потерь без резерва: $lost",
            "В момент обрыва не было готового запасного туннеля.",
            "Включи параллельный режим и протокол «Авто». Если уже включены, отправь отчёт.",
            "engine.go: noteLoss; race.go: горячий резерв")
    }
    if (engine.contains("состояние сети: whitelist")) {
        add("D31", 3, "Сеть в режиме «белых списков»",
            "доступны только российские адреса, зарубежные закрыты",
            "Оператор ограничил интернет списком разрешённых сайтов. Обычный WARP в этом режиме недоступен.",
            "Переключись на Wi-Fi или подожди: Гидра сама пробует имена из белых списков (SNI) и вернётся, когда режим снимут.",
            "mobile/netalive.go: realWLScan/WhitelistCheck; learn.go: sniPool")
    } else if (engine.contains("состояние сети: dead")) {
        add("D32", 3, "Нет интернета вообще",
            "ни зарубежные, ни российские адреса не отвечают",
            "Нет сигнала сети, режим «в самолёте» или сеть отключена.",
            "Проверь сигнал и режим «в самолёте», переключи сеть.",
            "mobile/netalive.go: classify")
    }
    if (journal.contains("Telegram не доходит")) {
        add("D33", 2, "Telegram не доходит через выбранный дата-центр",
            "в журнале: «Telegram не доходит через дата-центр …»",
            "Интернет работает, а сервера Telegram режутся на этом маршруте.",
            "Гидра ищет другой дата-центр сама. Можно ускорить: Дополнительно → Дата-центры → разрешить только HEL, FRA, AMS.",
            "gate.go: serviceGate/noteBadColo")
    }
    val hs = journal.lines().takeLast(400).count { it.contains("TLS handshake failure") }
    if (hs >= 5) {
        add("D34", 1, "Много отказов TLS при рукопожатии",
            "$hs строк «TLS handshake failure» в свежем журнале",
            "Пробуются адреса, которые не являются серверами MASQUE (адреса WireGuard).",
            "Ничего делать не нужно, если туннель в итоге поднялся. Иначе отправь отчёт.",
            "strategies.go: MasqueStrategies (список адресов); learn.go: генерация адресов")
    }
    val svc = lastServiceFailures(journal)
    if (svc == null && st == "up") {
        add("D40", 1, "Проверка сервисов через туннель ещё не запускалась",
            "в журнале нет результата проверки",
            "Без неё неизвестно, доходят ли YouTube, WhatsApp и Telegram.",
            "Диагностика → «Проверить сервисы» (при включённом VPN), затем снова собери отчёт.",
            "services.go: ServiceCheck; DiagnosticsScreen.kt")
    } else if (svc != null && svc.isNotEmpty()) {
        add("D41", 2, "Часть сервисов не доходит через туннель",
            svc.joinToString("\n         "),
            "Туннель есть, но до этих адресов TCP не проходит. Если не отвечают только они, их режут по маршруту или адресу.",
            "Гидра подбирает другой дата-центр и стратегию сама. Если не прошло за 5 минут, отправь отчёт.",
            "services.go; gate.go; learn.go (адаптация под сервис — план v22.2)")
    }
    val dnsBlocked = journal.lines().lastOrNull { it.contains("DNS оператора не отдаёт адрес") }
    if (dnsBlocked != null) {
        add("D44", 1, "Оператор блокирует часть имён на своём DNS",
            dnsBlocked.trim().take(220),
            "Обычный DNS оператора не отдаёт адрес сервиса. Внутри VPN приложения спрашивают DNS туннеля (1.1.1.1), поэтому им это не мешает.",
            "Ничего делать не нужно, пока приложение выбрано в Гидре. Вне VPN этот сервис не откроется.",
            "services.go: ServiceCheck; brain.go: resolveA")
    }
    return out
}

/** Раздел отчёта «ДИАГНОЗ»: читается первым, написан простым языком, у каждой проблемы есть шаги. */
fun buildDoctor(ctx: Context, prefs: Prefs, vpn: VpnController, checks: List<DiagCheck>): String {
    val engine = try { mobile.Mobile.diagnostics() } catch (t: Throwable) { "" }
    val journal = try { mobile.Mobile.getJournalFull(4000) } catch (t: Throwable) { "" }
    val list = diagnose(ctx, prefs, vpn, checks, engine, journal).sortedByDescending { it.level }
    val sb = StringBuilder()
    sb.append("\n=== ДИАГНОЗ (читать первым) ===\n")
    val crit = list.count { it.level >= 3 }
    if (list.isEmpty()) {
        sb.append("Итог: правила Доктора проблем не нашли.\n")
        sb.append("Если что-то всё равно не работает, опиши словами, что именно и в какой сети, и отправь этот отчёт.\n")
    } else {
        sb.append("Итог: найдено проблем ").append(list.size).append(", критичных ").append(crit).append(".\n")
        sb.append("Что делать: иди сверху вниз и выполняй пункт «Что сделать». Не помогло, отправь этот файл Claude целиком.\n\n")
        for (f in list) {
            val tag = when (f.level) { 3 -> "КРИТИЧНО"; 2 -> "ВАЖНО"; else -> "ЗАМЕЧАНИЕ" }
            sb.append('[').append(f.id).append("] ").append(tag).append(": ").append(f.title).append('\n')
            sb.append("  Что видно:     ").append(f.seen).append('\n')
            sb.append("  Почему так:    ").append(f.why).append('\n')
            sb.append("  Что сделать:   ").append(f.fix).append('\n')
            sb.append("  Код (для Claude): ").append(f.dev).append("\n\n")
        }
    }
    sb.append(networkProfile(ctx, checks, engine))
    sb.append("--- реестр возможностей (честный статус) ---\n")
    sb.append("✔ Свой адрес сервера: добавляется первым в список стратегий.\n")
    sb.append("✔ Свой SNI: добавляется как дополнительные стратегии, остальные не пропадают.\n")
    sb.append("✔ Память по сетям: Wi-Fi различается отпечатком (шлюз + DNS), мобильная сеть кодом оператора.\n")
    sb.append("✔ Самообучение: мутации TTL, числа и размера фейков, SNI, портов, адресов; мёртвые отбрасываются.\n")
    sb.append("✔ Параллельная гонка стратегий и горячий резерв (включается настройкой).\n")
    sb.append("✔ Проверка Telegram, YouTube, WhatsApp, Instagram, Discord через туннель (достижимость адреса по TCP).\n")
    sb.append("✔ Проверка сервисов: Telegram (4 дата-центра), YouTube, видео YouTube, WhatsApp, Instagram, Discord через туннель. Адрес узнаётся DNS-запросом внутри туннеля, поэтому блокировка имён на DNS оператора не мешает.\n")
    sb.append("⚠ Настоящий HTTPS-запрос от приложения через свой туннель невозможен: Android не пускает приложение в собственный VPN. Поэтому проверка идёт на уровне TCP.\n")
    sb.append("⚠ Скорость туннеля отдельно не измеряется (нужен свой TCP в ядре): видны задержка и потери.\n")
    sb.append("⚠ Сеть из-за YouTube или WhatsApp не меняется: запрет дата-центров без запасных оставил бы VPN без выхода. Сбой запоминается, и Гидра придумывает новые варианты. Меняется путь только при сбое Telegram.\n")
    sb.append("⚠ Свой DNS: обычный DNS внутри туннеля. DoH и DoT не поддерживаются.\n")
    sb.append("✘ Системный частный DNS не настраивается приложением, только определяется.\n")
    sb.append("✔ Память сервисов по сетям: какие из Telegram, YouTube, WhatsApp доходили через какую стратегию. Она влияет на порядок перебора, а при сбое сервиса Гидра сама придумывает новые варианты.\n")
    sb.append("⚠ Знания об ограничениях операторов не вшиты: Гидра выучивает их сама по каждой сети (оператор SIM или Wi-Fi). Заранее известных «правил МТС/Билайна» нет, и выдумывать их я не буду.\n")
    sb.append("=== конец диагноза ===\n")
    return sb.toString()
}
HYDRA_EOF

putv "app/src/main/java/app/hydra/HomeScreen.kt" <<'HYDRA_EOF'
package app.hydra

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.provider.Settings
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
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
    var wlText by remember { mutableStateOf<String?>(null) }
    var wlRelay by remember { mutableStateOf(false) }
    var wlBusy by remember { mutableStateOf(false) }
    val whitelist = vpn.message.startsWith("🛑")

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
        whitelist -> stringResource(R.string.wl_sub)
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
        // режим белых списков: оператор пропускает только российские сайты
        if (whitelist) {
            Spacer(Modifier.height(16.dp))
            HCard {
                Text(stringResource(R.string.wl_title), fontWeight = FontWeight.SemiBold, color = NeonAmber)
                Text(
                    stringResource(R.string.wl_text),
                    style = MaterialTheme.typography.bodySmall,
                    color = scheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 4.dp, bottom = 8.dp)
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(
                        onClick = {
                            if (!wlBusy) {
                                wlBusy = true
                                scope.launch {
                                    val t = withContext(Dispatchers.IO) { try { mobile.Mobile.whitelistCheck() } catch (e: Throwable) { "н/д" } }
                                    try { mobile.Mobile.logLine("🔎 проверка белых списков:\n" + t) } catch (e: Throwable) { }
                                    wlText = t
                                    wlBusy = false
                                }
                            }
                        },
                        modifier = Modifier.weight(1f)
                    ) { Text(if (wlBusy) "…" else stringResource(R.string.wl_check)) }
                    OutlinedButton(onClick = { wlRelay = true }, modifier = Modifier.weight(1f)) {
                        Text(stringResource(R.string.wl_relay))
                    }
                }
            }
        }
        // строгий частный DNS (DoT) часто не работает через VPN: из-за него не открываются сайты и Telegram
        val pdnsHost = try {
            if (Settings.Global.getString(ctx.contentResolver, "private_dns_mode") == "hostname")
                Settings.Global.getString(ctx.contentResolver, "private_dns_specifier") ?: "" else ""
        } catch (t: Throwable) { "" }
        if (pdnsHost.isNotEmpty()) {
            Spacer(Modifier.height(16.dp))
            HCard {
                Text(stringResource(R.string.pdns_title), fontWeight = FontWeight.SemiBold, color = NeonAmber)
                Text(
                    stringResource(R.string.pdns_text, pdnsHost),
                    style = MaterialTheme.typography.bodySmall,
                    color = scheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 4.dp, bottom = 8.dp)
                )
                OutlinedButton(onClick = {
                    try { ctx.startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS)) } catch (t: Throwable) { }
                }) { Text(stringResource(R.string.pdns_open)) }
            }
        }
        Spacer(Modifier.weight(3.2f))
    }
    wlText?.let { t ->
        AlertDialog(
            onDismissRequest = { wlText = null },
            title = { Text(stringResource(R.string.wl_title)) },
            text = { Text(t, fontSize = 12.sp, lineHeight = 16.sp, modifier = Modifier.verticalScroll(androidx.compose.foundation.rememberScrollState())) },
            confirmButton = { TextButton(onClick = { wlText = null }) { Text(stringResource(R.string.btn_ok)) } }
        )
    }
    if (wlRelay) {
        AlertDialog(
            onDismissRequest = { wlRelay = false },
            title = { Text(stringResource(R.string.wl_relay_title)) },
            text = { Text(stringResource(R.string.wl_relay_text), fontSize = 13.sp, lineHeight = 18.sp, modifier = Modifier.verticalScroll(androidx.compose.foundation.rememberScrollState())) },
            confirmButton = { TextButton(onClick = { wlRelay = false }) { Text(stringResource(R.string.btn_ok)) } }
        )
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

putv "app/src/main/java/app/hydra/HydraApp.kt" <<'HYDRA_EOF'
package app.hydra

import android.app.Application
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter

/**
 * Запоминает причину вылета приложения. На приставках Android TV нет ни отладки, ни привычных способов снять журнал,
 * поэтому текст ошибки пишется в файл: в отчёт («последний вылет приложения») и в папку приложения
 * Android/data/<пакет>/files/hydra_crash.txt, которую открывает любой файловый менеджер.
 */
class HydraApp : Application() {
    override fun onCreate() {
        super.onCreate()
        val old = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            try {
                val sw = StringWriter()
                e.printStackTrace(PrintWriter(sw))
                val text = "Hydra: вылет " + java.util.Date() + " (поток " + t.name + ")\n" +
                    "устройство: " + android.os.Build.MANUFACTURER + " " + android.os.Build.MODEL +
                    ", Android " + android.os.Build.VERSION.RELEASE + " (API " + android.os.Build.VERSION.SDK_INT + ")" +
                    ", ABI " + android.os.Build.SUPPORTED_ABIS.joinToString(",") + "\n\n" + sw.toString()
                File(filesDir, "last_crash.txt").writeText(text)
                getExternalFilesDir(null)?.let { File(it, "hydra_crash.txt").writeText(text) }
            } catch (x: Throwable) {
            }
            old?.uncaughtException(t, e)
        }
    }
}
HYDRA_EOF

putv "app/src/main/java/app/hydra/HydraHero.kt" <<'HYDRA_EOF'
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

putv "app/src/main/java/app/hydra/HydraVpnService.kt" <<'HYDRA_EOF'
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
import android.os.ParcelFileDescriptor
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

    /** TUN живёт в службе: при перезапуске ядра интерфейс не пропадает, и трафик не уходит мимо VPN. */
    private var tunPfd: ParcelFileDescriptor? = null
    private var restartFails = 0
    private var nextRestartAt = 0L

    private fun closeTun() {
        try { tunPfd?.close() } catch (t: Throwable) { }
        tunPfd = null
    }

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
            .setContentTitle(getString(R.string.app_name))
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
                if (raw.startsWith("up")) restartFails = 0
                // Wi-Fi ведёт в запрещённый дата-центр: туннель автоматически идёт через мобильную сеть
                val prefsNow = Prefs(this@HydraVpnService)
                if (p.getOrElse(4) { "" }.startsWith("⛔") && prefsNow.channel == "auto" && !forceCell) {
                    val wp = curWifiPrint()
                    if (wp.isNotEmpty() && hasCellNet()) {
                        enableAutoCell(wp)
                        return
                    }
                }
                val now = System.currentTimeMillis()
                if (raw.startsWith("off") && Prefs(this@HydraVpnService).wantConnected && now >= nextRestartAt) {
                    restartFails++
                    nextRestartAt = now + minOf(60_000L, 3_000L shl minOf(restartFails, 5))
                    jlog("служба: ядро остановлено — поднимаю заново (попытка $restartFails)")
                    startVpn()
                }
            } catch (t: Throwable) {
            }
            handler.postDelayed(this, 3000)
        }
    }

    private fun cm() = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager

    /** Отпечаток текущего Wi-Fi или "" (если Wi-Fi нет). */
    private fun curWifiPrint(): String = try {
        var r = ""
        for (n in cm().allNetworks) {
            val c = cm().getNetworkCapabilities(n) ?: continue
            if (c.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
            if (c.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) r = wifiPrint(n)
        }
        r
    } catch (t: Throwable) { "" }

    private fun hasCellNet(): Boolean = try {
        cm().allNetworks.any {
            val c = cm().getNetworkCapabilities(it)
            c != null && !c.hasTransport(NetworkCapabilities.TRANSPORT_VPN) && c.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)
        }
    } catch (t: Throwable) { false }

    private fun enableAutoCell(wp: String) {
        Prefs(this).addCellWifi(wp)
        jlog("📡 Этот Wi-Fi ведёт в запрещённый дата-центр: туннель переключается на мобильную сеть (на 12 часов для этого Wi-Fi)")
        handler.removeCallbacks(statusUpdater)
        try { mobile.Mobile.stopTunnel() } catch (t: Throwable) { }
        closeTun()
        handler.postDelayed({ startVpn() }, 1200)
    }

    private fun startVpn() {
        val running = try { !mobile.Mobile.engineStatus().startsWith("off") } catch (t: Throwable) { false }
        if (running) return

        handler.removeCallbacks(statusUpdater)
        handler.postDelayed(statusUpdater, 3000)
        val prefs = Prefs(this)
        prefs.migrate()
        forceCell = prefs.channel == "cell" || (prefs.channel == "auto" && prefs.cellWifiActive(curWifiPrint()))
        try {
            mobile.Mobile.setColoPolicy(prefs.blockedColos, prefs.allowColos)
            mobile.Mobile.setFallback(prefs.fallbackAny)
            mobile.Mobile.setProtocol(prefs.protocol)
            mobile.Mobile.setCustomSNI(prefs.customSni)
            mobile.Mobile.setParallel(if (prefs.parallel) 3L else 1L)
            mobile.Mobile.setIPv6(prefs.ipv6)
            mobile.Mobile.setServiceGate(prefs.tgGate)
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
            // аккаунта ещё нет (приложение само пробует зарегистрироваться): ждём и повторяем, VPN не бросаем
            jlog("служба: нет аккаунта WARP — повторю позже")
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
        if (v6.isNotEmpty() && prefs.ipv6) {
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

        val pfd = tunPfd ?: (try { b.establish() } catch (e: Exception) { null })
        if (pfd == null) {
            Log.e(TAG, "не удалось создать TUN")
            jlog("служба: не удалось создать TUN (нет разрешения VPN?) — остановка")
            stopVpn()
            return
        }
        tunPfd = pfd
        // ядру отдаём копию дескриптора: когда оно закроет её, сам интерфейс остаётся у службы
        val coreFd = try { ParcelFileDescriptor.dup(pfd.fileDescriptor) } catch (e: Exception) { null }
        if (coreFd == null) {
            jlog("служба: не удалось продублировать TUN — пересоздаю")
            closeTun()
            return
        }
        val err = try {
            mobile.Mobile.startTunnel(dir, coreFd.detachFd().toLong())
        } catch (t: Throwable) {
            t.message ?: "ошибка ядра"
        }
        if (err.isNotEmpty()) {
            Log.e(TAG, err)
            jlog("служба: ядро не запустилось: $err — повторю")
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
        closeTun()
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
        closeTun()
        super.onDestroy()
    }
}
HYDRA_EOF

putv "app/src/main/java/app/hydra/MainActivity.kt" <<'HYDRA_EOF'
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
        prefs.migrate()
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

putv "app/src/main/java/app/hydra/Prefs.kt" <<'HYDRA_EOF'
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

    /** IPv6 через туннель (по умолчанию выключен: приложения сразу идут по IPv4). */
    var ipv6: Boolean
        get() = sp.getBoolean("ipv6", false)
        set(v) { sp.edit().putBoolean("ipv6", v).apply() }

    /** После подключения проверять Telegram; негодные дата-центры обходятся. */
    var tgGate: Boolean
        get() = sp.getBoolean("tg_gate", true)
        set(v) { sp.edit().putBoolean("tg_gate", v).apply() }

    /** Wi-Fi, который ведёт в запрещённый дата-центр: туннель идёт через мобильную сеть (12 часов). */
    fun cellWifiActive(print: String): Boolean {
        if (print.isEmpty()) return false
        val now = System.currentTimeMillis()
        return (sp.getString("cell_wifi", "") ?: "").split(";").any {
            val p = it.split("@")
            p.size == 2 && p[0] == print && now - (p[1].toLongOrNull() ?: 0L) < 12L * 3600_000L
        }
    }

    fun addCellWifi(print: String) {
        val cur = (sp.getString("cell_wifi", "") ?: "").split(";").filter { it.isNotEmpty() && !it.startsWith("$print@") }
        sp.edit().putString("cell_wifi", (cur + "$print@${System.currentTimeMillis()}").joinToString(";")).apply()
    }

    /** Параллельная гонка стратегий и горячий резерв. */
    var parallel: Boolean
        get() = sp.getBoolean("parallel", true)
        set(v) { sp.edit().putBoolean("parallel", v).apply() }

    /** Однократная миграция: прежнее умолчание «DME,LED,SVX,…» заменяется на «DME». */
    fun migrate() {
        if (sp.getInt("defaults_ver", 0) < 2) {
            val cur = sp.getString("colo_block", null)
            if (cur != null && cur.replace(" ", "").startsWith("DME,LED")) sp.edit().remove("colo_block").apply()
            sp.edit().putInt("defaults_ver", 2).apply()
        }
    }

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

putv "app/src/main/java/app/hydra/SystemInfo.kt" <<'HYDRA_EOF'
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
    line("архитектура процессора (ABI)", Build.SUPPORTED_ABIS.joinToString(", "))
    line("экран", safe {
        "сенсорный=" + ctx.packageManager.hasSystemFeature("android.hardware.touchscreen") +
            ", телевизор (leanback)=" + ctx.packageManager.hasSystemFeature("android.software.leanback")
    })
    val crash = safe { java.io.File(ctx.filesDir, "last_crash.txt").takeIf { it.exists() }?.readText()?.take(3000) ?: "" }
    if (crash.isNotEmpty()) line("последний вылет приложения", "\n" + crash)
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

putv "app/src/main/java/app/hydra/Theme.kt" <<'HYDRA_EOF'
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

putv "app/src/main/java/app/hydra/Ui.kt" <<'HYDRA_EOF'
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

putv "app/src/main/java/app/hydra/VpnController.kt" <<'HYDRA_EOF'
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

putb "app/src/main/res/drawable-nodpi/hero_hydra.webp" <<'HYDRA_EOF'
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
EYZIVzAlcTFkCjcw4kjtDUgSR0a+AAAA
HYDRA_EOF

putb "app/src/main/res/drawable-nodpi/ic_launcher_art.webp" <<'HYDRA_EOF'
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
czxcnCCtVOxRBWOvabGZrBVMcAY1Ytdf8zmAAAA=
HYDRA_EOF

putb "app/src/main/res/drawable-nodpi/ic_warp_bg.webp" <<'HYDRA_EOF'
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
HYDRA_EOF

putb "app/src/main/res/drawable-nodpi/ic_warp_fg.webp" <<'HYDRA_EOF'
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
HYDRA_EOF

putb "app/src/main/res/drawable-xhdpi/tv_banner.png" <<'HYDRA_EOF'
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
HYDRA_EOF

putv "app/src/main/res/drawable/ic_hydra_mark.xml" <<'HYDRA_EOF'
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

putv "app/src/main/res/drawable/ic_launcher_background.xml" <<'HYDRA_EOF'
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

putv "app/src/main/res/drawable/ic_launcher_foreground.xml" <<'HYDRA_EOF'
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

putv "app/src/main/res/drawable/ic_launcher_monochrome.xml" <<'HYDRA_EOF'
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

putv "app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml" <<'HYDRA_EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_warp_bg" />
    <foreground android:drawable="@drawable/ic_warp_fg" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
HYDRA_EOF

putv "app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml" <<'HYDRA_EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_warp_bg" />
    <foreground android:drawable="@drawable/ic_warp_fg" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
HYDRA_EOF

putv "app/src/main/res/values-ru/strings.xml" <<'HYDRA_EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">WARP CLAUDE</string>

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
    <string name="diag_test_failover">Проверить горячий резерв</string>
    <string name="diag_test_failover_sub">Имитирует отказ основного туннеля: смотрите результат в журнале (🧪)</string>
    <string name="wl_title">Режим белых списков</string>
    <string name="wl_sub">Белые списки: Cloudflare недоступен, жду</string>
    <string name="wl_text">Оператор пропускает только российские сайты, поэтому Cloudflare WARP (как и любой зарубежный VPN) сейчас не подключается. Гидра сама проверяет сеть и подключится, когда ограничения снимут. Пока она пробует имена российских сайтов (SNI) и не портит память стратегий.</string>
    <string name="wl_check">Проверить сеть</string>
    <string name="wl_relay">Что можно сделать</string>
    <string name="wl_relay_title">Как обойти белые списки</string>
    <string name="wl_relay_text">Если оператор фильтрует по IP-адресам, поможет только ретранслятор: небольшая программа на сервере, чей адрес входит в белый список (российский хостинг или облако). Она просто пересылает UDP-пакеты к Cloudflare.\n\nНа сервере (Linux) одна команда:\nsocat UDP4-LISTEN:443,fork,reuseaddr UDP4:162.159.198.2:443\n\nВ приложении: Дополнительно → Польз. конечная точка → IP-адрес сервера:443.\n\nПодойдёт ли конкретный хостинг, зависит от оператора и региона: проверьте, открывается ли его адрес в режиме белых списков. Без собственного сервера обход возможен только если фильтр смотрит на имя сайта (SNI), а не на IP: Гидра проверяет это сама (кнопка «Проверить сеть»).</string>
    <string name="diag_wl">Проверка белых списков</string>
    <string name="diag_wl_sub">Какие адреса и имена доступны оператору сейчас</string>
    <string name="diag_svc">Проверка сервисов через туннель</string>
    <string name="diag_svc_sub">Telegram, Google, GitHub: проходит ли TCP через текущий туннель и дата-центр</string>
    <string name="pdns_title">Включён частный DNS</string>
    <string name="pdns_text">Строгий частный DNS (%1$s) часто не работает через VPN: из-за него могут не открываться сайты и Telegram. Выключите его или выберите «Автоматически»: Настройки → Подключение и общий доступ → Частный DNS.</string>
    <string name="pdns_open">Открыть настройки</string>
    <string name="adv_ipv6">IPv6 через туннель</string>
    <string name="adv_ipv6_sub">Выключено: приложения сразу идут по IPv4 (быстрее и без зависаний). Включите, если нужен ресурс только с IPv6.</string>
    <string name="adv_tg">Проверять Telegram после подключения</string>
    <string name="adv_tg_sub">Если интернет есть, а Telegram не доходит, Гидра сама выберет другой дата-центр.</string>
</resources>
HYDRA_EOF

putv "app/src/main/res/values/ic_colors.xml" <<'HYDRA_EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="hydra_icon_bg">#081F3F</color>
</resources>
HYDRA_EOF

putv "app/src/main/res/values/strings.xml" <<'HYDRA_EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">WARP CLAUDE</string>

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
    <string name="diag_test_failover">Test hot standby</string>
    <string name="diag_test_failover_sub">Simulates a primary tunnel failure: see the result in the journal (🧪)</string>
    <string name="wl_title">Whitelist mode</string>
    <string name="wl_sub">Whitelist mode: Cloudflare is unreachable, waiting</string>
    <string name="wl_text">The operator only lets Russian sites through, so Cloudflare WARP (like any foreign VPN) cannot connect right now. Hydra keeps checking and will connect when the limits are lifted. Meanwhile it tries Russian site names (SNI) and does not damage the strategy memory.</string>
    <string name="wl_check">Check network</string>
    <string name="wl_relay">What can be done</string>
    <string name="wl_relay_title">How to bypass whitelists</string>
    <string name="wl_relay_text">If the operator filters by IP address, only a relay helps: a small program on a server whose address is on the whitelist (a Russian host or cloud). It just forwards UDP packets to Cloudflare.\n\nOn the server (Linux), one command:\nsocat UDP4-LISTEN:443,fork,reuseaddr UDP4:162.159.198.2:443\n\nIn the app: Advanced → Custom endpoint → server IP:443.\n\nWhether a given host works depends on the operator and region: check that its address opens in whitelist mode. Without your own server a bypass is possible only if the filter looks at the site name (SNI) rather than the IP: Hydra checks this itself (the Check network button).</string>
    <string name="diag_wl">Whitelist check</string>
    <string name="diag_wl_sub">Which addresses and names the operator lets through now</string>
    <string name="diag_svc">Services through the tunnel</string>
    <string name="diag_svc_sub">Telegram, Google, GitHub: does TCP pass through the current tunnel and data center</string>
    <string name="pdns_title">Private DNS is on</string>
    <string name="pdns_text">Strict private DNS (%1$s) often does not work through a VPN: sites and Telegram may fail to open. Turn it off or choose Automatic: Settings → Connection and sharing → Private DNS.</string>
    <string name="pdns_open">Open settings</string>
    <string name="adv_ipv6">IPv6 through the tunnel</string>
    <string name="adv_ipv6_sub">Off: apps go straight over IPv4 (faster, no stalls). Turn on if you need an IPv6-only resource.</string>
    <string name="adv_tg">Check Telegram after connecting</string>
    <string name="adv_tg_sub">If the internet works but Telegram does not, Hydra picks another data center by itself.</string>
</resources>
HYDRA_EOF

putv "app/src/main/res/values/themes.xml" <<'HYDRA_EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="Theme.Hydra" parent="android:Theme.Material.NoActionBar">
        <item name="android:navigationBarColor">@android:color/black</item>
        <item name="android:statusBarColor">@android:color/black</item>
        <item name="android:windowBackground">@android:color/black</item>
    </style>
</resources>
HYDRA_EOF

putv "app/src/main/res/xml/file_paths.xml" <<'HYDRA_EOF'
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <cache-path name="reports" path="reports/" />
</paths>
HYDRA_EOF

putv "$GODIR/brain.go" <<'HYDRA_EOF'
package hydra

import (
	"context"
	"errors"
	"fmt"
	"net"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// «Мозг»: Гидра помнит не только «подключилось / нет», но и какие сервисы (Telegram, YouTube,
// WhatsApp) реально доходили через каждую стратегию в каждой сети. Эти данные влияют на порядок
// перебора и запускают придумывание новых вариантов, если сервис не дошёл.

const maxSvcEntries = 400

// RecordService запоминает, дошёл ли сервис svc через стратегию sid в сети nk.
func (m *Memory) RecordService(nk, sid, svc string, ok bool) {
	if m == nil {
		return
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.Svc == nil {
		m.Svc = map[string]*stat{}
	}
	key := nk + "|" + sid + "|" + svc
	s := m.Svc[key]
	if s == nil {
		s = &stat{}
		m.Svc[key] = s
	}
	if ok {
		s.OK++
		s.LastOK = time.Now()
	} else {
		s.Fail++
		s.LastFail = time.Now()
	}
	if s.OK+s.Fail > 12 { // забываем старое: сети и блокировки меняются
		s.OK /= 2
		s.Fail /= 2
	}
	if len(m.Svc) > maxSvcEntries {
		for k, v := range m.Svc {
			last := v.LastOK
			if v.LastFail.After(last) {
				last = v.LastFail
			}
			if time.Since(last) > 30*24*time.Hour {
				delete(m.Svc, k)
			}
		}
	}
	m.saveSoonLocked()
}

// svcBonusLocked — поправка к оценке стратегии по тому, как через неё доходили сервисы
// (от −0.15 до +0.15; нет данных — 0). Вызывать под m.mu.
func (m *Memory) svcBonusLocked(nk, sid string) float64 {
	if len(m.Svc) == 0 {
		return 0
	}
	prefix := nk + "|" + sid + "|"
	sum, n := 0.0, 0
	for k, st := range m.Svc {
		if !strings.HasPrefix(k, prefix) {
			continue
		}
		sum += float64(st.OK+1) / float64(st.OK+st.Fail+2)
		n++
	}
	if n == 0 {
		return 0
	}
	return (sum/float64(n) - 0.5) * 0.3
}

// ServiceMatrix — читаемая таблица «стратегия → сервисы» для этой сети (для отчёта).
func (m *Memory) ServiceMatrix(nk string) string {
	if m == nil {
		return "  нет памяти\n"
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	byS := map[string]map[string]*stat{}
	for k, st := range m.Svc {
		p := strings.SplitN(k, "|", 3)
		if len(p) != 3 || p[0] != nk {
			continue
		}
		if byS[p[1]] == nil {
			byS[p[1]] = map[string]*stat{}
		}
		byS[p[1]][p[2]] = st
	}
	if len(byS) == 0 {
		return "  пока нет данных: проверка сервисов идёт через несколько секунд после подключения\n"
	}
	ids := make([]string, 0, len(byS))
	for id := range byS {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	if len(ids) > 12 {
		ids = ids[:12]
	}
	var b strings.Builder
	for _, id := range ids {
		names := make([]string, 0, len(byS[id]))
		for n := range byS[id] {
			names = append(names, n)
		}
		sort.Strings(names)
		fmt.Fprintf(&b, "  %s:", id)
		for _, n := range names {
			st := byS[id][n]
			fmt.Fprintf(&b, " %s ✔%d/✘%d;", n, st.OK, st.Fail)
		}
		b.WriteString("\n")
	}
	return b.String()
}

// BadColoList — дата-центры, через которые в этой сети не дошёл Telegram (пока действует запрет).
func (e *Engine) BadColoList(nk string) []string {
	e.mu.Lock()
	defer e.mu.Unlock()
	var out []string
	for k, t := range e.badColo {
		if strings.HasPrefix(k, nk+"|") && time.Since(t) < badColoFor {
			out = append(out, strings.TrimPrefix(k, nk+"|"))
		}
	}
	sort.Strings(out)
	return out
}

var (
	svcGrowMu sync.Mutex
	svcGrowAt = map[string]time.Time{}
)

// svcGrow: сервис не дошёл — придумываем новые варианты под эту сеть (не чаще раза в 10 минут).
func (e *Engine) svcGrow(nk string) {
	svcGrowMu.Lock()
	if t, ok := svcGrowAt[nk]; ok && time.Since(t) < 10*time.Minute {
		svcGrowMu.Unlock()
		return
	}
	svcGrowAt[nk] = time.Now()
	svcGrowMu.Unlock()
	Logf("🧠 часть сервисов не дошла — придумываю новые варианты под сеть %s", nk)
	e.grow(nk)
}

// resolveA узнаёт IPv4-адрес имени запросом DNS ВНУТРИ туннеля (к 1.1.1.1). Оператор такой запрос не видит,
// поэтому подмена или блокировка имён на его DNS не мешает, как не мешает она и приложениям внутри VPN.
func (d *attemptDev) resolveA(ctx context.Context, host string, timeout time.Duration) (net.IP, error) {
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
	pkt := BuildDNSQueryA(e.cfg.LocalIP, d.port+1, id, host)
	if pkt == nil {
		return nil, errors.New("не удалось построить DNS-запрос")
	}
	select {
	case d.probeQ <- pkt:
	default:
		return nil, errors.New("очередь проб переполнена")
	}
	select {
	case res := <-ch:
		if ip := net.ParseIP(res); ip != nil {
			if ip4 := ip.To4(); ip4 != nil {
				return ip4, nil
			}
		}
		if res == "rcode=nxdomain" {
			return nil, errors.New("DNS через туннель: такого имени нет")
		}
		return nil, errors.New("DNS через туннель: " + res)
	case <-time.After(timeout):
		return nil, errors.New("DNS через туннель не ответил")
	case <-ctx.Done():
		return nil, ctx.Err()
	}
}

// ---------- обучение по классам стратегий ----------
// Результат одной стратегии говорит и о её «родне»: о других адресах того же варианта и о соседях по подсети.
// Если вариант j4 заработал на 162.159.192.3, то j4 на 162.159.192.4 надо пробовать сразу. Если десять адресов
// подряд не ответили на один вариант, одиннадцатый тоже не ответит: время тратится на другие.

type clsStat struct{ ok, fail int }

// stratKeys возвращает семейство ("wg"), вариант ("wg/j4") и подсеть адреса ("wg/162.159.192").
func stratKeys(id string) (fam, variant, subnet string) {
	parts := strings.Split(id, "/")
	fam = parts[0]
	if len(parts) < 3 {
		return
	}
	variant = fam + "/" + parts[len(parts)-1]
	host := parts[1]
	if i := strings.LastIndex(host, ":"); i > 0 && strings.Count(host, ":") == 1 {
		host = host[:i]
	}
	if p := strings.Split(host, "."); len(p) == 4 {
		subnet = fam + "/" + p[0] + "." + p[1] + "." + p[2]
	}
	return
}

// classAggLocked суммирует успехи и сбои по классам для сети net. Вызывать под m.mu.
func (m *Memory) classAggLocked(net string) map[string]*clsStat {
	agg := map[string]*clsStat{}
	add := func(k string, st *stat) {
		c := agg[k]
		if c == nil {
			c = &clsStat{}
			agg[k] = c
		}
		c.ok += st.OK
		c.fail += st.Fail
	}
	for id, st := range m.Nets[net] {
		fam, variant, subnet := stratKeys(id)
		add("f|"+fam, st)
		if variant != "" {
			add("v|"+variant, st)
		}
		if subnet != "" {
			add("s|"+subnet, st)
		}
	}
	return agg
}

// classAdj — поправка к оценке стратегии по опыту её класса (без учёта собственной статистики self).
func classAdj(agg map[string]*clsStat, id string, self *stat) float64 {
	fam, variant, subnet := stratKeys(id)
	adj := 0.0
	one := func(k string, wOK, wBad float64, minFail int) {
		c := agg[k]
		if c == nil {
			return
		}
		ok, fail := c.ok, c.fail
		if self != nil {
			ok -= self.OK
			fail -= self.Fail
		}
		if ok > 0 && ok*4 >= fail {
			adj += wOK
		} else if ok == 0 && fail >= minFail {
			adj -= wBad
		}
	}
	one("f|"+fam, 0, 0.15, 12)
	if variant != "" {
		one("v|"+variant, 0.2, 0.25, 6)
	}
	if subnet != "" {
		one("s|"+subnet, 0.2, 0.25, 4)
	}
	return adj
}

// netSeeds — что уже работало в конкретных сетях по отчётам пользователя от 2026-11-19. Это наблюдения, а не
// правила: реальные результаты в памяти важнее, а стратегия с тремя сбоями подряд теряет бонус.
var netSeeds = map[string][]string{
	// Билайн: MASQUE уходит в запрещённую Москву или молчит; WireGuard живёт на подсети 162.159.192.x
	"cell:25099": {
		"wg/162.159.192.4:2408/j4", "wg/162.159.192.3:2408/j4",
		"wg/162.159.192.4:2408/q3", "wg/162.159.192.4:2408/q3r",
		"wg/162.159.192.4:2408/v4", "wg/162.159.192.3:2408/v4",
	},
	// МТС: MASQUE через 162.159.198.x доходит до Хельсинки
	"cell:25001": {
		"h3/162.159.198.1/vk4x6", "h3/162.159.198.2/g3+speed",
		"h3/162.159.198.1/vk6x6", "h3/162.159.198.1/g3",
	},
}

func seedBonus(net, id string) float64 {
	for _, s := range netSeeds[net] {
		if s == id {
			return 0.35
		}
	}
	return 0
}

// prefix24 — ключ подсети /24 для адреса вида 162.159.192.3 (с портом или без): весь блок Cloudflare обычно
// маршрутизируется одинаково, поэтому если один адрес ведёт в запрещённый дата-центр, соседи ведут туда же.
func prefix24(host string) string {
	p := strings.Split(host, ".")
	if len(p) == 4 {
		return p[0] + "." + p[1] + "." + p[2] + ".*"
	}
	return host
}

// blockedFor — до какого времени запрещён адрес: по нему самому или по его подсети /24.
func blockedFor(blocked map[string]time.Time, host string) (time.Time, bool) {
	t1, ok1 := blocked[host]
	t2, ok2 := blocked[prefix24(host)]
	switch {
	case ok1 && ok2:
		if t2.After(t1) {
			return t2, true
		}
		return t1, true
	case ok1:
		return t1, true
	case ok2:
		return t2, true
	}
	return time.Time{}, false
}
HYDRA_EOF

putv "build.gradle.kts" <<'HYDRA_EOF'
plugins {
    id("com.android.application") version "8.7.3" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21" apply false
}
HYDRA_EOF

putv "$GODIR/clock.go" <<'HYDRA_EOF'
package hydra

import (
	"bufio"
	"context"
	"crypto/tls"
	"crypto/x509"
	_ "embed"
	"errors"
	"net"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// Корневые сертификаты, встроенные в приложение (набор Mozilla). На старых прошивках (приставки Android TV на
// Android 9) системное хранилище устарело и не знает новых корней, из-за чего регистрация WARP падает с
// «certificate signed by unknown authority». Встроенные корни только ДОБАВЛЯЮТСЯ к системным.
//
//go:embed roots.pem
var embeddedRoots []byte

var (
	rootsOnce sync.Once
	rootsPool *x509.CertPool
	clockSkew atomic.Int64 // разница «время сервера минус время устройства», нс
	skewDone  atomic.Bool
)

func rootPool() *x509.CertPool {
	rootsOnce.Do(func() {
		p, err := x509.SystemCertPool()
		if err != nil || p == nil {
			p = x509.NewCertPool()
		}
		p.AppendCertsFromPEM(embeddedRoots)
		rootsPool = p
	})
	return rootsPool
}

// tlsNow — время для проверки сертификатов с поправкой на неверные часы устройства.
func tlsNow() time.Time { return time.Now().Add(time.Duration(clockSkew.Load())) }

func isCertTimeError(err error) bool {
	var ci x509.CertificateInvalidError
	if errors.As(err, &ci) {
		return ci.Reason == x509.Expired
	}
	return strings.Contains(err.Error(), "expired or is not yet valid")
}

// learnClockSkew узнаёт время по заголовку Date ответа 1.1.1.1. Проверка сертификата на этом соединении отключена
// намеренно: нужен лишь заголовок Date, никакие секреты по нему не передаются. Поправка включается, только если часы
// устройства врут больше чем на 10 минут. Работает один раз за запуск; true — поправка найдена и сохранена.
func learnClockSkew(ctx context.Context, dial func(ctx context.Context, network, addr string) (net.Conn, error)) bool {
	if !skewDone.CompareAndSwap(false, true) {
		return false
	}
	cctx, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()
	raw, err := dial(cctx, "tcp", "1.1.1.1:443")
	if err != nil {
		return false
	}
	defer raw.Close()
	_ = raw.SetDeadline(time.Now().Add(8 * time.Second))
	tc := tls.Client(raw, &tls.Config{ServerName: "one.one.one.one", InsecureSkipVerify: true, MinVersion: tls.VersionTLS12})
	if err := tc.HandshakeContext(cctx); err != nil {
		return false
	}
	if _, err := tc.Write([]byte("HEAD / HTTP/1.1\r\nHost: one.one.one.one\r\nConnection: close\r\n\r\n")); err != nil {
		return false
	}
	resp, err := http.ReadResponse(bufio.NewReader(tc), nil)
	if err != nil {
		return false
	}
	resp.Body.Close()
	t, err := http.ParseTime(resp.Header.Get("Date"))
	if err != nil {
		return false
	}
	skew := time.Until(t)
	if skew < 10*time.Minute && skew > -10*time.Minute {
		return false
	}
	clockSkew.Store(int64(skew))
	Logf("⏰ часы устройства неверны на %s: для проверки сертификатов использую время сервера", skew.Round(time.Minute))
	return true
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

// DefaultColoPolicy: по умолчанию запрещена только Москва (DME); остальные точки можно добавить в настройках.
func DefaultColoPolicy() *ColoPolicy {
	return &ColoPolicy{Block: []string{"DME"}}
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
	for _, c := range []string{"DME", "dme", " DME "} {
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
	cfg := fastCfg()
	// по умолчанию запрещена только Москва (DME), поэтому здесь явно запрещаем оба дата-центра теста
	cfg.Colo = &ColoPolicy{Block: []string{"DME", "LED"}}
	o := New(cfg, mem, []Transport{ft}, nil)
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

// WhitelistStrategies — стратегии для режима белых списков: настоящий SNI подменяется на имя, которое
// оператор пропускает (российский сайт). HTTP/2 по TCP идёт первым: проход TLS к Cloudflare проверен заранее.
func WhitelistStrategies(snis []string) []Strategy {
	if len(snis) > 3 {
		snis = snis[:3]
	}
	var out []Strategy
	for _, sni := range snis {
		for _, h := range []string{"162.159.198.2", "162.159.198.1"} {
			hp := net.JoinHostPort(h, "443")
			out = append(out, Strategy{ID: "h2/" + hp + "/wl:" + sni, Transport: "masque",
				Params: map[string]string{"endpoint": hp, "sni": sni, "h2": "1"}})
		}
		hp := net.JoinHostPort("162.159.198.2", "443")
		out = append(out, Strategy{ID: "h3/" + hp + "/wl:" + sni, Transport: "masque",
			Params: map[string]string{"endpoint": hp, "sni": sni, "h2": "0"}})
	}
	return out
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
	NetState     func() string // "ok" | "whitelist" | "dead": доступен ли зарубежный интернет (nil — не проверять)
	WLScan       func(ctx context.Context) []string // какие SNI проходят к Cloudflare в режиме белых списков
	CanRun       func(Strategy) bool                // можно ли сейчас запускать стратегию (например, свободен ли аккаунт WG)
	Allow        func(Strategy) bool                // разрешена ли стратегия выбранным протоколом (nil — все)
	ServiceGate  bool                               // после подключения проверять Telegram и обходить дата-центры, где он недоступен
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
	rx, tx uint64 // байты из туннеля в приложения / из приложений в туннель; первыми в структуре: 64-битные атомарные операции на 32-битных ARM требуют выравнивания
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

	// статистика работы (под mu)
	nConnect, nFailover, nLost int
	upSince                    time.Time
	lastFail                   string
	lastFailAt                 time.Time
	probesTotal, probesLost    int
	active                     atomic.Value // *attemptDev: карта, через которую сейчас идёт трафик
	testFail                   chan struct{}
	tried                      map[string]time.Time // когда стратегию последний раз пробовали
	inOutage, outageLogged     bool
	wlLast                     time.Time
	badColo                    map[string]time.Time // дата-центры, через которые не доходит Telegram

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
		testFail: make(chan struct{}, 1),
		tried:    map[string]time.Time{},
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
			if r := buildICMPv6Unreach(buf[:n]); r != nil {
				e.tun.Write(r) // приложение сразу получит отказ и перейдёт на IPv4
			}
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
	stats   atomic.Value  // func() string: дополнительные счётчики клиента туннеля (например WireGuard)
	tcpMu   sync.Mutex    // одновременно идёт одна TCP-проба
	tcpSt   atomic.Value  // tcpProbeState
}

type tcpProbeState struct {
	dst          net.IP
	dport, sport uint16
	seq          uint32
}

// SetStats принимает от клиента туннеля функцию с его счётчиками для диагностики.
func (d *attemptDev) SetStats(f func() string) { d.stats.Store(f) }

func (d *attemptDev) extra() string {
	if f, ok := d.stats.Load().(func() string); ok {
		return f()
	}
	return ""
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
	if id, res, ok := ParseAReply(pkt, d.port+1); ok {
		d.e.deliver(id, res)
		return nil
	}
	if st, _ := d.tcpSt.Load().(tcpProbeState); st.dst != nil && ParseTCPSynAckFrom(pkt, st.dst, st.dport, st.sport, st.seq+1) {
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
	return d.tcpProbeTo(ctx, probeDst, 443, timeout)
}

// tcpProbeTo: SYN на любой адрес и порт через эту карту. Каждая проба берёт новый порт, а SYN
// повторяется один раз на полпути: единичная потеря пакета не должна считаться отказом.
func (d *attemptDev) tcpProbeTo(ctx context.Context, dst net.IP, dport uint16, timeout time.Duration) (time.Duration, error) {
	d.tcpMu.Lock()
	defer d.tcpMu.Unlock()
	e := d.e
	sport := uint16(41000 + rand.Intn(20000))
	seq := rand.Uint32()
	d.tcpSt.Store(tcpProbeState{dst: dst, dport: dport, sport: sport, seq: seq})
	select {
	case <-d.tcpAck:
	default:
	}
	send := func() error {
		id := uint16(atomic.AddUint32(&e.nextID, 1))
		syn := BuildTCPSynTo(e.cfg.LocalIP, dst, sport, dport, seq, id)
		if syn == nil {
			return errors.New("нет IPv4-адреса туннеля")
		}
		select {
		case d.probeQ <- syn:
			return nil
		default:
			return errors.New("очередь проб переполнена")
		}
	}
	t0 := time.Now()
	if err := send(); err != nil {
		return 0, err
	}
	retry := time.After(timeout / 2)
	deadline := time.After(timeout)
	for {
		select {
		case <-d.tcpAck:
			rtt := time.Since(t0)
			if rst := BuildTCPRstTo(e.cfg.LocalIP, dst, sport, dport, seq+1, uint16(atomic.AddUint32(&e.nextID, 1))); rst != nil {
				select {
				case d.probeQ <- rst:
				default:
				}
			}
			return rtt, nil
		case <-retry:
			retry = nil
			_ = send()
		case <-deadline:
			return 0, errors.New("нет SYN-ACK")
		case <-ctx.Done():
			return 0, ctx.Err()
		}
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
	e.cfg.Mem.RecordGenes(nk, s, false)
	e.cfg.Mem.NoteReason(nk, poolFamily(s), classifyFail(msg))
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
	e.active.Store(dev)
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
		// сеть: есть ли вообще зарубежный интернет (режим белых списков, обрыв)
		var wlExtra []Strategy
		if st := e.netState(); st != "ok" {
			extra, wait := e.outageStep(ctx, st)
			if wait {
				continue
			}
			wlExtra = extra
		} else if e.inOutage {
			e.inOutage, e.outageLogged = false, false
			e.cfg.Mem.Rehabilitate(nk)
			Logf("♻ ограничения сняты — зарубежный интернет снова доступен")
		}
		cands := e.cfg.Mem.Rank(nk, e.allStrategies(nk))
		if len(wlExtra) > 0 {
			cands = append(append([]Strategy(nil), wlExtra...), cands...)
		}
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
			if until, ok := blockedFor(blocked, epKey); ep != "" && ok && time.Now().Before(until) {
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
				blocked[prefix24(epKey)] = time.Now().Add(10 * time.Minute)
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

// ErrRunnerBusy: клиент туннеля сейчас занят (например, единственный аккаунт WireGuard уже держит сессию).
var ErrRunnerBusy = errors.New("клиент туннеля занят")

func (e *Engine) noteProbe(ok bool) {
	e.mu.Lock()
	e.probesTotal++
	if !ok {
		e.probesLost++
	}
	e.mu.Unlock()
}

func (e *Engine) probeStats() (total, lost int) {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.probesTotal, e.probesLost
}

// TestFailover просит движок имитировать отказ основного туннеля, чтобы проверить горячий резерв.
func (e *Engine) TestFailover() {
	select {
	case e.testFail <- struct{}{}:
	default:
	}
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
	if e.probesTotal > 0 {
		s += "проб: " + itoa(e.probesTotal) + ", потеряно: " + itoa(e.probesLost) + "\n"
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

putv "$GODIR/gate.go" <<'HYDRA_EOF'
package hydra

import (
	"context"
	"net"
	"strings"
	"time"
)

var tgTargets = []struct {
	ip   string
	port uint16
}{
	{"149.154.167.51", 443}, {"149.154.175.50", 443}, {"149.154.167.91", 443}, {"91.108.56.130", 443},
}

const badColoFor = 6 * time.Hour

// coloAllowed: разрешён ли дата-центр настройками и не «плохой» ли он (Telegram не доходит).
func (e *Engine) coloAllowed(nk, colo string) bool {
	if !e.policy().Allows(colo) {
		return false
	}
	if e.soft {
		return true
	}
	return !e.isBadColo(nk, colo)
}

func (e *Engine) isBadColo(nk, colo string) bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	t, ok := e.badColo[nk+"|"+colo]
	return ok && time.Since(t) < badColoFor
}

func (e *Engine) noteBadColo(nk, colo string) {
	e.mu.Lock()
	if e.badColo == nil {
		e.badColo = map[string]time.Time{}
	}
	e.badColo[nk+"|"+colo] = time.Now()
	e.mu.Unlock()
}

func (e *Engine) badColoCount(nk string) int {
	e.mu.Lock()
	defer e.mu.Unlock()
	n := 0
	for k, t := range e.badColo {
		if strings.HasPrefix(k, nk+"|") && time.Since(t) < badColoFor {
			n++
		}
	}
	return n
}

// knownBlocked: по памяти известно, что адрес этой стратегии в этой сети попадает в запрещённый дата-центр.
func (e *Engine) knownBlocked(nk string, s Strategy) bool {
	ep := s.Params["endpoint"]
	if ep == "" {
		return false
	}
	kc := e.cfg.Mem.KnownColo(nk, ep)
	return kc != "" && !e.coloAllowed(nk, kc)
}

// Сервисы «мягкой» проверки: у них нет постоянных адресов, адрес берётся DNS-запросом внутри туннеля. Результат
// идёт в память (влияет на порядок стратегий и запускает придумывание новых), но дата-центр из-за них не банится:
// запрет дата-центров без запасных оставил бы VPN без выхода.
var svcSoft = []struct{ name, host string }{
	{"YouTube", "redirector.googlevideo.com"},
	{"WhatsApp", "web.whatsapp.com"},
}

// serviceGate проверяет через только что поднятый туннель, доходят ли Telegram, YouTube и WhatsApp.
// Если интернет работает, а ни один сервер Telegram не отвечает, — дата-центр помечается плохим, и Гидра
// ищет другой путь. Больше трёх плохих дата-центров в одной сети не набираем: значит, дело не в них.
// Результаты по всем сервисам запоминаются: стратегии, через которые доходит всё, получают приоритет.
func (e *Engine) serviceGate(ctx context.Context, nk string, a *attempt, out chan<- string) {
	hard := e.badColoCount(nk) < 3
	select {
	case <-ctx.Done():
		return
	case <-a.ctx.Done():
		return
	case <-time.After(2500 * time.Millisecond):
	}
	base := false
	for _, ip := range []string{"8.8.8.8", "1.1.1.1"} {
		if _, err := a.dev.tcpProbeTo(a.ctx, net.ParseIP(ip).To4(), 443, 3*time.Second); err == nil {
			base = true
			break
		}
		if a.ctx.Err() != nil {
			return
		}
	}
	if !base {
		return // сеть шатается: вывод был бы ненадёжным
	}
	tgOK := false
	for _, t := range tgTargets {
		if _, err := a.dev.tcpProbeTo(a.ctx, net.ParseIP(t.ip).To4(), t.port, 3*time.Second); err == nil {
			tgOK = true
			break
		}
		if a.ctx.Err() != nil {
			return
		}
	}
	e.cfg.Mem.RecordService(nk, a.s.ID, "Telegram", tgOK)
	if tgOK {
		Logf("✔ Telegram через %s (дата-центр %s) достижим", a.s.ID, a.colo)
	} else {
		Logf("✘ Telegram через %s (дата-центр %s) не достижим", a.s.ID, a.colo)
		if hard {
			select {
			case out <- "Telegram не доходит через дата-центр " + a.colo + " (остальной интернет работает) — ищу другой путь":
			default:
			}
			return
		}
	}
	failed := 0
	for _, t := range svcSoft {
		if a.ctx.Err() != nil || ctx.Err() != nil {
			return
		}
		ip, err := a.dev.resolveA(a.ctx, t.host, 3*time.Second)
		if err != nil {
			Logf("   ? %s: адрес не получен (%v), в память не записываю", t.name, err)
			continue
		}
		_, err = a.dev.tcpProbeTo(a.ctx, ip, 443, 2500*time.Millisecond)
		if a.ctx.Err() != nil {
			return
		}
		e.cfg.Mem.RecordService(nk, a.s.ID, t.name, err == nil)
		if err == nil {
			Logf("✔ %s через %s достижим", t.name, a.s.ID)
		} else {
			failed++
			Logf("✘ %s через %s (дата-центр %s) не достижим: %v", t.name, a.s.ID, a.colo, err)
		}
	}
	if failed > 0 {
		e.svcGrow(nk)
	}
}
HYDRA_EOF

putv "$GODIR/genes.go" <<'HYDRA_EOF'
package hydra

import (
	"fmt"
	"math/rand"
	"net"
	"sort"
	"strings"
)

// «Гены» стратегии — её параметры (SNI, порт, TTL фейков, keepalive и т. д.). Гидра считает, с какими
// значениями параметров в этой сети чаще удаётся подключиться, и при придумывании новых вариантов
// чаще выбирает удачные значения (но 1 раз из 4 пробует случайное, чтобы не застрять).

func geneKeys(s Strategy) []string {
	fam := poolFamily(s)
	var ks []string
	add := func(name, v string) {
		if v != "" {
			ks = append(ks, fam+"."+name+"="+v)
		}
	}
	add("sni", s.Params["sni"])
	add("fake", s.Params["fake"])
	add("ttl", s.Params["fttl"])
	add("cnt", s.Params["fcount"])
	add("size", s.Params["fsize"])
	add("keep", s.Params["keep"])
	add("noise", s.Params["noise"])
	add("jc", s.Params["jc"])
	if _, port, err := net.SplitHostPort(s.Params["endpoint"]); err == nil {
		add("port", port)
	}
	return ks
}

// RecordGenes запоминает, как сработали значения параметров этой стратегии.
func (m *Memory) RecordGenes(nk string, s Strategy, ok bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.Genes == nil {
		m.Genes = map[string]*stat{}
	}
	for _, k := range geneKeys(s) {
		key := nk + "|" + k
		st := m.Genes[key]
		if st == nil {
			st = &stat{}
			m.Genes[key] = st
		}
		if ok {
			st.OK++
		} else {
			st.Fail++
		}
		if st.OK+st.Fail > 40 { // старое забываем
			st.OK /= 2
			st.Fail /= 2
		}
	}
	m.saveSoonLocked()
}

// PickGene выбирает значение параметра: чаще те, что в этой сети срабатывали лучше.
func (m *Memory) PickGene(nk, key string, opts []string, rnd *rand.Rand) string {
	if len(opts) == 0 {
		return ""
	}
	if rnd.Intn(100) < 25 {
		return opts[rnd.Intn(len(opts))]
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	w := make([]float64, len(opts))
	sum := 0.0
	for i, o := range opts {
		ok, fail := 0, 0
		if st := m.Genes[nk+"|"+key+"="+o]; st != nil {
			ok, fail = st.OK, st.Fail
		}
		r := (float64(ok) + 1) / (float64(ok+fail) + 2)
		w[i] = r*r + 0.05
		sum += w[i]
	}
	x := rnd.Float64() * sum
	for i := range opts {
		x -= w[i]
		if x <= 0 {
			return opts[i]
		}
	}
	return opts[len(opts)-1]
}

// NoteReason считает причины сбоев по семействам стратегий.
func (m *Memory) NoteReason(nk, fam, class string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.Why == nil {
		m.Why = map[string]int{}
	}
	m.Why[nk+"|"+fam+"|"+class]++
	m.saveSoonLocked()
}

// Reasons — сводка причин сбоев в этой сети (для отчёта).
func (m *Memory) Reasons(nk string) string {
	m.mu.Lock()
	defer m.mu.Unlock()
	type kv struct {
		k string
		n int
	}
	var rows []kv
	for k, n := range m.Why {
		if strings.HasPrefix(k, nk+"|") {
			rows = append(rows, kv{strings.TrimPrefix(k, nk+"|"), n})
		}
	}
	if len(rows) == 0 {
		return ""
	}
	sort.Slice(rows, func(i, j int) bool { return rows[i].n > rows[j].n })
	out := "причины сбоев в этой сети (семейство|причина):\n"
	for i, r := range rows {
		if i >= 10 {
			break
		}
		out += fmt.Sprintf("  %s ×%d\n", strings.Replace(r.k, "|", ": ", 1), r.n)
	}
	return out
}

// classifyFail приводит текст причины к короткому классу.
func classifyFail(msg string) string {
	switch {
	case strings.Contains(msg, "рукопожатие могло пройти"):
		return "рукопожатие есть, данных нет"
	case strings.Contains(msg, "ни одного пакета"):
		return "ничего не пришло из туннеля"
	case strings.Contains(msg, "TCP — нет"):
		return "UDP идёт, TCP нет"
	case strings.Contains(msg, "пакеты из туннеля приходят"):
		return "туннель принят, трафик не идёт"
	case strings.Contains(msg, "запрещён"):
		return "запрещённый дата-центр"
	case strings.Contains(msg, "клиент остановился"), strings.Contains(msg, "нет маршрута"):
		return "ошибка клиента"
	}
	return "прочее"
}
HYDRA_EOF

putv "$GODIR/go.mod" <<'HYDRA_EOF'
module hydra/core

go 1.22
HYDRA_EOF

putv "gradle.properties" <<'HYDRA_EOF'
org.gradle.jvmargs=-Xmx3g -Dfile.encoding=UTF-8
android.useAndroidX=true
android.nonTransitiveRClass=true
HYDRA_EOF

putv "$GODIR/icmp6.go" <<'HYDRA_EOF'
package hydra

import "encoding/binary"

// buildICMPv6Unreach строит ответ «адресат недостижим» на исходящий IPv6-пакет. Когда IPv6 через туннель
// выключен, приложение получает отказ мгновенно и сразу идёт по IPv4, а не ждёт таймаута.
func buildICMPv6Unreach(orig []byte) []byte {
	if len(orig) < 40 || orig[0]>>4 != 6 {
		return nil
	}
	inv := orig
	if len(inv) > 1232 {
		inv = inv[:1232]
	}
	plen := 8 + len(inv)
	p := make([]byte, 40+plen)
	p[0] = 0x60
	binary.BigEndian.PutUint16(p[4:], uint16(plen))
	p[6] = 58 // ICMPv6
	p[7] = 64
	copy(p[8:24], orig[24:40])  // отправитель ответа — прежний адресат
	copy(p[24:40], orig[8:24])  // получатель ответа — прежний отправитель
	p[40], p[41] = 1, 0         // destination unreachable, no route
	copy(p[48:], inv)
	var sum uint32
	add := func(b []byte) {
		for i := 0; i+1 < len(b); i += 2 {
			sum += uint32(b[i])<<8 | uint32(b[i+1])
		}
		if len(b)%2 == 1 {
			sum += uint32(b[len(b)-1]) << 8
		}
	}
	add(p[8:24])
	add(p[24:40])
	sum += uint32(plen) + 58
	add(p[40:])
	for sum>>16 != 0 {
		sum = (sum & 0xffff) + (sum >> 16)
	}
	binary.BigEndian.PutUint16(p[42:], ^uint16(sum))
	return p
}
HYDRA_EOF

putv "$GODIR/journal.go" <<'HYDRA_EOF'
package hydra

import (
	"fmt"
	"os"
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
	jfileWrite(line)
}

// Журнал дублируется в файл (до ~3 МБ, затем старая половина уходит в .old): так записи переживают
// перезапуск службы и слёт приложения, а в отчёте есть история за много часов.
var jfile struct {
	mu   sync.Mutex
	f    *os.File
	path string
	size int64
}

const jfileMax = 3 << 20

func jfileWrite(line string) {
	jfile.mu.Lock()
	defer jfile.mu.Unlock()
	if jfile.f == nil {
		return
	}
	n, _ := jfile.f.WriteString(time.Now().Format("01-02 ") + line + "\n")
	jfile.size += int64(n)
	if jfile.size > jfileMax {
		jfile.f.Close()
		os.Rename(jfile.path, jfile.path+".old")
		f, err := os.OpenFile(jfile.path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
		if err != nil {
			jfile.f = nil
			return
		}
		jfile.f, jfile.size = f, 0
	}
}

func lastLineOf(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	ls := strings.Split(strings.TrimRight(string(b), "\n"), "\n")
	if len(ls) == 0 {
		return ""
	}
	return ls[len(ls)-1]
}

// SetJournalFile включает запись журнала в файл. Если прошлая сессия оборвалась без записи об остановке
// службы, пишет предупреждение (слёт приложения, убийство процесса системой, перезагрузка).
func SetJournalFile(path string) {
	jfile.mu.Lock()
	if jfile.f != nil {
		jfile.mu.Unlock()
		return
	}
	prev := lastLineOf(path)
	jfile.path = path
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err == nil {
		jfile.f = f
		if st, e := f.Stat(); e == nil {
			jfile.size = st.Size()
		}
	}
	jfile.mu.Unlock()
	if err != nil {
		return
	}
	Logf("──────── запуск приложения ────────")
	if prev != "" && !strings.Contains(prev, "служба: уничтожена") && !strings.Contains(prev, "служба: остановка") {
		if len(prev) > 160 {
			prev = prev[:160]
		}
		Logf("⚠ прошлая сессия оборвалась без остановки службы (слёт приложения, убийство процесса системой или перезагрузка). Последняя запись: %s", prev)
	}
}

// JournalFileTail — последние n строк журнала из файла (включая прошлые запуски); пусто, если файла нет.
func JournalFileTail(n int) string {
	jfile.mu.Lock()
	path := jfile.path
	jfile.mu.Unlock()
	if path == "" {
		return ""
	}
	var all []string
	for _, p := range []string{path + ".old", path} {
		if b, err := os.ReadFile(p); err == nil {
			all = append(all, strings.Split(strings.TrimRight(string(b), "\n"), "\n")...)
		}
	}
	if n > 0 && len(all) > n {
		all = all[len(all)-n:]
	}
	return strings.Join(all, "\n")
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
	"net"
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
	for _, s := range e.cfg.Mem.Generated(nk) {
		if e.cfg.Allow == nil || e.cfg.Allow(s) { // придуманные стратегии чужого протокола не подмешиваем
			out = append(out, s)
		}
	}
	return out
}

// sniPool — SNI, которые принимает сервер MASQUE Cloudflare (сертификат проверяется по ключу, а не по имени).
var sniPool = []string{
	"consumer-masque.cloudflareclient.com", "cdnjs.cloudflare.com", "www.cloudflare.com",
	"one.one.one.one", "developers.cloudflare.com", "dash.cloudflare.com",
	"speed.cloudflare.com", "cloudflare.dev", "research.cloudflare.com",
	"www.speedtest.net", "www.microsoft.com", "www.apple.com", "www.bing.com",
	// российские сайты: имена, которые операторы пропускают даже в режиме белых списков
	"ya.ru", "yandex.ru", "dzen.ru", "vk.com", "mail.ru", "gosuslugi.ru",
}

// Порты, на которых слушают серверы WARP (взято из списков сканеров и генераторов конфигов).
var masquePorts = []string{"443", "8443", "4443", "8095", "500", "1701", "4500"}
var wgPorts = []string{"2408", "500", "1701", "4500", "854", "859", "864", "878", "880", "890", "891", "894", "903",
	"908", "928", "934", "939", "942", "943", "945", "946", "955", "968", "987", "988", "1002", "1010", "1014",
	"1018", "1070", "1074", "1180", "3476", "3581", "3854", "4177", "4198", "4233", "5279", "5956", "7103",
	"7152", "7156", "7281", "7559", "8319", "8742", "8854", "8886"}
var keepPool = []int{5, 10, 15, 30}
var keepPoolS = []string{"5", "10", "15", "30"}
var noisePool = []string{"0", "5", "10", "15"}

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
func GenerateVariants(nk string, mem *Memory, all []Strategy, n int, rnd *rand.Rand, needOK bool) []Strategy {
	parents := map[string][]Strategy{}
	for _, s := range mem.Rank(nk, all) {
		f := family(s)
		if f == "" || len(parents[f]) >= 3 {
			continue
		}
		if needOK && !mem.Worked(nk, s.ID) {
			continue // для пополнения пула берём «родителями» только то, что уже работало
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
		if f == "" || ep == "" || seenEP[f+ep] || mem.EndpointDead(nk, s.ID) {
			continue // мёртвые адреса в мутации не участвуют
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
				q["fake"] = mem.PickGene(nk, "h3.fake", fakeSNIPool, rnd)
			}
			if rnd.Intn(4) == 0 { // настоящий SNI в QUIC Initial — то, что читает DPI
				q["sni"] = mem.PickGene(nk, "h3.sni", sniPool, rnd)
			}
			if rnd.Intn(10) < 3 { // другой порт: операторы нередко режут именно UDP 443
				q["endpoint"] = net.JoinHostPort(hostOnly(q["endpoint"]), mem.PickGene(nk, "h3.port", masquePorts, rnd))
			}
			if rnd.Intn(4) == 0 { // другой период keepalive: помогает против таймеров NAT оператора
				q["keep"] = mem.PickGene(nk, "h3.keep", keepPoolS, rnd)
			}
			if rnd.Intn(3) == 0 { // шумовые пакеты перед рукопожатием (идея из генераторов конфигов)
				q["noise"] = mem.PickGene(nk, "h3.noise", noisePool, rnd)
				q["nmin"], q["nmax"] = "5", "10"
			}
			q["fttl"] = strconv.Itoa(ttl)
			q["fcount"] = strconv.Itoa(cnt)
			q["fsize"] = strconv.Itoa(size)
			id = fmt.Sprintf("h3/%s/g:%s:%s:%dx%ds%d", q["endpoint"], q["sni"], q["fake"], ttl, cnt, size)
			if k := q["keep"]; k != "" {
				id += "k" + k
			}
			if nz := q["noise"]; nz != "" && nz != "0" {
				id += "n" + nz
			}
		case "h2":
			q["sni"] = mem.PickGene(nk, "h2.sni", sniPool, rnd)
			id = fmt.Sprintf("h2/%s/g:%s", q["endpoint"], q["sni"])
		case "wg":
			jc := clampInt(atoiDefault(q["jc"], 4)+rnd.Intn(5)-2, 1, 16)
			jmin := clampInt(atoiDefault(q["jmin"], 40)+rnd.Intn(21)-10, 5, 100)
			jmax := clampInt(atoiDefault(q["jmax"], 70)+rnd.Intn(61)-30, jmin+10, 300)
			q["jc"], q["jmin"], q["jmax"] = strconv.Itoa(jc), strconv.Itoa(jmin), strconv.Itoa(jmax)
			if rnd.Intn(10) < 4 { // у серверов WARP десятки рабочих UDP-портов
				q["endpoint"] = net.JoinHostPort(hostOnly(q["endpoint"]), mem.PickGene(nk, "wg.port", wgPorts, rnd))
			}
			sfx := ""
			if q["rsv"] == "1" {
				sfx = "r"
			}
			id = fmt.Sprintf("wg/%s/g:%d-%d-%d%s", q["endpoint"], jc, jmin, jmax, sfx)
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
	gen := GenerateVariants(nk, e.cfg.Mem, e.allStrategies(nk), 6, rnd, false)
	if len(gen) == 0 {
		return
	}
	e.cfg.Mem.AddGenerated(nk, gen)
	Logf("🧬 все известные способы не сработали — придумал %d новых вариантов обхода для сети %s", len(gen), nk)
}

// blame записывает провал стратегии, но только если зарубежный интернет вообще есть: иначе виновата сеть
// (обрыв или режим белых списков), а не стратегия.
func (e *Engine) blame(nk, id string) bool {
	if e.cfg.NetState != nil {
		if st := e.netState(); st != "ok" {
			Logf("   ⚠ зарубежного интернета нет (%s) — стратегию не виню", st)
			return false
		}
	} else if e.cfg.NetAlive != nil && !e.cfg.NetAlive() {
		Logf("   ⚠ интернета нет совсем — стратегию не виню")
		return false
	}
	e.cfg.Mem.Record(nk, id, false, 0)
	return true
}

// waitOnline ждёт, пока зарубежный интернет появится (или станет понятно, что включены белые списки).
// Проверки редеют: 3 с, затем 10 с, затем 30 с.
func (e *Engine) waitOnline(ctx context.Context) {
	iv := 3 * time.Second
	start := time.Now()
	for {
		select {
		case <-ctx.Done():
			return
		case <-e.cfg.NetChanged:
		case <-time.After(iv):
		}
		if e.cfg.NetState != nil {
			if st := e.netState(); st == "ok" || st == "whitelist" {
				return
			}
		} else if e.cfg.NetAlive == nil || e.cfg.NetAlive() {
			return
		}
		if since := time.Since(start); since > 10*time.Minute {
			iv = 30 * time.Second
		} else if since > time.Minute {
			iv = 10 * time.Second
		}
	}
}

// grow пополняет пул: придумывает новые варианты на основе стратегий, которые уже работали.
func (e *Engine) grow(nk string) {
	if e.cfg.Mem == nil {
		return
	}
	rnd := rand.New(rand.NewSource(time.Now().UnixNano()))
	gen := GenerateVariants(nk, e.cfg.Mem, e.allStrategies(nk), 6, rnd, true)
	if len(gen) == 0 {
		return
	}
	e.cfg.Mem.AddGenerated(nk, gen)
	Logf("🧬 пополняю пул: придумал %d новых вариантов на основе работающих", len(gen))
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
		} else if fsni := s.Params["fake"]; fsni != "" || atoiDefault(s.Params["noise"], 0) > 0 {
			// фейковые QUIC-пакеты с малым TTL перед рукопожатием (как у Zarp)
			var fk FakeSpec
			fk.TTL = atoiDefault(s.Params["fttl"], 5)
			fk.Noise = atoiDefault(s.Params["noise"], 0)
			fk.NoiseMin = atoiDefault(s.Params["nmin"], 5)
			fk.NoiseMax = atoiDefault(s.Params["nmax"], 10)
			for i := 0; fsni != "" && i < atoiDefault(s.Params["fcount"], 6); i++ {
				if p, err := BuildFakeQUICInitial(fsni, atoiDefault(s.Params["fsize"], 1357)); err == nil {
					fk.Payloads = append(fk.Payloads, p)
				}
			}
			if len(fk.Payloads) > 0 || fk.Noise > 0 {
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
			KeepalivePeriod:   time.Duration(atoiDefault(s.Params["keep"], 30)) * time.Second,
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
	LastFail time.Time `json:"last_fail"`
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
	EPColo map[string]coloRec `json:"epcolo"` // в какой дата-центр попадает адрес в этой сети
	Genes map[string]*stat `json:"genes"` // как срабатывали значения параметров стратегий по сетям
	Why   map[string]int   `json:"why"`   // причины сбоев по сетям и семействам
	Svc map[string]*stat `json:"svc"` // дошли ли сервисы (Telegram, YouTube, WhatsApp) через стратегию: сеть|стратегия|сервис
	Ver int                   `json:"ver"` // версия формата: <2 — в памяти могли быть сбои из-за белых списков
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
	if m.Ver < 2 {
		// прежние версии записывали провалы стратегий и тогда, когда виноват был режим белых списков
		for k := range m.Nets {
			m.rehabLocked(k)
		}
		m.Ver = 2
	}
	return m, nil
}

func (m *Memory) rehabLocked(net string) {
	for _, st := range m.Nets[net] {
		if st.OK > 0 {
			if st.Fail > st.OK {
				st.Fail = st.OK
			}
		} else if st.Fail > 1 {
			st.Fail = 1
		}
		st.LastFail = time.Time{}
	}
}

// Rehabilitate прощает сбои, накопленные в период без интернета или режима белых списков.
func (m *Memory) Rehabilitate(net string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.rehabLocked(net)
	m.saveSoonLocked()
}

// EndpointDead: все стратегии с этим адресом (и протоколом) в этой сети подряд не работали, ни разу не сработав.
// Такие адреса на время (12 часов после последнего сбоя) исключаются из фоновых проверок и мутаций.
func (m *Memory) EndpointDead(net, id string) bool {
	parts := strings.SplitN(id, "/", 3)
	if len(parts) < 3 {
		return false
	}
	key := parts[0] + "/" + parts[1] + "/"
	m.mu.Lock()
	defer m.mu.Unlock()
	ok, fail := 0, 0
	var last time.Time
	for sid, st := range m.Nets[net] {
		if !strings.HasPrefix(sid, key) {
			continue
		}
		ok += st.OK
		fail += st.Fail
		if st.LastFail.After(last) {
			last = st.LastFail
		}
	}
	return ok == 0 && fail >= 3 && time.Since(last) < quarantineFor
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
		s.LastFail = time.Now()
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
	// карантин на 12 часов после последнего сбоя: потом стратегии дают второй шанс (DPI меняется)
	return st != nil && st.OK == 0 && st.Fail >= 3 && time.Since(st.LastFail) < 12*time.Hour
}

// Stat — опыт стратегии в этой сети.
func (m *Memory) Stat(net, id string) (ok, fail int, lastOK, lastFail time.Time, found bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	st := m.Nets[net][id]
	if st == nil {
		return 0, 0, time.Time{}, time.Time{}, false
	}
	return st.OK, st.Fail, st.LastOK, st.LastFail, true
}

// priorLocked — оценка стратегии для сети без истории: опыт в других сетях того же класса
// (все "wifi:*" или все "cell:*") с пониженным доверием. Вызывать под m.mu.
func (m *Memory) priorLocked(net, id string) float64 {
	class := net
	if i := strings.Index(net, ":"); i > 0 {
		class = net[:i]
	}
	if class == "cell" {
		return 0.5 // у разных операторов разные ограничения: опыт МТС ничего не говорит о Билайне
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
	agg := m.classAggLocked(net)
	score := func(s Strategy) float64 {
		st := m.Nets[net][s.ID]
		adj := classAdj(agg, s.ID, st)
		if sb := seedBonus(net, s.ID); sb > 0 && (st == nil || st.OK > 0 || st.Fail < 3) {
			adj += sb
		}
		if st == nil {
			return m.priorLocked(net, s.ID) + m.svcBonusLocked(net, s.ID) + adj
		}
		rate := float64(st.OK+1) / float64(st.OK+st.Fail+2)
		pen := math.Min(st.EWMAms/5000, 0.3)
		bonus := 0.0
		if time.Since(st.LastOK) < 24*time.Hour {
			bonus = 0.1
		}
		return rate - pen + bonus + m.svcBonusLocked(net, s.ID) + adj
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

type coloRec struct {
	Colo string    `json:"c"`
	At   time.Time `json:"t"`
}

// NoteColo запоминает, в какой дата-центр попал адрес.
func (m *Memory) NoteColo(nk, ep, colo string) {
	if ep == "" || colo == "" {
		return
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.EPColo == nil {
		m.EPColo = map[string]coloRec{}
	}
	m.EPColo[nk+"|"+ep] = coloRec{colo, time.Now()}
	m.saveSoonLocked()
}

// KnownColo — дата-центр, в который адрес попадал в этой сети в последние 6 часов ("" — неизвестно).
func (m *Memory) KnownColo(nk, ep string) string {
	m.mu.Lock()
	defer m.mu.Unlock()
	r, ok := m.EPColo[nk+"|"+ep]
	if !ok || time.Since(r.At) > 6*time.Hour {
		return ""
	}
	return r.Colo
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

const version = "0.9.1"

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

// wg2Path — второй аккаунт WireGuard: у сервера одна сессия на ключ, поэтому для горячего резерва нужен свой ключ.
func wg2Path(dir string) string { return filepath.Join(dir, "wg2.json") }

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

// RegisterWireguardExtraReport регистрирует второй аккаунт WireGuard (для резерва).
func RegisterWireguardExtraReport(dir string) string { return registerReport(wg2Path(dir), true) }

// WireguardExtraID возвращает ID второго аккаунта WireGuard или "".
func WireguardExtraID(dir string) string {
	a, err := hydra.LoadAccount(wg2Path(dir))
	if err != nil || a == nil {
		return ""
	}
	return a.ID
}

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
func DeleteWireguardConfig(dir string) {
	os.Remove(wgPath(dir))
	os.Remove(wg2Path(dir))
}
HYDRA_EOF

putv "$GODIR/mobile/netalive.go" <<'HYDRA_EOF'
package mobile

import (
	"context"
	"crypto/tls"
	"fmt"
	"net"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// Состояние сети: "ok" — зарубежный интернет доступен; "whitelist" — отвечают только российские адреса
// (режим «белых списков» у оператора); "dead" — не отвечает ничего.

var (
	foreignTargets  = []string{"1.1.1.1:443", "8.8.8.8:443", "9.9.9.9:443", "162.159.198.2:443"}
	domesticTargets = []string{"77.88.8.8:443", "77.88.8.1:443"}

	lastState   atomic.Value // string
	lastStateAt atomic.Int64
)

type dialRes struct {
	addr    string
	foreign bool
	ok      bool
	ms      int64
}

func dialAll(timeout time.Duration) []dialRes {
	type job struct {
		addr    string
		foreign bool
	}
	var jobs []job
	for _, a := range foreignTargets {
		jobs = append(jobs, job{a, true})
	}
	for _, a := range domesticTargets {
		jobs = append(jobs, job{a, false})
	}
	out := make([]dialRes, len(jobs))
	var wg sync.WaitGroup
	for i, j := range jobs {
		wg.Add(1)
		go func(i int, j job) {
			defer wg.Done()
			t0 := time.Now()
			c, err := net.DialTimeout("tcp", j.addr, timeout)
			if err == nil {
				c.Close()
			}
			out[i] = dialRes{j.addr, j.foreign, err == nil, time.Since(t0).Milliseconds()}
		}(i, j)
	}
	wg.Wait()
	return out
}

func classify(rs []dialRes) string {
	dom := false
	for _, r := range rs {
		if r.ok && r.foreign {
			return "ok"
		}
		if r.ok && !r.foreign {
			dom = true
		}
	}
	if dom {
		return "whitelist"
	}
	return "dead"
}

// realNetState: быстрая проверка — как только отвечает любой зарубежный адрес, сеть «ok».
func realNetState() string {
	type r struct {
		foreign, ok bool
	}
	ch := make(chan r, len(foreignTargets)+len(domesticTargets))
	probe := func(addr string, foreign bool) {
		c, err := net.DialTimeout("tcp", addr, 2500*time.Millisecond)
		if err == nil {
			c.Close()
		}
		ch <- r{foreign, err == nil}
	}
	for _, a := range foreignTargets {
		go probe(a, true)
	}
	for _, a := range domesticTargets {
		go probe(a, false)
	}
	dom := false
	st := "dead"
	for i := 0; i < len(foreignTargets)+len(domesticTargets); i++ {
		x := <-ch
		if x.ok && x.foreign {
			st = "ok"
			break
		}
		if x.ok {
			dom = true
		}
	}
	if st != "ok" && dom {
		st = "whitelist"
	}
	lastState.Store(st)
	lastStateAt.Store(time.Now().Unix())
	return st
}

// realNetAlive: есть ли зарубежный интернет (для отказоустойчивых проверок).
func realNetAlive() bool { return realNetState() == "ok" }

// wlSNIs — имена российских сайтов, которые операторы чаще всего пропускают в режиме белых списков.
var wlSNIs = []string{
	"ya.ru", "yandex.ru", "www.yandex.ru", "dzen.ru", "vk.com", "mail.ru", "gosuslugi.ru",
	"www.gosuslugi.ru", "sberbank.ru", "ozon.ru", "wildberries.ru", "avito.ru", "rutube.ru", "kinopoisk.ru",
}

func tlsOK(ctx context.Context, addr, sni string) bool {
	d := &net.Dialer{Timeout: 3 * time.Second}
	conn, err := tls.DialWithDialer(d, "tcp", addr, &tls.Config{ServerName: sni, InsecureSkipVerify: true, MinVersion: tls.VersionTLS12})
	if err != nil {
		return false
	}
	conn.Close()
	return ctx.Err() == nil
}

// realWLScan: с какими именами (SNI) удаётся завершить TLS-рукопожатие с Cloudflare сквозь белые списки.
func realWLScan(ctx context.Context) []string {
	const host = "162.159.198.2:443"
	res := make([]bool, len(wlSNIs))
	var wg sync.WaitGroup
	sem := make(chan struct{}, 5)
	for i, sni := range wlSNIs {
		wg.Add(1)
		sem <- struct{}{}
		go func(i int, sni string) {
			defer wg.Done()
			defer func() { <-sem }()
			res[i] = tlsOK(ctx, host, sni)
		}(i, sni)
	}
	wg.Wait()
	var out []string
	for i, ok := range res {
		if ok {
			out = append(out, wlSNIs[i])
		}
	}
	return out
}

// WhitelistCheck — подробная проверка для экрана диагностики: что доступно, а что нет.
func WhitelistCheck() string {
	rs := dialAll(3 * time.Second)
	st := classify(rs)
	var b strings.Builder
	switch st {
	case "ok":
		b.WriteString("Состояние сети: обычная (зарубежный интернет доступен)\n")
	case "whitelist":
		b.WriteString("Состояние сети: БЕЛЫЕ СПИСКИ (отвечают только российские адреса)\n")
	default:
		b.WriteString("Состояние сети: нет интернета\n")
	}
	b.WriteString("\nTCP-соединения:\n")
	for _, r := range rs {
		kind := "зарубежный"
		if !r.foreign {
			kind = "российский"
		}
		mark := "✘"
		if r.ok {
			mark = "✔"
		}
		b.WriteString(fmt.Sprintf("  %s %s (%s) %d мс\n", mark, r.addr, kind, r.ms))
	}
	ctx := context.Background()
	b.WriteString("\nTLS-рукопожатие с Cloudflare (162.159.198.2:443) под разными именами:\n")
	base := "www.cloudflare.com"
	mark := "✘"
	if tlsOK(ctx, "162.159.198.2:443", base) {
		mark = "✔"
	}
	b.WriteString(fmt.Sprintf("  %s %s (обычное имя)\n", mark, base))
	pass := realWLScan(ctx)
	for _, sni := range wlSNIs {
		m := "✘"
		for _, p := range pass {
			if p == sni {
				m = "✔"
			}
		}
		b.WriteString(fmt.Sprintf("  %s %s\n", m, sni))
	}
	if st == "whitelist" {
		if len(pass) > 0 {
			b.WriteString("\nК Cloudflare проходят имена: " + strings.Join(pass, ", ") + ". Гидра попробует подключиться с ними.\n")
		} else {
			b.WriteString("\nНи одно имя не прошло: фильтр, похоже, работает по IP-адресам. Нужен ретранслятор с адресом из белого списка (см. подсказку).\n")
		}
	}
	return b.String()
}

// netStateInfo — последнее известное состояние без сетевых запросов (для отчёта).
func netStateInfo() string {
	s, _ := lastState.Load().(string)
	if s == "" {
		return "состояние сети: ещё не проверялось\n"
	}
	ago := time.Now().Unix() - lastStateAt.Load()
	return fmt.Sprintf("состояние сети: %s (проверено %d с назад)\n", s, ago)
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
	polV6    = false // IPv6 через туннель (по умолчанию выключен: IPv4 надёжнее, приложения сразу переходят на него)
	polGate  = true  // проверять Telegram после подключения
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

// SetIPv6 включает или выключает IPv6 через туннель (выключен — приложения сразу получают отказ и идут по IPv4).
func SetIPv6(on bool) {
	polMu.Lock()
	polV6 = on
	polMu.Unlock()
}

func currentIPv6() bool {
	polMu.Lock()
	defer polMu.Unlock()
	return polV6
}

// SetServiceGate: после подключения проверять, доходит ли Telegram, и обходить дата-центры, где он недоступен.
func SetServiceGate(on bool) {
	polMu.Lock()
	polGate = on
	polMu.Unlock()
}

func currentGate() bool {
	polMu.Lock()
	defer polMu.Unlock()
	return polGate
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
	vpnMem    *hydra.Memory
	vpnWG     *hydra.WGPool
	journalOnce sync.Once
	vpnCancel context.CancelFunc
)

// StartTunnel запускает Гидру на TUN-интерфейсе, который создал Android (tunFd).
// Пустая строка — успех, иначе текст ошибки.
func StartTunnel(dir string, tunFd int) string {
	vpnMu.Lock()
	defer vpnMu.Unlock()
	journalOnce.Do(func() { hydra.SetJournalFile(filepath.Join(dir, "journal.log")) })
	if vpnEngine != nil {
		return "уже запущено"
	}
	macc, _ := hydra.LoadAccount(accountPath(dir))
	wacc, _ := hydra.LoadAccount(wgPath(dir))
	wacc2, _ := hydra.LoadAccount(wg2Path(dir))
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
	var wgp *hydra.WGPool
	if wacc != nil {
		accs := []*hydra.Account{wacc}
		if wacc2 != nil && wacc2.Kind == "wg" {
			accs = append(accs, wacc2) // второй ключ: резерв WireGuard не мешает основной сессии
		}
		wgp = hydra.NewWGPool(accs...)
		r, err := hydra.NewWGPoolRunner(wgp)
		if err != nil {
			return err.Error()
		}
		runners["wg"] = r
	}
	vpnWG = wgp
	var mS, wS []hydra.Strategy
	if macc != nil {
		mS = hydra.MasqueStrategies(macc)
		sni, cep := currentCustom()
		if cep != "" {
			mS = append(hydra.CustomEndpointStrategies(cep), mS...) // свой адрес — первым
		}
		if sni != "" {
			// свой SNI добавляется как дополнительные стратегии (первыми), а не подменяет все: так
			// остальное многообразие параметров, которым Гидра учится, не пропадает
			n := 8
			if n > len(mS) {
				n = len(mS)
			}
			var extra []hydra.Strategy
			for _, s0 := range mS[:n] {
				q := map[string]string{}
				for k, v := range s0.Params {
					q[k] = v
				}
				q["sni"] = sni
				extra = append(extra, hydra.Strategy{ID: s0.ID + "@" + sni, Transport: s0.Transport, Params: q})
			}
			mS = append(extra, mS...)
		}
	}
	if wacc != nil {
		wS = hydra.WGStrategies(wacc)
	}
	onlyMasque := currentProtocol() == "masque" && len(mS) > 0
	onlyWG := currentProtocol() == "wg" && len(wS) > 0
	allow := func(s hydra.Strategy) bool {
		return !(onlyMasque && s.Transport != "masque") && !(onlyWG && s.Transport != "wg")
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
	cfg.DropV6 = stripMask(acc.AddrV6) == "" || !currentIPv6()
	cfg.ServiceGate = currentGate()
	cfg.NetAlive = realNetAlive
	cfg.Allow = allow
	cfg.NetState = realNetState
	cfg.WLScan = realWLScan
	cfg.CanRun = func(s hydra.Strategy) bool { return wgp.CanRun(s) } // wgp может быть nil: метод это учитывает
	cfg.Parallel = currentParallel()

	e := hydra.NewEngine(os.NewFile(uintptr(tunFd), "tun"), cfg)
	ctx, cancel := context.WithCancel(context.Background())
	vpnEngine, vpnCancel = e, cancel
	go func() {
		defer func() {
			if r := recover(); r != nil { // паника движка не должна ронять приложение: служба поднимет его заново
				hydra.Logf("💥 паника движка: %v", r)
			}
			mem.Save()
			vpnMu.Lock()
			if vpnEngine == e {
				vpnEngine, vpnCancel = nil, nil
			}
			vpnMu.Unlock()
		}()
		e.Run(ctx)
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
	polMu.Lock()
	nk := netKey
	polMu.Unlock()
	if e := vpnEngine; e != nil {
		out += e.Stats()
		out += e.PoolSummary(nk)
		out += vpnWG.Info()
		out += vpnMem.Reasons(nk)
	} else {
		out += "движок не запущен\n"
	}
	out += netStateInfo()
	if m := vpnMem; m != nil {
		out += m.Summary(nk, 15)
		out += "🧠 что Гидра знает об этой сети (" + nk + "): какие сервисы доходят через какие стратегии\n" + m.ServiceMatrix(nk)
		if e := vpnEngine; e != nil {
			if bl := e.BadColoList(nk); len(bl) > 0 {
				out += "  плохие дата-центры (Telegram не доходит): " + strings.Join(bl, ", ") + "\n"
			}
		}
	}
	return out
}

// TestFailover имитирует отказ основного туннеля, чтобы проверить переход на горячий резерв.
func TestFailover() {
	vpnMu.Lock()
	e := vpnEngine
	vpnMu.Unlock()
	if e != nil {
		e.TestFailover()
	}
}

// ServiceCheck проверяет через действующий туннель доступность Telegram и других сервисов.
func ServiceCheck() string {
	vpnMu.Lock()
	e := vpnEngine
	vpnMu.Unlock()
	if e == nil {
		return "Гидра не запущена\n"
	}
	res := e.ServiceCheck(context.Background())
	hydra.Logf("🔎 проверка сервисов через туннель:\n%s", res)
	return res
}

// GetJournalFull возвращает журнал из файла (с прошлыми запусками); если файла нет — из памяти.
func GetJournalFull(n int) string {
	if s := hydra.JournalFileTail(n); s != "" {
		return s
	}
	return hydra.JournalText(n)
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

putv "$GODIR/outage.go" <<'HYDRA_EOF'
package hydra

import (
	"context"
	"strings"
	"time"
)

const wlMessage = "🛑 Белые списки: оператор пропускает только российские сайты, Cloudflare сейчас недоступен. Подключусь сам, когда ограничения снимут"

// netState — доступен ли зарубежный интернет: "ok", "whitelist" (отвечают только российские адреса) или "dead".
func (e *Engine) netState() string {
	if e.cfg.NetState == nil {
		return "ok"
	}
	return e.cfg.NetState()
}

func (e *Engine) sleepOrNet(ctx context.Context, d time.Duration) {
	select {
	case <-ctx.Done():
	case <-e.cfg.NetChanged:
	case <-time.After(d):
	}
}

func (e *Engine) noteTry(id string) {
	e.mu.Lock()
	if e.tried == nil {
		e.tried = map[string]time.Time{}
	}
	e.tried[id] = time.Now()
	e.mu.Unlock()
}

func (e *Engine) recentlyTried(id string, d time.Duration) bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	t, ok := e.tried[id]
	return ok && time.Since(t) < d
}

// outageStep обрабатывает «нет зарубежного интернета». wait=true — подключаться сейчас бессмысленно
// (уже подождали, надо перечитать состояние). Иначе возвращает дополнительные стратегии для режима белых списков.
func (e *Engine) outageStep(ctx context.Context, st string) (extra []Strategy, wait bool) {
	e.inOutage = true
	if st == "dead" {
		e.setStatus(Status{State: "reconnecting", Message: "нет интернета — жду сеть"})
		e.waitOnline(ctx)
		return nil, true
	}
	if !e.outageLogged {
		e.outageLogged = true
		Logf("🛑 режим белых списков: российские адреса отвечают, а Cloudflare, Google и другие зарубежные — нет")
	}
	e.setStatus(Status{State: "reconnecting", Message: wlMessage})
	// после попытки обхода даём паузу: чаще раза в минуту не сканируем
	if e.cfg.WLScan != nil && time.Since(e.wlLast) >= time.Minute {
		if pass := e.cfg.WLScan(ctx); len(pass) > 0 {
			e.wlLast = time.Now()
			Logf("🔎 к Cloudflare сквозь белые списки проходят имена (SNI): %s — пробую подключиться с ними", strings.Join(pass, ", "))
			return WhitelistStrategies(pass), false
		}
		e.wlLast = time.Now().Add(-45 * time.Second) // ничего не прошло: следующий скан через ~15 с
	}
	e.sleepOrNet(ctx, 20*time.Second)
	return nil, true
}
HYDRA_EOF

putv "$GODIR/pool.go" <<'HYDRA_EOF'
package hydra

import (
	"fmt"
	"time"
)

// Пул стратегий: Гидра сама следит, чтобы в запасе всегда было достаточно РАБОЧИХ стратегий каждого
// семейства. В фоне (пока основной туннель здоров) она проверяет непроверенные и давно не
// проверявшиеся стратегии отдельной короткой попыткой, неработающие отправляет в карантин,
// придуманные неработающие удаляет, а нехватку пополняет новыми вариантами.

var poolTargets = map[string]int{"h3": 6, "h2": 2, "wg": 2}
var poolFams = []string{"h3", "h2", "wg"}

const (
	testRetry     = 30 * time.Minute // одну стратегию не проверять чаще
	staleAfter    = 2 * time.Hour    // рабочая стратегия без успехов дольше этого — пора перепроверить
	testFast      = 90 * time.Second // период проверок, пока в пуле нехватка
	testSlow      = 20 * time.Minute // период проверок, когда пул в норме
	quarantineFor = 12 * time.Hour
)

func poolFamily(s Strategy) string {
	switch {
	case s.Transport == "wg":
		return "wg"
	case s.Params["h2"] == "1":
		return "h2"
	}
	return "h3"
}

func healthyStat(ok, fail int) bool { return ok > 0 && float64(ok)/float64(ok+fail) >= 0.4 }

// poolCounts считает по семействам: рабочие, непроверенные, в карантине.
func (e *Engine) poolCounts(nk string) (healthy, untested, dead map[string]int) {
	healthy, untested, dead = map[string]int{}, map[string]int{}, map[string]int{}
	for _, s := range e.allStrategies(nk) {
		f := poolFamily(s)
		ok, fail, _, lf, found := e.cfg.Mem.Stat(nk, s.ID)
		switch {
		case healthyStat(ok, fail):
			healthy[f]++
		case found && ok == 0 && fail >= 3 && time.Since(lf) < quarantineFor:
			dead[f]++
		default:
			untested[f]++ // не проверена или «слабая» (пара сбоев без успеха): требует проверки
		}
	}
	return
}

// hasDeficit: в каком-то семействе рабочих меньше цели, и есть что проверять.
func (e *Engine) hasDeficit(nk string) bool {
	h, u, _ := e.poolCounts(nk)
	for _, f := range poolFams {
		if h[f] < poolTargets[f] && u[f] > 0 {
			return true
		}
	}
	return false
}

// PoolSummary — состояние пула для журнала и отчёта.
func (e *Engine) PoolSummary(nk string) string {
	h, u, d := e.poolCounts(nk)
	s := "пул стратегий (рабочих/цель):"
	for _, f := range poolFams {
		s += fmt.Sprintf(" %s %d/%d", f, h[f], poolTargets[f])
	}
	s += fmt.Sprintf("; не проверено: h3 %d, h2 %d, wg %d; в карантине: h3 %d, h2 %d, wg %d; придуманных: %d\n",
		u["h3"], u["h2"], u["wg"], d["h3"], d["h2"], d["wg"], len(e.cfg.Mem.Generated(nk)))
	return s
}

// pickTest выбирает, что проверить в фоне: сначала непроверенные из семейства с нехваткой,
// затем самую «давнюю» рабочую, затем стратегию, отсидевшую карантин.
func (e *Engine) pickTest(nk string, exclude map[string]bool, blocked map[string]time.Time, tested map[string]time.Time) (Strategy, string, bool) {
	healthy, untested, _ := e.poolCounts(nk)
	all := e.cfg.Mem.Rank(nk, e.allStrategies(nk))
	elig := func(s Strategy) bool {
		if exclude[s.ID] {
			return false
		}
		if t, ok := tested[s.ID]; ok && time.Since(t) < testRetry {
			return false
		}
		if e.recentlyTried(s.ID, testRetry) || e.cfg.Mem.EndpointDead(nk, s.ID) || (e.cfg.CanRun != nil && !e.cfg.CanRun(s)) || e.knownBlocked(nk, s) {
			return false
		}
		ep := s.Params["endpoint"]
		if until, ok := blocked[hostOnly(ep)]; ep != "" && ok && time.Now().Before(until) {
			return false
		}
		return !e.cfg.Mem.Doomed(nk, s.ID)
	}
	// 1) нехватка: пробуем непроверенные из самого обделённого семейства
	best, bestDef := "", 0.0
	for _, f := range []string{"wg", "h2", "h3"} {
		t := poolTargets[f]
		if def := float64(t-healthy[f]) / float64(t); def > bestDef && untested[f] > 0 {
			best, bestDef = f, def
		}
	}
	if best != "" {
		for _, s := range all {
			ok, fail, _, _, _ := e.cfg.Mem.Stat(nk, s.ID)
			if poolFamily(s) == best && elig(s) && !healthyStat(ok, fail) {
				return s, "нехватка " + best, true
			}
		}
	}
	// 2) пул в норме: перепроверяем самую давнюю рабочую
	var stale Strategy
	var staleAt time.Time
	haveStale := false
	for _, s := range all {
		ok, fail, lastOK, _, found := e.cfg.Mem.Stat(nk, s.ID)
		if !found || !healthyStat(ok, fail) || !elig(s) || time.Since(lastOK) < staleAfter {
			continue
		}
		if !haveStale || lastOK.Before(staleAt) {
			stale, staleAt, haveStale = s, lastOK, true
		}
	}
	if haveStale {
		return stale, "перепроверка рабочей", true
	}
	// 3) вышедшие из карантина получают второй шанс
	for _, s := range all {
		ok, fail, _, lf, found := e.cfg.Mem.Stat(nk, s.ID)
		if found && ok == 0 && fail >= 3 && time.Since(lf) >= quarantineFor && elig(s) {
			return s, "после карантина", true
		}
	}
	return Strategy{}, "", false
}

// familyPresent — какие семейства стратегий вообще есть в списке (например, при протоколе «MASQUE» WireGuard нет).
func (e *Engine) familyPresent(nk string) map[string]bool {
	out := map[string]bool{}
	for _, s := range e.allStrategies(nk) {
		out[poolFamily(s)] = true
	}
	return out
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

// buildTCPTo строит TCP-пакет к произвольному адресу и порту (проверка доступности сервисов через туннель).
func buildTCPTo(src, dst net.IP, sport, dport uint16, seq, ack uint32, flags byte, id uint16, withMSS bool) []byte {
	s4, d4 := src.To4(), dst.To4()
	if s4 == nil || d4 == nil {
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
	copy(p[16:20], d4)
	binary.BigEndian.PutUint16(p[10:], ipChecksum(p[:20]))
	t := p[20:]
	binary.BigEndian.PutUint16(t[0:], sport)
	binary.BigEndian.PutUint16(t[2:], dport)
	binary.BigEndian.PutUint32(t[4:], seq)
	binary.BigEndian.PutUint32(t[8:], ack)
	t[12] = byte(tcpLen/4) << 4
	t[13] = flags
	binary.BigEndian.PutUint16(t[14:], 65535)
	if withMSS {
		t[20], t[21], t[22], t[23] = 2, 4, 0x04, 0xD8 // MSS 1240
	}
	binary.BigEndian.PutUint16(t[16:], tcpChecksum(s4, d4, t))
	return p
}

func BuildTCPSynTo(src, dst net.IP, sport, dport uint16, seq uint32, id uint16) []byte {
	return buildTCPTo(src, dst, sport, dport, seq, 0, 0x02, id, true)
}

func BuildTCPRstTo(src, dst net.IP, sport, dport uint16, seq uint32, id uint16) []byte {
	return buildTCPTo(src, dst, sport, dport, seq, 0, 0x04, id, false)
}

// ParseTCPSynAckFrom: это SYN-ACK от from:fport на наш порт dport с ожидаемым ack?
func ParseTCPSynAckFrom(pkt []byte, from net.IP, fport, dport uint16, wantAck uint32) bool {
	if len(pkt) < 40 || pkt[0]>>4 != 4 || pkt[9] != 6 {
		return false
	}
	ihl := int(pkt[0]&0x0f) * 4
	if ihl < 20 || len(pkt) < ihl+20 || !net.IP(pkt[12:16]).Equal(from) {
		return false
	}
	t := pkt[ihl:]
	if binary.BigEndian.Uint16(t[0:]) != fport || binary.BigEndian.Uint16(t[2:]) != dport {
		return false
	}
	if t[13]&0x12 != 0x12 { // SYN+ACK
		return false
	}
	return binary.BigEndian.Uint32(t[8:]) == wantAck
}

// BuildDNSQueryA строит IPv4-пакет с DNS-запросом A-записи для host к probeDst (1.1.1.1:53).
// nil, если src не IPv4 или имя некорректно. Запрос идёт внутри туннеля, поэтому DNS оператора его не видит.
func BuildDNSQueryA(src net.IP, srcPort, id uint16, host string) []byte {
	s4 := src.To4()
	if s4 == nil {
		return nil
	}
	dns := []byte{byte(id >> 8), byte(id), 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0}
	for _, label := range strings.Split(strings.TrimSuffix(host, "."), ".") {
		if len(label) == 0 || len(label) > 63 {
			return nil
		}
		dns = append(dns, byte(len(label)))
		dns = append(dns, label...)
	}
	dns = append(dns, 0, 0, 1, 0, 1) // тип A, класс IN
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
	copy(p[28:], dns)
	return p
}

// ParseAReply разбирает ответ на BuildDNSQueryA, пришедший на порт dstPort. В res первый IPv4-адрес
// из ответа либо "rcode=nxdomain" (имени нет), "rcode=err" (ошибка DNS), "rcode=noA" (нет A-записи).
func ParseAReply(pkt []byte, dstPort uint16) (id uint16, res string, ok bool) {
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
	if len(dns) < 12 || dns[2]&0x80 == 0 {
		return
	}
	id = binary.BigEndian.Uint16(dns[0:])
	if rc := dns[3] & 0x0f; rc == 3 {
		return id, "rcode=nxdomain", true
	} else if rc != 0 {
		return id, "rcode=err", true
	}
	qd := int(binary.BigEndian.Uint16(dns[4:]))
	an := int(binary.BigEndian.Uint16(dns[6:]))
	off := 12
	for i := 0; i < qd; i++ {
		off = skipName(dns, off)
		if off < 0 || off+4 > len(dns) {
			return id, "rcode=err", true
		}
		off += 4
	}
	for i := 0; i < an; i++ {
		off = skipName(dns, off)
		if off < 0 || off+10 > len(dns) {
			break
		}
		typ := binary.BigEndian.Uint16(dns[off:])
		rdlen := int(binary.BigEndian.Uint16(dns[off+8:]))
		off += 10
		if off+rdlen > len(dns) {
			break
		}
		if typ == 1 && rdlen == 4 {
			return id, net.IP(dns[off : off+4]).String(), true
		}
		off += rdlen
	}
	return id, "rcode=noA", true
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
	"errors"
	"fmt"
	"strings"
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
	tester bool // короткая фоновая проверка, а не резерв
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
	go func() {
		defer func() {
			if r := recover(); r != nil { // сбой клиента туннеля не должен ронять приложение
				Logf("💥 паника в клиенте туннеля %s: %v", s.ID, r)
				a.errc <- fmt.Errorf("паника: %v", r)
			}
		}()
		a.errc <- e.cfg.Runner(actx, a.dev, s)
	}()
	return a
}

// verify ждёт, пока попытка поднимется, и проверяет её: ответ туннеля, дата-центр, реальный TCP.
func (e *Engine) verify(nk string, a *attempt) (bool, outcome) {
	s := a.s
	e.noteTry(s.ID)
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
			if errors.Is(err, ErrRunnerBusy) {
				return false, outcome{reason: "остановка"} // не провал стратегии: клиент просто был занят
			}
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
		if x := a.dev.extra(); x != "" {
			msg += " [" + x + "]"
		}
		Logf("   ✘ %s: %s", s.ID, msg)
		return false, e.fail(nk, s, msg)
	}
	Logf("   %s: туннель ответил за %d мс, дата-центр Cloudflare: %s", s.ID, rtt.Milliseconds(), colo)
	e.cfg.Mem.NoteColo(nk, s.Params["endpoint"], colo)
	if !e.coloAllowed(nk, colo) {
		Logf("   ✘ %s: дата-центр %s запрещён (настройками или потому, что через него не доходит Telegram)", s.ID, colo)
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
	e.cfg.Mem.RecordGenes(nk, s, true)
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
			if e.recentlyTried(s.ID, standbyRetry) || (e.cfg.CanRun != nil && !e.cfg.CanRun(s)) || e.knownBlocked(nk, s) {
				continue
			}
			ep := s.Params["endpoint"]
			if until, ok := blockedFor(blocked, hostOnly(ep)); ep != "" && ok && time.Now().Before(until) {
				continue
			}
			if e.cfg.Mem.Doomed(nk, s.ID) || e.cfg.Mem.EndpointDead(nk, s.ID) {
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
	taken := make([]bool, len(cands))
	res := make(chan verdict, 64)
	live := 0
	var all []*attempt
	defer func() {
		for _, a := range all {
			a.cancel()
		}
	}()

	// remaining — остались ли непробованные кандидаты (даже те, которые пока нельзя запускать)
	remaining := func() bool {
		for _, t := range taken {
			if !t {
				return true
			}
		}
		return false
	}
	nextCand := func() (Strategy, bool) {
		for i, s := range cands {
			if taken[i] {
				continue
			}
			if s.ID == skip {
				taken[i] = true
				continue
			}
			ep := s.Params["endpoint"]
			if until, ok := blockedFor(blocked, hostOnly(ep)); ep != "" && ok && time.Now().Before(until) {
				taken[i] = true
				skipped++
				continue
			}
			if e.knownBlocked(nk, s) {
				taken[i] = true // этот адрес в этой сети попадает в запрещённый дата-центр: не тратим время
				skipped++
				sawBlocked = true
				continue
			}
			if e.cfg.CanRun != nil && !e.cfg.CanRun(s) {
				continue // например, единственный аккаунт WireGuard занят: попробуем позже
			}
			taken[i] = true
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
				blocked[prefix24(hostOnly(ep))] = time.Now().Add(10 * time.Minute)
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
				} else if !remaining() {
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
				} else if !remaining() {
					return
				}
			}
		}
	}

	// ---- победитель ----
	p.dev.promote()
	e.active.Store(p.dev)
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
	bad, sbBad, ticks, tcpBad := 0, 0, 0, 0
	nextSb := time.Now().Add(3 * time.Second)
	lastLearn := time.Time{}
	lastBeat := time.Now()
	gateCh := make(chan string, 1)
	if e.cfg.ServiceGate {
		go e.serviceGate(ctx, nk, p, gateCh)
	}
	testing := 0
	testedAt := map[string]time.Time{}
	lastTest := time.Now().Add(-time.Hour)
	lastGen := time.Time{}
	lastPrune := time.Now()
	launchTester := func(s Strategy) {
		a := e.startAttempt(ctx, s, false)
		a.tester = true
		all = append(all, a)
		testing++
		go func() {
			ok, o := e.verify(nk, a)
			res <- verdict{a, ok, o}
		}()
	}

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
		e.active.Store(p.dev)
		colo = p.colo
		e.setStatus(Status{State: "up", Strategy: p.s.ID, Colo: colo, RTT: p.rtt, Message: msg})
		e.emit("connected", p.s.ID, colo)
		if e.cfg.ServiceGate {
			go e.serviceGate(ctx, nk, p, gateCh)
		}
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
		case why := <-gateCh:
			Logf("🚫 %s", why)
			e.noteBadColo(nk, p.colo)
			if sb != nil && sb.colo != p.colo && failover(why) {
				continue
			}
			lose(why)
			return
		case <-e.testFail:
			Logf("🧪 тест: имитирую отказ основного туннеля %s", p.s.ID)
			if sb == nil {
				Logf("🧪 резерва сейчас нет — переключаться некуда (резерв поднимается в течение минуты после подключения)")
				continue
			}
			t0 := time.Now()
			if failover("тест переключения") {
				Logf("🧪 переключение выполнено за %d мс", time.Since(t0).Milliseconds())
			}
		case v := <-res:
			if v.a.tester {
				testing--
				v.a.cancel()
				if v.ok {
					Logf("🔬 %s: работает (дата-центр %s, %d мс)", v.a.s.ID, v.a.colo, v.a.rtt.Milliseconds())
				} else if v.o.reason != "остановка" {
					Logf("🔬 %s: не работает — %s", v.a.s.ID, v.o.reason)
					if v.o.coloBlocked != "" {
						noteFail(v)
					}
				}
				Logf("🔬 %s", strings.TrimSpace(e.PoolSummary(nk)))
				continue
			}
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
			e.noteProbe(err == nil)
			if err != nil && p.ctx.Err() == nil {
				// единичная потеря UDP — ещё не отказ: сразу повторяем пробу
				r, c, err = p.dev.probe(p.ctx, 1500*time.Millisecond)
				e.noteProbe(err == nil)
			}
			if err == nil && e.cfg.TCPCheck && ticks%5 == 0 {
				// одна неудачная TCP-проба при живой UDP-пробе — не отказ; считаем только две подряд
				if _, terr := p.dev.tcpProbe(p.ctx, e.cfg.TCPTimeout); terr != nil {
					tcpBad++
					if tcpBad >= 2 {
						err = terr
					}
				} else {
					tcpBad = 0
				}
			}
			limit := e.cfg.BadProbes
			if sb != nil && limit > 2 {
				limit = 2 // резерв готов — переходим на него быстрее
			}
			if err != nil {
				bad++
				Logf("   проба без ответа (%d из %d, в туннель ушло %d пакетов, пришло %d): %v", bad, limit,
					atomic.LoadInt32(&p.dev.sent), atomic.LoadInt32(&p.dev.recv), err)
				if bad >= limit {
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
					if !e.coloAllowed(nk, c) {
						e.cfg.Mem.Record(nk, p.s.ID, false, 0)
						e.emit("colo_blocked", p.s.ID, c)
						Logf("✘ дата-центр %s запрещён", c)
						sawBlocked = true
						if ep := p.s.Params["endpoint"]; ep != "" {
							blocked[hostOnly(ep)] = time.Now().Add(10 * time.Minute)
				blocked[prefix24(hostOnly(ep))] = time.Now().Add(10 * time.Minute)
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
				_, _, perr := sb.dev.probe(sb.ctx, 3*time.Second)
				if perr != nil && sb.ctx.Err() == nil {
					_, _, perr = sb.dev.probe(sb.ctx, 3*time.Second) // на мобильной сети пробы к резерву бывают медленными
				}
				if perr != nil {
					sbBad++
					Logf("   резерв %s не ответил на пробу (%d из %d)", sb.s.ID, sbBad, e.cfg.BadProbes)
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
			if time.Since(lastBeat) > 10*time.Minute {
				lastBeat = time.Now()
				sbName := "нет"
				if sb != nil {
					sbName = sb.s.ID
				}
				total, lost := e.probeStats()
				Logf("💓 в порядке: основной %s, дата-центр %s, пинг %d мс, резерв: %s, проб потеряно %d из %d",
					p.s.ID, colo, r.Milliseconds(), sbName, lost, total)
				Logf("💓 %s", strings.TrimSpace(e.PoolSummary(nk)))
			}
			if time.Since(lastPrune) > 10*time.Minute {
				lastPrune = time.Now()
				if n := e.cfg.Mem.Prune(nk); n > 0 {
					Logf("🧹 убрал %d придуманных способов, которые не работают", n)
				}
			}
			// обслуживание пула: фоновая проверка запасных стратегий и пополнение нехватки
			if testing == 0 && bad == 0 && time.Since(p.start) > 20*time.Second {
				every := testSlow
				if e.hasDeficit(nk) {
					every = testFast
				}
				if time.Since(lastTest) >= every {
					excl := map[string]bool{p.s.ID: true}
					if sb != nil {
						excl[sb.s.ID] = true
					}
					if s, why, ok := e.pickTest(nk, excl, blocked, testedAt); ok {
						lastTest = time.Now()
						testedAt[s.ID] = lastTest
						Logf("🔬 проверяю запасную стратегию (%s): %s", why, s.ID)
						launchTester(s)
					} else if time.Since(lastGen) > 5*time.Minute {
						lastGen = time.Now()
						h, u, _ := e.poolCounts(nk)
						present := e.familyPresent(nk)
						for _, f := range poolFams {
							if present[f] && h[f] < poolTargets[f] && u[f] == 0 {
								e.grow(nk)
								break
							}
						}
					}
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
		RootCAs:    rootPool(),
		Time:       tlsNow,
	})
	if err := tc.HandshakeContext(ctx); err != nil {
		raw.Close()
		if isCertTimeError(err) && learnClockSkew(ctx, rt.d.Dial) {
			return r.dialTLS(ctx, rt, addr) // часы устройства неверны: повторяем с поправкой
		}
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

putv "$GODIR/roots.pem" <<'HYDRA_EOF'
-----BEGIN CERTIFICATE-----
MIIH0zCCBbugAwIBAgIIXsO3pkN/pOAwDQYJKoZIhvcNAQEFBQAwQjESMBAGA1UE
AwwJQUNDVlJBSVoxMRAwDgYDVQQLDAdQS0lBQ0NWMQ0wCwYDVQQKDARBQ0NWMQsw
CQYDVQQGEwJFUzAeFw0xMTA1MDUwOTM3MzdaFw0zMDEyMzEwOTM3MzdaMEIxEjAQ
BgNVBAMMCUFDQ1ZSQUlaMTEQMA4GA1UECwwHUEtJQUNDVjENMAsGA1UECgwEQUND
VjELMAkGA1UEBhMCRVMwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCb
qau/YUqXry+XZpp0X9DZlv3P4uRm7x8fRzPCRKPfmt4ftVTdFXxpNRFvu8gMjmoY
HtiP2Ra8EEg2XPBjs5BaXCQ316PWywlxufEBcoSwfdtNgM3802/J+Nq2DoLSRYWo
G2ioPej0RGy9ocLLA76MPhMAhN9KSMDjIgro6TenGEyxCQ0jVn8ETdkXhBilyNpA
lHPrzg5XPAOBOp0KoVdDaaxXbXmQeOW1tDvYvEyNKKGno6e6Ak4l0Squ7a4DIrhr
IA8wKFSVf+DuzgpmndFALW4ir50awQUZ0m/A8p/4e7MCQvtQqR0tkw8jq8bBD5L/
0KIV9VMJcRz/RROE5iZe+OCIHAr8Fraocwa48GOEAqDGWuzndN9wrqODJerWx5eH
k6fGioozl2A3ED6XPm4pFdahD9GILBKfb6qkxkLrQaLjlUPTAYVtjrs78yM2x/47
4KElB0iryYl0/wiPgL/AlmXz7uxLaL2diMMxs0Dx6M/2OLuc5NF/1OVYm3z61PMO
m3WR5LpSLhl+0fXNWhn8ugb2+1KoS5kE3fj5tItQo05iifCHJPqDQsGH+tUtKSpa
cXpkatcnYGMN285J9Y0fkIkyF/hzQ7jSWpOGYdbhdQrqeWZ2iE9x6wQl1gpaepPl
uUsXQA+xtrn13k/c4LOsOxFwYIRKQ26ZIMApcQrAZQIDAQABo4ICyzCCAscwfQYI
KwYBBQUHAQEEcTBvMEwGCCsGAQUFBzAChkBodHRwOi8vd3d3LmFjY3YuZXMvZmls
ZWFkbWluL0FyY2hpdm9zL2NlcnRpZmljYWRvcy9yYWl6YWNjdjEuY3J0MB8GCCsG
AQUFBzABhhNodHRwOi8vb2NzcC5hY2N2LmVzMB0GA1UdDgQWBBTSh7Tj3zcnk1X2
VuqB5TbMjB4/vTAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFNKHtOPfNyeT
VfZW6oHlNsyMHj+9MIIBcwYDVR0gBIIBajCCAWYwggFiBgRVHSAAMIIBWDCCASIG
CCsGAQUFBwICMIIBFB6CARAAQQB1AHQAbwByAGkAZABhAGQAIABkAGUAIABDAGUA
cgB0AGkAZgBpAGMAYQBjAGkA8wBuACAAUgBhAO0AegAgAGQAZQAgAGwAYQAgAEEA
QwBDAFYAIAAoAEEAZwBlAG4AYwBpAGEAIABkAGUAIABUAGUAYwBuAG8AbABvAGcA
7QBhACAAeQAgAEMAZQByAHQAaQBmAGkAYwBhAGMAaQDzAG4AIABFAGwAZQBjAHQA
cgDzAG4AaQBjAGEALAAgAEMASQBGACAAUQA0ADYAMAAxADEANQA2AEUAKQAuACAA
QwBQAFMAIABlAG4AIABoAHQAdABwADoALwAvAHcAdwB3AC4AYQBjAGMAdgAuAGUA
czAwBggrBgEFBQcCARYkaHR0cDovL3d3dy5hY2N2LmVzL2xlZ2lzbGFjaW9uX2Mu
aHRtMFUGA1UdHwROMEwwSqBIoEaGRGh0dHA6Ly93d3cuYWNjdi5lcy9maWxlYWRt
aW4vQXJjaGl2b3MvY2VydGlmaWNhZG9zL3JhaXphY2N2MV9kZXIuY3JsMA4GA1Ud
DwEB/wQEAwIBBjAXBgNVHREEEDAOgQxhY2N2QGFjY3YuZXMwDQYJKoZIhvcNAQEF
BQADggIBAJcxAp/n/UNnSEQU5CmH7UwoZtCPNdpNYbdKl02125DgBS4OxnnQ8pdp
D70ER9m+27Up2pvZrqmZ1dM8MJP1jaGo/AaNRPTKFpV8M9xii6g3+CfYCS0b78gU
JyCpZET/LtZ1qmxNYEAZSUNUY9rizLpm5U9EelvZaoErQNV/+QEnWCzI7UiRfD+m
AM/EKXMRNt6GGT6d7hmKG9Ww7Y49nCrADdg9ZuM8Db3VlFzi4qc1GwQA9j9ajepD
vV+JHanBsMyZ4k0ACtrJJ1vnE5Bc5PUzolVt3OAJTS+xJlsndQAJxGJ3KQhfnlms
tn6tn1QwIgPBHnFk/vk4CpYY3QIUrCPLBhwepH2NDd4nQeit2hW3sCPdK6jT2iWH
7ehVRE2I9DZ+hJp4rPcOVkkO1jMl1oRQQmwgEh0q1b688nCBpHBgvgW1m54ERL5h
I6zppSSMEYCUWqKiuUnSwdzRp+0xESyeGabu4VXhwOrPDYTkF7eifKXeVSUG7szA
h1xA2syVP1XgNce4hL60Xc16gwFy7ofmXx2utYXGJt/mwZrpHgJHnyqobalbz+xF
d3+YJ5oyXSrjhO7FmGYvliAd3djDJ9ew+f7Zfc3Qn48LFFhRny+Lwzgt3uiP1o2H
pPVWQxaZLPSkVrQ0uGE3ycJYgBugl6H8WY3pEfbRD0tVNEYqi4Y7
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFgzCCA2ugAwIBAgIPXZONMGc2yAYdGsdUhGkHMA0GCSqGSIb3DQEBCwUAMDsx
CzAJBgNVBAYTAkVTMREwDwYDVQQKDAhGTk1ULVJDTTEZMBcGA1UECwwQQUMgUkFJ
WiBGTk1ULVJDTTAeFw0wODEwMjkxNTU5NTZaFw0zMDAxMDEwMDAwMDBaMDsxCzAJ
BgNVBAYTAkVTMREwDwYDVQQKDAhGTk1ULVJDTTEZMBcGA1UECwwQQUMgUkFJWiBG
Tk1ULVJDTTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALpxgHpMhm5/
yBNtwMZ9HACXjywMI7sQmkCpGreHiPibVmr75nuOi5KOpyVdWRHbNi63URcfqQgf
BBckWKo3Shjf5TnUV/3XwSyRAZHiItQDwFj8d0fsjz50Q7qsNI1NOHZnjrDIbzAz
WHFctPVrbtQBULgTfmxKo0nRIBnuvMApGGWn3v7v3QqQIecaZ5JCEJhfTzC8PhxF
tBDXaEAUwED653cXeuYLj2VbPNmaUtu1vZ5Gzz3rkQUCwJaydkxNEJY7kvqcfw+Z
374jNUUeAlz+taibmSXaXvMiwzn15Cou08YfxGyqxRxqAQVKL9LFwag0Jl1mpdIC
IfkYtwb1TplvqKtMUejPUBjFd8g5CSxJkjKZqLsXF3mwWsXmo8RZZUc1g16p6DUL
mbvkzSDGm0oGObVo/CK67lWMK07q87Hj/LaZmtVC+nFNCM+HHmpxffnTtOmlcYF7
wk5HlqX2doWjKI/pgG6BU6VtX7hI+cL5NqYuSf+4lsKMB7ObiFj86xsc3i1w4peS
MKGJ47xVqCfWS+2QrYv6YyVZLag13cqXM7zlzced0ezvXg5KkAYmY6252TUtB7p2
ZSysV4999AeU14ECll2jB0nVetBX+RvnU0Z1qrB5QstocQjpYL05ac70r8NWQMet
UqIJ5G+GR4of6ygnXYMgrwTJbFaai0b1AgMBAAGjgYMwgYAwDwYDVR0TAQH/BAUw
AwEB/zAOBgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYEFPd9xf3E6Jobd2Sn9R2gzL+H
YJptMD4GA1UdIAQ3MDUwMwYEVR0gADArMCkGCCsGAQUFBwIBFh1odHRwOi8vd3d3
LmNlcnQuZm5tdC5lcy9kcGNzLzANBgkqhkiG9w0BAQsFAAOCAgEAB5BK3/MjTvDD
nFFlm5wioooMhfNzKWtN/gHiqQxjAb8EZ6WdmF/9ARP67Jpi6Yb+tmLSbkyU+8B1
RXxlDPiyN8+sD8+Nb/kZ94/sHvJwnvDKuO+3/3Y3dlv2bojzr2IyIpMNOmqOFGYM
LVN0V2Ue1bLdI4E7pWYjJ2cJj+F3qkPNZVEI7VFY/uY5+ctHhKQV8Xa7pO6kO8Rf
77IzlhEYt8llvhjho6Tc+hj507wTmzl6NLrTQfv6MooqtyuGC2mDOL7Nii4LcK2N
JpLuHvUBKwrZ1pebbuCoGRw6IYsMHkCtA+fdZn71uSANA+iW+YJF1DngoABd15jm
fZ5nc8OaKveri6E6FO80vFIOiZiaBECEHX5FaZNXzuvO+FB8TxxuBEOb+dY7Ixjp
6o7RTUaN8Tvkasq6+yO3m/qZASlaWFot4/nUbQ4mrcFuNLwy+AwF+mWj2zs3gyLp
1txyM/1d8iC9djwj2ij3+RvrWWTV3F9yfiD8zYm1kGdNYno/Tq0dwzn+evQoFt9B
9kiABdcPUXmsEKvU7ANm5mqwujGSQkBqvjrTcuFqN1W8rB2Vt2lh8kORdOag0wok
RqEIr9baRRmW1FMdW4R58MD3R++Lj8UGrp1MYp3/RgT408m2ECVAdf4WqslKYIYv
uu8wd+RU4riEmViAqhOLUTpPSPaLtrM=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICbjCCAfOgAwIBAgIQYvYybOXE42hcG2LdnC6dlTAKBggqhkjOPQQDAzB4MQsw
CQYDVQQGEwJFUzERMA8GA1UECgwIRk5NVC1SQ00xDjAMBgNVBAsMBUNlcmVzMRgw
FgYDVQRhDA9WQVRFUy1RMjgyNjAwNEoxLDAqBgNVBAMMI0FDIFJBSVogRk5NVC1S
Q00gU0VSVklET1JFUyBTRUdVUk9TMB4XDTE4MTIyMDA5MzczM1oXDTQzMTIyMDA5
MzczM1oweDELMAkGA1UEBhMCRVMxETAPBgNVBAoMCEZOTVQtUkNNMQ4wDAYDVQQL
DAVDZXJlczEYMBYGA1UEYQwPVkFURVMtUTI4MjYwMDRKMSwwKgYDVQQDDCNBQyBS
QUlaIEZOTVQtUkNNIFNFUlZJRE9SRVMgU0VHVVJPUzB2MBAGByqGSM49AgEGBSuB
BAAiA2IABPa6V1PIyqvfNkpSIeSX0oNnnvBlUdBeh8dHsVnyV0ebAAKTRBdp20LH
sbI6GA60XYyzZl2hNPk2LEnb80b8s0RpRBNm/dfF/a82Tc4DTQdxz69qBdKiQ1oK
Um8BA06Oi6NCMEAwDwYDVR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYwHQYD
VR0OBBYEFAG5L++/EYZg8k/QQW6rcx/n0m5JMAoGCCqGSM49BAMDA2kAMGYCMQCu
SuMrQMN0EfKVrRYj3k4MGuZdpSRea0R7/DjiT8ucRRcRTBQnJlU5dUoDzBOQn5IC
MQD6SmxgiHPz7riYYqnOK8LZiqZwMR2vsJRM60/G49HzYqc8/5MuB1xJAWdpEgJy
v+c=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
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
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFuzCCA6OgAwIBAgIIVwoRl0LE48wwDQYJKoZIhvcNAQELBQAwazELMAkGA1UE
BhMCSVQxDjAMBgNVBAcMBU1pbGFuMSMwIQYDVQQKDBpBY3RhbGlzIFMucC5BLi8w
MzM1ODUyMDk2NzEnMCUGA1UEAwweQWN0YWxpcyBBdXRoZW50aWNhdGlvbiBSb290
IENBMB4XDTExMDkyMjExMjIwMloXDTMwMDkyMjExMjIwMlowazELMAkGA1UEBhMC
SVQxDjAMBgNVBAcMBU1pbGFuMSMwIQYDVQQKDBpBY3RhbGlzIFMucC5BLi8wMzM1
ODUyMDk2NzEnMCUGA1UEAwweQWN0YWxpcyBBdXRoZW50aWNhdGlvbiBSb290IENB
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAp8bEpSmkLO/lGMWwUKNv
UTufClrJwkg4CsIcoBh/kbWHuUA/3R1oHwiD1S0eiKD4j1aPbZkCkpAW1V8IbInX
4ay8IMKx4INRimlNAJZaby/ARH6jDuSRzVju3PvHHkVH3Se5CAGfpiEd9UEtL0z9
KK3giq0itFZljoZUj5NDKd45RnijMCO6zfB9E1fAXdKDa0hMxKufgFpbOr3JpyI/
gCczWw63igxdBzcIy2zSekciRDXFzMwujt0q7bd9Zg1fYVEiVRvjRuPjPdA1Yprb
rxTIW6HMiRvhMCb8oJsfgadHHwTrozmSBp+Z07/T6k9QnBn+locePGX2oxgkg4YQ
51Q+qDp2JE+BIcXjDwL4k5RHILv+1A7TaLndxHqEguNTVHnd25zS8gebLra8Pu2F
be8lEfKXGkJh90qX6IuxEAf6ZYGyojnP9zz/GPvG8VqLWeICrHuS0E4UT1lF9gxe
KF+w6D9Fz8+vm2/7hNN3WpVvrJSEnu68wEqPSpP4RCHiMUVhUE4Q2OM1fEwZtN4F
v6MGn8i1zeQf1xcGDXqVdFUNaBr8EBtiZJ1t4JWgw5QHVw0U5r0F+7if5t+L4sbn
fpb2U8WANFAoWPASUHEXMLrmeGO89LKtmyuy/uE5jF66CyCU3nuDuP/jVo23Eek7
jPKxwV2dpAtMK9myGPW1n0sCAwEAAaNjMGEwHQYDVR0OBBYEFFLYiDrIn3hm7Ynz
ezhwlMkCAjbQMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAUUtiIOsifeGbt
ifN7OHCUyQICNtAwDgYDVR0PAQH/BAQDAgEGMA0GCSqGSIb3DQEBCwUAA4ICAQAL
e3KHwGCmSUyIWOYdiPcUZEim2FgKDk8TNd81HdTtBjHIgT5q1d07GjLukD0R0i70
jsNjLiNmsGe+b7bAEzlgqqI0JZN1Ut6nna0Oh4lScWoWPBkdg/iaKWW+9D+a2fDz
WochcYBNy+A4mz+7+uAwTc+G02UQGRjRlwKxK3JCaKygvU5a2hi/a5iB0P2avl4V
SM0RFbnAKVy06Ij3Pjaut2L9HmLecHgQHEhb2rykOLpn7VU+Xlff1ANATIGk0k9j
pwlCCRT8AKnCgHNPLsBA2RF7SOp6AsDT6ygBJlh0wcBzIm2Tlf05fbsq4/aC4yyX
X04fkZT6/iyj2HYauE2yOE+b+h1IYHkm4vP9qdCa6HCPSXrW5b0KDtst842/6+Ok
fcvHlXHo2qN8xcL4dJIEG4aspCJTQLas/kx2z/uUMsA1n3Y/buWQbqCmJqK4LL7R
K4X9p2jIugErsWx0Hbhzlefut8cl8ABMALJ+tguLHPPAUJ4lueAI3jZm/zel0btU
ZCzJJ7VLkn5l/9Mt4blOvH+kQSGQQXemOR/qnuOf0GZvBeyqdn6/axag67XH/JJU
LysRJyU3eExRarDzzFhdFPFqSBX/wge2sY0PjlxQRrM9vwGYT7JZVEc+NHt4bVaT
LnPqZih4zR0Uv6CPLy64Lo7yFIrM6bV8+2ydDKXhlg==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIDQTCCAimgAwIBAgITBmyfz5m/jAo54vB4ikPmljZbyjANBgkqhkiG9w0BAQsF
ADA5MQswCQYDVQQGEwJVUzEPMA0GA1UEChMGQW1hem9uMRkwFwYDVQQDExBBbWF6
b24gUm9vdCBDQSAxMB4XDTE1MDUyNjAwMDAwMFoXDTM4MDExNzAwMDAwMFowOTEL
MAkGA1UEBhMCVVMxDzANBgNVBAoTBkFtYXpvbjEZMBcGA1UEAxMQQW1hem9uIFJv
b3QgQ0EgMTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALJ4gHHKeNXj
ca9HgFB0fW7Y14h29Jlo91ghYPl0hAEvrAIthtOgQ3pOsqTQNroBvo3bSMgHFzZM
9O6II8c+6zf1tRn4SWiw3te5djgdYZ6k/oI2peVKVuRF4fn9tBb6dNqcmzU5L/qw
IFAGbHrQgLKm+a/sRxmPUDgH3KKHOVj4utWp+UhnMJbulHheb4mjUcAwhmahRWa6
VOujw5H5SNz/0egwLX0tdHA114gk957EWW67c4cX8jJGKLhD+rcdqsq08p8kDi1L
93FcXmn/6pUCyziKrlA4b9v7LWIbxcceVOF34GfID5yHI9Y/QCB/IIDEgEw+OyQm
jgSubJrIqg0CAwEAAaNCMEAwDwYDVR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMC
AYYwHQYDVR0OBBYEFIQYzIU07LwMlJQuCFmcx7IQTgoIMA0GCSqGSIb3DQEBCwUA
A4IBAQCY8jdaQZChGsV2USggNiMOruYou6r4lK5IpDB/G/wkjUu0yKGX9rbxenDI
U5PMCCjjmCXPI6T53iHTfIUJrU6adTrCC2qJeHZERxhlbI1Bjjt/msv0tadQ1wUs
N+gDS63pYaACbvXy8MWy7Vu33PqUXHeeE6V/Uq2V8viTO96LXFvKWlJbYK8U90vv
o/ufQJVtMVT8QtPHRh8jrdkPSHCa2XV4cdFyQzR1bldZwgJcJmApzyMZFo6IQ6XU
5MsI+yMRQ+hDKXJioaldXgjUkK642M4UwtBV8ob2xJNDd2ZhwLnoQdeXeGADbkpy
rqXRfboQnoZsG4q5WTP468SQvvG5
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFQTCCAymgAwIBAgITBmyf0pY1hp8KD+WGePhbJruKNzANBgkqhkiG9w0BAQwF
ADA5MQswCQYDVQQGEwJVUzEPMA0GA1UEChMGQW1hem9uMRkwFwYDVQQDExBBbWF6
b24gUm9vdCBDQSAyMB4XDTE1MDUyNjAwMDAwMFoXDTQwMDUyNjAwMDAwMFowOTEL
MAkGA1UEBhMCVVMxDzANBgNVBAoTBkFtYXpvbjEZMBcGA1UEAxMQQW1hem9uIFJv
b3QgQ0EgMjCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAK2Wny2cSkxK
gXlRmeyKy2tgURO8TW0G/LAIjd0ZEGrHJgw12MBvIITplLGbhQPDW9tK6Mj4kHbZ
W0/jTOgGNk3Mmqw9DJArktQGGWCsN0R5hYGCrVo34A3MnaZMUnbqQ523BNFQ9lXg
1dKmSYXpN+nKfq5clU1Imj+uIFptiJXZNLhSGkOQsL9sBbm2eLfq0OQ6PBJTYv9K
8nu+NQWpEjTj82R0Yiw9AElaKP4yRLuH3WUnAnE72kr3H9rN9yFVkE8P7K6C4Z9r
2UXTu/Bfh+08LDmG2j/e7HJV63mjrdvdfLC6HM783k81ds8P+HgfajZRRidhW+me
z/CiVX18JYpvL7TFz4QuK/0NURBs+18bvBt+xa47mAExkv8LV/SasrlX6avvDXbR
8O70zoan4G7ptGmh32n2M8ZpLpcTnqWHsFcQgTfJU7O7f/aS0ZzQGPSSbtqDT6Zj
mUyl+17vIWR6IF9sZIUVyzfpYgwLKhbcAS4y2j5L9Z469hdAlO+ekQiG+r5jqFoz
7Mt0Q5X5bGlSNscpb/xVA1wf+5+9R+vnSUeVC06JIglJ4PVhHvG/LopyboBZ/1c6
+XUyo05f7O0oYtlNc/LMgRdg7c3r3NunysV+Ar3yVAhU/bQtCSwXVEqY0VThUWcI
0u1ufm8/0i2BWSlmy5A5lREedCf+3euvAgMBAAGjQjBAMA8GA1UdEwEB/wQFMAMB
Af8wDgYDVR0PAQH/BAQDAgGGMB0GA1UdDgQWBBSwDPBMMPQFWAJI/TPlUq9LhONm
UjANBgkqhkiG9w0BAQwFAAOCAgEAqqiAjw54o+Ci1M3m9Zh6O+oAA7CXDpO8Wqj2
LIxyh6mx/H9z/WNxeKWHWc8w4Q0QshNabYL1auaAn6AFC2jkR2vHat+2/XcycuUY
+gn0oJMsXdKMdYV2ZZAMA3m3MSNjrXiDCYZohMr/+c8mmpJ5581LxedhpxfL86kS
k5Nrp+gvU5LEYFiwzAJRGFuFjWJZY7attN6a+yb3ACfAXVU3dJnJUH/jWS5E4ywl
7uxMMne0nxrpS10gxdr9HIcWxkPo1LsmmkVwXqkLN1PiRnsn/eBG8om3zEK2yygm
btmlyTrIQRNg91CMFa6ybRoVGld45pIq2WWQgj9sAq+uEjonljYE1x2igGOpm/Hl
urR8FLBOybEfdF849lHqm/osohHUqS0nGkWxr7JOcQ3AWEbWaQbLU8uz/mtBzUF+
fUwPfHJ5elnNXkoOrJupmHN5fLT0zLm4BwyydFy4x2+IoZCn9Kr5v2c69BoVYh63
n749sSmvZ6ES8lgQGVMDMBu4Gon2nL2XA46jCfMdiyHxtN/kHNGfZQIG6lzWE7OE
76KlXIx3KadowGuuQNKotOrN8I1LOJwZmhsoVLiJkO/KdYE+HvJkJMcYr07/R54H
9jVlpNMKVv/1F2Rs76giJUmTtt8AF9pYfl3uxRuw0dFfIRDH+fO6AgonB8Xx1sfT
4PsJYGw=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIBtjCCAVugAwIBAgITBmyf1XSXNmY/Owua2eiedgPySjAKBggqhkjOPQQDAjA5
MQswCQYDVQQGEwJVUzEPMA0GA1UEChMGQW1hem9uMRkwFwYDVQQDExBBbWF6b24g
Um9vdCBDQSAzMB4XDTE1MDUyNjAwMDAwMFoXDTQwMDUyNjAwMDAwMFowOTELMAkG
A1UEBhMCVVMxDzANBgNVBAoTBkFtYXpvbjEZMBcGA1UEAxMQQW1hem9uIFJvb3Qg
Q0EgMzBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABCmXp8ZBf8ANm+gBG1bG8lKl
ui2yEujSLtf6ycXYqm0fc4E7O5hrOXwzpcVOho6AF2hiRVd9RFgdszflZwjrZt6j
QjBAMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgGGMB0GA1UdDgQWBBSr
ttvXBp43rDCGB5Fwx5zEGbF4wDAKBggqhkjOPQQDAgNJADBGAiEA4IWSoxe3jfkr
BqWTrBqYaGFy+uGh0PsceGCmQ5nFuMQCIQCcAu/xlJyzlvnrxir4tiz+OpAUFteM
YyRIHN8wfdVoOw==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIB8jCCAXigAwIBAgITBmyf18G7EEwpQ+Vxe3ssyBrBDjAKBggqhkjOPQQDAzA5
MQswCQYDVQQGEwJVUzEPMA0GA1UEChMGQW1hem9uMRkwFwYDVQQDExBBbWF6b24g
Um9vdCBDQSA0MB4XDTE1MDUyNjAwMDAwMFoXDTQwMDUyNjAwMDAwMFowOTELMAkG
A1UEBhMCVVMxDzANBgNVBAoTBkFtYXpvbjEZMBcGA1UEAxMQQW1hem9uIFJvb3Qg
Q0EgNDB2MBAGByqGSM49AgEGBSuBBAAiA2IABNKrijdPo1MN/sGKe0uoe0ZLY7Bi
9i0b2whxIdIA6GO9mif78DluXeo9pcmBqqNbIJhFXRbb/egQbeOc4OO9X4Ri83Bk
M6DLJC9wuoihKqB1+IGuYgbEgds5bimwHvouXKNCMEAwDwYDVR0TAQH/BAUwAwEB
/zAOBgNVHQ8BAf8EBAMCAYYwHQYDVR0OBBYEFNPsxzplbszh2naaVvuc84ZtV+WB
MAoGCCqGSM49BAMDA2gAMGUCMDqLIfG9fhGt0O9Yli/W651+kI0rz2ZVwyzjKKlw
CkcO8DdZEv8tmZQoTipPNU0zWgIxAOp1AE47xDqUEpHJWEadIRNyp4iciuRMStuW
1KyLa2tJElMzrdfkviT8tQp21KW8EA==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICFTCCAZugAwIBAgIQPZg7pmY9kGP3fiZXOATvADAKBggqhkjOPQQDAzBMMS4w
LAYDVQQDDCVBdG9zIFRydXN0ZWRSb290IFJvb3QgQ0EgRUNDIFRMUyAyMDIxMQ0w
CwYDVQQKDARBdG9zMQswCQYDVQQGEwJERTAeFw0yMTA0MjIwOTI2MjNaFw00MTA0
MTcwOTI2MjJaMEwxLjAsBgNVBAMMJUF0b3MgVHJ1c3RlZFJvb3QgUm9vdCBDQSBF
Q0MgVExTIDIwMjExDTALBgNVBAoMBEF0b3MxCzAJBgNVBAYTAkRFMHYwEAYHKoZI
zj0CAQYFK4EEACIDYgAEloZYKDcKZ9Cg3iQZGeHkBQcfl+3oZIK59sRxUM6KDP/X
tXa7oWyTbIOiaG6l2b4siJVBzV3dscqDY4PMwL502eCdpO5KTlbgmClBk1IQ1SQ4
AjJn8ZQSb+/Xxd4u/RmAo0IwQDAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBR2
KCXWfeBmmnoJsmo7jjPXNtNPojAOBgNVHQ8BAf8EBAMCAYYwCgYIKoZIzj0EAwMD
aAAwZQIwW5kp85wxtolrbNa9d+F851F+uDrNozZffPc8dz7kUK2o59JZDCaOMDtu
CCrCp1rIAjEAmeMM56PDr9NJLkaCI2ZdyQAUEv049OGYa3cpetskz2VAv9LcjBHo
9H1/IISpQuQo
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFZDCCA0ygAwIBAgIQU9XP5hmTC/srBRLYwiqipDANBgkqhkiG9w0BAQwFADBM
MS4wLAYDVQQDDCVBdG9zIFRydXN0ZWRSb290IFJvb3QgQ0EgUlNBIFRMUyAyMDIx
MQ0wCwYDVQQKDARBdG9zMQswCQYDVQQGEwJERTAeFw0yMTA0MjIwOTIxMTBaFw00
MTA0MTcwOTIxMDlaMEwxLjAsBgNVBAMMJUF0b3MgVHJ1c3RlZFJvb3QgUm9vdCBD
QSBSU0EgVExTIDIwMjExDTALBgNVBAoMBEF0b3MxCzAJBgNVBAYTAkRFMIICIjAN
BgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAtoAOxHm9BYx9sKOdTSJNy/BBl01Z
4NH+VoyX8te9j2y3I49f1cTYQcvyAh5x5en2XssIKl4w8i1mx4QbZFc4nXUtVsYv
Ye+W/CBGvevUez8/fEc4BKkbqlLfEzfTFRVOvV98r61jx3ncCHvVoOX3W3WsgFWZ
kmGbzSoXfduP9LVq6hdKZChmFSlsAvFr1bqjM9xaZ6cF4r9lthawEO3NUDPJcFDs
GY6wx/J0W2tExn2WuZgIWWbeKQGb9Cpt0xU6kGpn8bRrZtkh68rZYnxGEFzedUln
nkL5/nWpo63/dgpnQOPF943HhZpZnmKaau1Fh5hnstVKPNe0OwANwI8f4UDErmwh
3El+fsqyjW22v5MvoVw+j8rtgI5Y4dtXz4U2OLJxpAmMkokIiEjxQGMYsluMWuPD
0xeqqxmjLBvk1cbiZnrXghmmOxYsL3GHX0WelXOTwkKBIROW1527k2gV+p2kHYzy
geBYBr3JtuP2iV2J+axEoctr+hbxx1A9JNr3w+SH1VbxT5Aw+kUJWdo0zuATHAR8
ANSbhqRAvNncTFd+rrcztl524WWLZt+NyteYr842mIycg5kDcPOvdO3GDjbnvezB
c6eUWsuSZIKmAMFwoW4sKeFYV+xafJlrJaSQOoD0IJ2azsct+bJLKZWD6TWNp0lI
pw9MGZHQ9b8Q4HECAwEAAaNCMEAwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQU
dEmZ0f+0emhFdcN+tNzMzjkz2ggwDgYDVR0PAQH/BAQDAgGGMA0GCSqGSIb3DQEB
DAUAA4ICAQAjQ1MkYlxt/T7Cz1UAbMVWiLkO3TriJQ2VSpfKgInuKs1l+NsW4AmS
4BjHeJi78+xCUvuppILXTdiK/ORO/auQxDh1MoSf/7OwKwIzNsAQkG8dnK/haZPs
o0UvFJ/1TCplQ3IM98P4lYsU84UgYt1UU90s3BiVaU+DR3BAM1h3Egyi61IxHkzJ
qM7F78PRreBrAwA0JrRUITWXAdxfG/F851X6LWh3e9NpzNMOa7pNdkTWwhWaJuyw
xfW70Xp0wmzNxbVe9kzmWy2B27O3Opee7c9GslA9hGCZcbUztVdF5kJHdWoOsAgM
rr3e97sPWD2PAzHoPYJQyi9eDF20l74gNAf0xBLh7tew2VktafcxBPTy+av5EzH4
AXcOPUIjJsyacmdRIXrMPIWo6iFqO9taPKU0nprALN+AnCng33eU0aKAQv9qTFsR
0PXNor6uzFFcw9VUewyu1rkGd4Di7wcaaMxZUa1+XGdrudviB0JbuAEFWDlN5LuY
o7Ey7Nmj1m+UI/87tyll5gfp77YZ6ufCOB0yiJA8EytuzO+rdwY0d4RPcuSBhPm5
dDTedk+SKlOxJTnbPP/lPqYO5Wue/9vsL3SD3460s6neFE3/MaNFcyT6lSnMEpcE
oji2jbDwN/zIIX8/syQbPYtuzE2wFg2WHYMfRsCbvUOZ58SWLs5fyQ==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIGFDCCA/ygAwIBAgIIG3Dp0v+ubHEwDQYJKoZIhvcNAQELBQAwUTELMAkGA1UE
BhMCRVMxQjBABgNVBAMMOUF1dG9yaWRhZCBkZSBDZXJ0aWZpY2FjaW9uIEZpcm1h
cHJvZmVzaW9uYWwgQ0lGIEE2MjYzNDA2ODAeFw0xNDA5MjMxNTIyMDdaFw0zNjA1
MDUxNTIyMDdaMFExCzAJBgNVBAYTAkVTMUIwQAYDVQQDDDlBdXRvcmlkYWQgZGUg
Q2VydGlmaWNhY2lvbiBGaXJtYXByb2Zlc2lvbmFsIENJRiBBNjI2MzQwNjgwggIi
MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDKlmuO6vj78aI14H9M2uDDUtd9
thDIAl6zQyrET2qyyhxdKJp4ERppWVevtSBC5IsP5t9bpgOSL/UR5GLXMnE42QQM
cas9UX4PB99jBVzpv5RvwSmCwLTaUbDBPLutN0pcyvFLNg4kq7/DhHf9qFD0sefG
L9ItWY16Ck6WaVICqjaY7Pz6FIMMNx/Jkjd/14Et5cS54D40/mf0PmbR0/RAz15i
NA9wBj4gGFrO93IbJWyTdBSTo3OxDqqHECNZXyAFGUftaI6SEspd/NYrspI8IM/h
X68gvqB2f3bl7BqGYTM+53u0P6APjqK5am+5hyZvQWyIplD9amML9ZMWGxmPsu2b
m8mQ9QEM3xk9Dz44I8kvjwzRAv4bVdZO0I08r0+k8/6vKtMFnXkIoctXMbScyJCy
Z/QYFpM6/EfY0XiWMR+6KwxfXZmtY4laJCB22N/9q06mIqqdXuYnin1oKaPnirja
EbsXLZmdEyRG98Xi2J+Of8ePdG1asuhy9azuJBCtLxTa/y2aRnFHvkLfuwHb9H/T
KI8xWVvTyQKmtFLKbpf7Q8UIJm+K9Lv9nyiqDdVF8xM6HdjAeI9BZzwelGSuewvF
6NkBiDkal4ZkQdU7hwxu+g/GvUgUvzlN1J5Bto+WHWOWk9mVBngxaJ43BjuAiUVh
OSPHG0SjFeUc+JIwuwIDAQABo4HvMIHsMB0GA1UdDgQWBBRlzeurNR4APn7VdMAc
tHNHDhpkLzASBgNVHRMBAf8ECDAGAQH/AgEBMIGmBgNVHSAEgZ4wgZswgZgGBFUd
IAAwgY8wLwYIKwYBBQUHAgEWI2h0dHA6Ly93d3cuZmlybWFwcm9mZXNpb25hbC5j
b20vY3BzMFwGCCsGAQUFBwICMFAeTgBQAGEAcwBlAG8AIABkAGUAIABsAGEAIABC
AG8AbgBhAG4AbwB2AGEAIAA0ADcAIABCAGEAcgBjAGUAbABvAG4AYQAgADAAOAAw
ADEANzAOBgNVHQ8BAf8EBAMCAQYwDQYJKoZIhvcNAQELBQADggIBAHSHKAIrdx9m
iWTtj3QuRhy7qPj4Cx2Dtjqn6EWKB7fgPiDL4QjbEwj4KKE1soCzC1HA01aajTNF
Sa9J8OA9B3pFE1r/yJfY0xgsfZb43aJlQ3CTkBW6kN/oGbDbLIpgD7dvlAceHabJ
hfa9NPhAeGIQcDq+fUs5gakQ1JZBu/hfHAsdCPKxsIl68veg4MSPi3i1O1ilI45P
Vf42O+AMt8oqMEEgtIDNrvx2ZnOorm7hfNoD6JQg5iKj0B+QXSBTFCZX2lSX3xZE
EAEeiGaPcjiT3SC3NL7X8e5jjkd5KAb881lFJWAiMxujX6i6KtoaPc1A6ozuBRWV
1aUsIC+nmCjuRfzxuIgALI9C2lHVnOUTaHFFQ4ueCyE8S1wF3BqfmI7avSKecs2t
CsvMo2ebKHTEm9caPARYpoKdrcd7b/+Alun4jWq9GJAd/0kakFI3ky88Al2CdgtR
5xbHV/g4+afNmyJU72OwFW1TZQNKXkqgsqeOSQBZONXH9IBk9W6VULgRfhVwOEqw
f9DEMnDAGf/JOC0ULGb0QkTmVXYbgBVX/8Cnp6o5qtjTcNAuuuuUavpfNIbnYrX9
ivAwhZTJryQCL2/W3Wf+47BVTwSYT6RBVuKT0Gro1vP7ZeDOdcQxWQzugsgMYDNK
GbqEZycPvEJdvSRUDewdcAZfpLz6IHxV
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFdDCCA1ygAwIBAgIQVW9l47TZkGobCdFsPsBsIDANBgkqhkiG9w0BAQsFADBU
MQswCQYDVQQGEwJDTjEmMCQGA1UECgwdQkVJSklORyBDRVJUSUZJQ0FURSBBVVRI
T1JJVFkxHTAbBgNVBAMMFEJKQ0EgR2xvYmFsIFJvb3QgQ0ExMB4XDTE5MTIxOTAz
MTYxN1oXDTQ0MTIxMjAzMTYxN1owVDELMAkGA1UEBhMCQ04xJjAkBgNVBAoMHUJF
SUpJTkcgQ0VSVElGSUNBVEUgQVVUSE9SSVRZMR0wGwYDVQQDDBRCSkNBIEdsb2Jh
bCBSb290IENBMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAPFmCL3Z
xRVhy4QEQaVpN3cdwbB7+sN3SJATcmTRuHyQNZ0YeYjjlwE8R4HyDqKYDZ4/N+AZ
spDyRhySsTphzvq3Rp4Dhtczbu33RYx2N95ulpH3134rhxfVizXuhJFyV9xgw8O5
58dnJCNPYwpj9mZ9S1WnP3hkSWkSl+BMDdMJoDIwOvqfwPKcxRIqLhy1BDPapDgR
at7GGPZHOiJBhyL8xIkoVNiMpTAK+BcWyqw3/XmnkRd4OJmtWO2y3syJfQOcs4ll
5+M7sSKGjwZteAf9kRJ/sGsciQ35uMt0WwfCyPQ10WRjeulumijWML3mG90Vr4Tq
nMfK9Q7q8l0ph49pczm+LiRvRSGsxdRpJQaDrXpIhRMsDQa4bHlW/KNnMoH1V6XK
V0Jp6VwkYe/iMBhORJhVb3rCk9gZtt58R4oRTklH2yiUAguUSiz5EtBP6DF+bHq/
pj+bOT0CFqMYs2esWz8sgytnOYFcuX6U1WTdno9uruh8W7TXakdI136z1C2OVnZO
z2nxbkRs1CTqjSShGL+9V/6pmTW12xB3uD1IutbB5/EjPtffhZ0nPNRAvQoMvfXn
jSXWgXSHRtQpdaJCbPdzied9v3pKH9MiyRVVz99vfFXQpIsHETdfg6YmV6YBW37+
WGgHqel62bno/1Afq8K0wM7o6v0PvY1NuLxxAgMBAAGjQjBAMB0GA1UdDgQWBBTF
7+3M2I0hxkjk49cULqcWk+WYATAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQE
AwIBBjANBgkqhkiG9w0BAQsFAAOCAgEAUoKsITQfI/Ki2Pm4rzc2IInRNwPWaZ+4
YRC6ojGYWUfo0Q0lHhVBDOAqVdVXUsv45Mdpox1NcQJeXyFFYEhcCY5JEMEE3Kli
awLwQ8hOnThJdMkycFRtwUf8jrQ2ntScvd0g1lPJGKm1Vrl2i5VnZu69mP6u775u
+2D2/VnGKhs/I0qUJDAnyIm860Qkmss9vk/Ves6OF8tiwdneHg56/0OGNFK8YT88
X7vZdrRTvJez/opMEi4r89fO4aL/3Xtw+zuhTaRjAv04l5U/BXCga99igUOLtFkN
SoxUnMW7gZ/NfaXvCyUeOiDbHPwfmGcCCtRzRBPbUYQaVQNW4AB+dAb/OMRyHdOo
P2gxXdMJxy6MW2Pg6Nwe0uxhHvLe5e/2mXZgLR6UcnHGCyoyx5JO1UbXHfmpGQrI
+pXObSOYqgs4rZpWDW+N8TEAiMEXnM0ZNjX+VVOg4DwzX5Ze4jLp3zO7Bkqp2IRz
znfSxqxx4VyjHQy7Ct9f4qNx2No3WqB4K/TUfet27fJhcKVlmtOJNBir+3I+17Q9
eVzYH6Eze9mCUAyTF6ps3MKCuwJXNq+YJyo5UOGwifUll35HaBC07HPKs5fRJNz2
YqAo07WjuGS3iGJCz51TzZm+ZGiPTx4SSPfSKcOYKMryMguTjClPPGAyzQWWYezy
r/6zcCwupvI=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICJTCCAaugAwIBAgIQLBcIfWQqwP6FGFkGz7RK6zAKBggqhkjOPQQDAzBUMQsw
CQYDVQQGEwJDTjEmMCQGA1UECgwdQkVJSklORyBDRVJUSUZJQ0FURSBBVVRIT1JJ
VFkxHTAbBgNVBAMMFEJKQ0EgR2xvYmFsIFJvb3QgQ0EyMB4XDTE5MTIxOTAzMTgy
MVoXDTQ0MTIxMjAzMTgyMVowVDELMAkGA1UEBhMCQ04xJjAkBgNVBAoMHUJFSUpJ
TkcgQ0VSVElGSUNBVEUgQVVUSE9SSVRZMR0wGwYDVQQDDBRCSkNBIEdsb2JhbCBS
b290IENBMjB2MBAGByqGSM49AgEGBSuBBAAiA2IABJ3LgJGNU2e1uVCxA/jlSR9B
IgmwUVJY1is0j8USRhTFiy8shP8sbqjV8QnjAyEUxEM9fMEsxEtqSs3ph+B99iK+
+kpRuDCK/eHeGBIK9ke35xe/J4rUQUyWPGCWwf0VHKNCMEAwHQYDVR0OBBYEFNJK
sVF/BvDRgh9Obl+rg/xI1LCRMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQD
AgEGMAoGCCqGSM49BAMDA2gAMGUCMBq8W9f+qdJUDkpd0m2xQNz0Q9XSSpkZElaA
94M04TVOSG0ED1cxMDAtsaqdAzjbBgIxAMvMh1PLet8gUXOQwKhbYdDFUDn9hf7B
43j4ptZLvZuHjw/l1lOWqzzIQNph91Oj9w==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFWTCCA0GgAwIBAgIBAjANBgkqhkiG9w0BAQsFADBOMQswCQYDVQQGEwJOTzEd
MBsGA1UECgwUQnV5cGFzcyBBUy05ODMxNjMzMjcxIDAeBgNVBAMMF0J1eXBhc3Mg
Q2xhc3MgMiBSb290IENBMB4XDTEwMTAyNjA4MzgwM1oXDTQwMTAyNjA4MzgwM1ow
TjELMAkGA1UEBhMCTk8xHTAbBgNVBAoMFEJ1eXBhc3MgQVMtOTgzMTYzMzI3MSAw
HgYDVQQDDBdCdXlwYXNzIENsYXNzIDIgUm9vdCBDQTCCAiIwDQYJKoZIhvcNAQEB
BQADggIPADCCAgoCggIBANfHXvfBB9R3+0Mh9PT1aeTuMgHbo4Yf5FkNuud1g1Lr
6hxhFUi7HQfKjK6w3Jad6sNgkoaCKHOcVgb/S2TwDCo3SbXlzwx87vFKu3MwZfPV
L4O2fuPn9Z6rYPnT8Z2SdIrkHJasW4DptfQxh6NR/Md+oW+OU3fUl8FVM5I+GC91
1K2GScuVr1QGbNgGE41b/+EmGVnAJLqBcXmQRFBoJJRfuLMR8SlBYaNByyM21cHx
MlAQTn/0hpPshNOOvEu/XAFOBz3cFIqUCqTqc/sLUegTBxj6DvEr0VQVfTzh97QZ
QmdiXnfgolXsttlpF9U6r0TtSsWe5HonfOV116rLJeffawrbD02TTqigzXsu8lkB
arcNuAeBfos4GzjmCleZPe4h6KP1DBbdi+w0jpwqHAAVF41og9JwnxgIzRFo1clr
Us3ERo/ctfPYV3Me6ZQ5BL/T3jjetFPsaRyifsSP5BtwrfKi+fv3FmRmaZ9JUaLi
FRhnBkp/1Wy1TbMz4GHrXb7pmA8y1x1LPC5aAVKRCfLf6o3YBkBjqhHk/sM3nhRS
P/TizPJhk9H9Z2vXUq6/aKtAQ6BXNVN48FP4YUIHZMbXb5tMOA1jrGKvNouicwoN
9SG9dKpN6nIDSdvHXx1iY8f93ZHsM+71bbRuMGjeyNYmsHVee7QHIJihdjK4TWxP
AgMBAAGjQjBAMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFMmAd+BikoL1Rpzz
uvdMw964o605MA4GA1UdDwEB/wQEAwIBBjANBgkqhkiG9w0BAQsFAAOCAgEAU18h
9bqwOlI5LJKwbADJ784g7wbylp7ppHR/ehb8t/W2+xUbP6umwHJdELFx7rxP462s
A20ucS6vxOOto70MEae0/0qyexAQH6dXQbLArvQsWdZHEIjzIVEpMMpghq9Gqx3t
OluwlN5E40EIosHsHdb9T7bWR9AUC8rmyrV7d35BH16Dx7aMOZawP5aBQW9gkOLo
+fsicdl9sz1Gv7SEr5AcD48Saq/v7h56rgJKihcrdv6sVIkkLE8/trKnToyokZf7
KcZ7XC25y2a2t6hbElGFtQl+Ynhw/qlqYLYdDnkM/crqJIByw5c/8nerQyIKx+u2
DISCLIBrQYoIwOula9+ZEsuK1V6ADJHgJgg2SMX6OBE1/yWDLfJ6v9r9jv6ly0Us
H8SIU653DtmadsWOLB2jutXsMq7Aqqz30XpN69QH4kj3Io6wpJ9qzo6ysmD0oyLQ
I+uUWnpp3Q+/QFesa1lQ2aOZ4W7+jQF5JyMV3pKdewlNWudLSDBaGOYKbeaP4NK7
5t98biGCwWg5TbSYWGZizEqQXsP6JwSxeRV0mcy+rSDeJmAc61ZRpqPq5KM/p/9h
3PFaTWwyI0PurKju7koSCTxdccK+efrCh2gdC/1cacwG0Jp9VJkqyTkaGa9LKkPz
Y11aWOIv4x3kqdbQCtCev9eBCfHJxyYNrJgWVqA=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFWTCCA0GgAwIBAgIBAjANBgkqhkiG9w0BAQsFADBOMQswCQYDVQQGEwJOTzEd
MBsGA1UECgwUQnV5cGFzcyBBUy05ODMxNjMzMjcxIDAeBgNVBAMMF0J1eXBhc3Mg
Q2xhc3MgMyBSb290IENBMB4XDTEwMTAyNjA4Mjg1OFoXDTQwMTAyNjA4Mjg1OFow
TjELMAkGA1UEBhMCTk8xHTAbBgNVBAoMFEJ1eXBhc3MgQVMtOTgzMTYzMzI3MSAw
HgYDVQQDDBdCdXlwYXNzIENsYXNzIDMgUm9vdCBDQTCCAiIwDQYJKoZIhvcNAQEB
BQADggIPADCCAgoCggIBAKXaCpUWUOOV8l6ddjEGMnqb8RB2uACatVI2zSRHsJ8Y
ZLya9vrVediQYkwiL944PdbgqOkcLNt4EemOaFEVcsfzM4fkoF0LXOBXByow9c3E
N3coTRiR5r/VUv1xLXA+58bEiuPwKAv0dpihi4dVsjoT/Lc+JzeOIuOoTyrvYLs9
tznDDgFHmV0ST9tD+leh7fmdvhFHJlsTmKtdFoqwNxxXnUX/iJY2v7vKB3tvh2PX
0DJq1l1sDPGzbjniazEuOQAnFN44wOwZZoYS6J1yFhNkUsepNxz9gjDthBgd9K5c
/3ATAOux9TN6S9ZV+AWNS2mw9bMoNlwUxFFzTWsL8TQH2xc519woe2v1n/MuwU8X
KhDzzMro6/1rqy6any2CbgTUUgGTLT2G/H783+9CHaZr77kgxve9oKeV/afmiSTY
zIw0bOIjL9kSGiG5VZFvC5F5GQytQIgLcOJ60g7YaEi7ghM5EFjp2CoHxhLbWNvS
O1UQRwUVZ2J+GGOmRj8JDlQyXr8NYnon74Do29lLBlo3WiXQCBJ31G8JUJc9yB3D
34xFMFbG02SrZvPAXpacw8Tvw3xrizp5f7NJzz3iiZ+gMEuFuZyUJHmPfWupRWgP
K9Dx2hzLabjKSWJtyNBjYt1gD1iqj6G8BaVmos8bdrKEZLFMOVLAMLrwjEsCsLa3
AgMBAAGjQjBAMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFEe4zf/lb+74suwv
Tg75JbCOPGvDMA4GA1UdDwEB/wQEAwIBBjANBgkqhkiG9w0BAQsFAAOCAgEAACAj
QTUEkMJAYmDv4jVM1z+s4jSQuKFvdvoWFqRINyzpkMLyPPgKn9iB5btb2iUspKdV
cSQy9sgL8rxq+JOssgfCX5/bzMiKqr5qb+FJEMwx14C7u8jYog5kV+qi9cKpMRXS
IGrs/CIBKM+GuIAeqcwRpTzyFrNHnfzSgCHEy9BHcEGhyoMZCCxt8l13nIoUE9Q2
HJLw5QY33KbmkJs4j1xrG0aGQ0JfPgEHU1RdZX33inOhmlRaHylDFCfChQ+1iHsa
O5S3HWCntZznKWlXWpuTekMwGwPXYshApqr8ZORK15FTAaggiG6cX0S5y2CBNOxv
033aSF/rtJC8LakcC6wc1aJoIIAE1vyxjy+7SjENSoYc6+I2KSb12tjE8nVhz36u
dmNKekBlk4f4HoCMhuWG1o8O/FMsYOgWYRqiPkN7zTlgVGr18okmAWiDSKIz6MkE
kbIRNBE+6tBDGR8Dk5AM/1E9V/RBbuHLoL7ryWPNbczk+DaqaJ3tvV2XcEQNtg41
3OEMXbugUZTLfhbrES+jkkXITHHZvMmZUldGL1DPvTVp9D0VzgalLA8+9oG6lLvD
u79leNKGef9JOxqDDPDeeOzI8k1MGt6CKfjBWtrt7uYnXuhF0J0cUahoq0Tj0Itq
4/g7u9xN12TyUb7mqqta6THuBrxzvxNiCp/HuZc=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFaTCCA1GgAwIBAgIJAJK4iNuwisFjMA0GCSqGSIb3DQEBCwUAMFIxCzAJBgNV
BAYTAlNLMRMwEQYDVQQHEwpCcmF0aXNsYXZhMRMwEQYDVQQKEwpEaXNpZyBhLnMu
MRkwFwYDVQQDExBDQSBEaXNpZyBSb290IFIyMB4XDTEyMDcxOTA5MTUzMFoXDTQy
MDcxOTA5MTUzMFowUjELMAkGA1UEBhMCU0sxEzARBgNVBAcTCkJyYXRpc2xhdmEx
EzARBgNVBAoTCkRpc2lnIGEucy4xGTAXBgNVBAMTEENBIERpc2lnIFJvb3QgUjIw
ggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCio8QACdaFXS1tFPbCw3Oe
NcJxVX6B+6tGUODBfEl45qt5WDza/3wcn9iXAng+a0EE6UG9vgMsRfYvZNSrXaNH
PWSb6WiaxswbP7q+sos0Ai6YVRn8jG+qX9pMzk0DIaPY0jSTVpbLTAwAFjxfGs3I
x2ymrdMxp7zo5eFm1tL7A7RBZckQrg4FY8aAamkw/dLukO8NJ9+flXP04SXabBbe
QTg06ov80egEFGEtQX6sx3dOy1FU+16SGBsEWmjGycT6txOgmLcRK7fWV8x8nhfR
yyX+hk4kLlYMeE2eARKmK6cBZW58Yh2EhN/qwGu1pSqVg8NTEQxzHQuyRpDRQjrO
QG6Vrf/GlK1ul4SOfW+eioANSW1z4nuSHsPzwfPrLgVv2RvPN3YEyLRa5Beny912
H9AZdugsBbPWnDTYltxhh5EF5EQIM8HauQhl1K6yNg3ruji6DOWbnuuNZt2Zz9aJ
QfYEkoopKW1rOhzndX0CcQ7zwOe9yxndnWCywmZgtrEE7snmhrmaZkCo5xHtgUUD
i/ZnWejBBhG93c+AAk9lQHhcR1DIm+YfgXvkRKhbhZri3lrVx/k6RGZL5DJUfORs
nLMOPReisjQS1n6yqEm70XooQL6iFh/f5DcfEXP7kAplQ6INfPgGAVUzfbANuPT1
rqVCV3w2EYx7XsQDnYx5nQIDAQABo0IwQDAPBgNVHRMBAf8EBTADAQH/MA4GA1Ud
DwEB/wQEAwIBBjAdBgNVHQ4EFgQUtZn4r7CU9eMg1gqtzk5WpC5uQu0wDQYJKoZI
hvcNAQELBQADggIBACYGXnDnZTPIgm7ZnBc6G3pmsgH2eDtpXi/q/075KMOYKmFM
tCQSin1tERT3nLXK5ryeJ45MGcipvXrA1zYObYVybqjGom32+nNjf7xueQgcnYqf
GopTpti72TVVsRHFqQOzVju5hJMiXn7B9hJSi+osZ7z+Nkz1uM/Rs0mSO9MpDpkb
lvdhuDvEK7Z4bLQjb/D907JedR+Zlais9trhxTF7+9FGs9K8Z7RiVLoJ92Owk6Ka
+elSLotgEqv89WBW7xBci8QaQtyDW2QOy7W81k/BfDxujRNt+3vrMNDcTa/F1bal
TFtxyegxvug4BkihGuLq0t4SOVga/4AOgnXmt8kHbA7v/zjxmHHEt38OFdAlab0i
nSvtBfZGR6ztwPDUO+Ls7pZbkBNOHlY667DvlruWIxG68kOGdGSVyCh13x01utI3
gzhTODY7z2zp+WsO0PsE6E9312UBeIYMej4hYvF/Y3EMyZ9E26gnonW+boE+18Dr
G5gPcFw0sorMwIUY6256s/daoQe/qUKS82Ail+QUoQebTnbAjn39pCXHR+3/H3Os
zMOl6W8KjptlwlCFtaOgUxLMVYdh84GuEEZhvUQhuMI9dM9+JDX6HAcOmz0iyu8x
L4ysEr3vQCj8KWefshNPZiTEUxnpHikV7+ZtsH8tZ/3zbBt1RqPlShfppNcL
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFjTCCA3WgAwIBAgIEGErM1jANBgkqhkiG9w0BAQsFADBWMQswCQYDVQQGEwJD
TjEwMC4GA1UECgwnQ2hpbmEgRmluYW5jaWFsIENlcnRpZmljYXRpb24gQXV0aG9y
aXR5MRUwEwYDVQQDDAxDRkNBIEVWIFJPT1QwHhcNMTIwODA4MDMwNzAxWhcNMjkx
MjMxMDMwNzAxWjBWMQswCQYDVQQGEwJDTjEwMC4GA1UECgwnQ2hpbmEgRmluYW5j
aWFsIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRUwEwYDVQQDDAxDRkNBIEVWIFJP
T1QwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDXXWvNED8fBVnVBU03
sQ7smCuOFR36k0sXgiFxEFLXUWRwFsJVaU2OFW2fvwwbwuCjZ9YMrM8irq93VCpL
TIpTUnrD7i7es3ElweldPe6hL6P3KjzJIx1qqx2hp/Hz7KDVRM8Vz3IvHWOX6Jn5
/ZOkVIBMUtRSqy5J35DNuF++P96hyk0g1CXohClTt7GIH//62pCfCqktQT+x8Rgp
7hZZLDRJGqgG16iI0gNyejLi6mhNbiyWZXvKWfry4t3uMCz7zEasxGPrb382KzRz
EpR/38wmnvFyXVBlWY9ps4deMm/DGIq1lY+wejfeWkU7xzbh72fROdOXW3NiGUgt
hxwG+3SYIElz8AXSG7Ggo7cbcNOIabla1jj0Ytwli3i/+Oh+uFzJlU9fpy25IGvP
a931DfSCt/SyZi4QKPaXWnuWFo8BGS1sbn85WAZkgwGDg8NNkt0yxoekN+kWzqot
aK8KgWU6cMGbrU1tVMoqLUuFG7OA5nBFDWteNfB/O7ic5ARwiRIlk9oKmSJgamNg
TnYGmE69g60dWIolhdLHZR4tjsbftsbhf4oEIRUpdPA+nJCdDC7xij5aqgwJHsfV
PKPtl8MeNPo4+QgO48BdK4PRVmrJtqhUUy54Mmc9gn900PvhtgVguXDbjgv5E1hv
cWAQUhC5wUEJ73IfZzF4/5YFjQIDAQABo2MwYTAfBgNVHSMEGDAWgBTj/i39KNAL
tbq2osS/BqoFjJP7LzAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBBjAd
BgNVHQ4EFgQU4/4t/SjQC7W6tqLEvwaqBYyT+y8wDQYJKoZIhvcNAQELBQADggIB
ACXGumvrh8vegjmWPfBEp2uEcwPenStPuiB/vHiyz5ewG5zz13ku9Ui20vsXiObT
ej/tUxPQ4i9qecsAIyjmHjdXNYmEwnZPNDatZ8POQQaIxffu2Bq41gt/UP+TqhdL
jOztUmCypAbqTuv0axn96/Ua4CUqmtzHQTb3yHQFhDmVOdYLO6Qn+gjYXB74BGBS
ESgoA//vU2YApUo0FmZ8/Qmkrp5nGm9BC2sGE5uPhnEFtC+NiWYzKXZUmhH4J/qy
P5Hgzg0b8zAarb8iXRvTvyUFTeGSGn+ZnzxEk8rUQElsgIfXBDrDMlI1Dlb4pd19
xIsNER9Tyx6yF7Zod1rg1MvIB671Oi6ON7fQAUtDKXeMOZePglr4UeWJoBjnaH9d
Ci77o0cOPaYjesYBx4/IXr9tgFa+iiS6M+qf4TIRnvHST4D2G0CvOJ4RUHlzEhLN
5mydLIhyPDCBBpEi6lmt2hkuIsKNuYyH4Ga8cyNfIWRjgEj1oDwYPZTISEEdQLpe
/v5WOaHIz16eGWRGENoXkbcFgKyLmZJ956LYBws2J+dIeWCKw9cTXPhyQN9Ky8+Z
AAoACxGV2lZFA4gKn2fQ1XmxqI1AbQ3CekD6819kR5LLU7m7Wc5P/dAVUwHY3+vZ
5nbv0CO7O6l5s9UCKc2Jo5YPSjXnTkLAdc0Hz+Ys63su
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICiTCCAg+gAwIBAgIQH0evqmIAcFBUTAGem2OZKjAKBggqhkjOPQQDAzCBhTEL
MAkGA1UEBhMCR0IxGzAZBgNVBAgTEkdyZWF0ZXIgTWFuY2hlc3RlcjEQMA4GA1UE
BxMHU2FsZm9yZDEaMBgGA1UEChMRQ09NT0RPIENBIExpbWl0ZWQxKzApBgNVBAMT
IkNPTU9ETyBFQ0MgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkwHhcNMDgwMzA2MDAw
MDAwWhcNMzgwMTE4MjM1OTU5WjCBhTELMAkGA1UEBhMCR0IxGzAZBgNVBAgTEkdy
ZWF0ZXIgTWFuY2hlc3RlcjEQMA4GA1UEBxMHU2FsZm9yZDEaMBgGA1UEChMRQ09N
T0RPIENBIExpbWl0ZWQxKzApBgNVBAMTIkNPTU9ETyBFQ0MgQ2VydGlmaWNhdGlv
biBBdXRob3JpdHkwdjAQBgcqhkjOPQIBBgUrgQQAIgNiAAQDR3svdcmCFYX7deSR
FtSrYpn1PlILBs5BAH+X4QokPB0BBO490o0JlwzgdeT6+3eKKvUDYEs2ixYjFq0J
cfRK9ChQtP6IHG4/bC8vCVlbpVsLM5niwz2J+Wos77LTBumjQjBAMB0GA1UdDgQW
BBR1cacZSBm8nZ3qQUfflMRId5nTeTAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0TAQH/
BAUwAwEB/zAKBggqhkjOPQQDAwNoADBlAjEA7wNbeqy3eApyt4jf/7VGFAkK+qDm
fQjGGoe9GKhzvSbKYAydzpmfz1wPMOG+FDHqAjAU9JM8SaczepBGR7NjfRObTrdv
GDeAU/7dIOA1mjbRxwG55tzd8/8dLDoWV9mSOdY=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIF2DCCA8CgAwIBAgIQTKr5yttjb+Af907YWwOGnTANBgkqhkiG9w0BAQwFADCB
hTELMAkGA1UEBhMCR0IxGzAZBgNVBAgTEkdyZWF0ZXIgTWFuY2hlc3RlcjEQMA4G
A1UEBxMHU2FsZm9yZDEaMBgGA1UEChMRQ09NT0RPIENBIExpbWl0ZWQxKzApBgNV
BAMTIkNPTU9ETyBSU0EgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkwHhcNMTAwMTE5
MDAwMDAwWhcNMzgwMTE4MjM1OTU5WjCBhTELMAkGA1UEBhMCR0IxGzAZBgNVBAgT
EkdyZWF0ZXIgTWFuY2hlc3RlcjEQMA4GA1UEBxMHU2FsZm9yZDEaMBgGA1UEChMR
Q09NT0RPIENBIExpbWl0ZWQxKzApBgNVBAMTIkNPTU9ETyBSU0EgQ2VydGlmaWNh
dGlvbiBBdXRob3JpdHkwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCR
6FSS0gpWsawNJN3Fz0RndJkrN6N9I3AAcbxT38T6KhKPS38QVr2fcHK3YX/JSw8X
pz3jsARh7v8Rl8f0hj4K+j5c+ZPmNHrZFGvnnLOFoIJ6dq9xkNfs/Q36nGz637CC
9BR++b7Epi9Pf5l/tfxnQ3K9DADWietrLNPtj5gcFKt+5eNu/Nio5JIk2kNrYrhV
/erBvGy2i/MOjZrkm2xpmfh4SDBF1a3hDTxFYPwyllEnvGfDyi62a+pGx8cgoLEf
Zd5ICLqkTqnyg0Y3hOvozIFIQ2dOciqbXL1MGyiKXCJ7tKuY2e7gUYPDCUZObT6Z
+pUX2nwzV0E8jVHtC7ZcryxjGt9XyD+86V3Em69FmeKjWiS0uqlWPc9vqv9JWL7w
qP/0uK3pN/u6uPQLOvnoQ0IeidiEyxPx2bvhiWC4jChWrBQdnArncevPDt09qZah
SL0896+1DSJMwBGB7FY79tOi4lu3sgQiUpWAk2nojkxl8ZEDLXB0AuqLZxUpaVIC
u9ffUGpVRr+goyhhf3DQw6KqLCGqR84onAZFdr+CGCe01a60y1Dma/RMhnEw6abf
Fobg2P9A3fvQQoh/ozM6LlweQRGBY84YcWsr7KaKtzFcOmpH4MN5WdYgGq/yapiq
crxXStJLnbsQ/LBMQeXtHT1eKJ2czL+zUdqnR+WEUwIDAQABo0IwQDAdBgNVHQ4E
FgQUu69+Aj36pvE8hI6t7jiY7NkyMtQwDgYDVR0PAQH/BAQDAgEGMA8GA1UdEwEB
/wQFMAMBAf8wDQYJKoZIhvcNAQEMBQADggIBAArx1UaEt65Ru2yyTUEUAJNMnMvl
wFTPoCWOAvn9sKIN9SCYPBMtrFaisNZ+EZLpLrqeLppysb0ZRGxhNaKatBYSaVqM
4dc+pBroLwP0rmEdEBsqpIt6xf4FpuHA1sj+nq6PK7o9mfjYcwlYRm6mnPTXJ9OV
2jeDchzTc+CiR5kDOF3VSXkAKRzH7JsgHAckaVd4sjn8OoSgtZx8jb8uk2Intzna
FxiuvTwJaP+EmzzV1gsD41eeFPfR60/IvYcjt7ZJQ3mFXLrrkguhxuhoqEwWsRqZ
CuhTLJK7oQkYdQxlqHvLI7cawiiFwxv/0Cti76R7CZGYZ4wUAc1oBmpjIXUDgIiK
boHGhfKppC3n9KUkEEeDys30jXlYsQab5xoq2Z0B15R97QNKyvDb6KkBPvVWmcke
jkk9u+UJueBPSZI9FoJAzMxZxuY67RIuaTxslbH9qh17f4a+Hg4yRvv7E491f0yL
S0Zj/gA0QHDBw7mh3aZw4gSzQbzpgJHqZJx64SIDqZxubw5lT2yHh17zbqD5daWb
QOhTsiedSrnAdyGN/4fy3ryM7xfft0kL0fJuMAsaDk527RH89elWsn2/x20Kk4yl
0MC2Hb46TpSi125sC8KKfPog88Tk5c0NqMuRkrF8hey1FGlmDoLnzc7ILaZRfyHB
NVOFBkpdn627G190
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIB9zCCAX2gAwIBAgIQBiUzsUcDMydc+Y2aub/M+DAKBggqhkjOPQQDAzA9MQsw
CQYDVQQGEwJVUzESMBAGA1UEChMJQ2VydGFpbmx5MRowGAYDVQQDExFDZXJ0YWlu
bHkgUm9vdCBFMTAeFw0yMTA0MDEwMDAwMDBaFw00NjA0MDEwMDAwMDBaMD0xCzAJ
BgNVBAYTAlVTMRIwEAYDVQQKEwlDZXJ0YWlubHkxGjAYBgNVBAMTEUNlcnRhaW5s
eSBSb290IEUxMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAE3m/4fxzf7flHh4axpMCK
+IKXgOqPyEpeKn2IaKcBYhSRJHpcnqMXfYqGITQYUBsQ3tA3SybHGWCA6TS9YBk2
QNYphwk8kXr2vBMj3VlOBF7PyAIcGFPBMdjaIOlEjeR2o0IwQDAOBgNVHQ8BAf8E
BAMCAQYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQU8ygYy2R17ikq6+2uI1g4
hevIIgcwCgYIKoZIzj0EAwMDaAAwZQIxALGOWiDDshliTd6wT99u0nCK8Z9+aozm
ut6Dacpps6kFtZaSF4fC0urQe87YQVt8rgIwRt7qy12a7DLCZRawTDBcMPPaTnOG
BtjOiQRINzf43TNRnXCve1XYAS59BWQOhriR
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFRzCCAy+gAwIBAgIRAI4P+UuQcWhlM1T01EQ5t+AwDQYJKoZIhvcNAQELBQAw
PTELMAkGA1UEBhMCVVMxEjAQBgNVBAoTCUNlcnRhaW5seTEaMBgGA1UEAxMRQ2Vy
dGFpbmx5IFJvb3QgUjEwHhcNMjEwNDAxMDAwMDAwWhcNNDYwNDAxMDAwMDAwWjA9
MQswCQYDVQQGEwJVUzESMBAGA1UEChMJQ2VydGFpbmx5MRowGAYDVQQDExFDZXJ0
YWlubHkgUm9vdCBSMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANA2
1B/q3avk0bbm+yLA3RMNansiExyXPGhjZjKcA7WNpIGD2ngwEc/csiu+kr+O5MQT
vqRoTNoCaBZ0vrLdBORrKt03H2As2/X3oXyVtwxwhi7xOu9S98zTm/mLvg7fMbed
aFySpvXl8wo0tf97ouSHocavFwDvA5HtqRxOcT3Si2yJ9HiG5mpJoM610rCrm/b0
1C7jcvk2xusVtyWMOvwlDbMicyF0yEqWYZL1LwsYpfSt4u5BvQF5+paMjRcCMLT5
r3gajLQ2EBAHBXDQ9DGQilHFhiZ5shGIXsXwClTNSaa/ApzSRKft43jvRl5tcdF5
cBxGX1HpyTfcX35pe0HfNEXgO4T0oYoKNp43zGJS4YkNKPl6I7ENPT2a/Z2B7yyQ
wHtETrtJ4A5KVpK8y7XdeReJkd5hiXSSqOMyhb5OhaRLWcsrxXiOcVTQAjeZjOVJ
6uBUcqQRBi8LjMFbvrWhsFNunLhgkR9Za/kt9JQKl7XsxXYDVBtlUrpMklZRNaBA
2CnbrlJ2Oy0wQJuK0EJWtLeIAaSHO1OWzaMWj/Nmqhexx2DgwUMFDO6bW2BvBlyH
Wyf5QBGenDPBt+U1VwV/J84XIIwc/PH72jEpSe31C4SnT8H2TsIonPru4K8H+zMR
eiFPCyEQtkA6qyI6BJyLm4SGcprSp6XEtHWRqSsjAgMBAAGjQjBAMA4GA1UdDwEB
/wQEAwIBBjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTgqj8ljZ9EXME66C6u
d0yEPmcM9DANBgkqhkiG9w0BAQsFAAOCAgEAuVevuBLaV4OPaAszHQNTVfSVcOQr
PbA56/qJYv331hgELyE03fFo8NWWWt7CgKPBjcZq91l3rhVkz1t5BXdm6ozTaw3d
8VkswTOlMIAVRQdFGjEitpIAq5lNOo93r6kiyi9jyhXWx8bwPWz8HA2YEGGeEaIi
1wrykXprOQ4vMMM2SZ/g6Q8CRFA3lFV96p/2O7qUpUzpvD5RtOjKkjZUbVwlKNrd
rRT90+7iIgXr0PK3aBLXWopBGsaSpVo7Y0VPv+E6dyIvXL9G+VoDhRNCX8reU9di
taY1BMJH/5n9hN9czulegChB8n3nHpDYT3Y+gjwN/KUD+nsa2UUeYNrEjvn8K8l7
lcUq/6qJ34IxD3L/DCfXCh5WAFAeDJDBlrXYFIW7pw0WwfgHJBu6haEaBQmAupVj
yTrsJZ9/nbqkRxWbRHDxakvWOF5D8xh+UG7pWijmZeZ3Gzr9Hb4DJqPb1OG7fpYn
Kx3upPvaJVQTA945xsMfTZDsjxtK0hzthZU4UHlG1sGQUDGpXJpuHfUzVounmdLy
yCwzk5Iwx06MZTMQZBf9JBeW0Y3COmor6xOLRPIh80oat3df1+2IpHLlOR+Vnb5n
wXARPbv0+Em34yaXOp/SX3z7wJl8OSngex2/DaeP0ik0biQVy96QXr8axGbqwua6
OV+KmalBWQewLK8=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIGWzCCBEOgAwIBAgIRAMrpG4nxVQMNo+ZBbcTjpuEwDQYJKoZIhvcNAQELBQAw
WjELMAkGA1UEBhMCRlIxEjAQBgNVBAoMCURoaW15b3RpczEcMBoGA1UECwwTMDAw
MiA0ODE0NjMwODEwMDAzNjEZMBcGA1UEAwwQQ2VydGlnbmEgUm9vdCBDQTAeFw0x
MzEwMDEwODMyMjdaFw0zMzEwMDEwODMyMjdaMFoxCzAJBgNVBAYTAkZSMRIwEAYD
VQQKDAlEaGlteW90aXMxHDAaBgNVBAsMEzAwMDIgNDgxNDYzMDgxMDAwMzYxGTAX
BgNVBAMMEENlcnRpZ25hIFJvb3QgQ0EwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAw
ggIKAoICAQDNGDllGlmx6mQWDoyUJJV8g9PFOSbcDO8WV43X2KyjQn+Cyu3NW9sO
ty3tRQgXstmzy9YXUnIo245Onoq2C/mehJpNdt4iKVzSs9IGPjA5qXSjklYcoW9M
CiBtnyN6tMbaLOQdLNyzKNAT8kxOAkmhVECe5uUFoC2EyP+YbNDrihqECB63aCPu
I9Vwzm1RaRDuoXrC0SIxwoKF0vJVdlB8JXrJhFwLrN1CTivngqIkicuQstDuI7pm
TLtipPlTWmR7fJj6o0ieD5Wupxj0auwuA0Wv8HT4Ks16XdG+RCYyKfHx9WzMfgIh
C59vpD++nVPiz32pLHxYGpfhPTc3GGYo0kDFUYqMwy3OU4gkWGQwFsWq4NYKpkDf
ePb1BHxpE4S80dGnBs8B92jAqFe7OmGtBIyT46388NtEbVncSVmurJqZNjBBe3Yz
IoejwpKGbvlw7q6Hh5UbxHq9MfPU0uWZ/75I7HX1eBYdpnDBfzwboZL7z8g81sWT
Co/1VTp2lc5ZmIoJlXcymoO6LAQ6l73UL77XbJuiyn1tJslV1c/DeVIICZkHJC1k
JWumIWmbat10TWuXekG9qxf5kBdIjzb5LdXF2+6qhUVB+s06RbFo5jZMm5BX7CO5
hwjCxAnxl4YqKE3idMDaxIzb3+KhF1nOJFl0Mdp//TBt2dzhauH8XwIDAQABo4IB
GjCCARYwDwYDVR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYE
FBiHVuBud+4kNTxOc5of1uHieX4rMB8GA1UdIwQYMBaAFBiHVuBud+4kNTxOc5of
1uHieX4rMEQGA1UdIAQ9MDswOQYEVR0gADAxMC8GCCsGAQUFBwIBFiNodHRwczov
L3d3d3cuY2VydGlnbmEuZnIvYXV0b3JpdGVzLzBtBgNVHR8EZjBkMC+gLaArhilo
dHRwOi8vY3JsLmNlcnRpZ25hLmZyL2NlcnRpZ25hcm9vdGNhLmNybDAxoC+gLYYr
aHR0cDovL2NybC5kaGlteW90aXMuY29tL2NlcnRpZ25hcm9vdGNhLmNybDANBgkq
hkiG9w0BAQsFAAOCAgEAlLieT/DjlQgi581oQfccVdV8AOItOoldaDgvUSILSo3L
6btdPrtcPbEo/uRTVRPPoZAbAh1fZkYJMyjhDSSXcNMQH+pkV5a7XdrnxIxPTGRG
HVyH41neQtGbqH6mid2PHMkwgu07nM3A6RngatgCdTer9zQoKJHyBApPNeNgJgH6
0BGM+RFq7q89w1DTj18zeTyGqHNFkIwgtnJzFyO+B2XleJINugHA64wcZr+shncB
lA2c5uk5jR+mUYyZDDl34bSb+hxnV29qao6pK0xXeXpXIs/NX2NGjVxZOob4Mkdi
o2cNGJHc+6Zr9UhhcyNZjgKnvETq9Emd8VRY+WCv2hikLyhF3HqgiIZd8zvn/yk1
gPxkQ5Tm4xxvvq0OKmOZK8l+hfZx6AYDlf7ej0gcWtSS6Cvu5zHbugRqh5jnxV/v
faci9wHYTfmJ0A6aBVmknpjZbyvKcL5kwlWj9Omvw5Ip3IgWJJk8jSaYtlu3zM63
Nwf9JtmYhST/WSMDmu2dnajkXjjO11INb9I/bbEFa0nOipFGc/T2L/Coc3cOZayh
jWZSaX5LaAzHHjcng6WMxwLkFM1JAbBzs/3GkDpv0mztO+7skb6iQ12LAEpmJURw
3kAP+HwV96LOPNdeE4yBFxgX0b3xdxA61GU5wSesVywlVP+i2k+KYTlerj1KjL0=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICZTCCAeugAwIBAgIQeI8nXIESUiClBNAt3bpz9DAKBggqhkjOPQQDAzB0MQsw
CQYDVQQGEwJQTDEhMB8GA1UEChMYQXNzZWNvIERhdGEgU3lzdGVtcyBTLkEuMScw
JQYDVQQLEx5DZXJ0dW0gQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkxGTAXBgNVBAMT
EENlcnR1bSBFQy0zODQgQ0EwHhcNMTgwMzI2MDcyNDU0WhcNNDMwMzI2MDcyNDU0
WjB0MQswCQYDVQQGEwJQTDEhMB8GA1UEChMYQXNzZWNvIERhdGEgU3lzdGVtcyBT
LkEuMScwJQYDVQQLEx5DZXJ0dW0gQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkxGTAX
BgNVBAMTEENlcnR1bSBFQy0zODQgQ0EwdjAQBgcqhkjOPQIBBgUrgQQAIgNiAATE
KI6rGFtqvm5kN2PkzeyrOvfMobgOgknXhimfoZTy42B4mIF4Bk3y7JoOV2CDn7Tm
Fy8as10CW4kjPMIRBSqniBMY81CE1700LCeJVf/OTOffph8oxPBUw7l8t1Ot68Kj
QjBAMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFI0GZnQkdjrzife81r1HfS+8
EF9LMA4GA1UdDwEB/wQEAwIBBjAKBggqhkjOPQQDAwNoADBlAjADVS2m5hjEfO/J
UG7BJw+ch69u1RsIGL2SKcHvlJF40jocVYli5RsJHrpka/F2tNQCMQC0QoSZ/6vn
nvuRlydd3LBbMHHOXjgaatkl5+r3YZJW+OraNsKHZZYuciUvf9/DE8k=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIDuzCCAqOgAwIBAgIDBETAMA0GCSqGSIb3DQEBBQUAMH4xCzAJBgNVBAYTAlBM
MSIwIAYDVQQKExlVbml6ZXRvIFRlY2hub2xvZ2llcyBTLkEuMScwJQYDVQQLEx5D
ZXJ0dW0gQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkxIjAgBgNVBAMTGUNlcnR1bSBU
cnVzdGVkIE5ldHdvcmsgQ0EwHhcNMDgxMDIyMTIwNzM3WhcNMjkxMjMxMTIwNzM3
WjB+MQswCQYDVQQGEwJQTDEiMCAGA1UEChMZVW5pemV0byBUZWNobm9sb2dpZXMg
Uy5BLjEnMCUGA1UECxMeQ2VydHVtIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MSIw
IAYDVQQDExlDZXJ0dW0gVHJ1c3RlZCBOZXR3b3JrIENBMIIBIjANBgkqhkiG9w0B
AQEFAAOCAQ8AMIIBCgKCAQEA4/t9o3K6wvDJFIf1awFO4W5AB7ptJ11/91sts1rH
UV+rpDKmYYe2bg+G0jACl/jXaVehGDldamR5xgFZrDwxSjh80gTSSyjoIF87B6LM
TXPb865Px1bVWqeWifrzq2jUI4ZZJ88JJ7ysbnKDHDBy3+Ci6dLhdHUZvSqeexVU
BBvXQzmtVSjF4hq79MDkrjhJM8x2hZ85RdKknvISjFH4fOQtf/WsX+sWn7Et0brM
kUJ3TCXJkDhv2/DM+44el1k+1WBO5gUo7Ul5E0u6SNsv+XLTOcr+H9g0cvW0QM8x
AcPs3hEtF10fuFDRXhmnad4HMyjKUJX5p1TLVIZQRan5SQIDAQABo0IwQDAPBgNV
HRMBAf8EBTADAQH/MB0GA1UdDgQWBBQIds3LB/8k9sXN7buQvOKEN0Z19zAOBgNV
HQ8BAf8EBAMCAQYwDQYJKoZIhvcNAQEFBQADggEBAKaorSLOAT2mo/9i0Eidi15y
sHhE49wcrwn9I0j6vSrEuVUEtRCjjSfeC4Jj0O7eDDd5QVsisrCaQVymcODU0HfL
I9MA4GxWL+FpDQ3Zqr8hgVDZBqWo/5U30Kr+4rP1mS1FhIrlQgnXdAIv94nYmem8
J9RHjboNRhx3zxSkHLmkMcScKHQDNP8zGSal6Q10tz6XxnboJ5ajZt3hrvJBW8qY
VoNzcOSGGtIxQbovvi0TWnZvTuhOgQ4/WwMioBK+ZlgRSssDxLQqKi2WF+A5VLxI
03YnnZotBqbJ7DnSq9ufmgsnAjUpsUCV5/nonFWIGUbWtzT1fs45mtk48VH3Tyw=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIF0jCCA7qgAwIBAgIQIdbQSk8lD8kyN/yqXhKN6TANBgkqhkiG9w0BAQ0FADCB
gDELMAkGA1UEBhMCUEwxIjAgBgNVBAoTGVVuaXpldG8gVGVjaG5vbG9naWVzIFMu
QS4xJzAlBgNVBAsTHkNlcnR1bSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTEkMCIG
A1UEAxMbQ2VydHVtIFRydXN0ZWQgTmV0d29yayBDQSAyMCIYDzIwMTExMDA2MDgz
OTU2WhgPMjA0NjEwMDYwODM5NTZaMIGAMQswCQYDVQQGEwJQTDEiMCAGA1UEChMZ
VW5pemV0byBUZWNobm9sb2dpZXMgUy5BLjEnMCUGA1UECxMeQ2VydHVtIENlcnRp
ZmljYXRpb24gQXV0aG9yaXR5MSQwIgYDVQQDExtDZXJ0dW0gVHJ1c3RlZCBOZXR3
b3JrIENBIDIwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC9+Xj45tWA
DGSdhhuWZGc/IjoedQF97/tcZ4zJzFxrqZHmuULlIEub2pt7uZld2ZuAS9eEQCsn
0+i6MLs+CRqnSZXvK0AkwpfHp+6bJe+oCgCXhVqqndwpyeI1B+twTUrWwbNWuKFB
OJvR+zF/j+Bf4bE/D44WSWDXBo0Y+aomEKsq09DRZ40bRr5HMNUuctHFY9rnY3lE
fktjJImGLjQ/KUxSiyqnwOKRKIm5wFv5HdnnJ63/mgKXwcZQkpsCLL2puTRZCr+E
Sv/f/rOf69me4Jgj7KZrdxYq28ytOxykh9xGc14ZYmhFV+SQgkK7QtbwYeDBoz1m
o130GO6IyY0XRSmZMnUCMe4pJshrAua1YkV/NxVaI2iJ1D7eTiew8EAMvE0Xy02i
sx7QBlrd9pPPV3WZ9fqGGmd4s7+W/jTcvedSVuWz5XV710GRBdxdaeOVDUO5/IOW
OZV7bIBaTxNyxtd9KXpEulKkKtVBRgkg/iKgtlswjbyJDNXXcPiHUv3a76xRLgez
Tv7QCdpw75j6VuZt27VXS9zlLCUVyJ4ueE742pyehizKV/Ma5ciSixqClnrDvFAS
adgOWkaLOusm+iPJtrCBvkIApPjW/jAux9JG9uWOdf3yzLnQh1vMBhBgu4M1t15n
3kfsmUjxpKEV/q2MYo45VU85FrmxY53/twIDAQABo0IwQDAPBgNVHRMBAf8EBTAD
AQH/MB0GA1UdDgQWBBS2oVQ5AsOgP46KvPrU+Bym0ToO/TAOBgNVHQ8BAf8EBAMC
AQYwDQYJKoZIhvcNAQENBQADggIBAHGlDs7k6b8/ONWJWsQCYftMxRQXLYtPU2sQ
F/xlhMcQSZDe28cmk4gmb3DWAl45oPePq5a1pRNcgRRtDoGCERuKTsZPpd1iHkTf
CVn0W3cLN+mLIMb4Ck4uWBzrM9DPhmDJ2vuAL55MYIR4PSFk1vtBHxgP58l1cb29
XN40hz5BsA72udY/CROWFC/emh1auVbONTqwX3BNXuMp8SMoclm2q8KMZiYcdywm
djWLKKdpoPk79SPdhRB0yZADVpHnr7pH1BKXESLjokmUbOe3lEu6LaTaM4tMpkT/
WjzGHWTYtTHkpjx6qFcL2+1hGsvxznN3Y6SHb0xRONbkX8eftoEq5IVIeVheO/jb
AoJnwTnbw3RLPTYe+SmTiGhbqEQZIfCn6IENLOiTNrQ3ssqwGyZ6miUfmpqAnksq
P/ujmv5zMnHCnsZy4YpoJ/HkD7TETKVhk/iXEAcqMCWpuchxuO9ozC1+9eB+D4Ko
b7a6bINDd82Kkhehnlt4Fj1F4jNy3eFmypnTycUm/Q1oBEauttmbjL4ZvrHG8hnj
XALKLNhvSgfZyTXaQHXyxKcZb55CEJh15pWLYLztxRLXis7VmFxWlgPF7ncGNf/P
5O4/E2Hu29othfDNrp2yGAlFw5Khchf8R7agCyzxxN5DaAhqXzvwdmP7zAYspsbi
DrW5viSP
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFwDCCA6igAwIBAgIQHr9ZULjJgDdMBvfrVU+17TANBgkqhkiG9w0BAQ0FADB6
MQswCQYDVQQGEwJQTDEhMB8GA1UEChMYQXNzZWNvIERhdGEgU3lzdGVtcyBTLkEu
MScwJQYDVQQLEx5DZXJ0dW0gQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkxHzAdBgNV
BAMTFkNlcnR1bSBUcnVzdGVkIFJvb3QgQ0EwHhcNMTgwMzE2MTIxMDEzWhcNNDMw
MzE2MTIxMDEzWjB6MQswCQYDVQQGEwJQTDEhMB8GA1UEChMYQXNzZWNvIERhdGEg
U3lzdGVtcyBTLkEuMScwJQYDVQQLEx5DZXJ0dW0gQ2VydGlmaWNhdGlvbiBBdXRo
b3JpdHkxHzAdBgNVBAMTFkNlcnR1bSBUcnVzdGVkIFJvb3QgQ0EwggIiMA0GCSqG
SIb3DQEBAQUAA4ICDwAwggIKAoICAQDRLY67tzbqbTeRn06TpwXkKQMlzhyC93yZ
n0EGze2jusDbCSzBfN8pfktlL5On1AFrAygYo9idBcEq2EXxkd7fO9CAAozPOA/q
p1x4EaTByIVcJdPTsuclzxFUl6s1wB52HO8AU5853BSlLCIls3Jy/I2z5T4IHhQq
NwuIPMqw9MjCoa68wb4pZ1Xi/K1ZXP69VyywkI3C7Te2fJmItdUDmj0VDT06qKhF
8JVOJVkdzZhpu9PMMsmN74H+rX2Ju7pgE8pllWeg8xn2A1bUatMn4qGtg/BKEiJ3
HAVz4hlxQsDsdUaakFjgao4rpUYwBI4Zshfjvqm6f1bxJAPXsiEodg42MEx51UGa
mqi4NboMOvJEGyCI98Ul1z3G4z5D3Yf+xOr1Uz5MZf87Sst4WmsXXw3Hw09Omiqi
7VdNIuJGmj8PkTQkfVXjjJU30xrwCSss0smNtA0Aq2cpKNgB9RkEth2+dv5yXMSF
ytKAQd8FqKPVhJBPC/PgP5sZ0jeJP/J7UhyM9uH3PAeXjA6iWYEMspA90+NZRu0P
qafegGtaqge2Gcu8V/OXIXoMsSt0Puvap2ctTMSYnjYJdmZm/Bo/6khUHL4wvYBQ
v3y1zgD2DGHZ5yQD4OMBgQ692IU0iL2yNqh7XAjlRICMb/gv1SHKHRzQ+8S1h9E6
Tsd2tTVItQIDAQABo0IwQDAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBSM+xx1
vALTn04uSNn5YFSqxLNP+jAOBgNVHQ8BAf8EBAMCAQYwDQYJKoZIhvcNAQENBQAD
ggIBAEii1QALLtA/vBzVtVRJHlpr9OTy4EA34MwUe7nJ+jW1dReTagVphZzNTxl4
WxmB82M+w85bj/UvXgF2Ez8sALnNllI5SW0ETsXpD4YN4fqzX4IS8TrOZgYkNCvo
zMrnadyHncI013nR03e4qllY/p0m+jiGPp2Kh2RX5Rc64vmNueMzeMGQ2Ljdt4NR
5MTMI9UGfOZR0800McD2RrsLrfw9EAUqO0qRJe6M1ISHgCq8CYyqOhNf6DR5UMEQ
GfnTKB7U0VEwKbOukGfWHwpjscWpxkIxYxeU72nLL/qMFH3EQxiJ2fAyQOaA4kZf
5ePBAFmo+eggvIksDkc0C+pXwlM2/KfUrzHN/gLldfq5Jwn58/U7yn2fqSLLiMmq
0Uc9NneoWWRrJ8/vJ8HjJLWG965+Mk2weWjROeiQWMODvA8s1pfrzgzhIMfatz7D
P78v3DSk+yshzWePS/Tj6tQ/50+6uaWTRRxmHyH6ZF5v4HaUMst19W7l9o/HuKTM
qJZ9ZPskWkoDbGs4xugDQ5r3V7mzKWmTOPQD8rv7gmsHINFSH5pkAnuYZttcTVoP
0ISVoDwUQwbKytu4QTbaakRnh6+v40URFWkIsr4WOZckbxJF0WddCajJFdr60qZf
E2Efv4WstK2tBZQIgx51F9NxO5NQI1mg7TyRVJ12AMXDuDjb
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIC2zCCAmCgAwIBAgIQfMmPK4TX3+oPyWWa00tNljAKBggqhkjOPQQDAzBIMQsw
CQYDVQQGEwJERTEVMBMGA1UEChMMRC1UcnVzdCBHbWJIMSIwIAYDVQQDExlELVRS
VVNUIEJSIFJvb3QgQ0EgMSAyMDIwMB4XDTIwMDIxMTA5NDUwMFoXDTM1MDIxMTA5
NDQ1OVowSDELMAkGA1UEBhMCREUxFTATBgNVBAoTDEQtVHJ1c3QgR21iSDEiMCAG
A1UEAxMZRC1UUlVTVCBCUiBSb290IENBIDEgMjAyMDB2MBAGByqGSM49AgEGBSuB
BAAiA2IABMbLxyjR+4T1mu9CFCDhQ2tuda38KwOE1HaTJddZO0Flax7mNCq7dPYS
zuht56vkPE4/RAiLzRZxy7+SmfSk1zxQVFKQhYN4lGdnoxwJGT11NIXe7WB9xwy0
QVK5buXuQqOCAQ0wggEJMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFHOREKv/
VbNafAkl1bK6CKBrqx9tMA4GA1UdDwEB/wQEAwIBBjCBxgYDVR0fBIG+MIG7MD6g
PKA6hjhodHRwOi8vY3JsLmQtdHJ1c3QubmV0L2NybC9kLXRydXN0X2JyX3Jvb3Rf
Y2FfMV8yMDIwLmNybDB5oHegdYZzbGRhcDovL2RpcmVjdG9yeS5kLXRydXN0Lm5l
dC9DTj1ELVRSVVNUJTIwQlIlMjBSb290JTIwQ0ElMjAxJTIwMjAyMCxPPUQtVHJ1
c3QlMjBHbWJILEM9REU/Y2VydGlmaWNhdGVyZXZvY2F0aW9ubGlzdDAKBggqhkjO
PQQDAwNpADBmAjEAlJAtE/rhY/hhY+ithXhUkZy4kzg+GkHaQBZTQgjKL47xPoFW
wKrY7RjEsK70PvomAjEA8yjixtsrmfu3Ubgko6SUeho/5jbiA1czijDLgsfWFBHV
dWNbFJWcHwHP2NVypw87
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFqTCCA5GgAwIBAgIQczswBEhb2U14LnNLyaHcZjANBgkqhkiG9w0BAQ0FADBI
MQswCQYDVQQGEwJERTEVMBMGA1UEChMMRC1UcnVzdCBHbWJIMSIwIAYDVQQDExlE
LVRSVVNUIEJSIFJvb3QgQ0EgMiAyMDIzMB4XDTIzMDUwOTA4NTYzMVoXDTM4MDUw
OTA4NTYzMFowSDELMAkGA1UEBhMCREUxFTATBgNVBAoTDEQtVHJ1c3QgR21iSDEi
MCAGA1UEAxMZRC1UUlVTVCBCUiBSb290IENBIDIgMjAyMzCCAiIwDQYJKoZIhvcN
AQEBBQADggIPADCCAgoCggIBAK7/CVmRgApKaOYkP7in5Mg6CjoWzckjYaCTcfKr
i3OPoGdlYNJUa2NRb0kz4HIHE304zQaSBylSa053bATTlfrdTIzZXcFhfUvnKLNE
gXtRr90zsWh81k5M/itoucpmacTsXld/9w3HnDY25QdgrMBM6ghs7wZ8T1soegj8
k12b9py0i4a6Ibn08OhZWiihNIQaJZG2tY/vsvmA+vk9PBFy2OMvhnbFeSzBqZCT
Rphny4NqoFAjpzv2gTng7fC5v2Xx2Mt6++9zA84A9H3X4F07ZrjcjrqDy4d2A/wl
2ecjbwb9Z/Pg/4S8R7+1FhhGaRTMBffb00msa8yr5LULQyReS2tNZ9/WtT5PeB+U
cSTq3nD88ZP+npNa5JRal1QMNXtfbO4AHyTsA7oC9Xb0n9Sa7YUsOCIvx9gvdhFP
/Wxc6PWOJ4d/GUohR5AdeY0cW/jPSoXk7bNbjb7EZChdQcRurDhaTyN0dKkSw/bS
uREVMweR2Ds3OmMwBtHFIjYoYiMQ4EbMl6zWK11kJNXuHA7e+whadSr2Y23OC0K+
0bpwHJwh5Q8xaRfX/Aq03u2AnMuStIv13lmiWAmlY0cL4UEyNEHZmrHZqLAbWt4N
DfTisl01gLmB1IRpkQLLddCNxbU9CZEJjxShFHR5PtbJFR2kWVki3PaKRT08EtY+
XTIvAgMBAAGjgY4wgYswDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUZ5Dw1t61
GNVGKX5cq/ieCLxklRAwDgYDVR0PAQH/BAQDAgEGMEkGA1UdHwRCMEAwPqA8oDqG
OGh0dHA6Ly9jcmwuZC10cnVzdC5uZXQvY3JsL2QtdHJ1c3RfYnJfcm9vdF9jYV8y
XzIwMjMuY3JsMA0GCSqGSIb3DQEBDQUAA4ICAQA097N3U9swFrktpSHxQCF16+tI
FoE9c+CeJyrrd6kTpGoKWloUMz1oH4Guaf2Mn2VsNELZLdB/eBaxOqwjMa1ef67n
riv6uvw8l5VAk1/DLQOj7aRvU9f6QA4w9QAgLABMjDu0ox+2v5Eyq6+SmNMW5tTR
VFxDWy6u71cqqLRvpO8NVhTaIasgdp4D/Ca4nj8+AybmTNudX0KEPUUDAxxZiMrc
LmEkWqTqJwtzEr5SswrPMhfiHocaFpVIbVrg0M8JkiZmkdijYQ6qgYF/6FKC0ULn
4B0Y+qSFNueG4A3rvNTJ1jxD8V1Jbn6Bm2m1iWKPiFLY1/4nwSPFyysCu7Ff/vtD
hQNGvl3GyiEm/9cCnnRK3PgTFbGBVzbLZVzRHTF36SXDw7IyN9XxmAnkbWOACKsG
koHU6XCPpz+y7YaMgmo1yEJagtFSGkUPFaUA8JR7ZSdXOUPPfH/mvTWze/EZTN46
ls/pdu4D58JDUjxqgejBWoC9EV2Ta/vH5mQ/u2kc6d0li690yVRAysuTEwrt+2aS
Ecr1wPrYg1UDfNPFIkZ1cGt5SAYqgpq/5usWDiJFAbzdNpQ0qTUmiteXue4Icr80
knCDgKs4qllo3UCkGJCy89UDyibK79XH4I9TjvAA46jtn/mtd+ArY0+ew+43u3gJ
hJ65bvspmZDogNOfJA==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIC2zCCAmCgAwIBAgIQXwJB13qHfEwDo6yWjfv/0DAKBggqhkjOPQQDAzBIMQsw
CQYDVQQGEwJERTEVMBMGA1UEChMMRC1UcnVzdCBHbWJIMSIwIAYDVQQDExlELVRS
VVNUIEVWIFJvb3QgQ0EgMSAyMDIwMB4XDTIwMDIxMTEwMDAwMFoXDTM1MDIxMTA5
NTk1OVowSDELMAkGA1UEBhMCREUxFTATBgNVBAoTDEQtVHJ1c3QgR21iSDEiMCAG
A1UEAxMZRC1UUlVTVCBFViBSb290IENBIDEgMjAyMDB2MBAGByqGSM49AgEGBSuB
BAAiA2IABPEL3YZDIBnfl4XoIkqbz52Yv7QFJsnL46bSj8WeeHsxiamJrSc8ZRCC
/N/DnU7wMyPE0jL1HLDfMxddxfCxivnvubcUyilKwg+pf3VlSSowZ/Rk99Yad9rD
wpdhQntJraOCAQ0wggEJMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFH8QARY3
OqQo5FD4pPfsazK2/umLMA4GA1UdDwEB/wQEAwIBBjCBxgYDVR0fBIG+MIG7MD6g
PKA6hjhodHRwOi8vY3JsLmQtdHJ1c3QubmV0L2NybC9kLXRydXN0X2V2X3Jvb3Rf
Y2FfMV8yMDIwLmNybDB5oHegdYZzbGRhcDovL2RpcmVjdG9yeS5kLXRydXN0Lm5l
dC9DTj1ELVRSVVNUJTIwRVYlMjBSb290JTIwQ0ElMjAxJTIwMjAyMCxPPUQtVHJ1
c3QlMjBHbWJILEM9REU/Y2VydGlmaWNhdGVyZXZvY2F0aW9ubGlzdDAKBggqhkjO
PQQDAwNpADBmAjEAyjzGKnXCXnViOTYAYFqLwZOZzNnbQTs7h5kXO9XMT8oi96CA
y/m0sRtW9XLS/BnRAjEAkfcwkz8QRitxpNA7RJvAKQIFskF3UfN5Wp6OFKBOQtJb
gfM0agPnIjhQW+0ZT0MW
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFqTCCA5GgAwIBAgIQaSYJfoBLTKCnjHhiU19abzANBgkqhkiG9w0BAQ0FADBI
MQswCQYDVQQGEwJERTEVMBMGA1UEChMMRC1UcnVzdCBHbWJIMSIwIAYDVQQDExlE
LVRSVVNUIEVWIFJvb3QgQ0EgMiAyMDIzMB4XDTIzMDUwOTA5MTAzM1oXDTM4MDUw
OTA5MTAzMlowSDELMAkGA1UEBhMCREUxFTATBgNVBAoTDEQtVHJ1c3QgR21iSDEi
MCAGA1UEAxMZRC1UUlVTVCBFViBSb290IENBIDIgMjAyMzCCAiIwDQYJKoZIhvcN
AQEBBQADggIPADCCAgoCggIBANiOo4mAC7JXUtypU0w3uX9jFxPvp1sjW2l1sJkK
F8GLxNuo4MwxusLyzV3pt/gdr2rElYfXR8mV2IIEUD2BCP/kPbOx1sWy/YgJ25yE
7CUXFId/MHibaljJtnMoPDT3mfd/06b4HEV8rSyMlD/YZxBTfiLNTiVR8CUkNRFe
EMbsh2aJgWi6zCudR3Mfvc2RpHJqnKIbGKBv7FD0fUDCqDDPvXPIEysQEx6Lmqg6
lHPTGGkKSv/BAQP/eX+1SH977ugpbzZMlWGG2Pmic4ruri+W7mjNPU0oQvlFKzIb
RlUWaqZLKfm7lVa/Rh3sHZMdwGWyH6FDrlaeoLGPaxK3YG14C8qKXO0elg6DpkiV
jTujIcSuWMYAsoS0I6SWhjW42J7YrDRJmGOVxcttSEfi8i4YHtAxq9107PncjLgc
jmgjutDzUNzPZY9zOjLHfP7KgiJPvo5iR2blzYfi6NUPGJ/lBHJLRjwQ8kTCZFZx
TnXonMkmdMV9WdEKWw9t/p51HBjGGjp82A0EzM23RWV6sY+4roRIPrN6TagD4uJ+
ARZZaBhDM7DS3LAaQzXupdqpRlyuhoFBAUp0JuyfBr/CBTdkdXgpaP3F9ev+R/nk
hbDhezGdpn9yo7nELC7MmVcOIQxFAZRl62UJxmMiCzNJkkg8/M3OsD6Onov4/knF
NXJHAgMBAAGjgY4wgYswDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUqvyREBuH
kV8Wub9PS5FeAByxMoAwDgYDVR0PAQH/BAQDAgEGMEkGA1UdHwRCMEAwPqA8oDqG
OGh0dHA6Ly9jcmwuZC10cnVzdC5uZXQvY3JsL2QtdHJ1c3RfZXZfcm9vdF9jYV8y
XzIwMjMuY3JsMA0GCSqGSIb3DQEBDQUAA4ICAQCTy6UfmRHsmg1fLBWTxj++EI14
QvBukEdHjqOSMo1wj/Zbjb6JzkcBahsgIIlbyIIQbODnmaprxiqgYzWRaoUlrRc4
pZt+UPJ26oUFKidBK7GB0aL2QHWpDsvxVUjY7NHss+jOFKE17MJeNRqrphYBBo7q
3C+jisosketSjl8MmxfPy3MHGcRqwnNU73xDUmPBEcrCRbH0O1P1aa4846XerOhU
t7KR/aypH/KH5BfGSah82ApB9PI+53c0BFLd6IHyTS9URZ0V4U/M5d40VxDJI3IX
cI1QcB9WbMy5/zpaT2N6w25lBx2Eof+pDGOJbbJAiDnXH3dotfyc1dZnaVuodNv8
ifYbMvekJKZ2t0dT741Jj6m2g1qllpBFYfXeA08mD6iL8AOWsKwV0HFaanuU5nCT
2vFp4LJiTZ6P/4mdm13NRemUAiKN4DV/6PEEeXFsVIP4M7kFMhtYVRFP0OUnR3Hs
7dpn1mKmS00PaaLJvOwiS5THaJQXfuKOKD62xur1NGyfN4gHONuGcfrNlUhDbqNP
gofXNJhuS5N5YHVpD/Aa1VP6IQzCP+k/HxiMkl14p3ZnGbuy6n/pcAlWVqOwDAst
Nl7F6cTVg8uGF5csbBNvh1qvSaYd2804BC5f4ko1Di1L+KIkBI3Y4WNeApI02phh
XBxvWHZks/wCuPWdCg==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIEMzCCAxugAwIBAgIDCYPzMA0GCSqGSIb3DQEBCwUAME0xCzAJBgNVBAYTAkRF
MRUwEwYDVQQKDAxELVRydXN0IEdtYkgxJzAlBgNVBAMMHkQtVFJVU1QgUm9vdCBD
bGFzcyAzIENBIDIgMjAwOTAeFw0wOTExMDUwODM1NThaFw0yOTExMDUwODM1NTha
ME0xCzAJBgNVBAYTAkRFMRUwEwYDVQQKDAxELVRydXN0IEdtYkgxJzAlBgNVBAMM
HkQtVFJVU1QgUm9vdCBDbGFzcyAzIENBIDIgMjAwOTCCASIwDQYJKoZIhvcNAQEB
BQADggEPADCCAQoCggEBANOySs96R+91myP6Oi/WUEWJNTrGa9v+2wBoqOADER03
UAifTUpolDWzU9GUY6cgVq/eUXjsKj3zSEhQPgrfRlWLJ23DEE0NkVJD2IfgXU42
tSHKXzlABF9bfsyjxiupQB7ZNoTWSPOSHjRGICTBpFGOShrvUD9pXRl/RcPHAY9R
ySPocq60vFYJfxLLHLGvKZAKyVXMD9O0Gu1HNVpK7ZxzBCHQqr0ME7UAyiZsxGsM
lFqVlNpQmvH/pStmMaTJOKDfHR+4CS7zp+hnUquVH+BGPtikw8paxTGA6Eian5Rp
/hnd2HN8gcqW3o7tszIFZYQ05ub9VxC1X3a/L7AQDcUCAwEAAaOCARowggEWMA8G
A1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFP3aFMSfMN4hvR5COfyrYyNJ4PGEMA4G
A1UdDwEB/wQEAwIBBjCB0wYDVR0fBIHLMIHIMIGAoH6gfIZ6bGRhcDovL2RpcmVj
dG9yeS5kLXRydXN0Lm5ldC9DTj1ELVRSVVNUJTIwUm9vdCUyMENsYXNzJTIwMyUy
MENBJTIwMiUyMDIwMDksTz1ELVRydXN0JTIwR21iSCxDPURFP2NlcnRpZmljYXRl
cmV2b2NhdGlvbmxpc3QwQ6BBoD+GPWh0dHA6Ly93d3cuZC10cnVzdC5uZXQvY3Js
L2QtdHJ1c3Rfcm9vdF9jbGFzc18zX2NhXzJfMjAwOS5jcmwwDQYJKoZIhvcNAQEL
BQADggEBAH+X2zDI36ScfSF6gHDOFBJpiBSVYEQBrLLpME+bUMJm2H6NMLVwMeni
acfzcNsgFYbQDfC+rAF1hM5+n02/t2A7nPPKHeJeaNijnZflQGDSNiH+0LS4F9p0
o3/U37CYAqxva2ssJSRyoWXuJVrl5jLn8t+rSfrzkGkj2wTZ51xY/GXUl77M/C4K
zCUqNQT4YJEVdT1B/yMfGchs64JTBKbkTCJNjYy6zltz7GRUUG3RnFX7acM2w4y8
PIWmawomDeCTmGCufsYkl4phX5GOZpIJhzbNi5stPvZR1FDUWSi9g/LMKHtThm3Y
Johw1+qRzT65ysCQblrGXnRl11z+o+I=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIEQzCCAyugAwIBAgIDCYP0MA0GCSqGSIb3DQEBCwUAMFAxCzAJBgNVBAYTAkRF
MRUwEwYDVQQKDAxELVRydXN0IEdtYkgxKjAoBgNVBAMMIUQtVFJVU1QgUm9vdCBD
bGFzcyAzIENBIDIgRVYgMjAwOTAeFw0wOTExMDUwODUwNDZaFw0yOTExMDUwODUw
NDZaMFAxCzAJBgNVBAYTAkRFMRUwEwYDVQQKDAxELVRydXN0IEdtYkgxKjAoBgNV
BAMMIUQtVFJVU1QgUm9vdCBDbGFzcyAzIENBIDIgRVYgMjAwOTCCASIwDQYJKoZI
hvcNAQEBBQADggEPADCCAQoCggEBAJnxhDRwui+3MKCOvXwEz75ivJn9gpfSegpn
ljgJ9hBOlSJzmY3aFS3nBfwZcyK3jpgAvDw9rKFs+9Z5JUut8Mxk2og+KbgPCdM0
3TP1YtHhzRnp7hhPTFiu4h7WDFsVWtg6uMQYZB7jM7K1iXdODL/ZlGsTl28So/6Z
qQTMFexgaDbtCHu39b+T7WYxg4zGcTSHThfqr4uRjRxWQa4iN1438h3Z0S0NL2lR
p75mpoo6Kr3HGrHhFPC+Oh25z1uxav60sUYgovseO3Dvk5h9jHOW8sXvhXCtKSb8
HgQ+HKDYD8tSg2J87otTlZCpV6LqYQXY+U3EJ/pure3511H3a6UCAwEAAaOCASQw
ggEgMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFNOUikxiEyoZLsyvcop9Ntea
HNxnMA4GA1UdDwEB/wQEAwIBBjCB3QYDVR0fBIHVMIHSMIGHoIGEoIGBhn9sZGFw
Oi8vZGlyZWN0b3J5LmQtdHJ1c3QubmV0L0NOPUQtVFJVU1QlMjBSb290JTIwQ2xh
c3MlMjAzJTIwQ0ElMjAyJTIwRVYlMjAyMDA5LE89RC1UcnVzdCUyMEdtYkgsQz1E
RT9jZXJ0aWZpY2F0ZXJldm9jYXRpb25saXN0MEagRKBChkBodHRwOi8vd3d3LmQt
dHJ1c3QubmV0L2NybC9kLXRydXN0X3Jvb3RfY2xhc3NfM19jYV8yX2V2XzIwMDku
Y3JsMA0GCSqGSIb3DQEBCwUAA4IBAQA07XtaPKSUiO8aEXUHL7P+PPoeUSbrh/Yp
3uDx1MYkCenBz1UbtDDZzhr+BlGmFaQt77JLvyAoJUnRpjZ3NOhk31KxEcdzes05
nsKtjHEh8lprr988TlWvsoRlFIm5d8sqMb7Po23Pb0iUMkZv53GMoKaEGTcH8gNF
CSuGdXzfX2lXANtu2KZyIktQ1HWYVt+3GP9DQ1CuekR78HlR10M9p9OB0/DJT7na
xpeG0ILD5EJt/rDiZE4OJudANCa1CInXCGNjOCd1HjPqbqjdn5lPdE2BiYBL3ZqX
KVwvvoFBuYz/6n1gBp7N1z3TLqMVvKjmJuVvw9y4AyHqnxbxLFS1
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIDljCCAn6gAwIBAgIQC5McOtY5Z+pnI7/Dr5r0SzANBgkqhkiG9w0BAQsFADBl
MQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3
d3cuZGlnaWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJv
b3QgRzIwHhcNMTMwODAxMTIwMDAwWhcNMzgwMTE1MTIwMDAwWjBlMQswCQYDVQQG
EwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNl
cnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgRzIwggEi
MA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDZ5ygvUj82ckmIkzTz+GoeMVSA
n61UQbVH35ao1K+ALbkKz3X9iaV9JPrjIgwrvJUXCzO/GU1BBpAAvQxNEP4Htecc
biJVMWWXvdMX0h5i89vqbFCMP4QMls+3ywPgym2hFEwbid3tALBSfK+RbLE4E9Hp
EgjAALAcKxHad3A2m67OeYfcgnDmCXRwVWmvo2ifv922ebPynXApVfSr/5Vh88lA
bx3RvpO704gqu52/clpWcTs/1PPRCv4o76Pu2ZmvA9OPYLfykqGxvYmJHzDNw6Yu
YjOuFgJ3RFrngQo8p0Quebg/BLxcoIfhG69Rjs3sLPr4/m3wOnyqi+RnlTGNAgMB
AAGjQjBAMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgGGMB0GA1UdDgQW
BBTOw0q5mVXyuNtgv6l+vVa1lzan1jANBgkqhkiG9w0BAQsFAAOCAQEAyqVVjOPI
QW5pJ6d1Ee88hjZv0p3GeDgdaZaikmkuOGybfQTUiaWxMTeKySHMq2zNixya1r9I
0jJmwYrA8y8678Dj1JGG0VDjA9tzd29KOVPt3ibHtX2vK0LRdWLjSisCx1BL4Gni
lmwORGYQRI+tBev4eaymG+g3NJ1TyWGqolKvSnAWhsI6yLETcDbYz+70CjTVW0z9
B5yiutkBclzzTcHdDrEcDcRjvq30FPuJ7KJBDkzMyFdA0G4Dqs0MjomZmWzwPDCv
ON9vvKO+KSAnq3T/EyJ43pdSVR6DtVQgA+6uwE9W3jfMw3+qBCe703e4YtsXfJwo
IhNzbM8m9Yop5w==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICRjCCAc2gAwIBAgIQC6Fa+h3foLVJRK/NJKBs7DAKBggqhkjOPQQDAzBlMQsw
CQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cu
ZGlnaWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3Qg
RzMwHhcNMTMwODAxMTIwMDAwWhcNMzgwMTE1MTIwMDAwWjBlMQswCQYDVQQGEwJV
UzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQu
Y29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgRzMwdjAQBgcq
hkjOPQIBBgUrgQQAIgNiAAQZ57ysRGXtzbg/WPuNsVepRC0FFfLvC/8QdJ+1YlJf
Zn4f5dwbRXkLzMZTCp2NXQLZqVneAlr2lSoOjThKiknGvMYDOAdfVdp+CW7if17Q
RSAPWXYQ1qAk8C3eNvJsKTmjQjBAMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/
BAQDAgGGMB0GA1UdDgQWBBTL0L2p4ZgFUaFNN6KDec6NHSrkhDAKBggqhkjOPQQD
AwNnADBkAjAlpIFFAmsSS3V0T8gj43DydXLefInwz5FyYZ5eEJJZVrmDxxDnOOlY
JjZ91eQ0hjkCMHw2U/Aw5WJjOpnitqM7mzT6HtoQknFekROn3aRukswy1vUhZscv
6pZjamVFkpUBtA==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIDjjCCAnagAwIBAgIQAzrx5qcRqaC7KGSxHQn65TANBgkqhkiG9w0BAQsFADBh
MQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3
d3cuZGlnaWNlcnQuY29tMSAwHgYDVQQDExdEaWdpQ2VydCBHbG9iYWwgUm9vdCBH
MjAeFw0xMzA4MDExMjAwMDBaFw0zODAxMTUxMjAwMDBaMGExCzAJBgNVBAYTAlVT
MRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5j
b20xIDAeBgNVBAMTF0RpZ2lDZXJ0IEdsb2JhbCBSb290IEcyMIIBIjANBgkqhkiG
9w0BAQEFAAOCAQ8AMIIBCgKCAQEAuzfNNNx7a8myaJCtSnX/RrohCgiN9RlUyfuI
2/Ou8jqJkTx65qsGGmvPrC3oXgkkRLpimn7Wo6h+4FR1IAWsULecYxpsMNzaHxmx
1x7e/dfgy5SDN67sH0NO3Xss0r0upS/kqbitOtSZpLYl6ZtrAGCSYP9PIUkY92eQ
q2EGnI/yuum06ZIya7XzV+hdG82MHauVBJVJ8zUtluNJbd134/tJS7SsVQepj5Wz
tCO7TG1F8PapspUwtP1MVYwnSlcUfIKdzXOS0xZKBgyMUNGPHgm+F6HmIcr9g+UQ
vIOlCsRnKPZzFBQ9RnbDhxSJITRNrw9FDKZJobq7nMWxM4MphQIDAQABo0IwQDAP
BgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBhjAdBgNVHQ4EFgQUTiJUIBiV
5uNu5g/6+rkS7QYXjzkwDQYJKoZIhvcNAQELBQADggEBAGBnKJRvDkhj6zHd6mcY
1Yl9PMWLSn/pvtsrF9+wX3N3KjITOYFnQoQj8kVnNeyIv/iPsGEMNKSuIEyExtv4
NeF22d+mQrvHRAiGfzZ0JFrabA0UWTW98kndth/Jsw1HKj2ZL7tcu7XUIOGZX1NG
Fdtom/DzMNU+MeKNhJ7jitralj41E6Vf8PlwUHBHQRFXGU7Aj64GxJUTFy8bJZ91
8rGOmaFvE7FBcf6IKshPECBV1/MUReXgRPTqh5Uykw7+U0b6LJ3/iyK5S9kJRaTe
pLiaWN0bfVKfjllDiIGknibVb63dDcY3fe0Dkhvld1927jyNxF1WW6LZZm6zNTfl
MrY=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICPzCCAcWgAwIBAgIQBVVWvPJepDU1w6QP1atFcjAKBggqhkjOPQQDAzBhMQsw
CQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cu
ZGlnaWNlcnQuY29tMSAwHgYDVQQDExdEaWdpQ2VydCBHbG9iYWwgUm9vdCBHMzAe
Fw0xMzA4MDExMjAwMDBaFw0zODAxMTUxMjAwMDBaMGExCzAJBgNVBAYTAlVTMRUw
EwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20x
IDAeBgNVBAMTF0RpZ2lDZXJ0IEdsb2JhbCBSb290IEczMHYwEAYHKoZIzj0CAQYF
K4EEACIDYgAE3afZu4q4C/sLfyHS8L6+c/MzXRq8NOrexpu80JX28MzQC7phW1FG
fp4tn+6OYwwX7Adw9c+ELkCDnOg/QW07rdOkFFk2eJ0DQ+4QE2xy3q6Ip6FrtUPO
Z9wj/wMco+I+o0IwQDAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBhjAd
BgNVHQ4EFgQUs9tIpPmhxdiuNkHMEWNpYim8S8YwCgYIKoZIzj0EAwMDaAAwZQIx
AK288mw/EkrRLTnDCgmXc/SINoyIJ7vmiI1Qhadj+Z4y3maTD/HMsQmP3Wyr+mt/
oAIwOWZbwmSNuJ5Q3KjVSaLtx9zRSX8XAbjIho9OjIgrqJqpisXRAL34VOKa5Vt8
sycX
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICGTCCAZ+gAwIBAgIQCeCTZaz32ci5PhwLBCou8zAKBggqhkjOPQQDAzBOMQsw
CQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xJjAkBgNVBAMTHURp
Z2lDZXJ0IFRMUyBFQ0MgUDM4NCBSb290IEc1MB4XDTIxMDExNTAwMDAwMFoXDTQ2
MDExNDIzNTk1OVowTjELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJ
bmMuMSYwJAYDVQQDEx1EaWdpQ2VydCBUTFMgRUNDIFAzODQgUm9vdCBHNTB2MBAG
ByqGSM49AgEGBSuBBAAiA2IABMFEoc8Rl1Ca3iOCNQfN0MsYndLxf3c1TzvdlHJS
7cI7+Oz6e2tYIOyZrsn8aLN1udsJ7MgT9U7GCh1mMEy7H0cKPGEQQil8pQgO4CLp
0zVozptjn4S1mU1YoI71VOeVyaNCMEAwHQYDVR0OBBYEFMFRRVBZqz7nLFr6ICIS
B4CIfBFqMA4GA1UdDwEB/wQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MAoGCCqGSM49
BAMDA2gAMGUCMQCJao1H5+z8blUD2WdsJk6Dxv3J+ysTvLd6jLRl0mlpYxNjOyZQ
LgGheQaRnUi/wr4CMEfDFXuxoJGZSZOoPHzoRgaLLPIxAJSdYsiJvRmEFOml+wG4
DXZDjC5Ty3zfDBeWUA==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFZjCCA06gAwIBAgIQCPm0eKj6ftpqMzeJ3nzPijANBgkqhkiG9w0BAQwFADBN
MQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xJTAjBgNVBAMT
HERpZ2lDZXJ0IFRMUyBSU0E0MDk2IFJvb3QgRzUwHhcNMjEwMTE1MDAwMDAwWhcN
NDYwMTE0MjM1OTU5WjBNMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQs
IEluYy4xJTAjBgNVBAMTHERpZ2lDZXJ0IFRMUyBSU0E0MDk2IFJvb3QgRzUwggIi
MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCz0PTJeRGd/fxmgefM1eS87IE+
ajWOLrfn3q/5B03PMJ3qCQuZvWxX2hhKuHisOjmopkisLnLlvevxGs3npAOpPxG0
2C+JFvuUAT27L/gTBaF4HI4o4EXgg/RZG5Wzrn4DReW+wkL+7vI8toUTmDKdFqgp
wgscONyfMXdcvyej/Cestyu9dJsXLfKB2l2w4SMXPohKEiPQ6s+d3gMXsUJKoBZM
pG2T6T867jp8nVid9E6P/DsjyG244gXazOvswzH016cpVIDPRFtMbzCe88zdH5RD
nU1/cHAN1DrRN/BsnZvAFJNY781BOHW8EwOVfH/jXOnVDdXifBBiqmvwPXbzP6Po
sMH976pXTayGpxi0KcEsDr9kvimM2AItzVwv8n/vFfQMFawKsPHTDU9qTXeXAaDx
Zre3zu/O7Oyldcqs4+Fj97ihBMi8ez9dLRYiVu1ISf6nL3kwJZu6ay0/nTvEF+cd
Lvvyz6b84xQslpghjLSR6Rlgg/IwKwZzUNWYOwbpx4oMYIwo+FKbbuH2TbsGJJvX
KyY//SovcfXWJL5/MZ4PbeiPT02jP/816t9JXkGPhvnxd3lLG7SjXi/7RgLQZhNe
XoVPzthwiHvOAbWWl9fNff2C+MIkwcoBOU+NosEUQB+cZtUMCUbW8tDRSHZWOkPL
tgoRObqME2wGtZ7P6wIDAQABo0IwQDAdBgNVHQ4EFgQUUTMc7TZArxfTJc1paPKv
TiM+s0EwDgYDVR0PAQH/BAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcN
AQEMBQADggIBAGCmr1tfV9qJ20tQqcQjNSH/0GEwhJG3PxDPJY7Jv0Y02cEhJhxw
GXIeo8mH/qlDZJY6yFMECrZBu8RHANmfGBg7sg7zNOok992vIGCukihfNudd5N7H
PNtQOa27PShNlnx2xlv0wdsUpasZYgcYQF+Xkdycx6u1UQ3maVNVzDl92sURVXLF
O4uJ+DQtpBflF+aZfTCIITfNMBc9uPK8qHWgQ9w+iUuQrm0D4ByjoJYJu32jtyoQ
REtGBzRj7TG5BO6jm5qu5jF49OokYTurWGT/u4cnYiWB39yhL/btp/96j1EuMPik
AdKFOV8BmZZvWltwGUb+hmA+rYAQCd05JS9Yf7vSdPD3Rh9GOUrYU9DzLjtxpdRv
/PNn5AeP3SYZ4Y1b+qOTEZvpyDrDVWiakuFSdjjo4bq9+0/V77PnSIMx8IIh47a+
p6tv75/fTM8BuGJqIz3nCU2AG3swpMPdB380vqQmsvZB6Akd4yCYqjdP//fx4ilw
MUc/dNAUFvohigLVigmUdy7yWSiLfFCSCmZ4OIN1xLVaqBHG5cGdZlXPU8Sv13WF
qUITVuwhd4GTWgzqltlJyqEI8pc7bZsEGCREjnwB8twl2F6GmrE52/WRMmrRpnCK
ovfepEWFJqgejF0pW8hL2JpqA15w8oVPbEtoL8pU9ozaMv7Da4M/OMZ+
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFkDCCA3igAwIBAgIQBZsbV56OITLiOQe9p3d1XDANBgkqhkiG9w0BAQwFADBi
MQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3
d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2VydCBUcnVzdGVkIFJvb3Qg
RzQwHhcNMTMwODAxMTIwMDAwWhcNMzgwMTE1MTIwMDAwWjBiMQswCQYDVQQGEwJV
UzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQu
Y29tMSEwHwYDVQQDExhEaWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwggIiMA0GCSqG
SIb3DQEBAQUAA4ICDwAwggIKAoICAQC/5pBzaN675F1KPDAiMGkz7MKnJS7JIT3y
ithZwuEppz1Yq3aaza57G4QNxDAf8xukOBbrVsaXbR2rsnnyyhHS5F/WBTxSD1If
xp4VpX6+n6lXFllVcq9ok3DCsrp1mWpzMpTREEQQLt+C8weE5nQ7bXHiLQwb7iDV
ySAdYyktzuxeTsiT+CFhmzTrBcZe7FsavOvJz82sNEBfsXpm7nfISKhmV1efVFiO
DCu3T6cw2Vbuyntd463JT17lNecxy9qTXtyOj4DatpGYQJB5w3jHtrHEtWoYOAMQ
jdjUN6QuBX2I9YI+EJFwq1WCQTLX2wRzKm6RAXwhTNS8rhsDdV14Ztk6MUSaM0C/
CNdaSaTC5qmgZ92kJ7yhTzm1EVgX9yRcRo9k98FpiHaYdj1ZXUJ2h4mXaXpI8OCi
EhtmmnTK3kse5w5jrubU75KSOp493ADkRSWJtppEGSt+wJS00mFt6zPZxd9LBADM
fRyVw4/3IbKyEbe7f/LVjHAsQWCqsWMYRJUadmJ+9oCw++hkpjPRiQfhvbfmQ6QY
uKZ3AeEPlAwhHbJUKSWJbOUOUlFHdL4mrLZBdd56rF+NP8m800ERElvlEFDrMcXK
chYiCd98THU/Y+whX8QgUWtvsauGi0/C1kVfnSD8oR7FwI+isX4KJpn15GkvmB0t
9dmpsh3lGwIDAQABo0IwQDAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIB
hjAdBgNVHQ4EFgQU7NfjgtJxXWRM3y5nP+e6mK4cD08wDQYJKoZIhvcNAQEMBQAD
ggIBALth2X2pbL4XxJEbw6GiAI3jZGgPVs93rnD5/ZpKmbnJeFwMDF/k5hQpVgs2
SV1EY+CtnJYYZhsjDT156W1r1lT40jzBQ0CuHVD1UvyQO7uYmWlrx8GnqGikJ9yd
+SeuMIW59mdNOj6PWTkiU0TryF0Dyu1Qen1iIQqAyHNm0aAFYF/opbSnr6j3bTWc
fFqK1qI4mfN4i/RN0iAL3gTujJtHgXINwBQy7zBZLq7gcfJW5GqXb5JQbZaNaHqa
sjYUegbyJLkJEVDXCLG4iXqEI2FCKeWjzaIgQdfRnGTZ6iahixTXTBmyUEFxPT9N
cCOGDErcgdLMMpSEDQgJlxxPwO5rIHQw0uA5NBCFIRUBCOhVMt5xSdkoF1BN5r5N
0XWs0Mr7QbhDparTwwVETyw2m+L64kW4I1NsBm9nVX9GtUw/bihaeSbSpKhil9Ie
4u1Ki7wb/UdKDd9nZn6yW0HQO+T0O/QEY+nvwlQAUaCKKsnOeMzV6ocEGLPOr0mI
r/OSmbaz5mEP0oUA51Aa5BuVnRmhuZyxm7EAHu/QD09CbMkKvO5D+jpxpchNJqU1
/YldvIViHTLSoCtU7ZpXwdv6EM8Zt4tKG48BtieVU+i2iW1bvGjUI+iLUaJW+fCm
gKDWHrO8Dw9TdSmq6hN35N6MgSGtBxBHEa2HPQfRdbzP82Z+
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFiDCCA3CgAwIBAgIIfQmX/vBH6nowDQYJKoZIhvcNAQELBQAwYjELMAkGA1UE
BhMCQ04xMjAwBgNVBAoMKUdVQU5HIERPTkcgQ0VSVElGSUNBVEUgQVVUSE9SSVRZ
IENPLixMVEQuMR8wHQYDVQQDDBZHRENBIFRydXN0QVVUSCBSNSBST09UMB4XDTE0
MTEyNjA1MTMxNVoXDTQwMTIzMTE1NTk1OVowYjELMAkGA1UEBhMCQ04xMjAwBgNV
BAoMKUdVQU5HIERPTkcgQ0VSVElGSUNBVEUgQVVUSE9SSVRZIENPLixMVEQuMR8w
HQYDVQQDDBZHRENBIFRydXN0QVVUSCBSNSBST09UMIICIjANBgkqhkiG9w0BAQEF
AAOCAg8AMIICCgKCAgEA2aMW8Mh0dHeb7zMNOwZ+Vfy1YI92hhJCfVZmPoiC7XJj
Dp6L3TQsAlFRwxn9WVSEyfFrs0yw6ehGXTjGoqcuEVe6ghWinI9tsJlKCvLriXBj
TnnEt1u9ol2x8kECK62pOqPseQrsXzrj/e+APK00mxqriCZ7VqKChh/rNYmDf1+u
KU49tm7srsHwJ5uu4/Ts765/94Y9cnrrpftZTqfrlYwiOXnhLQiPzLyRuEH3FMEj
qcOtmkVEs7LXLM3GKeJQEK5cy4KOFxg2fZfmiJqwTTQJ9Cy5WmYqsBebnh52nUpm
MUHfP/vFBu8btn4aRjb3ZGM74zkYI+dndRTVdVeSN72+ahsmUPI2JgaQxXABZG12
ZuGR224HwGGALrIuL4xwp9E7PLOR5G62xDtw8mySlwnNR30YwPO7ng/Wi64HtloP
zgsMR6flPri9fcebNaBhlzpBdRfMK5Z3KpIhHtmVdiBnaM8Nvd/WHwlqmuLMc3Gk
L30SgLdTMEZeS1SZD2fJpcjyIMGC7J0R38IC+xo70e0gmu9lZJIQDSri3nDxGGeC
jGHeuLzRL5z7D9Ar7Rt2ueQ5Vfj4oR24qoAATILnsn8JuLwwoC8N9VKejveSswoA
HQBUlwbgsQfZxw9cZX08bVlX5O2ljelAU58VS6Bx9hoh49pwBiFYFIeFd3mqgnkC
AwEAAaNCMEAwHQYDVR0OBBYEFOLJQJ9NzuiaoXzPDj9lxSmIahlRMA8GA1UdEwEB
/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgGGMA0GCSqGSIb3DQEBCwUAA4ICAQDRSVfg
p8xoWLoBDysZzY2wYUWsEe1jUGn4H3++Fo/9nesLqjJHdtJnJO29fDMylyrHBYZm
DRd9FBUb1Ov9H5r2XpdptxolpAqzkT9fNqyL7FeoPueBihhXOYV0GkLH6VsTX4/5
COmSdI31R9KrO9b7eGZONn356ZLpBN79SWP8bfsUcZNnL0dKt7n/HipzcEYwv1ry
L3ml4Y0M2fmyYzeMN2WFcGpcWwlyua1jPLHd+PwyvzeG5LuOmCd+uh8W4XAR8gPf
JWIyJyYYMoSf/wA6E7qaTfRPuBRwIrHKK5DOKcFw9C+df/KQHtZa37dG/OaG+svg
IHZ6uqbL9XzeYqWxi+7egmaKTjowHz+Ay60nugxe19CxVsp3cbK1daFQqUBDF8Io
2c9Si1vIY9RCPqAzekYu9wogRlR+ak8x8YF+QnQ4ZXMn7sZ8uI7XpTrXmKGcjBBV
09tL7ECQ8s1uV9JiDnxXk7Gnbc2dg7sq5+W2O3FYrf3RRbxake5TFW/TRQl1brqQ
XR4EzzffHqhmsYzmIGrv/EhOdJhCrylvLmrH+33RZjEizIYAfmaDDEL0vTSSwxrq
T8p+ck0LcIymSLumoRT2+1hEmRSuqguTaaApJUqlyyvdimYHFngVV3Eb7PVHhPOe
MTd61X8kreS8/f3MboPoDKi3QWwH3b08hpcv0g==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFVzCCAz+gAwIBAgINAgPlk28xsBNJiGuiFzANBgkqhkiG9w0BAQwFADBHMQsw
CQYDVQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2VzIExMQzEU
MBIGA1UEAxMLR1RTIFJvb3QgUjEwHhcNMTYwNjIyMDAwMDAwWhcNMzYwNjIyMDAw
MDAwWjBHMQswCQYDVQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZp
Y2VzIExMQzEUMBIGA1UEAxMLR1RTIFJvb3QgUjEwggIiMA0GCSqGSIb3DQEBAQUA
A4ICDwAwggIKAoICAQC2EQKLHuOhd5s73L+UPreVp0A8of2C+X0yBoJx9vaMf/vo
27xqLpeXo4xL+Sv2sfnOhB2x+cWX3u+58qPpvBKJXqeqUqv4IyfLpLGcY9vXmX7w
Cl7raKb0xlpHDU0QM+NOsROjyBhsS+z8CZDfnWQpJSMHobTSPS5g4M/SCYe7zUjw
TcLCeoiKu7rPWRnWr4+wB7CeMfGCwcDfLqZtbBkOtdh+JhpFAz2weaSUKK0Pfybl
qAj+lug8aJRT7oM6iCsVlgmy4HqMLnXWnOunVmSPlk9orj2XwoSPwLxAwAtcvfaH
szVsrBhQf4TgTM2S0yDpM7xSma8ytSmzJSq0SPly4cpk9+aCEI3oncKKiPo4Zor8
Y/kB+Xj9e1x3+naH+uzfsQ55lVe0vSbv1gHR6xYKu44LtcXFilWr06zqkUspzBmk
MiVOKvFlRNACzqrOSbTqn3yDsEB750Orp2yjj32JgfpMpf/VjsPOS+C12LOORc92
wO1AK/1TD7Cn1TsNsYqiA94xrcx36m97PtbfkSIS5r762DL8EGMUUXLeXdYWk70p
aDPvOmbsB4om3xPXV2V4J95eSRQAogB/mqghtqmxlbCluQ0WEdrHbEg8QOB+DVrN
VjzRlwW5y0vtOUucxD/SVRNuJLDWcfr0wbrM7Rv1/oFB2ACYPTrIrnqYNxgFlQID
AQABo0IwQDAOBgNVHQ8BAf8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4E
FgQU5K8rJnEaK0gnhS9SZizv8IkTcT4wDQYJKoZIhvcNAQEMBQADggIBAJ+qQibb
C5u+/x6Wki4+omVKapi6Ist9wTrYggoGxval3sBOh2Z5ofmmWJyq+bXmYOfg6LEe
QkEzCzc9zolwFcq1JKjPa7XSQCGYzyI0zzvFIoTgxQ6KfF2I5DUkzps+GlQebtuy
h6f88/qBVRRiClmpIgUxPoLW7ttXNLwzldMXG+gnoot7TiYaelpkttGsN/H9oPM4
7HLwEXWdyzRSjeZ2axfG34arJ45JK3VmgRAhpuo+9K4l/3wV3s6MJT/KYnAK9y8J
ZgfIPxz88NtFMN9iiMG1D53Dn0reWVlHxYciNuaCp+0KueIHoI17eko8cdLiA6Ef
MgfdG+RCzgwARWGAtQsgWSl4vflVy2PFPEz0tv/bal8xa5meLMFrUKTX5hgUvYU/
Z6tGn6D/Qqc6f1zLXbBwHSs09dR2CQzreExZBfMzQsNhFRAbd03OIozUhfJFfbdT
6u9AWpQKXCBfTkBdYiJ23//OYb2MI3jSNwLgjt7RETeJ9r/tSQdirpLsQBqvFAnZ
0E6yove+7u7Y/9waLd64NnHi/Hm3lCXRSHNboTXns5lndcEZOitHTtNCjv0xyBZm
2tIMPNuzjsmhDYAPexZ3FL//2wmUspO8IFgV6dtxQ/PeEMMA3KgqlbbC1j+Qa3bb
bP6MvPJwNQzcmRk13NfIRmPVNnGuV/u3gm3c
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICCTCCAY6gAwIBAgINAgPluILrIPglJ209ZjAKBggqhkjOPQQDAzBHMQswCQYD
VQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2VzIExMQzEUMBIG
A1UEAxMLR1RTIFJvb3QgUjMwHhcNMTYwNjIyMDAwMDAwWhcNMzYwNjIyMDAwMDAw
WjBHMQswCQYDVQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2Vz
IExMQzEUMBIGA1UEAxMLR1RTIFJvb3QgUjMwdjAQBgcqhkjOPQIBBgUrgQQAIgNi
AAQfTzOHMymKoYTey8chWEGJ6ladK0uFxh1MJ7x/JlFyb+Kf1qPKzEUURout736G
jOyxfi//qXGdGIRFBEFVbivqJn+7kAHjSxm65FSWRQmx1WyRRK2EE46ajA2ADDL2
4CejQjBAMA4GA1UdDwEB/wQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQW
BBTB8Sa6oC2uhYHP0/EqEr24Cmf9vDAKBggqhkjOPQQDAwNpADBmAjEA9uEglRR7
VKOQFhG/hMjqb2sXnh5GmCCbn9MN2azTL818+FsuVbu/3ZL3pAzcMeGiAjEA/Jdm
ZuVDFhOD3cffL74UOO0BzrEXGhF16b0DjyZ+hOXJYKaV11RZt+cRLInUue4X
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICCTCCAY6gAwIBAgINAgPlwGjvYxqccpBQUjAKBggqhkjOPQQDAzBHMQswCQYD
VQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2VzIExMQzEUMBIG
A1UEAxMLR1RTIFJvb3QgUjQwHhcNMTYwNjIyMDAwMDAwWhcNMzYwNjIyMDAwMDAw
WjBHMQswCQYDVQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2Vz
IExMQzEUMBIGA1UEAxMLR1RTIFJvb3QgUjQwdjAQBgcqhkjOPQIBBgUrgQQAIgNi
AATzdHOnaItgrkO4NcWBMHtLSZ37wWHO5t5GvWvVYRg1rkDdc/eJkTBa6zzuhXyi
QHY7qca4R9gq55KRanPpsXI5nymfopjTX15YhmUPoYRlBtHci8nHc8iMai/lxKvR
HYqjQjBAMA4GA1UdDwEB/wQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQW
BBSATNbrdP9JNqPV2Py1PsVq8JQdjDAKBggqhkjOPQQDAwNpADBmAjEA6ED/g94D
9J+uHXqnLrmvT/aDHQ4thQEd0dlq7A/Cr8deVl5c1RxYIigL9zC2L7F8AjEA8GE8
p/SgguMh1YQdc4acLa/KNJvxn7kjNuK8YAOdgLOaVsjh4rsUecrNIdSUtUlD
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIB3DCCAYOgAwIBAgINAgPlfvU/k/2lCSGypjAKBggqhkjOPQQDAjBQMSQwIgYD
VQQLExtHbG9iYWxTaWduIEVDQyBSb290IENBIC0gUjQxEzARBgNVBAoTCkdsb2Jh
bFNpZ24xEzARBgNVBAMTCkdsb2JhbFNpZ24wHhcNMTIxMTEzMDAwMDAwWhcNMzgw
MTE5MDMxNDA3WjBQMSQwIgYDVQQLExtHbG9iYWxTaWduIEVDQyBSb290IENBIC0g
UjQxEzARBgNVBAoTCkdsb2JhbFNpZ24xEzARBgNVBAMTCkdsb2JhbFNpZ24wWTAT
BgcqhkjOPQIBBggqhkjOPQMBBwNCAAS4xnnTj2wlDp8uORkcA6SumuU5BwkWymOx
uYb4ilfBV85C+nOh92VC/x7BALJucw7/xyHlGKSq2XE/qNS5zowdo0IwQDAOBgNV
HQ8BAf8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUVLB7rUW44kB/
+wpu+74zyTyjhNUwCgYIKoZIzj0EAwIDRwAwRAIgIk90crlgr/HmnKAWBVBfw147
bmF0774BxL4YSFlhgjICICadVGNA3jdgUM/I2O2dgq43mLyjj0xMqTQrbO/7lZsm
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICHjCCAaSgAwIBAgIRYFlJ4CYuu1X5CneKcflK2GwwCgYIKoZIzj0EAwMwUDEk
MCIGA1UECxMbR2xvYmFsU2lnbiBFQ0MgUm9vdCBDQSAtIFI1MRMwEQYDVQQKEwpH
bG9iYWxTaWduMRMwEQYDVQQDEwpHbG9iYWxTaWduMB4XDTEyMTExMzAwMDAwMFoX
DTM4MDExOTAzMTQwN1owUDEkMCIGA1UECxMbR2xvYmFsU2lnbiBFQ0MgUm9vdCBD
QSAtIFI1MRMwEQYDVQQKEwpHbG9iYWxTaWduMRMwEQYDVQQDEwpHbG9iYWxTaWdu
MHYwEAYHKoZIzj0CAQYFK4EEACIDYgAER0UOlvt9Xb/pOdEh+J8LttV7HpI6SFkc
8GIxLcB6KP4ap1yztsyX50XUWPrRd21DosCHZTQKH3rd6zwzocWdTaRvQZU4f8ke
hOvRnkmSh5SHDDqFSmafnVmTTZdhBoZKo0IwQDAOBgNVHQ8BAf8EBAMCAQYwDwYD
VR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUPeYpSJvqB8ohREom3m7e0oPQn1kwCgYI
KoZIzj0EAwMDaAAwZQIxAOVpEslu28YxuglB4Zf4+/2a4n0Sye18ZNPLBSWLVtmg
515dTguDnFt2KaAJJiFqYgIwcdK1j1zqO+F4CYWodZI7yFz9SO8NdCKoCOJuxUnO
xwy8p2Fp8fc74SrL+SvzZpA3
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIDXzCCAkegAwIBAgILBAAAAAABIVhTCKIwDQYJKoZIhvcNAQELBQAwTDEgMB4G
A1UECxMXR2xvYmFsU2lnbiBSb290IENBIC0gUjMxEzARBgNVBAoTCkdsb2JhbFNp
Z24xEzARBgNVBAMTCkdsb2JhbFNpZ24wHhcNMDkwMzE4MTAwMDAwWhcNMjkwMzE4
MTAwMDAwWjBMMSAwHgYDVQQLExdHbG9iYWxTaWduIFJvb3QgQ0EgLSBSMzETMBEG
A1UEChMKR2xvYmFsU2lnbjETMBEGA1UEAxMKR2xvYmFsU2lnbjCCASIwDQYJKoZI
hvcNAQEBBQADggEPADCCAQoCggEBAMwldpB5BngiFvXAg7aEyiie/QV2EcWtiHL8
RgJDx7KKnQRfJMsuS+FggkbhUqsMgUdwbN1k0ev1LKMPgj0MK66X17YUhhB5uzsT
gHeMCOFJ0mpiLx9e+pZo34knlTifBtc+ycsmWQ1z3rDI6SYOgxXG71uL0gRgykmm
KPZpO/bLyCiR5Z2KYVc3rHQU3HTgOu5yLy6c+9C7v/U9AOEGM+iCK65TpjoWc4zd
QQ4gOsC0p6Hpsk+QLjJg6VfLuQSSaGjlOCZgdbKfd/+RFO+uIEn8rUAVSNECMWEZ
XriX7613t2Saer9fwRPvm2L7DWzgVGkWqQPabumDk3F2xmmFghcCAwEAAaNCMEAw
DgYDVR0PAQH/BAQDAgEGMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFI/wS3+o
LkUkrk1Q+mOai97i3Ru8MA0GCSqGSIb3DQEBCwUAA4IBAQBLQNvAUKr+yAzv95ZU
RUm7lgAJQayzE4aGKAczymvmdLm6AC2upArT9fHxD4q/c2dKg8dEe3jgr25sbwMp
jjM5RcOO5LlXbKr8EpbsU8Yt5CRsuZRj+9xTaGdWPoO4zzUhw8lo/s7awlOqzJCK
6fBdRoyV3XpYKBovHd7NADdBj+1EbddTKJd+82cEHhXXipa0095MJ6RMG3NzdvQX
mcIfeg7jLQitChws/zyrVQ4PkX4268NXSb7hLi18YIvDQVETI53O9zJrlAGomecs
Mx86OyXShkDOOyyGeMlhLxS67ttVb9+E7gUJTb0o2HLO02JQZR7rkpeDMdmztcpH
WD9f
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFgzCCA2ugAwIBAgIORea7A4Mzw4VlSOb/RVEwDQYJKoZIhvcNAQEMBQAwTDEg
MB4GA1UECxMXR2xvYmFsU2lnbiBSb290IENBIC0gUjYxEzARBgNVBAoTCkdsb2Jh
bFNpZ24xEzARBgNVBAMTCkdsb2JhbFNpZ24wHhcNMTQxMjEwMDAwMDAwWhcNMzQx
MjEwMDAwMDAwWjBMMSAwHgYDVQQLExdHbG9iYWxTaWduIFJvb3QgQ0EgLSBSNjET
MBEGA1UEChMKR2xvYmFsU2lnbjETMBEGA1UEAxMKR2xvYmFsU2lnbjCCAiIwDQYJ
KoZIhvcNAQEBBQADggIPADCCAgoCggIBAJUH6HPKZvnsFMp7PPcNCPG0RQssgrRI
xutbPK6DuEGSMxSkb3/pKszGsIhrxbaJ0cay/xTOURQh7ErdG1rG1ofuTToVBu1k
ZguSgMpE3nOUTvOniX9PeGMIyBJQbUJmL025eShNUhqKGoC3GYEOfsSKvGRMIRxD
aNc9PIrFsmbVkJq3MQbFvuJtMgamHvm566qjuL++gmNQ0PAYid/kD3n16qIfKtJw
LnvnvJO7bVPiSHyMEAc4/2ayd2F+4OqMPKq0pPbzlUoSB239jLKJz9CgYXfIWHSw
1CM69106yqLbnQneXUQtkPGBzVeS+n68UARjNN9rkxi+azayOeSsJDa38O+2HBNX
k7besvjihbdzorg1qkXy4J02oW9UivFyVm4uiMVRQkQVlO6jxTiWm05OWgtH8wY2
SXcwvHE35absIQh1/OZhFj931dmRl4QKbNQCTXTAFO39OfuD8l4UoQSwC+n+7o/h
bguyCLNhZglqsQY6ZZZZwPA1/cnaKI0aEYdwgQqomnUdnjqGBQCe24DWJfncBZ4n
WUx2OVvq+aWh2IMP0f/fMBH5hc8zSPXKbWQULHpYT9NLCEnFlWQaYw55PfWzjMpY
rZxCRXluDocZXFSxZba/jJvcE+kNb7gu3GduyYsRtYQUigAZcIN5kZeR1Bonvzce
MgfYFGM8KEyvAgMBAAGjYzBhMA4GA1UdDwEB/wQEAwIBBjAPBgNVHRMBAf8EBTAD
AQH/MB0GA1UdDgQWBBSubAWjkxPioufi1xzWx/B/yGdToDAfBgNVHSMEGDAWgBSu
bAWjkxPioufi1xzWx/B/yGdToDANBgkqhkiG9w0BAQwFAAOCAgEAgyXt6NH9lVLN
nsAEoJFp5lzQhN7craJP6Ed41mWYqVuoPId8AorRbrcWc+ZfwFSY1XS+wc3iEZGt
Ixg93eFyRJa0lV7Ae46ZeBZDE1ZXs6KzO7V33EByrKPrmzU+sQghoefEQzd5Mr61
55wsTLxDKZmOMNOsIeDjHfrYBzN2VAAiKrlNIC5waNrlU/yDXNOd8v9EDERm8tLj
vUYAGm0CuiVdjaExUd1URhxN25mW7xocBFymFe944Hn+Xds+qkxV/ZoVqW/hpvvf
cDDpw+5CRu3CkwWJ+n1jez/QcYF8AOiYrg54NMMl+68KnyBr3TsTjxKM4kEaSHpz
oHdpx7Zcf4LIHv5YGygrqGytXm3ABdJ7t+uA/iU3/gKbaKxCXcPu9czc8FB10jZp
nOZ7BN9uBmm23goJSFmH63sUYHpkqmlD75HHTOwY3WzvUy2MmeFe8nI+z1TIvWfs
pA9MRf/TuTAjB0yPEL+GltmZWrSZVxykzLsViVO6LAUP5MSeGbEYNNVMnbrt9x+v
JJUEeKgDu+6B5dpffItKoZB0JaezPkvILFa9x8jvOOJckvB595yEunQtYQEgfn7R
8k8HWV+LLUNS60YMlOH1Zkd5d9VUWx+tJDfLRVpOoERIyNiwmcUVhAn21klJwGW4
5hpxbqCo8YLoRT5s1gLXCmeDBVrJpBA=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICCzCCAZGgAwIBAgISEdK7ujNu1LzmJGjFDYQdmOhDMAoGCCqGSM49BAMDMEYx
CzAJBgNVBAYTAkJFMRkwFwYDVQQKExBHbG9iYWxTaWduIG52LXNhMRwwGgYDVQQD
ExNHbG9iYWxTaWduIFJvb3QgRTQ2MB4XDTE5MDMyMDAwMDAwMFoXDTQ2MDMyMDAw
MDAwMFowRjELMAkGA1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24gbnYtc2Ex
HDAaBgNVBAMTE0dsb2JhbFNpZ24gUm9vdCBFNDYwdjAQBgcqhkjOPQIBBgUrgQQA
IgNiAAScDrHPt+ieUnd1NPqlRqetMhkytAepJ8qUuwzSChDH2omwlwxwEwkBjtjq
R+q+soArzfwoDdusvKSGN+1wCAB16pMLey5SnCNoIwZD7JIvU4Tb+0cUB+hflGdd
yXqBPCCjQjBAMA4GA1UdDwEB/wQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB0GA1Ud
DgQWBBQxCpCPtsad0kRLgLWi5h+xEk8blTAKBggqhkjOPQQDAwNoADBlAjEA31SQ
7Zvvi5QCkxeCmb6zniz2C5GMn0oUsfZkvLtoURMMA/cVi4RguYv/Uo7njLwcAjA8
+RHUjE7AwWHCFUyqqx0LMV87HOIAl0Qx5v5zli/altP+CAezNIm8BZ/3Hobui3A=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFWjCCA0KgAwIBAgISEdK7udcjGJ5AXwqdLdDfJWfRMA0GCSqGSIb3DQEBDAUA
MEYxCzAJBgNVBAYTAkJFMRkwFwYDVQQKExBHbG9iYWxTaWduIG52LXNhMRwwGgYD
VQQDExNHbG9iYWxTaWduIFJvb3QgUjQ2MB4XDTE5MDMyMDAwMDAwMFoXDTQ2MDMy
MDAwMDAwMFowRjELMAkGA1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24gbnYt
c2ExHDAaBgNVBAMTE0dsb2JhbFNpZ24gUm9vdCBSNDYwggIiMA0GCSqGSIb3DQEB
AQUAA4ICDwAwggIKAoICAQCsrHQy6LNl5brtQyYdpokNRbopiLKkHWPd08EsCVeJ
OaFV6Wc0dwxu5FUdUiXSE2te4R2pt32JMl8Nnp8semNgQB+msLZ4j5lUlghYruQG
vGIFAha/r6gjA7aUD7xubMLL1aa7DOn2wQL7Id5m3RerdELv8HQvJfTqa1VbkNud
316HCkD7rRlr+/fKYIje2sGP1q7Vf9Q8g+7XFkyDRTNrJ9CG0Bwta/OrffGFqfUo
0q3v84RLHIf8E6M6cqJaESvWJ3En7YEtbWaBkoe0G1h6zD8K+kZPTXhc+CtI4wSE
y132tGqzZfxCnlEmIyDLPRT5ge1lFgBPGmSXZgjPjHvjK8Cd+RTyG/FWaha/LIWF
zXg4mutCagI0GIMXTpRW+LaCtfOW3T3zvn8gdz57GSNrLNRyc0NXfeD412lPFzYE
+cCQYDdF3uYM2HSNrpyibXRdQr4G9dlkbgIQrImwTDsHTUB+JMWKmIJ5jqSngiCN
I/onccnfxkF0oE32kRbcRoxfKWMxWXEM2G/CtjJ9++ZdU6Z+Ffy7dXxd7Pj2Fxzs
x2sZy/N78CsHpdlseVR2bJ0cpm4O6XkMqCNqo98bMDGfsVR7/mrLZqrcZdCinkqa
ByFrgY/bxFn63iLABJzjqls2k+g9vXqhnQt2sQvHnf3PmKgGwvgqo6GDoLclcqUC
4wIDAQABo0IwQDAOBgNVHQ8BAf8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAdBgNV
HQ4EFgQUA1yrc4GHqMywptWU4jaWSf8FmSwwDQYJKoZIhvcNAQEMBQADggIBAHx4
7PYCLLtbfpIrXTncvtgdokIzTfnvpCo7RGkerNlFo048p9gkUbJUHJNOxO97k4Vg
JuoJSOD1u8fpaNK7ajFxzHmuEajwmf3lH7wvqMxX63bEIaZHU1VNaL8FpO7XJqti
2kM3S+LGteWygxk6x9PbTZ4IevPuzz5i+6zoYMzRx6Fcg0XERczzF2sUyQQCPtIk
pnnpHs6i58FZFZ8d4kuaPp92CC1r2LpXFNqD6v6MVenQTqnMdzGxRBF6XLE+0xRF
FRhiJBPSy03OXIPBNvIQtQ6IbbjhVp+J3pZmOUdkLG5NrmJ7v2B0GbhWrJKsFjLt
rWhV/pi60zTe9Mlhww6G9kuEYO4Ne7UyWHmRVSyBQ7N0H3qqJZ4d16GLuc1CLgSk
ZoNNiTW2bKg2SnkheCLQQrzRQDGQob4Ez8pn7fXwgNNgyYMqIgXQBztSvwyeqiv5
u+YfjyW6hY0XHgL+XVAEV8/+LbzvXMAaq7afJMbfc2hIkCwU9D9SGuTSyxTDYWnP
4vkYxboznxSjBF25cfe1lNj2M8FawTSLfJvdkzrnE6JwYZ+vj+vYxXX4M2bUdGc6
N3ec592kD3ZDZopD8p/7DEJ4Y9HiD2971KE9dJeFt0g5QdYg/NA6s/rob8SKunE3
vouXsXgxT7PntgMTzlSdriVZzH81Xwj3QEUxeCp6
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIDxTCCAq2gAwIBAgIBADANBgkqhkiG9w0BAQsFADCBgzELMAkGA1UEBhMCVVMx
EDAOBgNVBAgTB0FyaXpvbmExEzARBgNVBAcTClNjb3R0c2RhbGUxGjAYBgNVBAoT
EUdvRGFkZHkuY29tLCBJbmMuMTEwLwYDVQQDEyhHbyBEYWRkeSBSb290IENlcnRp
ZmljYXRlIEF1dGhvcml0eSAtIEcyMB4XDTA5MDkwMTAwMDAwMFoXDTM3MTIzMTIz
NTk1OVowgYMxCzAJBgNVBAYTAlVTMRAwDgYDVQQIEwdBcml6b25hMRMwEQYDVQQH
EwpTY290dHNkYWxlMRowGAYDVQQKExFHb0RhZGR5LmNvbSwgSW5jLjExMC8GA1UE
AxMoR28gRGFkZHkgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgLSBHMjCCASIw
DQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAL9xYgjx+lk09xvJGKP3gElY6SKD
E6bFIEMBO4Tx5oVJnyfq9oQbTqC023CYxzIBsQU+B07u9PpPL1kwIuerGVZr4oAH
/PMWdYA5UXvl+TW2dE6pjYIT5LY/qQOD+qK+ihVqf94Lw7YZFAXK6sOoBJQ7Rnwy
DfMAZiLIjWltNowRGLfTshxgtDj6AozO091GB94KPutdfMh8+7ArU6SSYmlRJQVh
GkSBjCypQ5Yj36w6gZoOKcUcqeldHraenjAKOc7xiID7S13MMuyFYkMlNAJWJwGR
tDtwKj9useiciAF9n9T521NtYJ2/LOdYq7hfRvzOxBsDPAnrSTFcaUaz4EcCAwEA
AaNCMEAwDwYDVR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYE
FDqahQcQZyi27/a9BUFuIMGU2g/eMA0GCSqGSIb3DQEBCwUAA4IBAQCZ21151fmX
WWcDYfF+OwYxdS2hII5PZYe096acvNjpL9DbWu7PdIxztDhC2gV7+AJ1uP2lsdeu
9tfeE8tTEH6KRtGX+rcuKxGrkLAngPnon1rpN5+r5N9ss4UXnT3ZJE95kTXWXwTr
gIOrmgIttRD02JDHBHNA7XIloKmf7J6raBKZV8aPEjoJpL1E/QYVN8Gb5DKj7Tjo
2GTzLH4U/ALqn83/B2gX2yKQOC16jdFU8WnjXzPKej17CuPKf1855eJ1usV2GDPO
LPAvTK33sefOT6jEm0pUBsV/fdUID+Ic/n4XuKxe9tQWskMJDE32p2u0mYRlynqI
4uJEvlz36hz1
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICVDCCAdugAwIBAgIQZ3SdjXfYO2rbIvT/WeK/zjAKBggqhkjOPQQDAzBsMQsw
CQYDVQQGEwJHUjE3MDUGA1UECgwuSGVsbGVuaWMgQWNhZGVtaWMgYW5kIFJlc2Vh
cmNoIEluc3RpdHV0aW9ucyBDQTEkMCIGA1UEAwwbSEFSSUNBIFRMUyBFQ0MgUm9v
dCBDQSAyMDIxMB4XDTIxMDIxOTExMDExMFoXDTQ1MDIxMzExMDEwOVowbDELMAkG
A1UEBhMCR1IxNzA1BgNVBAoMLkhlbGxlbmljIEFjYWRlbWljIGFuZCBSZXNlYXJj
aCBJbnN0aXR1dGlvbnMgQ0ExJDAiBgNVBAMMG0hBUklDQSBUTFMgRUNDIFJvb3Qg
Q0EgMjAyMTB2MBAGByqGSM49AgEGBSuBBAAiA2IABDgI/rGgltJ6rK9JOtDA4MM7
KKrxcm1lAEeIhPyaJmuqS7psBAqIXhfyVYf8MLA04jRYVxqEU+kw2anylnTDUR9Y
STHMmE5gEYd103KUkE+bECUqqHgtvpBBWJAVcqeht6NCMEAwDwYDVR0TAQH/BAUw
AwEB/zAdBgNVHQ4EFgQUyRtTgRL+BNUW0aq8mm+3oJUZbsowDgYDVR0PAQH/BAQD
AgGGMAoGCCqGSM49BAMDA2cAMGQCMBHervjcToiwqfAircJRQO9gcS3ujwLEXQNw
SaSS6sUUiHCm0w2wqsosQJz76YJumgIwK0eaB8bRwoF8yguWGEEbo/QwCZ61IygN
nxS2PFOiTAZpffpskcYqSUXm7LcT4Tps
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFpDCCA4ygAwIBAgIQOcqTHO9D88aOk8f0ZIk4fjANBgkqhkiG9w0BAQsFADBs
MQswCQYDVQQGEwJHUjE3MDUGA1UECgwuSGVsbGVuaWMgQWNhZGVtaWMgYW5kIFJl
c2VhcmNoIEluc3RpdHV0aW9ucyBDQTEkMCIGA1UEAwwbSEFSSUNBIFRMUyBSU0Eg
Um9vdCBDQSAyMDIxMB4XDTIxMDIxOTEwNTUzOFoXDTQ1MDIxMzEwNTUzN1owbDEL
MAkGA1UEBhMCR1IxNzA1BgNVBAoMLkhlbGxlbmljIEFjYWRlbWljIGFuZCBSZXNl
YXJjaCBJbnN0aXR1dGlvbnMgQ0ExJDAiBgNVBAMMG0hBUklDQSBUTFMgUlNBIFJv
b3QgQ0EgMjAyMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAIvC569l
mwVnlskNJLnQDmT8zuIkGCyEf3dRywQRNrhe7Wlxp57kJQmXZ8FHws+RFjZiPTgE
4VGC/6zStGndLuwRo0Xua2s7TL+MjaQenRG56Tj5eg4MmOIjHdFOY9TnuEFE+2uv
a9of08WRiFukiZLRgeaMOVig1mlDqa2YUlhu2wr7a89o+uOkXjpFc5gH6l8Cct4M
pbOfrqkdtx2z/IpZ525yZa31MJQjB/OCFks1mJxTuy/K5FrZx40d/JiZ+yykgmvw
Kh+OC19xXFyuQnspiYHLA6OZyoieC0AJQTPb5lh6/a6ZcMBaD9YThnEvdmn8kN3b
LW7R8pv1GmuebxWMevBLKKAiOIAkbDakO/IwkfN4E8/BPzWr8R0RI7VDIp4BkrcY
AuUR0YLbFQDMYTfBKnya4dC6s1BG7oKsnTH4+yPiAwBIcKMJJnkVU2DzOFytOOqB
AGMUuTNe3QvboEUHGjMJ+E20pwKmafTCWQWIZYVWrkvL4N48fS0ayOn7H6NhStYq
E613TBoYm5EPWNgGVMWX+Ko/IIqmhaZ39qb8HOLubpQzKoNQhArlT4b4UEV4AIHr
W2jjJo3Me1xR9BQsQL4aYB16cmEdH2MtiKrOokWQCPxrvrNQKlr9qEgYRtaQQJKQ
CoReaDH46+0N0x3GfZkYVVYnZS6NRcUk7M7jAgMBAAGjQjBAMA8GA1UdEwEB/wQF
MAMBAf8wHQYDVR0OBBYEFApII6ZgpJIKM+qTW8VX6iVNvRLuMA4GA1UdDwEB/wQE
AwIBhjANBgkqhkiG9w0BAQsFAAOCAgEAPpBIqm5iFSVmewzVjIuJndftTgfvnNAU
X15QvWiWkKQUEapobQk1OUAJ2vQJLDSle1mESSmXdMgHHkdt8s4cUCbjnj1AUz/3
f5Z2EMVGpdAgS1D0NTsY9FVqQRtHBmg8uwkIYtlfVUKqrFOFrJVWNlar5AWMxaja
H6NpvVMPxP/cyuN+8kyIhkdGGvMA9YCRotxDQpSbIPDRzbLrLFPCU3hKTwSUQZqP
JzLB5UkZv/HywouoCjkxKLR9YjYsTewfM7Z+d21+UPCfDtcRj88YxeMn/ibvBZ3P
zzfF0HvaO7AWhAw6k9a+F9sPPg4ZeAnHqQJyIkv3N3a6dcSFA1pj1bF1BcK5vZSt
jBWZp5N99sXzqnTPBIWUmAD04vnKJGW/4GKvyMX6ssmeVkjaef2WdhW+o45WxLM0
/L5H9MG0qPzVMIho7suuyWPEdr6sOBjhXlzPrjoiUevRi7PzKzMHVIf6tLITe7pT
BGIBnfHAT+7hOtSLIBD6Alfm78ELt5BGnBkpjNxvoEppaZS3JGWg/6w/zgH7IS79
aPib8qXPMThcFarmlwDB31qlpzmq6YR/PFGoOtmUW4y/Twhx5duoXNTSpv4Ao8YW
xw/ogM4cKGR0GQjTQuPOAF1/sdwTsOEFy9EgqoZ0njnnkf3/W9b3raYvAwtt41dU
63ZTGI0RmLo=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICwzCCAkqgAwIBAgIBADAKBggqhkjOPQQDAjCBqjELMAkGA1UEBhMCR1IxDzAN
BgNVBAcTBkF0aGVuczFEMEIGA1UEChM7SGVsbGVuaWMgQWNhZGVtaWMgYW5kIFJl
c2VhcmNoIEluc3RpdHV0aW9ucyBDZXJ0LiBBdXRob3JpdHkxRDBCBgNVBAMTO0hl
bGxlbmljIEFjYWRlbWljIGFuZCBSZXNlYXJjaCBJbnN0aXR1dGlvbnMgRUNDIFJv
b3RDQSAyMDE1MB4XDTE1MDcwNzEwMzcxMloXDTQwMDYzMDEwMzcxMlowgaoxCzAJ
BgNVBAYTAkdSMQ8wDQYDVQQHEwZBdGhlbnMxRDBCBgNVBAoTO0hlbGxlbmljIEFj
YWRlbWljIGFuZCBSZXNlYXJjaCBJbnN0aXR1dGlvbnMgQ2VydC4gQXV0aG9yaXR5
MUQwQgYDVQQDEztIZWxsZW5pYyBBY2FkZW1pYyBhbmQgUmVzZWFyY2ggSW5zdGl0
dXRpb25zIEVDQyBSb290Q0EgMjAxNTB2MBAGByqGSM49AgEGBSuBBAAiA2IABJKg
QehLgoRc4vgxEZmGZE4JJS+dQS8KrjVPdJWyUWRrjWvmP3CV8AVER6ZyOFB2lQJa
jq4onvktTpnvLEhvTCUp6NFxW98dwXU3tNf6e3pCnGoKVlp8aQuqgAkkbH7BRqNC
MEAwDwYDVR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYEFLQi
C4KZJAEOnLvkDv2/+5cgk5kqMAoGCCqGSM49BAMCA2cAMGQCMGfOFmI4oqxiRaep
lSTAGiecMjvAwNW6qef4BENThe5SId6d9SWDPp5YSy/XZxMOIQIwBeF1Ad5o7Sof
TUwJCA3sS61kFyjndc5FZXIhF8siQQ6ME5g4mlRtm8rifOoCWCKR
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIGCzCCA/OgAwIBAgIBADANBgkqhkiG9w0BAQsFADCBpjELMAkGA1UEBhMCR1Ix
DzANBgNVBAcTBkF0aGVuczFEMEIGA1UEChM7SGVsbGVuaWMgQWNhZGVtaWMgYW5k
IFJlc2VhcmNoIEluc3RpdHV0aW9ucyBDZXJ0LiBBdXRob3JpdHkxQDA+BgNVBAMT
N0hlbGxlbmljIEFjYWRlbWljIGFuZCBSZXNlYXJjaCBJbnN0aXR1dGlvbnMgUm9v
dENBIDIwMTUwHhcNMTUwNzA3MTAxMTIxWhcNNDAwNjMwMTAxMTIxWjCBpjELMAkG
A1UEBhMCR1IxDzANBgNVBAcTBkF0aGVuczFEMEIGA1UEChM7SGVsbGVuaWMgQWNh
ZGVtaWMgYW5kIFJlc2VhcmNoIEluc3RpdHV0aW9ucyBDZXJ0LiBBdXRob3JpdHkx
QDA+BgNVBAMTN0hlbGxlbmljIEFjYWRlbWljIGFuZCBSZXNlYXJjaCBJbnN0aXR1
dGlvbnMgUm9vdENBIDIwMTUwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoIC
AQDC+Kk/G4n8PDwEXT2QNrCROnk8ZlrvbTkBSRq0t89/TSNTt5AA4xMqKKYx8ZEA
4yjsriFBzh/a/X0SWwGDD7mwX5nh8hKDgE0GPt+sr+ehiGsxr/CL0BgzuNtFajT0
AoAkKAoCFZVedioNmToUW/bLy1O8E00BiDeUJRtCvCLYjqOWXjrZMts+6PAQZe10
4S+nfK8nNLspfZu2zwnI5dMK/IhlZXQK3HMcXM1AsRzUtoSMTFDPaI6oWa7CJ06C
ojXdFPQf/7J31Ycvqm59JCfnxssm5uX+Zwdj2EUN3TpZZTlYepKZcj2chF6IIbjV
9Cz82XBST3i4vTwri5WY9bPRaM8gFH5MXF/ni+X1NYEZN9cRCLdmvtNKzoNXADrD
gfgXy5I2XdGj2HUb4Ysn6npIQf1FGQatJ5lOwXBH3bWfgVMS5bGMSF0xQxfjjMZ6
Y5ZLKTBOhE5iGV48zpeQpX8B653g+IuJ3SWYPZK2fu/Z8VFRfS0myGlZYeCsargq
NhEEelC9MoS+L9xy1dcdFkfkR2YgP/SWxa+OAXqlD3pk9Q0Yh9muiNX6hME6wGko
LfINaFGq46V3xqSQDqE3izEjR8EJCOtu93ib14L8hCCZSRm2Ekax+0VVFqmjZayc
Bw/qa9wfLgZy7IaIEuQt218FL+TwA9MmM+eAws1CoRc0CwIDAQABo0IwQDAPBgNV
HRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBBjAdBgNVHQ4EFgQUcRVnyMjJvXVd
ctA4GGqd83EkVAswDQYJKoZIhvcNAQELBQADggIBAHW7bVRLqhBYRjTyYtcWNl0I
XtVsyIe9tC5G8jH4fOpCtZMWVdyhDBKg2mF+D1hYc2Ryx+hFjtyp8iY/xnmMsVMI
M4GwVhO+5lFc2JsKT0ucVlMC6U/2DWDqTUJV6HwbISHTGzrMd/K4kPFox/la/vot
9L/J9UUbzjgQKjeKeaO04wlshYaT/4mWJ3iBj2fjRnRUjtkNaeJK9E10A/+yd+2V
Z5fkscWrv2oj6NSU4kQoYsRL4vDY4ilrGnB+JGGTe08DMiUNRSQrlrRGar9KC/ea
j8GsGsVn82800vpzY4zvFrCopEYq+OsS7HK07/grfoxSwIuEVPkvPuNVqNxmsdnh
X9izjFk0WaSrT2y7HxjbdavYy5LNlDhhDgcGH0tGEPEVvo2FXDtKK4F5D7Rpn0lQ
l033DlZdwJVqwjbDG2jJ9SrcR5q+ss7FJej6A7na+RZukYT1HCjI/CbM1xyQVqdf
bzoEvM14iQuODy+jqk+iGxI9FghAD/FGTNeqewjBCvVtJ94Cj8rDtSvK6evIIVM4
pcw72Hc3MKJP2W/R8kCtQXoXxdZKNYm3QdV8hn9VTYNKpXMgwDqvkPGaJI7ZjnHK
e7iG2rKPmT4dEw0SEe7Uq/DpFXYC5ODfqiAeW2GFZECpkJcNrVPSWh2HagCXZWK0
vm9qp/UsQu0yrbYhnr68
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFajCCA1KgAwIBAgIQLd2szmKXlKFD6LDNdmpeYDANBgkqhkiG9w0BAQsFADBP
MQswCQYDVQQGEwJUVzEjMCEGA1UECgwaQ2h1bmdod2EgVGVsZWNvbSBDby4sIEx0
ZC4xGzAZBgNVBAMMEkhpUEtJIFJvb3QgQ0EgLSBHMTAeFw0xOTAyMjIwOTQ2MDRa
Fw0zNzEyMzExNTU5NTlaME8xCzAJBgNVBAYTAlRXMSMwIQYDVQQKDBpDaHVuZ2h3
YSBUZWxlY29tIENvLiwgTHRkLjEbMBkGA1UEAwwSSGlQS0kgUm9vdCBDQSAtIEcx
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA9B5/UnMyDHPkvRN0o9Qw
qNCuS9i233VHZvR85zkEHmpwINJaR3JnVfSl6J3VHiGh8Ge6zCFovkRTv4354twv
Vcg3Px+kwJyz5HdcoEb+d/oaoDjq7Zpy3iu9lFc6uux55199QmQ5eiY29yTw1S+6
lZgRZq2XNdZ1AYDgr/SEYYwNHl98h5ZeQa/rh+r4XfEuiAU+TCK72h8q3VJGZDnz
Qs7ZngyzsHeXZJzA9KMuH5UHsBffMNsAGJZMoYFL3QRtU6M9/Aes1MU3guvklQgZ
KILSQjqj2FPseYlgSGDIcpJQ3AOPgz+yQlda22rpEZfdhSi8MEyr48KxRURHH+CK
FgeW0iEPU8DtqX7UTuybCeyvQqww1r/REEXgphaypcXTT3OUM3ECoWqj1jOXTyFj
HluP2cFeRXF3D4FdXyGarYPM+l7WjSNfGz1BryB1ZlpK9p/7qxj3ccC2HTHsOyDr
y+K49a6SsvfhhEvyovKTmiKe0xRvNlS9H15ZFblzqMF8b3ti6RZsR1pl8w4Rm0bZ
/W3c1pzAtH2lsN0/Vm+h+fbkEkj9Bn8SV7apI09bA8PgcSojt/ewsTu8mL3WmKgM
a/aOEmem8rJY5AIJEzypuxC00jBF8ez3ABHfZfjcK0NVvxaXxA/VLGGEqnKG/uY6
fsI/fe78LxQ+5oXdUG+3Se0CAwEAAaNCMEAwDwYDVR0TAQH/BAUwAwEB/zAdBgNV
HQ4EFgQU8ncX+l6o/vY9cdVouslGDDjYr7AwDgYDVR0PAQH/BAQDAgGGMA0GCSqG
SIb3DQEBCwUAA4ICAQBQUfB13HAE4/+qddRxosuej6ip0691x1TPOhwEmSKsxBHi
7zNKpiMdDg1H2DfHb680f0+BazVP6XKlMeJ45/dOlBhbQH3PayFUhuaVevvGyuqc
SE5XCV0vrPSltJczWNWseanMX/mF+lLFjfiRFOs6DRfQUsJ748JzjkZ4Bjgs6Fza
ZsT0pPBWGTMpWmWSBUdGSquEwx4noR8RkpkndZMPvDY7l1ePJlsMu5wP1G4wB9Tc
XzZoZjmDlicmisjEOf6aIW/Vcobpf2Lll07QJNBAsNB1CI69aO4I1258EHBGG3zg
iLKecoaZAeO/n0kZtCW+VmWuF2PlHt/o/0elv+EmBYTksMCv5wiZqAxeJoBF1Pho
L5aPruJKHJwWDBNvOIf2u8g0X5IDUXlwpt/L9ZlNec1OvFefQ05rLisY+GpzjLrF
Ne85akEez3GoorKGB1s6yeHvP2UEgEcyRHCVTjFnanRbEEV16rCf0OY1/k6fi8wr
kkVbbiVghUbN0aqwdmaTd5a+g744tiROJgvM7XpWGuDpWsZkrUx6AEhEL7lAuxM+
vhV4nYWBSipX3tUZQ9rbyltHhoMLP7YNdnhzeSJesYAfz77RP1YQmCuVh6EfnWQU
YDksswBVLuT1sw5XxJFBAJw/6KXf6vb/yPCtbVKoF6ubYfwSUTXkJf2vqmqGOQ==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
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
mpv0
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFazCCA1OgAwIBAgIRAIIQz7DSQONZRGPgu2OCiwAwDQYJKoZIhvcNAQELBQAw
TzELMAkGA1UEBhMCVVMxKTAnBgNVBAoTIEludGVybmV0IFNlY3VyaXR5IFJlc2Vh
cmNoIEdyb3VwMRUwEwYDVQQDEwxJU1JHIFJvb3QgWDEwHhcNMTUwNjA0MTEwNDM4
WhcNMzUwNjA0MTEwNDM4WjBPMQswCQYDVQQGEwJVUzEpMCcGA1UEChMgSW50ZXJu
ZXQgU2VjdXJpdHkgUmVzZWFyY2ggR3JvdXAxFTATBgNVBAMTDElTUkcgUm9vdCBY
MTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAK3oJHP0FDfzm54rVygc
h77ct984kIxuPOZXoHj3dcKi/vVqbvYATyjb3miGbESTtrFj/RQSa78f0uoxmyF+
0TM8ukj13Xnfs7j/EvEhmkvBioZxaUpmZmyPfjxwv60pIgbz5MDmgK7iS4+3mX6U
A5/TR5d8mUgjU+g4rk8Kb4Mu0UlXjIB0ttov0DiNewNwIRt18jA8+o+u3dpjq+sW
T8KOEUt+zwvo/7V3LvSye0rgTBIlDHCNAymg4VMk7BPZ7hm/ELNKjD+Jo2FR3qyH
B5T0Y3HsLuJvW5iB4YlcNHlsdu87kGJ55tukmi8mxdAQ4Q7e2RCOFvu396j3x+UC
B5iPNgiV5+I3lg02dZ77DnKxHZu8A/lJBdiB3QW0KtZB6awBdpUKD9jf1b0SHzUv
KBds0pjBqAlkd25HN7rOrFleaJ1/ctaJxQZBKT5ZPt0m9STJEadao0xAH0ahmbWn
OlFuhjuefXKnEgV4We0+UXgVCwOPjdAvBbI+e0ocS3MFEvzG6uBQE3xDk3SzynTn
jh8BCNAw1FtxNrQHusEwMFxIt4I7mKZ9YIqioymCzLq9gwQbooMDQaHWBfEbwrbw
qHyGO0aoSCqI3Haadr8faqU9GY/rOPNk3sgrDQoo//fb4hVC1CLQJ13hef4Y53CI
rU7m2Ys6xt0nUW7/vGT1M0NPAgMBAAGjQjBAMA4GA1UdDwEB/wQEAwIBBjAPBgNV
HRMBAf8EBTADAQH/MB0GA1UdDgQWBBR5tFnme7bl5AFzgAiIyBpY9umbbjANBgkq
hkiG9w0BAQsFAAOCAgEAVR9YqbyyqFDQDLHYGmkgJykIrGF1XIpu+ILlaS/V9lZL
ubhzEFnTIZd+50xx+7LSYK05qAvqFyFWhfFQDlnrzuBZ6brJFe+GnY+EgPbk6ZGQ
3BebYhtF8GaV0nxvwuo77x/Py9auJ/GpsMiu/X1+mvoiBOv/2X/qkSsisRcOj/KK
NFtY2PwByVS5uCbMiogziUwthDyC3+6WVwW6LLv3xLfHTjuCvjHIInNzktHCgKQ5
ORAzI4JMPJ+GslWYHb4phowim57iaztXOoJwTdwJx4nLCgdNbOhdjsnvzqvHu7Ur
TkXWStAmzOVyyghqpZXjFaH3pO3JLF+l+/+sKAIuvtd7u+Nxe5AW0wdeRlN8NwdC
jNPElpzVmbUq4JUagEiuTDkHzsxHpFKVK7q4+63SM1N95R1NbdWhscdCb+ZAJzVc
oyi3B43njTOQ5yOf+1CceWxG1bQVs5ZufpsMljq4Ui0/1lvh+wjChP4kqKOJ2qxq
4RgqsahDYVvTH9w7jXbyLeiNdd8XM2w9U/t7y0Ff/9yi0GE44Za4rF2LN9d11TPA
mRGunUHBcnWEvgJBQl9nJEiU0Zsnvgc/ubhPgXRR4Xq37Z0j4r7g1SgEEzwxA57d
emyPxgcYxn/eR44/KJ4EBs+lVDR3veyJm+kXQ99b21/+jh5Xos1AnX5iItreGCc=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICGzCCAaGgAwIBAgIQQdKd0XLq7qeAwSxs6S+HUjAKBggqhkjOPQQDAzBPMQsw
CQYDVQQGEwJVUzEpMCcGA1UEChMgSW50ZXJuZXQgU2VjdXJpdHkgUmVzZWFyY2gg
R3JvdXAxFTATBgNVBAMTDElTUkcgUm9vdCBYMjAeFw0yMDA5MDQwMDAwMDBaFw00
MDA5MTcxNjAwMDBaME8xCzAJBgNVBAYTAlVTMSkwJwYDVQQKEyBJbnRlcm5ldCBT
ZWN1cml0eSBSZXNlYXJjaCBHcm91cDEVMBMGA1UEAxMMSVNSRyBSb290IFgyMHYw
EAYHKoZIzj0CAQYFK4EEACIDYgAEzZvVn4CDCuwJSvMWSj5cz3es3mcFDR0HttwW
+1qLFNvicWDEukWVEYmO6gbf9yoWHKS5xcUy4APgHoIYOIvXRdgKam7mAHf7AlF9
ItgKbppbd9/w+kHsOdx1ymgHDB/qo0IwQDAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0T
AQH/BAUwAwEB/zAdBgNVHQ4EFgQUfEKWrt5LSDv6kviejM9ti6lyN5UwCgYIKoZI
zj0EAwMDaAAwZQIwe3lORlCEwkSHRhtFcP9Ymd70/aTSVaYgLXTWNLxBo1BfASdW
tL4ndQavEi51mI38AjEAi/V3bNTIZargCyzuFJ0nN6T5U6VR5CmD1/iQMVtCnwr1
/q4AaOeMSQ+2b1tbFfLn
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFYDCCA0igAwIBAgIQCgFCgAAAAUUjyES1AAAAAjANBgkqhkiG9w0BAQsFADBK
MQswCQYDVQQGEwJVUzESMBAGA1UEChMJSWRlblRydXN0MScwJQYDVQQDEx5JZGVu
VHJ1c3QgQ29tbWVyY2lhbCBSb290IENBIDEwHhcNMTQwMTE2MTgxMjIzWhcNMzQw
MTE2MTgxMjIzWjBKMQswCQYDVQQGEwJVUzESMBAGA1UEChMJSWRlblRydXN0MScw
JQYDVQQDEx5JZGVuVHJ1c3QgQ29tbWVyY2lhbCBSb290IENBIDEwggIiMA0GCSqG
SIb3DQEBAQUAA4ICDwAwggIKAoICAQCnUBneP5k91DNG8W9RYYKyqU+PZ4ldhNlT
3Qwo2dfw/66VQ3KZ+bVdfIrBQuExUHTRgQ18zZshq0PirK1ehm7zCYofWjK9ouuU
+ehcCuz/mNKvcbO0U59Oh++SvL3sTzIwiEsXXlfEU8L2ApeN2WIrvyQfYo3fw7gp
S0l4PJNgiCL8mdo2yMKi1CxUAGc1bnO/AljwpN3lsKImesrgNqUZFvX9t++uP0D1
bVoE/c40yiTcdCMbXTMTEl3EASX2MN0CXZ/g1Ue9tOsbobtJSdifWwLziuQkkORi
T0/Br4sOdBeo0XKIanoBScy0RnnGF7HamB4HWfp1IYVl3ZBWzvurpWCdxJ35UrCL
vYf5jysjCiN2O/cz4ckA82n5S6LgTrx+kzmEB/dEcH7+B1rlsazRGMzyNeVJSQjK
Vsk9+w8YfYs7wRPCTY/JTw436R+hDmrfYi7LNQZReSzIJTj0+kuniVyc0uMNOYZK
dHzVWYfCP04MXFL0PfdSgvHqo6z9STQaKPNBiDoT7uje/5kdX7rL6B7yuVBgwDHT
c+XvvqDtMwt0viAgxGds8AgDelWAf0ZOlqf0Hj7h9tgJ4TNkK2PXMl6f+cB7D3hv
l7yTmvmcEpB4eoCHFddydJxVdHixuuFucAS6T6C6aMN7/zHwcz09lCqxC0EOoP5N
iGVreTO01wIDAQABo0IwQDAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0TAQH/BAUwAwEB
/zAdBgNVHQ4EFgQU7UQZwNPwBovupHu+QucmVMiONnYwDQYJKoZIhvcNAQELBQAD
ggIBAA2ukDL2pkt8RHYZYR4nKM1eVO8lvOMIkPkp165oCOGUAFjvLi5+U1KMtlwH
6oi6mYtQlNeCgN9hCQCTrQ0U5s7B8jeUeLBfnLOic7iPBZM4zY0+sLj7wM+x8uwt
LRvM7Kqas6pgghstO8OEPVeKlh6cdbjTMM1gCIOQ045U8U1mwF10A0Cj7oV+wh93
nAbowacYXVKV7cndJZ5t+qntozo00Fl72u1Q8zW/7esUTTHHYPTa8Yec4kjixsU3
+wYQ+nVZZjFHKdp2mhzpgq7vmrlR94gjmmmVYjzlVYA211QC//G5Xc7UI2/YRYRK
W2XviQzdFKcgyxilJbQN+QHwotL0AMh0jqEqSI5l2xPE4iUXfeu+h1sXIFRRk0pT
AwvsXcoz7WL9RccvW9xYoIA55vrX/hMUpu09lEpCdNTDd1lzzY9GvlU47/rokTLq
l1gEIt44w8y8bckzOmoKaT+gyOpyj4xjhiO9bTyWnpXgSUyqorkqG5w2gXjtw+hG
4iZZRHUe2XWJUc0QhJ1hYMtd+ZciTY6Y5uN/9lu7rs3KSoFrXgvzUeF0K+l+J6fZ
mUlO+KWA2yUPHGNiiskzZ2s8EIPGrd6ozRaOjfAHN3Gf8qv8QfXBi+wAN10J5U6A
7/qxXDgGpRtK4dw4LTzcqx+QGtVKnO7RcGzM7vRX+Bi6hG6H
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFZjCCA06gAwIBAgIQCgFCgAAAAUUjz0Z8AAAAAjANBgkqhkiG9w0BAQsFADBN
MQswCQYDVQQGEwJVUzESMBAGA1UEChMJSWRlblRydXN0MSowKAYDVQQDEyFJZGVu
VHJ1c3QgUHVibGljIFNlY3RvciBSb290IENBIDEwHhcNMTQwMTE2MTc1MzMyWhcN
MzQwMTE2MTc1MzMyWjBNMQswCQYDVQQGEwJVUzESMBAGA1UEChMJSWRlblRydXN0
MSowKAYDVQQDEyFJZGVuVHJ1c3QgUHVibGljIFNlY3RvciBSb290IENBIDEwggIi
MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC2IpT8pEiv6EdrCvsnduTyP4o7
ekosMSqMjbCpwzFrqHd2hCa2rIFCDQjrVVi7evi8ZX3yoG2LqEfpYnYeEe4IFNGy
RBb06tD6Hi9e28tzQa68ALBKK0CyrOE7S8ItneShm+waOh7wCLPQ5CQ1B5+ctMlS
bdsHyo+1W/CD80/HLaXIrcuVIKQxKFdYWuSNG5qrng0M8gozOSI5Cpcu81N3uURF
/YTLNiCBWS2ab21ISGHKTN9T0a9SvESfqy9rg3LvdYDaBjMbXcjaY8ZNzaxmMc3R
3j6HEDbhuaR672BQssvKplbgN6+rNBM5Jeg5ZuSYeqoSmJxZZoY+rfGwyj4GD3vw
EUs3oERte8uojHH01bWRNszwFcYr3lEXsZdMUD2xlVl8BX0tIdUAvwFnol57plzy
9yLxkA2T26pEUWbMfXYD62qoKjgZl3YNa4ph+bz27nb9cCvdKTz4Ch5bQhyLVi9V
GxyhLrXHFub4qjySjmm2AcG1hp2JDws4lFTo6tyePSW8Uybt1as5qsVATFSrsrTZ
2fjXctscvG29ZV/viDUqZi/u9rNl8DONfJhBaUYPQxxp+pu10GFqzcpL2UyQRqsV
WaFHVCkugyhfHMKiq3IXAAaOReyL4jM9f9oZRORicsPfIsbyVtTdX5Vy7W1f90gD
W/3FKqD2cyOEEBsB5wIDAQABo0IwQDAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0TAQH/
BAUwAwEB/zAdBgNVHQ4EFgQU43HgntinQtnbcZFrlJPrw6PRFKMwDQYJKoZIhvcN
AQELBQADggIBAEf63QqwEZE4rU1d9+UOl1QZgkiHVIyqZJnYWv6IAcVYpZmxI1Qj
t2odIFflAWJBF9MJ23XLblSQdf4an4EKwt3X9wnQW3IV5B4Jaj0z8yGa5hV+rVHV
DRDtfULAj+7AmgjVQdZcDiFpboBhDhXAuM/FSRJSzL46zNQuOAXeNf0fb7iAaJg9
TaDKQGXSc3z1i9kKlT/YPyNtGtEqJBnZhbMX73huqVjRI9PHE+1yJX9dsXNw0H8G
lwmEKYBhHfpe/3OsoOOJuBxxFcbeMX8S3OFtm6/n6J91eEyrRjuazr8FGF1NFTwW
mhlQBJqymm9li1JfPFgEKCXAZmExfrngdbkaqIHWchezxQMxNRF4eKLg6TCMf4Df
WN88uieW4oA0beOY02QnrEh+KHdcxiVhJfiFDGX6xDIvpZgF5PgLZxYWxoK4Mhn5
+bl53B/N66+rDt0b20XkeucC4pVd/GnwU2lhlXV5C15V5jgclKlZM57IcXR5f1GJ
tshquDDIajjDbp7hNxbqBWJMWxJH7ae0s1hWx0nzfxJoCTFx8G34Tkf71oXuxVhA
GaQdp/lLQzfcaFpPz+vCZHTetBXZ9FRUGi8c15dxVJCO2SCdUyt/q4/i6jC8UDfv
8Ue1fXwsBOxonbRJRBD0ckscZOf85muQ3Wl9af0AVqW3rLatt8o+Ae+c
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
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
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIECjCCAvKgAwIBAgIJAMJ+QwRORz8ZMA0GCSqGSIb3DQEBCwUAMIGCMQswCQYD
VQQGEwJIVTERMA8GA1UEBwwIQnVkYXBlc3QxFjAUBgNVBAoMDU1pY3Jvc2VjIEx0
ZC4xJzAlBgNVBAMMHk1pY3Jvc2VjIGUtU3ppZ25vIFJvb3QgQ0EgMjAwOTEfMB0G
CSqGSIb3DQEJARYQaW5mb0BlLXN6aWduby5odTAeFw0wOTA2MTYxMTMwMThaFw0y
OTEyMzAxMTMwMThaMIGCMQswCQYDVQQGEwJIVTERMA8GA1UEBwwIQnVkYXBlc3Qx
FjAUBgNVBAoMDU1pY3Jvc2VjIEx0ZC4xJzAlBgNVBAMMHk1pY3Jvc2VjIGUtU3pp
Z25vIFJvb3QgQ0EgMjAwOTEfMB0GCSqGSIb3DQEJARYQaW5mb0BlLXN6aWduby5o
dTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAOn4j/NjrdqG2KfgQvvP
kd6mJviZpWNwrZuuyjNAfW2WbqEORO7hE52UQlKavXWFdCyoDh2Tthi3jCyoz/tc
cbna7P7ofo/kLx2yqHWH2Leh5TvPmUpG0IMZfcChEhyVbUr02MelTTMuhTlAdX4U
fIASmFDHQWe4oIBhVKZsTh/gnQ4H6cm6M+f+wFUoLAKApxn1ntxVUwOXewdI/5n7
N4okxFnMUBBjjqqpGrCEGob5X7uxUG6k0QrM1XF+H6cbfPVTbiJfyyvm1HxdrtbC
xkzlBQHZ7Vf8wSN5/PrIJIOV87VqUQHQd9bpEqH5GoP7ghu5sJf0dgYzQ0mg/wu1
+rUCAwEAAaOBgDB+MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMB0G
A1UdDgQWBBTLD8bfQkPMPcu1SCOhGnqmKrs0aDAfBgNVHSMEGDAWgBTLD8bfQkPM
Pcu1SCOhGnqmKrs0aDAbBgNVHREEFDASgRBpbmZvQGUtc3ppZ25vLmh1MA0GCSqG
SIb3DQEBCwUAA4IBAQDJ0Q5eLtXMs3w+y/w9/w0olZMEyL/azXm4Q5DwpL7v8u8h
mLzU1F0G9u5C7DBsoKqpyvGvivo/C3NqPuouQH4frlRheesuCDfXI/OMn74dseGk
ddug4lQUsbocKaQY9hK6ohQU4zE1yED/t+AFdlfBHFny+L/k7SViXITwfn4fs775
tyERzAMBVnCnEJIeGzSBHq2cGsMEPO0CYdYeBvNfOofyK/FFh+U9rNHHV4S9a67c
2Pm2G2JwCz02yULyMtd6YebS2z3PyKnJm9zbWETXbzivf3jTo60adbocwTZ8jx5t
HMN1Rq41Bab2XD0h7lbwyYIiLXpUq3DDfSJlgnCW
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICWTCCAd+gAwIBAgIQZvI9r4fei7FK6gxXMQHC7DAKBggqhkjOPQQDAzBlMQsw
CQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTYwNAYD
VQQDEy1NaWNyb3NvZnQgRUNDIFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIw
MTcwHhcNMTkxMjE4MjMwNjQ1WhcNNDIwNzE4MjMxNjA0WjBlMQswCQYDVQQGEwJV
UzEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTYwNAYDVQQDEy1NaWNy
b3NvZnQgRUNDIFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTcwdjAQBgcq
hkjOPQIBBgUrgQQAIgNiAATUvD0CQnVBEyPNgASGAlEvaqiBYgtlzPbKnR5vSmZR
ogPZnZH6thaxjG7efM3beaYvzrvOcS/lpaso7GMEZpn4+vKTEAXhgShC48Zo9OYb
hGBKia/teQ87zvH2RPUBeMCjVDBSMA4GA1UdDwEB/wQEAwIBhjAPBgNVHRMBAf8E
BTADAQH/MB0GA1UdDgQWBBTIy5lycFIM+Oa+sgRXKSrPQhDtNTAQBgkrBgEEAYI3
FQEEAwIBADAKBggqhkjOPQQDAwNoADBlAjBY8k3qDPlfXu5gKcs68tvWMoQZP3zV
L8KxzJOuULsJMsbG7X7JNpQS5GiFBqIb0C8CMQCZ6Ra0DvpWSNSkMBaReNtUjGUB
iudQZsIxtzm6uBoiB078a1QWIP8rtedMDE2mT3M=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFqDCCA5CgAwIBAgIQHtOXCV/YtLNHcB6qvn9FszANBgkqhkiG9w0BAQwFADBl
MQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTYw
NAYDVQQDEy1NaWNyb3NvZnQgUlNBIFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5
IDIwMTcwHhcNMTkxMjE4MjI1MTIyWhcNNDIwNzE4MjMwMDIzWjBlMQswCQYDVQQG
EwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTYwNAYDVQQDEy1N
aWNyb3NvZnQgUlNBIFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTcwggIi
MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDKW76UM4wplZEWCpW9R2LBifOZ
Nt9GkMml7Xhqb0eRaPgnZ1AzHaGm++DlQ6OEAlcBXZxIQIJTELy/xztokLaCLeX0
ZdDMbRnMlfl7rEqUrQ7eS0MdhweSE5CAg2Q1OQT85elss7YfUJQ4ZVBcF0a5toW1
HLUX6NZFndiyJrDKxHBKrmCk3bPZ7Pw71VdyvD/IybLeS2v4I2wDwAW9lcfNcztm
gGTjGqwu+UcF8ga2m3P1eDNbx6H7JyqhtJqRjJHTOoI+dkC0zVJhUXAoP8XFWvLJ
jEm7FFtNyP9nTUwSlq31/niol4fX/V4ggNyhSyL71Imtus5Hl0dVe49FyGcohJUc
aDDv70ngNXtk55iwlNpNhTs+VcQor1fznhPbRiefHqJeRIOkpcrVE7NLP8TjwuaG
YaRSMLl6IE9vDzhTyzMMEyuP1pq9KsgtsRx9S1HKR9FIJ3Jdh+vVReZIZZ2vUpC6
W6IYZVcSn2i51BVrlMRpIpj0M+Dt+VGOQVDJNE92kKz8OMHY4Xu54+OU4UZpyw4K
UGsTuqwPN1q3ErWQgR5WrlcihtnJ0tHXUeOrO8ZV/R4O03QK0dqq6mm4lyiPSMQH
+FJDOvTKVTUssKZqwJz58oHhEmrARdlns87/I6KJClTUFLkqqNfs+avNJVgyeY+Q
W5g5xAgGwax/Dj0ApQIDAQABo1QwUjAOBgNVHQ8BAf8EBAMCAYYwDwYDVR0TAQH/
BAUwAwEB/zAdBgNVHQ4EFgQUCctZf4aycI8awznjwNnpv7tNsiMwEAYJKwYBBAGC
NxUBBAMCAQAwDQYJKoZIhvcNAQEMBQADggIBAKyvPl3CEZaJjqPnktaXFbgToqZC
LgLNFgVZJ8og6Lq46BrsTaiXVq5lQ7GPAJtSzVXNUzltYkyLDVt8LkS/gxCP81OC
gMNPOsduET/m4xaRhPtthH80dK2Jp86519efhGSSvpWhrQlTM93uCupKUY5vVau6
tZRGrox/2KJQJWVggEbbMwSubLWYdFQl3JPk+ONVFT24bcMKpBLBaYVu32TxU5nh
SnUgnZUP5NbcA/FZGOhHibJXWpS2qdgXKxdJ5XbLwVaZOjex/2kskZGT4d9Mozd2
TaGf+G0eHdP67Pv0RR0Tbc/3WeUiJ3IrhvNXuzDtJE3cfVa7o7P4NHmJweDyAmH3
pvwPuxwXC65B2Xy9J6P9LjrRk5Sxcx0ki69bIImtt2dmefU6xqaWM/5TkshGsRGR
xpl/j8nWZjEgQRCHLQzWwa80mMpkg/sTV9HB8Dx6jKXB/ZUhoHHBk2dxEuqPiApp
GWSZI1b7rCoucL5mxAyE7+WL85MB+GqQk2dLsmijtWKP6T+MejteD+eMuMZ87zf9
dOLITzNy4ZQ5bb0Sr74MTnB8G2+NszKTc0QWbej09+CVgI+WXTik9KveCjCHk9hN
AHFiRSdLOkKEW39lt2c0Ui2cFmuqqNh7o0JMcccMyj6D5KbvtwEwXlGjefVwaaZB
RA+GsCyRxj3qrg+E
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFojCCA4qgAwIBAgIUAZQwHqIL3fXFMyqxQ0Rx+NZQTQ0wDQYJKoZIhvcNAQEM
BQAwaTELMAkGA1UEBhMCS1IxJjAkBgNVBAoMHU5BVkVSIEJVU0lORVNTIFBMQVRG
T1JNIENvcnAuMTIwMAYDVQQDDClOQVZFUiBHbG9iYWwgUm9vdCBDZXJ0aWZpY2F0
aW9uIEF1dGhvcml0eTAeFw0xNzA4MTgwODU4NDJaFw0zNzA4MTgyMzU5NTlaMGkx
CzAJBgNVBAYTAktSMSYwJAYDVQQKDB1OQVZFUiBCVVNJTkVTUyBQTEFURk9STSBD
b3JwLjEyMDAGA1UEAwwpTkFWRVIgR2xvYmFsIFJvb3QgQ2VydGlmaWNhdGlvbiBB
dXRob3JpdHkwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC21PGTXLVA
iQqrDZBbUGOukJR0F0Vy1ntlWilLp1agS7gvQnXp2XskWjFlqxcX0TM62RHcQDaH
38dq6SZeWYp34+hInDEW+j6RscrJo+KfziFTowI2MMtSAuXaMl3Dxeb57hHHi8lE
HoSTGEq0n+USZGnQJoViAbbJAh2+g1G7XNr4rRVqmfeSVPc0W+m/6imBEtRTkZaz
kVrd/pBzKPswRrXKCAfHcXLJZtM0l/aM9BhK4dA9WkW2aacp+yPOiNgSnABIqKYP
szuSjXEOdMWLyEz59JuOuDxp7W87UC9Y7cSw0BwbagzivESq2M0UXZR4Yb8Obtoq
vC8MC3GmsxY/nOb5zJ9TNeIDoKAYv7vxvvTWjIcNQvcGufFt7QSUqP620wbGQGHf
nZ3zVHbOUzoBppJB7ASjjw2i1QnK1sua8e9DXcCrpUHPXFNwcMmIpi3Ua2FzUCaG
YQ5fG8Ir4ozVu53BA0K6lNpfqbDKzE0K70dpAy8i+/Eozr9dUGWokG2zdLAIx6yo
0es+nPxdGoMuK8u180SdOqcXYZaicdNwlhVNt0xz7hlcxVs+Qf6sdWA7G2POAN3a
CJBitOUt7kinaxeZVL6HSuOpXgRM6xBtVNbv8ejyYhbLgGvtPe31HzClrkvJE+2K
AQHJuFFYwGY6sWZLxNUxAmLpdIQM201GLQIDAQABo0IwQDAdBgNVHQ4EFgQU0p+I
36HNLL3s9TsBAZMzJ7LrYEswDgYDVR0PAQH/BAQDAgEGMA8GA1UdEwEB/wQFMAMB
Af8wDQYJKoZIhvcNAQEMBQADggIBADLKgLOdPVQG3dLSLvCkASELZ0jKbY7gyKoN
qo0hV4/GPnrK21HUUrPUloSlWGB/5QuOH/XcChWB5Tu2tyIvCZwTFrFsDDUIbatj
cu3cvuzHV+YwIHHW1xDBE1UBjCpD5EHxzzp6U5LOogMFDTjfArsQLtk70pt6wKGm
+LUx5vR1yblTmXVHIloUFcd4G7ad6Qz4G3bxhYTeodoS76TiEJd6eN4MUZeoIUCL
hr0N8F5OSza7OyAfikJW4Qsav3vQIkMsRIz75Sq0bBwcupTgE34h5prCy8VCZLQe
lHsIJchxzIdFV4XTnyliIoNRlwAYl3dqmJLJfGBs32x9SuRwTMKeuB330DTHD8z7
p/8Dvq1wkNoL3chtl1+afwkyQf3NosxabUzyqkn+Zvjp2DXrDige7kgvOtB5CTh8
piKCk5XQA76+AqAF3SAi428diDRgxuYKuQl1C/AH6GmWNcf7I4GOODm4RStDeKLR
LBT/DShycpWbXgnbiUSYqqFJu3FS8r/2/yehNq+4tneI3TqkbZs0kNwUXTC/t+sX
5Ie3cdCh13cV1ELX8vMxmV2b3RZtP+oGI/hGoiLtk/bdmuYqh7GYVPEi92tF4+KO
dh2ajcQGjTa3FPOdVGm3jjzVpG2Tgbet9r1ke8LJaDmgkpzNNIaRkPpkUZ3+/uul
9XXeifdy
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIEFTCCAv2gAwIBAgIGSUEs5AAQMA0GCSqGSIb3DQEBCwUAMIGnMQswCQYDVQQG
EwJIVTERMA8GA1UEBwwIQnVkYXBlc3QxFTATBgNVBAoMDE5ldExvY2sgS2Z0LjE3
MDUGA1UECwwuVGFuw7pzw610dsOhbnlraWFkw7NrIChDZXJ0aWZpY2F0aW9uIFNl
cnZpY2VzKTE1MDMGA1UEAwwsTmV0TG9jayBBcmFueSAoQ2xhc3MgR29sZCkgRsWR
dGFuw7pzw610dsOhbnkwHhcNMDgxMjExMTUwODIxWhcNMjgxMjA2MTUwODIxWjCB
pzELMAkGA1UEBhMCSFUxETAPBgNVBAcMCEJ1ZGFwZXN0MRUwEwYDVQQKDAxOZXRM
b2NrIEtmdC4xNzA1BgNVBAsMLlRhbsO6c8OtdHbDoW55a2lhZMOzayAoQ2VydGlm
aWNhdGlvbiBTZXJ2aWNlcykxNTAzBgNVBAMMLE5ldExvY2sgQXJhbnkgKENsYXNz
IEdvbGQpIEbFkXRhbsO6c8OtdHbDoW55MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A
MIIBCgKCAQEAxCRec75LbRTDofTjl5Bu0jBFHjzuZ9lk4BqKf8owyoPjIMHj9DrT
lF8afFttvzBPhCf2nx9JvMaZCpDyD/V/Q4Q3Y1GLeqVw/HpYzY6b7cNGbIRwXdrz
AZAj/E4wqX7hJ2Pn7WQ8oLjJM2P+FpD/sLj916jAwJRDC7bVWaaeVtAkH3B5r9s5
VA1lddkVQZQBr17s9o3x/61k/iCa11zr/qYfCGSji3ZVrR47KGAuhyXoqq8fxmRG
ILdwfzzeSNuWU7c5d+Qa4scWhHaXWy+7GRWF+GmF9ZmnqfI0p6m2pgP8b4Y9VHx2
BJtr+UBdADTHLpl1neWIA6pN+APSQnbAGwIDAKiLo0UwQzASBgNVHRMBAf8ECDAG
AQH/AgEEMA4GA1UdDwEB/wQEAwIBBjAdBgNVHQ4EFgQUzPpnk/C2uNClwB7zU/2M
U9+D15YwDQYJKoZIhvcNAQELBQADggEBAKt/7hwWqZw8UQCgwBEIBaeZ5m8BiFRh
bvG5GK1Krf6BQCOUL/t1fC8oS2IkgYIL9WHxHG64YTjrgfpioTtaYtOUZcTh5m2C
+C8lcLIhJsFyUR+MLMOEkMNaj7rP9KdlpeuY0fsFskZ1FSNqb4VjMIDw1Z4fKRzC
bLBQWV2QWzuoDTDPv31/zvGdg73JRm4gpvlhUbohL3u+pRVjodSVh/GeufOJ8z2F
uLjbvrW5KfnaNwUASZQDhETnv0Mxz3WLJdH0pmT1kvarBes96aULNmLazAZfNou2
XjG4Kvte9nHfRCaexOYNkbQudZWAUWpLMKawYqGT8ZvYzsRjdT9ZR7E=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICNTCCAbqgAwIBAgIQI/nD1jWvjyhLH/BU6n6XnTAKBggqhkjOPQQDAzBLMQsw
CQYDVQQGEwJDSDEZMBcGA1UECgwQT0lTVEUgRm91bmRhdGlvbjEhMB8GA1UEAwwY
T0lTVEUgU2VydmVyIFJvb3QgRUNDIEcxMB4XDTIzMDUzMTE0NDIyOFoXDTQ4MDUy
NDE0NDIyN1owSzELMAkGA1UEBhMCQ0gxGTAXBgNVBAoMEE9JU1RFIEZvdW5kYXRp
b24xITAfBgNVBAMMGE9JU1RFIFNlcnZlciBSb290IEVDQyBHMTB2MBAGByqGSM49
AgEGBSuBBAAiA2IABBcv+hK8rBjzCvRE1nZCnrPoH7d5qVi2+GXROiFPqOujvqQy
cvO2Ackr/XeFblPdreqqLiWStukhEaivtUwL85Zgmjvn6hp4LrQ95SjeHIC6XG4N
2xml4z+cKrhAS93mT6NjMGEwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBQ3
TYhlz/w9itWj8UnATgwQb0K0nDAdBgNVHQ4EFgQUN02IZc/8PYrVo/FJwE4MEG9C
tJwwDgYDVR0PAQH/BAQDAgGGMAoGCCqGSM49BAMDA2kAMGYCMQCpKjAd0MKfkFFR
QD6VVCHNFmb3U2wIFjnQEnx/Yxvf4zgAOdktUyBFCxxgZzFDJe0CMQCSia7pXGKD
YmH5LVerVrkR3SW+ak5KGoJr3M/TvEqzPNcum9v4KGm8ay3sMaE641c=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFgzCCA2ugAwIBAgIQVaXZZ5Qoxu0M+ifdWwFNGDANBgkqhkiG9w0BAQwFADBL
MQswCQYDVQQGEwJDSDEZMBcGA1UECgwQT0lTVEUgRm91bmRhdGlvbjEhMB8GA1UE
AwwYT0lTVEUgU2VydmVyIFJvb3QgUlNBIEcxMB4XDTIzMDUzMTE0MzcxNloXDTQ4
MDUyNDE0MzcxNVowSzELMAkGA1UEBhMCQ0gxGTAXBgNVBAoMEE9JU1RFIEZvdW5k
YXRpb24xITAfBgNVBAMMGE9JU1RFIFNlcnZlciBSb290IFJTQSBHMTCCAiIwDQYJ
KoZIhvcNAQEBBQADggIPADCCAgoCggIBAKqu9KuCz/vlNwvn1ZatkOhLKdxVYOPM
vLO8LZK55KN68YG0nnJyQ98/qwsmtO57Gmn7KNByXEptaZnwYx4M0rH/1ow00O7b
rEi56rAUjtgHqSSY3ekJvqgiG1k50SeH3BzN+Puz6+mTeO0Pzjd8JnduodgsIUzk
ik/HEzxux9UTl7Ko2yRpg1bTacuCErudG/L4NPKYKyqOBGf244ehHa1uzjZ0Dl4z
O8vbUZeUapU8zhhabkvG/AePLhq5SvdkNCncpo1Q4Y2LS+VIG24ugBA/5J8bZT8R
tOpXaZ+0AOuFJJkk9SGdl6r7NH8CaxWQrbueWhl/pIzY+m0o/DjH40ytas7ZTpOS
jswMZ78LS5bOZmdTaMsXEY5Z96ycG7mOaES3GK/m5Q9l3JUJsJMStR8+lKXHiHUh
sd4JJCpM4rzsTGdHwimIuQq6+cF0zowYJmXa92/GjHtoXAvuY8BeS/FOzJ8vD+Ho
mnqT8eDI278n5mUpezbgMxVz8p1rhAhoKzYHKyfMeNhqhw5HdPSqoBNdZH702xSu
+zrkL8Fl47l6QGzwBrd7KJvX4V84c5Ss2XCTLdyEr0YconosP4EmQufU2MVshGYR
i3drVByjtdgQ8K4p92cIiBdcuJd5z+orKu5YM+Vt6SmqZQENghPsJQtdLEByFSnT
kCz3GkPVavBpAgMBAAGjYzBhMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU
8snBDw1jALvsRQ5KH7WxszbNDo0wHQYDVR0OBBYEFPLJwQ8NYwC77EUOSh+1sbM2
zQ6NMA4GA1UdDwEB/wQEAwIBhjANBgkqhkiG9w0BAQwFAAOCAgEANGd5sjrG5T33
I3K5Ce+SrScfoE4KsvXaFwyihdJ+klH9FWXXXGtkFu6KRcoMQzZENdl//nk6HOjG
5D1rd9QhEOP28yBOqb6J8xycqd+8MDoX0TJD0KqKchxRKEzdNsjkLWd9kYccnbz8
qyiWXmFcuCIzGEgWUOrKL+mlSdx/PKQZvDatkuK59EvV6wit53j+F8Bdh3foZ3dP
AGav9LEDOr4SfEE15fSmG0eLy3n31r8Xbk5l8PjaV8GUgeV6Vg27Rn9vkf195hfk
gSe7BYhW3SCl95gtkRlpMV+bMPKZrXJAlszYd2abtNUOshD+FKrDgHGdPY3ofRRs
YWSGRqbXVMW215AWRqWFyp464+YTFrYVI8ypKVL9AMb2kI5Wj4kI3Zaq5tNqqYY1
9tVFeEJKRvwDyF7YZvZFZSS0vod7VSCd9521Kvy5YhnLbDuv0204bKt7ph6N/Ome
/msVuduCmsuY33OhkKCgxeDoAaijFJzIwZqsFVAzje18KotzlUBDJvyBpCpfOZC3
J8tRd/iWkx7P8nd9H0aTolkelUTFLXVksNb54Dxp6gS1HAviRkRNQzuXSXERvSS2
wq1yVAb+axj5d9spLFKebXd7Yv0PTY6YMjAwcRLWJTXjn/hvnLXrahut6hDTlhZy
BiElxky8j3C7DOReIoMt0r7+hVu05L0=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIDtTCCAp2gAwIBAgIQdrEgUnTwhYdGs/gjGvbCwDANBgkqhkiG9w0BAQsFADBt
MQswCQYDVQQGEwJDSDEQMA4GA1UEChMHV0lTZUtleTEiMCAGA1UECxMZT0lTVEUg
Rm91bmRhdGlvbiBFbmRvcnNlZDEoMCYGA1UEAxMfT0lTVEUgV0lTZUtleSBHbG9i
YWwgUm9vdCBHQiBDQTAeFw0xNDEyMDExNTAwMzJaFw0zOTEyMDExNTEwMzFaMG0x
CzAJBgNVBAYTAkNIMRAwDgYDVQQKEwdXSVNlS2V5MSIwIAYDVQQLExlPSVNURSBG
b3VuZGF0aW9uIEVuZG9yc2VkMSgwJgYDVQQDEx9PSVNURSBXSVNlS2V5IEdsb2Jh
bCBSb290IEdCIENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA2Be3
HEokKtaXscriHvt9OO+Y9bI5mE4nuBFde9IllIiCFSZqGzG7qFshISvYD06fWvGx
WuR51jIjK+FTzJlFXHtPrby/h0oLS5daqPZI7H17Dc0hBt+eFf1Biki3IPShehtX
1F1Q/7pn2COZH8g/497/b1t3sWtuuMlk9+HKQUYOKXHQuSP8yYFfTvdv37+ErXNk
u7dCjmn21HYdfp2nuFeKUWdy19SouJVUQHMD9ur06/4oQnc/nSMbsrY9gBQHTC5P
99UKFg29ZkM3fiNDecNAhvVMKdqOmq0NpQSHiB6F4+lT1ZvIiwNjeOvgGUpuuy9r
M2RYk61pv48b74JIxwIDAQABo1EwTzALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUw
AwEB/zAdBgNVHQ4EFgQUNQ/INmNe4qPs+TtmFc5RUuORmj0wEAYJKwYBBAGCNxUB
BAMCAQAwDQYJKoZIhvcNAQELBQADggEBAEBM+4eymYGQfp3FsLAmzYh7KzKNbrgh
cViXfa43FK8+5/ea4n32cZiZBKpDdHij40lhPnOMTZTg+XHEthYOU3gf1qKHLwI5
gSk8rxWYITD+KJAAjNHhy/peyP34EEY7onhCkRd0VQreUGdNZtGn//3ZwLWoo4rO
ZvUPQ82nK1d7Y0Zqqi5S2PTt4W2tKZB4SLrhI6qjiey1q5bAtEuiHZeeevJuQHHf
aPFlTc58Bd9TZaml8LGXBHAVRgOY1NK/VLSgWH1Sb9pWJmLU2NuJMW8c8CLC02Ic
Nc1MaRVUGpCY3useX8p3x8uOPUNpnJpY0CQ73xtAln41rYHHTnG6iBM=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICaTCCAe+gAwIBAgIQISpWDK7aDKtARb8roi066jAKBggqhkjOPQQDAzBtMQsw
CQYDVQQGEwJDSDEQMA4GA1UEChMHV0lTZUtleTEiMCAGA1UECxMZT0lTVEUgRm91
bmRhdGlvbiBFbmRvcnNlZDEoMCYGA1UEAxMfT0lTVEUgV0lTZUtleSBHbG9iYWwg
Um9vdCBHQyBDQTAeFw0xNzA1MDkwOTQ4MzRaFw00MjA1MDkwOTU4MzNaMG0xCzAJ
BgNVBAYTAkNIMRAwDgYDVQQKEwdXSVNlS2V5MSIwIAYDVQQLExlPSVNURSBGb3Vu
ZGF0aW9uIEVuZG9yc2VkMSgwJgYDVQQDEx9PSVNURSBXSVNlS2V5IEdsb2JhbCBS
b290IEdDIENBMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAETOlQwMYPchi82PG6s4ni
eUqjFqdrVCTbUf/q9Akkwwsin8tqJ4KBDdLArzHkdIJuyiXZjHWd8dvQmqJLIX4W
p2OQ0jnUsYd4XxiWD1AbNTcPasbc2RNNpI6QN+a9WzGRo1QwUjAOBgNVHQ8BAf8E
BAMCAQYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUSIcUrOPDnpBgOtfKie7T
rYy0UGYwEAYJKwYBBAGCNxUBBAMCAQAwCgYIKoZIzj0EAwMDaAAwZQIwJsdpW9zV
57LnyAyMjMPdeYwbY9XJUpROTYJKcx6ygISpJcBMWm1JKWB4E+J+SOtkAjEA2zQg
Mgj/mkkCtojeFK9dbJlxjRo/i9fgojaGHAeCOnZT/cKi7e97sIBPWA9LUzm9
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFYDCCA0igAwIBAgIUeFhfLq0sGUvjNwc1NBMotZbUZZMwDQYJKoZIhvcNAQEL
BQAwSDELMAkGA1UEBhMCQk0xGTAXBgNVBAoTEFF1b1ZhZGlzIExpbWl0ZWQxHjAc
BgNVBAMTFVF1b1ZhZGlzIFJvb3QgQ0EgMSBHMzAeFw0xMjAxMTIxNzI3NDRaFw00
MjAxMTIxNzI3NDRaMEgxCzAJBgNVBAYTAkJNMRkwFwYDVQQKExBRdW9WYWRpcyBM
aW1pdGVkMR4wHAYDVQQDExVRdW9WYWRpcyBSb290IENBIDEgRzMwggIiMA0GCSqG
SIb3DQEBAQUAA4ICDwAwggIKAoICAQCgvlAQjunybEC0BJyFuTHK3C3kEakEPBtV
wedYMB0ktMPvhd6MLOHBPd+C5k+tR4ds7FtJwUrVu4/sh6x/gpqG7D0DmVIB0jWe
rNrwU8lmPNSsAgHaJNM7qAJGr6Qc4/hzWHa39g6QDbXwz8z6+cZM5cOGMAqNF341
68Xfuw6cwI2H44g4hWf6Pser4BOcBRiYz5P1sZK0/CPTz9XEJ0ngnjybCKOLXSoh
4Pw5qlPafX7PGglTvF0FBM+hSo+LdoINofjSxxR3W5A2B4GbPgb6Ul5jxaYA/qXp
UhtStZI5cgMJYr2wYBZupt0lwgNm3fME0UDiTouG9G/lg6AnhF4EwfWQvTA9xO+o
abw4m6SkltFi2mnAAZauy8RRNOoMqv8hjlmPSlzkYZqn0ukqeI1RPToV7qJZjqlc
3sX5kCLliEVx3ZGZbHqfPT2YfF72vhZooF6uCyP8Wg+qInYtyaEQHeTTRCOQiJ/G
KubX9ZqzWB4vMIkIG1SitZgj7Ah3HJVdYdHLiZxfokqRmu8hqkkWCKi9YSgxyXSt
hfbZxbGL0eUQMk1fiyA6PEkfM4VZDdvLCXVDaXP7a3F98N/ETH3Goy7IlXnLc6KO
Tk0k+17kBL5yG6YnLUlamXrXXAkgt3+UuU/xDRxeiEIbEbfnkduebPRq34wGmAOt
zCjvpUfzUwIDAQABo0IwQDAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIB
BjAdBgNVHQ4EFgQUo5fW816iEOGrRZ88F2Q87gFwnMwwDQYJKoZIhvcNAQELBQAD
ggIBABj6W3X8PnrHX3fHyt/PX8MSxEBd1DKquGrX1RUVRpgjpeaQWxiZTOOtQqOC
MTaIzen7xASWSIsBx40Bz1szBpZGZnQdT+3Btrm0DWHMY37XLneMlhwqI2hrhVd2
cDMT/uFPpiN3GPoajOi9ZcnPP/TJF9zrx7zABC4tRi9pZsMbj/7sPtPKlL92CiUN
qXsCHKnQO18LwIE6PWThv6ctTr1NxNgpxiIY0MWscgKCP6o6ojoilzHdCGPDdRS5
YCgtW2jgFqlmgiNR9etT2DGbe+m3nUvriBbP+V04ikkwj+3x6xn0dxoxGE1nVGwv
b2X52z3sIexe9PSLymBlVNFxZPT5pqOBMzYzcfCkeF9OrYMh3jRJjehZrJ3ydlo2
8hP0r+AJx2EqbPfgna67hkooby7utHnNkDPDs3b69fBsnQGQ+p6Q9pxyz0fawx/k
NSBT8lTR32GDpgLiJTjehTItXnOQUl1CxM49S+H5GYQd1aJQzEH7QRTDvdbJWqNj
ZgKAvQU6O0ec7AAmTPWIUb+oI38YB7AL7YsmoWTTYUrrXJ/es69nA7Mf3W1daWhp
q1467HxpvMc7hU6eFbm0FU/DlXpY18ls6Wy58yljXrQs8C097Vpl4KlbQMJImYFt
nh8GKjwStIsPm6Ik8KaN1nrgS7ZklmOVhMJKzRwuJIczYOXD
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFYDCCA0igAwIBAgIURFc0JFuBiZs18s64KztbpybwdSgwDQYJKoZIhvcNAQEL
BQAwSDELMAkGA1UEBhMCQk0xGTAXBgNVBAoTEFF1b1ZhZGlzIExpbWl0ZWQxHjAc
BgNVBAMTFVF1b1ZhZGlzIFJvb3QgQ0EgMiBHMzAeFw0xMjAxMTIxODU5MzJaFw00
MjAxMTIxODU5MzJaMEgxCzAJBgNVBAYTAkJNMRkwFwYDVQQKExBRdW9WYWRpcyBM
aW1pdGVkMR4wHAYDVQQDExVRdW9WYWRpcyBSb290IENBIDIgRzMwggIiMA0GCSqG
SIb3DQEBAQUAA4ICDwAwggIKAoICAQChriWyARjcV4g/Ruv5r+LrI3HimtFhZiFf
qq8nUeVuGxbULX1QsFN3vXg6YOJkApt8hpvWGo6t/x8Vf9WVHhLL5hSEBMHfNrMW
n4rjyduYNM7YMxcoRvynyfDStNVNCXJJ+fKH46nafaF9a7I6JaltUkSs+L5u+9ym
c5GQYaYDFCDy54ejiK2toIz/pgslUiXnFgHVy7g1gQyjO/Dh4fxaXc6AcW34Sas+
O7q414AB+6XrW7PFXmAqMaCvN+ggOp+oMiwMzAkd056OXbxMmO7FGmh77FOm6RQ1
o9/NgJ8MSPsc9PG/Srj61YxxSscfrf5BmrODXfKEVu+lV0POKa2Mq1W/xPtbAd0j
IaFYAI7D0GoT7RPjEiuA3GfmlbLNHiJuKvhB1PLKFAeNilUSxmn1uIZoL1NesNKq
IcGY5jDjZ1XHm26sGahVpkUG0CM62+tlXSoREfA7T8pt9DTEceT/AFr2XK4jYIVz
8eQQsSWu1ZK7E8EM4DnatDlXtas1qnIhO4M15zHfeiFuuDIIfR0ykRVKYnLP43eh
vNURG3YBZwjgQQvD6xVu+KQZ2aKrr+InUlYrAoosFCT5v0ICvybIxo/gbjh9Uy3l
7ZizlWNof/k19N+IxWA1ksB8aRxhlRbQ694Lrz4EEEVlWFA4r0jyWbYW8jwNkALG
cC4BrTwV1wIDAQABo0IwQDAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIB
BjAdBgNVHQ4EFgQU7edvdlq/YOxJW8ald7tyFnGbxD0wDQYJKoZIhvcNAQELBQAD
ggIBAJHfgD9DCX5xwvfrs4iP4VGyvD11+ShdyLyZm3tdquXK4Qr36LLTn91nMX66
AarHakE7kNQIXLJgapDwyM4DYvmL7ftuKtwGTTwpD4kWilhMSA/ohGHqPHKmd+RC
roijQ1h5fq7KpVMNqT1wvSAZYaRsOPxDMuHBR//47PERIjKWnML2W2mWeyAMQ0Ga
W/ZZGYjeVYg3UQt4XAoeo0L9x52ID8DyeAIkVJOviYeIyUqAHerQbj5hLja7NQ4n
lv1mNDthcnPxFlxHBlRJAHpYErAK74X9sbgzdWqTHBLmYF5vHX/JHyPLhGGfHoJE
+V+tYlUkmlKY7VHnoX6XOuYvHxHaU4AshZ6rNRDbIl9qxV6XU/IyAgkwo1jwDQHV
csaxfGl7w/U2Rcxhbl5MlMVerugOXou/983g7aEOGzPuVBj+D77vfoRrQ+NwmNtd
dbINWQeFFSM51vHfqSYP1kjHs6Yi9TM3WpVHn3u6GBVv/9YUZINJ0gpnIdsPNWNg
KCLjsZWDzYWm3S8P52dSbrsvhXz1SnPnxT7AvSESBT/8twNJAlvIJebiVDj1eYeM
HVOyToV7BjjHLPj4sHKNJeV3UvQDHEimUF+IIDBu8oJDqz2XhOdT+yHBTw8imoa4
WSr2Rz0ZiC3oheGe7IUIarFsNMkd7EgrO3jtZsSOeWmD3n+M
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFYDCCA0igAwIBAgIULvWbAiin23r/1aOp7r0DoM8Sah0wDQYJKoZIhvcNAQEL
BQAwSDELMAkGA1UEBhMCQk0xGTAXBgNVBAoTEFF1b1ZhZGlzIExpbWl0ZWQxHjAc
BgNVBAMTFVF1b1ZhZGlzIFJvb3QgQ0EgMyBHMzAeFw0xMjAxMTIyMDI2MzJaFw00
MjAxMTIyMDI2MzJaMEgxCzAJBgNVBAYTAkJNMRkwFwYDVQQKExBRdW9WYWRpcyBM
aW1pdGVkMR4wHAYDVQQDExVRdW9WYWRpcyBSb290IENBIDMgRzMwggIiMA0GCSqG
SIb3DQEBAQUAA4ICDwAwggIKAoICAQCzyw4QZ47qFJenMioKVjZ/aEzHs286IxSR
/xl/pcqs7rN2nXrpixurazHb+gtTTK/FpRp5PIpM/6zfJd5O2YIyC0TeytuMrKNu
FoM7pmRLMon7FhY4futD4tN0SsJiCnMK3UmzV9KwCoWdcTzeo8vAMvMBOSBDGzXR
U7Ox7sWTaYI+FrUoRqHe6okJ7UO4BUaKhvVZR74bbwEhELn9qdIoyhA5CcoTNs+c
ra1AdHkrAj80//ogaX3T7mH1urPnMNA3I4ZyYUUpSFlob3emLoG+B01vr87ERROR
FHAGjx+f+IdpsQ7vw4kZ6+ocYfx6bIrc1gMLnia6Et3UVDmrJqMz6nWB2i3ND0/k
A9HvFZcba5DFApCTZgIhsUfei5pKgLlVj7WiL8DWM2fafsSntARE60f75li59wzw
eyuxwHApw0BiLTtIadwjPEjrewl5qW3aqDCYz4ByA4imW0aucnl8CAMhZa634Ryl
sSqiMd5mBPfAdOhx3v89WcyWJhKLhZVXGqtrdQtEPREoPHtht+KPZ0/l7DxMYIBp
VzgeAVuNVejH38DMdyM0SXV89pgR6y3e7UEuFAUCf+D+IOs15xGsIs5XPd7JMG0Q
A4XN8f+MFrXBsj6IbGB/kE+V9/YtrQE5BwT6dYB9v0lQ7e/JxHwc64B+27bQ3RP+
ydOc17KXqQIDAQABo0IwQDAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIB
BjAdBgNVHQ4EFgQUxhfQvKjqAkPyGwaZXSuQILnXnOQwDQYJKoZIhvcNAQELBQAD
ggIBADRh2Va1EodVTd2jNTFGu6QHcrxfYWLopfsLN7E8trP6KZ1/AvWkyaiTt3px
KGmPc+FSkNrVvjrlt3ZqVoAh313m6Tqe5T72omnHKgqwGEfcIHB9UqM+WXzBusnI
FUBhynLWcKzSt/Ac5IYp8M7vaGPQtSCKFWGafoaYtMnCdvvMujAWzKNhxnQT5Wvv
oxXqA/4Ti2Tk08HS6IT7SdEQTXlm66r99I0xHnAUrdzeZxNMgRVhvLfZkXdxGYFg
u/BYpbWcC/ePIlUnwEsBbTuZDdQdm2NnL9DuDcpmvJRPpq3t/O5jrFc/ZSXPsoaP
0Aj/uHYUbt7lJ+yreLVTubY/6CD50qi+YUbKh4yE8/nxoGibIh6BJpsQBJFxwAYf
3KDTuVan45gtf4Od34wrnDKOMpTwATwiKp9Dwi7DmDkHOHv8XgBCH/MyJnmDhPbl
8MFREsALHgQjDFSlTC9JxUrRtm5gDWv8a4uFJGS3iQ6rJUdbPM9+Sb3H6QrG2vd+
DhcI00iX0HGS8A85PjRqHH3Y8iKuu2n0M7SmSFXRDw4m6Oy2Cy2nhTXN/VnIn9HN
PlopNLk9hM6xZdRZkZFWdSHBd575euFgndOtBBj0fOtek49TSiIp+EgrPk2GrFt/
ywaZWWDYWGWVjUTR939+J399roD1B0y2PpxxVJkES/1Y+Zj0
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICTDCCAdGgAwIBAgIJAIF6LO+PI3pEMAoGCCqGSM49BAMDMFoxCzAJBgNVBAYT
AkpQMSYwJAYDVQQKEx1TRUNPTSBUcnVzdCBTeXN0ZW1zIENvLiwgTHRkLjEjMCEG
A1UEAxMaU0VDT00gVExTIEVDQyBSb290IENBIDIwMjQwHhcNMjQwMTMxMDU1MjM0
WhcNNDkwMTE0MDU1MjM0WjBaMQswCQYDVQQGEwJKUDEmMCQGA1UEChMdU0VDT00g
VHJ1c3QgU3lzdGVtcyBDby4sIEx0ZC4xIzAhBgNVBAMTGlNFQ09NIFRMUyBFQ0Mg
Um9vdCBDQSAyMDI0MHYwEAYHKoZIzj0CAQYFK4EEACIDYgAE7NzFMtu9dzQXSNC1
2fabk0+GlC5finB3R7XaZonRUd20aFiWObtuNBCLUZSfk6QXAE55BjEXsXQ/NG8y
UqicXjsu9ksDK3JZBgCwLOVh6+nwJXTvso/dEj/GUYH5mBdoo2MwYTAdBgNVHQ4E
FgQUO3YReyl04k4GTFaCQNAhL3qzydUwHwYDVR0jBBgwFoAUO3YReyl04k4GTFaC
QNAhL3qzydUwDgYDVR0PAQH/BAQDAgEGMA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZI
zj0EAwMDaQAwZgIxAN3ib8fi1pMYtAPjMilB5e5/H+t5CL0xPL+cZ5oTTZuSCjpA
n1v7F/VAr8bFxQXAowIxAKsBVO1ACFp7skwzPvdv1EUY5a897WGLT4lb+bjxFAWy
l8wDcZJdwGZ/pAHxt1AJ1g==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFmjCCA4KgAwIBAgIJAO6JNNDLgOCyMA0GCSqGSIb3DQEBDAUAMFoxCzAJBgNV
BAYTAkpQMSYwJAYDVQQKEx1TRUNPTSBUcnVzdCBTeXN0ZW1zIENvLiwgTHRkLjEj
MCEGA1UEAxMaU0VDT00gVExTIFJTQSBSb290IENBIDIwMjQwHhcNMjQwMTMxMDUx
MTU1WhcNNDkwMTE0MDUxMTU1WjBaMQswCQYDVQQGEwJKUDEmMCQGA1UEChMdU0VD
T00gVHJ1c3QgU3lzdGVtcyBDby4sIEx0ZC4xIzAhBgNVBAMTGlNFQ09NIFRMUyBS
U0EgUm9vdCBDQSAyMDI0MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
4TjizUwzxbInq8Tx11gaFYNk5fO+34y7TyM4neh0UgL5JIZbJNLTz2x//L/B71+5
m6X6nGIr7d4lFJBGtjO677hXOz93zkcWaUTm3VbOAjBlt4YWxlcccBHXuZ7o3Q+4
R+ormrBdHeJ1CTUEG8ttQbKIl3G7OZYbnH8/pP8cjPub/0kDVNuMzp7xsVRROOis
Qt53fMoJLlYgoebbuMphOqMCtjkJ7R6efEMfLp8UAVi9ZaLRn76ET/CJkk925ndu
uufC4BatS4mnXFmxN0vUXb0ij9B8O/D8gixQEsVSD4GK8FWRPh3bVd/6bzdkHGJj
y21XI0yejVomZUbRrOfNuz0boPGV1pt18fFC39IHQEth3OFqb5NDO3L+A9bNqTgA
yUgRmIn4ucgDc/Ri/Km3V51ueZjy1/yk0qwJVadAVVrCt56iNeXOyEvzJADGgDQ8
E1Pdaqct8Cynz/47ReQM62vFYO08wcQkrjmX/tesiko1V1yyaf6EfPzUFzmaGy9x
vkCwdbm15EdTolOjE0H2Vb5/APDOyCFEokiYGmXTLdAUl0wKZ4IyjkHGzy0jhpaX
EXE/GJcEvI6VzEchjaBL03EJ0h9pG4OqeIOycKvAo3A+TbetyfsrgYyHzU0a7/qU
jGat1AAq1nVljMpKqpinPTsf/d9H39FTUeJL7TpzzjUCAwEAAaNjMGEwHQYDVR0O
BBYEFCzrchKOWHdkNRVWNQFXB6l9DTbmMB8GA1UdIwQYMBaAFCzrchKOWHdkNRVW
NQFXB6l9DTbmMA4GA1UdDwEB/wQEAwIBBjAPBgNVHRMBAf8EBTADAQH/MA0GCSqG
SIb3DQEBDAUAA4ICAQAVwsvluSafaez5tFPR/hRTBzRxEyMMQF3XJXCVi3yegZyK
oec7hmE6jx2ZM8KgM1kn2yJRwFXHX8zUW9nBLEDWc4wuE8LrlZqhGZM9pJQXGmGz
ResDJV6JgRBna+j4sA1M7yIdlvL0sAfFXFCTRaWTD4E1V99RLrFzWfTcC+e180hD
uNMpqOEo46+lMeW/Wvh7ifOQs+kiK0O2gHxQDNxslSavnCs4V7l8HRDJ2La10o70
Bo7VLzf1W8MBvv0VTnxB+NjT5qTAbhGFh9Gvp4BaJpmdUf0C5CEP6dbQlfgxWfzY
r69yVT6dPQB+GFEaY03IMY+AcBCs+om1fNxrQXt9zoofMBNFbLhvpNH/JsXWdGUz
fNbO12uswTa5wah8LB18FTQN2/zPHYmvBEoLuyUgZ09VNLJo5YA0kXItVYkLjMe2
SixzK4scUHv81IK99I91DWx7FwMVKw2xgFp+ZLYB2dnpQQrqwlW64glHUcK2N9BD
snjLSxeZ+UPECh9RxH4WAcKiZW+cqaKMmhP2WBfR4IcR7NOL32ml11ds87hhV1CZ
WWFCJAcCidYZz6CZa8exzHojP9SB5RH0/v1KdHAisqhSjtJl/UIAHIQ48elOn8wr
TdFap4Yb5aHglmMeNx+fAIhDluWVfxTO7H4dTPU+SFVRMLAh+wwKZfqb94nMeQ==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIClDCCAhqgAwIBAgIILCmcWxbtBZUwCgYIKoZIzj0EAwIwfzELMAkGA1UEBhMC
VVMxDjAMBgNVBAgMBVRleGFzMRAwDgYDVQQHDAdIb3VzdG9uMRgwFgYDVQQKDA9T
U0wgQ29ycG9yYXRpb24xNDAyBgNVBAMMK1NTTC5jb20gRVYgUm9vdCBDZXJ0aWZp
Y2F0aW9uIEF1dGhvcml0eSBFQ0MwHhcNMTYwMjEyMTgxNTIzWhcNNDEwMjEyMTgx
NTIzWjB/MQswCQYDVQQGEwJVUzEOMAwGA1UECAwFVGV4YXMxEDAOBgNVBAcMB0hv
dXN0b24xGDAWBgNVBAoMD1NTTCBDb3Jwb3JhdGlvbjE0MDIGA1UEAwwrU1NMLmNv
bSBFViBSb290IENlcnRpZmljYXRpb24gQXV0aG9yaXR5IEVDQzB2MBAGByqGSM49
AgEGBSuBBAAiA2IABKoSR5CYG/vvw0AHgyBO8TCCogbR8pKGYfL2IWjKAMTH6kMA
VIbc/R/fALhBYlzccBYy3h+Z1MzFB8gIH2EWB1E9fVwHU+M1OIzfzZ/ZLg1Kthku
WnBaBu2+8KGwytAJKaNjMGEwHQYDVR0OBBYEFFvKXuXe0oGqzagtZFG22XKbl+ZP
MA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAUW8pe5d7SgarNqC1kUbbZcpuX
5k8wDgYDVR0PAQH/BAQDAgGGMAoGCCqGSM49BAMCA2gAMGUCMQCK5kCJN+vp1RPZ
ytRrJPOwPYdGWBrssd9v+1a6cGvHOMzosYxPD/fxZ3YOg9AeUY8CMD32IygmTMZg
h5Mmm7I1HrrW9zzRHM76JTymGoEVW/MSD2zuZYrJh6j5B+BimoxcSg==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIF6zCCA9OgAwIBAgIIVrYpzTS8ePYwDQYJKoZIhvcNAQELBQAwgYIxCzAJBgNV
BAYTAlVTMQ4wDAYDVQQIDAVUZXhhczEQMA4GA1UEBwwHSG91c3RvbjEYMBYGA1UE
CgwPU1NMIENvcnBvcmF0aW9uMTcwNQYDVQQDDC5TU0wuY29tIEVWIFJvb3QgQ2Vy
dGlmaWNhdGlvbiBBdXRob3JpdHkgUlNBIFIyMB4XDTE3MDUzMTE4MTQzN1oXDTQy
MDUzMDE4MTQzN1owgYIxCzAJBgNVBAYTAlVTMQ4wDAYDVQQIDAVUZXhhczEQMA4G
A1UEBwwHSG91c3RvbjEYMBYGA1UECgwPU1NMIENvcnBvcmF0aW9uMTcwNQYDVQQD
DC5TU0wuY29tIEVWIFJvb3QgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkgUlNBIFIy
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAjzZlQOHWTcDXtOlG2mvq
M0fNTPl9fb69LT3w23jhhqXZuglXaO1XPqDQCEGD5yhBJB/jchXQARr7XnAjssuf
OePPxU7Gkm0mxnu7s9onnQqG6YE3Bf7wcXHswxzpY6IXFJ3vG2fThVUCAtZJycxa
4bH3bzKfydQ7iEGonL3Lq9ttewkfokxykNorCPzPPFTOZw+oz12WGQvE43LrrdF9
HSfvkusQv1vrO6/PgN3B0pYEW3p+pKk8OHakYo6gOV7qd89dAFmPZiw+B6KjBSYR
aZfqhbcPlgtLyEDhULouisv3D5oi53+aNxPN8k0TayHRwMwi8qFG9kRpnMphNQcA
b9ZhCBHqurj26bNg5U257J8UZslXWNvNh2n4ioYSA0e/ZhN2rHd9NCSFg83XqpyQ
Gp8hLH94t2S42Oim9HizVcuE0jLEeK6jj2HdzghTreyI/BXkmg3mnxp3zkyPuBQV
PWKchjgGAGYS5Fl2WlPAApiiECtoRHuOec4zSnaqW4EWG7WK2NAAe15itAnWhmMO
pgWVSbooi4iTsjQc2KRVbrcc0N6ZVTsj9CLg+SlmJuwgUHfbSguPvuUCYHBBXtSu
UDkiFCbLsjtzdFVHB3mBOagwE0TlBIqulhMlQg+5U8Sb/M3kHN48+qvWBkofZ6aY
MBzdLNvcGJVXZsb/XItW9XcCAwEAAaNjMGEwDwYDVR0TAQH/BAUwAwEB/zAfBgNV
HSMEGDAWgBT5YLvU49U09rj1BoAlp3PbRmmonjAdBgNVHQ4EFgQU+WC71OPVNPa4
9QaAJadz20ZpqJ4wDgYDVR0PAQH/BAQDAgGGMA0GCSqGSIb3DQEBCwUAA4ICAQBW
s47LCp1Jjr+kxJG7ZhcFUZh1++VQLHqe8RT6q9OKPv+RKY9ji9i0qVQBDb6Thi/5
Sm3HXvVX+cpVHBK+Rw82xd9qt9t1wkclf7nxY/hoLVUE0fKNsKTPvDxeH3jnpaAg
cLAExbf3cqfeIg29MyVGjGSSJuM+LmOW2puMPfgYCdcDzH2GguDKBAdRUNf/ktUM
79qGn5nX67evaOI5JpS6aLe/g9Pqemc9YmeuJeVy6OLk7K4S9ksrPJ/psEDzOFSz
/bdoyNrGj1E8svuR3Bznm53htw1yj+KkxKl4+esUrMZDBcJlOSgYAsOCsp0FvmXt
ll9ldDz7CTUue5wT/RsPXcdtgTpWD8w74a8CLyKsRspGPKAcTNZEtF4uXBVmCeEm
Kf7GUmG6sXP/wwyc5WxqlD8UykAWlYTzWamsX0xhk23RO8yilQwipmdnRC652dKK
QbNmC1r7fSOl8hqw/96bg5Qu0T/fkreRrwU7ZcegbLHNYhLDkBvjJc40vG93drEQ
w/cFGsDWr3RiSBd3kmmQYRzelYB0VI8YHMPzA9C/pEN1hlMYegouCRw2n5H9gooi
S9EOUCXdywMMF8mDAAhONU2Ki+3wApRmLER/y5UnlhetCTCstnEXbosX9hwJ1C07
mKVx01QT2WDz9UtmT/rx7iASjbSsV7FFY6GsdqnC+w==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICjTCCAhSgAwIBAgIIdebfy8FoW6gwCgYIKoZIzj0EAwIwfDELMAkGA1UEBhMC
VVMxDjAMBgNVBAgMBVRleGFzMRAwDgYDVQQHDAdIb3VzdG9uMRgwFgYDVQQKDA9T
U0wgQ29ycG9yYXRpb24xMTAvBgNVBAMMKFNTTC5jb20gUm9vdCBDZXJ0aWZpY2F0
aW9uIEF1dGhvcml0eSBFQ0MwHhcNMTYwMjEyMTgxNDAzWhcNNDEwMjEyMTgxNDAz
WjB8MQswCQYDVQQGEwJVUzEOMAwGA1UECAwFVGV4YXMxEDAOBgNVBAcMB0hvdXN0
b24xGDAWBgNVBAoMD1NTTCBDb3Jwb3JhdGlvbjExMC8GA1UEAwwoU1NMLmNvbSBS
b290IENlcnRpZmljYXRpb24gQXV0aG9yaXR5IEVDQzB2MBAGByqGSM49AgEGBSuB
BAAiA2IABEVuqVDEpiM2nl8ojRfLliJkP9x6jh3MCLOicSS6jkm5BBtHllirLZXI
7Z4INcgn64mMU1jrYor+8FsPazFSY0E7ic3s7LaNGdM0B9y7xgZ/wkWV7Mt/qCPg
CemB+vNH06NjMGEwHQYDVR0OBBYEFILRhXMw5zUE044CkvvlpNHEIejNMA8GA1Ud
EwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAUgtGFczDnNQTTjgKS++Wk0cQh6M0wDgYD
VR0PAQH/BAQDAgGGMAoGCCqGSM49BAMCA2cAMGQCMG/n61kRpGDPYbCWe+0F+S8T
kdzt5fxQaxFGRrMcIQBiu77D5+jNB5n5DQtdcj7EqgIwH7y6C+IwJPt8bYBVCpk+
gA0z5Wajs6O7pdWLjwkspl1+4vAHCGht0nxpbl/f5Wpl
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIF3TCCA8WgAwIBAgIIeyyb0xaAMpkwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UE
BhMCVVMxDjAMBgNVBAgMBVRleGFzMRAwDgYDVQQHDAdIb3VzdG9uMRgwFgYDVQQK
DA9TU0wgQ29ycG9yYXRpb24xMTAvBgNVBAMMKFNTTC5jb20gUm9vdCBDZXJ0aWZp
Y2F0aW9uIEF1dGhvcml0eSBSU0EwHhcNMTYwMjEyMTczOTM5WhcNNDEwMjEyMTcz
OTM5WjB8MQswCQYDVQQGEwJVUzEOMAwGA1UECAwFVGV4YXMxEDAOBgNVBAcMB0hv
dXN0b24xGDAWBgNVBAoMD1NTTCBDb3Jwb3JhdGlvbjExMC8GA1UEAwwoU1NMLmNv
bSBSb290IENlcnRpZmljYXRpb24gQXV0aG9yaXR5IFJTQTCCAiIwDQYJKoZIhvcN
AQEBBQADggIPADCCAgoCggIBAPkP3aMrfcvQKv7sZ4Wm5y4bunfh4/WvpOz6Sl2R
xFdHaxh3a3by/ZPkPQ/CFp4LZsNWlJ4Xg4XOVu/yFv0AYvUiCVToZRdOQbngT0aX
qhvIuG5iXmmxX9sqAn78bMrzQdjt0Oj8P2FI7bADFB0QDksZ4LtO7IZl/zbzXmcC
C52GVWH9ejjt/uIZALdvoVBidXQ8oPrIJZK0bnoix/geoeOy3ZExqysdBP+lSgQ3
6YWkMyv94tZVNHwZpEpox7Ko07fKoZOI68GXvIz5HdkihCR0xwQ9aqkpk8zruFvh
/l8lqjRYyMEjVJ0bmBHDOJx+PYZspQ9AhnwC9FwCTyjLrnGfDzrIM/4RJTXq/LrF
YD3ZfBjVsqnTdXgDciLKOsMf7yzlLqn6niy2UUb9rwPW6mBo6oUWNmuF6R7As93E
JNyAKoFBbZQ+yODJgUEAnl6/f8UImKIYLEJAs/lvOCdLToD0PYFH4Ih86hzOtXVc
US4cK38acijnALXRdMbX5J+tB5O2UzU1/Dfkw/ZdFr4hc96SCvigY2q8lpJqPvi8
ZVWb3vUNiSYE/CUapiVpy8JtynziWV+XrOvvLsi81xtZPCvM8hnIk2snYxnP/Okm
+Mpxm3+T/jRnhE6Z6/yzeAkzcLpmpnbtG3PrGqUNxCITIJRWCk4sbE6x/c+cCbqi
M+2HAgMBAAGjYzBhMB0GA1UdDgQWBBTdBAkHovV6fVJTEpKV7jiAJQ2mWTAPBgNV
HRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFN0ECQei9Xp9UlMSkpXuOIAlDaZZMA4G
A1UdDwEB/wQEAwIBhjANBgkqhkiG9w0BAQsFAAOCAgEAIBgRlCn7Jp0cHh5wYfGV
cpNxJK1ok1iOMq8bs3AD/CUrdIWQPXhq9LmLpZc7tRiRux6n+UBbkflVma8eEdBc
Hadm47GUBwwyOabqG7B52B2ccETjit3E+ZUfijhDPwGFpUenPUayvOUiaPd7nNgs
PgohyC0zrL/FgZkxdMF1ccW+sfAjRfSda/wZY52jvATGGAslu1OJD7OAUN5F7kR/
q5R4ZJjT9ijdh9hwZXT7DrkT66cPYakylszeu+1jTBi7qUD3oFRuIIhxdRjqerQ0
cuAjJ3dctpDqhiVAq+8zD8ufgr6iIPv2tS0a5sKFsXQP+8hlAqRSAUfdSSLBv9jr
a6x+3uxjMxW3IwiPxg+NQVrdjsW5j+VFP3jbutIbQLH+cU0/4IGiul607BXgk90I
H37hVZkLId6Tngr75qNJvTYw/ud3sqB1l7UtgYgXZSD32pAAn8lSzDLKNXz1PQ/Y
K9f1JmzJBjSWFupwWRoyeXkLtoh/D1JIPb9s2KJELtFOt3JY04kTlf5Eq/jXixtu
nLwsoFvVagCvXzfh1foQC5ichucmj87w7G6KVwuA406ywKBjYZC6VWg3dGq2ktuf
oYYitmUnDuy2n0Jg5GfCtdpBC8TTi2EbvPofkSvXRAdeuims2cXp71NIWuuA8ShY
Ic2wBlX7Jz9TkHCpBB5XJ7k=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICOjCCAcCgAwIBAgIQFAP1q/s3ixdAW+JDsqXRxDAKBggqhkjOPQQDAzBOMQsw
CQYDVQQGEwJVUzEYMBYGA1UECgwPU1NMIENvcnBvcmF0aW9uMSUwIwYDVQQDDBxT
U0wuY29tIFRMUyBFQ0MgUm9vdCBDQSAyMDIyMB4XDTIyMDgyNTE2MzM0OFoXDTQ2
MDgxOTE2MzM0N1owTjELMAkGA1UEBhMCVVMxGDAWBgNVBAoMD1NTTCBDb3Jwb3Jh
dGlvbjElMCMGA1UEAwwcU1NMLmNvbSBUTFMgRUNDIFJvb3QgQ0EgMjAyMjB2MBAG
ByqGSM49AgEGBSuBBAAiA2IABEUpNXP6wrgjzhR9qLFNoFs27iosU8NgCTWyJGYm
acCzldZdkkAZDsalE3D07xJRKF3nzL35PIXBz5SQySvOkkJYWWf9lCcQZIxPBLFN
SeR7T5v15wj4A4j3p8OSSxlUgaNjMGEwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSME
GDAWgBSJjy+j6CugFFR781a4Jl9nOAuc0DAdBgNVHQ4EFgQUiY8vo+groBRUe/NW
uCZfZzgLnNAwDgYDVR0PAQH/BAQDAgGGMAoGCCqGSM49BAMDA2gAMGUCMFXjIlbp
15IkWE8elDIPDAI2wv2sdDJO4fscgIijzPvX6yv/N33w7deedWo1dlJF4AIxAMeN
b0Igj762TVntd00pxCAgRWSGOlDGxK0tk/UYfXLtqc/ErFc2KAhl3zx5Zn6g6g==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFiTCCA3GgAwIBAgIQb77arXO9CEDii02+1PdbkTANBgkqhkiG9w0BAQsFADBO
MQswCQYDVQQGEwJVUzEYMBYGA1UECgwPU1NMIENvcnBvcmF0aW9uMSUwIwYDVQQD
DBxTU0wuY29tIFRMUyBSU0EgUm9vdCBDQSAyMDIyMB4XDTIyMDgyNTE2MzQyMloX
DTQ2MDgxOTE2MzQyMVowTjELMAkGA1UEBhMCVVMxGDAWBgNVBAoMD1NTTCBDb3Jw
b3JhdGlvbjElMCMGA1UEAwwcU1NMLmNvbSBUTFMgUlNBIFJvb3QgQ0EgMjAyMjCC
AiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANCkCXJPQIgSYT41I57u9nTP
L3tYPc48DRAokC+X94xI2KDYJbFMsBFMF3NQ0CJKY7uB0ylu1bUJPiYYf7ISf5OY
t6/wNr/y7hienDtSxUcZXXTzZGbVXcdotL8bHAajvI9AI7YexoS9UcQbOcGV0ins
S657Lb85/bRi3pZ7QcacoOAGcvvwB5cJOYF0r/c0WRFXCsJbwST0MXMwgsadugL3
PnxEX4MN8/HdIGkWCVDi1FW24IBydm5MR7d1VVm0U3TZlMZBrViKMWYPHqIbKUBO
L9975hYsLfy/7PO0+r4Y9ptJ1O4Fbtk085zx7AGL0SDGD6C1vBdOSHtRwvzpXGk3
R2azaPgVKPC506QVzFpPulJwoxJF3ca6TvvC0PeoUidtbnm1jPx7jMEWTO6Af77w
dr5BUxIzrlo4QqvXDz5BjXYHMtWrifZOZ9mxQnUjbvPNQrL8VfVThxc7wDNY8VLS
+YCk8OjwO4s4zKTGkH8PnP2L0aPP2oOnaclQNtVcBdIKQXTbYxE3waWglksejBYS
d66UNHsef8JmAOSqg+qKkK3ONkRN0VHpvB/zagX9wHQfJRlAUW7qglFA35u5CCoG
AtUjHBPW6dvbxrB6y3snm/vg1UYk7RBLY0ulBY+6uB0rpvqR4pJSvezrZ5dtmi2f
gTIFZzL7SAg/2SW4BCUvAgMBAAGjYzBhMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0j
BBgwFoAU+y437uOEeicuzRk1sTN8/9REQrkwHQYDVR0OBBYEFPsuN+7jhHonLs0Z
NbEzfP/UREK5MA4GA1UdDwEB/wQEAwIBhjANBgkqhkiG9w0BAQsFAAOCAgEAjYlt
hEUY8U+zoO9opMAdrDC8Z2awms22qyIZZtM7QbUQnRC6cm4pJCAcAZli05bg4vsM
QtfhWsSWTVTNj8pDU/0quOr4ZcoBwq1gaAafORpR2eCNJvkLTqVTJXojpBzOCBvf
R4iyrT7gJ4eLSYwfqUdYe5byiB0YrrPRpgqU+tvT5TgKa3kSM/tKWTcWQA673vWJ
DPFs0/dRa1419dvAJuoSc06pkZCmF8NsLzjUo3KUQyxi4U5cMj29TH0ZR6LDSeeW
P4+a0zvkEdiLA9z2tmBVGKaBUfPhqBVq6+AL8BQx1rmMRTqoENjwuSfr98t67wVy
lrXEj5ZzxOhWc5y8aVFjvO9nHEMaX3cZHxj4HCUp+UmZKbaSPaKDN7EgkaibMOlq
bLQjk2UEqxHzDh1TJElTHaE/nUiSEeJ9DU/1172iWD54nR4fK/4huxoTtrEoZP2w
AgDHbICivRZQIA9ygV/MlP+7mea6kMvq+cYMwq7FGc4zoWtcu358NFcXrfA/rs3q
r5nsLFR+jM4uElZI7xc7P0peYNLcdDa8pUNjyw9bowJWCZ4kLOGGgYz+qxcs+sji
Mho6/4UIyYOf8kpIEFR3N+2ivEC+5BB09+Rbu7nzifmPQdjH5FCQNYA+HLhNkNPU
98OwoX6EyneSMSy4kLGCenROmxMmtNVQZlR4rmA=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIDcjCCAlqgAwIBAgIUPopdB+xV0jLVt+O2XwHrLdzk1uQwDQYJKoZIhvcNAQEL
BQAwUTELMAkGA1UEBhMCUEwxKDAmBgNVBAoMH0tyYWpvd2EgSXpiYSBSb3psaWN6
ZW5pb3dhIFMuQS4xGDAWBgNVBAMMD1NaQUZJUiBST09UIENBMjAeFw0xNTEwMTkw
NzQzMzBaFw0zNTEwMTkwNzQzMzBaMFExCzAJBgNVBAYTAlBMMSgwJgYDVQQKDB9L
cmFqb3dhIEl6YmEgUm96bGljemVuaW93YSBTLkEuMRgwFgYDVQQDDA9TWkFGSVIg
Uk9PVCBDQTIwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC3vD5QqEvN
QLXOYeeWyrSh2gwisPq1e3YAd4wLz32ohswmUeQgPYUM1ljj5/QqGJ3a0a4m7utT
3PSQ1hNKDJA8w/Ta0o4NkjrcsbH/ON7Dui1fgLkCvUqdGw+0w8LBZwPd3BucPbOw
3gAeqDRHu5rr/gsUvTaE2g0gv/pby6kWIK05YO4vdbbnl5z5Pv1+TW9NL++IDWr6
3fE9biCloBK0TXC5ztdyO4mTp4CEHCdJckm1/zuVnsHMyAHs6A6KCpbns6aH5db5
BSsNl0BwPLqsdVqc1U2dAgrSS5tmS0YHF2Wtn2yIANwiieDhZNRnvDF5YTy7ykHN
XGoAyDw4jlivAgMBAAGjQjBAMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQD
AgEGMB0GA1UdDgQWBBQuFqlKGLXLzPVvUPMjX/hd56zwyDANBgkqhkiG9w0BAQsF
AAOCAQEAtXP4A9xZWx126aMqe5Aosk3AM0+qmrHUuOQn/6mWmc5G4G18TKI4pAZw
8PRBEew/R40/cof5O/2kbytTAOD/OblqBw7rHRz2onKQy4I9EYKL0rufKq8h5mOG
nXkZ7/e7DDWQw4rtTw/1zBLZpD67oPwglV9PJi8RI4NOdQcPv5vRtB3pEAT+ymCP
oky4rc/hkA/NrgrHXXu3UNLUYfrVFdvXn4dRVOul4+vJhaAlIDf7js4MNIThPIGy
d05DpYhfhmehPea0XGG2Ptv+tyjFogeutcrKjSoS75ftwjCkySp6+/NNIxuZMzSg
LvWpCz/UXeHPhJ/iGcJfitYgHuNztw==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICOjCCAcGgAwIBAgIQQvLM2htpN0RfFf51KBC49DAKBggqhkjOPQQDAzBfMQsw
CQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMTYwNAYDVQQDEy1T
ZWN0aWdvIFB1YmxpYyBTZXJ2ZXIgQXV0aGVudGljYXRpb24gUm9vdCBFNDYwHhcN
MjEwMzIyMDAwMDAwWhcNNDYwMzIxMjM1OTU5WjBfMQswCQYDVQQGEwJHQjEYMBYG
A1UEChMPU2VjdGlnbyBMaW1pdGVkMTYwNAYDVQQDEy1TZWN0aWdvIFB1YmxpYyBT
ZXJ2ZXIgQXV0aGVudGljYXRpb24gUm9vdCBFNDYwdjAQBgcqhkjOPQIBBgUrgQQA
IgNiAAR2+pmpbiDt+dd34wc7qNs9Xzjoq1WmVk/WSOrsfy2qw7LFeeyZYX8QeccC
WvkEN/U0NSt3zn8gj1KjAIns1aeibVvjS5KToID1AZTc8GgHHs3u/iVStSBDHBv+
6xnOQ6OjQjBAMB0GA1UdDgQWBBTRItpMWfFLXyY4qp3W7usNw/upYTAOBgNVHQ8B
Af8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAwNnADBkAjAn7qRa
qCG76UeXlImldCBteU/IvZNeWBj7LRoAasm4PdCkT0RHlAFWovgzJQxC36oCMB3q
4S6ILuH5px0CMk7yn2xVdOOurvulGu7t0vzCAxHrRVxgED1cf5kDW21USAGKcw==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFijCCA3KgAwIBAgIQdY39i658BwD6qSWn4cetFDANBgkqhkiG9w0BAQwFADBf
MQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMTYwNAYDVQQD
Ey1TZWN0aWdvIFB1YmxpYyBTZXJ2ZXIgQXV0aGVudGljYXRpb24gUm9vdCBSNDYw
HhcNMjEwMzIyMDAwMDAwWhcNNDYwMzIxMjM1OTU5WjBfMQswCQYDVQQGEwJHQjEY
MBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMTYwNAYDVQQDEy1TZWN0aWdvIFB1Ymxp
YyBTZXJ2ZXIgQXV0aGVudGljYXRpb24gUm9vdCBSNDYwggIiMA0GCSqGSIb3DQEB
AQUAA4ICDwAwggIKAoICAQCTvtU2UnXYASOgHEdCSe5jtrch/cSV1UgrJnwUUxDa
ef0rty2k1Cz66jLdScK5vQ9IPXtamFSvnl0xdE8H/FAh3aTPaE8bEmNtJZlMKpnz
SDBh+oF8HqcIStw+KxwfGExxqjWMrfhu6DtK2eWUAtaJhBOqbchPM8xQljeSM9xf
iOefVNlI8JhD1mb9nxc4Q8UBUQvX4yMPFF1bFOdLvt30yNoDN9HWOaEhUTCDsG3X
ME6WW5HwcCSrv0WBZEMNvSE6Lzzpng3LILVCJ8zab5vuZDCQOc2TZYEhMbUjUDM3
IuM47fgxMMxF/mL50V0yeUKH32rMVhlATc6qu/m1dkmU8Sf4kaWD5QazYw6A3OAS
VYCmO2a0OYctyPDQ0RTp5A1NDvZdV3LFOxxHVp3i1fuBYYzMTYCQNFu31xR13NgE
SJ/AwSiItOkcyqex8Va3e0lMWeUgFaiEAin6OJRpmkkGj80feRQXEgyDet4fsZfu
+Zd4KKTIRJLpfSYFplhym3kT2BFfrsU4YjRosoYwjviQYZ4ybPUHNs2iTG7sijbt
8uaZFURww3y8nDnAtOFr94MlI1fZEoDlSfB1D++N6xybVCi0ITz8fAr/73trdf+L
HaAZBav6+CuBQug4urv7qv094PPK306Xlynt8xhW6aWWrL3DkJiy4Pmi1KZHQ3xt
zwIDAQABo0IwQDAdBgNVHQ4EFgQUVnNYZJX5khqwEioEYnmhQBWIIUkwDgYDVR0P
AQH/BAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQEMBQADggIBAC9c
mTz8Bl6MlC5w6tIyMY208FHVvArzZJ8HXtXBc2hkeqK5Duj5XYUtqDdFqij0lgVQ
YKlJfp/imTYpE0RHap1VIDzYm/EDMrraQKFz6oOht0SmDpkBm+S8f74TlH7Kph52
gDY9hAaLMyZlbcp+nv4fjFg4exqDsQ+8FxG75gbMY/qB8oFM2gsQa6H61SilzwZA
Fv97fRheORKkU55+MkIQpiGRqRxOF3yEvJ+M0ejf5lG5Nkc/kLnHvALcWxxPDkjB
JYOcCj+esQMzEhonrPcibCTRAUH4WAP+JWgiH5paPHxsnnVI84HxZmduTILA7rpX
DhjvLpr3Etiga+kFpaHpaPi8TD8SHkXoUsCjvxInebnMMTzD9joiFgOgyY9mpFui
TdaBJQbpdqQACj7LzTWb4OE4y2BThihCQRxEV+ioratF4yUQvNs+ZUH7G6aXD+u5
dHn5HrwdVw1Hr8Mvn4dGp+smWg9WY7ViYG4A++MnESLn/pmPNPW56MORcr3Ywx65
LvKRRFHQV80MNNVIIb/bE/FmJUNS0nAiNs2fxBx1IK1jcmMGDw4nztJqDby1ORrp
0XZ60Vzk50lJLVU3aPAaOpg+VBeHVOmmJ1CJeyAvP/+/oYtKR5j/K3tJPsMpRmAY
QqszKbrAKbkTidOIijlBO8n9pu0f9GBj39ItVQGL
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFcjCCA1qgAwIBAgIUZNtaDCBO6Ncpd8hQJ6JaJ90t8sswDQYJKoZIhvcNAQEM
BQAwUTELMAkGA1UEBhMCSlAxIzAhBgNVBAoTGkN5YmVydHJ1c3QgSmFwYW4gQ28u
LCBMdGQuMR0wGwYDVQQDExRTZWN1cmVTaWduIFJvb3QgQ0ExNDAeFw0yMDA0MDgw
NzA2MTlaFw00NTA0MDgwNzA2MTlaMFExCzAJBgNVBAYTAkpQMSMwIQYDVQQKExpD
eWJlcnRydXN0IEphcGFuIENvLiwgTHRkLjEdMBsGA1UEAxMUU2VjdXJlU2lnbiBS
b290IENBMTQwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDF0nqh1oq/
FjHQmNE6lPxauG4iwWL3pwon71D2LrGeaBLwbCRjOfHw3xDG3rdSINVSW0KZnvOg
vlIfX8xnbacuUKLBl422+JX1sLrcneC+y9/3OPJH9aaakpUqYllQC6KxNedlsmGy
6pJxaeQp8E+BgQQ8sqVb1MWoWWd7VRxJq3qdwudzTe/NCcLEVxLbAQ4jeQkHO6Lo
/IrPj8BGJJw4J+CDnRugv3gVEOuGTgpa/d/aLIJ+7sr2KeH6caH3iGicnPCNvg9J
kdjqOvn90Ghx2+m1K06Ckm9mH+Dw3EzsytHqunQG+bOEkJTRX45zGRBdAuVwpcAQ
0BB8b8VYSbSwbprafZX1zNoCr7gsfXmPvkPx+SgojQlD+Ajda8iLLCSxjVIHvXib
y8posqTdDEx5YMaZ0ZPxMBoH064iwurO8YQJzOAUbn8/ftKChazcqRZOhaBgy/ac
18izju3Gm5h1DVXoX+WViwKkrkMpKBGk5hIwAUt1ax5mnXkvpXYvHUC0bcl9eQjs
0Wq2XSqypWa9a4X0dFbD9ed1Uigspf9mR6XU/v6eVL9lfgHWMI+lNpyiUBzuOIAB
SMbHdPTGrMNASRZhdCyvjG817XsYAFs2PJxQDcqSMxDxJklt33UkN4Ii1+iW/RVL
ApY+B3KVfqs9TC7XyvDf4Fg/LS8EmjijAQIDAQABo0IwQDAPBgNVHRMBAf8EBTAD
AQH/MA4GA1UdDwEB/wQEAwIBBjAdBgNVHQ4EFgQUBpOjCl4oaTeqYR3r6/wtbyPk
86AwDQYJKoZIhvcNAQEMBQADggIBAJaAcgkGfpzMkwQWu6A6jZJOtxEaCnFxEM0E
rX+lRVAQZk5KQaID2RFPeje5S+LGjzJmdSX7684/AykmjbgWHfYfM25I5uj4V7Ib
ed87hwriZLoAymzvftAj63iP/2SbNDefNWWipAA9EiOWWF3KY4fGoweITedpdopT
zfFP7ELyk+OZpDc8h7hi2/DsHzc/N19DzFGdtfCXwreFamgLRB7lUe6TzktuhsHS
DCRZNhqfLJGP4xjblJUK7ZGqDpncllPjYYPGFrojutzdfhrGe0K22VoF3Jpf1d+4
2kd92jjbrDnVHmtsKheMYc2xbXIBw8MgAGJoFjHVdqqGuw6qnsb58Nn4DSEC5MUo
FlkRudlpcyqSeLiSV5sI8jrlL5WwWLdrIBRtFO8KvH7YVdiI2i/6GaX7i+B/OfVy
K4XELKzvGUWSTLNhB9xNH27SgRNcmvMSZ4PPmz+Ln52kuaiWA3rF7iDeM9ovnhp6
dB7h7sxaOgTdsxoEqBRjrLdHEoOabPXm6RUVkRqEGQ6UROcSjiVbgGcZ3GOTEAtl
Lor6CZpO2oYofaphNdgOpygau1LgePhsumywbrmHXumZNTfxPWQrqaA0k89jL9WB
365jJ6UeTo3cKXhZ+PmhIIynJkBugnLNeLLIjzwec+fBH7/PzqUqm9tEZDKgu39c
JRNItX+S
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICIzCCAamgAwIBAgIUFhXHw9hJp75pDIqI7fBw+d23PocwCgYIKoZIzj0EAwMw
UTELMAkGA1UEBhMCSlAxIzAhBgNVBAoTGkN5YmVydHJ1c3QgSmFwYW4gQ28uLCBM
dGQuMR0wGwYDVQQDExRTZWN1cmVTaWduIFJvb3QgQ0ExNTAeFw0yMDA0MDgwODMy
NTZaFw00NTA0MDgwODMyNTZaMFExCzAJBgNVBAYTAkpQMSMwIQYDVQQKExpDeWJl
cnRydXN0IEphcGFuIENvLiwgTHRkLjEdMBsGA1UEAxMUU2VjdXJlU2lnbiBSb290
IENBMTUwdjAQBgcqhkjOPQIBBgUrgQQAIgNiAAQLUHSNZDKZmbPSYAi4Io5GdCx4
wCtELW1fHcmuS1Iggz24FG1Th2CeX2yF2wYUleDHKP+dX+Sq8bOLbe1PL0vJSpSR
ZHX+AezB2Ot6lHhWGENfa4HL9rzatAy2KZMIaY+jQjBAMA8GA1UdEwEB/wQFMAMB
Af8wDgYDVR0PAQH/BAQDAgEGMB0GA1UdDgQWBBTrQciu/NWeUUj1vYv0hyCTQSvT
9DAKBggqhkjOPQQDAwNoADBlAjEA2S6Jfl5OpBEHvVnCB96rMjhTKkZEBhd6zlHp
4P9mLQlO4E/0BdGF9jVg3PVys0Z9AjBEmEYagoUeYWmJSwdLZrWeqrqgHkHZAXQ6
bkU6iYAZezKYVWOr62Nuk22rGwlgMU4=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICODCCAb6gAwIBAgIJANZdm7N4gS7rMAoGCCqGSM49BAMDMGExCzAJBgNVBAYT
AkpQMSUwIwYDVQQKExxTRUNPTSBUcnVzdCBTeXN0ZW1zIENPLixMVEQuMSswKQYD
VQQDEyJTZWN1cml0eSBDb21tdW5pY2F0aW9uIEVDQyBSb290Q0ExMB4XDTE2MDYx
NjA1MTUyOFoXDTM4MDExODA1MTUyOFowYTELMAkGA1UEBhMCSlAxJTAjBgNVBAoT
HFNFQ09NIFRydXN0IFN5c3RlbXMgQ08uLExURC4xKzApBgNVBAMTIlNlY3VyaXR5
IENvbW11bmljYXRpb24gRUNDIFJvb3RDQTEwdjAQBgcqhkjOPQIBBgUrgQQAIgNi
AASkpW9gAwPDvTH00xecK4R1rOX9PVdu12O/5gSJko6BnOPpR27KkBLIE+Cnnfdl
dB9sELLo5OnvbYUymUSxXv3MdhDYW72ixvnWQuRXdtyQwjWpS4g8EkdtXP9JTxpK
ULGjQjBAMB0GA1UdDgQWBBSGHOf+LaVKiwj+KBH6vqNm+GBZLzAOBgNVHQ8BAf8E
BAMCAQYwDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAwNoADBlAjAVXUI9/Lbu
9zuxNuie9sRGKEkz0FhDKmMpzE2xtHqiuQ04pV1IKv3LsnNdo4gIxwwCMQDAqy0O
be0YottT6SXbVQjgUMzfRGEWgqtJsLKB7HOHeLRMsmIbEvoWTSVLY70eN9k=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIDdzCCAl+gAwIBAgIBADANBgkqhkiG9w0BAQsFADBdMQswCQYDVQQGEwJKUDEl
MCMGA1UEChMcU0VDT00gVHJ1c3QgU3lzdGVtcyBDTy4sTFRELjEnMCUGA1UECxMe
U2VjdXJpdHkgQ29tbXVuaWNhdGlvbiBSb290Q0EyMB4XDTA5MDUyOTA1MDAzOVoX
DTI5MDUyOTA1MDAzOVowXTELMAkGA1UEBhMCSlAxJTAjBgNVBAoTHFNFQ09NIFRy
dXN0IFN5c3RlbXMgQ08uLExURC4xJzAlBgNVBAsTHlNlY3VyaXR5IENvbW11bmlj
YXRpb24gUm9vdENBMjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBANAV
OVKxUrO6xVmCxF1SrjpDZYBLx/KWvNs2l9amZIyoXvDjChz335c9S672XewhtUGr
zbl+dp+++T42NKA7wfYxEUV0kz1XgMX5iZnK5atq1LXaQZAQwdbWQonCv/Q4EpVM
VAX3NuRFg3sUZdbcDE3R3n4MqzvEFb46VqZab3ZpUql6ucjrappdUtAtCms1FgkQ
hNBqyjoGADdH5H5XTz+L62e4iKrFvlNVspHEfbmwhRkGeC7bYRr6hfVKkaHnFtWO
ojnflLhwHyg/i/xAXmODPIMqGplrz95Zajv8bxbXH/1KEOtOghY6rCcMU/Gt1SSw
awNQwS08Ft1ENCcadfsCAwEAAaNCMEAwHQYDVR0OBBYEFAqFqXdlBZh8QIH4D5cs
OPEK7DzPMA4GA1UdDwEB/wQEAwIBBjAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3
DQEBCwUAA4IBAQBMOqNErLlFsceTfsgLCkLfZOoc7llsCLqJX2rKSpWeeo8HxdpF
coJxDjrSzG+ntKEju/Ykn8sX/oymzsLS28yN/HH8AynBbF0zX2S2ZTuJbxh2ePXc
okgfGT+Ok+vx+hfuzU7jBBJV1uXk3fs+BXziHV7Gp7yXT2g69ekuCkO2r1dcYmh8
t/2jioSgrGK+KwmHNPBqAbubKVY8/gA3zyNs8U6qtnRGEmyR7jTV7JqR50S+kDFy
1UkC9gLl9B/rfNmWVan/7Ir5mUf/NVoCqgTLiluHcSmRvaS0eg29mvVXIwAHIRc/
SjnRBUkLp7Y3gaVdjKozXoEofKd9J+sAro03
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIID3TCCAsWgAwIBAgIBADANBgkqhkiG9w0BAQsFADCBjzELMAkGA1UEBhMCVVMx
EDAOBgNVBAgTB0FyaXpvbmExEzARBgNVBAcTClNjb3R0c2RhbGUxJTAjBgNVBAoT
HFN0YXJmaWVsZCBUZWNobm9sb2dpZXMsIEluYy4xMjAwBgNVBAMTKVN0YXJmaWVs
ZCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAtIEcyMB4XDTA5MDkwMTAwMDAw
MFoXDTM3MTIzMTIzNTk1OVowgY8xCzAJBgNVBAYTAlVTMRAwDgYDVQQIEwdBcml6
b25hMRMwEQYDVQQHEwpTY290dHNkYWxlMSUwIwYDVQQKExxTdGFyZmllbGQgVGVj
aG5vbG9naWVzLCBJbmMuMTIwMAYDVQQDEylTdGFyZmllbGQgUm9vdCBDZXJ0aWZp
Y2F0ZSBBdXRob3JpdHkgLSBHMjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoC
ggEBAL3twQP89o/8ArFvW59I2Z154qK3A2FWGMNHttfKPTUuiUP3oWmb3ooa/RMg
nLRJdzIpVv257IzdIvpy3Cdhl+72WoTsbhm5iSzchFvVdPtrX8WJpRBSiUZV9Lh1
HOZ/5FSuS/hVclcCGfgXcVnrHigHdMWdSL5stPSksPNkN3mSwOxGXn/hbVNMYq/N
Hwtjuzqd+/x5AJhhdM8mgkBj87JyahkNmcrUDnXMN/uLicFZ8WJ/X7NfZTD4p7dN
dloedl40wOiWVpmKs/B/pM293DIxfJHP4F8R+GuqSVzRmZTRouNjWwl2tVZi4Ut0
HZbUJtQIBFnQmA4O5t78w+wfkPECAwEAAaNCMEAwDwYDVR0TAQH/BAUwAwEB/zAO
BgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYEFHwMMh+n2TB/xH1oo2Kooc6rB1snMA0G
CSqGSIb3DQEBCwUAA4IBAQARWfolTwNvlJk7mh+ChTnUdgWUXuEok21iXQnCoKjU
sHU48TRqneSfioYmUeYs0cYtbpUgSpIB7LiKZ3sx4mcujJUDJi5DnUox9g61DLu3
4jd/IroAow57UvtruzvE03lRTs2Q9GcHGcg8RnoNAX3FWOdt5oUwF5okxBDgBPfg
8n/Uqgr/Qh037ZTlZFkSIHc40zI+OIF1lnP6aI+xy84fxez6nH7PfrHxBy22/L/K
pL/QlwVKvOoYKAKQvVR4CSFx09F9HdkWsKlhPdAKACL8x3vLCWRFCztAgfd9fDL1
mMpYjn0q7pBZc2T5NnReJaH1ZgUufzkVqSr7UIuOhWn0
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIID7zCCAtegAwIBAgIBADANBgkqhkiG9w0BAQsFADCBmDELMAkGA1UEBhMCVVMx
EDAOBgNVBAgTB0FyaXpvbmExEzARBgNVBAcTClNjb3R0c2RhbGUxJTAjBgNVBAoT
HFN0YXJmaWVsZCBUZWNobm9sb2dpZXMsIEluYy4xOzA5BgNVBAMTMlN0YXJmaWVs
ZCBTZXJ2aWNlcyBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAtIEcyMB4XDTA5
MDkwMTAwMDAwMFoXDTM3MTIzMTIzNTk1OVowgZgxCzAJBgNVBAYTAlVTMRAwDgYD
VQQIEwdBcml6b25hMRMwEQYDVQQHEwpTY290dHNkYWxlMSUwIwYDVQQKExxTdGFy
ZmllbGQgVGVjaG5vbG9naWVzLCBJbmMuMTswOQYDVQQDEzJTdGFyZmllbGQgU2Vy
dmljZXMgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgLSBHMjCCASIwDQYJKoZI
hvcNAQEBBQADggEPADCCAQoCggEBANUMOsQq+U7i9b4Zl1+OiFOxHz/Lz58gE20p
OsgPfTz3a3Y4Y9k2YKibXlwAgLIvWX/2h/klQ4bnaRtSmpDhcePYLQ1Ob/bISdm2
8xpWriu2dBTrz/sm4xq6HZYuajtYlIlHVv8loJNwU4PahHQUw2eeBGg6345AWh1K
Ts9DkTvnVtYAcMtS7nt9rjrnvDH5RfbCYM8TWQIrgMw0R9+53pBlbQLPLJGmpufe
hRhJfGZOozptqbXuNC66DQO4M99H67FrjSXZm86B0UVGMpZwh94CDklDhbZsc7tk
6mFBrMnUVN+HL8cisibMn1lUaJ/8viovxFUcdUBgF4UCVTmLfwUCAwEAAaNCMEAw
DwYDVR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYEFJxfAN+q
AdcwKziIorhtSpzyEZGDMA0GCSqGSIb3DQEBCwUAA4IBAQBLNqaEd2ndOxmfZyMI
bw5hyf2E3F/YNoHN2BtBLZ9g3ccaaNnRbobhiCPPE95Dz+I0swSdHynVv/heyNXB
ve6SbzJ08pGCL72CQnqtKrcgfU28elUSwhXqvfdqlS5sdJ/PHLTyxQGjhdByPq1z
qwubdQxtRbeOlKyWN7Wg0I8VRw7j6IPdj/3vQQF3zCepYoUz8jcI73HPdwbeyBkd
iEDPfUYd/x7H4c7/I9vG+o1VTqkC50cRRj70/b17KSa7qWFiNyi2LSr2EIZkyXCn
0q23KXB56jzaYyWf/Wi3MOxw+3WKt21gZ7IeyLnp2KhvAotnDU0mV3HaIPzBSlCN
sSi6
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFkzCCA3ugAwIBAgIUQ/oMX04bgBhE79G0TzUfRPSA7cswDQYJKoZIhvcNAQEL
BQAwUTELMAkGA1UEBhMCQ0gxFTATBgNVBAoTDFN3aXNzU2lnbiBBRzErMCkGA1UE
AxMiU3dpc3NTaWduIFJTQSBUTFMgUm9vdCBDQSAyMDIyIC0gMTAeFw0yMjA2MDgx
MTA4MjJaFw00NzA2MDgxMTA4MjJaMFExCzAJBgNVBAYTAkNIMRUwEwYDVQQKEwxT
d2lzc1NpZ24gQUcxKzApBgNVBAMTIlN3aXNzU2lnbiBSU0EgVExTIFJvb3QgQ0Eg
MjAyMiAtIDEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDLKmjiC8NX
vDVjvHClO/OMPE5Xlm7DTjak9gLKHqquuN6orx122ro10JFwB9+zBvKK8i5VUXu7
LCTLf5ImgKO0lPaCoaTo+nUdWfMHamFk4saMla+ju45vVs9xzF6BYQ1t8qsCLqSX
5XH8irCRIFucdFJtrhUnWXjyCcplDn/L9Ovn3KlMd/YrFgSVrpxxpT8q2kFC5zyE
EPThPYxr4iuRR1VPuFa+Rd4iUU1OKNlfGUEGjw5NBuBwQCMBauTLE5tzrE0USJIt
/m2n+IdreXXhvhCxqohAWVTXz8TQm0SzOGlkjIHRI36qOTw7D59Ke4LKa2/KIj4x
0LDQKhySio/YGZxH5D4MucLNvkEM+KRHBdvBFzA4OmnczcNpI/2aDwLOEGrOyvi5
KaM2iYauC8BPY7kGWUleDsFpswrzd34unYyzJ5jSmY0lpx+Gs6ZUcDj8fV3oT4MM
0ZPlEuRU2j7yrTrePjxF8CgPBrnh25d7mUWe3f6VWQQvdT/TromZhqwUtKiE+shd
OxtYk8EXlFXIC+OCeYSf8wCENO7cMdWP8vpPlkwGqnj73mSiI80fPsWMvDdUDrta
clXvyFu1cvh43zcgTFeRc5JzrBh3Q4IgaezprClG5QtO+DdziZaKHG29777YtvTK
wP1H8K4LWCDFyB02rpeNUIMmJCn3nTsPBQIDAQABo2MwYTAPBgNVHRMBAf8EBTAD
AQH/MA4GA1UdDwEB/wQEAwIBBjAfBgNVHSMEGDAWgBRvjmKLk0Ow4UD2p8P98Q+4
DxU4pTAdBgNVHQ4EFgQUb45ii5NDsOFA9qfD/fEPuA8VOKUwDQYJKoZIhvcNAQEL
BQADggIBAKwsKUF9+lz1GpUYvyypiqkkVHX1uECry6gkUSsYP2OprphWKwVDIqO3
10aewCoSPY6WlkDfDDOLazeROpW7OSltwAJsipQLBwJNGD77+3v1dj2b9l4wBlgz
Hqp41eZUBDqyggmNzhYzWUUo8aWjlw5DI/0LIICQ/+Mmz7hkkeUFjxOgdg3XNwwQ
iJb0Pr6VvfHDffCjw3lHC1ySFWPtUnWK50Zpy1FVCypM9fJkT6lc/2cyjlUtMoIc
gC9qkfjLvH4YoiaoLqNTKIftV+Vlek4ASltOU8liNr3CjlvrzG4ngRhZi0Rjn9UM
ZfQpZX+RLOV/fuiJz48gy20HQhFRJjKKLjpHE7iNvUcNCfAWpO2Whi4Z2L6MOuhF
LhG6rlrnub+xzI/goP+4s9GFe3lmozm1O2bYQL7Pt2eLSMkZJVX8vY3PXtpOpvJp
zv1/THfQwUY1mFwjmwJFQ5Ra3bxHrSL+ul4vkSkphnsh3m5kt8sNjzdbowhq6/Td
Ao9QAwKxuDdollDruF/UKIqlIgyKhPBZLtU30WHlQnNYKoH3dtvi4k0NX/a3vgW0
rk4N3hY9A4GzJl5LuEsAz/+MF7psYC0nhzck5npgL7XTgwSqT0N1osGDsieYK7EO
gLrAhV5Cud+xYJHT6xh+cHiudoO+cVrQkOPKwRYlZ0rwtnu64ZzZ
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIDwzCCAqugAwIBAgIBATANBgkqhkiG9w0BAQsFADCBgjELMAkGA1UEBhMCREUx
KzApBgNVBAoMIlQtU3lzdGVtcyBFbnRlcnByaXNlIFNlcnZpY2VzIEdtYkgxHzAd
BgNVBAsMFlQtU3lzdGVtcyBUcnVzdCBDZW50ZXIxJTAjBgNVBAMMHFQtVGVsZVNl
YyBHbG9iYWxSb290IENsYXNzIDIwHhcNMDgxMDAxMTA0MDE0WhcNMzMxMDAxMjM1
OTU5WjCBgjELMAkGA1UEBhMCREUxKzApBgNVBAoMIlQtU3lzdGVtcyBFbnRlcnBy
aXNlIFNlcnZpY2VzIEdtYkgxHzAdBgNVBAsMFlQtU3lzdGVtcyBUcnVzdCBDZW50
ZXIxJTAjBgNVBAMMHFQtVGVsZVNlYyBHbG9iYWxSb290IENsYXNzIDIwggEiMA0G
CSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCqX9obX+hzkeXaXPSi5kfl82hVYAUd
AqSzm1nzHoqvNK38DcLZSBnuaY/JIPwhqgcZ7bBcrGXHX+0CfHt8LRvWurmAwhiC
FoT6ZrAIxlQjgeTNuUk/9k9uN0goOA/FvudocP05l03Sx5iRUKrERLMjfTlH6VJi
1hKTXrcxlkIF+3anHqP1wvzpesVsqXFP6st4vGCvx9702cu+fjOlbpSD8DT6Iavq
jnKgP6TeMFvvhk1qlVtDRKgQFRzlAVfFmPHmBiiRqiDFt1MmUUOyCxGVWOHAD3bZ
wI18gfNycJ5v/hqO2V81xrJvNHy+SE/iWjnX2J14np+GPgNeGYtEotXHAgMBAAGj
QjBAMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMB0GA1UdDgQWBBS/
WSA2AHmgoCJrjNXyYdK4LMuCSjANBgkqhkiG9w0BAQsFAAOCAQEAMQOiYQsfdOhy
NsZt+U2e+iKo4YFWz827n+qrkRk4r6p8FU3ztqONpfSO9kSpp+ghla0+AGIWiPAC
uvxhI+YzmzB6azZie60EI4RYZeLbK4rnJVM3YlNfvNoBYimipidx5joifsFvHZVw
IEoHNN/q/xWA5brXethbdXwFeilHfkCoMRN3zUA7tFFHei4R40cR3p1m0IvVVGb6
g1XqfMIpiRvpb7PO4gWEyS8+eIVibslfwXhjdFjASBgMmTnrpMwatXlajRWc2BQN
9noHV8cigwUtPJslJj0Ys6lDfMjIq2SPDqO/nBudMNva0Bkuqjzx+zOAduTNrRlP
BSeOE6Fuwg==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIDwzCCAqugAwIBAgIBATANBgkqhkiG9w0BAQsFADCBgjELMAkGA1UEBhMCREUx
KzApBgNVBAoMIlQtU3lzdGVtcyBFbnRlcnByaXNlIFNlcnZpY2VzIEdtYkgxHzAd
BgNVBAsMFlQtU3lzdGVtcyBUcnVzdCBDZW50ZXIxJTAjBgNVBAMMHFQtVGVsZVNl
YyBHbG9iYWxSb290IENsYXNzIDMwHhcNMDgxMDAxMTAyOTU2WhcNMzMxMDAxMjM1
OTU5WjCBgjELMAkGA1UEBhMCREUxKzApBgNVBAoMIlQtU3lzdGVtcyBFbnRlcnBy
aXNlIFNlcnZpY2VzIEdtYkgxHzAdBgNVBAsMFlQtU3lzdGVtcyBUcnVzdCBDZW50
ZXIxJTAjBgNVBAMMHFQtVGVsZVNlYyBHbG9iYWxSb290IENsYXNzIDMwggEiMA0G
CSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC9dZPwYiJvJK7genasfb3ZJNW4t/zN
8ELg63iIVl6bmlQdTQyK9tPPcPRStdiTBONGhnFBSivwKixVA9ZIw+A5OO3yXDw/
RLyTPWGrTs0NvvAgJ1gORH8EGoel15YUNpDQSXuhdfsaa3Ox+M6pCSzyU9XDFES4
hqX2iys52qMzVNn6chr3IhUciJFrf2blw2qAsCTz34ZFiP0Zf3WHHx+xGwpzJFu5
ZeAsVMhg02YXP+HMVDNzkQI6pn97djmiH5a2OK61yJN0HZ65tOVgnS9W0eDrXltM
EnAMbEQgqxHY9Bn20pxSN+f6tsIxO0rUFJmtxxr1XV/6B7h8DR/Wgx6zAgMBAAGj
QjBAMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMB0GA1UdDgQWBBS1
A/d2O2GCahKqGFPrAyGUv/7OyjANBgkqhkiG9w0BAQsFAAOCAQEAVj3vlNW92nOy
WL6ukK2YJ5f+AbGwUgC4TeQbIXQbfsDuXmkqJa9c1h3a0nnJ85cp4IaH3gRZD/FZ
1GSFS5mvJQQeyUapl96Cshtwn5z2r3Ex3XsFpSzTucpH9sry9uetuUg/vBa3wW30
6gmv7PO15wWeph6KU1HWk4HMdJP2udqmJQV0eVp+QD6CSyYRMG7hP0HHRwA11fXT
91Q+gT3aSWqas+8QPebrb9HIIkfLzM8BMZLZGOMivgkeGj5asuRrDFR6fUNOuIml
e9eiPZaGzPImNC1qkp2aGtAw4l1OBLBfiyB+d8E9lYLRRpo7PHi4b6HQDWSieB4p
TpPDpFQUWw==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIEYzCCA0ugAwIBAgIBATANBgkqhkiG9w0BAQsFADCB0jELMAkGA1UEBhMCVFIx
GDAWBgNVBAcTD0dlYnplIC0gS29jYWVsaTFCMEAGA1UEChM5VHVya2l5ZSBCaWxp
bXNlbCB2ZSBUZWtub2xvamlrIEFyYXN0aXJtYSBLdXJ1bXUgLSBUVUJJVEFLMS0w
KwYDVQQLEyRLYW11IFNlcnRpZmlrYXN5b24gTWVya2V6aSAtIEthbXUgU00xNjA0
BgNVBAMTLVRVQklUQUsgS2FtdSBTTSBTU0wgS29rIFNlcnRpZmlrYXNpIC0gU3Vy
dW0gMTAeFw0xMzExMjUwODI1NTVaFw00MzEwMjUwODI1NTVaMIHSMQswCQYDVQQG
EwJUUjEYMBYGA1UEBxMPR2ViemUgLSBLb2NhZWxpMUIwQAYDVQQKEzlUdXJraXll
IEJpbGltc2VsIHZlIFRla25vbG9qaWsgQXJhc3Rpcm1hIEt1cnVtdSAtIFRVQklU
QUsxLTArBgNVBAsTJEthbXUgU2VydGlmaWthc3lvbiBNZXJrZXppIC0gS2FtdSBT
TTE2MDQGA1UEAxMtVFVCSVRBSyBLYW11IFNNIFNTTCBLb2sgU2VydGlmaWthc2kg
LSBTdXJ1bSAxMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAr3UwM6q7
a9OZLBI3hNmNe5eA027n/5tQlT6QlVZC1xl8JoSNkvoBHToP4mQ4t4y86Ij5iySr
LqP1N+RAjhgleYN1Hzv/bKjFxlb4tO2KRKOrbEz8HdDc72i9z+SqzvBV96I01INr
N3wcwv61A+xXzry0tcXtAA9TNypN9E8Mg/uGz8v+jE69h/mniyFXnHrfA2eJLJ2X
YacQuFWQfw4tJzh03+f92k4S400VIgLI4OD8D62K18lUUMw7D8oWgITQUVbDjlZ/
iSIzL+aFCr2lqBs23tPcLG07xxO9WSMs5uWk99gL7eqQQESolbuT1dCANLZGeA4f
AJNG4e7p+exPFwIDAQABo0IwQDAdBgNVHQ4EFgQUZT/HiobGPN08VFw1+DrtUgxH
V8gwDgYDVR0PAQH/BAQDAgEGMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQEL
BQADggEBACo/4fEyjq7hmFxLXs9rHmoJ0iKpEsdeV31zVmSAhHqT5Am5EM2fKifh
AHe+SMg1qIGf5LgsyX8OsNJLN13qudULXjS99HMpw+0mFZx+CFOKWI3QSyjfwbPf
IPP54+M638yclNhOT8NrF7f3cuitZjO1JVOr4PhMqZ398g26rrnZqsZr+ZO7rqu4
lzwDGrpDxpa5RXI4s6ehlj2Re37AIVNMh+3yC1SVUZPVIqUNivGTDj5UDrDYyU7c
8jEyVupk+eq1nRZmQnLzf9OxMUP8pI4X8W0jq5Rm+K37DwhuJi1/FwcJsoz7UMCf
lo3Ptv0AnVoUmr8CRPXBwp8iXqIPoeM=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFjTCCA3WgAwIBAgIQQAE0jMIAAAAAAAAAATzyxjANBgkqhkiG9w0BAQwFADBQ
MQswCQYDVQQGEwJUVzESMBAGA1UEChMJVEFJV0FOLUNBMRAwDgYDVQQLEwdSb290
IENBMRswGQYDVQQDExJUV0NBIENZQkVSIFJvb3QgQ0EwHhcNMjIxMTIyMDY1NDI5
WhcNNDcxMTIyMTU1OTU5WjBQMQswCQYDVQQGEwJUVzESMBAGA1UEChMJVEFJV0FO
LUNBMRAwDgYDVQQLEwdSb290IENBMRswGQYDVQQDExJUV0NBIENZQkVSIFJvb3Qg
Q0EwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDG+Moe2Qkgfh1sTs6P
40czRJzHyWmqOlt47nDSkvgEs1JSHWdyKKHfi12VCv7qze33Kc7wb3+szT3vsxxF
avcokPFhV8UMxKNQXd7UtcsZyoC5dc4pztKFIuwCY8xEMCDa6pFbVuYdHNWdZsc/
34bKS1PE2Y2yHer43CdTo0fhYcx9tbD47nORxc5zb87uEB8aBs/pJ2DFTxnk684i
JkXXYJndzk834H/nY62wuFm40AZoNWDTNq5xQwTxaWV4fPMf88oon1oglWa0zbfu
j3ikRRjpJi+NmykosaS3Om251Bw4ckVYsV7r8Cibt4LK/c/WMw+f+5eesRycnupf
Xtuq3VTpMCEobY5583WSjCb+3MX2w7DfRFlDo7YDKPYIMKoNM+HvnKkHIuNZW0CP
2oi3aQiotyMuRAlZN1vH4xfyIutuOVLF3lSnmMlLIJXcRolftBL5hSmO68gnFSDA
S9TMfAxsNAwmmyYxpjyn9tnQS6Jk/zuZQXLB4HCX8SS7K8R0IrGsayIyJNN4KsDA
oS/xUgXJP+92ZuJF2A09rZXIx4kmyA+upwMu+8Ff+iDhcK2wZSA3M2Cw1a/XDBzC
kHDXShi8fgGwsOsVHkQGzaRP6AzRwyAQ4VRlnrZR0Bp2a0JaWHY06rc3Ga4udfmW
5cFZ95RXKSWNOkyrTZpB0F8mAwIDAQABo2MwYTAOBgNVHQ8BAf8EBAMCAQYwDwYD
VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBSdhWEUfMFib5do5E83QOGt4A1WNzAd
BgNVHQ4EFgQUnYVhFHzBYm+XaORPN0DhreANVjcwDQYJKoZIhvcNAQEMBQADggIB
AGSPesRiDrWIzLjHhg6hShbNcAu3p4ULs3a2D6f/CIsLJc+o1IN1KriWiLb73y0t
tGlTITVX1olNc79pj3CjYcya2x6a4CD4bLubIp1dhDGaLIrdaqHXKGnK/nZVekZn
68xDiBaiA9a5F/gZbG0jAn/xX9AKKSM70aoK7akXJlQKTcKlTfjF/biBzysseKNn
TKkHmvPfXvt89YnNdJdhEGoHK4Fa0o635yDRIG4kqIQnoVesqlVYL9zZyvpoBJ7t
RCT5dEA7IzOrg1oYJkK2bVS1FmAwbLGg+LhBoF1JSdJlBTrq/p1hvIbZv97Tujqx
f36SNI7JAG7cmL3c7IAFrQI932XtCwP39xaEBDG6k5TY8hL4iuO/Qq+n1M0RFxbI
Qh0UqEL20kCGoE8jypZFVmAGzbdVAaYBlGX+bgUJurSkquLvWL69J1bY73NxW0Qz
8ppy6rBePm6pUlvscG21h483XjyMnM7k8M4MZ0HMzvaAq07MTFb1wWFZk7Q+ptq4
NxKfKjLji7gh7MMrZQzvIt6IKTtM1/r+t+FHvpw+PoP7UV31aPcuIYXcv/Fa4nzX
xeSDwWrruoBa3lwtcHb4yOWHh8qgnaHlIhInD0Q9HWzq1MKLL295q39QpsQZp6F6
t5b5wR9iWqJDB0BeJsas7a5wFsWqynKKTbDPAYsDP27X
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFQTCCAymgAwIBAgICDL4wDQYJKoZIhvcNAQELBQAwUTELMAkGA1UEBhMCVFcx
EjAQBgNVBAoTCVRBSVdBTi1DQTEQMA4GA1UECxMHUm9vdCBDQTEcMBoGA1UEAxMT
VFdDQSBHbG9iYWwgUm9vdCBDQTAeFw0xMjA2MjcwNjI4MzNaFw0zMDEyMzExNTU5
NTlaMFExCzAJBgNVBAYTAlRXMRIwEAYDVQQKEwlUQUlXQU4tQ0ExEDAOBgNVBAsT
B1Jvb3QgQ0ExHDAaBgNVBAMTE1RXQ0EgR2xvYmFsIFJvb3QgQ0EwggIiMA0GCSqG
SIb3DQEBAQUAA4ICDwAwggIKAoICAQCwBdvI64zEbooh745NnHEKH1Jw7W2CnJfF
10xORUnLQEK1EjRsGcJ0pDFfhQKX7EMzClPSnIyOt7h52yvVavKOZsTuKwEHktSz
0ALfUPZVr2YOy+BHYC8rMjk1Ujoog/h7FsYYuGLWRyWRzvAZEk2tY/XTP3VfKfCh
MBwqoJimFb3u/Rk28OKRQ4/6ytYQJ0lM793B8YVwm8rqqFpD/G2Gb3PpN0Wp8DbH
zIh1HrtsBv+baz4X7GGqcXzGHaL3SekVtTzWoWH1EfcFbx39Eb7QMAfCKbAJTibc
46KokWofwpFFiFzlmLhxpRUZyXx1EcxwdE8tmx2RRP1WKKD+u4ZqyPpcC1jcxkt2
yKsi2XMPpfRaAok/T54igu6idFMqPVMnaR1sjjIsZAAmY2E2TqNGtz99sy2sbZCi
laLOz9qC5wc0GZbpuCGqKX6mOL6OKUohZnkfs8O1CWfe1tQHRvMq2uYiN2DLgbYP
oA/pyJV/v1WRBXrPPRXAb94JlAGD1zQbzECl8LibZ9WYkTunhHiVJqRaCPgrdLQA
BDzfuBSO6N+pjWxnkjMdwLfS7JLIvgm/LCkFbwJrnu+8vyq8W8BQj0FwcYeyTbcE
qYSjMq+u7msXi7Kx/mzhkIyIqJdIzshNy/MGz19qCkKxHh53L46g5pIOBvwFItIm
4TFRfTLcDwIDAQABoyMwITAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0TAQH/BAUwAwEB
/zANBgkqhkiG9w0BAQsFAAOCAgEAXzSBdu+WHdXltdkCY4QWwa6gcFGn90xHNcgL
1yg9iXHZqjNB6hQbbCEAwGxCGX6faVsgQt+i0trEfJdLjbDorMjupWkEmQqSpqsn
LhpNgb+E1HAerUf+/UqdM+DyucRFCCEK2mlpc3INvjT+lIutwx4116KD7+U4x6WF
H6vPNOw/KP4M8VeGTslV9xzU2KV9Bnpv1d8Q34FOIWWxtuEXeZVFBs5fzNxGiWNo
RI2T9GRwoD2dKAXDOXC4Ynsg/eTb6QihuJ49CcdP+yz4k3ZB3lLg4VfSnQO8d57+
nile98FRYB/e2guyLXW3Q0iT5/Z5xoRdgFlglPx4mI88k1HtQJAH32RjJMtOcQWh
15QaiDLxInQirqWm2BJpTGCjAu4r7NRjkgtevi92a6O2JryPA9gK8kxkRr05YuWW
6zRjESjMlfGt7+/cgFhI6Uu46mWs6fyAtbXIRfmswZ/ZuepiiI7E8UuDEq3mi4TW
nsLrgxifarsbJGAzcMzs9zLzXNl5fe+epP7JI8Mk7hWSsT2RTyaGvWZzJBPqpK5j
wa19hAM8EHiGG3njxPPyBJUgriOCxLM6AGK/5jYk4Ve6xx6QddVfP5VhK8E7zeWz
aGHQRiapIVJpLesux+t3zqY6tQMzT3bR51xUAV3LePTJDL/PEo4XLSNolOer/qmy
KwbQBM0=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIDezCCAmOgAwIBAgIBATANBgkqhkiG9w0BAQUFADBfMQswCQYDVQQGEwJUVzES
MBAGA1UECgwJVEFJV0FOLUNBMRAwDgYDVQQLDAdSb290IENBMSowKAYDVQQDDCFU
V0NBIFJvb3QgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkwHhcNMDgwODI4MDcyNDMz
WhcNMzAxMjMxMTU1OTU5WjBfMQswCQYDVQQGEwJUVzESMBAGA1UECgwJVEFJV0FO
LUNBMRAwDgYDVQQLDAdSb290IENBMSowKAYDVQQDDCFUV0NBIFJvb3QgQ2VydGlm
aWNhdGlvbiBBdXRob3JpdHkwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
AQCwfnK4pAOU5qfeCTiRShFAh6d8WWQUe7UREN3+v9XAu1bihSX0NXIP+FPQQeFE
AcK0HMMxQhZHhTMidrIKbw/lJVBPhYa+v5guEGcevhEFhgWQxFnQfHgQsIBct+HH
K3XLfJ+utdGdIzdjp9xCoi2SBBtQwXu4PhvJVgSLL1KbralW6cH/ralYhzC2gfeX
RfwZVzsrb+RH9JlF/h3x+JejiB03HFyP4HYlmlD4oFT/RJB2I9IyxsOrBr/8+7/z
rX2SYgJbKdM1o5OaQ2RgXbL6Mv87BK9NQGr5x+PvI/1ry+UPizgN7gr8/g+YnzAx
3WxSZfmLgb4i4RxYA7qRG4kHAgMBAAGjQjBAMA4GA1UdDwEB/wQEAwIBBjAPBgNV
HRMBAf8EBTADAQH/MB0GA1UdDgQWBBRqOFsmjd6LWvJPelSDGRjjCDWmujANBgkq
hkiG9w0BAQUFAAOCAQEAPNV3PdrfibqHDAhUaiBQkr6wQT25JmSDCi/oQMCXKCeC
MErJk/9q56YAf4lCmtYR5VPOL8zy2gXE/uJQxDqGfczafhAJO5I1KlOy/usrBdls
XebQ79NqZp4VKIV66IIArB6nCWlWQtNoURi+VJq/REG6Sb4gumlc7rh3zc5sH62D
lhh9DrUUOYTxKOkto557HnpyWoOzeW/vtPzQCqVYT0bf+215WfKEIlKuD8z7fDvn
aspHYcN6+NOSBB+4IIThNlQWx0DeO4pz3N/GCUzf7Nr/1FNCocnyYh0igzyXxfkZ
YiesZSLX0zzG5Y6yU8xJzrww/nsOM5D77dIUkR8Hrw==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICQjCCAcmgAwIBAgIQNjqWjMlcsljN0AFdxeVXADAKBggqhkjOPQQDAzBjMQsw
CQYDVQQGEwJERTEnMCUGA1UECgweRGV1dHNjaGUgVGVsZWtvbSBTZWN1cml0eSBH
bWJIMSswKQYDVQQDDCJUZWxla29tIFNlY3VyaXR5IFRMUyBFQ0MgUm9vdCAyMDIw
MB4XDTIwMDgyNTA3NDgyMFoXDTQ1MDgyNTIzNTk1OVowYzELMAkGA1UEBhMCREUx
JzAlBgNVBAoMHkRldXRzY2hlIFRlbGVrb20gU2VjdXJpdHkgR21iSDErMCkGA1UE
AwwiVGVsZWtvbSBTZWN1cml0eSBUTFMgRUNDIFJvb3QgMjAyMDB2MBAGByqGSM49
AgEGBSuBBAAiA2IABM6//leov9Wq9xCazbzREaK9Z0LMkOsVGJDZos0MKiXrPk/O
tdKPD/M12kOLAoC+b1EkHQ9rK8qfwm9QMuU3ILYg/4gND21Ju9sGpIeQkpT0CdDP
f8iAC8GXs7s1J8nCG6NCMEAwHQYDVR0OBBYEFONyzG6VmUex5rNhTNHLq+O6zd6f
MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2cA
MGQCMHVSi7ekEE+uShCLsoRbQuHmKjYC2qBuGT8lv9pZMo7k+5Dck2TOrbRBR2Di
z6fLHgIwN0GMZt9Ba9aDAEH9L1r3ULRn0SyocddDypwnJJGDSA3PzfdUga/sf+Rn
27iQ7t0l
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFszCCA5ugAwIBAgIQIZxULej27HF3+k7ow3BXlzANBgkqhkiG9w0BAQwFADBj
MQswCQYDVQQGEwJERTEnMCUGA1UECgweRGV1dHNjaGUgVGVsZWtvbSBTZWN1cml0
eSBHbWJIMSswKQYDVQQDDCJUZWxla29tIFNlY3VyaXR5IFRMUyBSU0EgUm9vdCAy
MDIzMB4XDTIzMDMyODEyMTY0NVoXDTQ4MDMyNzIzNTk1OVowYzELMAkGA1UEBhMC
REUxJzAlBgNVBAoMHkRldXRzY2hlIFRlbGVrb20gU2VjdXJpdHkgR21iSDErMCkG
A1UEAwwiVGVsZWtvbSBTZWN1cml0eSBUTFMgUlNBIFJvb3QgMjAyMzCCAiIwDQYJ
KoZIhvcNAQEBBQADggIPADCCAgoCggIBAO01oYGA88tKaVvC+1GDrib94W7zgRJ9
cUD/h3VCKSHtgVIs3xLBGYSJwb3FKNXVS2xE1kzbB5ZKVXrKNoIENqil/Cf2SfHV
cp6R+SPWcHu79ZvB7JPPGeplfohwoHP89v+1VmLhc2o0mD6CuKyVU/QBoCcHcqMA
U6DksquDOFczJZSfvkgdmOGjup5czQRxUX11eKvzWarE4GC+j4NSuHUaQTXtvPM6
Y+mpFEXX5lLRbtLevOP1Czvm4MS9Q2QTps70mDdsipWol8hHD/BeEIvnHRz+sTug
BTNoBUGCwQMrAcjnj02r6LX2zWtEtefdi+zqJbQAIldNsLGyMcEWzv/9FIS3R/qy
8XDe24tsNlikfLMR0cN3f1+2JeANxdKz+bi4d9s3cXFH42AYTyS2dTd4uaNir73J
co4vzLuu2+QVUhkHM/tqty1LkCiCc/4YizWN26cEar7qwU02OxY2kTLvtkCJkUPg
8qKrBC7m8kwOFjQgrIfBLX7JZkcXFBGk8/ehJImr2BrIoVyxo/eMbcgByU/J7MT8
rFEz0ciD0cmfHdRHNCk+y7AO+oMLKFjlKdw/fKifybYKu6boRhYPluV75Gp6SG12
mAWl3G0eQh5C2hrgUve1g8Aae3g1LDj1H/1Joy7SWWO/gLCMk3PLNaaZlSJhZQNg
+y+TS/qanIA7AgMBAAGjYzBhMA4GA1UdDwEB/wQEAwIBBjAdBgNVHQ4EFgQUtqeX
gj10hZv3PJ+TmpV5dVKMbUcwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBS2
p5eCPXSFm/c8n5OalXl1UoxtRzANBgkqhkiG9w0BAQwFAAOCAgEAqMxhpr51nhVQ
pGv7qHBFfLp+sVr8WyP6Cnf4mHGCDG3gXkaqk/QeoMPhk9tLrbKmXauw1GLLXrtm
9S3ul0A8Yute1hTWjOKWi0FpkzXmuZlrYrShF2Y0pmtjxrlO8iLpWA1WQdH6DErw
M807u20hOq6OcrXDSvvpfeWxm4bu4uB9tPcy/SKE8YXJN3nptT+/XOR0so8RYgDd
GGah2XsjX/GO1WfoVNpbOms2b/mBsTNHM3dA+VKq3dSDz4V4mZqTuXNnQkYRIer+
CqkbGmVps4+uFrb2S1ayLfmlyOw7YqPta9BO1UAJpB+Y1zqlklkg5LB9zVtzaL1t
xKITDmcZuI1CfmwMmm6gJC3VRRvcxAIU/oVbZZfKTpBQCHpCNfnqwmbU+AGuHrS+
w6jv/naaoqYfRvaE7fzbzsQCzndILIyy7MMAo+wsVRjBfhnu4S/yrYObnqsZ38aK
L4x35bcF7DvB7L6Gs4a8wPfc5+pbrrLMtTWGS9DiP7bY+A4A7l3j941Y/8+LN+lj
X273CXE2whJdV/LItM3z7gLfEdxquVeEHVlNjM7IDiPCtyaaEBRx/pOyiriA8A4Q
ntOoUAw3gi/q4Iqd4Sw5/7W0cwDk90imc6y/st53BIe0o82bNSQ3+pCTE4FCxpgm
dTdmQRCsu/WU48IxK63nI1bMNSWSs1A=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICMjCCAbegAwIBAgIPAYvSIlRjTQSLbOVHH9K1MAoGCCqGSM49BAMDMEoxCzAJ
BgNVBAYTAlNFMRkwFwYDVQQKDBBUZWxpYSBDb21wYW55IEFCMSAwHgYDVQQDDBdU
ZWxpYSBFQyBUTFMgUm9vdCBDQSB2MzAeFw0yMzExMTUwODU1MjZaFw00ODA1MjMx
MTAwMDBaMEoxCzAJBgNVBAYTAlNFMRkwFwYDVQQKDBBUZWxpYSBDb21wYW55IEFC
MSAwHgYDVQQDDBdUZWxpYSBFQyBUTFMgUm9vdCBDQSB2MzB2MBAGByqGSM49AgEG
BSuBBAAiA2IABMHIlhVDLbmFKUpW0iK4dpryT6emYOeS31JPwWnWPmkWRrAkTbPX
40sQfHI9mpR7Rbktu3ngg6W+BBSXSechtMCnBmWXj/EaVlmV5cY1jD2HoTfhBQ3A
acpCNMLJK4NpZaNjMGEwHwYDVR0jBBgwFoAU1GToQ4g6cy/QGnGCNgtehd7H3kMw
HQYDVR0OBBYEFNRk6EOIOnMv0BpxgjYLXoXex95DMA4GA1UdDwEB/wQEAwIBBjAP
BgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMDA2kAMGYCMQCXAUdS/9bbJ8A1JYaG
f/bWt/s7Ta0ot5Ulno8OjSNYRWQIlS4tVWldvTAVA7heOFgCMQCvKr8+Z2Rn+OBr
5UHzlgBObpad1LuwNTRcdNgUJxIWadcki+UBLEi1/AURKV5md2M=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFgjCCA2qgAwIBAgIPAYvSUKtCVSxHWr2h3BrFMA0GCSqGSIb3DQEBDAUAMEsx
CzAJBgNVBAYTAlNFMRkwFwYDVQQKDBBUZWxpYSBDb21wYW55IEFCMSEwHwYDVQQD
DBhUZWxpYSBSU0EgVExTIFJvb3QgQ0EgdjMwHhcNMjMxMTE1MDk0NzQyWhcNNDgw
NTIzMTEwMDAwWjBLMQswCQYDVQQGEwJTRTEZMBcGA1UECgwQVGVsaWEgQ29tcGFu
eSBBQjEhMB8GA1UEAwwYVGVsaWEgUlNBIFRMUyBSb290IENBIHYzMIICIjANBgkq
hkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAsV89KG19hCf4S1Fvk8D3TyDERhmcvx8F
7Kmb4WATx3ije1id3KHxRE0TKmcNCbAQ57bvHFEYa4hR2l20VjVadExqOW+2ld99
MbEiO+jRVOz+BbxLxJnmGwCqI+BfuTjjVReDxsxjQvjgBsClaO/sm5i70nlZcWGR
tIkvWDK3NNkT5RtwXc/O8NTFVpbUqT6cRjIj3olAblR+lRf4Ffy5o+Q9fabjYn9Z
9S4itruElcEFf9Ljk7fwdTycT/rvJW9w/B3G2a3r0f/zXNOVruIBcqE6pkSospAC
U2bG42fYKrbM/GWnp7u+p9Frz4jaNwpb4YHuEeS8BratNcP8X62jXIvvKHxlsMDJ
Cnb4U8JzFOLsU6mohVY58BdZrvi0Gk9UOuqmgoG6dskHoksjZTlK61D/InzmEoA1
yAYJFDVysjRxDUOu9cAwANbqmq77WIFL6BpnZgVqPtMfG6wN8BrTKdapvilVsYR5
9BFgIsAVBMxrGh+W+QcvmJafUpASvlArKvVG2FI4i6PiLjSBT0+6F6EQLrYqefOQ
F/fBNEXb+njUQ0SUVrAqtH4Y+OjCI/a4/JJQppxeemZcQ0SUShgiI5AM5xHO5iya
UrTjYH4zxUz9j+1FEbDH/xpstr1gXBykspup+hRTaJcbA+UbpJqtWZndAPddJmt6
YJQ+dU3pDu8CAwEAAaNjMGEwHwYDVR0jBBgwFoAUsMep0t2yKFZzBJSMFFxIbzdS
kqgwHQYDVR0OBBYEFLDHqdLdsihWcwSUjBRcSG83UpKoMA4GA1UdDwEB/wQEAwIB
BjAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBDAUAA4ICAQBdYzFsNGDRk7bR
/AgRKq+5637YuOW+w6uhpoS0VnKMUpyHCwku86hEvqivakPtfmlm4bFwt++sb/8O
XsWBqtfbXMaBNDTZl8XRMJuLWOW2JrbKkRzgG0eBUcvsadG1rrhbmZqYvFXaAZO7
o4TdOZzxhBB5GOAWWXB3IeraNP4J63zyo9n8Gqw3sJBG44em5hoYjBffP+npibys
lnslRi4L6xHsCYj/Pab+OlqbMCB6v+sTCLeEIukRVzoR9aQ45pEK7Z1QBnSsbAKQ
tss0JKD9d/mX143H1xePjPhTXlv5JCkhrcj+SShz0P9+EHoWe6m9lyUEOIVn0rp+
yVJWNbmyDv3VkwFxHC1ApSQsgSimjGQ4wtr6cSmordYxkV+Ro8lOIIhRksXPyDk2
7gW6IjUXCkZKpxFjkL3jiBSc8SkxnwCWtXg8xwNwdFVNBGLCCuJnsneYXjJNqzRq
UcoGwzsvF3Qi/ZnHUNvISdevlgIAXL4Wvrxaqvoa01wB+GCfs57RTGE4TvAGhKNK
us8K3hRT1BSpigzMIRzSxtAOrqPN6j//QSmW9f8Jcncri4j2ihSpVrFU0NdNkMhZ
eAKidTFPsxCVFuW4Aniz7jqiw5sWtjbQrlW035izIEU4sYwQoC1Nx0Svy+mMTRai
50LqFQ+A1/Hq6xHHDNx7CI83d23Erw==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFdDCCA1ygAwIBAgIPAWdfJ9b+euPkrL4JWwWeMA0GCSqGSIb3DQEBCwUAMEQx
CzAJBgNVBAYTAkZJMRowGAYDVQQKDBFUZWxpYSBGaW5sYW5kIE95ajEZMBcGA1UE
AwwQVGVsaWEgUm9vdCBDQSB2MjAeFw0xODExMjkxMTU1NTRaFw00MzExMjkxMTU1
NTRaMEQxCzAJBgNVBAYTAkZJMRowGAYDVQQKDBFUZWxpYSBGaW5sYW5kIE95ajEZ
MBcGA1UEAwwQVGVsaWEgUm9vdCBDQSB2MjCCAiIwDQYJKoZIhvcNAQEBBQADggIP
ADCCAgoCggIBALLQPwe84nvQa5n44ndp586dpAO8gm2h/oFlH0wnrI4AuhZ76zBq
AMCzdGh+sq/H1WKzej9Qyow2RCRj0jbpDIX2Q3bVTKFgcmfiKDOlyzG4OiIjNLh9
vVYiQJ3q9HsDrWj8soFPmNB06o3lfc1jw6P23pLCWBnglrvFxKk9pXSW/q/5iaq9
lRdU2HhE8Qx3FZLgmEKnpNaqIJLNwaCzlrI6hEKNfdWV5Nbb6WLEWLN5xYzTNTOD
n3WhUidhOPFZPY5Q4L15POdslv5e2QJltI5c0BE0312/UqeBAMN/mUWZFdUXyApT
7GPzmX3MaRKGwhfwAZ6/hLzRUssbkmbOpFPlob/E2wnW5olWK8jjfN7j/4nlNW4o
6GwLI1GpJQXrSPjdscr6bAhR77cYbETKJuFzxokGgeWKrLDiKca5JLNrRBH0pUPC
TEPlcDaMtjNXepUugqD0XBCzYYP2AgWGLnwtbNwDRm41k9V6lS/eINhbfpSQBGq6
WT0EBXWdN6IOLj3rwaRSg/7Qa9RmjtzG6RJOHSpXqhC8fF6CfaamyfItufUXJ63R
DolUK5X6wK0dmBR4M0KGCqlztft0DbcbMBnEWg4cJ7faGND/isgFuvGqHKI3t+ZI
pEYslOqodmJHixBTB0hXbOKSTbauBcvcwUpej6w9GU7C7WB1K9vBykLVAgMBAAGj
YzBhMB8GA1UdIwQYMBaAFHKs5DN5qkWH9v2sHZ7Wxy+G2CQ5MB0GA1UdDgQWBBRy
rOQzeapFh/b9rB2e1scvhtgkOTAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0TAQH/BAUw
AwEB/zANBgkqhkiG9w0BAQsFAAOCAgEAoDtZpwmUPjaE0n4vOaWWl/oRrfxn83EJ
8rKJhGdEr7nv7ZbsnGTbMjBvZ5qsfl+yqwE2foH65IRe0qw24GtixX1LDoJt0nZi
0f6X+J8wfBj5tFJ3gh1229MdqfDBmgC9bXXYfef6xzijnHDoRnkDry5023X4blMM
A8iZGok1GTzTyVR8qPAs5m4HeW9q4ebqkYJpCh3DflminmtGFZhb069GHWLIzoBS
SRE/yQQSwxN8PzuKlts8oB4KtItUsiRnDe+Cy748fdHif64W1lZYudogsYMVoe+K
TTJvQS8TUoKU1xrBeKJR3Stwbbca+few4GeXVtt8YVMJAygCQMez2P2ccGrGKMOF
6eLtGpOg3kuYooQ+BXcBlj37tCAPnHICehIv1aO6UXivKitEZU61/Qrowc15h2Er
3oBXRb9n8ZuRXqWk7FlIEA04x7D6w0RtBPV4UBySllva9bguulvP5fBqnUsvWHMt
Ty3EHD70sz+rFQ47GUGKpMFXEmZxTPpT41frYpUJnlTd0cI8Vzy9OK2YZLe4A5pT
VmBds9hCG1xLEooc6+t9xnppxyd/pPiL8uSUZodL6ZQHCRJ5irLrdATczvREWeAW
ysUsWNc8e89ihmpQfTU2Zqf7N+cox9jQraVplI/owd8k+BsHMYeB2F326CjYSlKA
rBPuUBQemMc=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFpTCCA42gAwIBAgIUZPYOZXdhaqs7tOqFhLuxibhxkw8wDQYJKoZIhvcNAQEM
BQAwWjELMAkGA1UEBhMCQ04xJTAjBgNVBAoMHFRydXN0QXNpYSBUZWNobm9sb2dp
ZXMsIEluYy4xJDAiBgNVBAMMG1RydXN0QXNpYSBHbG9iYWwgUm9vdCBDQSBHMzAe
Fw0yMTA1MjAwMjEwMTlaFw00NjA1MTkwMjEwMTlaMFoxCzAJBgNVBAYTAkNOMSUw
IwYDVQQKDBxUcnVzdEFzaWEgVGVjaG5vbG9naWVzLCBJbmMuMSQwIgYDVQQDDBtU
cnVzdEFzaWEgR2xvYmFsIFJvb3QgQ0EgRzMwggIiMA0GCSqGSIb3DQEBAQUAA4IC
DwAwggIKAoICAQDAMYJhkuSUGwoqZdC+BqmHO1ES6nBBruL7dOoKjbmzTNyPtxNS
T1QY4SxzlZHFZjtqz6xjbYdT8PfxObegQ2OwxANdV6nnRM7EoYNl9lA+sX4WuDqK
AtCWHwDNBSHvBm3dIZwZQ0WhxeiAysKtQGIXBsaqvPPW5vxQfmZCHzyLpnl5hkA1
nyDvP+uLRx+PjsXUjrYsyUQE49RDdT/VP68czH5GX6zfZBCK70bwkPAPLfSIC7Ep
qq+FqklYqL9joDiR5rPmd2jE+SoZhLsO4fWvieylL1AgdB4SQXMeJNnKziyhWTXA
yB1GJ2Faj/lN03J5Zh6fFZAhLf3ti1ZwA0pJPn9pMRJpxx5cynoTi+jm9WAPzJMs
hH/x/Gr8m0ed262IPfN2dTPXS6TIi/n1Q1hPy8gDVI+lhXgEGvNz8teHHUGf59gX
zhqcD0r83ERoVGjiQTz+LISGNzzNPy+i2+f3VANfWdP3kXjHi3dqFuVJhZBFcnAv
kV34PmVACxmZySYgWmjBNb9Pp1Hx2BErW+Canig7CjoKH8GB5S7wprlppYiU5msT
f9FkPz2ccEblooV7WIQn3MSAPmeamseaMQ4w7OYXQJXZRe0Blqq/DPNL0WP3E1jA
uPP6Z92bfW1K/zJMtSU7/xxnD4UiWQWRkUF3gdCFTIcQcf+eQxuulXUtgQIDAQAB
o2MwYTAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFEDk5PIj7zjKsK5Xf/Ih
MBY027ySMB0GA1UdDgQWBBRA5OTyI+84yrCuV3/yITAWNNu8kjAOBgNVHQ8BAf8E
BAMCAQYwDQYJKoZIhvcNAQEMBQADggIBACY7UeFNOPMyGLS0XuFlXsSUT9SnYaP4
wM8zAQLpw6o1D/GUE3d3NZ4tVlFEbuHGLige/9rsR82XRBf34EzC4Xx8MnpmyFq2
XFNFV1pF1AWZLy4jVe5jaN/TG3inEpQGAHUNcoTpLrxaatXeL1nHo+zSh2bbt1S1
JKv0Q3jbSwTEb93mPmY+KfJLaHEih6D4sTNjduMNhXJEIlU/HHzp/LgV6FL6qj6j
ITk1dImmasI5+njPtqzn59ZW/yOSLlALqbUHM/Q4X6RJpstlcHboCoWASzY9M/eV
VHUl2qzEc4Jl6VL1XP04lQJqaTDFHApXB64ipCz5xUG3uOyfT0gA+QEEVcys+TIx
xHWVBqB/0Y0n3bOppHKH/lmLmnp0Ft0WpWIp6zqW3IunaFnT63eROfjXy9mPX1on
AX1daBli2MjN9LdyR75bl87yraKZk62Uy5P2EgmVtqvXO9A/EcswFi55gORngS1d
7XB4tmBZrOFdRWOPyN9yaFvqHbgB8X7754qz41SgOAngPN5C8sLtLpvzHzW2Ntjj
gKGLzZlkD8Kqq7HK9W+eQ42EVJmzbsASZthwEPEGNTNDqJwuuhQxzhB/HIbjj9LV
+Hfsm6vxL2PZQl/gZ4FkkfGXL/xuJvYz+NO1+MRiqzFRJQJ6+N1rZdVtTTDIZbpo
FGWsJwt0ivKH
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICVTCCAdygAwIBAgIUTyNkuI6XY57GU4HBdk7LKnQV1tcwCgYIKoZIzj0EAwMw
WjELMAkGA1UEBhMCQ04xJTAjBgNVBAoMHFRydXN0QXNpYSBUZWNobm9sb2dpZXMs
IEluYy4xJDAiBgNVBAMMG1RydXN0QXNpYSBHbG9iYWwgUm9vdCBDQSBHNDAeFw0y
MTA1MjAwMjEwMjJaFw00NjA1MTkwMjEwMjJaMFoxCzAJBgNVBAYTAkNOMSUwIwYD
VQQKDBxUcnVzdEFzaWEgVGVjaG5vbG9naWVzLCBJbmMuMSQwIgYDVQQDDBtUcnVz
dEFzaWEgR2xvYmFsIFJvb3QgQ0EgRzQwdjAQBgcqhkjOPQIBBgUrgQQAIgNiAATx
s8045CVD5d4ZCbuBeaIVXxVjAd7Cq92zphtnS4CDr5nLrBfbK5bKfFJV4hrhPVbw
LxYI+hW8m7tH5j/uqOFMjPXTNvk4XatwmkcN4oFBButJ+bAp3TPsUKV/eSm4IJij
YzBhMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAUpbtKl86zK3+kMd6Xg1mD
pm9xy94wHQYDVR0OBBYEFKW7SpfOsyt/pDHel4NZg6ZvccveMA4GA1UdDwEB/wQE
AwIBBjAKBggqhkjOPQQDAwNnADBkAjBe8usGzEkxn0AAbbd+NvBNEU/zy4k6LHiR
UKNbwMp1JvK/kF0LgoxgKJ/GcJpo5PECMFxYDlZ2z1jD1xCMuo6u47xkdUfFVZDj
/bpV6wfEU6s3qe4hsiFbYI89MvHVI5TWWA==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICMTCCAbegAwIBAgIUNnThTXxlE8msg1UloD5Sfi9QaMcwCgYIKoZIzj0EAwMw
WDELMAkGA1UEBhMCQ04xJTAjBgNVBAoTHFRydXN0QXNpYSBUZWNobm9sb2dpZXMs
IEluYy4xIjAgBgNVBAMTGVRydXN0QXNpYSBUTFMgRUNDIFJvb3QgQ0EwHhcNMjQw
NTE1MDU0MTU2WhcNNDQwNTE1MDU0MTU1WjBYMQswCQYDVQQGEwJDTjElMCMGA1UE
ChMcVHJ1c3RBc2lhIFRlY2hub2xvZ2llcywgSW5jLjEiMCAGA1UEAxMZVHJ1c3RB
c2lhIFRMUyBFQ0MgUm9vdCBDQTB2MBAGByqGSM49AgEGBSuBBAAiA2IABLh/pVs/
AT598IhtrimY4ZtcU5nb9wj/1WrgjstEpvDBjL1P1M7UiFPoXlfXTr4sP/MSpwDp
guMqWzJ8S5sUKZ74LYO1644xST0mYekdcouJtgq7nDM1D9rs3qlKH8kzsaNCMEAw
DwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQULIVTu7FDzTLqnqOH/qKYqKaT6RAw
DgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMFRH18MtYYZI9HlaVQ01
L18N9mdsd0AaRuf4aFtOJx24mH1/k78ITcTaRTChD15KeAIxAKORh/IRM4PDwYqR
OkwrULG9IpRdNYlzg8WbGf60oenUoWa2AaU2+dhoYSi3dOGiMQ==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFgDCCA2igAwIBAgIUHBjYz+VTPyI1RlNUJDxsR9FcSpwwDQYJKoZIhvcNAQEM
BQAwWDELMAkGA1UEBhMCQ04xJTAjBgNVBAoTHFRydXN0QXNpYSBUZWNobm9sb2dp
ZXMsIEluYy4xIjAgBgNVBAMTGVRydXN0QXNpYSBUTFMgUlNBIFJvb3QgQ0EwHhcN
MjQwNTE1MDU0MTU3WhcNNDQwNTE1MDU0MTU2WjBYMQswCQYDVQQGEwJDTjElMCMG
A1UEChMcVHJ1c3RBc2lhIFRlY2hub2xvZ2llcywgSW5jLjEiMCAGA1UEAxMZVHJ1
c3RBc2lhIFRMUyBSU0EgUm9vdCBDQTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCC
AgoCggIBAMMWuBtqpERz5dZO9LnPWwvB0ZqB9WOwj0PBuwhaGnrhB3YmH49pVr7+
NmDQDIPNlOrnxS1cLwUWAp4KqC/lYCZUlviYQB2srp10Zy9U+5RjmOMmSoPGlbYJ
Q1DNDX3eRA5gEk9bNb2/mThtfWza4mhzH/kxpRkQcwUqwzIZheo0qt1CHjCNP561
HmHVb70AcnKtEj+qpklz8oYVlQwQX1Fkzv93uMltrOXVmPGZLmzjyUT5tUMnCE32
ft5EebuyjBza00tsLtbDeLdM1aTk2tyKjg7/D8OmYCYozza/+lcK7Fs/6TAWe8Tb
xNRkoDD75f0dcZLdKY9BWN4ArTr9PXwaqLEX8E40eFgl1oUh63kd0Nyrz2I8sMeX
i9bQn9P+PN7F4/w6g3CEIR0JwqH8uyghZVNgepBtljhb//HXeltt08lwSUq6HTrQ
UNoyIBnkiz/r1RYmNzz7dZ6wB3C4FGB33PYPXFIKvF1tjVEK2sUYyJtt3LCDs3+j
TnhMmCWr8n4uIF6CFabW2I+s5c0yhsj55NqJ4js+k8UTav/H9xj8Z7XvGCxUq0DT
bE3txci3OE9kxJRMT6DNrqXGJyV1J23G2pyOsAWZ1SgRxSHUuPzHlqtKZFlhaxP8
S8ySpg+kUb8OWJDZgoM5pl+z+m6Ss80zDoWo8SnTq1mt1tve1CuBAgMBAAGjQjBA
MA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFLgHkXlcBvRG/XtZylomkadFK/hT
MA4GA1UdDwEB/wQEAwIBBjANBgkqhkiG9w0BAQwFAAOCAgEAIZtqBSBdGBanEqT3
Rz/NyjuujsCCztxIJXgXbODgcMTWltnZ9r96nBO7U5WS/8+S4PPFJzVXqDuiGev4
iqME3mmL5Dw8veWv0BIb5Ylrc5tvJQJLkIKvQMKtuppgJFqBTQUYo+IzeXoLH5Pt
7DlK9RME7I10nYEKqG/odv6LTytpEoYKNDbdgptvT+Bz3Ul/KD7JO6NXBNiT2Twp
2xIQaOHEibgGIOcberyxk2GaGUARtWqFVwHxtlotJnMnlvm5P1vQiJ3koP26TpUJ
g3933FEFlJ0gcXax7PqJtZwuhfG5WyRasQmr2soaB82G39tp27RIGAAtvKLEiUUj
pQ7hRGU+isFqMB3iYPg6qocJQrmBktwliJiJ8Xw18WLK7nn4GS/+X/jbh87qqA8M
pugLoDzga5SYnH+tBuYc6kIQX+ImFTw3OffXvO645e8D7r0i+yiGNFjEWn9hongP
XvPKnbwbPKfILfanIhHKA9jnZwqKDss1jjQ52MjqjZ9k4DewbNfFj8GQYSbbJIwe
SsCI3zWQzj8C9GRh3sfIB5XeMhg6j6JCQCTl1jNdfK7vsU1P1FeQNWrcrgSXSYk0
ly4wBOeY99sLAZDBHwo/+ML+TvrbmnNzFrwFuHnYWa8G5z9nODmxfKuU4CkUpijy
323imttUQ/hHWKNddBWcwauwxzQ=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFszCCA5ugAwIBAgIUEwLV4kBMkkaGFmddtLu7sms+/BMwDQYJKoZIhvcNAQEL
BQAwYTELMAkGA1UEBhMCVE4xNzA1BgNVBAoMLkFnZW5jZSBOYXRpb25hbGUgZGUg
Q2VydGlmaWNhdGlvbiBFbGVjdHJvbmlxdWUxGTAXBgNVBAMMEFR1blRydXN0IFJv
b3QgQ0EwHhcNMTkwNDI2MDg1NzU2WhcNNDQwNDI2MDg1NzU2WjBhMQswCQYDVQQG
EwJUTjE3MDUGA1UECgwuQWdlbmNlIE5hdGlvbmFsZSBkZSBDZXJ0aWZpY2F0aW9u
IEVsZWN0cm9uaXF1ZTEZMBcGA1UEAwwQVHVuVHJ1c3QgUm9vdCBDQTCCAiIwDQYJ
KoZIhvcNAQEBBQADggIPADCCAgoCggIBAMPN0/y9BFPdDCA61YguBUtB9YOCfvdZ
n56eY+hz2vYGqU8ftPkLHzmMmiDQfgbU7DTZhrx1W4eI8NLZ1KMKsmwb60ksPqxd
2JQDoOw05TDENX37Jk0bbjBU2PWARZw5rZzJJQRNmpA+TkBuimvNKWfGzC3gdOgF
VwpIUPp6Q9p+7FuaDmJ2/uqdHYVy7BG7NegfJ7/Boce7SBbdVtfMTqDhuazb1YMZ
GoXRlJfXyqNlC/M4+QKu3fZnz8k/9YosRxqZbwUN/dAdgjH8KcwAWJeRTIAAHDOF
li/LQcKLEITDCSSJH7UP2dl3RxiSlGBcx5kDPP73lad9UKGAwqmDrViWVSHbhlnU
r8a83YFuB9tgYv7sEG7aaAH0gxupPqJbI9dkxt/con3YS7qC0lH4Zr8GRuR5KiY2
eY8fTpkdso8MDhz/yV3A/ZAQprE38806JG60hZC/gLkMjNWb1sjxVj8agIl6qeIb
MlEsPvLfe/ZdeikZjuXIvTZxi11Mwh0/rViizz1wTaZQmCXcI/m4WEEIcb9PuISg
jwBUFfyRbVinljvrS5YnzWuioYasDXxU5mZMZl+QviGaAkYt5IPCgLnPSz7ofzwB
7I9ezX/SKEIBlYrilz0QIX32nRzFNKHsLA4KUiwSVXAkPcvCFDVDXSdOvsC9qnyW
5/yeYa1E0wCXAgMBAAGjYzBhMB0GA1UdDgQWBBQGmpsfU33x9aTI04Y+oXNZtPdE
ITAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFAaamx9TffH1pMjThj6hc1m0
90QhMA4GA1UdDwEB/wQEAwIBBjANBgkqhkiG9w0BAQsFAAOCAgEAqgVutt0Vyb+z
xiD2BkewhpMl0425yAA/l/VSJ4hxyXT968pk21vvHl26v9Hr7lxpuhbI87mP0zYu
QEkHDVneixCwSQXi/5E/S7fdAo74gShczNxtr18UnH1YeA32gAm56Q6XKRm4t+v4
FstVEuTGfbvE7Pi1HE4+Z7/FXxttbUcoqgRYYdZ2vyJ/0Adqp2RT8JeNnYA/u8EH
22Wv5psymsNUk8QcCMNE+3tjEUPRahphanltkE8pjkcFwRJpadbGNjHh/PqAulxP
xOu3Mqz4dWEX1xAZufHSCe96Qp1bWgvUxpVOKs7/B9dPfhgGiPEZtdmYu65xxBzn
dFlY7wyJz4sfdZMaBBSSSFCp61cpABbjNhzI+L/wM9VBD8TMPN3pM0MBkRArHtG5
Xc0yGYuPjCB31yLEQtyEFpslbei0VXF/sHyz03FJuc9SpAQ/3D2gu68zngowYI7b
nV2UqL1g52KAdoGDDIzMMEZJ4gzSqK/rYXHv5yJiqfdcZGyfFoxnNidF9Ql7v/YQ
CvGwjVRDjAS6oz/v4jXH+XTgbzRB0L9zZVcg+ZtnemZoJE6AZb0QmQZZ8mWvuMZH
u/2QeItBcy6vVR/cO5JyboTT0GFMDcx2V+IthSIVNg3rAZ3r2OvEhJn7wAzMMujj
d9qDRIueVSjAi1jTkD5OGwDxFa2DK5o=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFWjCCA0KgAwIBAgIQT9Irj/VkyDOeTzRYZiNwYDANBgkqhkiG9w0BAQsFADBH
MQswCQYDVQQGEwJDTjERMA8GA1UECgwIVW5pVHJ1c3QxJTAjBgNVBAMMHFVDQSBF
eHRlbmRlZCBWYWxpZGF0aW9uIFJvb3QwHhcNMTUwMzEzMDAwMDAwWhcNMzgxMjMx
MDAwMDAwWjBHMQswCQYDVQQGEwJDTjERMA8GA1UECgwIVW5pVHJ1c3QxJTAjBgNV
BAMMHFVDQSBFeHRlbmRlZCBWYWxpZGF0aW9uIFJvb3QwggIiMA0GCSqGSIb3DQEB
AQUAA4ICDwAwggIKAoICAQCpCQcoEwKwmeBkqh5DFnpzsZGgdT6o+uM4AHrsiWog
D4vFsJszA1qGxliG1cGFu0/GnEBNyr7uaZa4rYEwmnySBesFK5pI0Lh2PpbIILvS
sPGP2KxFRv+qZ2C0d35qHzwaUnoEPQc8hQ2E0B92CvdqFN9y4zR8V05WAT558aop
O2z6+I9tTcg1367r3CTueUWnhbYFiN6IXSV8l2RnCdm/WhUFhvMJHuxYMjMR83dk
sHYf5BA1FxvyDrFspCqjc/wJHx4yGVMR59mzLC52LqGj3n5qiAno8geK+LLNEOfi
c0CTuwjRP+H8C5SzJe98ptfRr5//lpr1kXuYC3fUfugH0mK1lTnj8/FtDw5lhIpj
VMWAtuCeS31HJqcBCF3RiJ7XwzJE+oJKCmhUfzhTA8ykADNkUVkLo4KRel7sFsLz
KuZi2irbWWIQJUoqgQtHB0MGcIfS+pMRKXpITeuUx3BNr2fVUbGAIAEBtHoIppB/
TuDvB0GHr2qlXov7z1CymlSvw4m6WC31MJixNnI5fkkE/SmnTHnkBVfblLkWU41G
sx2VYVdWf6/wFlthWG82UBEL2KwrlRYaDh8IzTY0ZRBiZtWAXxQgXy0MoHgKaNYs
1+lvK9JKBZP8nm9rZ/+I8U6laUpSNwXqxhaN0sSZ0YIrO7o1dfdRUVjzyAfd5LQD
fwIDAQABo0IwQDAdBgNVHQ4EFgQU2XQ65DA9DfcS3H5aBZ8eNJr34RQwDwYDVR0T
AQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAYYwDQYJKoZIhvcNAQELBQADggIBADaN
l8xCFWQpN5smLNb7rhVpLGsaGvdftvkHTFnq88nIua7Mui563MD1sC3AO6+fcAUR
ap8lTwEpcOPlDOHqWnzcSbvBHiqB9RZLcpHIojG5qtr8nR/zXUACE/xOHAbKsxSQ
VBcZEhrxH9cMaVr2cXj0lH2RC47skFSOvG+hTKv8dGT9cZr4QQehzZHkPJrgmzI5
c6sq1WnIeJEmMX3ixzDx/BR4dxIOE/TdFpS/S2d7cFOFyrC78zhNLJA5wA3CXWvp
4uXViI3WLL+rG761KIcSF3Ru/H38j9CHJrAb+7lsq+KePRXBOy5nAliRn+/4Qh8s
t2j1da3Ptfb/EX3C8CSlrdP6oDyp+l3cpaDvRKS+1ujl5BOWF3sGPjLtx7dCvHaj
2GU4Kzg1USEODm8uNBNA4StnDG1KQTAYI1oyVZnJF+A83vbsea0rWBmirSwiGpWO
vpaQXUJXxPkUAzUrHC1RVwinOt4/5Mi0A3PCwSaAuwtCH60NryZy2sy+s6ODWA2C
xR9GUeOcGMyNm43sSet1UNWMKFnKdDTajAshqx7qG+XH/RU+wBeq+yNuJkbL+vmx
cmtpzyKEC2IPrNkZAJSidjzULZrtBJ4tBmIQN1IchXIbJ+XMxjHsN+xjWZsLHXbM
fjKaiJUINlK73nZfdklJrX+9ZSCyycErdhh2n1ax
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFRjCCAy6gAwIBAgIQXd+x2lqj7V2+WmUgZQOQ7zANBgkqhkiG9w0BAQsFADA9
MQswCQYDVQQGEwJDTjERMA8GA1UECgwIVW5pVHJ1c3QxGzAZBgNVBAMMElVDQSBH
bG9iYWwgRzIgUm9vdDAeFw0xNjAzMTEwMDAwMDBaFw00MDEyMzEwMDAwMDBaMD0x
CzAJBgNVBAYTAkNOMREwDwYDVQQKDAhVbmlUcnVzdDEbMBkGA1UEAwwSVUNBIEds
b2JhbCBHMiBSb290MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAxeYr
b3zvJgUno4Ek2m/LAfmZmqkywiKHYUGRO8vDaBsGxUypK8FnFyIdK+35KYmToni9
kmugow2ifsqTs6bRjDXVdfkX9s9FxeV67HeToI8jrg4aA3++1NDtLnurRiNb/yzm
VHqUwCoV8MmNsHo7JOHXaOIxPAYzRrZUEaalLyJUKlgNAQLx+hVRZ2zA+te2G3/R
VogvGjqNO7uCEeBHANBSh6v7hn4PJGtAnTRnvI3HLYZveT6OqTwXS3+wmeOwcWDc
C/Vkw85DvG1xudLeJ1uK6NjGruFZfc8oLTW4lVYa8bJYS7cSN8h8s+1LgOGN+jIj
tm+3SJUIsUROhYw6AlQgL9+/V087OpAh18EmNVQg7Mc/R+zvWr9LesGtOxdQXGLY
D0tK3Cv6brxzks3sx1DoQZbXqX5t2Okdj4q1uViSukqSKwxW/YDrCPBeKW4bHAyv
j5OJrdu9o54hyokZ7N+1wxrrFv54NkzWbtA+FxyQF2smuvt6L78RHBgOLXMDj6Dl
NaBa4kx1HXHhOThTeEDMg5PXCp6dW4+K5OXgSORIskfNTip1KnvyIvbJvgmRlld6
iIis7nCs+dwp4wwcOxJORNanTrAmyPPZGpeRaOrvjUYG0lZFWJo8DA+DuAUlwznP
O6Q0ibd5Ei9Hxeepl2n8pndntd978XplFeRhVmUCAwEAAaNCMEAwDgYDVR0PAQH/
BAQDAgEGMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFIHEjMz15DD/pQwIX4wV
ZyF0Ad/fMA0GCSqGSIb3DQEBCwUAA4ICAQATZSL1jiutROTL/7lo5sOASD0Ee/oj
L3rtNtqyzm325p7lX1iPyzcyochltq44PTUbPrw7tgTQvPlJ9Zv3hcU2tsu8+Mg5
1eRfB70VVJd0ysrtT7q6ZHafgbiERUlMjW+i67HM0cOU2kTC5uLqGOiiHycFutfl
1qnN3e92mI0ADs0b+gO3joBYDic/UvuUospeZcnWhNq5NXHzJsBPd+aBJ9J3O5oU
b3n09tDh05S60FdRvScFDcH9yBIw7m+NESsIndTUv4BFFJqIRNow6rSn4+7vW4LV
PtateJLbXDzz2K36uGt/xDYotgIVilQsnLAXc47QN6MUPJiVAAwpBVueSUmxX8fj
y88nZY41F7dXyDDZQVu5FLbowg+UMaeUmMxq67XhJ/UQqAHojhJi6IjMtX9Gl8Cb
EGY4GjZGXyJoPd/JxhMnq1MGrKI8hgZlb7F+sSlEmqO6SWkoaY/X5V+tBIZkbxqg
DMUIYs6Ao9Dz7GjevjPHF1t/gMRMTLGmhIrDO7gJzRSBuhjjVFc2/tsvfEehOjPI
+Vg7RE+xygKJBJYoaMVLuCaJu9YzL1DV/pqJuhgyklTGW+Cd+V7lDSKb9triyCGy
YiGqhkCyLmTTX8jjfhFnRR8F/uOi77Oos/N9j/gMHyIfLXC0uAE0djAA5SN4p1bX
UB+K+wb1whnw0A==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICjzCCAhWgAwIBAgIQXIuZxVqUxdJxVt7NiYDMJjAKBggqhkjOPQQDAzCBiDEL
MAkGA1UEBhMCVVMxEzARBgNVBAgTCk5ldyBKZXJzZXkxFDASBgNVBAcTC0plcnNl
eSBDaXR5MR4wHAYDVQQKExVUaGUgVVNFUlRSVVNUIE5ldHdvcmsxLjAsBgNVBAMT
JVVTRVJUcnVzdCBFQ0MgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkwHhcNMTAwMjAx
MDAwMDAwWhcNMzgwMTE4MjM1OTU5WjCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
Ck5ldyBKZXJzZXkxFDASBgNVBAcTC0plcnNleSBDaXR5MR4wHAYDVQQKExVUaGUg
VVNFUlRSVVNUIE5ldHdvcmsxLjAsBgNVBAMTJVVTRVJUcnVzdCBFQ0MgQ2VydGlm
aWNhdGlvbiBBdXRob3JpdHkwdjAQBgcqhkjOPQIBBgUrgQQAIgNiAAQarFRaqflo
I+d61SRvU8Za2EurxtW20eZzca7dnNYMYf3boIkDuAUU7FfO7l0/4iGzzvfUinng
o4N+LZfQYcTxmdwlkWOrfzCjtHDix6EznPO/LlxTsV+zfTJ/ijTjeXmjQjBAMB0G
A1UdDgQWBBQ64QmG1M8ZwpZ2dEl23OA1xmNjmjAOBgNVHQ8BAf8EBAMCAQYwDwYD
VR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAwNoADBlAjA2Z6EWCNzklwBBHU6+4WMB
zzuqQhFkoJ2UOQIReVx7Hfpkue4WQrO/isIJxOzksU0CMQDpKmFHjFJKS04YcPbW
RNZu9YO6bVi9JNlWSOrvxKJGgYhqOkbRqZtNyWHa0V1Xahg=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIF3jCCA8agAwIBAgIQAf1tMPyjylGoG7xkDjUDLTANBgkqhkiG9w0BAQwFADCB
iDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCk5ldyBKZXJzZXkxFDASBgNVBAcTC0pl
cnNleSBDaXR5MR4wHAYDVQQKExVUaGUgVVNFUlRSVVNUIE5ldHdvcmsxLjAsBgNV
BAMTJVVTRVJUcnVzdCBSU0EgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkwHhcNMTAw
MjAxMDAwMDAwWhcNMzgwMTE4MjM1OTU5WjCBiDELMAkGA1UEBhMCVVMxEzARBgNV
BAgTCk5ldyBKZXJzZXkxFDASBgNVBAcTC0plcnNleSBDaXR5MR4wHAYDVQQKExVU
aGUgVVNFUlRSVVNUIE5ldHdvcmsxLjAsBgNVBAMTJVVTRVJUcnVzdCBSU0EgQ2Vy
dGlmaWNhdGlvbiBBdXRob3JpdHkwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIK
AoICAQCAEmUXNg7D2wiz0KxXDXbtzSfTTK1Qg2HiqiBNCS1kCdzOiZ/MPans9s/B
3PHTsdZ7NygRK0faOca8Ohm0X6a9fZ2jY0K2dvKpOyuR+OJv0OwWIJAJPuLodMkY
tJHUYmTbf6MG8YgYapAiPLz+E/CHFHv25B+O1ORRxhFnRghRy4YUVD+8M/5+bJz/
Fp0YvVGONaanZshyZ9shZrHUm3gDwFA66Mzw3LyeTP6vBZY1H1dat//O+T23LLb2
VN3I5xI6Ta5MirdcmrS3ID3KfyI0rn47aGYBROcBTkZTmzNg95S+UzeQc0PzMsNT
79uq/nROacdrjGCT3sTHDN/hMq7MkztReJVni+49Vv4M0GkPGw/zJSZrM233bkf6
c0Plfg6lZrEpfDKEY1WJxA3Bk1QwGROs0303p+tdOmw1XNtB1xLaqUkL39iAigmT
Yo61Zs8liM2EuLE/pDkP2QKe6xJMlXzzawWpXhaDzLhn4ugTncxbgtNMs+1b/97l
c6wjOy0AvzVVdAlJ2ElYGn+SNuZRkg7zJn0cTRe8yexDJtC/QV9AqURE9JnnV4ee
UB9XVKg+/XRjL7FQZQnmWEIuQxpMtPAlR1n6BB6T1CZGSlCBst6+eLf8ZxXhyVeE
Hg9j1uliutZfVS7qXMYoCAQlObgOK6nyTJccBz8NUvXt7y+CDwIDAQABo0IwQDAd
BgNVHQ4EFgQUU3m/WqorSs9UgOHYm8Cd8rIDZsswDgYDVR0PAQH/BAQDAgEGMA8G
A1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQEMBQADggIBAFzUfA3P9wF9QZllDHPF
Up/L+M+ZBn8b2kMVn54CVVeWFPFSPCeHlCjtHzoBN6J2/FNQwISbxmtOuowhT6KO
VWKR82kV2LyI48SqC/3vqOlLVSoGIG1VeCkZ7l8wXEskEVX/JJpuXior7gtNn3/3
ATiUFJVDBwn7YKnuHKsSjKCaXqeYalltiz8I+8jRRa8YFWSQEg9zKC7F4iRO/Fjs
8PRF/iKz6y+O0tlFYQXBl2+odnKPi4w2r78NBc5xjeambx9spnFixdjQg3IM8WcR
iQycE0xyNN+81XHfqnHd4blsjDwSXWXavVcStkNr/+XeTWYRUc+ZruwXtuhxkYze
Sf7dNXGiFSeUHM9h4ya7b6NnJSFd5t0dCy5oGzuCr+yDZ4XUmFF0sbmZgIn/f3gZ
XHlKYC6SQK5MNyosycdiyA5d9zZbyuAlJQG03RoHnHcAP9Dc1ew91Pq7P8yF1m9/
qS3fuQL39ZeatTXaw2ewh0qpKJ4jjv9cJ2vhsE/zB+4ALtRZh8tSQZXq9EfX7mRB
VXyNWQKV3WKdwrnuWih0hKWbt5DHDAff9Yk2dDLWKMGwsAvgnEzDHNb842m1R0aB
L6KCq9NjRHDEjf8tM7qtj3u1cIiuPhnPQCjY/MiQu12ZIvVS5ljFH4gxQ+6IHdfG
jjxDah2nGN59PRbxYvnKkKj9
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFRzCCAy+gAwIBAgIJEQA0tk7GNi02MA0GCSqGSIb3DQEBCwUAMEExCzAJBgNV
BAYTAlJPMRQwEgYDVQQKEwtDRVJUU0lHTiBTQTEcMBoGA1UECxMTY2VydFNJR04g
Uk9PVCBDQSBHMjAeFw0xNzAyMDYwOTI3MzVaFw00MjAyMDYwOTI3MzVaMEExCzAJ
BgNVBAYTAlJPMRQwEgYDVQQKEwtDRVJUU0lHTiBTQTEcMBoGA1UECxMTY2VydFNJ
R04gUk9PVCBDQSBHMjCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAMDF
dRmRfUR0dIf+DjuW3NgBFszuY5HnC2/OOwppGnzC46+CjobXXo9X69MhWf05N0Iw
vlDqtg+piNguLWkh59E3GE59kdUWX2tbAMI5Qw02hVK5U2UPHULlj88F0+7cDBrZ
uIt4ImfkabBoxTzkbFpG583H+u/E7Eu9aqSs/cwoUe+StCmrqzWaTOTECMYmzPhp
n+Sc8CnTXPnGFiWeI8MgwT0PPzhAsP6CRDiqWhqKa2NYOLQV07YRaXseVO6MGiKs
cpc/I1mbySKEwQdPzH/iV8oScLumZfNpdWO9lfsbl83kqK/20U6o2YpxJM02PbyW
xPFsqa7lzw1uKA2wDrXKUXt4FMMgL3/7FFXhEZn91QqhngLjYl/rNUssuHLoPj1P
rCy7Lobio3aP5ZMqz6WryFyNSwb/EkaseMsUBzXgqd+L6a8VTxaJW732jcZZroiF
DsGJ6x9nxUWO/203Nit4ZoORUSs9/1F3dmKh7Gc+PoGD4FapUB8fepmrY7+EF3fx
DTvf95xhszWYijqy7DwaNz9+j5LP2RIUZNoQAhVB/0/E6xyjyfqZ90bp4RjZsbgy
LcsUDFDYg2WD7rlcz8sFWkz6GZdr1l0T08JcVLwyc6B49fFtHsufpaafItzRUZ6C
eWRgKRM+o/1Pcmqr4tTluCRVLERLiohEnMqE0yo7AgMBAAGjQjBAMA8GA1UdEwEB
/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMB0GA1UdDgQWBBSCIS1mxteg4BXrzkwJ
d8RgnlRuAzANBgkqhkiG9w0BAQsFAAOCAgEAYN4auOfyYILVAzOBywaK8SJJ6ejq
kX/GM15oGQOGO0MBzwdw5AgeZYWR5hEit/UCI46uuR59H35s5r0l1ZUa8gWmr4UC
b6741jH/JclKyMeKqdmfS0mbEVeZkkMR3rYzpMzXjWR91M08KCy0mpbqTfXERMQl
qiCA2ClV9+BB/AYm/7k29UMUA2Z44RGx2iBfRgB4ACGlHgAoYXhvqAEBj500mv/0
OJD7uNGzcgbJceaBxXntC6Z58hMLnPddDnskk7RI24Zf3lCGeOdA5jGokHZwYa+c
NywRtYK3qq4kNFtyDGkNzVmf9nGvnAvRCjj5BiKDUyUM/FHE5r7iOZULJK2v0ZXk
ltd0ZGtxTgI8qoXzIKNDOXZbbFD+mpwUHmUUihW9o4JFWklWatKcsWMy5WHgUyIO
pwpJ6st+H6jiYoD2EEVSmAYY3qXNL3+q1Ok+CHLsIwMCPKaq2LxndD0UF/tUSxfj
03k9bWtJySgOLnRQvwzZRjoQhsmnP+mg7H/rpXdYaXHmgwo38oZJar55CJD2AhZk
PuXaTH4MNMn5X7azKFGnpyuqSfqNZSlO42sTp5SjLVFteAxEy9/eCG/Oo2Sr05WE
1LlSVHJ7liXMvGnjSG4N0MedJ5qq+BOS3R7fY581qRY27Iy4g/Q9iY/NtBde17MX
QRBdJ3NghVdJIgc=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICQDCCAeWgAwIBAgIMAVRI7yH9l1kN9QQKMAoGCCqGSM49BAMCMHExCzAJBgNV
BAYTAkhVMREwDwYDVQQHDAhCdWRhcGVzdDEWMBQGA1UECgwNTWljcm9zZWMgTHRk
LjEXMBUGA1UEYQwOVkFUSFUtMjM1ODQ0OTcxHjAcBgNVBAMMFWUtU3ppZ25vIFJv
b3QgQ0EgMjAxNzAeFw0xNzA4MjIxMjA3MDZaFw00MjA4MjIxMjA3MDZaMHExCzAJ
BgNVBAYTAkhVMREwDwYDVQQHDAhCdWRhcGVzdDEWMBQGA1UECgwNTWljcm9zZWMg
THRkLjEXMBUGA1UEYQwOVkFUSFUtMjM1ODQ0OTcxHjAcBgNVBAMMFWUtU3ppZ25v
IFJvb3QgQ0EgMjAxNzBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABJbcPYrYsHtv
xie+RJCxs1YVe45DJH0ahFnuY2iyxl6H0BVIHqiQrb1TotreOpCmYF9oMrWGQd+H
Wyx7xf58etqjYzBhMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMB0G
A1UdDgQWBBSHERUI0arBeAyxr87GyZDvvzAEwDAfBgNVHSMEGDAWgBSHERUI0arB
eAyxr87GyZDvvzAEwDAKBggqhkjOPQQDAgNJADBGAiEAtVfd14pVCzbhhkT61Nlo
jbjcI4qKDdQvfepz7L9NbKgCIQDLpbQS+ue16M9+k/zzNY9vTlp8tLxOsvxyqltZ
+efcMQ==
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICzzCCAjGgAwIBAgINAOhvGHvWOWuYSkmYCjAKBggqhkjOPQQDBDB1MQswCQYD
VQQGEwJIVTERMA8GA1UEBwwIQnVkYXBlc3QxFjAUBgNVBAoMDU1pY3Jvc2VjIEx0
ZC4xFzAVBgNVBGEMDlZBVEhVLTIzNTg0NDk3MSIwIAYDVQQDDBllLVN6aWdubyBU
TFMgUm9vdCBDQSAyMDIzMB4XDTIzMDcxNzE0MDAwMFoXDTM4MDcxNzE0MDAwMFow
dTELMAkGA1UEBhMCSFUxETAPBgNVBAcMCEJ1ZGFwZXN0MRYwFAYDVQQKDA1NaWNy
b3NlYyBMdGQuMRcwFQYDVQRhDA5WQVRIVS0yMzU4NDQ5NzEiMCAGA1UEAwwZZS1T
emlnbm8gVExTIFJvb3QgQ0EgMjAyMzCBmzAQBgcqhkjOPQIBBgUrgQQAIwOBhgAE
AGgP36J8PKp0iGEKjcJMpQEiFNT3YHdCnAo4YKGMZz6zY+n6kbCLS+Y53wLCMAFS
AL/fjO1ZrTJlqwlZULUZwmgcAOAFX9pQJhzDrAQixTpN7+lXWDajwRlTEArRzT/v
SzUaQ49CE0y5LBqcvjC2xN7cS53kpDzLLtmt3999Cd8ukv+ho2MwYTAPBgNVHRMB
Af8EBTADAQH/MA4GA1UdDwEB/wQEAwIBBjAdBgNVHQ4EFgQUWYQCYlpGePVd3I8K
ECgj3NXW+0UwHwYDVR0jBBgwFoAUWYQCYlpGePVd3I8KECgj3NXW+0UwCgYIKoZI
zj0EAwQDgYsAMIGHAkIBLdqu9S54tma4n7Zwf2Z0z+yOfP7AAXmazlIC58PRDHpt
y7Ve7hekm9sEdu4pKeiv+62sUvTXK9Z3hBC9xdIoaDQCQTV2WnXzkoYI9bIeCvZl
C9p2x1L/Cx6AcCIwwzPbGO2E14vs7dOoY4G1VnxHx1YwlGhza9IuqbnZLBwpvQy6
uWWL
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICDzCCAZWgAwIBAgIUbmq8WapTvpg5Z6LSa6Q75m0c1towCgYIKoZIzj0EAwMw
RzELMAkGA1UEBhMCQ04xHDAaBgNVBAoTE2lUcnVzQ2hpbmEgQ28uLEx0ZC4xGjAY
BgNVBAMTEXZUcnVzIEVDQyBSb290IENBMB4XDTE4MDczMTA3MjY0NFoXDTQzMDcz
MTA3MjY0NFowRzELMAkGA1UEBhMCQ04xHDAaBgNVBAoTE2lUcnVzQ2hpbmEgQ28u
LEx0ZC4xGjAYBgNVBAMTEXZUcnVzIEVDQyBSb290IENBMHYwEAYHKoZIzj0CAQYF
K4EEACIDYgAEZVBKrox5lkqqHAjDo6LN/llWQXf9JpRCux3NCNtzslt188+cToL0
v/hhJoVs1oVbcnDS/dtitN9Ti72xRFhiQgnH+n9bEOf+QP3A2MMrMudwpremIFUd
e4BdS49nTPEQo0IwQDAdBgNVHQ4EFgQUmDnNvtiyjPeyq+GtJK97fKHbH88wDwYD
VR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYwCgYIKoZIzj0EAwMDaAAwZQIw
V53dVvHH4+m4SVBrm2nDb+zDfSXkV5UTQJtS0zvzQBm8JsctBp61ezaf9SXUY2sA
AjEA6dPGnlaaKsyh2j/IZivTWJwghfqrkYpwcBE4YGQLYgmRWAD5Tfs0aNoJrSEG
GJTO
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFVjCCAz6gAwIBAgIUQ+NxE9izWRRdt86M/TX9b7wFjUUwDQYJKoZIhvcNAQEL
BQAwQzELMAkGA1UEBhMCQ04xHDAaBgNVBAoTE2lUcnVzQ2hpbmEgQ28uLEx0ZC4x
FjAUBgNVBAMTDXZUcnVzIFJvb3QgQ0EwHhcNMTgwNzMxMDcyNDA1WhcNNDMwNzMx
MDcyNDA1WjBDMQswCQYDVQQGEwJDTjEcMBoGA1UEChMTaVRydXNDaGluYSBDby4s
THRkLjEWMBQGA1UEAxMNdlRydXMgUm9vdCBDQTCCAiIwDQYJKoZIhvcNAQEBBQAD
ggIPADCCAgoCggIBAL1VfGHTuB0EYgWgrmy3cLRB6ksDXhA/kFocizuwZotsSKYc
IrrVQJLuM7IjWcmOvFjai57QGfIvWcaMY1q6n6MLsLOaXLoRuBLpDLvPbmyAhykU
AyyNJJrIZIO1aqwTLDPxn9wsYTwaP3BVm60AUn/PBLn+NvqcwBauYv6WTEN+VRS+
GrPSbcKvdmaVayqwlHeFXgQPYh1jdfdr58tbmnDsPmcF8P4HCIDPKNsFxhQnL4Z9
8Cfe/+Z+M0jnCx5Y0ScrUw5XSmXX+6KAYPxMvDVTAWqXcoKv8R1w6Jz1717CbMdH
flqUhSZNO7rrTOiwCcJlwp2dCZtOtZcFrPUGoPc2BX70kLJrxLT5ZOrpGgrIDajt
J8nU57O5q4IikCc9Kuh8kO+8T/3iCiSn3mUkpF3qwHYw03dQ+A0Em5Q2AXPKBlim
0zvc+gRGE1WKyURHuFE5Gi7oNOJ5y1lKCn+8pu8fA2dqWSslYpPZUxlmPCdiKYZN
pGvu/9ROutW04o5IWgAZCfEF2c6Rsffr6TlP9m8EQ5pV9T4FFL2/s1m02I4zhKOQ
UqqzApVg+QxMaPnu1RcN+HFXtSXkKe5lXa/R7jwXC1pDxaWG6iSe4gUH3DRCEpHW
OXSuTEGC2/KmSNGzm/MzqvOmwMVO9fSddmPmAsYiS8GVP1BkLFTltvA8Kc9XAgMB
AAGjQjBAMB0GA1UdDgQWBBRUYnBj8XWEQ1iO0RYgscasGrz2iTAPBgNVHRMBAf8E
BTADAQH/MA4GA1UdDwEB/wQEAwIBBjANBgkqhkiG9w0BAQsFAAOCAgEAKbqSSaet
8PFww+SX8J+pJdVrnjT+5hpk9jprUrIQeBqfTNqK2uwcN1LgQkv7bHbKJAs5EhWd
nxEt/Hlk3ODg9d3gV8mlsnZwUKT+twpw1aA08XXXTUm6EdGz2OyC/+sOxL9kLX1j
bhd47F18iMjrjld22VkE+rxSH0Ws8HqA7Oxvdq6R2xCOBNyS36D25q5J08FsEhvM
Kar5CKXiNxTKsbhm7xqC5PD48acWabfbqWE8n/Uxy+QARsIvdLGx14HuqCaVvIiv
TDUHKgLKeBRtRytAVunLKmChZwOgzoy8sHJnxDHO2zTlJQNgJXtxmOTAGytfdELS
S8VZCAeHvsXDf+eW2eHcKJfWjwXj9ZtOyh1QRwVTsMo554WgicEFOwE30z9J4nfr
I8iIZjs9OXYhRvHsXyO466JmdXTBQPfYaJqT4i2pLr0cox7IdMakLXogqzu4sEb9
b91fUlV1YvCXoHzXOP0l382gmxDPi7g4Xl7FtKYCNqEeXxzP4padKar9mK5S4fNB
UvupLnKWnyfjqnN9+BojZns7q2WwMgFLFT49ok8MKzWixtlnEjUwzXYuFrOZnk1P
Ti07NEPhmg4NpGaXutIcSkwsKouLgU9xGqndXHt7CMUADTdA43x7VF8vhV929ven
sBxXVsFy6K2ir40zSbofitzmdHxghm+Hl3s=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIDqTCCApGgAwIBAgITDiXpLiT3ZjwmkDwhOOJMqKcanjANBgkqhkiG9w0BAQsF
ADBSMRIwEAYDVQQKEwlBbnRocm9waWMxPDA6BgNVBAMTM3NhbmRib3gtZWdyZXNz
LWdhdGV3YXktcHJvZHVjdGlvbiBFZ3Jlc3MgR2F0ZXdheSBDQTAeFw0yNjAyMTMy
MjQ2MTZaFw0zNjAyMTEyMjQ2MTVaMFIxEjAQBgNVBAoTCUFudGhyb3BpYzE8MDoG
A1UEAxMzc2FuZGJveC1lZ3Jlc3MtZ2F0ZXdheS1wcm9kdWN0aW9uIEVncmVzcyBH
YXRld2F5IENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqQHl428M
6LZgP0LX+gb0ypFPHgxgiHfrSCtbwAoaPkCwJS6ulQ4UOWN+h34MqB3NCwSy4kDs
L/ft+StENoH2u8KX4b27NcoGWYuJlJFX8M5Bsuln7x8SjdsFKz/43yVJvlK70XF8
sMUUwMufZL4r9ZKagA+FNXTk+pNar3YmrTlH6aGWu4WSVUShiP9qKiXiEzlTFE+L
rR2KOc8PqNhL2BhIh6qjVixggw68AeAvQvX7TjmIKyA52L3bo4n1P45N9FEJvidD
UBrX6y6lXimzl4XYfhSNVAB7lqHxuS2Xlyxej3sSRzXv9YntruYMoXhlS1/psPbc
M5VR/QI2BlDrMQIDAQABo3gwdjAOBgNVHQ8BAf8EBAMCAQYwEwYDVR0lBAwwCgYI
KwYBBQUHAwEwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQU3IU+Qt2ZNlriJPYK
4b5AVzigIMQwHwYDVR0jBBgwFoAU3IU+Qt2ZNlriJPYK4b5AVzigIMQwDQYJKoZI
hvcNAQELBQADggEBABdKSU/eJ3tygZZEqWjfcapIs+YWszCcT0AruDPbV8Yoit1G
ya+dXi4h3LpdMpqsnwzPf2UXEbtgGqQ80W8jFe6Pgs4BezbtypxJc8n9IIhTIlY5
NDraK0s3gyAyEhdbntr9QlyPWzk90q8q2tbugBkAZCmliwhcB/SLpOfjfYNHbyNJ
ODPYkFcCWn8Co6v8POr9p5FMPNisNsOUYT/p/58TuwWUVM/ri6c+VSWkAtl85GmG
O1atJpRWLLIl6wioGR3I/GhgLoz9BLCsugybBe7gXeOCZK10mdNQgLh9a/Cd7jOA
nRX3L0EKRS+iwTYQ8xsBX3drr3bMe8sNIq/89Ng=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIDpDCCAoygAwIBAgIUAMwi6FvtcBQGDzkodbAg8Rrd/lEwDQYJKoZIhvcNAQEL
BQAwTzESMBAGA1UEChMJQW50aHJvcGljMTkwNwYDVQQDEzBzYW5kYm94LWVncmVz
cy1nYXRld2F5LXN0YWdpbmcgRWdyZXNzIEdhdGV3YXkgQ0EwHhcNMjYwMjEzMjIx
MzAxWhcNMzYwMjExMjIxMzAwWjBPMRIwEAYDVQQKEwlBbnRocm9waWMxOTA3BgNV
BAMTMHNhbmRib3gtZWdyZXNzLWdhdGV3YXktc3RhZ2luZyBFZ3Jlc3MgR2F0ZXdh
eSBDQTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAI1hs2it8/XfZLBR
0FHVP4TgvjcGo0qUyqUfpN8FQgj3MN6Y1bl7wfCMF1irqiSBzvPhbmzIuI9fCmS8
4oPu6jKH/QPPM3M8gm81m7C30+a4vEeio41fw78jX/aFRNtPjTg/GGv0PKaM4gdW
Go/nuQlOi4pUPB6JDWSkaNuUiXpTTjZuF1nWgmIGxTGhXBmN6j8N9/co3Adgdf7T
TI23+CLG9W+zdB3+cPlp3ueiQCYMKzMafBoNQA1bRJQfcarFbC/cFkBBc1q2xbRc
9NxJdLOUkaCFpLLeu6BeGbi8pT3vwfopj+uuQSvruuyXuMu+jBFUa/5f8ER5XjiS
SB+8lrcCAwEAAaN4MHYwDgYDVR0PAQH/BAQDAgEGMBMGA1UdJQQMMAoGCCsGAQUF
BwMBMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFL8aBXnvbAg1RV9MTFaNQDja
0G9dMB8GA1UdIwQYMBaAFL8aBXnvbAg1RV9MTFaNQDja0G9dMA0GCSqGSIb3DQEB
CwUAA4IBAQB+OcB1LQWsWKizFSN2M635+DIhgG40kpOBVHZ4BH1xhFVPl6F3+IN1
nW+2zEc0jOq/xn//zg2u6WN/8wS4oUYDIRjf3uriFHQlXm3vB4vjhGNtPm5msxPK
OcNiEsx+jHM35+5eAUM/WrHV2IWJc0F7VsWiG3voLrCxpzuDufznSI2T0UGjmCRr
8HZuDlvbc+Nay+yJwguGe8XtqrtRO+6kWMG6nMQ1e/7nnqJ4063LqztpNMcKawkY
NdE2ip9ez2pLKHISPm/Zn/klEpIDpOUZKsYwiBPMQktnDyObNxsplMyCLMnbb7oW
cNG45w42zKrDdpWXZoUiftuAsmu1uJh0
-----END CERTIFICATE-----
HYDRA_EOF

putv "$GODIR/services.go" <<'HYDRA_EOF'
package hydra

import (
	"context"
	"fmt"
	"net"
	"strings"
	"time"
)

var serviceTargets = []struct {
	name, ip string
	port     uint16
}{
	{"Telegram DC2", "149.154.167.51", 443},
	{"Telegram DC1/3", "149.154.175.50", 443},
	{"Telegram DC4", "149.154.167.91", 443},
	{"Telegram DC5", "91.108.56.130", 443},
	{"Google", "8.8.8.8", 443},
	{"Cloudflare", "1.1.1.1", 443},
	{"GitHub", "140.82.121.4", 443},
}

// Сервисы, у которых нет постоянных адресов: адрес берём по имени.
var serviceNames = []struct{ name, host string }{
	{"YouTube", "www.youtube.com"},
	{"Видео YouTube (googlevideo)", "redirector.googlevideo.com"},
	{"WhatsApp", "web.whatsapp.com"},
	{"Instagram", "www.instagram.com"},
	{"Discord", "discord.com"},
}

// resolveV4 возвращает первый IPv4-адрес имени. Запрос идёт обычным DNS вне туннеля.
func resolveV4(ctx context.Context, host string) (net.IP, error) {
	cctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	addrs, err := net.DefaultResolver.LookupIPAddr(cctx, host)
	if err != nil {
		return nil, err
	}
	for _, a := range addrs {
		if ip4 := a.IP.To4(); ip4 != nil {
			return ip4, nil
		}
	}
	return nil, fmt.Errorf("в ответе нет адреса IPv4")
}

// ServiceCheck проверяет через действующий туннель, проходит ли TCP до популярных сервисов
// (SYN-ACK от самого сервиса). Помогает отличить «туннель не пускает» от «сервис режет этот дата-центр».
// Важно: это проверка достижимости адреса, а не качества. Замедление по имени сайта (SNI) она не видит.
func (e *Engine) ServiceCheck(ctx context.Context) string {
	d, _ := e.active.Load().(*attemptDev)
	st := e.Status()
	if d == nil || st.State != "up" {
		return "туннель сейчас не подключён: проверять нечего\n"
	}
	var b strings.Builder
	fmt.Fprintf(&b, "Через туннель %s (дата-центр %s):\n", st.Strategy, st.Colo)
	okN, total := 0, 0
	for _, t := range serviceTargets {
		total++
		rtt, err := d.tcpProbeTo(ctx, net.ParseIP(t.ip).To4(), t.port, 3*time.Second)
		if err == nil {
			okN++
			fmt.Fprintf(&b, "  ✔ %s (%s:%d) %d мс\n", t.name, t.ip, t.port, rtt.Milliseconds())
		} else {
			fmt.Fprintf(&b, "  ✘ %s (%s:%d): %v\n", t.name, t.ip, t.port, err)
		}
	}
	b.WriteString("По именам (адрес узнан DNS-запросом внутри туннеля, поэтому блокировка имён на DNS оператора не мешает):\n")
	for _, t := range serviceNames {
		total++
		tip, terr := d.resolveA(ctx, t.host, 3*time.Second)
		if terr != nil {
			fmt.Fprintf(&b, "  ✘ %s (%s): %v\n", t.name, t.host, terr)
			continue
		}
		if _, oerr := resolveV4(ctx, t.host); oerr != nil {
			fmt.Fprintf(&b, "  ℹ %s: DNS оператора не отдаёт адрес (%v), через туннель адрес есть: имя блокируется на DNS оператора, внутри VPN это не мешает\n", t.name, oerr)
		}
		rtt, err := d.tcpProbeTo(ctx, tip, 443, 2500*time.Millisecond)
		if err == nil {
			okN++
			fmt.Fprintf(&b, "  ✔ %s (%s → %s) %d мс\n", t.name, t.host, tip.String(), rtt.Milliseconds())
		} else {
			fmt.Fprintf(&b, "  ✘ %s (%s → %s): %v\n", t.name, t.host, tip.String(), err)
		}
	}
	fmt.Fprintf(&b, "Доступно %d из %d.\n", okN, total)
	return b.String()
}
HYDRA_EOF

putv "settings.gradle.kts" <<'HYDRA_EOF'
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
		"162.159.199.2", // запасной официальный адрес MASQUE
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
	for _, port := range []string{"500", "1701", "4500", "8443", "4443", "8095"} {
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
	"fmt"
	"math/rand"
	"net"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
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
	// UseReserved: в каждом сообщении WireGuard байты 1–3 заменяются на Reserved (как у клиентов WARP,
	// они берутся из client_id аккаунта); от сервера эти байты обнуляются обратно.
	UseReserved bool
	Reserved    [3]byte
	// CountWG: считать сообщения WireGuard по типам (для диагностики).
	CountWG bool
	// Noise: столько случайных коротких датаграмм (NoiseMin–NoiseMax байт) уходит перед рукопожатием.
	Noise, NoiseMin, NoiseMax int
}

type UDPRelay struct {
	local  *net.UDPConn
	remote *net.UDPAddr
	fake   FakeSpec

	mu    sync.Mutex
	peers map[string]*net.UDPConn
	once  sync.Once

	out, in [6]int32 // сообщения WireGuard по типам: 1 init, 2 ответ, 3 cookie, 4 данные, 5 прочее
}

func wgType(p []byte) int {
	if len(p) >= 4 && p[0] >= 1 && p[0] <= 4 && p[1] == 0 && p[2] == 0 && p[3] == 0 {
		return int(p[0])
	}
	return 5
}

// Stats — сколько сообщений WireGuard прошло через переходник (для отчёта).
func (r *UDPRelay) Stats() string {
	g := func(a *[6]int32, i int) int32 { return atomic.LoadInt32(&a[i]) }
	return fmt.Sprintf("к серверу: рукопожатий %d, данных %d; от сервера: ответов %d, данных %d, cookie %d, прочих %d",
		g(&r.out, 1), g(&r.out, 4), g(&r.in, 2), g(&r.in, 4), g(&r.in, 3), g(&r.in, 5))
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
			pkt := buf[:n]
			if r.fake.PerInit != nil && IsWGInit(pkt) {
				for _, j := range r.fake.PerInit() {
					up.Write(j)
				}
			}
			if r.fake.CountWG {
				atomic.AddInt32(&r.out[wgType(pkt)], 1)
			}
			if r.fake.UseReserved && wgType(pkt) != 5 {
				copy(pkt[1:4], r.fake.Reserved[:])
			}
			up.Write(pkt)
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
			pkt := buf[:n]
			if r.fake.UseReserved && len(pkt) >= 4 && pkt[0] >= 1 && pkt[0] <= 4 {
				pkt[1], pkt[2], pkt[3] = 0, 0, 0
			}
			if r.fake.CountWG {
				atomic.AddInt32(&r.in[wgType(pkt)], 1)
			}
			r.local.WriteToUDP(pkt, from)
		}
	}()
	return c
}

func (r *UDPRelay) sendFakes(c *net.UDPConn) {
	if len(r.fake.Payloads) == 0 && r.fake.Noise <= 0 {
		return
	}
	if len(r.fake.Payloads) > 0 {
		if r.fake.TTL > 0 {
			if err := setTTL(c, r.fake.TTL); err != nil {
				Logf("   фейковые пакеты: не удалось задать TTL: %v", err)
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
		Logf("   фейковых пакетов: %d, %d байт, TTL=%d → %s", len(r.fake.Payloads), total, r.fake.TTL, c.RemoteAddr())
	}
	if r.fake.Noise > 0 {
		lo, hi := r.fake.NoiseMin, r.fake.NoiseMax
		if lo < 1 {
			lo = 5
		}
		if hi < lo {
			hi = lo
		}
		sent := 0
		for i := 0; i < r.fake.Noise; i++ {
			b := make([]byte, lo+rand.Intn(hi-lo+1))
			rand.Read(b)
			if _, err := c.Write(b); err == nil {
				sent++
			}
			time.Sleep(time.Duration(1+rand.Intn(2)) * time.Millisecond)
		}
		Logf("   шумовых пакетов: %d (%d–%d байт)", sent, lo, hi)
	}
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
	case "quic", "qv":
		out = append(out, BuildQUICLike())
	case "stun":
		out = append(out, BuildSTUNLike())
	}
	// "qv" — точная копия захвата Варвары на Билайне: QUIC-подобный пакет (108 байт) и сразу 4 мусорных пакета
	// по 50–80 байт, без лишних пакетов между ними; всего 5 пакетов до рукопожатия, а не 8, как у "quic".
	if sig != "" && sig != "qv" {
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
	// близнец стратегии с reserved-байтами из client_id (так подключаются клиенты WARP)
	rsv := acc.ClientID != "" && !acc.Custom
	mkr := func(ep, sig string, jc, jmin, jmax int, alias string) Strategy {
		s := mk(ep, sig, jc, jmin, jmax, alias+"r")
		s.Params["rsv"] = "1"
		return s
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
	// 162.159.192.4 работал на Билайне, 188.114.96.41 — адрес из захвата Варвары
	first := []string{hostOnly(acc.EndpointV4), "162.159.192.3", "162.159.192.4", "188.114.96.41"}
	for _, h := range first {
		add(h)
	}
	for _, h := range hosts {
		ep := net.JoinHostPort(h, "2408")
		out = append(out, mk(ep, "quic", 3, 41, 78, "q3"))
		if rsv {
			out = append(out, mkr(ep, "quic", 3, 41, 78, "q3"))
		}
		// точный образ Варвары: QUIC-подобный пакет + 4 мусорных по 50–80 байт
		out = append(out, mk(ep, "qv", 4, 50, 80, "v4"))
		if rsv {
			out = append(out, mkr(ep, "qv", 4, 50, 80, "v4"))
		}
		out = append(out, mk(ep, "stun", 3, 41, 78, "s3"))
		out = append(out, mk(ep, "", 4, 40, 70, "j4"))
		out = append(out, mk(ep, "", 0, 0, 0, "plain"))
		if rsv {
			out = append(out, mkr(ep, "", 0, 0, 0, "plain"))
		}
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
			if rsv {
				out = append(out, mkr(net.JoinHostPort(h, "2408"), "quic", 3, 41, 78, "q3"))
			}
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
	"bytes"
	"context"
	"encoding/base64"
	"encoding/binary"
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

	// Подмена адреса: сервер WARP принимает от аккаунта WireGuard только пакеты с его собственным
	// адресом. Если трафик из TUN идёт с другого адреса (адрес MASQUE-аккаунта), подменяем его
	// на выходе и возвращаем на входе.
	wgAddr []byte
	mu     sync.Mutex
	orig   []byte
}

// fixSum — инкрементальное обновление контрольной суммы (RFC 1624) при замене двух 16-битных слов.
func fixSum(sum uint16, oldW, newW [2]uint16) uint16 {
	s := uint32(^sum) & 0xffff
	for i := 0; i < 2; i++ {
		s += uint32(^oldW[i]) & 0xffff
		s += uint32(newW[i])
	}
	for s>>16 != 0 {
		s = (s & 0xffff) + (s >> 16)
	}
	return ^uint16(s)
}

// rewriteIPv4 заменяет адрес в IPv4-пакете (off 12 — источник, 16 — получатель) и правит контрольные суммы.
func rewriteIPv4(p []byte, off int, na []byte) {
	ihl := int(p[0]&0x0f) * 4
	if ihl < 20 || len(p) < ihl || len(na) != 4 {
		return
	}
	oldW := [2]uint16{binary.BigEndian.Uint16(p[off:]), binary.BigEndian.Uint16(p[off+2:])}
	newW := [2]uint16{binary.BigEndian.Uint16(na), binary.BigEndian.Uint16(na[2:])}
	binary.BigEndian.PutUint16(p[10:], fixSum(binary.BigEndian.Uint16(p[10:]), oldW, newW))
	copy(p[off:off+4], na)
	if binary.BigEndian.Uint16(p[6:])&0x1fff != 0 {
		return // не первый фрагмент: заголовка L4 нет
	}
	switch p[9] {
	case 6: // TCP
		if len(p) >= ihl+18 {
			o := ihl + 16
			binary.BigEndian.PutUint16(p[o:], fixSum(binary.BigEndian.Uint16(p[o:]), oldW, newW))
		}
	case 17: // UDP (контрольная сумма 0 — «не считалась»)
		if len(p) >= ihl+8 {
			o := ihl + 6
			if c := binary.BigEndian.Uint16(p[o:]); c != 0 {
				v := fixSum(c, oldW, newW)
				if v == 0 {
					v = 0xffff
				}
				binary.BigEndian.PutUint16(p[o:], v)
			}
		}
	}
}

func (m *memTun) natOut(p []byte) {
	if m.wgAddr == nil || len(p) < 20 || p[0]>>4 != 4 || bytes.Equal(p[12:16], m.wgAddr) {
		return
	}
	m.mu.Lock()
	if m.orig == nil {
		m.orig = append([]byte(nil), p[12:16]...)
		Logf("   адрес в аккаунте WireGuard %d.%d.%d.%d, а трафик идёт с %d.%d.%d.%d — подменяю",
			m.wgAddr[0], m.wgAddr[1], m.wgAddr[2], m.wgAddr[3], p[12], p[13], p[14], p[15])
	}
	same := bytes.Equal(p[12:16], m.orig)
	m.mu.Unlock()
	if same {
		rewriteIPv4(p, 12, m.wgAddr)
	}
}

func (m *memTun) natIn(p []byte) {
	if m.wgAddr == nil || len(p) < 20 || p[0]>>4 != 4 || !bytes.Equal(p[16:20], m.wgAddr) {
		return
	}
	m.mu.Lock()
	o := m.orig
	m.mu.Unlock()
	if o != nil {
		rewriteIPv4(p, 16, o)
	}
}

func (m *memTun) File() *os.File { return nil }

func (m *memTun) Read(bufs [][]byte, sizes []int, offset int) (int, error) {
	n, err := m.dev.ReadPacket(bufs[0][offset:])
	if err != nil {
		return 0, err
	}
	m.natOut(bufs[0][offset : offset+n])
	sizes[0] = n
	return 1, nil
}

func (m *memTun) Write(bufs [][]byte, offset int) (int, error) {
	for i, b := range bufs {
		m.natIn(b[offset:])
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
// WGPool — аккаунты WireGuard. Сервер WARP помнит одну сессию на ключ: второе рукопожатие с тем же ключом
// «уводит» ответы к новому клиенту, и первый туннель замолкает. Поэтому каждый аккаунт держит не более
// одной сессии одновременно; для горячего резерва нужен второй аккаунт.
type WGPool struct {
	mu   sync.Mutex
	accs []*Account
	busy []bool
}

func NewWGPool(accs ...*Account) *WGPool {
	p := &WGPool{}
	for _, a := range accs {
		if a != nil && a.Kind == "wg" {
			p.accs = append(p.accs, a)
		}
	}
	p.busy = make([]bool, len(p.accs))
	return p
}

func (p *WGPool) acquire() (int, *Account, bool) {
	p.mu.Lock()
	defer p.mu.Unlock()
	for i, b := range p.busy {
		if !b {
			p.busy[i] = true
			return i, p.accs[i], true
		}
	}
	return 0, nil, false
}

func (p *WGPool) release(i int) {
	p.mu.Lock()
	p.busy[i] = false
	p.mu.Unlock()
}

// CanRun: для WireGuard — есть ли свободный аккаунт; остальные стратегии ограничений не имеют.
func (p *WGPool) CanRun(s Strategy) bool {
	if p == nil || s.Transport != "wg" {
		return true
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	for _, b := range p.busy {
		if !b {
			return true
		}
	}
	return false
}

// Info — сводка для диагностики.
func (p *WGPool) Info() string {
	if p == nil {
		return ""
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	busy := 0
	for _, b := range p.busy {
		if b {
			busy++
		}
	}
	return fmt.Sprintf("аккаунтов WireGuard: %d, занято сессиями: %d\n", len(p.accs), busy)
}

// NewWGRunner — раннер WireGuard с одним аккаунтом.
func NewWGRunner(acc *Account) (Runner, error) {
	return NewWGPoolRunner(NewWGPool(acc))
}

// NewWGPoolRunner — раннер WireGuard, который берёт свободный аккаунт из пула на время работы сессии.
func NewWGPoolRunner(p *WGPool) (Runner, error) {
	if p == nil || len(p.accs) == 0 {
		return nil, errors.New("нет конфигурации WireGuard")
	}
	if _, err := WGUAPI(p.accs[0], "127.0.0.1:1"); err != nil {
		return nil, err
	}
	return func(ctx context.Context, dev PacketDevice, s Strategy) error {
		ai, acc, got := p.acquire()
		if !got {
			return ErrRunnerBusy
		}
		defer p.release(ai) // выполнится последним: сессия закрыта полностью
		Logf("   аккаунт WireGuard №%d из %d", ai+1, len(p.accs))
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
		if s.Params["rsv"] == "1" {
			rb, derr := base64.StdEncoding.DecodeString(strings.TrimSpace(acc.ClientID))
			if derr != nil || len(rb) != 3 {
				return errors.New("для этой стратегии нужен client_id аккаунта (reserved-байты)")
			}
			fk.UseReserved = true
			copy(fk.Reserved[:], rb)
			Logf("   reserved-байты аккаунта: %v", rb)
		}
		fk.CountWG = true
		relay, err := StartUDPRelay(remote, fk)
		if err != nil {
			return err
		}
		defer relay.Close()

		uapi, err := WGUAPI(acc, relay.Addr().String())
		if err != nil {
			return err
		}
		if st, ok := dev.(interface{ SetStats(func() string) }); ok {
			st.SetStats(relay.Stats) // счётчики сообщений WG попадут в причину сбоя
		}
		mt := &memTun{dev: dev, mtu: 1280, events: make(chan tun.Event, 4)}
		if a4 := net.ParseIP(strings.Split(acc.AddrV4, "/")[0]).To4(); a4 != nil {
			mt.wgAddr = []byte(a4)
		}
		logger := &device.Logger{
			Verbosef: func(format string, args ...any) {
				if l := fmt.Sprintf(format, args...); strings.Contains(l, "andshake") && !strings.Contains(l, "Routine:") {
					Logf("   wg: %s", l)
				}
			},
			Errorf: func(format string, args ...any) {
				l := fmt.Sprintf(format, args...)
				if strings.Contains(l, "TUN device: EOF") {
					return // обычное закрытие сессии, не ошибка
				}
				Logf("   wg ✘ %s", l)
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

# --- убрать лишние .go и .kt, которых нет в этом наборе ---
if [ "$OLD" -lt "$NEW" ]; then
  KEEP_GO=" brain.go clock.go colo.go colo_test.go custom.go dns.go dns_test.go engine.go engine_test.go events.go front.go front_test.go gate.go genes.go icmp6.go journal.go learn.go masque_runner.go memory.go mobile/mobile.go mobile/netalive.go mobile/policy.go mobile/vpn_stub.go mobile/vpn_usque.go orchestrator.go orchestrator_test.go outage.go pool.go probe.go probe_test.go quicfake.go quicfake_test.go race.go register.go register_test.go services.go strategies.go strategies_test.go transport.go udprelay.go udprelay_test.go wg.go wg_runner.go wg_test.go "
  KEEP_KT=" app/src/main/java/app/hydra/AccountController.kt app/src/main/java/app/hydra/AdvancedScreens.kt app/src/main/java/app/hydra/AppsScreen.kt app/src/main/java/app/hydra/BootReceiver.kt app/src/main/java/app/hydra/DiagScreen.kt app/src/main/java/app/hydra/Diagnostics.kt app/src/main/java/app/hydra/DiagnosticsScreen.kt app/src/main/java/app/hydra/Doctor.kt app/src/main/java/app/hydra/HomeScreen.kt app/src/main/java/app/hydra/HydraApp.kt app/src/main/java/app/hydra/HydraHero.kt app/src/main/java/app/hydra/HydraVpnService.kt app/src/main/java/app/hydra/MainActivity.kt app/src/main/java/app/hydra/Prefs.kt app/src/main/java/app/hydra/SystemInfo.kt app/src/main/java/app/hydra/Theme.kt app/src/main/java/app/hydra/Ui.kt app/src/main/java/app/hydra/VpnController.kt "
  for f in "$GODIR"/*.go "$GODIR"/mobile/*.go; do
    [ -e "$f" ] || continue
    rel="${f#"$GODIR"/}"
    case "$KEEP_GO" in *" $rel "*) ;; *) echo "удаляю лишний файл: $f"; rm -f "$f";; esac
  done
  for f in app/src/main/java/app/hydra/*.kt; do
    [ -e "$f" ] || continue
    case "$KEEP_KT" in *" $f "*) ;; *) echo "удаляю лишний файл: $f"; rm -f "$f";; esac
  done
fi

echo "$NEW" > "$STAMP"
