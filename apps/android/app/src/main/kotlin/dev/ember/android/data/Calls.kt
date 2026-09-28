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
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.JsonNull
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

    /** Brings the page of an agent's execution history before what it shows into the view. */
    suspend fun historyOlder(key: String) { core.call("history.older", buildJsonObject { put("station", station); put("key", key) }) }

    /** The viewer has read the chat up to `seq`. */
    suspend fun read(thread: Long, seq: Long) { chat("chat.read", thread) { put("seq", seq) } }

    // ── connects (web/src/api.ts → stationApi) ──

    /** Changes a connect: any of `bind`, `mode`, `requireMention`, `enabled`, `slack`, `owner`. */
    suspend fun putConnect(id: String, body: JsonObject) { request("PUT", "/connects/${at(id)}", body) }
    suspend fun deleteConnect(id: String) { request("DELETE", "/connects/${at(id)}") }
    suspend fun reconnect(id: String) { request("POST", "/connects/${at(id)}/reconnect") }
    /** A single-session connect's session: `session` null makes a new one (named `title`). */
    suspend fun bindSession(connect: String, session: String?, title: String) {
        request("POST", "/connects/${at(connect)}/session", buildJsonObject { put("session", session); if (title.isNotBlank()) put("title", title) })
    }
    /** Who the Slack tokens are (null with the errors when they do not work). */
    suspend fun verifySlack(connect: String?, install: String?, appToken: String, botToken: String): Pair<SlackIdentity?, List<String>> {
        val r = request("POST", "/slack/verify", buildJsonObject {
            if (connect != null) put("connect", connect); if (install != null) put("install", install); put("appToken", appToken); put("botToken", botToken)
        }).jsonObject
        val identity = r["identity"]?.takeIf { it !is JsonNull }?.let { decode(SlackIdentity.serializer(), it) }
        return identity to (r["errors"]?.jsonArray?.map { it.jsonPrimitive.content } ?: emptyList())
    }
    /** A Slack workspace's app configuration token (its refresh token); answers which workspace. */
    suspend fun addConfigToken(refreshToken: String): String =
        request("POST", "/slack/config-tokens", buildJsonObject { put("refreshToken", refreshToken) }).jsonObject["teamId"]!!.jsonPrimitive.content
    /**
     * Makes a Slack app with ember's manifest in the workspace of `team`: its name and description, the rest as a new
     * app's. The station keeps it, waiting for its connect (the overview's `slackApps`); answers its app id.
     */
    suspend fun makeSlackApp(team: String, name: String, description: String): String =
        request("POST", "/slack/apps", buildJsonObject {
            put("team", team)
            put("settings", buildJsonObject {
                put("name", name); put("displayName", name); put("description", description); put("longDescription", ""); put("backgroundColor", "#F3E3D3")
                put("groups", buildJsonObject { SLACK_GROUPS.forEach { put(it, true) } })
            })
        }).jsonObject["appId"]!!.jsonPrimitive.content
    /** Drops an app made here from the waiting ones; it stays in Slack. */
    suspend fun dropSlackApp(appId: String) { request("DELETE", "/slack/apps/${at(appId)}") }
    /** The people of the Slack workspaces this station's connects are in, once each by email, and what could not be read. */
    suspend fun slackPeople(): Pair<List<SlackPerson>, List<String>> {
        val r = request("GET", "/slack/people").jsonObject
        val people = r["people"]?.takeIf { it !is JsonNull }?.let { decode(ListSerializer(SlackPerson.serializer()), it) } ?: emptyList()
        return people to (r["errors"]?.takeIf { it !is JsonNull }?.jsonArray?.map { it.jsonPrimitive.content } ?: emptyList())
    }
    /** Where to make a Slack app by hand from ember's manifest. */
    suspend fun createAppUrl(name: String): String =
        request("GET", "/slack/create-app-url?name=${at(name)}").jsonObject["url"]!!.jsonPrimitive.content
    /** A new connect; answers its id. */
    suspend fun createConnect(body: JsonObject): String = request("POST", "/connects", body).jsonObject["id"]!!.jsonPrimitive.content

    // ── profiles ──

    /** Changes a profile: any of `name`, `access`, `env`, `models`. */
    suspend fun putProfile(id: String, body: JsonObject) { request("PUT", "/profiles/${at(id)}", body) }
    suspend fun deleteProfile(id: String) { request("DELETE", "/profiles/${at(id)}") }
    suspend fun refreshQuota(id: String) { request("POST", "/profiles/${at(id)}/quota") }
    suspend fun startLogin(profile: String) { request("POST", "/profiles/${at(profile)}/login") }
    suspend fun cancelLogin(profile: String) { request("DELETE", "/profiles/${at(profile)}/login") }
    suspend fun loginCode(profile: String, code: String) { request("POST", "/profiles/${at(profile)}/login-code", buildJsonObject { put("code", code) }) }
    /** A subscription signed in before its profile exists: the station makes the profile when it succeeds. Answers the login's id. */
    suspend fun newLogin(runtime: String): String = request("POST", "/logins", buildJsonObject { put("runtime", runtime) }).jsonObject["id"]!!.jsonPrimitive.content
    suspend fun newLoginCode(id: String, code: String) { request("POST", "/logins/${at(id)}/code", buildJsonObject { put("code", code) }) }
    suspend fun dropLogin(id: String) { request("DELETE", "/logins/${at(id)}") }
    /** A keyed (or variables) profile, made only once its key is checked; answers its id. */
    suspend fun addProfile(runtime: String?, kind: String, key: String?): String = request("POST", "/profiles", buildJsonObject {
        if (runtime != null) put("runtime", runtime)
        put("access", buildJsonObject { put("kind", kind); if (key != null) put("key", key) })
    }).jsonObject["id"]!!.jsonPrimitive.content
    /** A profile on the machine's own login of `runtime` (one kept in a file); answers its id. */
    suspend fun useMachineLogin(runtime: String): String =
        request("POST", "/profiles/machine", buildJsonObject { put("runtime", runtime) }).jsonObject["id"]!!.jsonPrimitive.content

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
    suspend fun upload(name: String, bytes: ByteArray, width: Long?, height: Long?): Attachment {
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

    // ── background jobs and web services (web/src/Jobs.tsx) ──

    /** A background job (a web service's page finds its port by it). */
    suspend fun job(id: String): Job = decode(Job.serializer(), request("GET", "/jobs/${at(id)}"))
    /** A job's last `lines` lines of output, and when it last grew. */
    suspend fun jobLog(id: String, lines: Int): JobLog {
        val r = request("GET", "/jobs/${at(id)}/log?lines=$lines").jsonObject
        return JobLog(id, r["text"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content ?: "", r["outputAt"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content?.toDoubleOrNull()?.toLong())
    }
    /** Stops a job from the app (its agent is told who did). */
    suspend fun stopJob(id: String) { request("POST", "/jobs/${at(id)}/stop") }
}

/** A job's output as last read: whose, its last lines, when it last grew. */
class JobLog(val job: String, val text: String, val outputAt: Long?)

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

    suspend fun renameWorkspace(workspace: String, name: String) { call("PATCH", ws(workspace), buildJsonObject { put("name", name) }) }
    suspend fun deleteWorkspace(workspace: String) { call("DELETE", ws(workspace)) }
    /** Leaving a workspace is removing oneself. */
    suspend fun removeMember(workspace: String, member: String) { call("DELETE", "${ws(workspace)}/members/${at(member)}") }
    suspend fun setRole(workspace: String, member: String, role: String) { call("PATCH", "${ws(workspace)}/members/${at(member)}", buildJsonObject { put("role", role) }) }
    /** Adds people by email: members at once, or from their first sign-in; no invitation to accept. */
    suspend fun addMembers(workspace: String, role: String, emails: List<String>): AddedMembers {
        val r = call("POST", "${ws(workspace)}/members", buildJsonObject { put("role", role); putJsonArray("emails") { emails.forEach { add(JsonPrimitive(it)) } } }).jsonObject
        val list = { key: String -> r[key]?.takeIf { it !is JsonNull }?.jsonArray?.map { it.jsonPrimitive.content } ?: emptyList() }
        return AddedMembers(list("joined"), list("added"), list("already"))
    }
    /** An email added and not signed in yet, taken off. */
    suspend fun removeAdded(workspace: String, email: String) { call("DELETE", "${ws(workspace)}/added/${at(email)}") }
    suspend fun revokeInvitation(workspace: String, invitation: String) { call("DELETE", "${ws(workspace)}/invitations/${at(invitation)}") }
    /** A one-time token for a machine to join as a station: the installer's command, and the command for a machine that has ember. */
    suspend fun enroll(workspace: String, name: String): Enrollment =
        call("POST", "${ws(workspace)}/enrollments", buildJsonObject { put("name", name) }).jsonObject.let {
            Enrollment(it["install"]!!.jsonPrimitive.content, it["command"]!!.jsonPrimitive.content)
        }
    suspend fun renameStation(workspace: String, station: String, name: String) { call("PATCH", "${ws(workspace)}/stations/${at(station)}", buildJsonObject { put("name", name) }) }
    suspend fun removeStation(workspace: String, station: String) { call("DELETE", "${ws(workspace)}/stations/${at(station)}") }
    suspend fun revokeLoginSession(id: String) { call("DELETE", "/v1/auth/sessions/${at(id)}") }

    private fun ws(id: String) = "/v1/workspaces/${at(id)}"
}

class Enrollment(val install: String, val command: String)

/** The permission groups a new Slack app is made with (web/src/pages/SlackApp.tsx → GROUPS), all on. */
private val SLACK_GROUPS = listOf("base", "public", "dm", "customize", "files", "reactions", "channels", "people", "extras")

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
