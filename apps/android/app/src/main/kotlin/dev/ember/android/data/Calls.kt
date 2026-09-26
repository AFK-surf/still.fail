// Writes, through the core's calls (docs/client-core.md → Calls), with the
// paths and bodies the web pages use (web/src/api.ts → stationApi). After a
// write the core refreshes the topics it touches; nothing here keeps a cache.
package dev.ember.android.data

import android.util.Base64
import dev.ember.core.EmberCore
import java.net.URLEncoder
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray

private fun at(id: String) = URLEncoder.encode(id, "UTF-8").replace("+", "%20")

/** The admin API of one station, by what each call does. */
class StationApi(private val core: EmberCore, val station: String) {
    private suspend fun request(method: String, path: String, body: JsonObject? = null): JsonElement =
        core.call("station.request", buildJsonObject {
            put("station", station); put("method", method); put("path", path)
            if (body != null) put("body", body)
        })

    private suspend fun chat(call: String, key: String, fill: kotlinx.serialization.json.JsonObjectBuilder.() -> Unit = {}) =
        core.call(call, buildJsonObject { put("station", station); put("key", key); fill() })

    /** Sends to the chat: the message shows at once from the view's outbox, and leaves it once the station has it. */
    suspend fun send(key: String, text: String, attachments: List<Attachment> = emptyList(), quotes: List<Quote> = emptyList()) {
        chat("chat.send", key) {
            put("text", text)
            put("attachments", EmberJson.encodeToJsonElement(ListSerializer(Attachment.serializer()), attachments))
            put("quotes", EmberJson.encodeToJsonElement(ListSerializer(Quote.serializer()), quotes))
        }
    }

    /** A failed message from the outbox: send it again, or drop it. */
    suspend fun retry(key: String, id: String) { chat("chat.retry", key) { put("id", id) } }
    suspend fun discard(key: String, id: String) { chat("chat.discard", key) { put("id", id) } }

    /** Brings the page before the chat's first shown message into the view. */
    suspend fun older(key: String) { chat("chat.older", key) }

    /** The viewer has read the chat up to `seq`. */
    suspend fun read(key: String, seq: Long) { chat("chat.read", key) { put("seq", seq) } }

    /** Starts the session's runtime ahead of a message. */
    suspend fun warm(key: String) { request("POST", "/sessions/${at(key)}/warm") }

    suspend fun stop(key: String) { request("POST", "/sessions/${at(key)}/stop") }

    /** Hides the chat from lists (docs/station-storage.md → Housekeeping). */
    suspend fun archive(key: String) { request("POST", "/sessions/${at(key)}/archive") }

    /** A new chat's session, made before its first message so files can go into it. */
    suspend fun newSession(runtime: String, model: String, effort: String?): String =
        request("POST", "/sessions", buildJsonObject {
            put("runtime", runtime); put("model", model)
            if (effort != null) put("effort", effort)
        }).jsonObject["key"]!!.jsonPrimitive.content

    /** Replaces a profile's enabled models. */
    suspend fun setModels(profile: String, models: List<String>) {
        request("PUT", "/profiles/${at(profile)}", buildJsonObject { putJsonArray("models") { models.forEach { add(JsonPrimitive(it)) } } })
    }

    /** Puts a file in the session's workspace on the station; send the result with a message. */
    suspend fun upload(key: String, name: String, bytes: ByteArray, width: Int?, height: Int?): Attachment {
        val saved = decode(Attachment.serializer(), core.call("station.upload", buildJsonObject {
            put("station", station); put("key", key); put("name", name); put("bytes", Base64.encodeToString(bytes, Base64.NO_WRAP))
        }))
        // An image's size travels with it, so every page can hold its place before it loads.
        return if (width != null && height != null) saved.copy(width = width, height = height) else saved
    }

    /** A file sent to the session. */
    suspend fun file(key: String, name: String): ByteArray {
        val answer = core.call("station.file", buildJsonObject { put("station", station); put("key", key); put("name", name) }).jsonObject
        return Base64.decode(answer["bytes"]!!.jsonPrimitive.content, Base64.DEFAULT)
    }
}

object Auth {
    const val REDIRECT = "ember://auth/callback"

    /** The URL to open in a Custom Tab; ember cloud comes back to REDIRECT. */
    suspend fun begin(core: EmberCore, deviceName: String): String =
        core.call("auth.begin", buildJsonObject { put("redirect_uri", REDIRECT); put("return_to", "/"); put("device_name", deviceName) })
            .jsonObject["url"]!!.jsonPrimitive.content

    /** Finishes a sign-in with the callback's query string ("?code=…&state=…"). */
    suspend fun complete(core: EmberCore, query: String) {
        core.call("auth.complete", buildJsonObject { put("query", query) })
    }

    suspend fun signOut(core: EmberCore, account: String) {
        core.call("auth.signOut", buildJsonObject { put("account", account) })
    }
}
