// The core for the motion tests: topics answered from values the test sets (and set again mid-motion: a message
// arriving, the station taking one), calls answered by the test's `answer`; what the app called is kept in `calls`, the
// bytes it sent beside them in `carried`. Calls named in `streams` (`screen.view`) are held open: the test says their
// values (with bytes beside them, as a screen's frames come) and ends them. An answer's `bytes` (base64, as a test writes
// them) go beside it, as the core sends a file; a part read with `stream` (`drive.read`, `station.file.part`) has them
// said beside a value before it, and none beside the answer.
package fail.still.android.motion

import android.util.Base64
import fail.still.android.data.StillFailJson
import fail.still.core.CoreException
import fail.still.core.StillFailCore
import fail.still.core.scriptedBytes
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlinx.serialization.json.put

class FakeCore {
    private val values = ConcurrentHashMap<JsonObject, JsonElement>()
    private val subs = ConcurrentHashMap<Long, JsonObject>()
    @Volatile private var reply: ((String, ByteArray?) -> Unit)? = null

    /** How long (ms, on the system's clock) a topic's first value takes to come once subscribed, where not at once. */
    val lags = ConcurrentHashMap<JsonObject, Long>()

    /** Each call the app made: its name and params. */
    val calls = CopyOnWriteArrayList<Pair<String, JsonObject>>()
    /** The bytes each of [calls] carried beside its params (an upload's part), null for one with none; in `answer`, the last is its call's. */
    val carried = CopyOnWriteArrayList<ByteArray?>()

    /** The answer to a call (`ok`); throwing a [CoreException] answers it as an error. */
    @Volatile var answer: (name: String, params: JsonObject) -> JsonElement = { _, _ -> JsonNull }

    /**
     * Calls that say how they go before they answer (`station.preview` with `stream`), by name: each value said through
     * `say` with the bytes beside it, then its answer; the bytes the call carried come with its params. Off the app's
     * threads, as the core's.
     */
    val talks = ConcurrentHashMap<String, (params: JsonObject, bytes: ByteArray?, say: (JsonElement, ByteArray?) -> Unit) -> JsonElement>()

    /** The calls held open rather than answered (a screen's view), by name. */
    val streams: MutableSet<String> = ConcurrentHashMap.newKeySet()
    /** The open ones now: name → their request's id. */
    private val open = ConcurrentHashMap<String, Long>()
    /** The streamed calls the app cancelled, by name. */
    val cancelled = CopyOnWriteArrayList<String>()

    val core: StillFailCore = StillFailCore.scriptedBytes { json, bytes, reply -> this.reply = reply; handle(json, bytes, reply) }

    private fun handle(json: String, sent: ByteArray?, replyBytes: (String, ByteArray?) -> Unit) {
        val reply = { text: String -> replyBytes(text, null) }
        val m = Json.parseToJsonElement(json).jsonObject
        val id = m["id"]!!.jsonPrimitive.long
        m["subscribe"]?.let { topic ->
            subs[id] = topic.jsonObject
            val value = values[topic.jsonObject] ?: return
            // As long as the real core takes to answer it (reading the device's database), off this thread.
            val lag = lags[topic.jsonObject]
            if (lag == null) reply(valueOf(id, value)) else Thread { Thread.sleep(lag); if (subs[id] == topic.jsonObject) reply(valueOf(id, value)) }.start()
            return
        }
        if (m["unsubscribe"] != null) { subs.remove(id); return }
        if (m["cancel"] != null) {
            open.entries.firstOrNull { it.value == id }?.let { open.remove(it.key); cancelled += it.key }
            return
        }
        val name = m["call"]?.jsonPrimitive?.contentOrNull ?: return
        val params = m["params"]?.jsonObject ?: JsonObject(emptyMap())
        carried += sent
        calls += name to params
        if (name in streams) { open[name] = id; return }
        talks[name]?.let { talk ->
            Thread {
                val out = try {
                    val ok = talk(params, sent) { value, bytes -> replyBytes(valueOf(id, value), bytes) }
                    buildJsonObject { put("id", id); put("ok", ok) }
                } catch (e: CoreException) {
                    buildJsonObject { put("id", id); put("error", buildJsonObject { put("code", e.code); put("message", e.message) }) }
                }
                reply(out.toString())
            }.start()
            return
        }
        var beside: ByteArray? = null
        val out = try {
            var ok = answer(name, params)
            val bytes = ((ok as? JsonObject)?.get("bytes") as? JsonPrimitive)?.takeIf { it.isString }?.content
            if (bytes != null) {
                val raw = Base64.decode(bytes, Base64.DEFAULT)
                ok = JsonObject((ok as JsonObject) - "bytes")
                if (params["stream"]?.jsonPrimitive?.booleanOrNull != true) beside = raw
                else if (raw.isNotEmpty()) replyBytes(valueOf(id, buildJsonObject { put("loaded", raw.size) }), raw)
            }
            buildJsonObject { put("id", id); put("ok", ok) }
        } catch (e: CoreException) {
            buildJsonObject { put("id", id); put("error", buildJsonObject { put("code", e.code); put("message", e.message) }) }
        }
        replyBytes(out.toString(), beside)
    }

    private fun valueOf(id: Long, value: JsonElement) = buildJsonObject { put("id", id); put("value", value) }.toString()

    /** A topic's value from now on; those subscribed to it hear it at once. */
    fun set(topic: JsonObject, value: JsonElement) {
        values[topic] = value
        val to = reply ?: return
        subs.filterValues { it == topic }.keys.forEach { to(valueOf(it, value), null) }
    }

    inline fun <reified T> put(topic: JsonObject, value: T) = set(topic, StillFailJson.encodeToJsonElement(value))

    /** Whether the streamed call `name` is open now. */
    fun opened(name: String) = open.containsKey(name)

    /** A value of the open call `name` (`{id, value}`), with `bytes` beside it when given. */
    fun say(name: String, value: JsonElement, bytes: ByteArray? = null) {
        val id = open[name] ?: error("$name is not open")
        reply?.invoke(valueOf(id, value), bytes)
    }

    /** The open call `name` answered (it ended). */
    fun finish(name: String, ok: JsonElement = JsonNull) {
        val id = open.remove(name) ?: return
        reply?.invoke(buildJsonObject { put("id", id); put("ok", ok) }.toString(), null)
    }

    /** The open call `name` failed (`{id, error}`). */
    fun fail(name: String, code: String, message: String) {
        val id = open.remove(name) ?: return
        reply?.invoke(buildJsonObject { put("id", id); put("error", buildJsonObject { put("code", code); put("message", message) }) }.toString(), null)
    }

    /** Whether the app is subscribed to `topic` now. */
    fun subscribed(topic: JsonObject) = subs.containsValue(topic)
}
