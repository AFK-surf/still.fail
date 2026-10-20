// A login's loopback listener for the core (`listen.*`, client/core-ts hosts/bridge.ts; docs/remote-login.md): a
// command on a station (gcloud, aws, az…) waits for the browser to come back to http://localhost:<port>/…; this phone
// listens on that port, on loopback only (127.0.0.1, or ::1), while the person signs in in the browser here, and hands
// what comes to the core, which relays the one request the login waits for to the station and answers the browser with
// what the command said. The core decides what is relayed and when the listener closes; this only takes requests and
// writes the answers back, one connection a request (each answer closes its connection).
//
// While one listens the app has to keep running with the browser in front (a frozen process answers nobody):
// `open` says how many listen now, for the app's foreground service (LoginRelay.kt in :app).
package fail.still.core

import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import kotlin.concurrent.thread
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put

/** A request that came to a listener: as the browser sent it (its path with its query, its headers in their order). */
class LoopbackAsked(val method: String, val path: String, val headers: List<Pair<String, String>>, val body: ByteArray)

/** One core's listeners, by the id the core knows each by. */
class Loopback {
    private class Server(val socket: ServerSocket) {
        val requests = Channel<Pair<Long, LoopbackAsked>>(Channel.UNLIMITED)
        /** The connections whose request was handed on, by its number, until answered. */
        val asked = ConcurrentHashMap<Long, Socket>()
        val next = AtomicLong(1)
    }

    private val servers = ConcurrentHashMap<Long, Server>()
    private val ids = AtomicLong(1)

    /** A `listen.*` call: the answer's JSON and bytes. */
    suspend fun answer(op: String, json: String, bytes: ByteArray?): Pair<String, ByteArray?> {
        val a = Json.parseToJsonElement(json).jsonObject
        val id = a["id"]?.jsonPrimitive?.longOrNull
        return when (op) {
            "listen.open" -> {
                val port = a["port"]?.jsonPrimitive?.intOrNull ?: throw IllegalArgumentException("no port")
                val host = a["host"]?.jsonPrimitive?.contentOrNull ?: throw IllegalArgumentException("no host")
                buildJsonObject { put("id", withContext(Dispatchers.IO) { open(port, host) }) }.toString() to null
            }
            "listen.next" -> {
                val server = servers[id] ?: return END to null
                val (n, r) = server.requests.receiveCatching().getOrNull() ?: return END to null
                buildJsonObject {
                    put("request", n)
                    put("method", r.method)
                    put("path", r.path)
                    put("headers", buildJsonArray { r.headers.forEach { (k, v) -> add(JsonArray(listOf(JsonPrimitive(k), JsonPrimitive(v)))) } })
                }.toString() to r.body
            }
            "listen.respond" -> {
                val n = a["request"]?.jsonPrimitive?.longOrNull ?: throw IllegalArgumentException("no request")
                val status = a["status"]?.jsonPrimitive?.intOrNull ?: 502
                val headers = a["headers"]?.jsonArray.orEmpty().mapNotNull { h ->
                    val pair = h as? JsonArray ?: return@mapNotNull null
                    val k = pair.getOrNull(0)?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
                    val v = pair.getOrNull(1)?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
                    k to v
                }
                val socket = servers[id]?.asked?.remove(n)
                if (socket != null) withContext(Dispatchers.IO) { respond(socket, status, headers, bytes ?: ByteArray(0)) }
                "{}" to null
            }
            "listen.close" -> {
                if (id != null) close(id)
                "{}" to null
            }
            else -> throw IllegalArgumentException("no such call: $op")
        }
    }

    /** Listens on loopback `host` at `port`: its id. Fails (Address already in use) when the port is taken there. */
    fun open(port: Int, host: String): Long {
        val address: InetAddress = when (host) {
            "127.0.0.1" -> InetAddress.getByAddress("localhost", byteArrayOf(127, 0, 0, 1)) as Inet4Address
            "::1" -> InetAddress.getByAddress("localhost", ByteArray(16).also { it[15] = 1 }) as Inet6Address
            else -> throw IllegalArgumentException("not a loopback address: $host")
        }
        require(port in 1..65535) { "no such port: $port" }
        val socket = ServerSocket()
        try {
            socket.bind(InetSocketAddress(address, port), 16)
        } catch (e: IOException) {
            socket.close()
            throw e
        }
        val id = ids.getAndIncrement()
        val server = Server(socket)
        servers[id] = server
        _open.update { it + 1 }
        thread(name = "stillfail-loopback-$port", isDaemon = true) {
            while (true) {
                val c = try { socket.accept() } catch (_: IOException) { break }
                thread(name = "stillfail-loopback-$port-request", isDaemon = true) { take(server, c) }
            }
            server.requests.close()
        }
        return id
    }

    /** Stops listening: what is still unanswered is closed unanswered. */
    fun close(id: Long) {
        val server = servers.remove(id) ?: return
        runCatching { server.socket.close() }
        server.requests.close()
        server.asked.values.forEach { runCatching { it.close() } }
        server.asked.clear()
        _open.update { (it - 1).coerceAtLeast(0) }
    }

    /** Every listener of this core closed (the core ends). */
    fun closeAll() = servers.keys.toList().forEach(::close)

    /** A connection's request read whole and handed on; one that is not HTTP, or too slow, closed. */
    private fun take(server: Server, c: Socket) {
        val asked = try {
            c.soTimeout = READ_MS
            read(BufferedInputStream(c.getInputStream()))
        } catch (_: IOException) { null }
        if (asked == null) { runCatching { c.close() }; return }
        val n = server.next.getAndIncrement()
        server.asked[n] = c
        if (server.requests.trySend(n to asked).isFailure) { server.asked.remove(n); runCatching { c.close() } }
    }

    companion object {
        private const val END = """{"end":true}"""
        /** Most of a request's head and body taken (a login's callback: a query, or a small form). */
        private const val HEAD_MOST = 64 * 1024
        private const val BODY_MOST = 1_000_000
        /** A browser sends its request at once: one that has not in this long is let go. */
        private const val READ_MS = 15_000
        /** The headers that are the connection's, not the answer's: each answer closes its connection. */
        private val HOP = setOf("connection", "transfer-encoding", "content-length", "keep-alive")

        private val _open = MutableStateFlow(0)
        /** How many listeners are open now, in every core of the app. */
        val open: StateFlow<Int> = _open.asStateFlow()

        /** An HTTP/1.x request off a connection: null for what is not one. */
        fun read(input: InputStream): LoopbackAsked? {
            val head = ByteArrayOutputStream()
            // The last four bytes read: the head ends at CR LF CR LF.
            var last = 0
            while (last != 0x0d0a0d0a) {
                val b = input.read()
                if (b < 0 || head.size() >= HEAD_MOST) return null
                head.write(b)
                last = (last shl 8) or b
            }
            val lines = head.toString(Charsets.ISO_8859_1.name()).split("\r\n").dropLast(2)
            val first = lines.firstOrNull()?.split(' ') ?: return null
            if (first.size != 3 || !first[2].startsWith("HTTP/1.")) return null
            val headers = lines.drop(1).mapNotNull { line ->
                val at = line.indexOf(':')
                if (at <= 0) null else line.substring(0, at).trim() to line.substring(at + 1).trim()
            }
            val length = headers.lastOrNull { it.first.equals("content-length", ignoreCase = true) }?.second?.toLongOrNull() ?: 0L
            if (length < 0) return null
            val body = ByteArrayOutputStream()
            var left = length
            val buf = ByteArray(8192)
            while (left > 0) {
                val n = input.read(buf, 0, minOf(buf.size.toLong(), left).toInt())
                if (n < 0) return null
                if (body.size() < BODY_MOST) body.write(buf, 0, minOf(n, BODY_MOST - body.size()))
                left -= n
            }
            return LoopbackAsked(first[0], first[1], headers, body.toByteArray())
        }

        /** The answer, whole, then the connection closed. */
        fun respond(socket: Socket, status: Int, headers: List<Pair<String, String>>, body: ByteArray) {
            try {
                socket.use { s ->
                    val head = StringBuilder("HTTP/1.1 $status ${reason(status)}\r\n")
                    headers.filter { it.first.lowercase() !in HOP }.forEach { (k, v) -> head.append(k).append(": ").append(v.replace("\r", "").replace("\n", "")).append("\r\n") }
                    head.append("Connection: close\r\nContent-Length: ").append(body.size).append("\r\n\r\n")
                    val out = s.getOutputStream()
                    out.write(head.toString().toByteArray(Charsets.UTF_8))
                    out.write(body)
                    out.flush()
                }
            } catch (_: IOException) {
                // The browser went away: nothing to answer.
            }
        }

        private fun reason(status: Int) = when (status) {
            200 -> "OK"; 302 -> "Found"; 303 -> "See Other"; 400 -> "Bad Request"; 404 -> "Not Found"; 502 -> "Bad Gateway"
            else -> "Status"
        }
    }
}
