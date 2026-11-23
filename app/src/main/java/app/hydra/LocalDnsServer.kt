package app.hydra

import android.util.Log
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

/**
 * Локальный DNS «только ИИ»:
 * - имена из карты → A-запись (IP прокси)
 * - всё остальное → форвард на 1.1.1.1 / 8.8.8.8
 *
 * Слушает 127.0.0.1:53 (если удалось) или :5353.
 * С root iptables REDIRECT 53→5353 подхватывает системные запросы.
 */
object LocalDnsServer {
    private const val TAG = "HydraLocalDns"
    const val FALLBACK_PORT = 5353

    private val map = ConcurrentHashMap<String, String>()
    private val running = AtomicBoolean(false)
    private var socket: DatagramSocket? = null
    private var protect: ((DatagramStream) -> Boolean)? = null
    private var protectSock: ((DatagramSocket) -> Boolean)? = null
    private val hitsAi = AtomicInteger(0)
    private val hitsFwd = AtomicInteger(0)
    @Volatile var boundPort: Int = 0
        private set

    // placeholder type unused
    private class DatagramStream

    fun setMap(hits: List<AiDns.ResolveHit>) {
        map.clear()
        for (h in hits) {
            val d = h.domain.lowercase().trimEnd('.')
            if (d.isBlank() || h.ip.isBlank()) continue
            map[d] = h.ip
            // www ↔ apex
            if (d.startsWith("www.")) map[d.removePrefix("www.")] = h.ip
            else map["www.$d"] = h.ip
        }
        Log.i(TAG, "map size=${map.size}")
    }

    fun mapSize(): Int = map.size
    fun stats(): String = "ai=${hitsAi.get()} fwd=${hitsFwd.get()} port=$boundPort map=${map.size}"

    fun start(protectFn: ((DatagramSocket) -> Boolean)? = null) {
        protectSock = protectFn
        if (running.get()) return
        thread(name = "hydra-local-dns", isDaemon = true) {
            val ports = listOf(53, FALLBACK_PORT)
            var bound: DatagramSocket? = null
            var portUsed = 0
            for (port in ports) {
                try {
                    val s = DatagramSocket(null)
                    s.reuseAddress = true
                    s.bind(InetSocketAddress(InetAddress.getByName("127.0.0.1"), port))
                    bound = s
                    portUsed = port
                    break
                } catch (e: Exception) {
                    Log.w(TAG, "bind 127.0.0.1:$port fail: ${e.message}")
                }
            }
            if (bound == null) {
                Log.e(TAG, "cannot bind any DNS port")
                running.set(false)
                return@thread
            }
            socket = bound
            boundPort = portUsed
            running.set(true)
            Log.i(TAG, "listening 127.0.0.1:$portUsed map=${map.size}")
            val buf = ByteArray(512)
            while (running.get()) {
                try {
                    val req = DatagramPacket(buf, buf.size)
                    bound.receive(req)
                    val data = req.data.copyOf(req.length)
                    val resp = handle(data) ?: continue
                    bound.send(DatagramPacket(resp, resp.size, req.socketAddress))
                } catch (e: Exception) {
                    if (running.get()) Log.w(TAG, "loop: ${e.message}")
                }
            }
            try { bound.close() } catch (_: Exception) {}
            if (socket === bound) socket = null
        }
        // wait briefly for bind
        var i = 0
        while (i < 20 && boundPort == 0 && running.get()) {
            Thread.sleep(50)
            i++
        }
    }

    fun stop() {
        running.set(false)
        try { socket?.close() } catch (_: Exception) {}
        socket = null
        boundPort = 0
    }

    private fun handle(raw: ByteArray): ByteArray? {
        if (raw.size < 12) return null
        val id0 = raw[0]
        val id1 = raw[1]
        var i = 12
        val labels = ArrayList<String>()
        while (i < raw.size) {
            val len = raw[i].toInt() and 0xff
            if (len == 0) { i++; break }
            if (len and 0xc0 == 0xc0) return forward(raw)
            if (i + 1 + len > raw.size) return null
            labels.add(String(raw, i + 1, len, Charsets.US_ASCII))
            i += 1 + len
        }
        if (i + 4 > raw.size) return null
        val qtype = ((raw[i].toInt() and 0xff) shl 8) or (raw[i + 1].toInt() and 0xff)
        val name = labels.joinToString(".").lowercase()
        if (qtype == 1) { // A
            val ip = lookup(name)
            if (ip != null) {
                hitsAi.incrementAndGet()
                return buildAResponse(id0, id1, raw, i + 4, ip)
            }
        }
        hitsFwd.incrementAndGet()
        return forward(raw)
    }

    private fun lookup(name: String): String? {
        map[name]?.let { return it }
        val parts = name.split('.')
        // suffix: foo.bar.chatgpt.com → chatgpt.com
        if (parts.size >= 2) {
            for (n in 2..minOf(parts.size, 4)) {
                val parent = parts.takeLast(n).joinToString(".")
                map[parent]?.let { return it }
            }
        }
        return null
    }

    private fun buildAResponse(id0: Byte, id1: Byte, question: ByteArray, qEnd: Int, ip: String): ByteArray {
        val octets = ip.split('.').mapNotNull { it.toIntOrNull()?.toByte() }
        if (octets.size != 4) return forward(question) ?: question
        val out = ArrayList<Byte>(qEnd + 16)
        out.add(id0); out.add(id1)
        out.add(0x81.toByte()); out.add(0x80.toByte())
        out.add(0); out.add(1) // QD
        out.add(0); out.add(1) // AN
        out.add(0); out.add(0); out.add(0); out.add(0)
        for (j in 12 until qEnd) out.add(question[j])
        out.add(0xc0.toByte()); out.add(0x0c)
        out.add(0); out.add(1)
        out.add(0); out.add(1)
        out.add(0); out.add(0); out.add(0); out.add(60)
        out.add(0); out.add(4)
        out.addAll(octets)
        return out.toByteArray()
    }

    private fun forward(raw: ByteArray): ByteArray? {
        for (upHost in listOf("1.1.1.1", "8.8.8.8")) {
            try {
                val up = DatagramSocket()
                try {
                    protectSock?.invoke(up)
                    up.soTimeout = 2500
                    up.send(DatagramPacket(raw, raw.size, InetAddress.getByName(upHost), 53))
                    val buf = ByteArray(512)
                    val resp = DatagramPacket(buf, buf.size)
                    up.receive(resp)
                    return buf.copyOf(resp.length)
                } finally {
                    up.close()
                }
            } catch (e: Exception) {
                Log.w(TAG, "forward $upHost: ${e.message}")
            }
        }
        return null
    }
}
