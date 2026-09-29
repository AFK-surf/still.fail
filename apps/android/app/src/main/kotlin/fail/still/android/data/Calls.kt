// What the app has done, through the core's calls by name (docs/client-core.md → Calls; client/core/src/ops.rs), as
// the web pages do (web/src/api.ts → stationApi). The app never makes a request itself: the core knows the request
// and brings the topics it touches up to date before it answers; nothing here keeps a cache.
package fail.still.android.data

import android.util.Base64
import fail.still.core.CoreException
import fail.still.core.StillFailCore
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


/** The admin API of one station, by what each call does. */
class StationApi(private val core: StillFailCore, val station: String) {
    private suspend fun op(name: String, fill: kotlinx.serialization.json.JsonObjectBuilder.() -> Unit = {}): JsonElement =
        core.call(name, buildJsonObject { fill(); put("station", station) })

    private suspend fun chat(call: String, thread: Long, fill: kotlinx.serialization.json.JsonObjectBuilder.() -> Unit = {}) =
        core.call(call, buildJsonObject { put("station", station); put("thread", thread); fill() })

    /** Sends to the chat: the message shows at once from the view's outbox, and leaves it once the station has it. */
    suspend fun send(thread: Long, text: String, attachments: List<Attachment> = emptyList(), quotes: List<Quote> = emptyList()) {
        chat("chat.send", thread) {
            put("text", text)
            put("attachments", StillFailJson.encodeToJsonElement(ListSerializer(Attachment.serializer()), attachments))
            put("quotes", StillFailJson.encodeToJsonElement(ListSerializer(Quote.serializer()), quotes))
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
    suspend fun putConnect(id: String, body: JsonObject) { op("connect.put") { put("id", id); put("input", body) } }
    suspend fun deleteConnect(id: String) { op("connect.delete") { put("id", id) } }
    suspend fun reconnect(id: String) { op("connect.reconnect") { put("id", id) } }
    /** A single-session connect's session: `session` null makes a new one (named `title`). */
    suspend fun bindSession(connect: String, session: String?, title: String) {
        op("connect.bindSession") { put("connect", connect); put("session", session); if (title.isNotBlank()) put("title", title) }
    }
    /** Who the Slack tokens are (null with the errors when they do not work). */
    suspend fun verifySlack(connect: String?, install: String?, appToken: String, botToken: String): Pair<SlackIdentity?, List<String>> {
        val r = op("slack.verify") {
            if (connect != null) put("connect", connect); if (install != null) put("install", install); put("appToken", appToken); put("botToken", botToken)
        }.jsonObject
        val identity = r["identity"]?.takeIf { it !is JsonNull }?.let { decode(SlackIdentity.serializer(), it) }
        return identity to (r["errors"]?.jsonArray?.map { it.jsonPrimitive.content } ?: emptyList())
    }
    /** A Slack workspace's app configuration token (its refresh token); answers which workspace. */
    suspend fun addConfigToken(refreshToken: String): String =
        op("slack.addConfigToken") { put("refreshToken", refreshToken) }.jsonObject["teamId"]!!.jsonPrimitive.content
    /**
     * Makes a Slack app with still.fail's manifest in the workspace of `team`: its name and description, the rest as a new
     * app's. The station keeps it, waiting for its connect (the overview's `slackApps`); answers its app id.
     */
    suspend fun makeSlackApp(team: String, name: String, description: String): String =
        op("slack.makeApp") {
            put("team", team)
            put("settings", buildJsonObject {
                put("name", name); put("displayName", name); put("description", description); put("longDescription", ""); put("backgroundColor", "#F3E3D3")
                put("groups", buildJsonObject { SLACK_GROUPS.forEach { put(it, true) } })
            })
        }.jsonObject["appId"]!!.jsonPrimitive.content
    /** Drops an app made here from the waiting ones; it stays in Slack. */
    suspend fun dropSlackApp(appId: String) { op("slack.dropApp") { put("appId", appId) } }
    /** The people of the Slack workspaces this station's connects are in, once each by email, and what could not be read. */
    suspend fun slackPeople(): Pair<List<SlackPerson>, List<String>> {
        val r = op("slack.people").jsonObject
        val people = r["people"]?.takeIf { it !is JsonNull }?.let { decode(ListSerializer(SlackPerson.serializer()), it) } ?: emptyList()
        return people to (r["errors"]?.takeIf { it !is JsonNull }?.jsonArray?.map { it.jsonPrimitive.content } ?: emptyList())
    }
    /** Where to make a Slack app by hand from still.fail's manifest. */
    suspend fun createAppUrl(name: String): String =
        op("slack.createAppUrl") { put("name", name) }.jsonObject["url"]!!.jsonPrimitive.content
    /** A new connect; answers its id. */
    suspend fun createConnect(body: JsonObject): String = op("connect.create") { put("input", body) }.jsonObject["id"]!!.jsonPrimitive.content

    // ── profiles ──

    /** Changes a profile: any of `name`, `access`, `env`, `models`. */
    suspend fun putProfile(id: String, body: JsonObject) { op("profile.put") { put("id", id); put("input", body) } }
    suspend fun deleteProfile(id: String) { op("profile.delete") { put("id", id) } }
    suspend fun refreshQuota(id: String) { op("profile.quota") { put("id", id) } }
    suspend fun startLogin(profile: String) { op("profile.login") { put("id", profile) } }
    suspend fun cancelLogin(profile: String) { op("profile.cancelLogin") { put("id", profile) } }
    suspend fun loginCode(profile: String, code: String) { op("profile.loginCode") { put("id", profile); put("code", code) } }
    /** A subscription signed in before its profile exists: the station makes the profile when it succeeds. Answers the login's id. */
    suspend fun newLogin(runtime: String): String = op("login.new") { put("runtime", runtime) }.jsonObject["id"]!!.jsonPrimitive.content
    suspend fun newLoginCode(id: String, code: String) { op("login.code") { put("id", id); put("code", code) } }
    suspend fun dropLogin(id: String) { op("login.drop") { put("id", id) } }
    /** A keyed (or variables) profile, made only once its key is checked; answers its id. */
    suspend fun addProfile(runtime: String?, kind: String, key: String?): String = op("profile.add") {
        if (runtime != null) put("runtime", runtime)
        put("access", buildJsonObject { put("kind", kind); if (key != null) put("key", key) })
    }.jsonObject["id"]!!.jsonPrimitive.content
    /** A profile on the machine's own login of `runtime` (one kept in a file); answers its id. */
    suspend fun useMachineLogin(runtime: String): String =
        op("profile.useMachineLogin") { put("runtime", runtime) }.jsonObject["id"]!!.jsonPrimitive.content

    /** Starts the session's runtime ahead of a message. */
    suspend fun warm(key: String) { op("session.warm") { put("key", key) } }

    suspend fun stop(key: String) { op("session.stop") { put("key", key) } }

    /**
     * How it runs from its next turn on: a model, how hard it thinks, and who runs it (a profile kept to by hand, or
     * null: the station's pick).
     */
    suspend fun sessionSettings(key: String, model: String, effort: String?, profile: String?) {
        op("session.settings") { put("key", key); put("model", model); put("effort", effort); put("profile", profile) }
    }

    /** Releases an idle agent's process. */
    suspend fun evict(key: String) { op("session.evict") { put("key", key) } }

    /** A new chat: its session and its thread, made before its first message so files can go into it. */
    suspend fun newChat(runtime: String, model: String, effort: String?): Pair<String, Long> =
        op("session.new") {
            put("runtime", runtime); put("model", model)
            if (effort != null) put("effort", effort)
        }.jsonObject.let { it["key"]!!.jsonPrimitive.content to it["thread"]!!.jsonObject["id"]!!.jsonPrimitive.long }

    /** The chat of an agent that has none yet, bound to its session; answers the thread. */
    suspend fun chatFor(session: String): Long =
        op("chat.forSession") { put("session", session) }.jsonObject["id"]!!.jsonPrimitive.long

    /** Checks a profile, which lists the models it can use. */
    suspend fun checkProfile(id: String) { op("profile.check") { put("id", id) } }

    /** "这是我" (bound) or "不是我" on a Slack user: the station takes them for the viewer, or no longer. */
    suspend fun slackIdentity(user: String, bound: Boolean) { op("slack.identity") { put("user", user); put("bound", bound) } }

    /** Replaces a profile's enabled models. */
    suspend fun setModels(profile: String, models: List<String>) {
        op("profile.put") { put("id", profile); put("input", buildJsonObject { putJsonArray("models") { models.forEach { add(JsonPrimitive(it)) } } }) }
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
    suspend fun job(id: String): Job = decode(Job.serializer(), op("job.get") { put("id", id) })
    /** A job's last `lines` lines of output, and when it last grew. */
    suspend fun jobLog(id: String, lines: Int): JobLog {
        val r = op("job.log") { put("id", id); put("lines", lines) }.jsonObject
        return JobLog(id, r["text"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content ?: "", r["outputAt"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content?.toDoubleOrNull()?.toLong())
    }
    /** Stops a job from the app (its agent is told who did). */
    suspend fun stopJob(id: String) { op("job.stop") { put("id", id) } }
}

/** A job's output as last read: whose, its last lines, when it last grew. */
class JobLog(val job: String, val text: String, val outputAt: Long?)

object Auth {
    // stillfail:// since the rename; the app still accepts ember:// coming back (MainActivity), and the cloud both.
    const val REDIRECT = "stillfail://auth/callback"

    /** The URL to open in a Custom Tab; still.fail cloud comes back to REDIRECT. */
    suspend fun begin(core: StillFailCore, deviceName: String): String =
        core.call("auth.begin", buildJsonObject { put("redirect_uri", REDIRECT); put("return_to", "/"); put("device_name", deviceName) })
            .jsonObject["url"]!!.jsonPrimitive.content

    /** Finishes a sign-in with the callback's query string ("?code=…&state=…"). */
    suspend fun complete(core: StillFailCore, query: String) {
        core.call("auth.complete", buildJsonObject { put("query", query) })
    }

    suspend fun signOut(core: StillFailCore, account: String) {
        core.call("auth.signOut", buildJsonObject { put("account", account) })
    }
}

/** still.fail cloud's account API: what the app has done there, by name, done by the core as one of the signed-in accounts (web/src/cloud/api.ts). */
class Cloud(private val core: StillFailCore, private val account: String) {
    private suspend fun op(name: String, fill: kotlinx.serialization.json.JsonObjectBuilder.() -> Unit = {}): JsonElement =
        core.call(name, buildJsonObject { fill(); put("account", account) })

    /** `code`: an invite code, for an account not let in yet (still.fail is invite-only). Answers the new workspace's id. */
    suspend fun createWorkspace(name: String, code: String): String =
        op("workspace.create") { put("name", name); if (code.isNotEmpty()) put("invite_code", code) }.jsonObject["id"]!!.jsonPrimitive.content

    /** Answers the workspace joined. */
    suspend fun acceptInvitation(id: String): String = op("invitation.accept") { put("id", id) }.jsonObject["id"]!!.jsonPrimitive.content

    suspend fun declineInvitation(id: String) { op("invitation.decline") { put("id", id) } }

    suspend fun renameWorkspace(workspace: String, name: String) { op("workspace.rename") { put("workspace", workspace); put("name", name) } }
    suspend fun deleteWorkspace(workspace: String) { op("workspace.delete") { put("workspace", workspace) } }
    /** Leaving a workspace is removing oneself. */
    suspend fun removeMember(workspace: String, member: String) { op("workspace.removeMember") { put("workspace", workspace); put("member", member) } }
    suspend fun setRole(workspace: String, member: String, role: String) { op("workspace.setRole") { put("workspace", workspace); put("member", member); put("role", role) } }
    /** Adds people by email: members at once, or from their first sign-in; no invitation to accept. */
    suspend fun addMembers(workspace: String, role: String, emails: List<String>): AddedMembers {
        val r = op("workspace.addMembers") { put("workspace", workspace); put("role", role); putJsonArray("emails") { emails.forEach { add(JsonPrimitive(it)) } } }.jsonObject
        val list = { key: String -> r[key]?.takeIf { it !is JsonNull }?.jsonArray?.map { it.jsonPrimitive.content } ?: emptyList() }
        return AddedMembers(list("joined"), list("added"), list("already"))
    }
    /** An email added and not signed in yet, taken off. */
    suspend fun removeAdded(workspace: String, email: String) { op("workspace.removeAdded") { put("workspace", workspace); put("email", email) } }
    suspend fun revokeInvitation(workspace: String, invitation: String) { op("workspace.revokeInvitation") { put("workspace", workspace); put("invitation", invitation) } }
    /** A one-time token for a machine to join as a station: the installer's command, and the command for a machine that has ember. */
    suspend fun enroll(workspace: String, name: String): Enrollment =
        op("workspace.enroll") { put("workspace", workspace); put("name", name) }.jsonObject.let {
            Enrollment(it["install"]!!.jsonPrimitive.content, it["command"]!!.jsonPrimitive.content)
        }
    suspend fun renameStation(workspace: String, station: String, name: String) { op("workspace.renameStation") { put("workspace", workspace); put("station", station); put("name", name) } }
    suspend fun removeStation(workspace: String, station: String) { op("workspace.removeStation") { put("workspace", workspace); put("station", station) } }
    suspend fun revokeLoginSession(id: String) { op("loginSession.revoke") { put("id", id) } }
}

class Enrollment(val install: String, val command: String)

/** The permission groups a new Slack app is made with (web/src/pages/SlackApp.tsx → GROUPS), all on. */
private val SLACK_GROUPS = listOf("base", "public", "dm", "customize", "files", "reactions", "channels", "people", "extras")

// still.fail cloud's invite-code errors in Chinese; the core passes their codes through.
private val INVITE_ERRORS = mapOf(
    "invite_code_required" to "still.fail 目前只对受邀的人开放，需要邀请码才能新建 workspace",
    "invite_code_invalid" to "这个邀请码不对，检查一下有没有输错",
    "invite_code_used" to "这个邀请码已经被用过了",
    "invite_code_expired" to "这个邀请码已经过期了",
)

/** Whether creating a workspace failed for want of a (good) invite code. */
fun needsInviteCode(e: CoreException?): Boolean = e != null && e.code in INVITE_ERRORS

fun errorText(e: CoreException): String = INVITE_ERRORS[e.code] ?: e.message
