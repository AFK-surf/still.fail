// Writes, through the core's calls (docs/client-core.md → Calls), with the
// paths and bodies the web pages use (web/src/api.ts → stationApi). After a
// write the core refreshes the topics it touches; nothing here keeps a cache.
package dev.ember.android.data

import android.util.Base64
import dev.ember.core.CoreException
import dev.ember.core.EmberCore
import java.net.URLEncoder
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
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

    private suspend fun chat(call: String, thread: Long, fill: kotlinx.serialization.json.JsonObjectBuilder.() -> Unit = {}) =
        core.call(call, buildJsonObject { put("station", station); put("thread", thread); fill() })

    /** Sends to the chat: the message shows at once from the view's outbox, and leaves it once the station has it. */
    suspend fun send(thread: Long, text: String, attachments: List<Attachment> = emptyList(), quotes: List<Quote> = emptyList()) {
        chat("chat.send", thread) {
            put("text", text)
            put("attachments", EmberJson.encodeToJsonElement(ListSerializer(Attachment.serializer()), attachments))
            put("quotes", EmberJson.encodeToJsonElement(ListSerializer(Quote.serializer()), quotes))
        }
    }

    /** A failed message from the outbox: send it again, or drop it. */
    suspend fun retry(thread: Long, id: String) { chat("chat.retry", thread) { put("id", id) } }
    suspend fun discard(thread: Long, id: String) { chat("chat.discard", thread) { put("id", id) } }

    /** Brings the page before the chat's first loaded message into the view. */
    suspend fun older(thread: Long) { chat("chat.older", thread) }

    /** The viewer has read the chat up to `seq`. */
    suspend fun read(thread: Long, seq: Long) { chat("chat.read", thread) { put("seq", seq) } }

    /** Starts the session's runtime ahead of a message. */
    suspend fun warm(key: String) { request("POST", "/sessions/${at(key)}/warm") }

    suspend fun stop(key: String) { request("POST", "/sessions/${at(key)}/stop") }

    /**
     * How it runs from its next turn on: a model, how hard it thinks, and who runs it (a profile kept to by hand, or
     * null: the station's pick).
     */
    suspend fun sessionSettings(key: String, model: String, effort: String?, profile: String?) {
        request("POST", "/sessions/${at(key)}/settings", buildJsonObject { put("model", model); put("effort", effort); put("profile", profile) })
    }

    /** Releases an idle agent's process. */
    suspend fun evict(key: String) { request("POST", "/sessions/${at(key)}/evict") }

    /** A new chat: its session and its thread, made before its first message so files can go into it. */
    suspend fun newChat(runtime: String, model: String, effort: String?): Pair<String, Long> =
        request("POST", "/sessions", buildJsonObject {
            put("runtime", runtime); put("model", model)
            if (effort != null) put("effort", effort)
        }).jsonObject.let { it["key"]!!.jsonPrimitive.content to it["thread"]!!.jsonObject["id"]!!.jsonPrimitive.long }

    /** The chat of an agent that has none yet, bound to its session; answers the thread. */
    suspend fun chatFor(session: String): Long =
        request("POST", "/threads", buildJsonObject { put("session", session) }).jsonObject["id"]!!.jsonPrimitive.long

    /** Checks a profile, which lists the models it can use. */
    suspend fun checkProfile(id: String) { request("POST", "/profiles/${at(id)}/check") }

    /** "这是我" (bound) or "不是我" on a Slack user: the station takes them for the viewer, or no longer. */
    suspend fun slackIdentity(user: String, bound: Boolean) { request(if (bound) "PUT" else "DELETE", "/me/slack/${at(user)}") }

    /** Replaces a profile's enabled models. */
    suspend fun setModels(profile: String, models: List<String>) {
        request("PUT", "/profiles/${at(profile)}", buildJsonObject { putJsonArray("models") { models.forEach { add(JsonPrimitive(it)) } } })
    }

    /** Puts a file on the station, in no chat yet; a message that sends it takes it into its chat. */
    suspend fun upload(name: String, bytes: ByteArray, width: Int?, height: Int?): Attachment {
        val saved = decode(Attachment.serializer(), core.call("station.upload", buildJsonObject {
            put("station", station); put("name", name); put("bytes", Base64.encodeToString(bytes, Base64.NO_WRAP))
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

/** ember cloud's account API, called as one of the signed-in accounts (web/src/cloud/api.ts). */
class Cloud(private val core: EmberCore, private val account: String) {
    private suspend fun call(method: String, path: String, body: JsonObject? = null): JsonElement =
        core.call("cloud.request", buildJsonObject {
            put("account", account); put("method", method); put("path", path)
            if (body != null) put("body", body)
        })

    /** `code`: an invite code, for an account not let in yet (ember is invite-only). Answers the new workspace's id. */
    suspend fun createWorkspace(name: String, code: String): String =
        call("POST", "/v1/workspaces", buildJsonObject { put("name", name); if (code.isNotEmpty()) put("invite_code", code) }).jsonObject["id"]!!.jsonPrimitive.content

    /** Answers the workspace joined. */
    suspend fun acceptInvitation(id: String): String = call("POST", "/v1/invitations/${at(id)}/accept").jsonObject["id"]!!.jsonPrimitive.content

    suspend fun declineInvitation(id: String) { call("POST", "/v1/invitations/${at(id)}/decline") }
}

// ember cloud's invite-code errors in Chinese; the core passes their codes through.
private val INVITE_ERRORS = mapOf(
    "invite_code_required" to "ember 目前只对受邀的人开放，需要邀请码才能新建 workspace",
    "invite_code_invalid" to "这个邀请码不对，检查一下有没有输错",
    "invite_code_used" to "这个邀请码已经被用过了",
    "invite_code_expired" to "这个邀请码已经过期了",
)

/** Whether creating a workspace failed for want of a (good) invite code. */
fun needsInviteCode(e: CoreException?): Boolean = e != null && e.code in INVITE_ERRORS

fun errorText(e: CoreException): String = INVITE_ERRORS[e.code] ?: e.message
