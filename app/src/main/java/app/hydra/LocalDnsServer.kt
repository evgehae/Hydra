package app.hydra

import android.util.Log
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/**
 * Локальный DNS на 127.0.0.1:5353.
 * Имена из карты AI-DNS → фиксированный A-ответ (IP прокси).
 * Остальное — форвард на upstream (1.1.1.1), сокет можно protect() от VPN.
 */
object LocalDnsServer {
    private const val TAG = "HydraLocalDns"
    const val PORT = 5353

    private val map = ConcurrentHashMap<String, String>() // lowercase domain → ipv4
    private val running = AtomicBoolean(false)
    private var socket: DatagramSocket? = null
    private var protect: ((DatagramSocket) -> Boolean)? = null

    fun setMap(hits: List<AiDns.ResolveHit>) {
        map.clear()
        for (h in hits) {
            map[h.domain.lowercase().trimEnd('.')] = h.ip
        }
        Log.i(TAG, "map size=${map.size}")
    }

    fun mapSize(): Int = map.size

    fun start(protectFn: ((DatagramSocket) -> Boolean)? = null) {
        protect = protectFn
        if (running.getAndSet(true)) return
        thread(name = "hydra-local-dns", isDaemon = true) {
            try {
                val s = DatagramSocket(null)
                s.reuseAddress = true
                s.bind(InetSocketAddress(InetAddress.getByName("127.0.0.1"), PORT))
                socket = s
                Log.i(TAG, "listening 127.0.0.1:$PORT map=${map.size}")
                val buf = ByteArray(512)
                while (running.get()) {
                    try {
                        val req = DatagramPacket(buf, buf.size)
                        s.receive(req)
                        val data = req.data.copyOf(req.length)
                        val resp = handle(data) ?: continue
                        s.send(DatagramPacket(resp, resp.size, req.socketAddress))
                    } catch (e: Exception) {
                        if (running.get()) Log.w(TAG, "loop: ${e.message}")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "bind failed: ${e.message}")
                running.set(false)
            } finally {
                try { socket?.close() } catch (_: Exception) {}
                socket = null
            }
        }
    }

    fun stop() {
        running.set(false)
        try { socket?.close() } catch (_: Exception) {}
        socket = null
    }

    private fun handle(raw: ByteArray): ByteArray? {
        if (raw.size < 12) return null
        val id0 = raw[0]
        val id1 = raw[1]
        // parse QNAME
        var i = 12
        val labels = ArrayList<String>()
        while (i < raw.size) {
            val len = raw[i].toInt() and 0xff
            if (len == 0) { i++; break }
            if (len and 0xc0 == 0xc0) return null // compression in question — rare
            if (i + 1 + len > raw.size) return null
            labels.add(String(raw, i + 1, len, Charsets.US_ASCII))
            i += 1 + len
        }
        if (i + 4 > raw.size) return null
        val qtype = ((raw[i].toInt() and 0xff) shl 8) or (raw[i + 1].toInt() and 0xff)
        val name = labels.joinToString(".").lowercase()
        if (qtype == 1) { // A
            val ip = lookup(name)
            if (ip != null) return buildAResponse(id0, id1, raw, i + 4, ip)
        }
        // forward
        return forward(raw)
    }

    private fun lookup(name: String): String? {
        map[name]?.let { return it }
        // suffix match: api.openai.com if openai.com in map? only exact + www strip
        if (name.startsWith("www.") && map.containsKey(name.removePrefix("www."))) {
            return map[name.removePrefix("www.")]
        }
        // parent: foo.chatgpt.com → chatgpt.com
        val parts = name.split('.')
        if (parts.size > 2) {
            val parent = parts.drop(1).joinToString(".")
            map[parent]?.let { return it }
        }
        return null
    }

    private fun buildAResponse(id0: Byte, id1: Byte, question: ByteArray, qEnd: Int, ip: String): ByteArray {
        val octets = ip.split('.').map { it.toInt().toByte() }
        if (octets.size != 4) return forward(question) ?: question
        val out = ArrayList<Byte>(qEnd + 16)
        // header
        out.add(id0); out.add(id1)
        out.add(0x81.toByte()); out.add(0x80.toByte()) // response, recursive
        out.add(0); out.add(1) // QDCOUNT
        out.add(0); out.add(1) // ANCOUNT
        out.add(0); out.add(0); out.add(0); out.add(0)
        // question copy
        for (j in 12 until qEnd) out.add(question[j])
        // answer: pointer to name at 12
        out.add(0xc0.toByte()); out.add(0x0c)
        out.add(0); out.add(1) // A
        out.add(0); out.add(1) // IN
        out.add(0); out.add(0); out.add(0); out.add(60) // TTL 60
        out.add(0); out.add(4)
        out.addAll(octets)
        return out.toByteArray()
    }

    private fun forward(raw: ByteArray): ByteArray? {
        return try {
            val up = DatagramSocket()
            try {
                protect?.invoke(up)
                up.soTimeout = 3000
                up.send(DatagramPacket(raw, raw.size, InetAddress.getByName("1.1.1.1"), 53))
                val buf = ByteArray(512)
                val resp = DatagramPacket(buf, buf.size)
                up.receive(resp)
                buf.copyOf(resp.length)
            } finally {
                up.close()
            }
        } catch (e: Exception) {
            Log.w(TAG, "forward: ${e.message}")
            null
        }
    }
}
