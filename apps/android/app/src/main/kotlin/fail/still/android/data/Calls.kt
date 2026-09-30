// What the app has done, through the core's calls by name (docs/client-core.md → Calls; client/core/src/ops.rs), as
// the web pages do (web/src/api.ts → stationApi). The app never makes a request itself: the core knows the request
// and brings the topics it touches up to date before it answers; nothing here keeps a cache.
package fail.still.android.data

import android.util.Base64
import fail.still.android.BuildConfig
import fail.still.core.CoreException
import fail.still.core.StillFailCore
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray


/** Which app a message is sent from ("android 0.1.1123"): the station tells the chat's agent; never shown. */
private val SENT_FROM = "android " + BuildConfig.VERSION_NAME

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
            put("client", SENT_FROM)
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

    /**
     * A file sent to the session, and its type as the station says (web/src/api.ts → file). `thumb`: an image as a chat
     * shows it (its thumbnail, where the station keeps one; an older station answers the image itself). `onProgress`:
     * the bytes so far and the whole size (null when the station does not say) as a whole file comes.
     */
    suspend fun file(key: String, name: String, thumb: Boolean, onProgress: ((Long, Long?) -> Unit)? = null): Pair<String, ByteArray> {
        val params = buildJsonObject {
            put("station", station); put("key", key); put("name", name)
            if (thumb) put("thumb", true)
            if (onProgress != null) put("progress", true)
        }
        val answer = (if (onProgress == null) core.call("station.file", params) else core.call("station.file", params) { got ->
            val o = got as? JsonObject
            val loaded = (o?.get("loaded") as? JsonPrimitive)?.content?.toLongOrNull()
            if (loaded != null) onProgress(loaded, (o["total"] as? JsonPrimitive)?.content?.toLongOrNull())
        }).jsonObject
        val type = (answer["type"] as? JsonPrimitive)?.content ?: ""
        return type to Base64.decode(answer["bytes"]!!.jsonPrimitive.content, Base64.DEFAULT)
    }

    /** What a visualization's widget kept (widget.state; null when nothing, or an older station that keeps nothing). */
    suspend fun widgetState(key: String, path: String): JsonElement? =
        op("widget.state") { put("key", key); put("path", path) }.jsonObject["state"]?.takeIf { it !is JsonNull }
    /** Keeps what a visualization's widget asks to keep (widget.setState), for the next time it is shown. */
    suspend fun setWidgetState(key: String, path: String, state: JsonElement) {
        op("widget.setState") { put("key", key); put("path", path); put("state", state) }
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
    /** Clears a session's ended jobs (stopped, failed, ended by itself) off its pages, as the station keeps them. */
    suspend fun clearEndedJobs(session: String) { op("job.clearEnded") { put("session", session) } }

    // ── the archive (web/src/pages/Archive.tsx) ──

    /** The archive's items; a station from before it answers its shown ones (none say `archived`), so none. */
    suspend fun archivedChats(): List<ArchivedChat> =
        decode(ListSerializer(ArchivedChat.serializer()), op("chats.archived")).filter { it.archived != null }
    /** A chat into the archive or back: its thread (with its session when it is that session's own), or an agent with no chat yet. */
    suspend fun setArchived(thread: Long?, session: String, archived: Boolean) {
        op("chat.archive") { put("session", session); if (thread != null) put("thread", thread); put("archived", archived) }
    }
    /** Keeps a chat at the top of the viewer's list, or lets it go (by its item's id, its session's key). */
    suspend fun setPinned(session: String, pinned: Boolean) { op("chat.pin") { put("session", session); put("pinned", pinned) } }
    /** Deletes a session for good: its chat, its history and its workspace directory. */
    suspend fun deleteSession(key: String) { op("session.delete") { put("key", key) } }

    // ── a new chat (web/src/NewChat.tsx → useEnsureChat) ──

    /**
     * A new chat, there at once: the core has its page, its row and what is sent to it under the key it answers (the
     * station makes it behind it, told that key as `clientKey`, so its row is known for this one's, never guessed).
     * `profile`: the one kept to, or null for the station's pick.
     */
    suspend fun createChat(runtime: String, model: String, effort: String?, profile: String?): String =
        core.call("chat.create", buildJsonObject {
            put("station", station); put("runtime", runtime); put("model", model)
            if (effort != null) put("effort", effort)
            if (profile != null) put("profile", profile)
        }).jsonObject["key"]!!.jsonPrimitive.content

    // ── the machine's own sessions (web/src/MachineSessions.tsx) ──

    /** Sessions the machine's own Claude Code and Codex kept (in a terminal); a station from before them fails it. */
    suspend fun machineSessions(): List<MachineSession> =
        decode(ListSerializer(MachineSession.serializer()), op("machineSessions.list").jsonObject["sessions"] ?: JsonArray(emptyList()))
    /** One of them to look at first: what was said in it (the latest `limit`), and how many there are in all. */
    suspend fun machineSession(runtime: String, id: String, limit: Int = 200): Pair<List<MachineSaid>, Long> {
        val r = op("machineSessions.read") { put("runtime", runtime); put("id", id); put("limit", limit) }.jsonObject
        val said = decode(ListSerializer(MachineSaid.serializer()), r["said"] ?: JsonArray(emptyList()))
        return said to (r["total"]?.jsonPrimitive?.content?.toDoubleOrNull()?.toLong() ?: said.size.toLong())
    }
    /** A chat going on with one of them (the one already going on with it, if any); answers its key. */
    suspend fun continueMachineSession(runtime: String, id: String): String =
        op("machineSessions.continue") { put("runtime", runtime); put("id", id) }.jsonObject["key"]!!.jsonPrimitive.content

    // ── the station's software, its memory, Slack apps (web/src/api.ts → stationApi) ──

    /** Updates the station or a runtime (`id`: station | claude | codex), or installs a runtime not there; the overview says how it goes. */
    suspend fun updateSoftware(id: String) { op("software.update") { put("id", id) } }
    /** Reads again what versions are out. */
    suspend fun checkSoftware() { op("software.check") }
    /** The agents' memory on the station: the global one and the skills (projects' memories among them), as they are. */
    suspend fun memory(): JsonElement = op("memory.get")
    /**
     * Writes what changed of a connect's Slack app (any of name, displayName, description, longDescription,
     * backgroundColor, groups; `icon`: a data URL) into its manifest; answers whether Slack wants its new permissions
     * approved, and why the icon did not go up.
     */
    suspend fun putSlackApp(connect: String, input: JsonObject): JsonObject = op("connect.putSlackApp") { put("connect", connect); put("input", input) }.jsonObject
    /** A Slack app made with its settings as a whole (and its icon, a data URL); answers its app id and why the icon did not go up. */
    suspend fun makeSlackApp(team: String, settings: JsonObject, icon: String?): Pair<String, String?> {
        val r = op("slack.makeApp") { put("team", team); put("settings", settings); if (icon != null) put("icon", icon) }.jsonObject
        return r["appId"]!!.jsonPrimitive.content to r["iconError"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content
    }
    /** Forgets the viewer's configuration token of a Slack workspace. */
    suspend fun removeConfigToken(team: String) { op("slack.removeConfigToken") { put("team", team) } }
    /** Hands Slack's install code to the station that made the app; answers the workspace it went into. */
    suspend fun slackInstalled(code: String, state: String): String? =
        op("slack.installed") { put("code", code); put("state", state) }.jsonObject["team"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content

    // ── a chat itself (web/src/api.ts → rename; chats made here, by their key) ──

    /** Sends to a chat by its key (one made here, made by its station or not): it waits in the chat until it can go. */
    suspend fun sendIn(session: String, text: String, attachments: List<Attachment> = emptyList(), quotes: List<Quote> = emptyList()) {
        op("chat.send") {
            put("session", session); put("text", text)
            put("attachments", StillFailJson.encodeToJsonElement(ListSerializer(Attachment.serializer()), attachments))
            put("quotes", StillFailJson.encodeToJsonElement(ListSerializer(Quote.serializer()), quotes))
            put("client", SENT_FROM)
        }
    }
    /** A failed message of such a chat, by its key: sent again, or dropped. */
    suspend fun retryIn(session: String, id: String) { op("chat.retry") { put("session", session); put("id", id) } }
    suspend fun discardIn(session: String, id: String) { op("chat.discard") { put("session", session); put("id", id) } }
    /** A chat named by hand; an empty name: named by its first message again. */
    suspend fun rename(thread: Long?, session: String, title: String) {
        op("chat.rename") { put("session", session); if (thread != null) put("thread", thread); put("title", title) }
    }
}

/** A session the station's machine kept (its own Claude Code or Codex, in a terminal); `session`: the chat going on with it. */
@kotlinx.serialization.Serializable
data class MachineSession(
    val runtime: String,
    val id: String,
    val cwd: String,
    val title: String? = null,
    val first: String? = null,
    val model: String? = null,
    val updatedAt: Long,
    val session: String? = null,
)

/** Something said in one of them: by the person, else by its agent; when, in ms. */
@kotlinx.serialization.Serializable
data class MachineSaid(val person: Boolean, val text: String, val at: Long? = null)

/** An item of a station's archive (`chats.archived`), as the station sends it (not in client/shapes yet). */
@kotlinx.serialization.Serializable
data class ArchivedChat(
    val id: String,
    val session: String,
    val thread: Long? = null,
    val title: String,
    val last: ArchivedLast? = null,
    val lastActiveAt: Long,
    val archived: ArchivedMark? = null,
)

@kotlinx.serialization.Serializable
data class ArchivedLast(val text: String? = null)

/** When it was archived, by a person (`manual`) or the station for idling (`auto`); `alone`: its agents still at work elsewhere. */
@kotlinx.serialization.Serializable
data class ArchivedMark(val at: Long, val by: String, val alone: Boolean = false)

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
    /** What an invitation link leads to, for the account looking: the workspace, the role, who invited, whose email it is for. */
    suspend fun previewInvitation(token: String): InvitationPreview =
        decode(InvitationPreview.serializer(), op("invitation.preview") { put("token", token) })
    /** Accepts an invitation by its link's token; answers the workspace joined. */
    suspend fun acceptInvitationToken(token: String): String = op("invitation.accept") { put("token", token) }.jsonObject["id"]!!.jsonPrimitive.content
}

@kotlinx.serialization.Serializable
data class InvitationPreview(val workspace: String, val name: String, val role: String = "member", val inviter: String = "", val email: String? = null)

class Enrollment(val install: String, val command: String)

/** The permission groups a new Slack app is made with (web/src/pages/SlackApp.tsx → GROUPS), all on. */
private val SLACK_GROUPS = listOf("base", "public", "dm", "customize", "files", "reactions", "channels", "people", "extras", "canvases", "lists", "topics", "usergroups", "search", "connect", "more")

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
