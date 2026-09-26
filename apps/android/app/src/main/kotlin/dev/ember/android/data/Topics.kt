// Screens read the core's topics as typed values: a topic's JSON is decoded
// here, with the shapes of the area files (Chats.kt, Stations.kt, Chat.kt,
// Accounts.kt), so a changed shape is fixed in one place.
package dev.ember.android.data

import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.produceState
import dev.ember.core.CoreException
import dev.ember.core.EmberCore
import dev.ember.core.TopicState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.serializer

val EmberJson = Json { ignoreUnknownKeys = true; explicitNulls = false; coerceInputValues = true }

/** A topic's value as a screen sees it: the value (kept through a later error), why it failed, whether it is still coming. */
data class Topic<T>(val value: T?, val error: CoreException?, val loading: Boolean)

/** The core sends every number as a float (1790000000000.0); whole ones become integers, so they decode into Int and Long. */
private fun whole(json: JsonElement): JsonElement = when (json) {
    is JsonObject -> JsonObject(json.mapValues { whole(it.value) })
    is JsonArray -> JsonArray(json.map(::whole))
    is JsonPrimitive -> {
        val d = if (json.isString) null else json.content.toDoubleOrNull()
        if (d != null && d == Math.floor(d) && !d.isInfinite() && Math.abs(d) < 9.0e15 && (json.content.contains('.') || json.content.contains('e', ignoreCase = true))) JsonPrimitive(d.toLong()) else json
    }
}

fun <T> decode(serializer: KSerializer<T>, json: JsonElement): T = try {
    EmberJson.decodeFromJsonElement(serializer, whole(json))
} catch (e: IllegalArgumentException) {
    throw CoreException("decode", "读不懂 core 给的数据：${e.message?.take(200)}", null)
}

/** Subscribes while in composition; `topic` null subscribes to nothing. */
@Composable
fun <T> rememberTopic(core: EmberCore, topic: JsonObject?, serializer: KSerializer<T>): State<Topic<T>> =
    produceState(Topic<T>(null, null, topic != null), core, topic) {
        if (topic == null) return@produceState
        core.topic(topic).map<TopicState, Topic<T>> { state ->
            try {
                Topic(state.value?.takeIf { it !is JsonNull }?.let { decode(serializer, it) }, state.error, state.loading)
            } catch (e: CoreException) {
                // What this app cannot read is its bug or the core's: recorded with the rest of the trace, not only shown.
                try {
                    core.call("client.error", buildJsonObject { put("source", "android.decode"); put("message", "${topic["topic"]}: ${e.message}") })
                } catch (_: CoreException) {
                    // Recording it failed too: the page still says what went wrong.
                }
                Topic(null, e, false)
            }
        }
            // Decoding a whole value (a chat is all its messages) is work: off the main thread, and only the latest
            // when several come at once (a chat being fetched arrives in batches).
            .flowOn(Dispatchers.Default)
            .conflate()
            .collect { next -> value = if (next.value == null && next.error != null) next.copy(value = value.value) else next }
    }

@Composable
inline fun <reified T> rememberTopic(core: EmberCore, topic: JsonObject?): State<Topic<T>> = rememberTopic(core, topic, serializer<T>())

object Topics {
    val accounts = buildJsonObject { put("topic", "accounts") }
    val workspaces = buildJsonObject { put("topic", "workspaces") }
    fun chats(scope: String, mine: Boolean) = buildJsonObject { put("topic", "chats"); put("scope", scope); put("mine", mine) }
    fun stations(scope: String) = buildJsonObject { put("topic", "stations"); put("scope", scope) }
    fun workspace(id: String) = buildJsonObject { put("topic", "workspace"); put("workspace", id) }
    fun overview(station: String) = buildJsonObject { put("topic", "overview"); put("station", station) }
    fun host(station: String) = buildJsonObject { put("topic", "host"); put("station", station) }
    /** An item's page: its chat, or its agent before it has one. */
    fun chat(station: String, of: ChatOf) = buildJsonObject {
        put("topic", "chat"); put("station", station)
        when (of) { is ChatOf.Thread -> put("thread", of.id); is ChatOf.Session -> put("session", of.key) }
    }
    fun live(station: String, key: String) = buildJsonObject { put("topic", "live"); put("station", station); put("key", key) }
    /** An agent's execution history, read for people (the core's). */
    fun history(station: String, key: String) = buildJsonObject { put("topic", "history"); put("station", station); put("key", key) }
}

/** What an item's page is of: its chat's thread, or its agent's session while it has no chat. */
sealed interface ChatOf {
    data class Thread(val id: Long) : ChatOf
    data class Session(val key: String) : ChatOf
}

/** A row's page. */
/** A row's page: its agent's, chat or no chat (the core shows the chat once there is one). */
val ChatItem.page: ChatOf get() = ChatOf.Session(session)
