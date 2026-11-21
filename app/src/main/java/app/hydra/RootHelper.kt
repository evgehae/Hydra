package app.hydra

import android.content.Context
import android.util.Log
import java.io.BufferedReader
import java.io.DataOutputStream
import java.io.InputStreamReader

/**
 * Root-режим: iptables / nftables / ipset для жёсткого anti-leak и политики маршрутов.
 * Работает только если на устройстве есть su (Magisk и т.п.).
 * Без root все методы безопасно возвращают false / пустую строку.
 */
object RootHelper {
    private const val TAG = "HydraRoot"

    /** Есть ли рабочий su. */
    fun hasRoot(): Boolean {
        return try {
            val p = Runtime.getRuntime().exec(arrayOf("su", "-c", "id"))
            val out = BufferedReader(InputStreamReader(p.inputStream)).readText()
            val code = p.waitFor()
            code == 0 && out.contains("uid=0")
        } catch (t: Throwable) {
            false
        }
    }

    /** Выполнить команды от root. Возвращает stdout+stderr и код. */
    fun su(commands: List<String>, timeoutMs: Long = 8000): Pair<Int, String> {
        return try {
            val p = Runtime.getRuntime().exec("su")
            DataOutputStream(p.outputStream).use { os ->
                for (c in commands) {
                    os.writeBytes(c + "\n")
                }
                os.writeBytes("exit\n")
                os.flush()
            }
            val finished = p.waitFor()
            val out = buildString {
                BufferedReader(InputStreamReader(p.inputStream)).use { append(it.readText()) }
                BufferedReader(InputStreamReader(p.errorStream)).use { append(it.readText()) }
            }
            finished to out.trim()
        } catch (t: Throwable) {
            -1 to (t.message ?: "su failed")
        }
    }

    fun suOne(cmd: String): Pair<Int, String> = su(listOf(cmd))

    /** Какой firewall доступен: nft | iptables | none */
    fun firewallBackend(): String {
        if (!hasRoot()) return "none"
        val (c1, _) = suOne("nft list ruleset >/dev/null 2>&1 && echo nft")
        if (c1 == 0) {
            val (_, o) = suOne("nft list ruleset >/dev/null 2>&1 && echo nft || true")
            if (o.contains("nft")) return "nft"
        }
        val (c2, o2) = suOne("iptables -L -n >/dev/null 2>&1 && echo ipt || true")
        if (c2 == 0 && o2.contains("ipt")) return "iptables"
        return "none"
    }

    /**
     * Включить жёсткий kill-switch: весь трафик, кроме VPN-интерфейса и локальных подсетей,
     * режется. Вызывать после поднятия tun0 (или как он называется).
     */
    fun enableKillSwitch(tunIf: String = "tun0"): Boolean {
        if (!hasRoot()) return false
        val backend = firewallBackend()
        return when (backend) {
            "nft" -> enableKillSwitchNft(tunIf)
            "iptables" -> enableKillSwitchIptables(tunIf)
            else -> false
        }
    }

    fun disableKillSwitch(): Boolean {
        if (!hasRoot()) return false
        val backend = firewallBackend()
        return when (backend) {
            "nft" -> {
                val (c, _) = su(listOf(
                    "nft delete table inet hydra_ks 2>/dev/null || true"
                ))
                c == 0
            }
            "iptables" -> {
                val (c, _) = su(listOf(
                    "iptables -D OUTPUT -j HYDRA_KS 2>/dev/null || true",
                    "iptables -F HYDRA_KS 2>/dev/null || true",
                    "iptables -X HYDRA_KS 2>/dev/null || true",
                    "ip6tables -D OUTPUT -j HYDRA_KS 2>/dev/null || true",
                    "ip6tables -F HYDRA_KS 2>/dev/null || true",
                    "ip6tables -X HYDRA_KS 2>/dev/null || true"
                ))
                c == 0
            }
            else -> false
        }
    }

    private fun enableKillSwitchNft(tunIf: String): Boolean {
        val script = """
            nft delete table inet hydra_ks 2>/dev/null || true
            nft add table inet hydra_ks
            nft add chain inet hydra_ks output { type filter hook output priority 0 \; policy accept \; }
            # разрешаем loopback и VPN
            nft add rule inet hydra_ks output oif "lo" accept
            nft add rule inet hydra_ks output oif "$tunIf" accept
            # локальные сети
            nft add rule inet hydra_ks output ip daddr 10.0.0.0/8 accept
            nft add rule inet hydra_ks output ip daddr 172.16.0.0/12 accept
            nft add rule inet hydra_ks output ip daddr 192.168.0.0/16 accept
            nft add rule inet hydra_ks output ip daddr 127.0.0.0/8 accept
            nft add rule inet hydra_ks output ip daddr 169.254.0.0/16 accept
            # DHCP / DNS к роутеру иногда нужны до туннеля — оставляем established
            nft add rule inet hydra_ks output ct state established,related accept
            # всё остальное режем
            nft add rule inet hydra_ks output drop
        """.trimIndent().lines().filter { it.isNotBlank() && !it.trimStart().startsWith("#") }
        val (c, out) = su(script)
        if (c != 0) Log.w(TAG, "nft kill-switch: $out")
        return c == 0
    }

    private fun enableKillSwitchIptables(tunIf: String): Boolean {
        val cmds = listOf(
            "iptables -N HYDRA_KS 2>/dev/null || iptables -F HYDRA_KS",
            "iptables -F HYDRA_KS",
            "iptables -A HYDRA_KS -o lo -j ACCEPT",
            "iptables -A HYDRA_KS -o $tunIf -j ACCEPT",
            "iptables -A HYDRA_KS -d 10.0.0.0/8 -j ACCEPT",
            "iptables -A HYDRA_KS -d 172.16.0.0/12 -j ACCEPT",
            "iptables -A HYDRA_KS -d 192.168.0.0/16 -j ACCEPT",
            "iptables -A HYDRA_KS -d 127.0.0.0/8 -j ACCEPT",
            "iptables -A HYDRA_KS -d 169.254.0.0/16 -j ACCEPT",
            "iptables -A HYDRA_KS -m state --state ESTABLISHED,RELATED -j ACCEPT",
            "iptables -A HYDRA_KS -j DROP",
            "iptables -D OUTPUT -j HYDRA_KS 2>/dev/null || true",
            "iptables -I OUTPUT -j HYDRA_KS",
            // IPv6
            "ip6tables -N HYDRA_KS 2>/dev/null || ip6tables -F HYDRA_KS",
            "ip6tables -F HYDRA_KS",
            "ip6tables -A HYDRA_KS -o lo -j ACCEPT",
            "ip6tables -A HYDRA_KS -o $tunIf -j ACCEPT",
            "ip6tables -A HYDRA_KS -m state --state ESTABLISHED,RELATED -j ACCEPT",
            "ip6tables -A HYDRA_KS -j DROP",
            "ip6tables -D OUTPUT -j HYDRA_KS 2>/dev/null || true",
            "ip6tables -I OUTPUT -j HYDRA_KS"
        )
        val (c, out) = su(cmds)
        if (c != 0) Log.w(TAG, "iptables kill-switch: $out")
        return c == 0
    }

    /**
     * ipset с «плохими» адресами (опционально) — для будущего блокинга/маршрутизации.
     */
    fun ensureIpset(name: String = "hydra_block"): Boolean {
        if (!hasRoot()) return false
        val (c, _) = su(listOf(
            "ipset list $name >/dev/null 2>&1 || ipset create $name hash:ip family inet maxelem 65536",
            "ipset list ${name}6 >/dev/null 2>&1 || ipset create ${name}6 hash:ip family inet6 maxelem 65536 || true"
        ))
        return c == 0
    }


    /**
     * Root-защита от убийства VPN системой (Xiaomi/HyperOS и др.):
     *  - whitelist в battery optimization
     *  - oom_score_adj = -1000 для текущего процесса
     *  - попытка autostart permission (MIUI)
     */
    fun protectProcess(pkg: String, pid: Int = android.os.Process.myPid()): String {
        if (!hasRoot()) return "root: нет"
        val cmds = mutableListOf(
            // не убивать по OOM
            "echo -1000 > /proc/$pid/oom_score_adj 2>/dev/null || true",
            "echo -1000 > /proc/$pid/oom_adj 2>/dev/null || true",
            // whitelist батареи (Android 6+)
            "dumpsys deviceidle whitelist +$pkg 2>/dev/null || true",
            // MIUI autostart / background
            "cmd appops set $pkg RUN_IN_BACKGROUND allow 2>/dev/null || true",
            "cmd appops set $pkg RUN_ANY_IN_BACKGROUND allow 2>/dev/null || true",
            "cmd appops set $pkg START_FOREGROUND allow 2>/dev/null || true",
            // снять ограничения standby
            "am set-inactive $pkg false 2>/dev/null || true"
        )
        val (c, out) = su(cmds)
        return if (c == 0) "protect: ok" else "protect: $out"
    }

    /** Поднять приоритет сетевых очередей для tun (если есть). */
    fun boostTun(tunIf: String = "tun0"): Boolean {
        if (!hasRoot()) return false
        val (c, _) = su(listOf(
            "ip link set dev $tunIf txqueuelen 1000 2>/dev/null || true",
            // fq_codel снижает bufferbloat на VPN
            "tc qdisc replace dev $tunIf root fq_codel 2>/dev/null || true"
        ))
        return c == 0
    }

    fun statusReport(): String {
        if (!hasRoot()) return "root: нет"
        val backend = firewallBackend()
        val (c, out) = when (backend) {
            "nft" -> suOne("nft list table inet hydra_ks 2>/dev/null | head -20 || echo 'hydra_ks не активна'")
            "iptables" -> suOne("iptables -S HYDRA_KS 2>/dev/null | head -20 || echo 'HYDRA_KS не активна'")
            else -> 0 to "firewall backend не найден"
        }
        return "root: да\nbackend: $backend\n$out"
    }
}
