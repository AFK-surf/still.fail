// The core for the motion tests: topics answered from values the test sets (and set again mid-motion: a message
// arriving, the station taking one), calls answered by the test's `answer`; what the app called is kept in `calls`.
package fail.still.android.motion

import fail.still.android.data.StillFailJson
import fail.still.core.CoreException
import fail.still.core.StillFailCore
import fail.still.core.scripted
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
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
    @Volatile private var reply: ((String) -> Unit)? = null

    /** How long (ms, on the system's clock) a topic's first value takes to come once subscribed, where not at once. */
    val lags = ConcurrentHashMap<JsonObject, Long>()

    /** Each call the app made: its name and params. */
    val calls = CopyOnWriteArrayList<Pair<String, JsonObject>>()

    /** The answer to a call (`ok`); throwing a [CoreException] answers it as an error. */
    @Volatile var answer: (name: String, params: JsonObject) -> JsonElement = { _, _ -> JsonNull }

    val core: StillFailCore = StillFailCore.scripted { json, reply -> handle(json, reply) }

    private fun handle(json: String, reply: (String) -> Unit) {
        this.reply = reply
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
        val name = m["call"]?.jsonPrimitive?.contentOrNull ?: return
        if (m["cancel"] != null) return
        val params = m["params"]?.jsonObject ?: JsonObject(emptyMap())
        calls += name to params
        val out = try {
            buildJsonObject { put("id", id); put("ok", answer(name, params)) }
        } catch (e: CoreException) {
            buildJsonObject { put("id", id); put("error", buildJsonObject { put("code", e.code); put("message", e.message) }) }
        }
        reply(out.toString())
    }

    private fun valueOf(id: Long, value: JsonElement) = buildJsonObject { put("id", id); put("value", value) }.toString()

    /** A topic's value from now on; those subscribed to it hear it at once. */
    fun set(topic: JsonObject, value: JsonElement) {
        values[topic] = value
        val to = reply ?: return
        subs.filterValues { it == topic }.keys.forEach { to(valueOf(it, value)) }
    }

    inline fun <reified T> put(topic: JsonObject, value: T) = set(topic, StillFailJson.encodeToJsonElement(value))

    /** Whether the app is subscribed to `topic` now. */
    fun subscribed(topic: JsonObject) = subs.containsValue(topic)
}
