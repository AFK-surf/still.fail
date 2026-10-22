// Files picked on the phone, read by the core a part at a time as it sends them up (`picked.*`, client/core-ts
// hosts/bridge.ts): the app gives each a number (`composer.add`'s `blob: {hostFile, size, type}`), the core names its
// content first (`picked.hash`: a station that has it already copies its own), reads parts of it by that number while
// it goes up, and lets it go once it is up or taken out (a failed one is kept, to go again).
// As the desktop's page holds its picked files for its core (client/core-ts hosts/file-port.ts).
package fail.still.core

import java.io.InputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long

object PickedFiles {
    /** One picked file: where its bytes are read from, and the stream read last with how far it has gone. */
    private class Held(val size: Long, val open: () -> InputStream) {
        var stream: InputStream? = null
        var at = 0L
    }

    private val held = ConcurrentHashMap<Long, Held>()
    /** The most of a file read through to name its content before it goes up. */
    private const val HASHED_MAX = 256L * 1024 * 1024
    private val ids = AtomicLong(1)

    /** Holds a file of `size` bytes, read from `open` (opened again when a part is asked from before where it was): its number. */
    fun hold(size: Long, open: () -> InputStream): Long {
        val id = ids.getAndIncrement()
        held[id] = Held(size, open)
        return id
    }

    /** Lets a file go (the app took it out before the core had it). */
    fun release(id: Long) {
        held.remove(id)?.let { h -> synchronized(h) { runCatching { h.stream?.close() }; h.stream = null } }
    }

    /** A `picked.*` call: the answer's JSON and bytes. */
    fun answer(op: String, json: String): Pair<String, ByteArray?> {
        val a = Json.parseToJsonElement(json).jsonObject
        val id = a["file"]?.jsonPrimitive?.long ?: throw IllegalArgumentException("no file")
        return when (op) {
            "picked.read" -> {
                val h = held[id] ?: throw IllegalStateException("The picked file is no longer available")
                val start = a["start"]!!.jsonPrimitive.long
                val end = minOf(a["end"]!!.jsonPrimitive.long, h.size)
                require(start in 0..end) { "invalid file part" }
                "{}" to synchronized(h) { read(h, start, (end - start).toInt()) }
            }
            "picked.hash" -> {
                val h = held[id] ?: throw IllegalStateException("The picked file is no longer available")
                // Too big to read through first for it: sent as it is.
                if (h.size > HASHED_MAX) return "{}" to null
                val digest = java.security.MessageDigest.getInstance("SHA-256")
                h.open().use { input ->
                    val buf = ByteArray(1 shl 16)
                    while (true) { val n = input.read(buf); if (n < 0) break; digest.update(buf, 0, n) }
                }
                """{"sha256":"${digest.digest().joinToString("") { "%02x".format(it) }}"}""" to null
            }
            "picked.release" -> { release(id); "{}" to null }
            else -> throw IllegalArgumentException("no operation $op")
        }
    }

    /** `count` bytes from `start`: on from the stream read last when it is there, else from a stream opened anew. */
    private fun read(h: Held, start: Long, count: Int): ByteArray {
        var s = h.stream
        if (s == null || h.at != start) {
            runCatching { s?.close() }
            s = h.open()
            var left = start
            while (left > 0) { val n = s.skip(left); if (n <= 0) throw java.io.IOException("short file"); left -= n }
            h.stream = s
            h.at = start
        }
        val part = ByteArray(count)
        var got = 0
        while (got < count) { val n = s.read(part, got, count - got); if (n < 0) throw java.io.IOException("short file"); got += n }
        h.at += got
        // All of it read: nothing more is asked unless it goes again (from its start).
        if (h.at >= h.size) { runCatching { s.close() }; h.stream = null }
        return part
    }
}
